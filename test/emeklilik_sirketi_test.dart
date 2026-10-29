import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/emeklilik_sirketi.dart';
import 'package:portfoy_takip/screens/add_asset/emeklilik_fonu_secici.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// Emeklilik şirketi TEFAS EMK fon unvanlarından türer; fon seçici
/// sözleşmenin şirketine göre süzülür (2026-10-29, yasin: "MetLife gibi
/// BES varlıkları incelenmeli"). Unvan biçimi: şirketin ticaret unvanı
/// ("… A.Ş.") + fonun adı. Elle şirket listesi yok.
void main() {
  // Unvanlar TEFAS biçiminde; ilk üçü depodaki gerçek örneklerden
  // (`supabase/tests/fon_dagilim_ornek.json`, `devlet_katkisi_fonu_test`).
  const unvanlar = [
    'ANADOLU HAYAT EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU',
    'ANADOLU HAYAT EMEKLİLİK A.Ş. KATKI EMEKLİLİK YATIRIM FONU',
    'AGESA HAYAT VE EMEKLİLİK A.Ş. HİSSE SENEDİ EMEKLİLİK YATIRIM FONU',
    'ALLIANZ YAŞAM VE EMEKLİLİK A.Ş. KATILIM STANDART EMEKLİLİK YATIRIM FONU',
    'METLİFE EMEKLİLİK VE HAYAT A.Ş. BORÇLANMA ARAÇLARI EMEKLİLİK YATIRIM FONU',
    'METLİFE EMEKLİLİK VE HAYAT A.Ş. KATKI EMEKLİLİK YATIRIM FONU',
    'GARANTİ EMEKLİLİK VE HAYAT A.Ş. DENGELİ EMEKLİLİK YATIRIM FONU',
    'HDI FİBA EMEKLİLİK VE HAYAT A.Ş. PARA PİYASASI EMEKLİLİK YATIRIM FONU',
    // A.Ş. taşımayan unvan hiçbir şirkete bağlanmaz (tahmin yok).
    'ESKİ BİÇİM EMEKLİLİK YATIRIM FONU',
  ];

  group('şirket öneki ve adı', () {
    test('önek "A.Ş."ye kadar; yoksa null', () {
      expect(emeklilikSirketOneki(unvanlar[0]), 'ANADOLU HAYAT EMEKLİLİK');
      expect(emeklilikSirketOneki(unvanlar.last), isNull);
      expect(emeklilikSirketOneki('A.Ş. ADSIZ FON'), isNull);
    });

    test('gösterim adı: Türkçe harf kuralı, "ve" küçük, marka yazımı', () {
      expect(emeklilikSirketAdi('ANADOLU HAYAT EMEKLİLİK'),
          'Anadolu Hayat Emeklilik');
      expect(emeklilikSirketAdi('ALLIANZ YAŞAM VE EMEKLİLİK'),
          'Allianz Yaşam ve Emeklilik');
      expect(emeklilikSirketAdi('METLİFE EMEKLİLİK VE HAYAT'),
          'MetLife Emeklilik ve Hayat');
      expect(emeklilikSirketAdi('AGESA HAYAT VE EMEKLİLİK'),
          'AgeSA Hayat ve Emeklilik');
      expect(emeklilikSirketAdi('HDI FİBA EMEKLİLİK VE HAYAT'),
          'HDI Fiba Emeklilik ve Hayat');
    });

    test('liste: tekrar yok, fon sayısı, ada göre sıralı', () {
      final l = emeklilikSirketleri(unvanlar);
      expect(l.map((s) => s.ad), [
        'AgeSA Hayat ve Emeklilik',
        'Allianz Yaşam ve Emeklilik',
        'Anadolu Hayat Emeklilik',
        'Garanti Emeklilik ve Hayat',
        'HDI Fiba Emeklilik ve Hayat',
        'MetLife Emeklilik ve Hayat',
      ]);
      expect(l.firstWhere((s) => s.ad.startsWith('MetLife')).fonSayisi, 2);
    });

    test('fonun kısa adı: şirket ve "emeklilik yatırım fonu" atılır', () {
      expect(emeklilikFonuKisaAdi(unvanlar[0]), 'Altın Katılım');
      expect(emeklilikFonuKisaAdi(unvanlar[2]), 'Hisse Senedi');
      expect(emeklilikFonuKisaAdi('XYZ'), isNull);
    });
  });

  group('serbest metinli kurumu şirkete bağlama', () {
    final sirketler = emeklilikSirketleri(unvanlar);
    String? bul(String k) => emeklilikSirketiBul(k, sirketler)?.ad;

    test('büyük/küçük harf ve Türkçe karakter farkı yok', () {
      expect(bul('Anadolu Hayat'), 'Anadolu Hayat Emeklilik');
      expect(bul('ANADOLU HAYAT'), 'Anadolu Hayat Emeklilik');
      expect(bul('metlife'), 'MetLife Emeklilik ve Hayat');
      expect(bul('MetLife Emeklilik'), 'MetLife Emeklilik ve Hayat');
      expect(bul('allianz yasam'), 'Allianz Yaşam ve Emeklilik');
      expect(bul('Garanti'), 'Garanti Emeklilik ve Hayat');
      expect(bul('HDI Fiba'), 'HDI Fiba Emeklilik ve Hayat');
    });

    test('listedeki adın kendisi birebir eşleşir', () {
      for (final s in sirketler) {
        expect(emeklilikSirketiBul(s.ad, sirketler), s);
      }
    });

    test('bilinmeyen, boş ya da yalnız genel kelime → null', () {
      expect(bul('Bilinmeyen Sigorta'), isNull);
      expect(bul(''), isNull);
      expect(bul('Emeklilik'), isNull);
      expect(emeklilikSirketiBul(null, sirketler), isNull);
    });

    test('iki şirkete uyan ad tahmin edilmez', () {
      final iki = emeklilikSirketleri([
        'GARANTİ EMEKLİLİK VE HAYAT A.Ş. X EMEKLİLİK YATIRIM FONU',
        'GARANTİ BBVA EMEKLİLİK A.Ş. Y EMEKLİLİK YATIRIM FONU',
      ]);
      expect(emeklilikSirketiBul('Garanti', iki), isNull);
      expect(emeklilikSirketiBul('Garanti BBVA', iki)?.ad,
          'Garanti BBVA Emeklilik');
    });
  });

  group('fon seçici şirkete göre süzer', () {
    final fonlar = [
      for (final (i, u) in unvanlar.indexed)
        TefasFund(
            code: 'F$i',
            name: u,
            price: 0,
            fundType: 'EMK',
            managerName: ''),
    ];
    final sirketler = emeklilikSirketleri(unvanlar);

    test('şirket seçiliyse yalnız onun fonları', () {
      final metlife = emeklilikSirketiBul('MetLife', sirketler);
      expect(sirketFonlari(fonlar, metlife).map((f) => f.code), ['F4', 'F5']);
    });

    test('"Tüm fonlar" (şirket yok) → hepsi, A.Ş.\'siz fon dahil', () {
      expect(sirketFonlari(fonlar, null).length, unvanlar.length);
    });
  });
}
