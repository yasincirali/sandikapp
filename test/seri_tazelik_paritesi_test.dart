import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// **Değişmez:** ana sayfa Bugün kartı ile Performans › Özet aynı kapsamda
/// AYNI kâr/zararı göstermeli (kullanıcı bildirimi 2026-09-22: "ana sayfa
/// günlük ben tabıyla performans tabındaki günlük ben kâr zarar tutarsız").
///
/// ## Üç ayrı sebep vardı, üçü de kapandı
///
/// 1. **Farklı lot kümesi** — Performans `isRenderable` eliyordu, Bugün
///    kartı ham `activeAssets` gönderiyordu. Kural tek eve taşındı:
///    `FiyatKaynagi.seriyeGirer` (bkz. `seri_giris_kurali_test`).
///
/// 2. **Farklı canlı toplam yolu** — `liveTotalTRY` `sonFiyat`'ı kullanıyor,
///    `DailySummary.from` içindeki `total` kullanmıyordu (bkz.
///    `ozet_ilk_kare_test`).
///
/// 3. **Farklı YAŞTA seri** — bu dosyanın konusu. Performans gün içi seriyi
///    30 sn'de bir tazeliyor (`_startIntradayTickIfNeeded`); Bugün kartı
///    `IntradaySeriesCache`'ten okuyordu ve onun penceresi 5 DAKİKA.
///    Gün başı (`open`) serinin ilk noktasından gelir; iki seri farklı
///    anlarda çekildiğinde o nokta da farklı olabiliyor ve aynı kapsamda
///    iki farklı kâr/zarar çıkıyordu.
///
/// ## Neden TTL topluca düşürülmedi
/// Önbelleği ana ekran widget'ı ve Live Activity de kullanıyor; onlar 5
/// dk'lık push döngüsüyle hizalı ve daha sık çekmek boşuna ağ trafiği
/// olurdu (`IntradaySeriesCache.minInterval` gerekçesi). Tazelik, yalnızca
/// KULLANICININ BAKTIĞI yüzeyde `azamiYas` ile istenir.
void main() {
  test('önbellek varsayılanı DEĞİŞMEDİ — widget/Live Activity etkilenmez', () {
    expect(IntradaySeriesCache.minInterval, const Duration(minutes: 5),
        reason: 'arka plan yüzeyleri push döngüsüyle hizalı kalmalı');
  });

  test('önbellek azamiYas kapısı taşır', () {
    final src = File('lib/services/daily_summary.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('Duration? azamiYas,'), isTrue,
        reason: 'ekrandaki yüzey daha taze seri isteyebilmeli');
    // Bayat önbellek gerçekten TAZELENMELİ — parametreyi alıp yok saymak
    // sessizce eski davranışa dönmek olurdu.
    //
    // Ama veri SİLİNMEZ: ilk sürüm `_series = null` yapıyordu ve bu,
    // fetch sürerken diğer yüzeylere boş seri veriyordu
    // (bkz. `intraday_cache_dayaniklilik_test`).
    expect(src.contains('final tazeleZorla = azamiYas != null'), isTrue,
        reason: 'azamiYas aşıldığında tazeleme istenmeli');
    expect(
        src.contains(
            '} else if (!tazeleZorla && ts.difference(_fetchedAt!) < minInterval) {'),
        isTrue,
        reason: 'bayrak kısa devreyi atlatmalı, yoksa tazelik hiç gelmez');
  });

  test('Bugün kartı Performans ile AYNI tazelik penceresini kullanır', () {
    final src = File('lib/widgets/bugun_karti.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');

    expect(
        src.contains(
            'static const _seriTazelikPenceresi = Duration(seconds: 30);'),
        isTrue,
        reason: 'Performans tick\'i 30 sn — ayrışırsa iki yüzey farklı '
            'yaşta seriye bakar');
    expect(src.contains('azamiYas: _seriTazelikPenceresi'), isTrue,
        reason: 'pencere tanımlanıp kullanılmazsa ölü koddur');
  });

  test('Performans tick periyodu hâlâ 30 sn (parite dayanağı)', () {
    final src = File('lib/screens/portfolio_performance/seriler.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('Timer.periodic(const Duration(seconds: 30)'), isTrue,
        reason: 'bu değer değişirse `_seriTazelikPenceresi` de değişmeli — '
            'ikisi birlikte anlamlı');
  });
}
