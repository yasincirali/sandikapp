import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';
import 'package:portfoy_takip/services/ekstre/tutar_tablosu.dart';

/// Yalnız tutar yazan banka belgesi (2026-10-15, DenizBank "Varlık Geçmişi
/// Formu"; yasin: "varlık tablosu bulamadı diyor"). Tablolar gerçek
/// belgenin PDF geometrisinden çıkan DÜZENDE; hesap numaraları ve tutarlar
/// uydurmadır (kişisel veri teste girmez).
void main() {
  const tefas = [
    (kod: 'IJC', unvan: 'İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON'),
    (
      kod: 'YAY',
      unvan: 'YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU'
    ),
    (kod: 'DLY', unvan: 'DENİZ PORTFÖY PARA PİYASASI (TL) FONU'),
  ];

  const metin = 'Varlık Geçmişi Formu\nSayın Müşterimiz,\n'
      '31.08.2026 tarihi itibarıyla varlıklarınızın ürün ve döviz türü '
      'bazında dağılımını gösteren Varlık Geçmişiniz bilgilerinize '
      'sunulmuştur.\nDenizBank A.Ş.';
  const tablolar = [
    EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Varlık Geçmişi Formu', '', '', '', ''],
      ['Vadesiz Mevduat', '', '', '', '1.500,00 TRY'],
      ['1111-2222-351', '', '', '', '1.000 TRY'],
      ['1111-2222-355', '', '', '', '0 USD'],
    ]),
    EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Vadeli Mevduat', '200,00 TRY'],
      ['1111-2222-354', '200,00 TRY'],
    ]),
    EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Yatırım Fonları', '100.000,00 TRY'],
      ['YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE---TRMYK9WWWWW2',
          '30.000,00 TRY'],
      ['İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON---TRYISPO00704',
          '20.000,02 TRY'],
      ['Deniz Portföy Para Piyasası (TL) Fonu---TRMDLYWWWWW9', '50.000,00 TRY'],
      ['Toplam Varlık Tutarı', '101.700,00 TRY'],
    ]),
  ];

  group('tanıma', () {
    test('fon adı + TL tutar satırları; grup, toplam ve hesaplar alınmaz', () {
      final f = tutarliFonlar(tablolar);
      expect(f.map((x) => (x.ad.split('---').first, x.tutar)), [
        ('YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE', 30000.0),
        ('İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON', 20000.02),
        ('Deniz Portföy Para Piyasası (TL) Fonu', 50000.0),
      ]);
    });

    test('elle eşleme adayı yerine tutarlı fonlar döner', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, tablolar, metin);
      expect(s.ana, isNull);
      expect(s.tutarFonlari, hasLength(3));
      expect(s.belgeTarihi, DateTime(2026, 8, 31));
      expect(s.cozulecekFonAdlari, hasLength(3));
    });

    test('adetli varlık tablosu varken devreye girmez', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, [
        ...tablolar,
        const EkstreTablosu(kaynak: 'PDF', satirlar: [
          ['Sembol', 'Adet', 'Fiyat'],
          ['THYAO', '100', '312,40'],
          ['ASELS', '20', '60,00'],
        ]),
      ], metin);
      expect(s.tutarFonlari, isEmpty);
      expect(s.ana, isNotNull);
    });
  });

  group('adet = tutar ÷ belge günü fiyatı', () {
    test('kuruş içinde tutan tam sayı adet; tutmazsa 4 ondalık', () {
      expect(tutardanAdet(30000, 1034.482759), 29); // 29 × 1034,48… ≈ 30.000
      expect(tutardanAdet(20000.02, 12.145732), 1646.6706);
    });

    test('belge günü yoksa önceki 7 günün son fiyatı; daha eskisi sayılmaz', () {
      int t(int g) => DateTime(2026, 8, g, 18).millisecondsSinceEpoch;
      expect(gunFiyati([(t(27), 1.0), (t(28), 2.0), (t(31), 3.0)],
          DateTime(2026, 8, 31)), 3.0);
      expect(gunFiyati([(t(27), 1.0), (t(28), 2.0)], DateTime(2026, 8, 31)),
          2.0);
      expect(gunFiyati([(t(1), 1.0)], DateTime(2026, 8, 31)), isNull);
    });

    test('fiyatı olan fon içe aktarılır, olmayan atlanıp söylenir', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, tablolar, metin)
          .kodlarla(tefas)
          .fiyatlarla({'YAY': 1034.482759, 'DLY': 5.0});
      expect(s.tutarFonKodlari, ['YAY', 'IJC', 'DLY']);
      expect(s.fiyatiAlinamayanFonlar,
          ['İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON']);
      for (final hareketlerle in [false, true]) {
        final r = CsvImportService.parse(
            s.kanonikMetin(hareketlerle: hareketlerle));
        expect(r.errors, isEmpty);
        expect(r.rows.map((x) => (x.ticker, x.quantity, x.price)), [
          ('TEFAS:YAY', 29.0, 1034.482759),
          ('TEFAS:DLY', 10000.0, 5.0),
        ]);
        expect(r.rows.first.addedDate, DateTime(2026, 8, 31));
      }
    });

    test('fiyat gelmeden metin boş (uydurma adet yok)', () {
      final s =
          ekstreyiAnla(EkstreBicimi.pdf, tablolar, metin).kodlarla(tefas);
      expect(s.kanonikMetin(), isEmpty);
    });
  });
}
