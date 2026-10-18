import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/emtia_katalogu.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ons kote emtia gram olarak da eklenir (yasin 18 Eki 2026). Kilitlenenler:
///   · her ons kote katalog satırının gram eşi var ve tersi;
///   · gram fiyatı ons kotasyonu ÷ 31,1035, yüzde aynı (fiyat katmanında);
///   · gram ve ons lotu ayrı sembol (aynı pozisyonda toplanmaz);
///   · seçim kayda birim yazar (gr / oz etiketi, gram hazır miktarları).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('her ons kote satırın gram eşi var, gram tabanı ons kote', () {
    final onslar = emtiaKatalogu.where((e) => e.birim == EmtiaBirimi.ons);
    final gramlar = emtiaKatalogu.where((e) => e.birim == EmtiaBirimi.gram);
    expect(onslar.length, 3);
    for (final o in onslar) {
      expect(emtiaSecenegi('$emtiaGramOneki${o.ticker}')?.birim,
          EmtiaBirimi.gram, reason: o.ad);
    }
    for (final g in gramlar) {
      expect(emtiaSecenegi(emtiaGramTabani(g.ticker)!)?.birim,
          EmtiaBirimi.ons, reason: g.ad);
    }
  });

  test('gram tabanı: önek, büyük/küçük harf, gram olmayan sembol', () {
    expect(emtiaGramTabani('GRAM:SI=F'), 'SI=F');
    expect(emtiaGramTabani(' gram:pl=f '), 'PL=F');
    expect(emtiaGramTabani('SI=F'), isNull);
    expect(emtiaGramTabani('GRAM:'), isNull);
  });

  test('gram kotasyonu = ons ÷ 31,1035, yüzde aynı', () async {
    final ps = PriceService.instance;
    ps.testIcinOnbellegeYaz(const YahooQuote(
        symbol: 'SI=F',
        regularMarketPrice: 31.1035 * 2,
        currency: 'USD',
        regularMarketChangePercent: 1.5));
    final q = await ps.fetchQuotes(['GRAM:SI=F', 'SI=F']);
    expect(q['GRAM:SI=F']!.regularMarketPrice, closeTo(2, 1e-9));
    expect(q['GRAM:SI=F']!.regularMarketChangePercent, 1.5);
    expect(q['SI=F']!.regularMarketPrice, closeTo(62.207, 1e-9));
    expect(ps.sonBilinenFiyat('GRAM:SI=F'), closeTo(2, 1e-9));
  });

  test('gram ve ons lotu ayrı pozisyon', () {
    Asset lot(String t) => Asset(
          id: t,
          userId: 'u',
          name: 'Gümüş',
          ticker: t,
          type: AssetType.emtia,
          quantity: 1,
          purchasePrice: 1,
          currency: 'USD',
          notes: '',
          isManualPrice: false,
          currentPrice: 1,
          addedDate: DateTime(2026, 10, 18),
        );
    expect(positionKey(lot('SI=F')), isNot(positionKey(lot('GRAM:SI=F'))));
  });

  test('seçim birimi kayda yazar; Diğer adete döner', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final args = AddAssetFormArgs(prefillType: AssetType.emtia);
    final n = c.read(addAssetFormProvider(args).notifier);
    n.selectEmtia(emtiaSecenegi('GRAM:SI=F')!);
    var s = c.read(addAssetFormProvider(args));
    expect(s.unitType, 'gram');
    expect(s.quantitySuffix, 'gr');
    expect(s.quantityPresets, contains('100'));
    n.selectEmtia(emtiaSecenegi('SI=F')!);
    s = c.read(addAssetFormProvider(args));
    expect(s.unitType, 'ounce');
    expect(s.quantitySuffix, 'oz');
    n.emtiaDiger(tickerText: 'SI=F');
    expect(c.read(addAssetFormProvider(args)).unitType, 'piece');
  });
}
