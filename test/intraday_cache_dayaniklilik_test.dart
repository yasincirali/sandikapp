import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ana ekranda rakamlar "biraz saçmalayıp düzeliyordu" (kullanıcı
/// bildirimi 2026-09-22) ve belirti **yalnızca "Ben" seçiliyken**
/// görülüyordu.
///
/// ## Neden yalnızca "Ben"
/// `IntradaySeriesCache`'i yalnızca o kapsam kullanıyor; ortak ve Birlikte
/// `getPortfolioHistoryHourlyBreakdown`'u doğrudan çağırır. Yani arıza
/// önbelleğin kendisindeydi ve kapsam ipucu onu tam olarak işaret etti.
///
/// ## İki kaynak
///
/// 1. **`azamiYas` veriyi SİLİYORDU.** Tazelik penceresi eklenirken
///    (aynı gün, önceki tur) bayat önbellek `_series = null` ile
///    boşaltılıyordu. Fetch sürerken aynı önbelleği çağıran başka bir
///    yüzey (ana ekran widget'ı, Live Activity) BOŞ seri alıyordu; fetch
///    başarısız olursa kart gün başı olmadan hesap yapıyordu.
///    → Artık yalnızca "tazele" bayrağı kurulur; eski seri fetch bitene
///      kadar elde kalır.
///
/// 2. **Eşzamanlı fetch tekilleştirilmiyordu.** Üç yüzey bu önbelleği
///    paylaşıyor ve açılışta hepsi birden isteyebiliyor. İki istek
///    yarışınca GEÇ dönen erken döneni eziyordu.
///    → Süren fetch paylaşılır (`_surenFetch`).
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/services/daily_summary.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
  });

  group('azamiYas veriyi silmez', () {
    test('yalnızca tazele bayrağı kurar', () {
      expect(src.contains('final tazeleZorla = azamiYas != null'), isTrue,
          reason: 'bayrak kurulmalı');
    });

    test('bayrak kısa devreyi atlatır — yeni veri GERÇEKTEN çekilir', () {
      expect(
          src.contains(
              '} else if (!tazeleZorla && ts.difference(_fetchedAt!) < minInterval) {'),
          isTrue,
          reason: 'bayrak kurulup kullanılmazsa tazelik hiç gelmez');
    });

    test('REGRESYON: azamiYas dalında _series boşaltılmaz', () {
      // Eski hatanın imzası: tazelik kapısının içinde üçlü sıfırlama.
      expect(
          src.contains(
              'ts.difference(_fetchedAt!) > azamiYas) { _series = null;'),
          isFalse,
          reason: 'eski seri fetch bitene kadar elde kalmalı — '
              'silinirse diğer yüzeyler boş seri alır');
    });
  });

  group('eşzamanlı fetch tekilleştirilir', () {
    test('süren fetch alanı var', () {
      expect(src.contains('Future<Map<int, double>>? _surenFetch;'), isTrue);
    });

    test('ikinci çağıran aynı future\'ı bekler', () {
      expect(
          src.contains('final suren = _surenFetch; if (suren != null) return suren;'),
          isTrue,
          reason: 'ikinci ağ turu atılmamalı');
    });

    test('fetch bitince alan temizlenir (finally)', () {
      expect(src.contains('} finally { _surenFetch = null; }'), isTrue,
          reason: 'temizlenmezse önbellek kalıcı olarak kilitlenir');
    });
  });

  test('gün ve sahip kapıları KORUNDU', () {
    // Bu iki kural daha önceki arızaların ürünü; tazelik değişikliği
    // onları gölgelememeli.
    expect(src.contains('final sameDay = _fetchedAt != null'), isTrue,
        reason: 'gece yarısını geçen oturumda dünün açılışı kullanılamaz');
    expect(
        src.contains(
            'final sameOwner = state.ownerId.isEmpty || state.ownerId == _ownerId;'),
        isTrue,
        reason: 'başka kullanıcının serisi bu deftere ait değildir');
  });

  test('toplam hesaplayan HER çağıran sonFiyat geçirir', () {
    // Ortak lot'unun fiyatı bayatsa toplam onu saymaz, kâr/zarar sayardı:
    // aynı kartta iki sayı ayrışıyordu.
    for (final yol in [
      'lib/widgets/bugun_karti.dart',
      'lib/screens/portfolio_performance/kartlar.dart',
      'lib/services/daily_summary.dart',
    ]) {
      final dosya = File(yol)
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (!dosya.contains('ownerScopedTotalValue(')) continue;
      expect(dosya.contains('sonFiyat:'), isTrue,
          reason: '$yol toplamı sonFiyat olmadan hesaplıyor — '
              'DailySummary ile ayrışır');
    }
  });
}
