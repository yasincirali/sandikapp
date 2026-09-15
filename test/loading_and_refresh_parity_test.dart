import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'helpers/kaynak.dart';

/// Yükleme ve yenileme dili tek olsun.
///
/// 2026-09 denetimi: 5 ekranda ham `CircularProgressIndicator` (marka
/// göstergesi `CustomLoadingIndicator` dururken), 15 veri ekranının 3'ünde
/// pull-to-refresh vardı. Bu test ikisini de kilitler.
void main() {
  group('SandikSkeleton', () {
    testWidgets('hareketi azalt açıkken nabız yok, blok yine çizilir',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SandikSkeletonList(rows: 3)),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(SandikSkeleton), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('grafik iskeleti verilen yüksekliği korur — yerleşim zıplamaz',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: SandikSkeletonChart(height: 260)),
      ));
      await t.pump();
      final size = t.getSize(find.byType(SandikSkeletonChart));
      expect(size.height, 260);
    });
  });

  test('ekran/widget katmanında ham CircularProgressIndicator yok', () {
    // Tek istisna: onboarding'deki ilerleme HALKASI (value: 0.46) — yükleme
    // göstergesi değil, dağılım görseli.
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart')) continue;
      if (!p.contains('lib/screens/') && !p.contains('lib/widgets/')) continue;
      if (p.endsWith('onboarding_screen.dart')) continue;
      // Marka göstergesinin kendi GIF-yoksa yedeği.
      if (p.endsWith('custom_loading_indicator.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (lines[i].contains('CircularProgressIndicator')) {
          hits.add('$p:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'CustomLoadingIndicator / SandikSkeleton* kullan:\n'
            '${hits.join('\n')}');
  });

  test('veri ekranlarında pull-to-refresh var', () {
    const dataScreens = [
      'lib/screens/home_screen.dart',
      'lib/screens/portfolio_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/asset_detail_screen.dart',
      'lib/screens/watchlist_screen.dart',
      'lib/screens/watchlist_detail_screen.dart',
      'lib/screens/price_alerts_screen.dart',
      'lib/screens/all_transactions_screen.dart',
      'lib/screens/comparison_screen.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/partnership_requests_screen.dart',
    ];
    for (final p in dataScreens) {
      final src = ekranKaynagiSync(p);
      expect(src.contains('RefreshIndicator('), isTrue,
          reason: '$p: aşağı çekince yenileme yok');
    }
  });
}
