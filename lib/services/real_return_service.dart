import '../models/asset.dart';
import 'history_service.dart';
import 'inflation_service.dart';
import 'period_summary_service.dart';

/// Yıllık reel getiri — "enflasyonun kaç puan önündeyim" sorusunun
/// **TEK** cevabı.
///
/// ## Neden bu dosya var (2026-09-16)
/// Aynı soru üç yüzeyde üç ayrı formülle cevaplanıyordu ve sayılar
/// tutmuyordu: ana ekran rozeti "5,7 puan önde", Performans kartı ve
/// paylaşım kartı "1,0 puan geride" diyordu. Enflasyon aynıydı; fark
/// NOMİNAL getirinin kaynağındaydı:
///   · ana ekran → `LeaderboardService.computeROI`: bugünkü pozisyonlar
///     12 ay boyunca aynen tutulmuş gibi SİMÜLE edilir, para giriş çıkışı
///     görülmez (yarış için doğru: herkes aynı pencerede ölçülür),
///   · Performans → `PeriodSummaryService.compute`: gerçek seri + nakit
///     akışı düzeltmesi, yani "gerçekte ne oldu",
///   · yıl sonu özeti → snapshot uçlarından portföy DEĞERİ değişimi, katkı
///     dahil.
/// Kullanıcının gözünde bunlar aynı etiketli tek bir sayı. Karar: alım
/// gücü sorusu için nominal getiri **her yerde** Performans'ın nakit akışı
/// düzeltmeli 1Y piyasa getirisidir (`PeriodSummary.getiriPct`). Yarış
/// sıralaması simülasyonda kalır — o başka bir soru ("kimin varlıkları
/// daha çok kazandı") ve enflasyonla karşılaştırılmıyor.
///
/// Servis ağa çıkar (fiyat serisi + TÜFE endeksi); saf hesap yine
/// `PeriodSummaryService` ve `InflationService`'te. Pencere sabit 365 gün:
/// TÜİK'in "yıllık enflasyon" diliyle örtüşür.
class RealReturnService {
  const RealReturnService._();

  /// Karşılaştırma penceresi (gün).
  static const periodDays = 365;

  /// Nakit akışı düzeltmeli son 12 ay piyasa getirisi (yüzde).
  ///
  /// Pencere TÜFE'nin penceresine HİZALIDIR: uçlar `InflationWindow`'dan
  /// gelir, bugünden geriye sayılmaz ([piyasaGetirisi] notuna bakın).
  /// Endeks yoksa karşılaştırılacak bir şey de yok — `null` döner.
  static Future<double?> yillikPiyasaGetirisi(
    List<Asset> assets, {
    DateTime? now,
  }) async {
    if (assets.isEmpty) return null;
    final w = await InflationService.instance.pencere(periodDays, now: now);
    if (w == null) return null;
    return piyasaGetirisi(assets, w);
  }

  /// Verilen TÜFE penceresinde nakit akışı düzeltmeli piyasa getirisi.
  ///
  /// **Pencere TÜFE'den gelir, bugünden değil (2026-09-16).** Ölçüldü:
  /// nominal `donemBaslangici(now, 12)` ile (2025-09-16 … 2026-09-16),
  /// TÜFE son açıklanmış aydan (2025-08-01 … 2026-08-01) hesaplanıyordu ve
  /// ikisi "nominal − TÜFE" diye çıkarılıyordu. 1Y'de ~1,5 ay kayma vardı;
  /// 1A'da pencereler hiç kesişmiyordu. Fark, ölçülmemiş bir aralığın
  /// getirisini içeriyordu.
  ///
  /// TÜFE ucu doğru olan taraf (TÜİK'in yıllık enflasyonu böyle kurulur ve
  /// kullanıcı rakamı oradan doğruluyor), bu yüzden hizalama nominal
  /// tarafta yapılır: seri [InflationWindow.seriBaslangici] →
  /// [InflationWindow.seriBitisi] arasında çekilir.
  ///
  /// `compute`'un `now`'ı da pencerenin BİTİŞİDİR: `pencere()` dönem
  /// başlangıcını `now`'dan türetiyor, bugünü geçirmek hizalamayı geri
  /// alırdı.
  ///
  /// Seri kurulamıyorsa ya da taban sıfırsa `null` — tahmin yürütülmez.
  static Future<double?> piyasaGetirisi(
    List<Asset> assets,
    InflationWindow w,
  ) async {
    if (assets.isEmpty) return null;
    final tier = ResolutionTierMeta.pickForSpan(
      w.seriBitisi.difference(w.seriBaslangici).inDays.toDouble(),
    );
    final bd = await HistoryService.instance
        .getPortfolioHistoryBreakdownAtResolution(
      assets: assets,
      from: w.seriBaslangici,
      to: w.seriBitisi,
      tier: tier,
    );
    return PeriodSummaryService.compute(
      period: SummaryPeriod.birYil,
      assets: assets,
      breakdown: bd,
      now: w.seriBitisi,
      pencereBaslangici: w.seriBaslangici,
    ).getiriPct;
  }

  /// Nominal + TÜFE çifti. Biri eksikse `null`: eksik veriyle rozet
  /// çizmek, çizmemekten kötü.
  ///
  /// Enflasyon ÖNCE sorulur: tablo boşsa (olağan başlangıç durumu) pahalı
  /// olan seri hesabına hiç girilmez.
  static Future<RealReturn?> yillik(List<Asset> assets, {DateTime? now}) async {
    if (assets.isEmpty) return null;
    final w = await InflationService.instance.pencere(periodDays, now: now);
    if (w == null) return null;
    // Nominal AYNI pencereden hesaplanır — iki ayrı çağrı iki ayrı pencere
    // demekti ve fark ölçülmemiş bir aralığı içeriyordu.
    final nominal = await piyasaGetirisi(assets, w);
    if (nominal == null) return null;
    return RealReturn(nominal: nominal, inflation: w.pct, pencere: w);
  }
}

/// Yıllık nominal getiri ve TÜFE; türevleri tek yerden.
class RealReturn {
  const RealReturn({
    required this.nominal,
    required this.inflation,
    required this.pencere,
  });

  final double nominal;
  final double inflation;

  /// İki sayının da ölçüldüğü ORTAK pencere. Rozet bunu tarih aralığı
  /// olarak yazabiliyor; kullanıcı "hangi tarihler arası" diye
  /// sorabilmeli.
  final InflationWindow pencere;

  /// Puan farkı (nominal − TÜFE) — gündelik dilin okuduğu sayı.
  double get puan => InflationService.spreadPoints(nominal, inflation);

  /// Bileşik reel getiri — matematiksel olarak doğru olan.
  double get reel => InflationService.realReturnPct(nominal, inflation);
}
