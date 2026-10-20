import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/ice_aktarma_kotasi.dart';

/// Toplu kayıt öncesi kota planı (paywall incelemesi, 2026-10-20).
///
/// Bulgu: ekstre içe aktarma 10'luk kotada yarıda kesiliyor, hangi
/// kalemlerin yazıldığı hata özetinden öğreniliyordu. Plan kayıttan önce
/// "N kalem, M sığıyor" der; sayım `addAsset` kapısıyla aynı anahtar.
BulkCartItem _k(String id, String ticker,
        {AssetType type = AssetType.hisse,
        bool satis = false,
        SepetMevduati? mevduat}) =>
    BulkCartItem(
      id: id,
      type: type,
      name: ticker,
      ticker: ticker,
      quantity: 1,
      price: 10,
      currency: 'TRY',
      addedDate: DateTime(2026, 1, 1),
      satis: satis,
      mevduat: mevduat,
    );

void main() {
  test('sınırsızda her şey sığar', () {
    final p = iceAktarmaKotaPlani(
        kalemler: [_k('1', 'A'), _k('2', 'B')], kayitli: {}, sinir: null);
    expect(p.asiyor, isFalse);
    expect(p.sigan, hasLength(2));
    expect(p.yeniVarlik, 2);
  });

  test('8/10 doluyken 5 yeni kalemin ilk 2\'si sığar, sepet sırasıyla', () {
    final kayitli = {for (var i = 0; i < 8; i++) 'hisse|K$i|TRY'};
    final p = iceAktarmaKotaPlani(
      kalemler: [
        for (final t in ['A', 'B', 'C', 'D', 'E']) _k(t, t)
      ],
      kayitli: kayitli,
      sinir: 10,
    );
    expect(p.asiyor, isTrue);
    expect(p.sigan.map((k) => k.ticker), ['A', 'B']);
    expect(p.sigmayan.map((k) => k.ticker), ['C', 'D', 'E']);
    expect(p.yeniVarlik, 5);
  });

  test(
      'zaten sahip olunan varlığa ek lot ve aynı varlığın ikinci lotu '
      'kota yemez', () {
    final p = iceAktarmaKotaPlani(
      kalemler: [_k('1', 'A'), _k('2', 'A'), _k('3', 'B'), _k('4', 'B')],
      kayitli: {kotaAnahtari(AssetType.hisse, 'A', 'TRY')},
      sinir: 2,
    );
    expect(p.asiyor, isFalse);
    expect(p.yeniVarlik, 1);
  });

  test('satış kota yemez; alımı sığmayan varlığın satışı da sepette kalır', () {
    final p = iceAktarmaKotaPlani(
      kalemler: [
        _k('1', 'A'),
        _k('2', 'B'),
        _k('3', 'B', satis: true),
        _k('4', 'X', satis: true), // elde olan X'in satışı: sığar
      ],
      kayitli: {kotaAnahtari(AssetType.hisse, 'X', 'TRY')},
      sinir: 2,
    );
    expect(p.sigan.map((k) => k.id), ['1', '4']);
    expect(p.sigmayan.map((k) => k.id), ['2', '3']);
  });

  test('ekstreden gelen her vadeli mevduat ayrı varlıktır', () {
    const m = (kurum: 'Banka', yillikFaiz: 40.0, stopaj: 5.0, vadeGun: 32);
    final p = iceAktarmaKotaPlani(
      kalemler: [
        _k('m1', 'Mevduat', type: AssetType.diger, mevduat: m),
        _k('m2', 'Mevduat', type: AssetType.diger, mevduat: m),
      ],
      kayitli: {},
      sinir: 1,
    );
    expect(p.sigan.map((k) => k.id), ['m1']);
    expect(p.sigmayan.map((k) => k.id), ['m2']);
  });
}
