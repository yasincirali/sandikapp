import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
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
      final f = tutarliKalemler(tablolar);
      expect(f.map((x) => (x.ad.split('---').first, x.tutar)), [
        ('YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE', 30000.0),
        ('İŞ PORTFÖY YARI İLETKEN TEKNOLOJİLERİ DEĞİŞKEN FON', 20000.02),
        ('Deniz Portföy Para Piyasası (TL) Fonu', 50000.0),
      ]);
    });

    test('elle eşleme adayı yerine tutarlı fonlar döner', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, tablolar, metin);
      expect(s.ana, isNull);
      expect(s.tutarKalemleri, hasLength(3));
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
      expect(s.tutarKalemleri, isEmpty);
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
          .fiyatlarla({'TEFAS:YAY': 1034.482759, 'TEFAS:DLY': 5.0});
      expect(s.istenecekFiyatlar, ['TEFAS:YAY', 'TEFAS:IJC', 'TEFAS:DLY']);
      expect(s.fiyatiAlinamayanlar,
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

  // yasin 2026-10-15: "sadece fonlar için değil, altın hisse döviz vs tüm
  // varlıklar için olmalı, ayrıca Midas gibi yabancı piyasa aracı
  // kurumlarının varlık PDF ya da Excelleri de". Düzen bankanınkiyle aynı,
  // tutarlar uydurma.
  group('tüm varlık türleri', () {
    setUp(() => CsvImportService.abdHisseAcik = () => true);

    const karma = [
      EkstreTablosu(kaynak: 'PDF', satirlar: [
        ['Hisse Senetleri', '31.240,00 TRY'],
        ['THYAO', '31.240,00 TRY'],
        ['AKBANK T.A.Ş.---TRAAKBNK91N6', '6.000,00 TRY'],
        ['Altın', '10.000,00 TRY'],
        ['Altın Hesabı', '10.000,00 TRY'],
        ['Çeyrek Altın', '8.000,00 TRY'],
        ['Vadesiz USD Hesabı', '1.250,50 USD'],
        ['Euro', '3.500,00 TRY'],
        ['Bitcoin', '40.000,00 TRY'],
        ['AAPL', '2,500.00', 'USD'],
        ['NVDA - NVIDIA CORP', r'$1,000.00'],
        ['1111-2222-351', '1.000 TRY'],
        ['Altın Fonu', '5.000,00 TRY'],
      ]),
    ];

    test('işaretli adlar türüne ayrılır; grup başlığı ve hesap no alınmaz',
        () {
      final k = tutarliKalemler(karma);
      expect(k.map((x) => (x.tur, x.sembol, x.para, x.tutar)), [
        (EkstreTutarTuru.hisse, 'THYAO', 'TRY', 31240.0),
        (EkstreTutarTuru.hisse, 'AKBNK', 'TRY', 6000.0),
        (EkstreTutarTuru.altin, 'ALTIN_GRAM24', 'TRY', 10000.0),
        (EkstreTutarTuru.altin, 'ALTIN_CEYREK', 'TRY', 8000.0),
        (EkstreTutarTuru.doviz, 'USD', 'USD', 1250.5),
        (EkstreTutarTuru.doviz, 'EUR', 'TRY', 3500.0),
        (EkstreTutarTuru.kripto, 'KRIPTO:BTC', 'TRY', 40000.0),
        (EkstreTutarTuru.abd, 'AAPL', 'USD', 2500.0),
        (EkstreTutarTuru.abd, 'NVDA', 'USD', 1000.0),
        (EkstreTutarTuru.fon, null, 'TRY', 5000.0),
      ]);
    });

    test('belge günü fiyatı ve kuruyla adet; doğru sembol ve para', () {
      final s = ekstreyiAnla(EkstreBicimi.pdf, karma, metin).fiyatlarla({
        'THYAO.IS': 312.40,
        'AKBNK.IS': 60.0,
        'ALTIN_GRAM24': 4000.0,
        'ALTIN_CEYREK': 6400.0,
        'USDTRY=X': 40.0,
        'EURTRY=X': 35.0,
        'KRIPTO:BTC': 4000000.0,
        'AAPL': 250.0,
        'NVDA': 125.0,
      });
      final r = CsvImportService.parse(s.kanonikMetin());
      expect(r.errors, isEmpty);
      expect(
          r.rows.map((x) => (x.type, x.ticker, x.quantity, x.price,
              x.currency, x.subCategory)),
          [
            (AssetType.hisse, 'THYAO.IS', 100.0, 312.40, 'TRY', null),
            (AssetType.hisse, 'AKBNK.IS', 100.0, 60.0, 'TRY', null),
            (AssetType.altin, 'ALTIN_GRAM24', 2.5, 4000.0, 'TRY',
                'Gram Altın (24 Ayar)'),
            (AssetType.altin, 'ALTIN_CEYREK', 1.25, 6400.0, 'TRY',
                'Çeyrek Altın'),
            // Döviz hesabı kendi parasıyla: adet = tutar, fiyat = kur.
            (AssetType.doviz, 'USDTRY=X', 1250.5, 40.0, 'TRY', 'USD'),
            (AssetType.doviz, 'EURTRY=X', 100.0, 35.0, 'TRY', 'EUR'),
            (AssetType.kripto, 'KRIPTO:BTC', 0.01, 4000000.0, 'TRY', null),
            (AssetType.hisse, 'AAPL', 10.0, 250.0, 'USD',
                StockSubCategory.abd.name),
            (AssetType.hisse, 'NVDA', 8.0, 125.0, 'USD',
                StockSubCategory.abd.name),
          ]);
      // Adı bulunamamış fon (TEFAS listesi verilmedi) sessizce fiyat
      // istemez; "tanınmadı" uyarısı ad çözümünden gelir.
      expect(s.cozulemeyenFonlar, ['Altın Fonu']);
    });

    test('dolar tutarlı altın belge günü kuruyla TL fiyata bölünür', () {
      const t = [
        EkstreTablosu(kaynak: 'PDF', satirlar: [
          ['AAPL', '1.000,00 USD'],
          ['Altın', '200,00 USD'],
        ]),
      ];
      final s = ekstreyiAnla(EkstreBicimi.pdf, t, metin);
      expect(s.istenecekFiyatlar, ['AAPL', 'ALTIN_GRAM24', 'USDTRY=X']);
      final f = s.fiyatlarla({'AAPL': 250.0, 'ALTIN_GRAM24': 4000.0});
      // Kur yok → altın eklenmez, nedeni söylenir; dolar fiyatlı AAPL girer.
      expect(f.fiyatiAlinamayanlar, ['Altın']);
      final tam = s.fiyatlarla(
          {'AAPL': 250.0, 'ALTIN_GRAM24': 4000.0, 'USDTRY=X': 40.0});
      final r = CsvImportService.parse(tam.kanonikMetin());
      expect(r.rows.map((x) => (x.ticker, x.quantity)), [
        ('AAPL', 4.0),
        ('ALTIN_GRAM24', 2.0),
      ]);
    });

    test('ABD hissesi bayrağı kapalıysa satır eklenmez, nedeni söylenir', () {
      CsvImportService.abdHisseAcik = () => false;
      final s = ekstreyiAnla(EkstreBicimi.pdf, const [
        EkstreTablosu(kaynak: 'PDF', satirlar: [
          ['AAPL', '2,500.00', 'USD'],
          ['THYAO', '3.124,00 TRY'],
        ]),
      ], metin).fiyatlarla({'AAPL': 250.0, 'THYAO.IS': 312.40});
      final r = CsvImportService.parse(s.kanonikMetin());
      expect(r.rows.map((x) => x.ticker), ['THYAO.IS']);
      expect(r.errors.single, contains('ABD hissesi'));
    });
  });
}
