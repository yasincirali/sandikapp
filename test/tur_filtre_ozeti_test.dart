import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_grubu.dart';
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
    expect(o.adet[PortfoyGrubu(AssetType.hisse)], 1);
    expect(o.adet[PortfoyGrubu(AssetType.fon)], 1);
    expect(o.toplamAdet, 2);
    expect(o.pay(PortfoyGrubu(AssetType.hisse)), closeTo(1500 / 1700, 1e-9));
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
    expect(o.pay(PortfoyGrubu(AssetType.doviz)), closeTo(0.5, 1e-9));
  });

  test('fiyat bilinmiyorsa pay YOK (uydurma oran çizilmez), sayı var', () {
    final o = TurFiltreOzeti.hesapla([
      [_a('1', AssetType.fon, 10, 0, ticker: 'AFT')]
    ], _tl);
    expect(o.adet[PortfoyGrubu(AssetType.fon)], 1);
    expect(o.payVar, isFalse);
    expect(o.pay(PortfoyGrubu(AssetType.fon)), 0);
  });

  test('ayrım açıkken hisse BIST ve ABD diye ayrı sayılır', () {
    final abd = Asset(
      id: 'u', userId: 'u', name: 'Apple', ticker: 'AAPL',
      type: AssetType.hisse, subCategory: 'abd', quantity: 1,
      purchasePrice: 5, currency: 'USD', notes: '', isManualPrice: true,
      currentPrice: 5, addedDate: DateTime(2026, 1, 1),
    );
    final o = TurFiltreOzeti.hesapla([
      [_a('1', AssetType.hisse, 10, 100, ticker: 'THYAO.IS'), abd]
    ], _tl, pazarAyir: true);
    expect(o.adet[const PortfoyGrubu(AssetType.hisse, abd: false)], 1);
    expect(o.adet[const PortfoyGrubu(AssetType.hisse, abd: true)], 1);
    expect(o.adet[const PortfoyGrubu(AssetType.hisse)], isNull);
  });
}
