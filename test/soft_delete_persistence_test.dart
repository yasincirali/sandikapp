import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Silme KALICI olmalı — fiyat güncellemesi damgayı ezmez.
///
/// ## Ölçülen arıza (kullanıcı bildirimi, 2026-09-16)
/// Kullanıcı varlıkları sildi, ekranda silinmiş göründüler; uygulamayı
/// kapatıp açınca GERİ GELDİLER. Logda aynı varlıkların dört ayrı silme
/// turu görüldü (15:54, 15:58, 16:11, 16:19) — her seferinde sunucu
/// `rows: 1` dönüyordu, yani satır her defasında yeniden dirilmişti.
///
/// Sebep iki katmanlıydı:
///   1. `updateAsset` gövdenin TAMAMINI yazıyor ve `toSupabase()`
///      `deleted_at` alanını içeriyor. Elindeki nesne damgasızsa UPDATE
///      damgayı NULL'a çekiyor.
///   2. `refreshPrices` silinmiş lot'lar için de `updateAsset` çağırıyordu
///      (fiyat çekme döngüsünde `isActive` kapısı vardı, yazma döngüsünde
///      yoktu).
void main() {
  Asset lot({DateTime? deletedAt}) => Asset(
        id: 'a1',
        userId: 'u1',
        name: 'THYAO',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 100,
        purchasePrice: 250,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 300,
        addedDate: DateTime(2026, 1, 10),
        deletedAt: deletedAt,
      );

  group('toSupabase', () {
    test('deleted_at alanını taşır — damganın kaynağı burası', () {
      final damgali = lot(deletedAt: DateTime.utc(2026, 9, 16, 12));
      expect(damgali.toSupabase()['deleted_at'], isNotNull);
      expect(lot().toSupabase()['deleted_at'], isNull);
    });
  });

  group('updateAsset gövdesi', () {
    // Servis ağa çıkıyor; burada gövdenin KURULUMU doğrulanıyor —
    // `updateAsset` içindeki `..remove('deleted_at')` ile aynı işlem.
    Map<String, dynamic> govde(Asset a) =>
        a.toSupabase()..remove('deleted_at');

    test('damga gövdeden ÇIKARILIR — silinmiş lot dirilmez', () {
      final silinmis = lot(deletedAt: DateTime.utc(2026, 9, 16, 12));
      expect(govde(silinmis).containsKey('deleted_at'), isFalse,
          reason: 'UPDATE damgayı NULL yapamamalı');
    });

    test('damgasız nesne de damgayı YAZMAZ — asıl dirilme yolu buydu', () {
      // Kritik durum: bellekteki nesne damgasız (eski snapshot) ama
      // sunucuda satır SİLİNMİŞ. Gövde `deleted_at: null` taşısaydı
      // sunucudaki damga silinirdi.
      expect(govde(lot()).containsKey('deleted_at'), isFalse);
    });

    test('diğer alanlar korunur — güncelleme işlevini kaybetmez', () {
      final g = govde(lot());
      expect(g['current_price'], 300);
      expect(g['quantity'], 100);
      expect(g['ticker'], 'THYAO.IS');
    });
  });

  group('isActive kapısı', () {
    test('damgalı lot aktif DEĞİL — yazma döngüsü onu atlamalı', () {
      expect(lot(deletedAt: DateTime.utc(2026, 9, 16)).isActive, isFalse);
      expect(lot().isActive, isTrue);
    });

    test('deleteLog mezar taşı da aktif değil', () {
      final tas = Asset(
        id: 'log1',
        userId: 'u1',
        name: 'THYAO',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 0,
        purchasePrice: 0,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 0,
        addedDate: DateTime(2026, 1, 10),
        kind: AssetKind.deleteLog,
      );
      expect(tas.isActive, isFalse);
    });
  });

  group('kaynak kilidi', () {
    test('updateAsset deleted_at çıkarır', () {
      final src = File('lib/services/supabase_service.dart').readAsStringSync();
      final i = src.indexOf('Future<void> updateAsset(');
      expect(i, greaterThan(-1));
      final govde = src.substring(i, i + 400);
      expect(govde.contains("remove('deleted_at')"), isTrue,
          reason: 'damga gövdeden çıkarılmazsa silinen varlık dirilir');
    });

    test('refreshPrices silinmiş lot için yazma yapmaz', () {
      final src =
          File('lib/providers/portfolio_provider.dart').readAsStringSync();
      expect(src.contains('if (!asset.isActive) return asset;'), isTrue,
          reason: 'yazma döngüsünde isActive kapısı olmalı');
    });
  });
}
