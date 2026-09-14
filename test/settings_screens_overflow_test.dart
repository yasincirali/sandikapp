import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar hub'ı ve dört alt ekranının taşma regresyonu.
///
/// `settings_hub_test` bilgi mimarisini 1200pt'te doğruluyor; taşma riski
/// ise dar ekranda (320pt) ve her alt ekranın kendi satırlarında (dört
/// seçenekli baz para birimi satırı, saat kutuları, uzun yasal başlıklar).
/// `asset_card_overflow_test` kalıbı: gerçek ekran, `takeException`.
Future<void> _pump(WidgetTester tester, double width,
    {SettingsBolum? bolum}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: SettingsScreen(bolum: bolum),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  for (final w in <double>[320, 360, 430]) {
    testWidgets('${w.toInt()}pt hub', (tester) async {
      await _pump(tester, w);
      expect(tester.takeException(), isNull);
    });

    for (final b in SettingsBolum.values) {
      testWidgets('${w.toInt()}pt ${b.name}', (tester) async {
        await _pump(tester, w, bolum: b);
        expect(tester.takeException(), isNull, reason: b.name);
      });
    }
  }

  testWidgets('büyük metin ölçeği (1.6×) — Görünüm', (tester) async {
    // Baz para birimi satırı dört seçenek yan yana; Dynamic Type büyüyünce
    // en dar ekranda taşmamalı.
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const SettingsScreen(bolum: SettingsBolum.gorunum),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
