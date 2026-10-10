@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paywall GÖRSEL önizlemesi — `build/gorsel/paywall_*.png`. Assert etmez;
/// `gorsel` etiketi CI'da atlanır. Önce/sonra için aynı testi main'de ve
/// dalda koş:
///   flutter test --run-skipped test/paywall_gorsel_onizleme_test.dart
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> ciz(WidgetTester t, String ad, String kaynak,
      {required Set<String> bayraklar, double boy = 844}) async {
    RemoteConfigService.testAcik = {'paywall_enabled', ...bayraklar};
    t.view.physicalSize = Size(390 * 2, boy * 2);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    const k = ValueKey('kok');
    await t.pumpWidget(ProviderScope(
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PaywallScreen(source: kaynak),
        ),
      ),
    ));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.runAsync(() async {
      final b = t.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 10));
  }

  testWidgets('deste: mum/EMA kilidinden', (t) async {
    await ciz(t, 'paywall_deste_grafik', 'grafik_mum',
        bayraklar: {'paywall_deste'});
  });
  testWidgets('deste: kısmi aktarım kilidinden', (t) async {
    await ciz(t, 'paywall_deste_kismi_aktar', 'portfoy_kismi_aktar',
        bayraklar: {'paywall_deste', 'coklu_portfoy'});
  });
  testWidgets('klasik paywall: özellik listesi ve tablo', (t) async {
    await ciz(t, 'paywall_klasik', 'profile_banner',
        bayraklar: {'coklu_portfoy'}, boy: 2600);
  });
}
