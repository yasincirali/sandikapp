import 'package:flutter/foundation.dart';

import 'fon_dagilimi.dart';
import 'zirve_kiyas.dart';

/// Zirvedeki bir portföyün fonları ve BES'i açılınca gerçekte neye
/// yatırım yaptığı (yasin 2026-10-20: "fonların hisseleri, kriptonun,
/// dövizin ve beste de fonların bilgileri verilmeli, böylece tümden bir
/// portföyün kazandırması için nelere yatırım yaptığı anlaşılabilir").
///
/// Portföy X-Ray'in (`portfoy_xray.dart`) Zirve eşi. Fark: girdi TL değil,
/// sunucunun anonim YÜZDELERİ (`allocation_pct`, `fon_detay`,
/// `varlik_detay`); çıktı da toplam portföyün yüzdesi. Kova kuralı aynı:
///   · doğrudan tutulan tür tek kovaya (altın → kıymetli maden, eurobond →
///     döviz/dış borçlanma…),
///   · fon ve BES kodu → pay × (TEFAS kova yüzdesi / 100).
///
/// ## Uydurma yok
/// İçeriği bilinmeyen pay (TEFAS'ta dağılımı olmayan fon, %1 altı fonların
/// "diğer" toplamı, vitrinde gizli `?n` kod, tür payının koda bölünmemiş
/// kalanı, kaynak toplamı 100'ün altındaki fark) hiçbir kovaya dağıtılmaz:
/// [bilinmeyen] olarak görünür kalır (X-Ray'in "yeniden normalize edilmez"
/// kuralı).
///
/// ## Hisse: BIST mi yurt dışı mı
/// Sunucu sembolü `.IS` ile biterse BIST, açık başka bir sembolse (AAPL)
/// yurt dışı. Sembolü olmayan hisse payı ("diğer", gizli kod, kalan) BIST
/// sayılır: uygulamadaki hisselerin varsayılanı BIST'tir ve iki kova da
/// "hisse"dir — yanlışlık olsa bile sınıf (hisse) doğru kalır.
///
/// Saf: ağ yok. Veri `zirve_icerik_provider.dart`, çizim
/// `zirve_icerik_karti.dart`.

/// Kaynak anahtarı: doğrudan tutulan pay (fon kodu değil).
const zirveDogrudan = '·DOGRUDAN';

/// Doğrudan tutulan dövizin para birimi kaynağı: `KUR:USD`, `KUR:EUR`
/// (yasin 2026-10-20: "döviz katmanının ne kadarı dolar ne kadarı euro").
/// Ön ek fon koduyla karışmasın diye; ekranda yalnız kod yazar.
const zirveKurOneki = 'KUR:';

/// Kaynak anahtarının para birimi kodu; kur kaynağı değilse null.
String? zirveKurKodu(String kaynak) => kaynak.startsWith(zirveKurOneki)
    ? kaynak.substring(zirveKurOneki.length)
    : null;

final _kurSembolu = RegExp(r'^([A-Z]{3})TRY=X$');

@immutable
class ZirveIcerik {
  const ZirveIcerik({
    required this.kovalar,
    required this.kaynaklar,
    required this.bilinmeyen,
    required this.fonPayi,
    required this.tarih,
  });

  /// Kova → toplam portföyün %'si.
  final Map<XrayKova, double> kovalar;

  /// Kova → kaynak (fon/BES kodu ya da [zirveDogrudan]) → %.
  final Map<XrayKova, Map<String, double>> kaynaklar;

  /// İçeriği bilinmeyen fon/BES payı (%).
  final double bilinmeyen;

  /// Fon + BES türlerinin toplam payı (%); 0 ise açılacak bir şey yok.
  final double fonPayi;

  /// Kullanılan en yeni TEFAS dağılım günü; hiçbir fon açılamadıysa null.
  final DateTime? tarih;

  bool get acilacakVar => fonPayi > 0;

  /// En az bir fon gerçekten açıldı mı.
  bool get acildi => tarih != null;

  /// Kovalar büyükten küçüğe (eşitlikte enum sırası). Negatif (borçlanma,
  /// repo) en sonda.
  List<MapEntry<XrayKova, double>> get sirali =>
      kovalar.entries.where((e) => e.value.abs() >= 0.05).toList()
        ..sort((a, b) {
          final f = b.value.compareTo(a.value);
          return f != 0 ? f : a.key.index.compareTo(b.key.index);
        });

  /// Bir kovanın kaynakları büyükten küçüğe; doğrudan pay (para birimine
  /// ayrılmışsa birimler) önce gelir, fonlar sonra.
  List<MapEntry<String, double>> kaynaklariSirali(XrayKova k) =>
      (kaynaklar[k] ?? const {})
          .entries
          .where((e) => e.value.abs() >= 0.05)
          .toList()
        ..sort((a, b) {
          final ad = _dogrudanMi(a.key), bd = _dogrudanMi(b.key);
          if (ad != bd) return ad ? -1 : 1;
          final f = b.value.compareTo(a.value);
          return f != 0 ? f : a.key.compareTo(b.key);
        });

  static bool _dogrudanMi(String k) =>
      k == zirveDogrudan || k.startsWith(zirveKurOneki);

  /// Hisse kovalarının toplamı ve bunun fonlardan gelen kısmı — özet
  /// cümlesi "payının %X'i hissede, %Y'si fonların içinden" için.
  ({double toplam, double fonlardan}) hisse() {
    var t = 0.0, f = 0.0;
    for (final k in const [XrayKova.bistHisse, XrayKova.yabanciHisse]) {
      t += kovalar[k] ?? 0;
      for (final e in (kaynaklar[k] ?? const <String, double>{}).entries) {
        if (!_dogrudanMi(e.key)) f += e.value;
      }
    }
    return (toplam: t, fonlardan: f);
  }
}

/// Fon ve BES kodları (açılabilecek olanlar): "diğer" ve gizli `?n` hariç,
/// sıralı. Sağlayıcı bunları TEFAS dağılımı için ister.
List<String> zirveFonKodlari(
    Map<String, double> fonDetay, Map<String, Map<String, double>> varlik) {
  bool acik(String k) => k != ZirveKiyas.fonDiger && !ZirveKiyas.kilitliMi(k);
  return {
    for (final k in fonDetay.keys)
      if (acik(k)) k,
    for (final k in (varlik['bes'] ?? const <String, double>{}).keys)
      if (acik(k)) k,
  }.toList()
    ..sort();
}

XrayKova? _dogrudanKova(String tur) => switch (tur) {
      'altin' => XrayKova.kiymetliMaden,
      'doviz' => XrayKova.doviz,
      'kripto' => XrayKova.kripto,
      'mevduat' => XrayKova.mevduat,
      'eurobond' => XrayKova.dovizBorclanma,
      'emtia' => XrayKova.emtia,
      'diger' => XrayKova.diger,
      _ => null,
    };

ZirveIcerik zirveIcerigi({
  required Map<String, double> pay,
  required Map<String, double> fonDetay,
  required Map<String, Map<String, double>> varlikDetay,
  required Map<String, FonDagilimi> dagilimlar,
}) {
  final kovalar = <XrayKova, double>{};
  final kaynaklar = <XrayKova, Map<String, double>>{};
  var bilinmeyen = 0.0;
  DateTime? tarih;

  void ekle(XrayKova k, String kaynak, double v) {
    if (!v.isFinite || v == 0) return;
    kovalar[k] = (kovalar[k] ?? 0) + v;
    final m = kaynaklar.putIfAbsent(k, () => <String, double>{});
    m[kaynak] = (m[kaynak] ?? 0) + v;
  }

  // Bir fon/BES kalemini aç: dağılım varsa kovalara, yoksa bilinmeyen.
  void ac(String kod, double v) {
    if (v <= 0) return;
    final d = (kod == ZirveKiyas.fonDiger || ZirveKiyas.kilitliMi(kod))
        ? null
        : dagilimlar[kod];
    if (d == null) {
      bilinmeyen += v;
      return;
    }
    var kapsanan = 0.0;
    kovalaraTopla(d.dagilim).forEach((k, yuzde) {
      ekle(k, kod, v * yuzde / 100);
      kapsanan += yuzde;
    });
    // Kaynak toplamı 100'ün altındaysa fark bilinmeyen; üstündeyse kaynak
    // söylendiği gibi kalır (X-Ray kuralı).
    if (kapsanan < 100) bilinmeyen += v * (100 - kapsanan) / 100;
    if (tarih == null || d.tarih.isAfter(tarih!)) tarih = d.tarih;
  }

  // Tür payının koda bölünmüş toplamı; kalan bilinmeyen (fon/BES) ya da
  // türün kendi kovası (diğerleri).
  double kalan(String tur, Map<String, double>? kalemler) {
    final t = pay[tur] ?? 0;
    final s = (kalemler ?? const <String, double>{})
        .values
        .fold(0.0, (a, b) => a + b);
    final k = t - s;
    // Sunucu tek ondalığa yuvarlar: kuruşluk fark gürültüdür.
    return k > 0.05 ? k : 0;
  }

  for (final e in pay.entries) {
    final tur = e.key;
    final v = e.value;
    if (v <= 0) continue;
    switch (tur) {
      case 'fon':
        fonDetay.forEach(ac);
        bilinmeyen += kalan('fon', fonDetay);
      case 'bes':
        final b = varlikDetay['bes'];
        b?.forEach(ac);
        bilinmeyen += kalan('bes', b);
      case 'hisse':
        final h = varlikDetay['hisse'] ?? const <String, double>{};
        h.forEach((sembol, p) {
          final yurtDisi = sembol != ZirveKiyas.fonDiger &&
              !ZirveKiyas.kilitliMi(sembol) &&
              !sembol.endsWith('.IS');
          ekle(yurtDisi ? XrayKova.yabanciHisse : XrayKova.bistHisse,
              zirveDogrudan, p);
        });
        ekle(XrayKova.bistHisse, zirveDogrudan, kalan('hisse', h));
      case 'doviz':
        // Para birimine ayrılır: sunucu sembolü `USDTRY=X` → USD. Sembolü
        // açık olmayan ("diğer", gizli kod, kalan) "doğrudan" kalır —
        // birimi bilinmeyen dövize birim uydurulmaz. Fonların içindeki
        // döviz (eurobond, döviz mevduatı) TEFAS'ta para birimine ayrılmaz;
        // o pay kendi sınıfında (döviz/dış borçlanma, mevduat) kalır.
        final d = varlikDetay['doviz'] ?? const <String, double>{};
        d.forEach((sembol, p) {
          final kur = _kurSembolu.firstMatch(sembol)?.group(1);
          ekle(XrayKova.doviz,
              kur == null ? zirveDogrudan : '$zirveKurOneki$kur', p);
        });
        ekle(XrayKova.doviz, zirveDogrudan, kalan('doviz', d));
      default:
        final k = _dogrudanKova(tur);
        if (k != null) ekle(k, zirveDogrudan, v);
    }
  }

  return ZirveIcerik(
    kovalar: kovalar,
    kaynaklar: kaynaklar,
    bilinmeyen: bilinmeyen,
    fonPayi: (pay['fon'] ?? 0) + (pay['bes'] ?? 0),
    tarih: tarih,
  );
}
