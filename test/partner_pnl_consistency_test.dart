import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// "Birlikte" sekmesindeki kâr/zarar, tekil sekmelerin toplamına eşit olmalı.
///
/// **Bug:** Birlikte sekmesi tüm sahiplerin lot'larını TEK havuzda
/// `aggregatePositions`'a veriyordu. `positionKey` sahip bilgisi taşımaz
/// (`type|ticker|currency`) — aynı hisseye sahip iki kişinin lot'ları tek
/// pozisyona düşer. O pozisyonun TEK bir `representative` lot'u vardır ve
/// `totalValue = totalQuantity * representative.currentPrice` hesabı
/// herkesin miktarına tek kişinin fiyatını uygular.
///
/// En görünür hâli: bir tarafın fiyatı henüz çekilememişse (currentPrice=0)
/// ve temsilci o lot olursa, `PortfolioState.gainLoss` filtresi
/// (`currentPrice > 0`) birleşmiş pozisyonun TAMAMINI eler — kârda olan
/// ortağın kârı da yok olur.
///
/// **Doğru davranış:** her sahip kendi içinde aggregate edilir, sonra toplanır.
/// [ownerScopedGainLoss] bunu yapar.

Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  AssetKind kind = AssetKind.buy,
  double fx = 1.0,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: currency,
      notes: '',
      isManualPrice: false,
      purchaseFxRate: fx,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

/// Tek sahiplik kapsamında P/L — tekil sekmelerin ("Ben", "Ortak") hesabı.
double _singleOwnerPnl(List<Asset> assets) => PortfolioState(
      assets: aggregatePositions(assets).map((p) => p.asDisplayAsset()).toList(),
    ).gainLoss;

/// BUGGY: tüm sahipleri tek havuzda aggregate eden eski "Birlikte" hesabı.
double _pooledPnl(List<List<Asset>> owners) =>
    _singleOwnerPnl([for (final o in owners) ...o]);

void main() {
  group('birlikte sekmesi kâr/zarar tutarlılığı', () {
    test('iki ortak da kârdayken birlikte de kâr ve tam toplam olmalı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 110,
            currentPrice: 120),
      ];

      expect(_singleOwnerPnl(mine), closeTo(200, 0.01), reason: 'Ben sekmesi');
      expect(_singleOwnerPnl(partner), closeTo(100, 0.01),
          reason: 'Ortak sekmesi');

      final combined = ownerScopedGainLoss([mine, partner]);
      expect(combined, closeTo(300, 0.01));
      expect(combined, greaterThan(0),
          reason: 'iki taraf da kârdayken toplam negatif olamaz');
    });

    test('fiyatı çekilememiş varlık diğer ortağın kârını silmemeli', () {
      // Regresyon: asıl kullanıcı şikâyetinin en sert hâli.
      // Benim varlığımın fiyatı henüz gelmedi (currentPrice=0) → benim P/L'im 0.
      // Ortak aynı hisseden kârda (+700).
      final mine = [
        _lot(
            userId: 'me', ticker: 'X', qty: 10, buyPrice: 100, currentPrice: 0),
      ];
      final partner = [
        _lot(
            userId: 'p1', ticker: 'X', qty: 10, buyPrice: 50, currentPrice: 120),
      ];

      expect(_singleOwnerPnl(mine), closeTo(0, 0.01));
      expect(_singleOwnerPnl(partner), closeTo(700, 0.01));

      // Eski havuzlanmış hesap ortağın kârını tamamen yutuyordu.
      expect(_pooledPnl([mine, partner]), closeTo(0, 0.01),
          reason: 'bug davranışı: birleşen pozisyon fiyatsız temsilci yüzünden elenir');

      // Düzeltilmiş hesap parçaların toplamını verir.
      expect(ownerScopedGainLoss([mine, partner]), closeTo(700, 0.01));
    });

    test('aynı hissede farklı maliyetler ortaklanmamalı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'ASELS',
            qty: 5,
            buyPrice: 50,
            currentPrice: 60),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'ASELS',
            qty: 15,
            buyPrice: 80,
            currentPrice: 60),
      ];

      expect(_singleOwnerPnl(mine), closeTo(50, 0.01));
      expect(_singleOwnerPnl(partner), closeTo(-300, 0.01));
      expect(ownerScopedGainLoss([mine, partner]), closeTo(-250, 0.01));
    });

    test('bir ortağın satışı diğerinin pozisyonunu etkilememeli', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120,
            kind: AssetKind.sell),
      ];

      expect(_singleOwnerPnl(partner), closeTo(0, 0.01),
          reason: 'pozisyon kapandı');
      expect(ownerScopedGainLoss([mine, partner]), closeTo(200, 0.01));
    });

    test('üç taraf: birlikte her zaman parçaların toplamı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final p1 = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 4,
            buyPrice: 130,
            currentPrice: 120),
        _lot(
            userId: 'p1',
            ticker: 'ASELS',
            qty: 2,
            buyPrice: 50,
            currentPrice: 55),
      ];
      final p2 = [
        _lot(
            userId: 'p2',
            ticker: 'ASELS',
            qty: 8,
            buyPrice: 40,
            currentPrice: 55),
      ];

      final parts =
          _singleOwnerPnl(mine) + _singleOwnerPnl(p1) + _singleOwnerPnl(p2);
      expect(ownerScopedGainLoss([mine, p1, p2]), closeTo(parts, 0.01));
    });

    test('tek sahiplik varken davranış değişmez', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
        _lot(
            userId: 'me',
            ticker: 'ASELS',
            qty: 5,
            buyPrice: 40,
            currentPrice: 55),
      ];
      // Ortak yokken sahip-bazlı hesap eski hesapla birebir aynı olmalı.
      expect(ownerScopedGainLoss([mine]), closeTo(_singleOwnerPnl(mine), 0.01));
    });
  });

  group('sahip-bazlı toplam değer', () {
    test('birlikte toplam değer parçaların toplamı', () {
      final mine = [
        _lot(
            userId: 'me', ticker: 'X', qty: 10, buyPrice: 100, currentPrice: 0),
      ];
      final partner = [
        _lot(
            userId: 'p1', ticker: 'X', qty: 10, buyPrice: 50, currentPrice: 120),
      ];
      // Fiyatsız lot değere 0 katkı verir; ortağınki 10*120 = 1200.
      expect(ownerScopedTotalValue([mine, partner]), closeTo(1200, 0.01));
    });
  });
}
