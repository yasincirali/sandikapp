import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Kâr/zarar denetimi (2026-09-22) — kullanıcı talebi: "varlık para
/// tutarlılık ister".
///
/// ## Bulunan üç hata
///
/// **1. Satış lot'ları hem değere hem maliyete sayılıyordu.**
/// `totalValue` `aggregatePositions` kullanıyordu (satışı düşer), ama
/// `totalCost` ve `_trackedValue` ham `activeAssets` üzerinden gidiyordu.
/// Satış lot'unun `currentPrice`'ı dolu olduğu için fiyat filtresini
/// geçiyor ve "elde duran varlık" sayılıyordu.
///
/// **2. Sahip sınırı yoktu.** `positionKey` sahip taşımaz; Birlikte
/// defterinde iki kişinin aynı hissesi tek pozisyona düşüyordu
/// (bkz. `aggregatePositionsByOwner`). Aynı hata sınıfı toplam DEĞERDE
/// daha önce kapatılmıştı, kâr/zararda açık kalmıştı.
///
/// **3. `ownerScopedGainLoss` ölü koddu** — doğru hesap yazılmış ama
/// hiçbir ekran ona bağlanmamıştı.
///
/// Üçünün de çözümü aynıydı: `PortfolioState`'in üç sayısını (değer,
/// maliyet, kâr) TEK kümeden beslemek.
Asset _lot({
  required String id,
  String userId = 'ben',
  String ticker = 'THYAO',
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double dividend = 0,
  double commission = 0,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buy,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
      dividendAmount: dividend,
      commission: commission,
    );

void main() {
  group('BULGU 1 — satış lot\'u maliyete sayılmaz', () {
    test('kısmi satış: taban AÇIK pozisyonun maliyeti', () {
      // 10 al @100, 4 sat @130 → elde 6 lot, güncel 120.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 's1',
            qty: 4,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
      ]);

      expect(st.totalValue, 720.0, reason: '6 × ₺120');
      expect(st.totalCost, 600.0,
          reason: 'eskiden ₺1.400 idi — satış lot\'u da sayılıyordu');
      expect(st.capitalGainLoss, 120.0, reason: '6 × (120 − 100)');
      expect(st.gainLossPercentage, closeTo(20.0, 0.001));
    });

    test('REGRESYON: yalnızca satış lot\'u olan defter kâr göstermez', () {
      // Denetimdeki en net kanıt: elde hiçbir şey yokken +₺80 / %20.
      final st = PortfolioState(assets: [
        _lot(
            id: 's1',
            qty: 4,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
      ]);

      expect(st.totalValue, 0.0);
      expect(st.totalCost, 0.0,
          reason: 'eskiden ₺400 — elde olmayan lot maliyete giriyordu');
      expect(st.capitalGainLoss, 0.0,
          reason: 'eskiden +₺80 — olmayan varlıktan kâr');
      expect(st.gainLossPercentage, 0.0,
          reason: 'eskiden %20 — payda uydurmaydı');
    });

    test('tam satış: pozisyon kapanır, taban sıfırlanır', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 's1',
            qty: 10,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
      ]);
      expect(st.totalValue, 0.0);
      expect(st.totalCost, 0.0);
      expect(st.capitalGainLoss, 0.0);
      // Satıştan gerçekleşen kâr AYRI taşınır — kaybolmaz.
      expect(st.realizedGainLoss, 300.0, reason: '10 × (130 − 100)');
    });
  });

  group('BULGU 2 — sahip sınırı kâr/zararda da korunur', () {
    // Ben 10 lot; ortak 5 al + 3 sat (net 2).
    final defter = [
      _lot(id: 'b1', userId: 'ben', qty: 10, buy: 100, cur: 120),
      _lot(id: 'o1', userId: 'ortak', qty: 5, buy: 100, cur: 120),
      _lot(
          id: 'o2',
          userId: 'ortak',
          qty: 3,
          buy: 110,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130),
    ];

    test('ortağın satışı benim lot\'umu düşürmez', () {
      final st = PortfolioState(assets: defter);
      final sahipBazli =
          ownerScopedCapitalGainLoss(lotlarSahibeGore(defter));
      expect(st.capitalGainLoss, closeTo(sahipBazli, 0.001),
          reason: 'state havuzlamamalı');
    });

    test('Σ parça == bütün (değer)', () {
      final ben = defter.where((a) => a.userId == 'ben').toList();
      final ortak = defter.where((a) => a.userId == 'ortak').toList();

      final tBen = PortfolioState(assets: ben).totalValue;
      final tOrtak = PortfolioState(assets: ortak).totalValue;
      final tHepsi = PortfolioState(assets: defter).totalValue;
      expect(tBen + tOrtak, closeTo(tHepsi, 0.001));
    });

    test('Σ parça == bütün (maliyet ve kâr)', () {
      final ben = defter.where((a) => a.userId == 'ben').toList();
      final ortak = defter.where((a) => a.userId == 'ortak').toList();

      final cBen = PortfolioState(assets: ben).totalCost;
      final cOrtak = PortfolioState(assets: ortak).totalCost;
      expect(cBen + cOrtak,
          closeTo(PortfolioState(assets: defter).totalCost, 0.001));

      final kBen = PortfolioState(assets: ben).capitalGainLoss;
      final kOrtak = PortfolioState(assets: ortak).capitalGainLoss;
      expect(kBen + kOrtak,
          closeTo(PortfolioState(assets: defter).capitalGainLoss, 0.001));
    });
  });

  group('BULGU 3 — sahip sınırlı hesaplar KULLANILIYOR', () {
    test('ownerScopedCostBasis ve capitalGainLoss aynı kümeyi kullanır', () {
      final defter = [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 'b2', ticker: 'XXXX', qty: 5, buy: 200, cur: 0),
      ];
      final lots = lotlarSahibeGore(defter);
      // Fiyatsız lot İKİSİNDEN de düşer — taban ile pay ayrışmamalı.
      expect(ownerScopedCostBasis(lots), 1000.0);
      expect(ownerScopedCapitalGainLoss(lots), 200.0);
    });

    test('değer = maliyet + sermaye kazancı (yapısal denklik)', () {
      final defter = [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 'b2', ticker: 'ASELS', qty: 4, buy: 50, cur: 45),
        _lot(
            id: 's1',
            qty: 3,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
      ];
      final st = PortfolioState(assets: defter);
      expect(st.totalCost + st.capitalGainLoss, closeTo(st.totalValue, 0.001),
          reason: 'üç sayı tek kümeden beslenmezse bu denklik kırılır');
    });
  });

  group('korunan davranışlar', () {
    test('komisyon maliyete dahil', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, commission: 25),
      ]);
      expect(st.totalCost, 1025.0);
      expect(st.capitalGainLoss, 175.0);
    });

    test('fiyatsız lot taban DIŞI ama değer içi değil', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 'b2', ticker: 'XXXX', qty: 5, buy: 200, cur: 0),
      ]);
      expect(st.totalCost, 1000.0, reason: 'fiyatı bilinmeyen ölçüme girmez');
      expect(st.capitalGainLoss, 200.0);
    });

    test('temettü toplam getiriye girer, sermaye kazancına girmez', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 'd1',
            qty: 0,
            buy: 0,
            cur: 0,
            kind: AssetKind.dividend,
            dividend: 50),
      ]);
      expect(st.capitalGainLoss, 200.0, reason: 'yalnızca fiyat hareketi');
      expect(st.totalDividend, 50.0);
      expect(st.gainLoss, 250.0, reason: 'toplam getiri = kazanç + temettü');
    });
  });
}
