import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Temettü takibi.
///
/// En kritik değişmez: **temettü satırı miktara ASLA girmez.** Kod tabanında
/// birçok yerde `isSell ? -qty : +qty` kalıbı vardı — temettü satırı oraya
/// düşerse hayalet lot olarak pozisyonu şişirirdi.

Asset _buy({
  double qty = 10,
  double price = 100,
  double current = 120,
  double commission = 0,
  String ticker = 'THYAO',
  double fx = 1.0,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$ticker-buy-$qty-$price',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: price,
      currency: currency,
      notes: '',
      isManualPrice: false,
      purchaseFxRate: fx,
      currentPrice: current,
      addedDate: DateTime(2026, 1, 1),
      commission: commission,
    );

Asset _dividend({
  required double amount,
  String ticker = 'THYAO',
  double fx = 1.0,
  String currency = 'TRY',
  DateTime? paidAt,
}) =>
    Asset(
      id: '$ticker-div-$amount-${paidAt?.millisecondsSinceEpoch ?? 0}',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      // Provider da böyle yazar: miktar 0, fiyat 0.
      quantity: 0,
      purchasePrice: 0,
      currency: currency,
      notes: '',
      isManualPrice: false,
      purchaseFxRate: fx,
      currentPrice: 120,
      addedDate: paidAt ?? DateTime(2026, 6, 1),
      kind: AssetKind.dividend,
      dividendAmount: amount,
    );

Asset _sell({double qty = 10, String ticker = 'THYAO'}) => Asset(
      id: '$ticker-sell-$qty',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 7, 1),
      kind: AssetKind.sell,
    );

void main() {
  group('temettü miktara girmez', () {
    test('temettü satırı pozisyon miktarını değiştirmez', () {
      final withoutDiv = aggregatePositions([_buy(qty: 10)]).single;
      final withDiv =
          aggregatePositions([_buy(qty: 10), _dividend(amount: 500)]).single;

      expect(withDiv.totalQuantity, closeTo(10, 0.0001),
          reason: 'temettü hayalet lot olarak eklenmemeli');
      expect(withDiv.totalQuantity, closeTo(withoutDiv.totalQuantity, 0.0001));
    });

    test('temettü ağırlıklı maliyeti bozmaz', () {
      final withDiv =
          aggregatePositions([_buy(qty: 10, price: 100), _dividend(amount: 500)])
              .single;
      expect(withDiv.weightedPurchasePrice, closeTo(100, 0.01),
          reason: 'purchasePrice=0 olan temettü ortalamaya karışmamalı');
      expect(withDiv.totalCost, closeTo(1000, 0.01));
    });

    test('temettü portföy toplam değerine eklenmez', () {
      // Temettü nakit; hisse değeri değil. quantity=0 olduğu için 0 katkı.
      final state = PortfolioState(
          assets: [_buy(qty: 10, current: 120), _dividend(amount: 500)]);
      expect(state.totalValue, closeTo(1200, 0.01));
    });

    test('isQuantityNeutral temettü ve deleteLog için true', () {
      expect(_dividend(amount: 100).isQuantityNeutral, isTrue);
      expect(_buy().isQuantityNeutral, isFalse);
      expect(_sell().isQuantityNeutral, isFalse);
    });
  });

  group('temettü yalnızca hisseye özgü', () {
    Asset ofType(AssetType t) => Asset(
          id: 't-${t.name}',
          userId: 'u1',
          name: t.label,
          ticker: 'X',
          type: t,
          quantity: 1,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 110,
          addedDate: DateTime(2026, 1, 1),
        );

    test('hisse temettü destekler', () {
      expect(ofType(AssetType.hisse).supportsDividend, isTrue);
    });

    test('diğer türler desteklemez', () {
      // Altın/döviz/emtia temettü dağıtmaz; mevduatın getirisi faizdir.
      // Fon dağıtım yapabilir ama TEFAS fiyatına yansır → çift sayım olurdu.
      for (final t in [
        AssetType.fon,
        AssetType.doviz,
        AssetType.altin,
        AssetType.emtia,
        AssetType.mevduat,
        AssetType.diger,
      ]) {
        expect(ofType(t).supportsDividend, isFalse,
            reason: '${t.label} için temettü butonu görünmemeli');
      }
    });
  });

  group('temettü getiriye eklenir', () {
    test('toplam getiri = sermaye kazancı + temettü', () {
      final state = PortfolioState(assets: [
        _buy(qty: 10, price: 100, current: 120), // +200 sermaye
        _dividend(amount: 500),
      ]);
      expect(state.capitalGainLoss, closeTo(200, 0.01));
      expect(state.totalDividend, closeTo(500, 0.01));
      expect(state.gainLoss, closeTo(700, 0.01));
    });

    test('temettüsüz portföyde davranış değişmez', () {
      final state =
          PortfolioState(assets: [_buy(qty: 10, price: 100, current: 120)]);
      expect(state.totalDividend, 0);
      expect(state.gainLoss, closeTo(state.capitalGainLoss, 0.01));
      expect(state.gainLoss, closeTo(200, 0.01));
    });

    test('zarardaki pozisyonu temettü kâra çevirebilir', () {
      final state = PortfolioState(assets: [
        _buy(qty: 10, price: 100, current: 95), // -50 sermaye
        _dividend(amount: 200),
      ]);
      expect(state.capitalGainLoss, closeTo(-50, 0.01));
      expect(state.gainLoss, closeTo(150, 0.01),
          reason: 'temettü dahil edilince net pozitif');
    });

    test('temettü ödeme günü kuruyla TRY\'ye çevrilir', () {
      // 100 USD temettü, ödeme günü kuru 35 → 3500 TL
      final d = _dividend(amount: 100, fx: 35, currency: 'USD');
      expect(d.dividendTRY, closeTo(3500, 0.01));
    });

    test('fiyatı çekilememiş varlığın temettüsü yine sayılır', () {
      // Temettü realize edilmiş gelirdir; fiyat filtresine takılmamalı.
      final unpriced = Asset(
        id: 'x',
        userId: 'u1',
        name: 'X',
        ticker: 'X',
        type: AssetType.hisse,
        quantity: 10,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 0, // fiyat yok
        addedDate: DateTime(2026, 1, 1),
      );
      final state =
          PortfolioState(assets: [unpriced, _dividend(amount: 300, ticker: 'X')]);
      expect(state.capitalGainLoss, closeTo(0, 0.01),
          reason: 'fiyatsız varlık sermaye kazancına girmez');
      expect(state.gainLoss, closeTo(300, 0.01),
          reason: 'ama temettü cebe girdi, sayılmalı');
    });
  });

  group('satılmış pozisyonun temettüsü kaybolmaz', () {
    test('tamamen satılan hissenin temettüsü toplamda kalır', () {
      // 10 alım, 10 satım → pozisyon kapandı, aggregate listeden düşer.
      final lots = [_buy(qty: 10), _sell(qty: 10), _dividend(amount: 400)];
      expect(aggregatePositions(lots), isEmpty,
          reason: 'kapanan pozisyon listede olmamalı');
      // Ama temettü ham lot'lardan hesaplanır.
      expect(totalDividendTRY(lots), closeTo(400, 0.01));
    });
  });

  group('ortak sekmeleriyle tutarlılık', () {
    test('birlikte getiri temettüleri de toplar', () {
      final mine = [_buy(qty: 10, price: 100, current: 120), // +200
        _dividend(amount: 100)];
      final partner = [_buy(qty: 10, price: 110, current: 120), // +100
        _dividend(amount: 50)];

      // 200 + 100 (temettü) + 100 + 50 = 450
      expect(ownerScopedGainLoss([mine, partner]), closeTo(450, 0.01));
    });

    test('birlikte toplam parçaların toplamına eşit', () {
      final mine = [_buy(qty: 10), _dividend(amount: 100)];
      final partner = [_buy(qty: 5, price: 90), _dividend(amount: 60)];
      final parts =
          ownerScopedGainLoss([mine]) + ownerScopedGainLoss([partner]);
      expect(ownerScopedGainLoss([mine, partner]), closeTo(parts, 0.01));
    });
  });
}
