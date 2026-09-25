import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/altin_kisayollari.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Altın türü seçicisindeki 5 kısayolun kuralı (kullanıcı kararı
/// 2026-09-25): portföyde olan türler önce, 5'e popülerlerle tamamlanır;
/// hiç altın yoksa popüler beşli.
Asset _lot(
  String id,
  GoldSubCategory g, {
  double qty = 1,
  double fiyat = 100,
  AssetKind kind = AssetKind.buy,
  String userId = 'u1',
  String? subCategory,
  String? ticker,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: g.label,
      ticker: ticker ?? goldTickerMap[g.label]!,
      notes: '',
      type: AssetType.altin,
      subCategory: subCategory ?? g.label,
      unitType: g.unitType,
      quantity: qty,
      purchasePrice: fiyat,
      currentPrice: fiyat,
      currency: 'TRY',
      kind: kind,
      addedDate: DateTime(2026, 1, 1),
    );

void main() {
  test('hiç altın yoksa kullanıcının verdiği sırayla popüler beşli', () {
    expect(altinKisayollari(const []), [
      GoldSubCategory.ceyrek,
      GoldSubCategory.gr24,
      GoldSubCategory.gr22,
      GoldSubCategory.yarim,
      GoldSubCategory.tam,
    ]);
  });

  test('portföydeki türler önce (değere göre), kalanı popülerle tamamlanır',
      () {
    final k = altinKisayollari([
      _lot('a', GoldSubCategory.resat, qty: 1, fiyat: 100),
      _lot('b', GoldSubCategory.gr14, qty: 10, fiyat: 100),
      _lot('c', GoldSubCategory.ceyrek, qty: 1, fiyat: 50),
    ]);
    expect(k, [
      GoldSubCategory.gr14, // 1000 TL
      GoldSubCategory.resat, // 100 TL
      GoldSubCategory.ceyrek, // 50 TL — popüler olduğu için tekrar gelmez
      GoldSubCategory.gr24,
      GoldSubCategory.gr22,
    ]);
  });

  test('tamamen satılmış tür kısayolda kalmaz', () {
    final k = altinKisayollari([
      _lot('a', GoldSubCategory.hamit, qty: 2),
      _lot('s', GoldSubCategory.hamit, qty: 2, kind: AssetKind.sell),
    ]);
    expect(k, isNot(contains(GoldSubCategory.hamit)));
    expect(k, hasLength(5));
  });

  test('5\'ten fazla tür tutuluyorsa en değerli beşi', () {
    final turler = [
      GoldSubCategory.has,
      GoldSubCategory.ata,
      GoldSubCategory.besli,
      GoldSubCategory.gremse,
      GoldSubCategory.ikibucuk,
      GoldSubCategory.hamit,
    ];
    final k = altinKisayollari([
      for (var i = 0; i < turler.length; i++)
        _lot('$i', turler[i], qty: (i + 1).toDouble()),
    ]);
    expect(k, [
      GoldSubCategory.hamit,
      GoldSubCategory.ikibucuk,
      GoldSubCategory.gremse,
      GoldSubCategory.besli,
      GoldSubCategory.ata,
    ]);
  });

  test('altın dışı varlıklar kısayola girmez', () {
    final hisse = Asset(
      id: 'h',
      userId: 'u1',
      name: 'GARAN',
      ticker: 'GARAN.IS',
      notes: '',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 100,
      currency: 'TRY',
    );
    expect(altinKisayollari([hisse]), populerAltinTurleri);
  });

  test('tür CSV biçimindeki subCategory (enum adı) ve sembolden de tanınır',
      () {
    // CSV içe aktarma subCategory'ye enum adını yazar.
    expect(altinTuru(_lot('a', GoldSubCategory.tam, subCategory: 'tam')),
        GoldSubCategory.tam);
    // Sembolü tanınmayan eski kayıt: label'dan.
    expect(
        altinTuru(_lot('b', GoldSubCategory.ata, ticker: 'ESKI')),
        GoldSubCategory.ata);
  });

  test('her tür bir gruba ait, dört grubun hepsi dolu', () {
    final gruplar = {for (final g in GoldSubCategory.values) g.grup};
    expect(gruplar, AltinGrubu.values.toSet());
  });

  test('arama aksan ve harf duyarsız', () {
    expect(altinTurleriniAra('resat'), [GoldSubCategory.resat]);
    expect(altinTurleriniAra('IKIBUCUK'), contains(GoldSubCategory.ikibucuk));
    expect(altinTurleriniAra('22 ayar'), contains(GoldSubCategory.gr22));
    expect(altinTurleriniAra(''), GoldSubCategory.values);
    expect(altinTurleriniAra('xyz'), isEmpty);
  });
}
