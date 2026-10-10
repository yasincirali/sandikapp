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
  });

  final String ad;
  final String sembol;

  /// Bugünkü lot.
  final double lot;

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
  });

  final String ad;
  final String sembol;
  final double lot;

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
  const TemettuTahmini({required this.satirlar, required this.aylik});

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
  for (final g in girdiler) {
    if (g.lot <= 0) continue;
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
    ));
  }
  satirlar.sort((a, b) => b.brutTry.compareTo(a.brutTry));
  return TemettuTahmini(satirlar: satirlar, aylik: aylik);
}
