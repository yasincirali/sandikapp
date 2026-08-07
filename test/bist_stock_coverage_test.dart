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
        expect(ticker.endsWith('.IS'), isTrue, reason: '$ticker .IS ile bitmiyor');
        expect(ticker, equals(ticker.toUpperCase()));
      }
      expect(bist100StocksMap.keys.toSet().length, bist100StocksMap.length);
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
