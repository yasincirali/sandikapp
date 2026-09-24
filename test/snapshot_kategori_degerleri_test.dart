import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Denetim F12 (2026-09-23): günlük anlık görüntü ham lot defterini
/// topluyordu; satış satırı da `totalValue` taşıdığı için satılmış hisse
/// portföyde duruyormuş gibi sayılıyordu. Yıllık özet ve dönem push'u bu
/// değerlerden hesaplanır.
void main() {
  Asset lot(String id, String ticker, double qty,
          {AssetKind kind = AssetKind.buy, double fiyat = 120}) =>
      Asset(
        id: id,
        userId: 'u1',
        name: ticker,
        ticker: ticker,
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: 1.0,
        currentPrice: fiyat,
        addedDate: DateTime(2026, 1, 1),
        kind: kind,
      );

  test('satılmış pozisyon anlık görüntüye girmez', () {
    final s = PortfolioState(assets: [
      lot('a1', 'THYAO', 10),
      lot('a2', 'THYAO', 10, kind: AssetKind.sell),
      lot('b1', 'ASELS', 5),
    ]);
    expect(snapshotKategoriDegerleri(s), {'hisse': 5 * 120.0});
    expect(snapshotKategoriDegerleri(s)['hisse'], s.totalValue,
        reason: 'anlık görüntü ekrandaki toplamla aynı kurala uyar');
  });

  test('kısmi satışta kalan miktar sayılır', () {
    final s = PortfolioState(assets: [
      lot('a1', 'THYAO', 10),
      lot('a2', 'THYAO', 4, kind: AssetKind.sell),
    ]);
    expect(snapshotKategoriDegerleri(s)['hisse'], 6 * 120.0);
  });
}
