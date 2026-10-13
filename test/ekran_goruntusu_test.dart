import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekran_goruntusu.dart';

/// Ekran görüntüsünden adet ve ortalama maliyet (bayrak
/// `ekran_goruntusu_maliyet`, 2026-10-13). Hücreler yerel OCR'ın verdiği
/// biçimde elle kurulur (piksel, sol üst başlangıç, satır 40 px yüksek).
/// Kurum adı/verisi uydurmadır; düzenler gerçek uygulama kalıplarını taklit
/// eder: liste satırı, kart, başlıklı tablo.
OcrHucre h(String t, double x, double y, {double w = 200}) =>
    OcrHucre(t, x, y, x + w, y + 40);

const _fonlar = [
  (kod: 'YAY', unvan: 'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU (HİSSE SENEDİ YOĞUN FON)'),
  (kod: 'IIH', unvan: 'İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON'),
  (kod: 'IPJ', unvan: 'İŞ PORTFÖY ELEKTRİKLİ ARAÇLAR KARMA FON'),
  (kod: 'MAC', unvan: 'MARMARA CAPITAL PORTFÖY HİSSE SENEDİ (TL) FONU (HİSSE SENEDİ YOĞUN FON)'),
];

void main() {
  group('liste satırı (etiket ve sayı aynı hücrede)', () {
    test('kod satırı + "100 Adet · Ort. 250,00"', () {
      final v = ekranGoruntusunuAnla([
        h('THYAO', 40, 100),
        h('312,40 ₺', 800, 100),
        h('Türk Hava Yolları', 40, 145),
        h('100 Adet · Ort. 250,00', 600, 145, w: 400),
        h('ASELS', 40, 260),
        h('45,10 ₺', 800, 260),
        h('Aselsan', 40, 305),
        h('1.250 Adet · Ort. 38,75', 600, 305, w: 400),
      ]);
      expect(v.map((x) => x.kod), ['THYAO', 'ASELS']);
      expect(v[0].adet, 100);
      expect(v[0].maliyet, 250);
      expect(v[1].adet, 1250);
      expect(v[1].maliyet, 38.75);
    });

    test('etiketsiz güncel fiyat maliyet sayılmaz', () {
      final v = ekranGoruntusunuAnla([
        h('THYAO', 40, 100),
        h('312,40 ₺', 800, 100),
        h('Adet: 100', 40, 145),
      ]);
      expect(v.single.adet, 100);
      expect(v.single.maliyet, isNull);
    });

    test('yüzde, tarih ve saat değer sayılmaz', () {
      final v = ekranGoruntusunuAnla([
        h('THYAO', 40, 100),
        h('Ort. Maliyet %12,5', 40, 145, w: 400),
        h('Alış 13.10.2026 14:32', 40, 190, w: 400),
        h('Lot 50', 40, 235),
      ]);
      expect(v.single.maliyet, isNull);
      expect(v.single.adet, 50);
    });
  });

  group('kart (etiket üstte, değer altında)', () {
    test('iki satıra taşan fon adı + Pay Adedi / Ort. Maliyet', () {
      final v = ekranGoruntusunuAnla([
        h('İŞ PORTFÖY YARI İLETKEN', 40, 100, w: 600),
        h('TEKNOLOJİLERİ DEĞİŞKEN FON', 40, 145, w: 600),
        h('Pay Adedi', 40, 220),
        h('Ort. Maliyet', 600, 220),
        h('1.234,567', 40, 265),
        h('2,345678 TL', 600, 265),
        h('Güncel Değer', 40, 330),
        h('Kâr/Zarar', 600, 330),
        h('3.456,78 TL', 40, 375),
        h('+%12,30', 600, 375),
      ], fonlar: _fonlar);
      expect(v.single.kod, 'IIH');
      expect(v.single.adet, closeTo(1234.567, 1e-9));
      expect(v.single.maliyet, closeTo(2.345678, 1e-9));
    });

    test('kesik ad (…) unvanın önekiyse tanınır', () {
      final v = ekranGoruntusunuAnla([
        h('YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ…', 40, 100, w: 700),
        h('Adet', 40, 170),
        h('Ortalama Maliyet', 600, 170),
        h('29', 40, 215),
        h('1.739,18', 600, 215),
      ], fonlar: _fonlar);
      expect(v.single.kod, 'YAY');
      expect(v.single.adet, 29);
      expect(v.single.maliyet, 1739.18);
    });

    test('birden çok fona uyan ad tahminle eşlenmez', () {
      final v = ekranGoruntusunuAnla([
        h('İŞ PORTFÖY', 40, 100),
        h('Adet', 40, 170),
        h('10', 40, 215),
      ], fonlar: _fonlar);
      expect(v.single.kod, isNull);
      expect(v.single.ad, 'İŞ PORTFÖY');
      expect(ekranKanonikMetni(v), isEmpty);
    });

    test('"Maliyet" toplamsa değerden birime çevrilir', () {
      // 100 pay, güncel değer 3.000 (birim 30) → "Maliyet 2.500" toplamdır.
      final v = ekranGoruntusunuAnla([
        h('THYAO', 40, 100),
        h('Adet', 40, 170),
        h('Maliyet', 400, 170),
        h('Değer', 760, 170),
        h('100', 40, 215),
        h('2.500,00', 400, 215),
        h('3.000,00', 760, 215),
      ]);
      expect(v.single.maliyet, 25);
    });

    test('"Maliyet" birimse olduğu gibi kalır', () {
      final v = ekranGoruntusunuAnla([
        h('THYAO', 40, 100),
        h('Adet', 40, 170),
        h('Maliyet', 400, 170),
        h('Değer', 760, 170),
        h('100', 40, 215),
        h('25,00', 400, 215),
        h('3.000,00', 760, 215),
      ]);
      expect(v.single.maliyet, 25);
    });

    test('toplam maliyet adede bölünür', () {
      final v = ekranGoruntusunuAnla([
        h('ASELS', 40, 100),
        h('Lot', 40, 170),
        h('Toplam Maliyet', 400, 170),
        h('200', 40, 215),
        h('9.000,00 TL', 400, 215),
      ]);
      expect(v.single.maliyet, 45);
    });
  });

  group('tablo (başlık satırı + sütunlar)', () {
    test('başlıktaki sütunun altındaki değer', () {
      final v = ekranGoruntusunuAnla([
        h('Sembol', 40, 100, w: 120),
        h('Adet', 260, 100, w: 100),
        h('Ort. Maliyet', 420, 100, w: 180),
        h('Son Fiyat', 660, 100, w: 150),
        h('THYAO', 40, 160, w: 120),
        h('100', 300, 160, w: 60),
        h('250,00', 480, 160, w: 120),
        h('312,40', 690, 160, w: 120),
        h('MAC', 40, 220, w: 120),
        h('1.500', 280, 220, w: 80),
        h('8,123456', 460, 220, w: 140),
        h('9,50', 720, 220, w: 90),
      ], fonlar: _fonlar);
      expect(v.map((x) => (x.kod, x.adet, x.maliyet)), [
        ('THYAO', 100, 250),
        ('MAC', 1500, 8.123456),
      ]);
      expect(v[1].tur, 'Fon');
    });
  });

  test('OCR satırı kelime boşluğundan hücrelere bölünür', () {
    final hucreler = ocrSatirlarindanHucreler([
      OcrSatiri(h('THYAO 100 250,00', 40, 100, w: 700), [
        h('THYAO', 40, 100, w: 120),
        h('100', 300, 100, w: 60),
        h('250,00', 480, 100, w: 120),
      ]),
      OcrSatiri(h('Ort. Maliyet', 40, 160, w: 300), [
        h('Ort.', 40, 160, w: 60),
        h('Maliyet', 110, 160, w: 140),
      ]),
    ]);
    expect(hucreler.map((x) => x.metin), ['THYAO', '100', '250,00', 'Ort. Maliyet']);
  });

  test('OcrSatiri yerel kanal haritasından kurulur', () {
    final s = OcrSatiri.haritadan({
      't': 'THYAO',
      'l': 1, 'u': 2, 'r': 3, 'b': 4,
      'k': [
        {'t': 'THYAO', 'l': 1, 'u': 2, 'r': 3, 'b': 4},
      ],
    });
    expect(s.kutu.metin, 'THYAO');
    expect(s.kelimeler.single.sag, 3);
  });

  test('birden çok görüntü: aynı kodun eksiği tamamlanır', () {
    final b = ekranVarliklariniBirlestir([
      [const EkranVarligi(kod: 'THYAO', tur: 'Hisse', adet: 100)],
      [const EkranVarligi(kod: 'THYAO', tur: 'Hisse', maliyet: 250)],
    ]);
    expect(b.single.adet, 100);
    expect(b.single.maliyet, 250);
  });

  group('ekstreye uygulama', () {
    test('tek alış satırının fiyatı maliyet olur, tutar boşalır', () {
      const metin = 'sembol\tadet\tfiyat\ttutar\ttarih\ttur\n'
          'YAY\t29\t1800\t52200\t31.05.2026\tFon\n'
          'IIH\t10\t5\t50\t31.05.2026\tFon';
      final r = maliyetleriUygula(metin, const [
        EkranVarligi(kod: 'YAY', tur: 'Fon', maliyet: 1739.18),
        EkranVarligi(kod: 'THYAO', tur: 'Hisse', maliyet: 250),
      ]);
      expect(r.uygulanan, 1);
      expect(r.ekstredeYok, ['THYAO']);
      final satirlar = r.metin.split('\n');
      expect(satirlar[1], 'YAY\t29\t1739,18\t\t31.05.2026\tFon');
      expect(satirlar[2], 'IIH\t10\t5\t50\t31.05.2026\tFon');
      // Aynı ayrıştırıcıdan geçer: fiyat maliyet, adet ekstreden.
      final p = CsvImportService.parse(r.metin);
      expect(p.rows.first.price, 1739.18);
      expect(p.rows.first.quantity, 29);
    });

    test('hareketlerle bölünmüş ya da satışlı kod dokunulmaz', () {
      const metin = 'sembol\tadet\tfiyat\ttarih\tislem turu\n'
          'YAY\t20\t\t01.05.2026\tAlış\n'
          'YAY\t9\t1700\t10.05.2026\tAlış\n'
          'IPJ\t5\t\t01.05.2026\tAlış\n'
          'IPJ\t5\t3\t20.05.2026\tSatış';
      final r = maliyetleriUygula(metin, const [
        EkranVarligi(kod: 'YAY', tur: 'Fon', maliyet: 1739.18),
        EkranVarligi(kod: 'IPJ', tur: 'Fon', maliyet: 2),
      ]);
      expect(r.uygulanan, 0);
      expect(r.bolunmus, ['YAY', 'IPJ']);
      expect(r.metin, metin);
    });

    test('fiyat sütunu yoksa eklenir', () {
      const metin = 'sembol\tadet\ttarih\nTHYAO\t100\t31.05.2026';
      final r = maliyetleriUygula(
          metin, const [EkranVarligi(kod: 'THYAO', tur: 'Hisse', maliyet: 250)]);
      expect(r.metin, 'sembol\tadet\ttarih\tfiyat\nTHYAO\t100\t31.05.2026\t250');
    });
  });

  test('ekstre yokken kanonik metin aynı ayrıştırıcıdan geçer', () {
    final metin = ekranKanonikMetni(const [
      EkranVarligi(kod: 'THYAO', tur: 'Hisse', adet: 100, maliyet: 250),
      EkranVarligi(kod: 'MAC', tur: 'Fon', adet: 1500),
      EkranVarligi(kod: 'ASELS', tur: 'Hisse', maliyet: 40), // adet yok
    ]);
    final p = CsvImportService.parse(metin);
    expect(p.errors, isEmpty);
    expect(p.rows.length, 2);
    expect(p.rows[0].price, 250);
    expect(p.rows[1].price, 0);
  });
}
