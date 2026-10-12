import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/seans_sikistirma.dart';

/// Seans boşlukları (yasin 2026-10-12): "Ok böyle yapalım" — ama takvim
/// varsayımı yok ("bazı varlıklar hafta sonu değerlenebiliyor") ve uydurma
/// nokta yok. X birimi burada varlık detayınınki gibi kesirli gün.
void main() {
  const saat = 1 / 24;
  const dakika = 1 / 1440;
  // 5 Eki 2026 Pazartesi 00:00 = x 0.
  final bas = DateTime(2026, 10, 5);
  DateTime an(double x) => bas.add(Duration(minutes: (x * 1440).round()));

  /// BIST: Pzt–Cum 10:00–18:00, [adimDk] dakikalık çubuk başları.
  List<double> bist({int gun = 5, int adimDk = 5, int hafta = 1}) => [
        for (var h = 0; h < hafta; h++)
          for (var g = 0; g < gun; g++)
            for (var dk = 600; dk < 1080; dk += adimDk)
              h * 7 + g + dk * dakika,
      ];

  test('kripto (7/24, boşluksuz) sıkıştırılmaz', () {
    final xs = [for (var i = 0; i < 7 * 288; i++) i * 5 * dakika];
    expect(SeansSikistirma.kur(xs, hizalama: saat, birGun: 1), isNull);
  });

  test('günlük ve haftalık çubuk sıkıştırılmaz (hafta sonu tek adım)', () {
    final gunluk = [
      for (var g = 0; g < 60; g++)
        if (g % 7 < 5) g.toDouble(),
    ];
    expect(SeansSikistirma.kur(gunluk, hizalama: saat, birGun: 1), isNull);
  });

  test('hafta sonu da kotasyonu olan varlıkta yalnız gerçek boşluk kesilir',
      () {
    // Altın gibi: 7 gün boyunca saatlik, yalnız Çarşamba 02:00–06:00 veri
    // yok. Hafta sonu KESİLMEZ; yalnız o 4 saatlik boşluk.
    final xs = [
      for (var i = 0; i < 7 * 24; i++)
        if (!(i >= 2 * 24 + 2 && i < 2 * 24 + 6)) i * saat,
    ];
    final s = SeansSikistirma.kur(xs, hizalama: saat, birGun: 1)!;
    expect(s.boslukSayisi, 1);
    // Cumartesi öğlen yalnız o boşluğun 4 saati kadar sola kayar.
    final cmt = 5 + 12 * saat;
    expect(cmt - s.ileri(cmt), closeTo(4 * saat, 1e-9));
  });

  test('BIST haftası: geceler ve hafta sonu tam saat kesilir', () {
    final xs = [...bist(hafta: 2)];
    final s = SeansSikistirma.kur(xs, hizalama: saat, birGun: 1)!;
    // 2 hafta × 5 gün → 9 boşluk (4 gece + hafta sonu + 4 gece).
    expect(s.boslukSayisi, 9);
    // Sıkışmış eksen: 10 seans × 8 sa + boşluk artıkları (her biri < 1 sa).
    final boy = s.ileri(xs.last) - s.ileri(xs.first);
    expect(boy, lessThan(10 * 8 * saat + 9 * saat));
    expect(boy, greaterThan(10 * 8 * saat - saat));
    // Kesilen hep tam saat: yuvarlak saat sıkışmış eksende de yuvarlak.
    for (final x in xs) {
      final kayma = (x - s.ileri(x)) / saat;
      expect(kayma, closeTo(kayma.roundToDouble(), 1e-6));
    }
  });

  test('ileri monoton, geri onun tersi (veri anlarında)', () {
    final xs = bist(hafta: 2, adimDk: 30);
    final s = SeansSikistirma.kur(xs, hizalama: saat, birGun: 1)!;
    var once = -double.infinity;
    for (var x = -0.5; x < 15; x += 7 * dakika) {
      final c = s.ileri(x);
      expect(c, greaterThanOrEqualTo(once - 1e-12));
      once = c;
    }
    for (final x in xs) {
      expect(s.geri(s.ileri(x)), closeTo(x, 1e-9));
    }
  });

  test('uydurma nokta yok: noktalar yalnız kayar, sıra ve sayı aynı', () {
    final xs = bist(adimDk: 30);
    final s = SeansSikistirma.kur(xs, hizalama: saat, birGun: 1)!;
    final c = xs.map(s.ileri).toList();
    expect(c.length, xs.length);
    for (var i = 1; i < c.length; i++) {
      expect(c[i], greaterThan(c[i - 1]));
    }
    // Seans içi aralık aynen korunur (30 dk).
    expect(c[1] - c[0], closeTo(30 * dakika, 1e-12));
  });

  test('eksen: seans başına tarih, sığarsa yuvarlak saat', () {
    final xs = bist(adimDk: 5);
    final s = SeansSikistirma.kur(xs, hizalama: saat, birGun: 1)!;
    final cMin = s.ileri(xs.first) - 0.05, cMax = s.ileri(xs.last) + 0.1;
    const adim = 60 * dakika;
    final y = s.eksenYazilari(
      cMin: cMin,
      cMax: cMax,
      adim: adim,
      taban: 0,
      eksenPx: 290,
      etiketPx: 44,
      an: an,
      birDakika: dakika,
    );
    final tarihler = [
      for (final e in y.entries)
        if (e.value) an(s.geri(e.key * adim)),
    ]..sort();
    expect(tarihler, isNotEmpty);
    for (final t in tarihler) {
      expect(t.hour, 10, reason: 'tarih seansın ilk saatinde: $t');
      expect(t.weekday, lessThanOrEqualTo(5));
    }
    // Yakınlaşınca (tek seans) saat yazıları da gelir.
    final z = s.eksenYazilari(
      cMin: s.ileri(2 + 600 * dakika) - 0.01,
      cMax: s.ileri(2 + 1075 * dakika),
      adim: 30 * dakika,
      taban: 0,
      eksenPx: 290,
      etiketPx: 44,
      an: an,
      birDakika: dakika,
    );
    final saatler = [
      for (final e in z.entries)
        if (!e.value) an(s.geri(e.key * 30 * dakika)),
    ];
    expect(saatler, isNotEmpty);
    for (final t in saatler) {
      expect(t.minute, 0);
      expect(t.hour, inInclusiveRange(10, 18));
    }
  });
}
