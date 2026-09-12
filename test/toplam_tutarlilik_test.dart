import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Ana ekran ile performans ekranının TOPLAMI aynı olmalı.
///
/// ## Kullanıcı bildirimi (2026-09-12)
/// "Piyasa kapandıktan sonra 2.517.574 gözüküyor ancak ana ekranda
/// 2.519.470 TL olarak gözüküyor, bir tutarsızlık var."
///
/// ## Ölçülen kök sebep
/// İki ekran FARKLI hesap kullanıyordu:
///
///   ana ekran   → `PortfolioState.totalValue`
///                 = ham `activeAssets` üzerinde `quantity * currentPrice`
///   performans  → `ownerScopedTotalValue`
///                 = `aggregatePositions` (net pozisyon)
///
/// `Asset.totalValue` İŞARETSİZ: `quantity * currentPrice`. Satış lot'u
/// da pozitif miktar taşıdığı için ham toplama EKLENİYOR — oysa satış
/// pozisyonu AZALTIR. Aynı şekilde `quantity: 0` temettü satırları da
/// listede duruyor.
///
/// Sonuç: kısmen satılmış bir pozisyonu olan kullanıcıda ana ekran
/// olduğundan YÜKSEK toplam gösteriyordu.
Asset _lot({
  required String id,
  required AssetKind kind,
  required double qty,
  double fiyat = 100,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: 'T',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 90,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      kind: kind,
      addedDate: DateTime(2026, 1, 1),
    );

void main() {
  test('kısmen satılmış pozisyonda iki hesap AYNI sonucu verir', () {
    // 10 al, 4 sat → net 6 lot × 100 TL = 600 TL.
    final defter = [
      _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
      _lot(id: 's1', kind: AssetKind.sell, qty: 4),
    ];
    final state = PortfolioState(assets: defter);

    final performans = ownerScopedTotalValue([defter]);
    expect(performans, closeTo(600, 0.01),
        reason: 'Net pozisyon 6 lot olmalı.');

    expect(state.totalValue, closeTo(performans, 0.01),
        reason: 'Ana ekran toplamı performans ekranından farklı — '
            'satış lot\'u ÇIKARILMAK yerine EKLENİYOR.');
  });

  test('temettü satırı toplama GİRMEZ', () {
    // Temettü nakit hareketidir; `quantity: 0` taşır ama listede durur.
    final defter = [
      _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
      _lot(id: 'd1', kind: AssetKind.dividend, qty: 0),
    ];
    final state = PortfolioState(assets: defter);

    expect(state.totalValue, closeTo(1000, 0.01));
    expect(state.totalValue, closeTo(ownerScopedTotalValue([defter]), 0.01));
  });

  test('tamamen satılmış pozisyon SIFIR değer', () {
    final defter = [
      _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
      _lot(id: 's1', kind: AssetKind.sell, qty: 10),
    ];
    final state = PortfolioState(assets: defter);

    expect(ownerScopedTotalValue([defter]), closeTo(0, 0.01));
    expect(state.totalValue, closeTo(0, 0.01),
        reason: 'Kapanmış pozisyon ana ekranda hâlâ değer taşıyor.');
  });

  test('hiç satış yoksa iki hesap zaten aynıydı', () {
    // Regresyon kapısı: düzeltme basit durumu bozmamalı.
    final defter = [_lot(id: 'a1', kind: AssetKind.buy, qty: 10)];
    final state = PortfolioState(assets: defter);

    expect(state.totalValue, closeTo(1000, 0.01));
    expect(state.totalValue, closeTo(ownerScopedTotalValue([defter]), 0.01));
  });

  test('silinmiş lot her iki hesapta da ELENİR', () {
    final defter = [
      _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
      _lot(id: 'a2', kind: AssetKind.buy, qty: 5)
          .copyWithDeletedAt(DateTime(2026, 2, 1)),
    ];
    final state = PortfolioState(assets: defter);

    expect(state.totalValue, closeTo(1000, 0.01));
    expect(state.totalValue, closeTo(ownerScopedTotalValue([defter]), 0.01));
  });
}
