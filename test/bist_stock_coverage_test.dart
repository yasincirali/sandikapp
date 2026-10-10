import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';

void main() {
  group('BIST hisse listesi kapsamı', () {
    test('BIST 100 dışı hisseler de listede — GSDHO regresyonu', () {
      // Kullanıcı bildirimi: GSDHO seçicide hiç görünmüyordu çünkü liste
      // yalnızca BIST 100 ile sınırlıydı. Borsada işlem gören her hisse
      // eklenebilmeli.
      const bist100DisiOrnekler = [
        'GSDHO.IS', // GSD Holding — bildirilen hata
        'TSKB.IS',
        'AEFES.IS',
        'AKCNS.IS',
        'ANSGR.IS',
        'ARENA.IS',
        'ISDMR.IS',
        'LKMNH.IS',
      ];
      for (final ticker in bist100DisiOrnekler) {
        expect(
          bist100StocksMap.containsKey(ticker),
          isTrue,
          reason: '$ticker listede yok — kullanıcı bu hisseyi ekleyemez',
        );
        expect(
          bist100StocksMap[ticker],
          isNotEmpty,
          reason: '$ticker için şirket adı boş',
        );
      }
    });

    test('mevcut BIST 100 hisseleri korundu', () {
      for (final ticker in ['GARAN.IS', 'THYAO.IS', 'ASELS.IS', 'TUPRS.IS']) {
        expect(bist100StocksMap.containsKey(ticker), isTrue);
      }
    });

    test('tüm semboller .IS son ekiyle ve tekil', () {
      for (final ticker in bist100StocksMap.keys) {
        expect(ticker.endsWith('.IS'), isTrue,
            reason: '$ticker .IS ile bitmiyor');
        expect(ticker, equals(ticker.toUpperCase()));
      }
      expect(bist100StocksMap.keys.toSet().length, bist100StocksMap.length);
    });

    test('BIST 100\'ün tamamı listede (2026-10-10 bileşimi)', () {
      // Kullanıcı bildirimi: "tüm BIST100 hisseleri yok" — AYGAZ, ENKAI,
      // FENER, ASTOR, TRALT… eksikti. Bileşim TradingView XU100 kümesinden
      // ölçüldü (tool/bist_evren_olc.py). Endeks değişince bu liste de
      // güncellenir; eksik kalan sembol kullanıcının ekleyemediği hissedir.
      const xu100 = [
        'AEFES',
        'AGHOL',
        'AHGAZ',
        'AKBNK',
        'AKCNS',
        'AKFYE',
        'AKSA',
        'AKSEN',
        'ALARK',
        'ALBRK',
        'ALTNY',
        'ANHYT',
        'ANSGR',
        'ARCLK',
        'ASELS',
        'ASTOR',
        'AYGAZ',
        'BERA',
        'BIMAS',
        'BINHO',
        'BRSAN',
        'BRYAT',
        'BTCIM',
        'CANTE',
        'CCOLA',
        'CIMSA',
        'CVKMD',
        'CWENE',
        'DOAS',
        'DOHOL',
        'ECILC',
        'ECZYT',
        'EGEEN',
        'EGGUB',
        'EKGYO',
        'ENERY',
        'ENJSA',
        'ENKAI',
        'ENTRA',
        'EREGL',
        'EUREN',
        'FENER',
        'FROTO',
        'GARAN',
        'GLRMK',
        'GLYHO',
        'GRSEL',
        'GUBRF',
        'GWIND',
        'HALKB',
        'HEKTS',
        'ISCTR',
        'ISDMR',
        'ISMEN',
        'KARSN',
        'KATMR',
        'KCAER',
        'KCHOL',
        'KORDS',
        'KRDMD',
        'LMKDC',
        'MAVI',
        'MGROS',
        'MPARK',
        'OBAMS',
        'ODAS',
        'OTKAR',
        'OYAKC',
        'PAHOL',
        'PETKM',
        'PGSUS',
        'RGYAS',
        'RYSAS',
        'SAHOL',
        'SASA',
        'SISE',
        'SNGYO',
        'SOKM',
        'TABGD',
        'TAVHL',
        'TCELL',
        'TCKRC',
        'THYAO',
        'TKFEN',
        'TOASO',
        'TRALT',
        'TRENJ',
        'TRGYO',
        'TRMET',
        'TSKB',
        'TTKOM',
        'TTRAK',
        'TUKAS',
        'TUPRS',
        'TURSG',
        'ULKER',
        'VAKBN',
        'VESTL',
        'YKBNK',
        'ZOREN',
      ];
      expect(xu100.length, 100);
      final eksik = [
        for (final k in xu100)
          if (!bist100StocksMap.containsKey('$k.IS')) k,
      ];
      expect(eksik, isEmpty,
          reason: 'BIST 100\'de olup listede olmayan: $eksik');
    });

    test('işlem görmeyen eski kodlar seçicide yok ama içe aktarmada tanınır',
        () {
      // KOZAL→TRALT, KOZAA→TRMET, IPEKE→TRENJ, QNBFB→QNBTR; ENKA hiç yoktu
      // (doğrusu ENKAI). Fiyatı gelmeyen hisseyi seçtirmek hata; ama 2024
      // ekstresindeki KOZAL satırı hâlâ hisse satırıdır.
      for (final k in ['KOZAL', 'KOZAA', 'IPEKE', 'QNBFB', 'ENKA']) {
        expect(bist100StocksMap.containsKey('$k.IS'), isFalse, reason: k);
        expect(bistKoduMu(k), isTrue, reason: k);
      }
      for (final k in ['TRALT', 'TRMET', 'TRENJ', 'QNBTR', 'ENKAI']) {
        expect(bist100StocksMap.containsKey('$k.IS'), isTrue, reason: k);
      }
      expect(
          bist100StocksMap.keys
              .toSet()
              .intersection(bistEskiSemboller.keys.toSet()),
          isEmpty);
    });

    test('ALTIN sertifikası hisse kodu sayılmaz', () {
      // "ALTIN" hisse kodu sayılsaydı ekstrede altın satırı hisse diye
      // okunurdu (sembolPuani 1).
      expect(bistKoduMu('ALTIN'), isFalse);
    });

    test('liste borsanın tamamına yakın (600+)', () {
      expect(bist100StocksMap.length, greaterThan(600));
    });

    test('liste anlamlı biçimde genişledi (91 → 300+)', () {
      expect(bist100StocksMap.length, greaterThan(250));
    });

    test('picker arama mantığı GSDHO\'yu bulur', () {
      // _Bist100PickerState._filtered ile aynı filtre: ad veya sembol eşleşmesi
      List<String> ara(String q) => bist100StocksMap.entries
          .where((e) =>
              e.value.toLowerCase().contains(q.toLowerCase()) ||
              e.key.toLowerCase().contains(q.toLowerCase()))
          .map((e) => e.key)
          .toList();

      expect(ara('GSDHO'), contains('GSDHO.IS'));
      expect(ara('gsdho'), contains('GSDHO.IS'));
      expect(ara('GSD Holding'), contains('GSDHO.IS'));
    });
  });
}
