import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/hareket_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Hesap hareketlerinden gerçek alış (2026-10-05). Düzen gerçek bir banka
/// varlık ekstresinin PDF'ten okunmuş hâli; değerler ve adlar sentetik.
void main() {
  const fonlar = EkstreTablosu(kaynak: 'PDF', satirlar: [
    ['', '', '', 'YATIRIM FONLARI', '', '', ''],
    ['Yatırım Fonu İsmi', 'Pay Adedi', 'Birim Fiyat', 'Bloke Adedi',
        'Para Birimi', 'Bakiye', 'Kullanılabilir Bakiye'],
    ['YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE', '30.00',
        '1800.0000', '', 'TL', '54,000.00', '54,000.00'],
    ['GARANTİ PORTFÖY ALTIN KATILIM FONU', '1,000.00', '3.0000', '', 'TL',
        '3,000.00', '3,000.00'],
    ['Deniz Portföy Para Piyasası (TL) Fonu', '100.00', '5.0000', '', 'TL',
        '500.00', '500.00'],
  ]);
  const hareket = EkstreTablosu(kaynak: 'PDF', satirlar: [
    ['', 'Hesap Numarası : 1111-2222-333 Vadesiz / TL', '', '', ''],
    ['İşlem Tarihi', 'Açıklama', 'Yatırılan Tutar', 'Çekilen Tutar', 'Bakiye'],
    ['', 'Önceki Aydan Devreden', '', '', '90,000.00 TL'],
    ['02/05/2026', 'AD SOYAD Banka: 0001 SN: 123456', '', '-500.00 TL',
        '89,500.00 TL'],
    // Bankanın gözünden "Müşteriye Fon Satış" = müşterinin ALIŞI; yön
    // kelimeden değil paranın çıkışından gelir.
    ['15/05/2026', 'TEFAS Müşteriye Fon Satış YAY 20,00x1.700,0000000', '',
        '-34,000.00 TL', '55,500.00 TL'],
    ['16/05/2026', 'TEFAS Müşteriye Fon Satış GOL 1.000,00x2,9000000', '',
        '-2,900.00 TL', '52,600.00 TL'],
    // Stopaj satırı kalıbı taşır ama tutar tutmaz → hareket değil.
    ['16/05/2026', 'Stopaj Vergisi FON ALIS FON5 1834X5,4803060', '',
        '-19.37 TL', '52,580.63 TL'],
    // Bankanın iç süpürme fonu: varlık tablosunda yok → hiçbir yere girmez.
    ['17/05/2026', 'FON ALIS FON5 1000X5,0000000(KAPTAN)', '5,000.00 TL', '',
        '57,580.63 TL'],
  ]);

  test('hareketler: kalıp + tutar doğrulaması, yön paranın işaretinden', () {
    final h = hareketleriBul([fonlar, hareket]);
    expect(h.map((x) => (x.kod, x.adet, x.fiyat, x.satis)), [
      ('YAY', 20.0, 1700.0, false),
      ('GOL', 1000.0, 2.9, false),
      ('FON5', 1000.0, 5.0, true),
    ]);
    expect(h.first.tarih, DateTime(2026, 5, 15));
  });

  test('ayrı Yatırılan sütunu, işaretsiz tutar: giriş = satış', () {
    const t = EkstreTablosu(kaynak: 'CSV', satirlar: [
      ['Tarih', 'Açıklama', 'Borç', 'Alacak'],
      ['01.06.2026', 'THYAO 10x300,00 hisse', '3.000,00', ''],
      ['02.06.2026', 'THYAO 5x320,00 hisse', '', '1.600,00'],
    ]);
    expect(hareketleriBul([t]).map((x) => (x.kod, x.satis)), [
      ('THYAO', false),
      ('THYAO', true),
    ]);
  });

  EkstreOkumaSonucu oku() =>
      ekstreyiAnla(EkstreBicimi.pdf, [fonlar, hareket],
              'Hesap Özeti Dönemi 01/05/2026 - 31/05/2026')
          .kodlarla(const [
        (
          kod: 'YAY',
          unvan: 'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU'
        ),
        (kod: 'GOL', unvan: 'GARANTİ PORTFÖY ALTIN KATILIM FONU'),
        (kod: 'DLY', unvan: 'DENİZ PORTFÖY PARA PİYASASI (TL) FONU'),
      ]);

  test('bayrak kapalı: çıktı birebir eski (ekstre günü, ekstre fiyatı)', () {
    final s = oku();
    expect(s.kanonikMetin(), s.kanonikMetin(hareketlerle: false));
    final r = CsvImportService.parse(s.kanonikMetin());
    expect(r.rows.map((x) => (x.ticker, x.quantity, x.price)), [
      ('TEFAS:YAY', 30.0, 1800.0),
      ('TEFAS:GOL', 1000.0, 3.0),
      ('TEFAS:DLY', 100.0, 5.0),
    ]);
  });

  test('hareketlerle: dönem içi alış gerçek tarih/fiyat, kalan ekstre günü',
      () {
    final s = oku();
    expect(s.hareketleIncelenen(), 2);
    final r = CsvImportService.parse(s.kanonikMetin(hareketlerle: true));
    expect(r.errors, isEmpty);
    expect(
        r.rows.map((x) => (x.ticker, x.quantity, x.price, x.addedDate)), [
      // 30 payın 20'si dönemde alındı; 10'u önceden vardı.
      ('TEFAS:YAY', 20.0, 1700.0, DateTime(2026, 5, 15)),
      ('TEFAS:YAY', 10.0, 1800.0, DateTime(2026, 5, 31)),
      ('TEFAS:GOL', 1000.0, 2.9, DateTime(2026, 5, 16)),
      // Hareketi olmayan fon değişmez.
      ('TEFAS:DLY', 100.0, 5.0, DateTime(2026, 5, 31)),
    ]);
  });

  const sutunlar = [
    EkstreRol.sembol, EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tutar,
    EkstreRol.tarih, EkstreRol.yon, EkstreRol.tur,
  ];
  EkstreHareketi hr(int gun, String kod, double adet, double fiyat,
          {bool satis = false}) =>
      EkstreHareketi(
          tarih: DateTime(2026, 5, gun),
          kod: kod,
          adet: adet,
          fiyat: fiyat,
          satis: satis);

  test('alışı eldekini aşan ya da sırası tutmayan kod inceltilmez', () {
    final satirlar = ['YAY\t10\t1800\t18000\t31.05.2026\tAlış\t'];
    expect(
        hareketlerleIncelt(satirlar, sutunlar, [hr(1, 'YAY', 20, 1)]).satirlar,
        satirlar);
    // Eldeki 10, dönemde 15 satış ve sonra 20 alış: açılış 5 ama ilk satış
    // 15'i karşılamıyor → hareket listesi eksik/başka hesap; dokunulmaz.
    final sirasiz = [
      hr(1, 'YAY', 15, 1, satis: true),
      hr(2, 'YAY', 20, 1),
    ];
    expect(hareketlerleIncelt(satirlar, sutunlar, sirasiz).satirlar, satirlar);
  });

  test('satışlı kod: açılış ilk hareket gününde fiyatsız, sonra alış/satış',
      () {
    final satirlar = ['YAY\t10\t1800\t18000\t31.05.2026\tAlış\tFon'];
    final r = hareketlerleIncelt(satirlar, sutunlar, [
      hr(2, 'YAY', 2, 1500, satis: true),
      hr(1, 'YAY', 5, 1400),
    ]);
    expect(r.incelen, 1);
    expect(r.satirlar, [
      // Açılış = 10 − 5 + 2 = 7; fiyat boş → toplu kayıt o günün kapanışı.
      'YAY\t7\t\t\t01.05.2026\tAlış\tFon',
      'YAY\t5\t1400\t7000\t01.05.2026\tAlış\tFon',
      'YAY\t2\t1500\t3000\t02.05.2026\tSatış\tFon',
    ]);
    final p = CsvImportService.parse(
        [sutunlar.map((x) => x.kanonikBaslik).join('\t'), ...r.satirlar]
            .join('\n'));
    expect(p.errors, isEmpty);
    expect(p.rows.map((x) => (x.quantity, x.price, x.satis)), [
      (7.0, 0.0, false),
      (5.0, 1400.0, false),
      (2.0, 1500.0, true),
    ]);
  });

  test('varlık tablosunda olmayan kod: yalnız bilinen kod, dönem sonu 0',
      () {
    final r = hareketlerleIncelt(const [], sutunlar, [
      hr(3, 'TTE', 100, 10, satis: true),
      hr(4, 'FON5', 50, 5, satis: true), // bankanın süpürme fonu
      hr(5, 'GOL', 10, 3), // alındı ama dönem sonunda yok → tutarsız
    ], bilinenKodlar: const {'TTE': 'Fon', 'GOL': 'Fon'});
    expect(r.incelen, 1);
    expect(r.satirlar, [
      'TTE\t100\t\t\t03.05.2026\tAlış\tFon',
      'TTE\t100\t10\t1000\t03.05.2026\tSatış\tFon',
    ]);
  });

  test('yalnız hareket listesi: açılış satışı karşılayan en küçük adet', () {
    final r = hareketlerleIncelt(const [], sutunlar, [
      hr(1, 'THYAO', 10, 300),
      hr(2, 'THYAO', 15, 320, satis: true),
    ], bilinenKodlar: const {'THYAO': 'Hisse'}, varlikTablosuVar: false);
    expect(r.satirlar, [
      'THYAO\t5\t\t\t01.05.2026\tAlış\tHisse',
      'THYAO\t10\t300\t3000\t01.05.2026\tAlış\tHisse',
      'THYAO\t15\t320\t4800\t02.05.2026\tSatış\tHisse',
    ]);
  });

  group('banka ekstresi: satılan fon', () {
    const satisli = EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['İşlem Tarihi', 'Açıklama', 'Yatırılan Tutar', 'Çekilen Tutar', 'Bakiye'],
      ['15/05/2026', 'TEFAS Müşteriye Fon Satış YAY 20,00x1.700,0000000', '',
          '-34,000.00 TL', '55,500.00 TL'],
      // Bankanın "Müşteriden Fon Alış"ı müşterinin SATIŞI: para girdi.
      ['20/05/2026', 'TEFAS Müşteriden Fon Alış YAY 5,00x1.750,0000000',
          '8,750.00 TL', '', '64,250.00 TL'],
      // Dönemde tamamen satılmış fon: varlık tablosunda yok.
      ['21/05/2026', 'TEFAS Müşteriden Fon Alış TTE 100,00x10,0000000',
          '1,000.00 TL', '', '65,250.00 TL'],
    ]);
    const liste = [
      (
        kod: 'YAY',
        unvan: 'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU'
      ),
      (kod: 'GOL', unvan: 'GARANTİ PORTFÖY ALTIN KATILIM FONU'),
      (kod: 'DLY', unvan: 'DENİZ PORTFÖY PARA PİYASASI (TL) FONU'),
      (kod: 'TTE', unvan: 'İŞ PORTFÖY BIST TEKNOLOJİ AĞIRLIK SINIRLAMALI ENDEKS HİSSE SENEDİ FONU'),
    ];

    test('satış ve satılmış fon içe aktarılır; bayrak kapalıyken eski', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, [fonlar, satisli],
              'Hesap Özeti Dönemi 01/05/2026 - 31/05/2026')
          .kodlarla(liste);
      final eski = CsvImportService.parse(s.kanonikMetin());
      expect(eski.rows.map((x) => (x.ticker, x.satis)), [
        ('TEFAS:YAY', false),
        ('TEFAS:GOL', false),
        ('TEFAS:DLY', false),
      ]);
      expect(s.hareketleIncelenen(), 2);
      final r = CsvImportService.parse(s.kanonikMetin(hareketlerle: true));
      expect(r.errors, isEmpty);
      expect(
          r.rows.map((x) =>
              (x.ticker, x.quantity, x.price, x.addedDate.day, x.satis)),
          [
            // YAY: eldeki 30 = açılış 15 + 20 alış − 5 satış.
            ('TEFAS:YAY', 15.0, 0.0, 15, false),
            ('TEFAS:YAY', 20.0, 1700.0, 15, false),
            ('TEFAS:YAY', 5.0, 1750.0, 20, true),
            ('TEFAS:GOL', 1000.0, 3.0, 31, false),
            ('TEFAS:DLY', 100.0, 5.0, 31, false),
            ('TEFAS:TTE', 100.0, 0.0, 21, false),
            ('TEFAS:TTE', 100.0, 10.0, 21, true),
          ]);
    });

    test('çözülemeyen fon adının adayı olan kod alınmaz', () {
      // "İŞ PORTFÖY" iki fona uyar → ad çözülmez; TTE adaylardan biri,
      // bugünkü adedi bilinmez → satışı eklenmez (elde duran fonu kapanmış
      // gösterirdi).
      const belirsiz = EkstreTablosu(kaynak: 'PDF', satirlar: [
        ['Yatırım Fonu İsmi', 'Pay Adedi', 'Birim Fiyat', 'Para Birimi',
            'Bakiye'],
        ['YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE', '30.00',
            '1800.0000', 'TL', '54,000.00'],
        ['GARANTİ PORTFÖY ALTIN KATILIM FONU', '1,000.00', '3.0000', 'TL',
            '3,000.00'],
        ['İŞ PORTFÖY', '50.00', '10.0000', 'TL', '500.00'],
      ]);
      final s = ekstreyiAnla(EkstreBicimi.pdf, [belirsiz, satisli], '')
          .kodlarla([
        ...liste,
        (kod: 'IPB', unvan: 'İŞ PORTFÖY BORÇLANMA ARAÇLARI FONU'),
      ]);
      expect(s.cozulemeyenFonlar, ['İŞ PORTFÖY']);
      expect(s.hareketKodlari.containsKey('TTE'), isFalse);
      final r = CsvImportService.parse(s.kanonikMetin(hareketlerle: true));
      expect(r.rows.where((x) => x.ticker == 'TEFAS:TTE'), isEmpty);
    });
  });
}
