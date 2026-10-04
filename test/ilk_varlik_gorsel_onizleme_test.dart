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
import 'package:portfoy_takip/models/ilk_varlik_secimi.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/ilk_varlik_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme 2 / A'nın GÖRSEL önizlemesi — `build/gorsel/` altına PNG.
///
/// Emülatörde oturum gerektiren yüzeyler (boş ana ekran, Varlık Ekle) demo
/// modundan açılamıyor; bu dosya onları gerçek tema ve DM Sans ile çizer.
/// Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/ilk_varlik_gorsel_onizleme_test.dart

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 6541.91;
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
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfigService.testAcik = {'ilk_varlik_kolay'};
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {Future<void> Function()? sonra}) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: ekran,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    if (sonra != null) await sonra();
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('varlık ekle — bayrak açık', (tester) async {
    await ciz(tester, 'ilk_varlik_form', const AddAssetScreen());
  });

  testWidgets('varlık ekle — gram altın seçili', (tester) async {
    await ciz(tester, 'ilk_varlik_altin',
        const AddAssetScreen(hizliSecim: IlkVarlikSecimi.gramAltin));
  });

  testWidgets('varlık ekle — ayrıntı açık', (tester) async {
    await ciz(tester, 'ilk_varlik_ayrinti',
        const AddAssetScreen(hizliSecim: IlkVarlikSecimi.dolar),
        sonra: () async {
      final f = find.text('Ayrıntı ekle (komisyon, not)');
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('boş ana ekran çipleri', (tester) async {
    await ciz(
        tester,
        'ilk_varlik_bos_ekran',
        Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: IlkVarlikSecici(onSec: (_) {})),
            ),
          ),
        ));
  });
}
