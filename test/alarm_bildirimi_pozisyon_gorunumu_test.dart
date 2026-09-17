import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Alarm bildiriminden açılan varlık ekranı grafiği çizmeli.
///
/// Kullanıcı bildirimi (2026-09-17): "fiyat alarmından tıkladığımda varlık
/// performans ekranında veriyi çekememiş; aynı 22 ayar gram altın
/// portföyümden tıklayınca grafiği çizdiriyor."
///
/// Sebep: bildirim yolu ekrana sembolle eşleşen İLK ham lot'u veriyordu
/// (satış ya da silinmiş kayıt olabilir); portföy yolu ise pozisyon
/// toplamını (`asDisplayAsset`). `HistoryService` satış lot'unu tek başına
/// fiyatlamaz → seri boş → "veri çekilemedi".
void main() {
  Asset lot({
    required String id,
    required AssetKind kind,
    required double qty,
    DateTime? deletedAt,
    int gunOnce = 30,
  }) =>
      Asset(
        id: id,
        userId: 'u1',
        name: '22 Ayar Gram Altın',
        ticker: 'ALTIN_GRAM',
        type: AssetType.altin,
        subCategory: '22 Ayar',
        quantity: qty,
        purchasePrice: 5000,
        currency: 'TRY',
        notes: '',
        currentPrice: 6212.28,
        addedDate: DateTime.now().subtract(Duration(days: gunOnce)),
        kind: kind,
        deletedAt: deletedAt,
      );

  group('pozisyonGorunumu', () {
    test('satış lot\'uyla girilse de net miktarlı ALIM görünümü döner', () {
      final alim = lot(id: 'a', kind: AssetKind.buy, qty: 5, gunOnce: 40);
      final satis = lot(id: 's', kind: AssetKind.sell, qty: 2, gunOnce: 10);
      final g = pozisyonGorunumu([satis, alim], satis);

      expect(g, isNotNull);
      expect(g!.asset.isBuy, isTrue,
          reason: 'HistoryService yalnızca alım nesnesini fiyatlar');
      expect(g.asset.quantity, closeTo(3, 1e-9));
      expect(g.asset.currentPrice, 6212.28);
      expect(g.lots.map((l) => l.id), containsAll(['a', 's']));
    });

    test('silinmiş lot\'la girilse de açık pozisyon bulunur', () {
      final alim = lot(id: 'a', kind: AssetKind.buy, qty: 5);
      final silinmis = lot(
          id: 'x', kind: AssetKind.buy, qty: 1, deletedAt: DateTime.now());
      final g = pozisyonGorunumu([silinmis, alim], silinmis);
      expect(g, isNotNull);
      expect(g!.asset.quantity, closeTo(5, 1e-9),
          reason: 'silinmiş lot miktara girmez');
      expect(g.lots.map((l) => l.id), isNot(contains('x')));
    });

    test('pozisyon tamamen satılmışsa null — çağıran ham lot\'a düşer', () {
      final alim = lot(id: 'a', kind: AssetKind.buy, qty: 2, gunOnce: 40);
      final satis = lot(id: 's', kind: AssetKind.sell, qty: 2, gunOnce: 10);
      expect(pozisyonGorunumu([alim, satis], alim), isNull);
    });
  });

  test('bildirim ve derin bağlantı yolu pozisyon görünümünü kullanır', () {
    final src = File('lib/services/notification_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(src.contains('pozisyonGorunumu(assets, asset)'), isTrue,
        reason: 'openAssetPerformance ekrana ham lot veriyor — alarm '
            'bildiriminden açılan altın grafiği yine boş kalır');
  });
}
