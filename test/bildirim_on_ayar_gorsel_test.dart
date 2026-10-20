@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

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

/// Ayarlar › Bildirimler GÖRSEL önizlemesi (Az · Dengeli · Çok, 2026-10-20).
///
/// Koyu/açık tema × 1.0/2.0 yazı, gerçek tema ve DM Sans ile PNG yazar.
/// Assert etmez; `gorsel` etiketi varsayılanda atlanır. Önce/sonra için
/// aynı dosya eski commit'te `ON_EK=once` ile koşulur:
///   flutter test --run-skipped --dart-define=ON_EK=sonra \
///     --dart-define=CIKTI=build/gorsel test/bildirim_on_ayar_gorsel_test.dart
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
      {required bool koyu, required double olcek, bool ayrinti = false}) async {
    tester.view.physicalSize = const Size(390 * 2, 1300 * 2);
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
            size: const Size(390, 1300),
            textScaler: TextScaler.linear(olcek),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(
                p, koyu ? Brightness.dark : Brightness.light),
            home: const SettingsScreen(bolum: SettingsBolum.bildirimler),
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Eski düzende grup yok; yalnız yeni düzende açılır.
    final grup = find.text('AYRINTILI');
    if (ayrinti && grup.evaluate().isNotEmpty) {
      await tester.tap(grup);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_cikti).createSync(recursive: true);
      File('$_cikti/${_onEk}_$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Ekranın gecikmeli işleri (yükleme zamanlayıcıları) test bitmeden
    // sönsün; yoksa "Timer is still pending" PNG'yi yazdıktan sonra kırar.
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  for (final koyu in [true, false]) {
    for (final olcek in [1.0, 2.0]) {
      final ad = '${koyu ? 'koyu' : 'acik'}_${olcek.toStringAsFixed(1)}x';
      testWidgets(ad, (tester) => ciz(tester, ad, koyu: koyu, olcek: olcek));
    }
  }
  testWidgets('koyu_1.0x_ayrintili',
      (tester) => ciz(tester, 'koyu_1.0x_ayrintili',
          koyu: true, olcek: 1.0, ayrinti: true));
}
