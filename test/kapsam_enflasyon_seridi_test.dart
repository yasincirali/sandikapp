import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reel getiri ve haftalık özet, SEÇİLİ KAPSAM için hesaplanmalı
/// (kullanıcı, 2026-09-17):
///
/// "Ortak ve Birlikte sekmeleri seçildiğinde onlar için de hesaplanmalı,
/// ortağımın hesabında görülenle aynı olmalı, iki ayrı hesap yapmak yerine
/// aynı datadan beslenmeliler."
///
/// 2026-09-21 sadeleştirmesinden sonra iki yol var, ikisi de aynı hesap:
///   · KENDİ görünümü → Bugün kartının satırları (`BugunKarti` kendi
///     `state.assets`'ini `RealReturnService.yillik` /
///     `PeriodSummaryService.compute`'a verir).
///   · ORTAK / BİRLİKTE görünümü → eski şeritler, kapsamın defteriyle
///     (`ledgerAssets`) ve kapsama bağlı `key` ile.
/// Yüzdelik dilim şeridi Profil'e taşındı (kullanıcının kendi dilimi,
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

  test('ortak görünümünde reel getiri şeridi kapsamın defterini alır', () {
    final blok = src.substring(src.indexOf('child: RealReturnStrip('));
    final parca = blok.substring(0, blok.indexOf('padding:'));
    expect(parca.contains('myAssets: ledgerAssets'), isTrue,
        reason: 'ortak sekmesinde hâlâ kendi portföyün enflasyonu yazılır');
    expect(parca.contains("ValueKey('reel-"), isTrue,
        reason: 'key olmadan sekme değişince seri yeniden kurulmaz');
    final oncesi = src.substring(src.indexOf('child: RealReturnStrip(') - 200,
        src.indexOf('child: RealReturnStrip('));
    expect(oncesi.contains('if (!ownView)'), isTrue,
        reason: 'kendi görünümünde şerit yok — satır Bugün kartında');
  });

  test('ortak görünümünde haftalık özet çipi kapsamın defterini alır', () {
    final blok = src.substring(src.indexOf('child: WeeklySummaryChip('));
    final parca = blok.substring(0, blok.indexOf('padding:'));
    expect(parca.contains('myAssets: ledgerAssets'), isTrue);
    expect(parca.contains("ValueKey('hafta-"), isTrue);
  });

  test('kendi görünümünde reel getiri ve haftalık Bugün kartının satırı', () {
    expect(kart.contains('RealReturnService.yillik(widget.state.assets)'), isTrue,
        reason: 'aynı hesap yolu — ikinci bir reel getiri hesabı yok');
    expect(kart.contains('PeriodSummaryService.compute('), isTrue);
    expect(kart.contains('SummaryPeriod.birHafta'), isTrue);
    expect(kart.contains('RemoteConfigService.instance.realReturnEnabled'), isTrue,
        reason: 'bayrak kapısı şeritle aynı');
    expect(kart.contains('RemoteConfigService.instance.periodSummaryEnabled'),
        isTrue);
  });

  test('Bugün kartı yalnızca kendi görünümünde', () {
    final i = src.indexOf('child: BugunKarti(');
    final oncesi = src.substring(i - 400, i);
    expect(oncesi.contains('if (ownView)'), isTrue);
  });

  test('şeritler boş kapsamda çizilmez', () {
    expect(src.contains('if (aktifLotlar(ledgerAssets).isNotEmpty) ...['),
        isTrue,
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
