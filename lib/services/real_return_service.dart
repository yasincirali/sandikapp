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
  /// Performans sekmesinin 1Y bloğuyla AYNI hesap: aynı pencere
  /// (`donemBaslangici(now, 12)`), aynı çözünürlük, aynı `compute`. Seri
  /// kurulamıyorsa ya da taban sıfırsa `null` — tahmin yürütülmez.
  static Future<double?> yillikPiyasaGetirisi(
    List<Asset> assets, {
    DateTime? now,
  }) async {
    if (assets.isEmpty) return null;
    final t = now ?? DateTime.now();
    final from = PeriodSummaryService.donemBaslangici(t, 12);
    final tier =
        ResolutionTierMeta.pickForSpan(SummaryPeriod.birYil.days.toDouble());
    final bd = await HistoryService.instance
        .getPortfolioHistoryBreakdownAtResolution(
      assets: assets,
      from: from,
      to: t,
      tier: tier,
    );
    return PeriodSummaryService.compute(
      period: SummaryPeriod.birYil,
      assets: assets,
      breakdown: bd,
      now: t,
    ).getiriPct;
  }

  /// Nominal + TÜFE çifti. Biri eksikse `null`: eksik veriyle rozet
  /// çizmek, çizmemekten kötü.
  ///
  /// Enflasyon ÖNCE sorulur: tablo boşsa (olağan başlangıç durumu) pahalı
  /// olan seri hesabına hiç girilmez.
  static Future<RealReturn?> yillik(List<Asset> assets, {DateTime? now}) async {
    if (assets.isEmpty) return null;
    final enflasyon = await InflationService.instance
        .inflationForPeriod(periodDays, now: now);
    if (enflasyon == null) return null;
    final nominal = await yillikPiyasaGetirisi(assets, now: now);
    if (nominal == null) return null;
    return RealReturn(nominal: nominal, inflation: enflasyon);
  }
}

/// Yıllık nominal getiri ve TÜFE; türevleri tek yerden.
class RealReturn {
  const RealReturn({required this.nominal, required this.inflation});

  final double nominal;
  final double inflation;

  /// Puan farkı (nominal − TÜFE) — gündelik dilin okuduğu sayı.
  double get puan => InflationService.spreadPoints(nominal, inflation);

  /// Bileşik reel getiri — matematiksel olarak doğru olan.
  double get reel => InflationService.realReturnPct(nominal, inflation);
}
