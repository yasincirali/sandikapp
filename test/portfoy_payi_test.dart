import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_payi.dart';

/// "Portföyündeki payı" (Ar-Ge 11 Kas 19:04 #7): payda Portföy halkasının
/// toplamıyla aynı — açık pozisyonlar, `toTRY(totalValue, currency)`.

Asset _lot(String ticker, double qty, double fiyat,
        {String currency = 'TRY',
        AssetType type = AssetType.hisse,
        AssetKind kind = AssetKind.buy,
        String id = ''}) =>
    Asset(
      id: id.isEmpty ? '$ticker-$qty-${kind.name}' : id,
      userId: 'ben',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: fiyat,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

double _toTRY(double tutar, String pb) => pb == 'USD' ? tutar * 40 : tutar;

void main() {
  test('pay = değer / açık pozisyonların TL toplamı (kur çevrili)', () {
    final defter = [
      _lot('THYAO', 100, 300), // 30.000
      _lot('AAPL', 10, 25, currency: 'USD'), // 250 $ × 40 = 10.000
    ];
    expect(portfoyPayi(degerTRY: 30000, defter: defter, toTRY: _toTRY),
        closeTo(0.75, 1e-9));
    expect(portfoyPayi(degerTRY: 10000, defter: defter, toTRY: _toTRY),
        closeTo(0.25, 1e-9));
  });

  test('tamamen satılmış pozisyon paydaya girmez (aktifLotlar)', () {
    final defter = [
      _lot('THYAO', 100, 300),
      _lot('ASELS', 50, 100),
      _lot('ASELS', 50, 100, kind: AssetKind.sell),
    ];
    expect(portfoyPayi(degerTRY: 30000, defter: defter, toTRY: _toTRY),
        closeTo(1.0, 1e-9));
  });

  test('mevduat halkada olduğu için paydada da var', () {
    final defter = [
      _lot('THYAO', 100, 300),
      _lot('MEVDUAT', 1, 10000, type: AssetType.mevduat),
    ];
    expect(portfoyPayi(degerTRY: 30000, defter: defter, toTRY: _toTRY),
        closeTo(0.75, 1e-9));
  });

  test('değer ya da toplam ≤ 0 → null (uydurma oran yok)', () {
    expect(
        portfoyPayi(
            degerTRY: 0, defter: [_lot('THYAO', 1, 1)], toTRY: _toTRY),
        isNull);
    expect(portfoyPayi(degerTRY: 100, defter: const [], toTRY: _toTRY),
        isNull);
    expect(
        portfoyPayi(
            degerTRY: 100, defter: [_lot('THYAO', 1, 0)], toTRY: _toTRY),
        isNull);
  });

  test('bayat değer toplamı aşarsa 1\'e kırpılır', () {
    expect(
        portfoyPayi(
            degerTRY: 500, defter: [_lot('THYAO', 1, 100)], toTRY: _toTRY),
        1.0);
  });
}
