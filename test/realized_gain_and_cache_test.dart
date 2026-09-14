import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/portfolio_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Asset _lot({
  required String id,
  AssetKind kind = AssetKind.buy,
  double qty = 10,
  double buy = 100,
  double? sell,
  double fx = 1.0,
  String currency = 'TRY',
  DateTime? deletedAt,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Test',
      ticker: 'TEST.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
      notes: '',
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sell,
      purchaseFxRate: fx,
      deletedAt: deletedAt,
    );

void main() {
  group('gerçekleşen K/Z', () {
    test('satış satırlarından (satış − maliyet) × miktar × kur', () {
      final s = PortfolioState(assets: [
        _lot(id: 'b1'),
        _lot(id: 's1', kind: AssetKind.sell, qty: 4, buy: 100, sell: 130),
        // dövizli satış: alım kuruyla TRY'ye
        _lot(id: 's2', kind: AssetKind.sell, qty: 2, buy: 10, sell: 8,
            fx: 30, currency: 'USD'),
      ]);
      expect(s.hasRealized, isTrue);
      // 4 × 30 = 120 ; 2 × (−2) × 30 = −120 → 0
      expect(s.realizedGainLoss, closeTo(0, 1e-9));
    });

    test('sell_price olmayan eski satış satırı SAYILMAZ', () {
      final s = PortfolioState(assets: [
        _lot(id: 'b1'),
        _lot(id: 's1', kind: AssetKind.sell, qty: 4, buy: 100),
      ]);
      expect(s.hasRealized, isFalse);
      expect(s.realizedGainLoss, 0);
    });

    test('silinmiş satış satırı hesaba girmez', () {
      final s = PortfolioState(assets: [
        _lot(id: 's1', kind: AssetKind.sell, qty: 4, buy: 100, sell: 130,
            deletedAt: DateTime(2026, 2, 1)),
      ]);
      expect(s.hasRealized, isFalse);
    });
  });

  group('PortfolioCache', () {
    test('yaz → oku round-trip; kullanıcıya özel; clear siler', () async {
      SharedPreferences.setMockInitialValues({});
      final assets = [
        _lot(id: 'b1'),
        _lot(id: 's1', kind: AssetKind.sell, qty: 4, buy: 100, sell: 130),
      ];
      await PortfolioCache.write('u1', assets);
      final back = await PortfolioCache.read('u1');
      expect(back, isNotNull);
      expect(back!.length, 2);
      expect(back[1].isSell, isTrue);
      expect(back[1].sellPrice, 130);
      expect(await PortfolioCache.read('u2'), isNull);
      await PortfolioCache.clear('u1');
      expect(await PortfolioCache.read('u1'), isNull);
    });

    test('bozuk kayıt null döner, fırlatmaz', () async {
      SharedPreferences.setMockInitialValues({'portfolio_cache_v1_u1': '{bozuk'});
      expect(await PortfolioCache.read('u1'), isNull);
    });
  });
}
