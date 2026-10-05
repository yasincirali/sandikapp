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

  test('satışı olan ya da alışı eldekini aşan kod inceltilmez', () {
    final satirlar = ['YAY\t10\t1800\t18000\t31.05.2026\tAlış'];
    const sutunlar = [
      EkstreRol.sembol, EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tutar,
      EkstreRol.tarih, EkstreRol.yon,
    ];
    final asan = [
      EkstreHareketi(
          tarih: DateTime(2026, 5, 1), kod: 'YAY', adet: 20, fiyat: 1, satis: false),
    ];
    expect(hareketlerleIncelt(satirlar, sutunlar, asan).satirlar, satirlar);
    final satisli = [
      EkstreHareketi(
          tarih: DateTime(2026, 5, 1), kod: 'YAY', adet: 5, fiyat: 1, satis: false),
      EkstreHareketi(
          tarih: DateTime(2026, 5, 2), kod: 'YAY', adet: 2, fiyat: 1, satis: true),
    ];
    expect(hareketlerleIncelt(satirlar, sutunlar, satisli).satirlar, satirlar);
  });
}
