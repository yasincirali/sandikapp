import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import 'crash_reporter.dart';
import 'history_service.dart';
import 'seri_disk_depo.dart';

/// Performans sekmesinin son hesaplanmış portföy serisi — diskte, lot
/// defterinin parmak iziyle (önce-eski-seri, Ar-Ge 2026-10-25 §4; yasin
/// onayı 2026-10-25).
///
/// ## Neden
/// Varlık sayfası ve varlık detayı 2026-10-24'ten beri diskteki son seriyle
/// soluk açılıyor (`HistoryService.eldekiSeriyle`). Performans sekmesi o yola
/// bilerek girmedi: portföy serisi LOT DEFTERİNE bağlı ve eski seri ile yeni
/// lotlar karışabilirdi ("yanlış bir toplam görmek çok rahatsız eder",
/// müşteri raporu 2026-10-25 §4). Bu depo karışmayı kökten keser: seri,
/// hesaplandığı defterin parmak iziyle ([imza]) yazılır ve yalnız AYNI
/// parmak izinde okunur. Lot eklendi, satıldı, silindi ya da düzenlendiyse
/// iz değişir, kayıt hiç dönmez ve ekran bugünkü iskeletle açılır.
///
/// ## Neden bileşenlerden yeniden hesap değil
/// Eldeki-kip (`eldekiSeriyle`) sembol serilerinden portföyü yeniden
/// kurabilirdi; ama çok varlıklı portföyde bir bileşenin diskten düşmesi
/// (80 dosya sınırı) bütün yolu kapatır ve hesap motorunun en riskli yeri
/// (portföy toplamı) ikinci bir kipte koşardı. Burada motor hiç değişmez:
/// ekranın son ÇİZDİĞİ seri olduğu gibi saklanır.
///
/// ## Uydurma sayı yok
/// Gösterilen her nokta bu cihazda bu defterle ölçülmüş eski bir hesaptır;
/// soluk çizilir, taze hesap gelince yerine geçer. Sıfır ya da sonlu olmayan
/// değer içeren seri hiç yazılmaz (depo okurken sıfırı atar; atılmış nokta
/// çizilen seriden farklı bir çizgi olurdu).
///
/// ## Sınırlar
/// · Tazelik: günlük/haftalık ≤ 7 gün, saatlik (1H) ≤ 1 gün
///   (`HistoryService.bayatAzamiYas` / `bayatSaatlikAzamiYas`); gün içi
///   dönem bu yola hiç girmez.
/// · Ayrı klasör (`performans_onbellek`), en çok [azamiDosya] dosya — bir
///   dosya = bir kapsam × dönem; sembol serilerini budamaz.
/// · Kullanıcıya ait: çıkışta [temizle] (Çerez ve Depolama metni §2.3 "çıkış
///   yaptığınızda hesabınıza ait önbellek silinir"). Metin "grafik serisi
///   önbelleği"ni zaten sayıyor; yeni veri türü, amaç ya da alıcı yok.
/// · Demo modunda okunmaz, yazılmaz.
/// · Okunamayan/bozuk/biçimi değişmiş kayıt yok sayılır (kullanıcı tercihi
///   değil, önbellek).
abstract final class PortfoySeriDepo {
  /// `main()` gerçek depoyu bağlar; testler geçici klasör verir. `null`
  /// iken yol tümüyle kapalı (eski davranış).
  static SeriDiskDepo? kaliciDepo;

  static const klasor = 'performans_onbellek';

  /// 7 dönem × birkaç kapsam (Ben, ortaklar, tür süzgeci) yeter.
  static const azamiDosya = 24;

  static SeriDiskDepo varsayilanDepo() =>
      SeriDiskDepo(klasor: klasor, azamiDosya: azamiDosya);

  /// Lot defterinin parmak izi.
  ///
  /// [hamDefter] kapsamın HAM defteri — kapanmış pozisyonun alım/satım
  /// satırları, silme kaydı ve yumuşak silinmiş lotlar dahil (CLAUDE.md
  /// "Kapanmış pozisyon": geçmişi soran yer ham defteri okur). [seriGirdisi]
  /// motora giden liste (süzgeç, `seriyeGirer`, simülasyon sonrası); ikisi
  /// birlikte hem defter değişikliğini hem kapsam/süzgeç kararını yakalar.
  ///
  /// Alanlar seriyi değiştirebilen HER şey: kimlik, tür, sembol, miktar,
  /// tarih, alış/satış fiyatı ve kuru, para birimi, birim, alt kategori,
  /// elle fiyat, silinme, portföy. `currentPrice`/`lastUpdated` YOK: her
  /// fiyat turunda değişir ve iz hiç tutmazdı; canlı fiyatı taze hesap ve
  /// grafiğin canlı ucu taşır.
  static String imza(List<Asset> hamDefter, List<Asset> seriGirdisi) {
    String satir(Asset a) => [
          a.id,
          a.kind.name,
          a.refAssetId ?? '',
          a.ticker,
          a.type.name,
          a.subCategory ?? '',
          a.unitType,
          a.quantity,
          a.purchasePrice,
          a.sellPrice ?? '',
          a.currency,
          a.purchaseFxRate,
          a.sellFxRate ?? '',
          a.commission,
          a.dividendAmount,
          a.addedDate.millisecondsSinceEpoch,
          a.isManualPrice ? 1 : 0,
          a.deletedAt?.millisecondsSinceEpoch ?? '',
          a.portfoyId ?? '',
        ].join('~');
    final metin = [
      for (final a in hamDefter) satir(a),
      '#',
      for (final a in seriGirdisi) satir(a),
    ].join('\n');
    return sha1.convert(utf8.encode(metin)).toString();
  }

  /// Defter bu yola girebilir mi? Sözleşmeli lot (mevduat, BES) seriyi
  /// sözleşmenin faiz/vade koşullarından alır; o koşullar lot satırında
  /// değil, iz onları göremez — koşul düzenlenince eski seri doğru defter
  /// sanılırdı. O kapsamlar bugünkü davranışta kalır.
  static bool uygunMu(List<Asset> seriGirdisi) =>
      seriGirdisi.isNotEmpty && seriGirdisi.every((a) => a.sozlesmeId == null);

  /// Çözünürlüğe göre eski kopyanın en fazla yaşı.
  static Duration azamiYas(ResolutionTier tier) =>
      tier == ResolutionTier.daily || tier == ResolutionTier.weekly
          ? HistoryService.bayatAzamiYas
          : HistoryService.bayatSaatlikAzamiYas;

  /// [anahtar] kapsamı (kullanıcı, kişi, portföy, tür, dönem, simülasyon)
  /// taşır; [imza] defteri. Dönen seri `[from, to]`'ya kırpılır (eski
  /// pencerenin taşan noktaları negatif X'e düşmesin); iki noktadan azsa
  /// `null`.
  static Future<({Map<int, double> seri, DateTime zaman})?> oku({
    required String anahtar,
    required String imza,
    required ResolutionTier tier,
    required DateTime from,
    required DateTime to,
    DateTime? simdi,
  }) async {
    final depo = kaliciDepo;
    if (depo == null || DemoModu.aktif) return null;
    try {
      final k = await depo.okuKayit(anahtar, imza: imza);
      if (k == null) return null;
      if ((simdi ?? DateTime.now()).difference(k.at) > azamiYas(tier)) {
        return null;
      }
      final f = from.millisecondsSinceEpoch;
      final t = to.millisecondsSinceEpoch;
      final seri = <int, double>{
        for (final p in k.noktalar)
          if (p.$1 >= f && p.$1 <= t) p.$1: p.$2,
      };
      return seri.length < 2 ? null : (seri: seri, zaman: k.at);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'PortfoySeriDepo.oku');
      return null;
    }
  }

  static Future<void> yaz({
    required String anahtar,
    required String imza,
    required Map<int, double> seri,
  }) async {
    final depo = kaliciDepo;
    if (depo == null || DemoModu.aktif || seri.length < 2) return;
    if (seri.values.any((v) => !(v > 0) || !v.isFinite)) return;
    final noktalar = [for (final e in seri.entries) (e.key, e.value)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    await depo.yaz(anahtar, noktalar, imza: imza);
  }

  /// Çıkışta / hesap kaldırılınca: kullanıcıya ait seri cihazda kalmaz.
  static Future<void> temizle() async {
    await kaliciDepo?.temizle();
  }
}
