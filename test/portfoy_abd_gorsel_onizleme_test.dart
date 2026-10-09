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
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy BIST / ABD hisse ayrımının (bayrak `abd_hisse`) GÖRSEL
/// önizlemesi — `build/gorsel/` altına PNG, önce/sonra için. Assert etmez;
/// `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/portfoy_abd_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur; canlı veri değildir.
const _uid = 'u1';

Asset _lot(String id, String ticker, String ad, AssetType tur, double adet,
        double fiyat, {String currency = 'TRY', String? sub}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
      subCategory: sub,
      quantity: adet,
      purchasePrice: fiyat * 0.9,
      currency: currency,
      purchaseFxRate: currency == 'USD' ? 38.0 : 1.0,
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2025, 3, 14),
    );

final _varliklar = [
  _lot('1', 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 400, 312.4),
  _lot('2', 'ASELS.IS', 'Aselsan', AssetType.hisse, 600, 142.6),
  _lot('3', 'AAPL', 'Apple', AssetType.hisse, 10, 228.5,
      currency: 'USD', sub: 'abd'),
  _lot('4', 'NVDA', 'NVIDIA', AssetType.hisse, 8, 181.2,
      currency: 'USD', sub: 'abd'),
  _lot('5', 'TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler', AssetType.fon, 9000,
      4.1),
  _lot('6', 'ALTIN_GRAM', 'Gram Altın', AssetType.altin, 6, 4300),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _varliklar, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
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
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> ciz(WidgetTester tester, String ad,
      {required Set<String> bayraklar,
      String? dokun,
      bool acik = false}) async {
    RemoteConfigService.testAcik = bayraklar;
    tester.view.physicalSize = const Size(390 * 2, 1100 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        watchlistProvider.overrideWith(_Takip.new),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: acik
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: const PortfolioScreen(),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (dokun != null) {
      await tester.tap(find.textContaining(dokun).first);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  const kucuk = {'portfoy_dagilim_cubugu', 'goz_alici'};
  testWidgets('önce: küçük halka', (t) => ciz(t, 'abd_once_kucuk',
      bayraklar: kucuk));
  testWidgets('sonra: küçük halka', (t) => ciz(t, 'abd_sonra_kucuk',
      bayraklar: {...kucuk, 'abd_hisse'}));
  testWidgets('sonra: ABD süzgeci', (t) => ciz(t, 'abd_sonra_abd_secili',
      bayraklar: {...kucuk, 'abd_hisse'}, dokun: 'ABD Hisse'));
  testWidgets('sonra: BIST süzgeci', (t) => ciz(t, 'abd_sonra_bist_secili',
      bayraklar: {...kucuk, 'abd_hisse'}, dokun: 'BIST Hisse'));
  testWidgets('sonra: açık tema', (t) => ciz(t, 'abd_sonra_kucuk_acik',
      bayraklar: {...kucuk, 'abd_hisse'}, acik: true));
  testWidgets('önce: büyük halka', (t) => ciz(t, 'abd_once_buyuk',
      bayraklar: {'goz_alici'}));
  testWidgets('sonra: büyük halka', (t) => ciz(t, 'abd_sonra_buyuk',
      bayraklar: {'goz_alici', 'abd_hisse'}));
}
