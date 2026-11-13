import 'package:flutter/foundation.dart';

import 'temettu_gecmisi.dart' show TemettuGecmisi, TemettuOlayi;

/// Önümüzdeki 12 ayın temettü tahmini (Premium, yasin 2026-10-10).
///
/// ## Neden
/// Temettü takvimi ve yakalama ücretsiz kalır (rakiplerde de ücretsiz);
/// para ödenen bir sonraki adım "önümüzdeki yıl ne kadar temettü gelir"
/// sorusu (getquin, Parqet ücretli). Araştırma: tmp/arastirma.
///
/// ## Tahmin kuralı — tek ve söylenen
/// Her BIST hissesi için son 12 ayda (Yahoo, gerçekleşmiş, BRÜT TL/pay)
/// dağıtılan temettü, BUGÜNKÜ lotunla aynı aylarda tekrarlanırsa ne olur.
/// Şirket kararı, bölünme, bedelsiz ya da yeni yıl beklentisi tahmin
/// EDİLMEZ — bunları bilmiyoruz ve uydurma sayı yasak (fiyat kaynağı
/// sözleşmesi madde 3). Ekran bu kuralı cümleyle söyler; sayı "tahmini"
/// etiketini taşır (masraf kartındaki tahmini kalemle aynı ilke: gerçek
/// veri × kullanıcının kendi pozisyonu).
///
/// Net, yalnız stopaj oranı biliniyorsa (`TemettuGecmisi.oneriTutari`);
/// bilinmiyorsa brüt kalır. Yalnız TL kote BIST hissesi
/// (`FiyatKaynagi.temettuSembolu`): ABD temettüsü dolar ve ödeme günü kuru
/// ister, bilinmeyen kurla tutar üretilmez.
///
/// Saf: ağ yok. Ağ `TemettuGecmisiService.olaylariCek`, sağlayıcı
/// `temettu_tahmini_provider.dart`.

@immutable
class TahminGirdisi {
  const TahminGirdisi({
    required this.ad,
    required this.sembol,
    required this.lot,
    required this.olaylar,
    this.maliyet,
    this.kaydedilenNet = 0,
  });

  final String ad;
  final String sembol;

  /// Bugünkü lot.
  final double lot;

  /// Bugünkü mülkiyetin toplam maliyeti (TL, komisyon dahil;
  /// `aktifLotlar` → `Position.totalCost`). `null`/0 = bilinmiyor; o satır
  /// maliyete göre verime girmez (2026-11-13).
  final double? maliyet;

  /// Son `TemettuGecmisi.pencereGun` günde bu pozisyon için deftere
  /// KAYDEDİLMİŞ net temettü (`TemettuGecmisi.kaydedilenToplam`). Tahminle
  /// kıyas satırının "geçen 12 ayda aldın" tutarı (2026-11-13).
  final double kaydedilenNet;

  /// Son 12 ayın gerçekleşmiş olayları (BRÜT TL/pay).
  final List<TemettuOlayi> olaylar;
}

@immutable
class TahminSatiri {
  const TahminSatiri({
    required this.ad,
    required this.sembol,
    required this.lot,
    required this.brutPay,
    required this.brutTry,
    required this.netTry,
    required this.aylar,
    this.hakGunleri = const [],
    this.maliyet,
  });

  /// Bugünkü mülkiyetin maliyeti; bilinmiyorsa `null` (bkz.
  /// `TahminGirdisi.maliyet`).
  final double? maliyet;

  final String ad;
  final String sembol;
  final double lot;

  /// Geçen yılın gerçekleşmiş hak günleri (TR takvimi, saatsiz). Ana
  /// sayfadaki "seni ilgilendiren günler" satırı yıl dönümünü söyler
  /// (`seni_ilgilendiren_gunler.dart`); tahminin kendisi yalnız ayı kullanır.
  final List<DateTime> hakGunleri;

  /// Son 12 ayda pay başına brüt.
  final double brutPay;
  final double brutTry;

  /// Stopaj oranı bilinmiyorsa `null`.
  final double? netTry;

  /// Beklenen ödeme ayları (1-12), geçen yılın hak ayları.
  final List<int> aylar;
}

@immutable
class TemettuTahmini {
  const TemettuTahmini({
    required this.satirlar,
    required this.aylik,
    this.alinanNet = 0,
  });

  /// Son 12 ayda deftere kaydedilmiş net temettü toplamı — bugünkü TL kote
  /// BIST pozisyonlarının hepsi, Yahoo'da olayı görünmeyenler dahil
  /// (kullanıcının kendi kaydı Yahoo'dan daha doğru tanıktır). 0 = kayıt yok.
  final double alinanNet;

  /// Brüt tutara göre büyükten küçüğe; temettü dağıtmamış varlık yok.
  final List<TahminSatiri> satirlar;

  /// Ay (1-12) → o ay beklenen BRÜT TL. 12 eleman, boş ay 0.
  final List<double> aylik;

  double get brutTry => satirlar.fold(0.0, (t, s) => t + s.brutTry);

  /// Herhangi bir satırın neti bilinmiyorsa `null`.
  double? get netTry {
    double t = 0;
    for (final s in satirlar) {
      if (s.netTry == null) return null;
      t += s.netTry!;
    }
    return t;
  }

  bool get bos => satirlar.isEmpty;

  /// Ekranın büyük sayısı: net biliniyorsa net, değilse brüt.
  double get yillikBeklenen => netTry ?? brutTry;

  /// "Ayda ortalama" (2026-11-13): yıllık beklenen ÷ 12. Ödeme aylarının
  /// dağılımı çubuklarda; bu sayı bütçe dilinde "ayda ne eder" sorusunu
  /// cevaplar, belirli bir ayın ödemesi DEĞİLDİR.
  double get aylikOrtalama => yillikBeklenen / 12;

  /// Maliyetine göre beklenen yıllık verim (%), 2026-11-13.
  ///
  /// Varlık sayfasındaki verimle (`TemettuGecmisi.maliyeteGoreVerim`) aynı
  /// payda: bugünkü mülkiyetin maliyeti. Pay ise GEÇMİŞ kayıt değil bu
  /// ekranın tahmini (net ya da brüt — büyük sayıyla aynı). Yalnız maliyeti
  /// bilinen temettü dağıtan satırlar sayılır, pay da payda da onlardan:
  /// maliyeti bilinmeyen satırın tahmini paya girip paydaya girmeseydi verim
  /// şişerdi. Hiçbirinin maliyeti bilinmiyorsa `null` → yüzde yazılmaz
  /// (uydurma sayı yok).
  double? get maliyeteGoreVerim {
    final netVar = netTry != null;
    var pay = 0.0;
    var payda = 0.0;
    for (final s in satirlar) {
      final m = s.maliyet;
      if (m == null || !m.isFinite || m <= 0) continue;
      pay += netVar ? s.netTry! : s.brutTry;
      payda += m;
    }
    if (payda <= 0) return null;
    return pay / payda * 100;
  }

  /// Geçen 12 ayda kaydedilen net; kayıt yoksa `null` → kıyas satırı yok.
  double? get gecenYilAlinan => alinanNet > 0 ? alinanNet : null;

  /// Tahminin geçen yıl alınana göre farkı (%): (tahmin − alınan) ÷ alınan.
  ///
  /// Yalnız NET tahminle: defter kaydı net (kullanıcının eline geçen);
  /// stopaj oranı bilinmeyip tahmin brüt kalınca kıyas brüt ile neti
  /// karıştırır ve stopaj kadar sahte "artış" gösterirdi. O durumda `null`:
  /// tutar satırı yine yazılır, yüzde yazılmaz.
  double? get tahminFarkiYuzde {
    final alinan = gecenYilAlinan;
    final net = netTry;
    if (alinan == null || net == null) return null;
    return (net - alinan) / alinan * 100;
  }
}

/// [simdi]'den geriye 12 ayın olaylarını [girdiler]'in bugünkü lotuyla
/// tekrarlar. [stopaj] Remote Config `temettu_stopaj_orani` (`null` =
/// bilinmiyor).
TemettuTahmini temettuTahmini(
  List<TahminGirdisi> girdiler, {
  required double? stopaj,
  required DateTime simdi,
}) {
  final esik = simdi.subtract(const Duration(days: TemettuGecmisi.pencereGun));
  final aylik = List<double>.filled(12, 0);
  final satirlar = <TahminSatiri>[];
  var alinan = 0.0;
  for (final g in girdiler) {
    if (g.lot <= 0) continue;
    if (g.kaydedilenNet.isFinite && g.kaydedilenNet > 0) {
      alinan += g.kaydedilenNet;
    }
    final olaylar = [
      for (final o in g.olaylar)
        if (o.hakTarihi.isAfter(esik) && o.tutarPay > 0) o
    ];
    if (olaylar.isEmpty) continue;
    final brutPay = olaylar.fold(0.0, (t, o) => t + o.tutarPay);
    final brut = brutPay * g.lot;
    for (final o in olaylar) {
      aylik[o.hakTarihi.month - 1] += o.tutarPay * g.lot;
    }
    satirlar.add(TahminSatiri(
      ad: g.ad,
      sembol: g.sembol,
      lot: g.lot,
      brutPay: brutPay,
      brutTry: brut,
      netTry: TemettuGecmisi.oneriTutari(brut, stopaj).tutar,
      aylar: {for (final o in olaylar) o.hakTarihi.month}.toList()..sort(),
      hakGunleri: [for (final o in olaylar) o.hakTarihi],
      maliyet: g.maliyet,
    ));
  }
  satirlar.sort((a, b) => b.brutTry.compareTo(a.brutTry));
  return TemettuTahmini(satirlar: satirlar, aylik: aylik, alinanNet: alinan);
}

/// Kilitli temettü tahmini kartının kişisel satırı (2026-11-12, Ar-Ge
/// 12 Kas #3): portföyündeki hangi BIST hisseleri son 12 ayda temettü
/// dağıttı. TUTAR YOK: tutar kilitli içeriğin kendisidir; satır yalnız
/// "bu ekran benim için dolu mu" sorusunu kendi defterinle cevaplar.
/// Hiçbiri dağıtmadıysa bunu da söyler (satış yerine dürüstlük: açınca
/// boş durum görecek kullanıcıya "dolu" izlenimi verilmez).
@immutable
class TemettuKancasi {
  const TemettuKancasi(this.kodlar);

  /// Son 12 ayda temettü dağıtan hisselerin kısa kodları, alfabetik.
  /// Sıra tutara göre DEĞİL: tutar sırası kilitli bilgiyi sızdırırdı.
  final List<String> kodlar;

  bool get bos => kodlar.isEmpty;
}

/// [girdiler]: (kısa kod, olaylar) — olaylar `null` ise o sembol
/// okunamadı. Tek bir okuma düşerse `null` döner ve satır hiç çizilmez:
/// eksik okumayla "3 hisse dağıttı" ya da "dağıtan yok" demek uydurma
/// olurdu. Pencere ve olay eşiği [temettuTahmini] ile aynı (son
/// `TemettuGecmisi.pencereGun` gün, pay başına > 0), iki yüzey aynı
/// hisseleri sayar.
TemettuKancasi? temettuKancasi(
  List<(String, List<TemettuOlayi>?)> girdiler, {
  required DateTime simdi,
}) {
  final esik = simdi.subtract(const Duration(days: TemettuGecmisi.pencereGun));
  final kodlar = <String>{};
  for (final (kod, olaylar) in girdiler) {
    if (olaylar == null) return null;
    if (olaylar.any((o) => o.hakTarihi.isAfter(esik) && o.tutarPay > 0)) {
      kodlar.add(kod);
    }
  }
  return TemettuKancasi(kodlar.toList()..sort());
}
