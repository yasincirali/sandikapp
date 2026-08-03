import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Komisyon maliyete dahil edilmezse kâr olduğundan yüksek görünür.
/// Bu testler komisyonun maliyete eklendiğini ve aggregation sırasında
/// KAYBOLMADIĞINI doğrular.

Asset _lot({
  required double qty,
  required double buyPrice,
  required double currentPrice,
  double commission = 0,
  double fx = 1.0,
  String currency = 'TRY',
  AssetKind kind = AssetKind.buy,
  String ticker = 'THYAO',
}) =>
    Asset(
      id: '$ticker-${kind.name}-$qty-$buyPrice-$commission',
      userId: 'u1',
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
      commission: commission,
    );

void main() {
  group('komisyon maliyete girer', () {
    test('komisyonsuz davranış değişmez (geriye dönük uyumluluk)', () {
      final a = _lot(qty: 10, buyPrice: 100, currentPrice: 120);
      expect(a.totalCost, closeTo(1000, 0.01));
      expect(a.totalCostTRY, closeTo(1000, 0.01));
      expect(a.gainLoss, closeTo(200, 0.01));
    });

    test('komisyon maliyeti artırır, kârı azaltır', () {
      final a =
          _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 25);
      expect(a.totalCost, closeTo(1025, 0.01));
      // Kâr 200 değil 175 — gerçek rakam.
      expect(a.gainLoss, closeTo(175, 0.01));
    });

    test('komisyon alım kurundan TRY\'ye çevrilir', () {
      // 10 adet × 100 USD + 20 USD komisyon = 1020 USD, kur 30 → 30.600 TL
      final a = _lot(
          qty: 10,
          buyPrice: 100,
          currentPrice: 120,
          commission: 20,
          fx: 30,
          currency: 'USD');
      expect(a.totalCostTRY, closeTo(30600, 0.01));
    });

    test('komisyon kâr yüzdesini de düşürür', () {
      final without = _lot(qty: 10, buyPrice: 100, currentPrice: 110);
      final with_ =
          _lot(qty: 10, buyPrice: 100, currentPrice: 110, commission: 50);
      expect(without.gainLossPercentage, closeTo(10.0, 0.01));
      expect(with_.gainLossPercentage, lessThan(10.0));
    });
  });

  group('aggregation komisyonu korur', () {
    test('çok lotlu pozisyonda komisyonlar toplanır', () {
      final positions = aggregatePositions([
        _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 15),
        _lot(qty: 5, buyPrice: 110, currentPrice: 120, commission: 10),
      ]);
      expect(positions, hasLength(1));
      final p = positions.single;
      expect(p.totalCommission, closeTo(25, 0.01));
      // 10*100 + 5*110 = 1550, + 25 komisyon = 1575
      expect(p.totalCost, closeTo(1575, 0.01));
    });

    test('asDisplayAsset komisyonu taşır — maliyet düşmez', () {
      final p = aggregatePositions([
        _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 40),
      ]).single;
      final display = p.asDisplayAsset();
      expect(display.commission, closeTo(40, 0.01),
          reason: 'komisyon taşınmazsa Asset\'e çevrildiği an kaybolur');
      expect(display.totalCost, closeTo(p.totalCost, 0.01));
    });

    test('satış komisyonu da maliyete yansır', () {
      final positions = aggregatePositions([
        _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 15),
        _lot(
            qty: 4,
            buyPrice: 100,
            currentPrice: 120,
            commission: 8,
            kind: AssetKind.sell),
      ]);
      final p = positions.single;
      expect(p.totalQuantity, closeTo(6, 0.0001), reason: '10 alım - 4 satım');
      expect(p.totalCommission, closeTo(23, 0.01),
          reason: 'alış 15 + satış 8, ikisi de cepten çıktı');
    });

    test('sahip-bazlı toplamda komisyon korunur', () {
      final mine = [
        _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 20),
      ];
      final partner = [
        _lot(qty: 10, buyPrice: 100, currentPrice: 120, commission: 30),
      ];
      // Her biri 200 brüt kâr, komisyon sonrası 180 ve 170 → 350
      final combined = ownerScopedGainLoss([mine, partner]);
      expect(combined, closeTo(350, 0.01));
    });
  });
}
