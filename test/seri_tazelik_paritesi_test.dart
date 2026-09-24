import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

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
    expect(src.contains('final tazeleZorla = _fetchedAt != null && (zorla || (azamiYas != null'), isTrue,
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

    // **Değişti (2026-09-23):** ritim artık ham literal değil, tek
    // kaynaktan (`TazelikRitmi.yuzey`) geliyor. Testin koruduğu DEĞER aynı
    // — iki yüzey aynı pencereyi kullanmalı — ama artık YAZIMI değil
    // KAYNAĞI doğruluyor: literal aramak, merkezi sabite geçişi sahte bir
    // kırılma olarak gösterirdi.
    expect(
        src.contains(
            'static const _seriTazelikPenceresi = TazelikRitmi.yuzey;'),
        isTrue,
        reason: 'pencere TazelikRitmi\'nden okunmalı — kendi literalini '
            'tanımlayan yüzey bir sonraki değişiklikte ayrışır');
    expect(src.contains('azamiYas: _seriTazelikPenceresi'), isTrue,
        reason: 'pencere tanımlanıp kullanılmazsa ölü koddur');
  });

  test('Performans ORTAK NABZI dinler (parite dayanağı)', () {
    // **Değişti (2026-09-23):** aynı ritmi kullanmak YETMEDİ. Her yüzey
    // sayacını mount anında kurduğu için hepsi 30 sn'de bir ama FARKLI
    // FAZDA çalışıyordu — ana sayfa t=0, Performans t=12 ise iki yüzey
    // 12 saniye farklı anın verisini gösteriyordu.
    final src = File('lib/screens/portfolio_performance/seriler.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('TazelikRitmi.nabiz.dinle('), isTrue,
        reason: 'Bugün kartı ile AYNI nabzı dinlemeli; ayrı sayaçlar '
            'aynı ritimde bile faz kaydırır (bkz. tazelik_nabzi_test)');
  });

  test('iki yüzeyin penceresi FİİLEN eşit (kaynak metni değil, DEĞER)', () {
    // Yukarıdaki ikisi kaynak metni tarıyor — yazım değişirse sahte
    // kırılırlar. Bu test değerin kendisini ölçer: bu projede "kaynak
    // doğru görünüyor ama davranış yanlış" sınıfı hatalar yaşandı.
    expect(TazelikRitmi.yuzey, TazelikRitmi.temel,
        reason: 'yüzey ritmi taban ritim olmalı');
    expect(TazelikRitmi.hizali(TazelikRitmi.gunIciSeriOmru), isTrue,
        reason: 'seri ömrü tabana hizalı değilse tickler faz kayar');
  });
}
