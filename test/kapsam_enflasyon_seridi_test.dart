import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reel getiri ve haftalık özet, SEÇİLİ KAPSAM için hesaplanmalı
/// (kullanıcı, 2026-09-17):
///
/// "Ortak ve Birlikte sekmeleri seçildiğinde onlar için de hesaplanmalı,
/// ortağımın hesabında görülenle aynı olmalı, iki ayrı hesap yapmak yerine
/// aynı datadan beslenmeliler."
///
/// 2026-09-21 (ikinci tur, "kart kapsamı izler, başlıkta kimin olduğu
/// yazar"): tek yol kaldı — Bugün kartı HER görünümde çizilir ve o
/// görünümün defterini alır. Eski şeritler ana ekrandan kalktı; reel ve
/// haftalık kartın satırları. Kişisel satırlar (hedef, aylık) yalnızca kendi
/// görünümünde. Yüzdelik dilim şeridi Profil'de (kullanıcının kendi dilimi,
/// ortağın portföyüne bakarken anlamsız).
void main() {
  final src = File('lib/screens/home_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final kart = File('lib/widgets/bugun_karti.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final profil = File('lib/screens/profile_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  // Kartın üç yükleyicisi 2026-09-28'den beri burada (splash da ısıtır);
  // kart yalnızca delege eder. Hesap yolu değişmezleri bu dosyada aranır.
  final yukleyici = File('lib/services/bugun_yukleyici.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('Bugün kartı her görünümde ve kapsamın defteriyle', () {
    final i = src.indexOf('child: BugunKarti(');
    expect(i, greaterThan(0));
    final oncesi = src.substring(i - 400, i);
    expect(oncesi.contains('if (ownView)'), isFalse,
        reason: 'kart artık yalnızca kendi görünümünde değil');
    final blok = src.substring(i, src.indexOf('padding:', i));
    expect(blok.contains('gorunumDurumu(ledgerAssets)'), isTrue,
        reason: 'ortak/Birlikte görünümünde kart kapsamın defterini almalı');
    // `ownView` "ortak değil" demektir ve Birlikte'yi (`_view == null`)
    // de kapsar: kart Birlikte'de yine kendi defterini anlatıyordu
    // (kullanıcı bulgusu 2026-09-21). Kart YALNIZCA `_view == ''` iken
    // kişiseldir; `ownView` bu blokta hiç geçmemeli.
    // Yalnızca kod: karar yorumu ownView'ı adıyla anıyor.
    final kod = blok
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(kod.contains('ownView'), isFalse,
        reason: "ownView Birlikte'yi de kapsar; kart Birlikte'de kendi "
            "defterini değil birleşik defteri anlatmalı");
    expect(blok.contains('state: benGorunumu ? myState'), isTrue,
        reason: 'ham state yalnızca Ben görünümünde');
    expect(blok.contains('kisisel: benGorunumu'), isTrue,
        reason: 'hedef ve aylık özet yalnızca kendi görünümünde');
    expect(src.contains("final benGorunumu = _view == '';"), isTrue,
        reason: 'Ben = boş dize; null Birlikte, id ortak');
    expect(blok.contains('etiket: _bugunEtiketi('), isTrue,
        reason: 'kartın kimin olduğu başlıkta yazar');
    expect(blok.contains("ValueKey('bugun-"), isTrue,
        reason: 'key olmadan görünüm değişince seri yeniden kurulmaz');
  });

  test('ana ekranda ayrı reel/haftalık şerit kalmadı', () {
    expect(src.contains('RealReturnStrip('), isFalse,
        reason: 'reel getiri kartın satırı, ikinci bir yüzey yok');
    expect(src.contains('WeeklySummaryChip('), isFalse);
  });

  test('reel getiri Bugün kartının satırı, aynı hesap yolu', () {
    // `activeAssets` (2026-10-01): ham defter silinmiş lot'ları taşır, Özet
    // süzüyordu; Ana 5,4 puan derken Özet 4,5 yazdı.
    expect(yukleyici.contains('RealReturnService.yillik(state.activeAssets)'),
        isTrue,
        reason: 'aynı hesap yolu — ikinci bir reel getiri hesabı yok');
    expect(yukleyici.contains('RealReturnService.yillik(state.assets)'), isFalse,
        reason: 'ham defter getiri hesabına girmez');
    expect(yukleyici.contains('RemoteConfigService.instance.realReturnEnabled'),
        isTrue,
        reason: 'bayrak kapısı şeritle aynı');
    // Kart kendi kopyasını tutmaz — tek kaynak.
    expect(kart.contains('BugunYukleyici.reel(widget.state'), isTrue);
    // Haftalık satır 2026-10-08'de kalktı (H düzeni çizmiyordu); istek de
    // geri gelmesin.
    expect(kart.contains('BugunYukleyici.haftalik('), isFalse);
    expect(kart.contains('RealReturnService.yillik('), isFalse,
        reason: 'yükleyici mantığı karta geri kopyalanmamalı');
  });

  test('kapsam görünümünde paylaşımlı gün içi önbellek kullanılmaz', () {
    // Önbellek kilit ekranıyla ortak ve oturumdaki kullanıcıya damgalı;
    // ortağın defteriyle doldurulursa kilit ekranı yanlış seriyi gösterir.
    final k = kart.indexOf('Future<Map<int, double>?> _seriYukle(');
    final kartGovde = kart.substring(k, kart.indexOf('catch', k));
    expect(kartGovde.contains('kisisel: widget.kisisel'), isTrue,
        reason: 'kapsam bilgisi yükleyiciye taşınmalı');
    final i = yukleyici.indexOf('static Future<Map<int, double>?> seri(');
    final govde = yukleyici.substring(i, yukleyici.indexOf('catch', i));
    expect(govde.contains('if (!kisisel)'), isTrue);
    // 2026-10-02 (gün içi tek seri): kapsam dalı da önbellekten okur ama
    // KENDİ yuvasından (`breakdown(` kümeyle anahtarlı), Ben yuvasını
    // (`get(`) doldurmaz — kilit ekranı ortağın serisini görmez.
    expect(govde.contains('IntradaySeriesCache.instance'), isTrue);
    expect(govde.contains('.breakdown('), isTrue,
        reason: 'ortak kapsam kendi yuvasını okur');
    expect(govde.contains('getPortfolioHistoryHourlyBreakdown('), isFalse,
        reason: 'gün içi seri yalnızca önbellekten (tek kaynak)');
    expect(govde.indexOf('.breakdown('), lessThan(govde.indexOf('.get(')),
        reason: 'kapsam dalı Ben yuvasından ÖNCE ayrılmalı');
  });

  test('kart boş kapsamda çizilmez', () {
    expect(src.contains('if (aktifLotlar(ledgerAssets).isNotEmpty)'), isTrue,
        reason: 'boş kapsamda (sıfır lira) enflasyonu yenmek diye bir şey yok');
  });

  test('yüzdelik dilim Profil\'de, ana ekranda değil', () {
    expect(src.contains('PercentileStrip('), isFalse,
        reason: 'ana ekranın sorusu "nasıl gidiyorum", sosyal karşılaştırma değil');
    expect(profil.contains('PercentileStrip('), isTrue);
    final i = profil.indexOf('PercentileStrip(');
    final oncesi = profil.substring(i - 500, i);
    expect(oncesi.contains('seviyeGorunurlugu('), isTrue,
        reason: 'başlangıç seviyesinde gizli kapısı korunmalı');
  });
}
