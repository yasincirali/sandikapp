import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';

/// Fon X-Ray (Premium, 2026-10-10) — TEFAS sınıf kodu → kaba kova eşlemesi
/// ve sunucu satırı ayrıştırması.
///
/// Kilitlenen kurallar (`fon_dagilimi.dart` başlığı):
///   · yüzdeler kaynaktan AYNEN, kova yalnız TOPLAR;
///   · `kba`/`kibd` etiket çelişkisi aynı kovaya düşer;
///   · haritada olmayan kod "Diğer" değil "Etiketsiz";
///   · Σ ≠ 100 ise fark hiçbir kovaya eklenmez.
void main() {
  group('tefasKodKovasi — her kod', () {
    // TEFAS'ın 57 yüzde kolonu (pytefas `schema.py`) ve beklenen kova.
    const beklenen = <String, XrayKova>{
      'hs': XrayKova.bistHisse,
      'yhs': XrayKova.yabanciHisse,
      'dt': XrayKova.devletBorclanma,
      'hb': XrayKova.devletBorclanma,
      'kks': XrayKova.devletBorclanma,
      'kkstl': XrayKova.devletBorclanma,
      'fb': XrayKova.ozelBorclanma,
      'ost': XrayKova.ozelBorclanma,
      'bb': XrayKova.ozelBorclanma,
      'vdm': XrayKova.ozelBorclanma,
      'osks': XrayKova.ozelBorclanma,
      'eut': XrayKova.dovizBorclanma,
      'kba': XrayKova.dovizBorclanma,
      'kibd': XrayKova.dovizBorclanma,
      'osdb': XrayKova.dovizBorclanma,
      'dot': XrayKova.dovizBorclanma,
      'db': XrayKova.dovizBorclanma,
      'kksd': XrayKova.dovizBorclanma,
      'kksyd': XrayKova.dovizBorclanma,
      'oksyd': XrayKova.dovizBorclanma,
      'yba': XrayKova.dovizBorclanma,
      'ybkb': XrayKova.dovizBorclanma,
      'ybosb': XrayKova.dovizBorclanma,
      'tpp': XrayKova.paraPiyasasi,
      'bpp': XrayKova.paraPiyasasi,
      'btaa': XrayKova.paraPiyasasi,
      'btas': XrayKova.paraPiyasasi,
      'r': XrayKova.paraPiyasasi,
      'tr': XrayKova.paraPiyasasi,
      'vm': XrayKova.mevduat,
      'vmtl': XrayKova.mevduat,
      'vmd': XrayKova.mevduat,
      'vmau': XrayKova.mevduat,
      'kh': XrayKova.mevduat,
      'khtl': XrayKova.mevduat,
      'khd': XrayKova.mevduat,
      'khau': XrayKova.mevduat,
      'km': XrayKova.kiymetliMaden,
      'kmbyf': XrayKova.kiymetliMaden,
      'kmkba': XrayKova.kiymetliMaden,
      'kmkks': XrayKova.kiymetliMaden,
      'fkb': XrayKova.fon,
      'yyf': XrayKova.fon,
      'byf': XrayKova.fon,
      'ybyf': XrayKova.fon,
      'gykb': XrayKova.gayrimenkulGirisim,
      'gyy': XrayKova.gayrimenkulGirisim,
      'gsykb': XrayKova.gayrimenkulGirisim,
      'gsyy': XrayKova.gayrimenkulGirisim,
      'gas': XrayKova.gayrimenkulGirisim,
      'd': XrayKova.diger,
      't': XrayKova.diger,
      'vint': XrayKova.diger,
      'ymk': XrayKova.diger,
    };

    test('harita tam olarak bu kodları taşır', () {
      expect(tefasKodKovasi.keys.toSet(), beklenen.keys.toSet());
    });

    for (final e in beklenen.entries) {
      test('${e.key} → ${e.value.name}', () {
        expect(kovaOf(e.key), e.value);
      });
    }

    test('kba / kibd çelişkisi aynı kovada (pytefas ↔ borsapy)', () {
      expect(kovaOf('kba'), kovaOf('kibd'));
    });

    test('bilinmeyen kod "Diğer" DEĞİL, Etiketsiz', () {
      expect(kovaOf('yenikod'), XrayKova.etiketsiz);
      expect(kovaOf('bilFiyat'), XrayKova.etiketsiz);
      expect(kovaOf(''), XrayKova.etiketsiz);
    });

    test('büyük harf / boşluk aynı koda iner', () {
      expect(kovaOf(' HS '), XrayKova.bistHisse);
    });

    test(
        'portföy-yalnız kovalar (döviz, kripto, emtia) hiçbir TEFAS kodundan '
        'gelmez', () {
      expect(
          tefasKodKovasi.values,
          isNot(contains(
              anyOf(XrayKova.doviz, XrayKova.kripto, XrayKova.emtia))));
    });
  });

  group('kovalaraTopla — yalnız toplama', () {
    test('para piyasası fonu AAL (TEFAS 2026-10-09)', () {
      final k = kovalaraTopla(const {
        'dt': 10.29,
        'fb': 9.03,
        'hb': 3.91,
        'tpp': 14.53,
        'tr': 34.29,
        'vmtl': 23.88,
        'khtl': 1.19,
        'ost': 1.48,
        'osks': 0.7,
        'vdm': 0.7,
      });
      expect(k[XrayKova.paraPiyasasi], closeTo(14.53 + 34.29, 1e-9));
      expect(k[XrayKova.mevduat], closeTo(23.88 + 1.19, 1e-9));
      expect(k[XrayKova.devletBorclanma], closeTo(10.29 + 3.91, 1e-9));
      expect(k[XrayKova.ozelBorclanma], closeTo(9.03 + 1.48 + 0.7 + 0.7, 1e-9));
      expect(k.containsKey(XrayKova.bistHisse), isFalse);
    });

    test('BES altın fonu AEA (EMK)', () {
      final k = kovalaraTopla(const {
        'km': 18.46,
        'kmbyf': 17.63,
        'kmkks': 63.67,
        'byf': 0.19,
        'yyf': 0.05
      });
      expect(k[XrayKova.kiymetliMaden], closeTo(99.76, 1e-9));
      expect(k[XrayKova.fon], closeTo(0.24, 1e-9));
    });

    test('sıfır ve sonsuz değer atlanır; negatif (repo borcu) korunur', () {
      final k = kovalaraTopla(
          const {'hs': 0, 'tr': double.infinity, 'r': -2.5, 'yhs': 102.5});
      expect(k, {XrayKova.paraPiyasasi: -2.5, XrayKova.yabanciHisse: 102.5});
    });
  });

  group('FonDagilimi', () {
    FonDagilimi? satir(Map<String, dynamic> d, {String tarih = '2026-10-09'}) =>
        FonDagilimi.satirdan({
          'fon_kodu': 'aft',
          'fon_tipi': 'YAT',
          'tarih': tarih,
          'dagilim': d
        });

    test('satirdan: kod büyük harf, tarih gün, yüzde aynen', () {
      final d = satir({'tr': 0.8, 'yhs': 98.74, 'yyf': 0.46})!;
      expect(d.fonKodu, 'AFT');
      expect(d.tarih, DateTime(2026, 10, 9));
      expect(d.dagilim, {'tr': 0.8, 'yhs': 98.74, 'yyf': 0.46});
    });

    test('kovalar büyükten küçüğe', () {
      final d = satir({'tr': 0.8, 'yhs': 98.74, 'yyf': 0.46})!;
      expect(d.kovalar.map((k) => k.kova), [
        XrayKova.yabanciHisse,
        XrayKova.paraPiyasasi,
        XrayKova.fon,
      ]);
      expect(d.kovalar.first.yuzde, 98.74);
    });

    test('Σ ≠ 100: fark hiçbir kovaya EKLENMEZ, kart söyler', () {
      final d = satir({'hs': 60, 'dt': 30})!; // %90
      expect(d.toplam, 90);
      expect(d.toplamSapiyor, isTrue);
      final toplamKova = d.kovalar.fold(0.0, (t, k) => t + k.yuzde);
      expect(toplamKova, 90);
      expect(d.kovalar.map((k) => k.kova),
          isNot(contains(anyOf(XrayKova.diger, XrayKova.etiketsiz))));
    });

    test('yuvarlama farkı (99,99) sapma sayılmaz', () {
      expect(satir({'hs': 99.99})!.toplamSapiyor, isFalse);
      expect(satir({'hs': 100.4})!.toplamSapiyor, isFalse);
      expect(satir({'hs': 100.6})!.toplamSapiyor, isTrue);
    });

    test('bilinmeyen kod Etiketsiz kovasında görünür, kaybolmaz', () {
      final d = satir({'hs': 90, 'yeni': 10})!;
      expect(d.kovalar.map((k) => k.kova),
          [XrayKova.bistHisse, XrayKova.etiketsiz]);
    });

    test('bozuk satır: null', () {
      expect(satir({}), isNull);
      expect(satir({'hs': 'yuzde'}), isNull);
      expect(satir({'hs': 10}, tarih: 'dün'), isNull);
      expect(
          FonDagilimi.satirdan({
            'fon_kodu': '',
            'tarih': '2026-10-09',
            'dagilim': {'hs': 1}
          }),
          isNull);
      expect(
          FonDagilimi.satirdan(
              {'fon_kodu': 'X', 'tarih': '2026-10-09', 'dagilim': 'hs'}),
          isNull);
    });
  });

  group('FonKalemleri (Katman A)', () {
    Map<String, dynamic> satir(List<Object?> kalemler,
            {String url = 'https://www.kap.org.tr/tr/Bildirim/1678119'}) =>
        {
          'fon_kodu': 'BTE',
          'donem': '2026-09-30',
          'kalemler': kalemler,
          'kaynak_url': url,
        };

    test('ağırlığa göre sıralı; bozuk kalem düşer', () {
      final k = FonKalemleri.satirdan(satir([
        {'ad': 'ASELSAN', 'kod': 'ASELS', 'tur': 'hisse', 'agirlik': 1.21},
        {
          'ad': 'TENCENT',
          'kod': '700 HK',
          'tur': 'yabanci_hisse',
          'agirlik': 7.7
        },
        {'ad': '', 'kod': 'X', 'tur': 'hisse', 'agirlik': 3},
        {'ad': 'Y', 'kod': 'Y', 'tur': 'hisse', 'agirlik': -1},
        'bozuk',
      ]))!;
      expect(k.kalemler.map((x) => x.kod), ['700 HK', 'ASELS']);
      expect(k.donem, DateTime(2026, 9, 30));
      expect(k.kaynakUrl, 'https://www.kap.org.tr/tr/Bildirim/1678119');
    });

    test('ilk(n) en fazla n kalem', () {
      final k = FonKalemleri.satirdan(satir([
        for (var i = 1; i <= 15; i++)
          {'ad': 'K$i', 'kod': 'K$i', 'tur': 'hisse', 'agirlik': i.toDouble()},
      ]))!;
      expect(k.ilk(10).length, 10);
      expect(k.ilk(10).first.agirlik, 15);
    });

    test('KAP dışı adres açılmaz', () {
      final k = FonKalemleri.satirdan(satir([
        {'ad': 'A', 'kod': 'A', 'tur': 'hisse', 'agirlik': 1},
      ], url: 'https://kotu.example/x'))!;
      expect(k.kaynakUrl, isNull);
    });

    test('etiket: kod, ISIN ise ad; hisse anahtarı yalnız hissede', () {
      const hisse =
          FonKalemi(ad: 'ASELSAN', kod: 'asels', tur: 'hisse', agirlik: 1);
      const tahvil = FonKalemi(
          ad: 'T.C. HAZİNE', kod: 'TRT150127T13', tur: 'borclanma', agirlik: 1);
      const repo =
          FonKalemi(ad: 'Ters repo', kod: '', tur: 'para_piyasasi', agirlik: 1);
      expect(hisse.etiket, 'asels');
      expect(hisse.hisseAnahtari, 'ASELS');
      expect(tahvil.etiket, 'T.C. HAZİNE');
      expect(tahvil.hisseAnahtari, isNull);
      expect(repo.etiket, 'Ters repo');
    });

    test('boş liste: null (kart kalem bölümü çizmez)', () {
      expect(FonKalemleri.satirdan(satir(const [])), isNull);
    });
  });
}
