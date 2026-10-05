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
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/widgets/ilk_varlik_vitrini.dart';
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

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

/// Vitrinin canlı fiyatları — DEMO sayılar (önizleme; canlı değil).
Future<Map<String, YahooQuote>> _demoKotasyon(List<String> _) async => const {
      'ALTIN_GRAM24': YahooQuote(
          symbol: 'ALTIN_GRAM24',
          regularMarketPrice: 6541.91,
          regularMarketChangePercent: 0.45),
      'USDTRY=X': YahooQuote(
          symbol: 'USDTRY=X',
          regularMarketPrice: 42.15,
          regularMarketChangePercent: 0.12),
      'EURTRY=X': YahooQuote(
          symbol: 'EURTRY=X',
          regularMarketPrice: 48.9,
          regularMarketChangePercent: -0.08),
      'ALTIN_CEYREK': YahooQuote(
          symbol: 'ALTIN_CEYREK',
          regularMarketPrice: 10712.45,
          regularMarketChangePercent: -0.21),
    };

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
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {Future<void> Function()? sonra,
      bool acik = false,
      double genislik = 412}) async {
    tester.view.physicalSize = Size(genislik * 2, 915 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        vitrinKotasyonYukleyiciProvider.overrideWithValue(_demoKotasyon),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: acik
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: ekran,
        ),
      ),
    ));
    await tester.pump();
    // Giriş + nabız biter (kademeli; tek büyük pump yalnız bir kare atar).
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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

  // Boş ana ekran — "Canlı fiyat vitrini" (2026-10-04). Gerçek HomeScreen:
  // şerit, başlık bloğu ve vitrin birlikte; fiyatlar DEMO.
  for (final (ad, acik, genislik) in [
    ('ilk_varlik_vitrin_koyu', false, 412.0),
    ('ilk_varlik_vitrin_acik', true, 412.0),
    ('ilk_varlik_vitrin_acik_320', true, 320.0),
  ]) {
    testWidgets('boş ana ekran vitrini — $ad', (tester) async {
      await ciz(tester, ad, const Scaffold(body: SafeArea(child: HomeScreen())),
          acik: acik, genislik: genislik);
    });
  }
}
