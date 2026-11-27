@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yenileme sıklığı GÖRSEL önizlemesi (Ayarlar › Görünüm widget kırılımı ve
/// Bildirimler › Canlı etkinlikler, iOS; 27 Kas 2026).
///
/// Assert etmez; `gorsel` etiketi varsayılanda atlanır. Önce/sonra için
/// aynı dosya eski commit'te `ON_EK=once` ile koşulur:
///   flutter test --run-skipped --dart-define=ON_EK=sonra \
///     --dart-define=CIKTI=build/gorsel test/yenileme_sikligi_gorsel_test.dart
const _onEk = String.fromEnvironment('ON_EK', defaultValue: 'sonra');
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        username: 'deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Future<void> ciz(WidgetTester tester, String ad,
      {required SettingsBolum bolum,
      required String hedef,
      required bool koyu,
      required double olcek}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith(_FakeAuth.new),
      ]);
      const k = ValueKey('kok');
      final p = koyu ? SandikPalette.dark : SandikPalette.light;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(
          key: k,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(olcek),
            ),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: SandikApp.buildTheme(
                  p, koyu ? Brightness.dark : Brightness.light),
              home: SettingsScreen(bolum: bolum),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final f = find.text(hedef);
      await tester.scrollUntilVisible(f, 120,
          scrollable: find.byType(Scrollable).first);
      await tester.runAsync(() => Scrollable.ensureVisible(
          tester.element(f), alignment: 0.15));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
        final img = await b.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(_cikti).createSync(recursive: true);
        File('$_cikti/${_onEk}_$ad.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(const Duration(minutes: 1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  for (final olcek in [1.0, 2.0]) {
    final o = olcek.toStringAsFixed(1);
    testWidgets('widget_koyu_${o}x',
        (t) => ciz(t, 'widget_koyu_${o}x',
            bolum: SettingsBolum.gorunum,
            hedef: 'Ana ekran widget\'ı',
            koyu: true,
            olcek: olcek));
    testWidgets('canli_koyu_${o}x',
        (t) => ciz(t, 'canli_koyu_${o}x',
            bolum: SettingsBolum.bildirimler,
            hedef: 'Hafta sonu da göster',
            koyu: true,
            olcek: olcek));
  }
  testWidgets('canli_acik_1.0x',
      (t) => ciz(t, 'canli_acik_1.0x',
          bolum: SettingsBolum.bildirimler,
          hedef: 'Hafta sonu da göster',
          koyu: false,
          olcek: 1.0));
}
