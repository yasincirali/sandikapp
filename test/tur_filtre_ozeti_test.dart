import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/tur_filtre_ozeti.dart';

/// Filtre döşemelerinin sayı/pay hesabı — ekranın grafiğiyle aynı küme.
Asset _a(String id, AssetType t, double adet, double fiyat,
        {String ticker = 'X', DateTime? silindi, String cur = 'TRY'}) =>
    Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: ticker,
      type: t,
      quantity: adet,
      purchasePrice: fiyat,
      currency: cur,
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
      deletedAt: silindi,
    );

double _tl(double v, String c) => c == 'USD' ? v * 40 : v;

void main() {
  test('net pozisyon sayılır; aynı sembolün iki lot\'u tek varlık', () {
    final o = TurFiltreOzeti.hesapla([
      [
        _a('1', AssetType.hisse, 10, 100, ticker: 'THYAO.IS'),
        _a('2', AssetType.hisse, 5, 100, ticker: 'THYAO.IS'),
        _a('3', AssetType.fon, 100, 2, ticker: 'AFT'),
      ]
    ], _tl);
    expect(o.adet[AssetType.hisse], 1);
    expect(o.adet[AssetType.fon], 1);
    expect(o.toplamAdet, 2);
    expect(o.pay(AssetType.hisse), closeTo(1500 / 1700, 1e-9));
  });

  test('silinmiş lot sayılmaz', () {
    final o = TurFiltreOzeti.hesapla([
      [_a('1', AssetType.altin, 1, 4000, silindi: DateTime(2026, 2, 1))]
    ], _tl);
    expect(o.toplamAdet, 0);
    expect(o.payVar, isFalse);
  });

  test('USD değeri TL\'ye çevrilir', () {
    final o = TurFiltreOzeti.hesapla([
      [
        _a('1', AssetType.doviz, 100, 1, ticker: 'USD', cur: 'USD'),
        _a('2', AssetType.hisse, 10, 400, ticker: 'A'),
      ]
    ], _tl);
    expect(o.pay(AssetType.doviz), closeTo(0.5, 1e-9));
  });

  test('fiyat bilinmiyorsa pay YOK (uydurma oran çizilmez), sayı var', () {
    final o = TurFiltreOzeti.hesapla([
      [_a('1', AssetType.fon, 10, 0, ticker: 'AFT')]
    ], _tl);
    expect(o.adet[AssetType.fon], 1);
    expect(o.payVar, isFalse);
    expect(o.pay(AssetType.fon), 0);
  });
}
