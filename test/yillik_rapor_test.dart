import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';

/// Yıllık kâr, temettü ve masraf raporu (Premium, 2026-10-10).
///
/// Kilitler: ham defter (kapanmış pozisyonun satışı da girer), yalnız kendi
/// lotlar, silinen satır düşer, satış fiyatsız eski satır uydurulmaz,
/// stopaj yalnız bilinen orandan, ABD satışları ayrı toplanır.
Asset _lot(
  String id,
  AssetKind kind, {
  String ticker = 'THYAO.IS',
  String userId = 'u1',
  double qty = 10,
  double fiyat = 100,
  double? satis,
  double kur = 1,
  double? satisKuru,
  double komisyon = 0,
  double temettu = 0,
  DateTime? tarih,
  DateTime? silindi,
  String? alt,
  String para = 'TRY',
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      subCategory: alt,
      quantity: qty,
      purchasePrice: fiyat,
      currency: para,
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      purchaseFxRate: kur,
      sellFxRate: satisKuru,
      commission: komisyon,
      dividendAmount: temettu,
      addedDate: tarih ?? DateTime(2025, 6, 1),
      deletedAt: silindi,
    );

void main() {
  test('kapanmış pozisyonun satışı rapordadır; kâr = satış − maliyet − komisyon',
      () {
    final r = yillikRapor(
      lotlar: [
        _lot('b', AssetKind.buy, komisyon: 5, tarih: DateTime(2025, 1, 2)),
        _lot('s', AssetKind.sell,
            satis: 130, komisyon: 7, tarih: DateTime(2025, 3, 4)),
      ],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: 0.15,
    );
    expect(r.satislar, hasLength(1));
    expect(r.satislar.single.karTry, closeTo(10 * 130 - 10 * 100 - 7, 1e-9));
    expect(r.gerceklesenKarTry, closeTo(293, 1e-9));
    expect(r.alimKomisyonuTry, 5);
    expect(r.masrafTry, 12);
  });

  test('başka yılın, ortağın ve silinmiş satırın kaydı girmez', () {
    final r = yillikRapor(
      lotlar: [
        _lot('s1', AssetKind.sell, satis: 120, tarih: DateTime(2024, 12, 31)),
        _lot('s2', AssetKind.sell, satis: 120, userId: 'ortak'),
        _lot('s3', AssetKind.sell, satis: 120, silindi: DateTime(2025, 7, 1)),
      ],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: 0.15,
    );
    expect(r.bos, isTrue);
  });

  test('satış fiyatı olmayan eski satır uydurulmaz, sayılır', () {
    final r = yillikRapor(
      lotlar: [_lot('s', AssetKind.sell)],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: 0.15,
    );
    expect(r.satislar, isEmpty);
    expect(r.fiyatsizSatis, 1);
  });

  test('dövizli satışta satış kuru satışa, alım kuru maliyete', () {
    final r = yillikRapor(
      lotlar: [
        _lot('s', AssetKind.sell,
            ticker: 'AAPL',
            alt: StockSubCategory.abd.name,
            para: 'USD',
            qty: 2,
            fiyat: 100,
            satis: 110,
            kur: 30,
            satisKuru: 40,
            komisyon: 1),
      ],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: 0.15,
    );
    final s = r.satislar.single;
    expect(s.satisTry, 2 * 110 * 40);
    expect(s.maliyetTry, 2 * 100 * 30);
    expect(s.komisyonTry, 40);
    expect(s.yurtDisi, isTrue);
    expect(r.yurtDisiKarTry, closeTo(8800 - 6000 - 40, 1e-9));
    expect(r.yurtDisiVar, isTrue);
  });

  test('temettü: net kayıtlı, brüt ve stopaj bilinen orandan', () {
    final r = yillikRapor(
      lotlar: [
        _lot('d1', AssetKind.dividend, temettu: 85),
        _lot('d2', AssetKind.dividend,
            ticker: 'AAPL',
            alt: StockSubCategory.abd.name,
            para: 'USD',
            kur: 40,
            temettu: 8),
      ],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: 0.15,
    );
    expect(r.temettuNetTry, closeTo(85 + 320, 1e-9));
    final bist = r.temettuler.firstWhere((t) => !t.yurtDisi);
    expect(bist.brutTry, closeTo(100, 1e-9));
    expect(bist.stopajTry, closeTo(15, 1e-9));
    final abd = r.temettuler.firstWhere((t) => t.yurtDisi);
    expect(abd.brutTry, closeTo(400, 1e-9));
    expect(r.stopajTry, closeTo(15 + 80, 1e-9));
  });

  test('BIST oranı bilinmiyorsa stopaj toplamı yazılmaz', () {
    final r = yillikRapor(
      lotlar: [_lot('d', AssetKind.dividend, temettu: 85)],
      userId: 'u1',
      yil: 2025,
      bistStopajOrani: null,
    );
    expect(r.temettuler.single.brutTry, isNull);
    expect(r.stopajTry, isNull);
    expect(r.temettuNetTry, 85);
  });

  test('rapor yılları: yalnız satış, temettü ya da komisyonlu alım olan yıllar',
      () {
    final yillar = raporYillari([
      _lot('b1', AssetKind.buy, tarih: DateTime(2023, 1, 1)),
      _lot('b2', AssetKind.buy, komisyon: 2, tarih: DateTime(2024, 1, 1)),
      _lot('s', AssetKind.sell, satis: 1, tarih: DateTime(2025, 1, 1)),
      _lot('o', AssetKind.sell, satis: 1, userId: 'x', tarih: DateTime(2022)),
    ], 'u1');
    expect(yillar, [2025, 2024]);
  });
}
