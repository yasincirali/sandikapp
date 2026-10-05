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
  double? sellFx,
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
      sellFxRate: sellFx,
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

    // 0110 (2026-10-05): dövizli satışta ele geçen tutar satış günü kuruyla.
    // 1 adet $100'dan alındı (kur 30), $100'dan satıldı (kur 41): dolar
    // bazında kâr yok, TL bazında kur kazancı 1.100 TL.
    test('satış günü kuru varsa kur kazancı gerçekleşen kâra girer', () {
      final s = PortfolioState(assets: [
        _lot(id: 's1', kind: AssetKind.sell, qty: 1, buy: 100, sell: 100,
            fx: 30, sellFx: 41, currency: 'USD'),
      ]);
      expect(s.realizedGainLoss, closeTo(1100, 1e-9));
    });

    test('satış komisyonu satış kuruyla düşer', () {
      final lot = Asset(
        id: 's1',
        userId: 'u1',
        name: 'Test',
        ticker: 'AAPL',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 100,
        currency: 'USD',
        notes: '',
        kind: AssetKind.sell,
        sellPrice: 100,
        purchaseFxRate: 30,
        sellFxRate: 41,
        commission: 2,
      );
      // 100×41 − 100×30 − 2×41
      expect(PortfolioState(assets: [lot]).realizedGainLoss,
          closeTo(1100 - 82, 1e-9));
      // Ele geçen: (100 − 2) × 41
      expect(lot.sellProceedsTRY, closeTo(98 * 41, 1e-9));
    });

    test('satış günü kuru yoksa eski davranış: alım kuru', () {
      final eski = _lot(id: 's1', kind: AssetKind.sell, qty: 1, buy: 100,
          sell: 100, fx: 30, currency: 'USD');
      expect(eski.satisKuru, 30);
      expect(eski.sellProceedsTRY, closeTo(3000, 1e-9));
      expect(PortfolioState(assets: [eski]).realizedGainLoss, 0);
    });

    test('sell_fx_rate yalnız doluyken yazılır, okunur', () {
      final eski = _lot(id: 's1', kind: AssetKind.sell, sell: 1, fx: 30);
      expect(eski.toSupabase().containsKey('sell_fx_rate'), isFalse,
          reason: 'bayrak kapalıyken gövde eskisiyle birebir olmalı '
              '(0110 sunucuda yokken PGRST204)');
      final yeni = _lot(id: 's2', kind: AssetKind.sell, sell: 1, fx: 30,
          sellFx: 41, currency: 'USD');
      final m = yeni.toSupabase();
      expect(m['sell_fx_rate'], 41);
      expect(Asset.fromSupabase(m).sellFxRate, 41);
      expect(Asset.fromSupabase(eski.toSupabase()).sellFxRate, isNull);
      expect(yeni.copyWithDeletedAt(null).sellFxRate, 41);
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
