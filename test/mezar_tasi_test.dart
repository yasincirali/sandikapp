import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Sil'in yazdığı "Silindi" mezar taşı sunucu kısıtlarına (0008:
/// `quantity >= 0`, `purchase_price >= 0`) her zaman uymalı. Uymazsa INSERT
/// düşer ve Sil "Veri işlemi başarısız oldu" der (TestFlight, 2026-10-10).
Asset _lot(String id, double adet, double fiyat,
        {AssetKind kind = AssetKind.buy, double? satis}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      sellPrice: satis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 300,
      kind: kind,
      addedDate: DateTime(2025, 3, 1),
    );

void main() {
  test('kârla satılmış pozisyon: fiyat EKSİ çıkmaz (asıl hata)', () {
    final lotlar = [
      _lot('a', 10, 100),
      _lot('s', 5, 100, kind: AssetKind.sell, satis: 300),
    ];
    final (miktar, fiyat) = mezarTasiDegerleri(lotlar, lotlar.first);
    expect(miktar, 5);
    expect(fiyat, 100, reason: 'Alımların ağırlıklı ortalaması');
  });

  test('parça parça alım: ağırlıklı ortalama', () {
    final lotlar = [_lot('a', 10, 100), _lot('b', 30, 200)];
    final (miktar, fiyat) = mezarTasiDegerleri(lotlar, lotlar.first);
    expect(miktar, 40);
    expect(fiyat, 175);
  });

  test('tamamı satılmış + yuvarlama artığı: miktar 0, fiyat ≥ 0', () {
    final lotlar = [
      _lot('a', 0.1, 50),
      _lot('b', 0.2, 50),
      _lot('s', 0.3, 50, kind: AssetKind.sell, satis: 80),
    ];
    final (miktar, fiyat) = mezarTasiDegerleri(lotlar, lotlar.first);
    expect(miktar, 0);
    expect(fiyat, greaterThanOrEqualTo(0));
  });

  test('fazla satış ya da maliyetsiz lot: yine sınırların içinde', () {
    final lotlar = [
      _lot('a', 5, 0),
      _lot('s', 8, 0, kind: AssetKind.sell, satis: 10),
    ];
    final (miktar, fiyat) = mezarTasiDegerleri(lotlar, lotlar.first);
    expect(miktar, 0);
    expect(fiyat, 0);
  });

  test('silme ÖNCE damgalar, mezar taşı sonra ve hatası silmeyi durdurmaz',
      () {
    // yasin 2026-10-10: "silme zaten o varlığı tamamen yok sayması
    // gerekiyordu". Mezar taşı yalnız geçmiş satırı; INSERT'i düşerse
    // silme yine olmalı.
    final src =
        File('lib/providers/portfolio_provider.dart').readAsStringSync();
    final govde = src.substring(
        src.indexOf('Future<SilinenPozisyon?> deletePositionLots'),
        src.indexOf('Future<void> restorePositionLots'));
    final damga = govde.indexOf('softDeleteAssets(');
    final mezar = govde.indexOf('insertAsset(log)');
    expect(damga, greaterThan(0));
    expect(mezar, greaterThan(damga), reason: 'Önce damga');
    expect(govde.substring(damga, mezar), contains('try {'),
        reason: 'Mezar taşı hatası yakalanmalı');
  });
}
