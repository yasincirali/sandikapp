import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Bugün kartı Birlikte görünümünde BİRLEŞİK defteri anlatır (kullanıcı
/// bulgusu 2026-09-21: "birlikteye gelince günlük kartında giriş yapan
/// müşterinin datası yazıyor").
///
/// İki katman vardı:
///   1. Ana ekran kartı `ownView` ile seçiyordu; `ownView` "ortak değil"
///      demektir ve Birlikte'yi (`_view == null`) de kapsar → kart
///      Birlikte'de `myState` alıyordu. Şimdi yalnızca `_view == ''` kişisel.
///   2. Kart birleşik defteri tek havuzda `aggregatePositions`'a veriyordu;
///      `positionKey` sahip taşımaz, iki sahibin aynı hissesi tek pozisyona
///      düşer (bkz. `aggregatePositionsByOwner`). Defter sahibe göre
///      bölünür (`lotlarSahibeGore`).
Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

void main() {
  // Ben: 10 THYAO @100 → 120; ortak: 10 THYAO @100 → fiyatı henüz yok (0)
  // ve 4 tanesini satmış. Havuzda: 20 alım − 4 satış = 16 lot, temsilci
  // rastgele → ya 1.920 ya 0. Sahibe göre: 1.200 + 0 = 1.200.
  final ben = [
    _lot(userId: 'ben', ticker: 'THYAO', qty: 10, buyPrice: 100, currentPrice: 120),
  ];
  final ortak = [
    _lot(userId: 'ortak', ticker: 'THYAO', qty: 10, buyPrice: 100, currentPrice: 0),
    _lot(
      userId: 'ortak',
      ticker: 'THYAO',
      qty: 4,
      buyPrice: 110,
      currentPrice: 0,
      kind: AssetKind.sell,
    ),
  ];
  final birlesik = [...ben, ...ortak];

  test('lotlarSahibeGore: birleşik defter sahibe göre bölünür', () {
    final g = lotlarSahibeGore(birlesik);
    expect(g.length, 2);
    expect(g.map((l) => l.first.userId).toSet(), {'ben', 'ortak'});
    expect(lotlarSahibeGore(ben).length, 1, reason: 'tek sahip → tek grup');
    expect(lotlarSahibeGore(const []), isEmpty);
  });

  test('Birlikte toplamı = tekil toplamların toplamı (sahiplik sınırı)', () {
    final tekil = ownerScopedTotalValue([ben]) + ownerScopedTotalValue([ortak]);
    expect(ownerScopedTotalValue(lotlarSahibeGore(birlesik)), tekil);
    expect(tekil, 1200.0);
  });

  test('liveTotalTRY birleşik defterde sahipleri havuzlamaz', () {
    final birlikteState = PortfolioState(assets: birlesik);
    expect(DailySummary.liveTotalTRY(birlikteState), 1200.0);
    // Tek sahipli yol değişmedi — kilit ekranı/widget aynı sayıyı görür.
    expect(DailySummary.liveTotalTRY(PortfolioState(assets: ben)), 1200.0);
  });

  test('kart pozisyonları sahibe göre: ortağın satışı benim lotumu düşmez',
      () {
    final sahipler = lotlarSahibeGore(birlesik);
    final pozisyonlar = aggregatePositionsByOwner(
        [for (final lots in sahipler) aktifLotlar(lots)]);
    // İki sahip, iki pozisyon; benimki 10 lot (havuzda 16 olurdu).
    expect(pozisyonlar.length, 2);
    final benim = pozisyonlar.firstWhere((p) => p.representative.userId == 'ben');
    expect(benim.totalQuantity, 10);
  });

  test('kaynak: kart birleşik defteri tek havuzda aggregate etmez', () {
    final kart = File('lib/widgets/bugun_karti.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(kart.contains('aggregatePositions(aktifLotlar(widget.state.assets))'),
        isFalse,
        reason: 'positionKey sahip taşımaz; Birlikte defteri havuzlanmaz');
    expect(kart.contains('lotlarSahibeGore(widget.state.assets)'), isTrue);
    expect(kart.contains('toplamDeger: widget.state.totalValue'), isFalse,
        reason: 'state.totalValue ham listeyi tek havuzda toplar');
    expect(kart.contains('ownerScopedTotalValue(sahipler'), isTrue);
  });
}
