import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Crashlytics: `ActionTrampolineKt.launchTrampolineAction` →
/// "List adapter activity trampoline invoked without specifying target
/// intent" (2026-10-14). Uygulama Glance kullanmaz; trampoline aktiviteleri
/// yalnızca home_widget'ın glance-appwidget bağımlılığından gelir ve
/// ekstrasız başlatılınca düşer. Kalıcı çözüm manifest'te `tools:node="remove"`.
/// Bu test o satırların sessizce silinmesini ve uygulamanın Glance'e
/// geçip trampoline'ı hâlâ düşürmesini yakalar.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  const trampolinler = [
    'androidx.glance.appwidget.action.ActionTrampolineActivity',
    'androidx.glance.appwidget.action.InvisibleActionTrampolineActivity',
  ];

  for (final ad in trampolinler) {
    test('$ad birleştirilmiş manifest\'ten düşürülüyor', () {
      expect(
        RegExp('<activity\\s+android:name="${RegExp.escape(ad)}"\\s+'
                'tools:node="remove"\\s*/>')
            .hasMatch(manifest),
        isTrue,
        reason: 'Glance trampoline aktivitesi geri gelirse ekstrasız '
            'başlatmada uygulama çöker (Crashlytics, 2026-10-14).',
      );
    });
  }

  test('Android widget kodu Glance kullanmıyor (kullanırsa remove kalkmalı)',
      () {
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'));
    for (final f in kotlin) {
      final kaynak = f.readAsStringSync();
      expect(
        kaynak.contains('androidx.glance') ||
            kaynak.contains('HomeWidgetGlance'),
        isFalse,
        reason: '${f.path} Glance kullanıyor: AndroidManifest.xml\'deki '
            'trampoline tools:node="remove" satırları Glance aksiyonlarını '
            'bozar; kaldırıp çökme için başka çözüm gerekir.',
      );
    }
  });
}
