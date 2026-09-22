import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// **Değişmez:** tür dağılımının toplamı üst karttaki toplama EŞİT olmalı —
/// `Σ parça == bütün` (bkz. "Kırılım Değişmezi").
///
/// ## Bulgu (denetim, 2026-09-22)
/// Ana ekrandaki dağılım listesi (`_buildDistributionList`) türleri HAM
/// `state.assets` üzerinden topluyordu; payda (`state.totalValue`) ise net
/// pozisyonlardan geliyor. Satış lot'u hem kendi türüne ekleniyor hem de
/// paydadan düşük olduğu için oran 1.0'ı AŞIYORDU:
///
///   * kısmi satış (10 al, 4 sat)      → oran 2,33
///   * iki sahipli defter (ortak satmış) → oran 1,50
///
/// Sonuç: yüzdeler %100'ü aşıyor, çubuklar taşıyor.
///
/// Bu hata benim `totalValue` düzeltmemden ÖNCE de vardı; düzeltme onu
/// görünür kıldı çünkü payda artık doğru. İkisi aynı kuraldan beslenmezse
/// bir sonraki değişiklikte yeniden ayrışır.
Asset _lot({
  required String id,
  String userId = 'ben',
  String ticker = 'THYAO',
  AssetType type = AssetType.hisse,
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
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
    );

/// `home_screen._buildDistributionList` ile AYNI hesap.
double _dagilimToplami(PortfolioState state) {
  double t = 0;
  for (final p in aggregatePositionsByOwner(
      [for (final lots in lotlarSahibeGore(state.assets)) aktifLotlar(lots)])) {
    final a = p.asDisplayAsset();
    t += state.toTRY(a.totalValue, a.currency);
  }
  return t;
}

void main() {
  test('kısmi satış: dağılım toplamı == üst kart toplamı', () {
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
    expect(_dagilimToplami(st), closeTo(st.totalValue, 0.01),
        reason: 'eskiden oran 2,33 idi — yüzdeler %100\'ü aşıyordu');
    expect(st.totalValue, 720.0);
  });

  test('iki sahipli defter: sahip sınırı dağılımda da korunur', () {
    final st = PortfolioState(assets: [
      _lot(id: 'b1', userId: 'ben', qty: 10, buy: 100, cur: 120),
      _lot(id: 'o1', userId: 'ortak', qty: 5, buy: 100, cur: 120),
      _lot(
          id: 'o2',
          userId: 'ortak',
          qty: 3,
          buy: 100,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130),
    ]);
    expect(_dagilimToplami(st), closeTo(st.totalValue, 0.01),
        reason: 'eskiden oran 1,50 idi');
    expect(st.totalValue, 1440.0, reason: 'ben 10 + ortak 2 = 12 lot × 120');
  });

  test('çok türlü defter: her tür kendi payını alır, toplam tutar', () {
    final st = PortfolioState(assets: [
      _lot(id: 'h1', ticker: 'THYAO', type: AssetType.hisse, qty: 10, cur: 120),
      _lot(id: 'a1', ticker: 'ALTIN_GRAM', type: AssetType.altin, qty: 5,
          buy: 2000, cur: 2400),
      _lot(id: 'd1', ticker: 'USD', type: AssetType.doviz, qty: 100, buy: 30,
          cur: 42),
    ]);
    expect(_dagilimToplami(st), closeTo(st.totalValue, 0.01));

    // Türlerin ayrı ayrı toplamı da bütünü vermeli.
    final turler = <AssetType, double>{};
    for (final p in aggregatePositionsByOwner(
        [for (final l in lotlarSahibeGore(st.assets)) aktifLotlar(l)])) {
      final a = p.asDisplayAsset();
      turler[a.type] = (turler[a.type] ?? 0) + st.toTRY(a.totalValue, a.currency);
    }
    final toplam = turler.values.fold<double>(0, (s, v) => s + v);
    expect(toplam, closeTo(st.totalValue, 0.01),
        reason: 'Σ tür == bütün, yapısal olarak');
  });

  test('tam satış: kapanan pozisyon dağılımda da yok', () {
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
    expect(_dagilimToplami(st), 0.0);
    expect(st.totalValue, 0.0);
  });

  test('oran HER ZAMAN 0..1 aralığında', () {
    for (final st in [
      PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 's1', qty: 4, buy: 100, cur: 120, kind: AssetKind.sell,
            sellPrice: 130),
      ]),
      PortfolioState(assets: [
        _lot(id: 'b1', userId: 'ben', qty: 10, buy: 100, cur: 120),
        _lot(id: 'o1', userId: 'ortak', qty: 5, buy: 100, cur: 120),
        _lot(id: 'o2', userId: 'ortak', qty: 3, buy: 100, cur: 120,
            kind: AssetKind.sell, sellPrice: 130),
      ]),
    ]) {
      if (st.totalValue <= 0) continue;
      final oran = _dagilimToplami(st) / st.totalValue;
      expect(oran, lessThanOrEqualTo(1.0 + 1e-9),
          reason: 'oran 1.0\'ı aşarsa çubuk taşar, yüzde %100\'ü geçer');
      expect(oran, greaterThan(0.0));
    }
  });
}
