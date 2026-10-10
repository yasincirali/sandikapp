import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Ücretsiz varlık kotası "bugün kaç varlığın var" sayar.
///
/// yasin (2026-10-08): *"aktif 5 varlığı olan eleman 6.'yı ekleyemiyor"*.
/// Kota ham defteri sayıyordu: tamamen satılmış pozisyonlar ve Birlikte
/// görünümündeki ortak lot'ları da kotaya giriyordu.
Asset _lot(String id, String ticker, AssetKind kind, double qty,
        {String userId = 'u1', DateTime? silindi, String? sozlesme}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      addedDate: DateTime(2026, 1, 1),
      deletedAt: silindi,
      sozlesmeId: sozlesme,
    );

void main() {
  test('5 açık varlık + 2 satılmış + ortağın 3 varlığı = kota 5', () {
    final defter = [
      for (final t in ['A', 'B', 'C', 'D', 'E'])
        _lot('b$t', '$t.IS', AssetKind.buy, 10),
      _lot('bX', 'X.IS', AssetKind.buy, 10),
      _lot('sX', 'X.IS', AssetKind.sell, 10),
      _lot('bY', 'Y.IS', AssetKind.buy, 5),
      _lot('sY', 'Y.IS', AssetKind.sell, 5),
      for (final t in ['P', 'Q', 'R'])
        _lot('o$t', '$t.IS', AssetKind.buy, 1, userId: 'ortak'),
    ];
    final k = kotaAnahtarlari(defter, 'u1');
    expect(k, hasLength(5));
    expect(k, isNot(contains(kotaAnahtari(AssetType.hisse, 'X.IS', 'TRY'))));
    expect(k, isNot(contains(kotaAnahtari(AssetType.hisse, 'P.IS', 'TRY'))));
  });

  test('kısmen satılmış pozisyon sayılır, silinmiş lot sayılmaz', () {
    final defter = [
      _lot('b1', 'A.IS', AssetKind.buy, 10),
      _lot('s1', 'A.IS', AssetKind.sell, 4),
      _lot('b2', 'B.IS', AssetKind.buy, 10, silindi: DateTime(2026, 2, 1)),
    ];
    expect(kotaAnahtarlari(defter, 'u1'),
        {kotaAnahtari(AssetType.hisse, 'A.IS', 'TRY')});
  });

  test('aynı varlığa ikinci lot kotayı artırmaz', () {
    final defter = [
      _lot('b1', 'A.IS', AssetKind.buy, 10),
      _lot('b2', 'A.IS', AssetKind.buy, 3),
    ];
    expect(kotaAnahtarlari(defter, 'u1'), hasLength(1));
  });

  test('BES sözleşmesinin üç fonu kotada TEK varlık (2026-10-10)', () {
    final defter = [
      _lot('f1', 'TEFAS:AAA', AssetKind.buy, 10, sozlesme: 'bes1'),
      _lot('f2', 'TEFAS:BBB', AssetKind.buy, 10, sozlesme: 'bes1'),
      _lot('f3', 'TEFAS:CCC', AssetKind.buy, 10, sozlesme: 'bes1'),
      _lot('h', 'A.IS', AssetKind.buy, 10),
    ];
    expect(kotaAnahtarlari(defter, 'u1'), hasLength(2));
    expect(
        kotaAnahtari(AssetType.hisse, 'X', 'TRY', sozlesmeId: 'bes1'),
        'sozlesme|bes1');
    // Sözleşmesiz anahtar eski biçimde kalır.
    expect(kotaAnahtari(AssetType.hisse, 'A.IS', 'TRY'), 'hisse|A.IS|TRY');
  });
}
