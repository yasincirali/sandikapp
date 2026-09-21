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

  test('reel getiri ve haftalık Bugün kartının satırı, aynı hesap yolu', () {
    expect(kart.contains('RealReturnService.yillik(widget.state.assets)'), isTrue,
        reason: 'aynı hesap yolu — ikinci bir reel getiri hesabı yok');
    expect(kart.contains('PeriodSummaryService.compute('), isTrue);
    expect(kart.contains('SummaryPeriod.birHafta'), isTrue);
    expect(kart.contains('RemoteConfigService.instance.realReturnEnabled'), isTrue,
        reason: 'bayrak kapısı şeritle aynı');
    expect(kart.contains('RemoteConfigService.instance.periodSummaryEnabled'),
        isTrue);
  });

  test('kapsam görünümünde paylaşımlı gün içi önbellek kullanılmaz', () {
    // Önbellek kilit ekranıyla ortak ve oturumdaki kullanıcıya damgalı;
    // ortağın defteriyle doldurulursa kilit ekranı yanlış seriyi gösterir.
    final i = kart.indexOf('Future<Map<int, double>?> _seriYukle()');
    final govde = kart.substring(i, kart.indexOf('catch', i));
    expect(govde.contains('if (!widget.kisisel)'), isTrue);
    expect(govde.contains('getPortfolioHistoryHourlyBreakdown('), isTrue);
    expect(govde.indexOf('getPortfolioHistoryHourlyBreakdown('),
        lessThan(govde.indexOf('IntradaySeriesCache.instance')),
        reason: 'kapsam dalı önbellekten ÖNCE ayrılmalı');
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
