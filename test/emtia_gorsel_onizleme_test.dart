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
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Emtia listeden seçim (2026-10-18) görselleri — `build/gorsel/`.
/// Assert etmez (`gorsel` etiketi CI'da atlanır). Elle:
/// flutter test --tags gorsel test/emtia_gorsel_onizleme_test.dart

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _Fiyat implements AddAssetPriceLookup {
  const _Fiyat();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => ticker == 'BZ=F' ? 61.29 : null;
  @override
  Future<String?> companyName(String ticker) async => null;
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> ciz(WidgetTester tester, String ad,
      Future<void> Function() sonra, {double olcek = 1.0}) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 2);
    addTearDown(tester.view.reset);
    FlutterError.onError = (_) {};
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        addAssetPriceLookupProvider.overrideWithValue(const _Fiyat()),
      ],
      child: RepaintBoundary(
        key: k,
        child: MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 844),
              padding: const EdgeInsets.only(top: 47),
              textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
            home: const AddAssetScreen(prefillType: AssetType.emtia),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await sonra();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/emtia_$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Finder cip(String s) => find.textContaining(s, findRichText: true);

  Future<void> sec(WidgetTester t, String s) async {
    await t.tap(find.byType(PopupMenuButton<String>));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(cip(s));
  }

  testWidgets('bos', (t) => ciz(t, '1_bos', () async {}));
  testWidgets('liste acik', (t) => ciz(t, '2_liste', () async {
        await t.tap(find.byType(PopupMenuButton<String>));
      }));
  testWidgets('brent', (t) => ciz(t, '3_brent', () => sec(t, 'Petrol (Brent)')));
  testWidgets('diger', (t) => ciz(t, '4_diger', () => sec(t, 'Diğer (sembol yaz)')));
  testWidgets('buyuk yazi liste', (t) => ciz(t, '5_yazi2x', () async {
        await t.tap(find.byType(PopupMenuButton<String>));
      }, olcek: 2.0));
}
