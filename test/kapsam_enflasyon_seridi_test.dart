import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ana ekrandaki enflasyon (TÜFE) ve haftalık piyasa şeritleri SEÇİLİ
/// KAPSAM için hesaplanmalı (kullanıcı, 2026-09-17):
///
/// "Ortak ve Birlikte sekmeleri seçildiğinde onlar için de hesaplanmalı,
/// ortağımın hesabında görülenle aynı olmalı, iki ayrı hesap yapmak yerine
/// aynı datadan beslenmeliler."
///
/// Çözüm: şeritler `myState.assets` yerine kapsamın defterini
/// (`ledgerAssets`: kendi / ortağın / ikisi) alır ve `key` ile kapsama
/// bağlanır (seriyi initState'te bir kez kuruyorlar). Aynı fonksiyon
/// (`RealReturnService.yillik`, `PeriodSummaryService.compute`) ve aynı
/// canlı kur kullanıldığı için ortağın kendi ekranındaki sayı birebir aynı
/// çıkar — ikinci bir hesap yolu yok. Yüzdelik dilim şeridi kendi
/// görünümünde kalır (sosyal karşılaştırma, kullanıcının kendi dilimi).
void main() {
  final src = File('lib/screens/home_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('reel getiri şeridi kapsamın defterini alır ve kapsama bağlı', () {
    final blok = src.substring(src.indexOf('child: RealReturnStrip('));
    // Widget çağrısının gövdesi: `padding:` satırına kadar.
    final parca = blok.substring(0, blok.indexOf('padding:'));
    expect(parca.contains('myAssets: ledgerAssets'), isTrue,
        reason: 'ortak sekmesinde hâlâ kendi portföyün enflasyonu yazılır');
    expect(parca.contains("ValueKey('reel-"), isTrue,
        reason: 'key olmadan sekme değişince seri yeniden kurulmaz');
  });

  test('haftalık özet çipi kapsamın defterini alır ve kapsama bağlı', () {
    final blok = src.substring(src.indexOf('child: WeeklySummaryChip('));
    final parca = blok.substring(0, blok.indexOf('padding:'));
    expect(parca.contains('myAssets: ledgerAssets'), isTrue);
    expect(parca.contains("ValueKey('hafta-"), isTrue);
  });

  test('şeritler yalnızca kendi görünümüne KİLİTLİ değil', () {
    expect(src.contains('if (ownView && !isEmptyOwn) ...['), isFalse,
        reason: 'eski kapı geri gelmiş — ortak/birlikte sekmesinde şerit yok');
    expect(src.contains('if (aktifLotlar(ledgerAssets).isNotEmpty) ...['),
        isTrue,
        reason: 'boş kapsamda (sıfır lira) enflasyonu yenmek diye bir şey yok');
  });

  test('yüzdelik dilim kendi görünümünde kalır', () {
    final i = src.indexOf('child: PercentileStrip(');
    final oncesi = src.substring(i - 400, i);
    expect(oncesi.contains('if (ownView &&'), isTrue,
        reason: 'ortağın portföyüne bakarken kullanıcının kendi dilimini '
            'göstermek hangi portföyden bahsedildiğini belirsizleştirir');
  });
}
