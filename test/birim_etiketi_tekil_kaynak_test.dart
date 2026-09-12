import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';

/// Birim etiketi uygulamanın HER yerinde aynı olmalı.
///
/// ## Yakaladığı ayrışma (TECHNICAL_DEBT, 2026-09-12'de kapatıldı)
/// `bulk_add_asset_screen._unitLabel()` yalnızca `unitType`'a bakıyordu ve
/// `type`'ı hiç sormuyordu. Hisse/fon `default` dalına düşüp **"adet"**
/// yazıyordu; aynı varlık kaydedildikten sonra `Asset.unitLabel`
/// **"lot"** diyordu. Kullanıcı aynı varlığı iki ekranda iki farklı
/// birimle görüyordu.
///
/// Bu dosya iki şeyi birden kilitler: kanonik eşlemenin kendisi ve
/// kopyanın geri gelmemesi.
Asset _a({
  required AssetType type,
  String unitType = 'piece',
  String ticker = 'X',
  String currency = 'TRY',
}) =>
    Asset(
      id: 'i',
      userId: 'u',
      name: 'n',
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 1,
      currency: currency,
      notes: '',
      isManualPrice: false,
      unitType: unitType,
    );

BulkCartItem _b({
  required AssetType type,
  String unitType = 'piece',
  String currency = 'TRY',
}) =>
    BulkCartItem(
      id: 'i',
      type: type,
      name: 'n',
      ticker: 'X',
      quantity: 1,
      price: 1,
      currency: currency,
      addedDate: DateTime(2026, 1, 1),
      unitType: unitType,
    );

/// Sepet satırının gösterdiği etiket — ekrandaki `_unitLabel()` ile AYNI
/// çağrı.
String _sepetEtiketi(BulkCartItem i) => birimEtiketi(
      type: i.type,
      unitType: i.unitType,
      currency: i.currency,
    );

void main() {
  group('sepet ve kayıtlı varlık AYNI etiketi verir', () {
    // Asıl regresyon: bu liste ayrışmanın görüldüğü yerleri kapsıyor.
    final durumlar = <({AssetType type, String unitType, String beklenen})>[
      (type: AssetType.hisse, unitType: 'piece', beklenen: 'lot'),
      (type: AssetType.fon, unitType: 'piece', beklenen: 'lot'),
      (type: AssetType.altin, unitType: 'gram', beklenen: 'gr'),
      (type: AssetType.altin, unitType: 'piece', beklenen: 'adet'),
      (type: AssetType.emtia, unitType: 'ounce', beklenen: 'oz'),
      (type: AssetType.emtia, unitType: 'kilogram', beklenen: 'kg'),
      (type: AssetType.emtia, unitType: 'liter', beklenen: 'lt'),
      (type: AssetType.emtia, unitType: 'barrel', beklenen: 'bbl'),
      (type: AssetType.mevduat, unitType: 'piece', beklenen: '₺'),
      (type: AssetType.diger, unitType: 'piece', beklenen: 'adet'),
    ];

    for (final d in durumlar) {
      test('${d.type.name} + ${d.unitType} → ${d.beklenen}', () {
        final kayitli = _a(type: d.type, unitType: d.unitType).unitLabel;
        final sepet = _sepetEtiketi(_b(type: d.type, unitType: d.unitType));

        expect(kayitli, d.beklenen, reason: 'Kayıtlı varlık etiketi yanlış.');
        expect(sepet, d.beklenen, reason: 'Sepet etiketi yanlış.');
        expect(sepet, kayitli,
            reason: 'Sepet ve kayıtlı varlık AYRIŞMIŞ — kullanıcı aynı '
                'varlığı iki ekranda farklı birimle görür.');
      });
    }
  });

  test('hisse/fon sepette "adet" DEMEZ — asıl regresyon', () {
    // Eski kopyanın tam olarak yaptığı hata.
    for (final t in [AssetType.hisse, AssetType.fon]) {
      expect(_sepetEtiketi(_b(type: t)), isNot('adet'),
          reason: '$t sepette yine "adet" diyor; kopya geri gelmiş.');
    }
  });

  test('döviz sembolü para birimine göre', () {
    expect(
      _a(type: AssetType.doviz, ticker: 'USDTRY=X', currency: 'USD').unitLabel,
      '\$',
    );
    // Sepette `currencySymbol` yok (ticker'a bakmıyor) — para birimi
    // kodunun kendisi dönmeli, ham `unitType` DEĞİL.
    expect(_sepetEtiketi(_b(type: AssetType.doviz, currency: 'USD')), 'USD');
  });

  test('hiçbir tür ham `unitType` sabitini BASMAZ', () {
    const hamlar = {'piece', 'gram', 'ounce', 'kilogram', 'liter', 'barrel'};
    for (final t in AssetType.values) {
      for (final u in hamlar) {
        final e = birimEtiketi(type: t, unitType: u, currency: 'TRY');
        expect(hamlar.contains(e), isFalse,
            reason: '$t + $u → "$e" ham sabit kalmış.');
        expect(e.trim(), isNotEmpty, reason: '$t + $u için boş etiket.');
      }
    }
  });

  test('KOPYA geri gelmesin — sepet ekranı kendi switch\'ini kurmaz', () {
    final kaynak = File('lib/screens/bulk_add_asset_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    expect(kaynak.contains('birimEtiketi('), isTrue,
        reason: 'Sepet ekranı ortak kaynağı kullanmıyor.');
    // Eski kopyanın imzası: `unitType` üzerinde switch + 'bbl' dalı.
    expect(kaynak.contains("switch (item.unitType)"), isFalse,
        reason: 'Yerel birim switch\'i geri gelmiş — ayrışma buradan '
            'başlamıştı.');
  });
}
