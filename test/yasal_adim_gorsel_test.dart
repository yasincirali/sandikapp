@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/screens/yasal_onay_kapisi_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yasal adımlar GÖRSEL önizlemesi (okuma şartı kalktı, 2026-11-20).
///
/// Hiç onayı olmayan hesabın kapısı (yatırım uyarısı + Açık Rıza + kutu),
/// kayıt formundaki listeyle aynı bileşen. Assert etmez; `gorsel` etiketi
/// varsayılanda atlanır. Önce/sonra için eski commit'te `ON_EK=once`:
///   flutter test --run-skipped --dart-define=ON_EK=sonra \
///     --dart-define=CIKTI=build/gorsel test/yasal_adim_gorsel_test.dart
const _onEk = String.fromEnvironment('ON_EK', defaultValue: 'sonra');
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');

void main() {
  setUpAll(() async {
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
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'sandık',
        packageName: 'com.sandik.app',
        version: '1.1.10',
        buildNumber: '7',
        buildSignature: '');
    SharedPreferences.setMockInitialValues({});
    YasalOnayService.rpcTesti = (p) async {};
    YasalOnayService.instance.testSifirla();
  });
  tearDown(() => YasalOnayService.rpcTesti = null);

  Future<void> ciz(WidgetTester tester, String ad,
      {required bool koyu, required double olcek}) async {
    const boyut = Size(390, 1400);
    tester.view.physicalSize = boyut * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    final p = koyu ? SandikPalette.dark : SandikPalette.light;
    await tester.pumpWidget(ProviderScope(
      child: RepaintBoundary(
        key: k,
        child: MediaQuery(
          data: MediaQueryData(
              size: boyut, textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('tr', 'TR'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: SandikApp.buildTheme(
                p, koyu ? Brightness.dark : Brightness.light),
            home: YasalOnayKapisiScreen(
              userId: 'u1',
              durum: YasalOnayService.eksikleriHesapla(const []),
              yatirimUyarisiDahil: true,
              onTamam: () {},
            ),
          ),
        ),
      ),
    ));
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
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('koyu_1.0x', (t) => ciz(t, 'koyu_1.0x', koyu: true, olcek: 1));
  testWidgets('acik_1.0x', (t) => ciz(t, 'acik_1.0x', koyu: false, olcek: 1));
  testWidgets('koyu_2.0x', (t) => ciz(t, 'koyu_2.0x', koyu: true, olcek: 2));
}
