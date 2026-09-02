import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';

/// **Değişmez: takip edilen varlık HİÇBİR portföy hesabına girmez.**
///
/// Portföy değeri, kâr/zarar, tür dökümü, grafik serisi, leaderboard,
/// Live Activity — hiçbiri.
///
/// ## Neden bu test var
/// Bu proje "iki kavramın tek havuzda toplanması" hata sınıfını İKİ KEZ yaşadı:
///   · ortak lot'ları tek havuzda aggregate ediliyordu → yanlış kâr/zarar,
///   · tür dökümü ayrı bir veri yolundan besleniyordu → toplamlar tutmuyordu.
///
/// Takip listesi aynı tuzağı kurar: "izlenen" ve "sahip olunan" birbirine
/// çok benzer iki kavram. Koruma iki katmanlı:
///   1. **Şema:** `watchlist` AYRI tablo (`0043`). `assets`'i sorgulayan
///      hiçbir kod takip kaydını göremez — sızma yapısal olarak imkânsız.
///   2. **Tip:** `WatchlistItem` ayrı sınıf; `Asset` değil, dolayısıyla
///      `aggregatePositions` gibi fonksiyonlara GEÇİRİLEMEZ (derleme hatası).
///
/// Buradaki testler ikinci katmanı ve kaynak düzeyindeki ayrımı kilitler.

Asset _lot({
  required String id,
  required AssetType type,
  required double qty,
  required double price,
  String ticker = 'TEST',
  String? sub,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: price,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      purchaseFxRate: 1.0,
      currentPrice: price,
      addedDate: DateTime.now().subtract(const Duration(days: 30)),
      kind: AssetKind.buy,
      subCategory: sub,
    );

WatchlistItem _watch({
  required String ticker,
  AssetType type = AssetType.hisse,
  String? sub,
}) =>
    WatchlistItem(
      id: 'w-$ticker',
      userId: 'u1',
      ticker: ticker,
      name: ticker,
      type: type,
      currency: 'TRY',
      addedAt: DateTime.now(),
      subCategory: sub,
      currentPrice: 999999, // toplama girerse ANINDA fark edilsin
    );

void main() {
  group('tip ayrımı', () {
    test('WatchlistItem bir Asset DEĞİLDİR', () {
      // Bu testin asıl değeri derleme zamanında: `WatchlistItem`
      // `aggregatePositions(List<Asset>)`'a geçirilemez. Çalışma zamanında
      // da tip kontrolüyle belgeliyoruz.
      final w = _watch(ticker: 'ASELS');
      // ignore: unnecessary_type_check
      expect(w is Asset, isFalse,
          reason: 'takip kaydı Asset olsaydı her aggregate onu saymaya '
              'çalışırdı — sahte quantity/purchasePrice ile');
    });

    test('WatchlistItem miktar ve maliyet TAŞIMAZ', () {
      // Sahip olmadığın varlığın miktarı ve alış fiyatı yoktur. Bu alanların
      // hiç var olmaması, "0 mı yoksa bilinmiyor mu?" belirsizliğini önler.
      final w = _watch(ticker: 'ASELS');
      final alanlar = w.toInsertMap().keys.toSet();
      expect(alanlar.contains('quantity'), isFalse);
      expect(alanlar.contains('purchase_price'), isFalse);
      expect(alanlar.contains('current_price'), isFalse,
          reason: 'canlı fiyat DB\'de tutulmaz — bayatlar');
    });
  });

  group('portföy toplamı etkilenmez', () {
    test('takip listesi büyürken portföy toplamı SABİT kalır', () {
      final lots = [
        _lot(id: 'a1', type: AssetType.hisse, qty: 100, price: 50),
        _lot(id: 'a2', type: AssetType.altin, qty: 10, price: 4000, sub: 'gram'),
      ];
      final oncesi = ownerScopedTotalValue([lots]);

      // Takip listesine yüksek fiyatlı varlıklar eklenir. Portföy tarafına
      // hiçbir şey eklenmez — `watchlist` ayrı tablo, ayrı tip.
      final _ = [
        _watch(ticker: 'THYAO'),
        _watch(ticker: 'ASELS'),
        _watch(ticker: 'GARAN'),
      ];

      final sonrasi = ownerScopedTotalValue([lots]);
      expect(sonrasi, closeTo(oncesi, 0.001),
          reason: 'takip listesi portföy toplamını DEĞİŞTİRMEMELİ');
      expect(sonrasi, closeTo(100 * 50 + 10 * 4000, 0.001));
    });

    test('aggregatePositions yalnızca sahip olunan lot\'ları görür', () {
      final lots = [_lot(id: 'a1', type: AssetType.hisse, qty: 100, price: 50)];
      final positions = aggregatePositions(lots);
      expect(positions.length, 1);
      expect(positions.first.totalQuantity, 100);
      // Takip kaydı bu listeye hiç giremez — tip uyuşmaz.
    });
  });

  group('anahtar tutarlılığı', () {
    // `WatchlistItem.key` ile sunucudaki unique index
    // (`watchlist_user_asset_uidx`) aynı kuralı uygulamalı. Ayrışırlarsa
    // istemci "zaten takipte" derken sunucu kabul eder (ya da tersi).
    test('alt kategori anahtara girer — Gram ve Çeyrek AYRI', () {
      final gram = _watch(
          ticker: 'ALTIN_GRAM', type: AssetType.altin, sub: '22 Ayar Gram Altın');
      final ceyrek = _watch(
          ticker: 'ALTIN_CEYREK', type: AssetType.altin, sub: 'Çeyrek Altın');
      expect(gram.key == ceyrek.key, isFalse,
          reason: 'altın türleri ayrı takip edilebilmeli');
    });

    test('tür anahtara girer — aynı ticker farklı türde ayrışır', () {
      final a = _watch(ticker: 'X', type: AssetType.hisse);
      final b = _watch(ticker: 'X', type: AssetType.fon);
      expect(a.key == b.key, isFalse);
    });

    test('büyük/küçük harf anahtarı değiştirmez', () {
      final a = _watch(ticker: 'asels');
      final b = _watch(ticker: 'ASELS');
      expect(a.key, b.key,
          reason: 'sunucudaki index de upper() kullanıyor');
    });
  });

  group('şema koruması — kaynak metin', () {
    // Birim testleri tipi doğrular, ŞEMAYI değil. Bu projede wiring
    // testlerinin değeri sabotajla ölçüldü (`lot_collapse_test.ts`).

    test('watchlist AYRI tablo — assets\'e kind eklenmemiş', () async {
      final sql = await File('supabase/migrations/0043_watchlist.sql')
          .readAsString();
      expect(sql.contains('create table if not exists watchlist'), isTrue);
      expect(sql.toLowerCase().contains('alter table assets'), isFalse,
          reason: 'takip kaydı assets tablosuna eklenirse her aggregate\'in '
              'yoluna düşer ve her birinde ayrı ayrı elenmesi gerekir');
    });

    test('RLS ve GRANT AYNI dosyada', () async {
      // Bu projede iki kez ayrı ayrı unutuldu: 0035→0036, 0042.
      // Politika tek başına yetmez; GRANT yoksa sorgu sessizce 0 satır döner.
      final sql = await File('supabase/migrations/0043_watchlist.sql')
          .readAsString();
      expect(sql.contains('enable row level security'), isTrue);
      expect(sql.contains('grant select, insert, delete on table watchlist'),
          isTrue,
          reason: 'RLS politikası GRANT olmadan çalışmaz');
      expect(sql.contains('raise exception'), isTrue,
          reason: 'migration kendini denetlemeli — sessizce eksik kalmasın');
    });

    test('portföy providerları watchlist OKUMAZ', () async {
      // Takip listesinin portföy hesabına sızmasının tek yolu, portföy
      // tarafındaki bir provider'ın onu okuması olurdu.
      for (final yol in [
        'lib/providers/portfolio_provider.dart',
        'lib/models/position.dart',
        'lib/services/history_service.dart',
      ]) {
        final src = await File(yol).readAsString();
        expect(src.contains('watchlist'), isFalse,
            reason: '$yol takip listesini okumamalı — portföy hesabı '
                'yalnızca `assets` üzerinden yapılır');
      }
    });
  });
}
