import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';

/// `pref_*` anahtar literal'leri yalnızca `lib/config/pref_keys.dart`'ta.
///
/// Aynı anahtar iki dosyada ayrı `const` olarak yaşıyordu; biri değişince
/// Ayarlar'daki toggle ile bildirim yolu sessizce ayrışırdı.
void main() {
  test("'pref_…' literal'i PrefKeys dışında yazılmaz", () {
    final pattern = RegExp(r"'pref_[a-z0-9_]+'");
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart') || p.endsWith('config/pref_keys.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(lines[i])) hits.add('$p:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: 'PrefKeys.* kullan:\n${hits.join('\n')}');
  });

  test('PrefKeys değerleri benzersiz', () {
    const all = [
      PrefKeys.themeMode,
      PrefKeys.signalNotifications,
      PrefKeys.partnerNotifications,
      PrefKeys.balanceHidden,
      PrefKeys.lockScreenAmounts,
      PrefKeys.liveActivityStartMin,
      PrefKeys.liveActivityEndMin,
      PrefKeys.liveActivityWeekend,
      PrefKeys.premiumUnlocked,
      PrefKeys.indicatorsByType,
      PrefKeys.chartOverlayMa20,
      PrefKeys.chartLogScale,
      PrefKeys.leaderboardOptIn,
      PrefKeys.surfaceIsLight,
      PrefKeys.signalThresholdByType,
      PrefKeys.signalNeutralPush,
      PrefKeys.signalFrequencyByType,
      PrefKeys.signalHoursByType,
      PrefKeys.fxMigrationLastRunMs,
      PrefKeys.portfolioCachePrefix,
    ];
    expect(all.toSet().length, all.length);
  });
}
