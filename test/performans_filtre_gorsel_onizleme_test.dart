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
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/recap_screen.dart' show yilOzetiProvider;
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Performans › Filtre alt sayfasının (bayrak `goz_alici`) GÖRSEL
/// önizlemesi — `build/gorsel/` altına PNG, önce/sonra için. Assert etmez;
/// `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/performans_filtre_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur; canlı veri değildir.
const _uid = 'u1';

Asset _lot(String id, String ticker, String ad, AssetType tur, double adet,
        double fiyat, {String currency = 'TRY'}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
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
  _lot('3', 'TUPRS.IS', 'Tüpraş', AssetType.hisse, 300, 171.0),
  _lot('4', 'TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler', AssetType.fon, 9000,
      4.1),
  _lot('5', 'TEFAS:TTE', 'İş Portföy BIST Teknoloji', AssetType.fon, 5000,
      3.2),
  _lot('6', 'ALTIN_GRAM', 'Gram Altın', AssetType.altin, 12, 4300),
  _lot('7', 'USD', 'ABD Doları', AssetType.doviz, 800, 1, currency: 'USD'),
  _lot('8', 'BTCTRY', 'Bitcoin', AssetType.kripto, 0.004, 4600000),
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

  Future<void> bekle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ciz(WidgetTester tester, String ad,
      {required Set<String> bayraklar,
      bool sayfa = true,
      String? sec,
      bool acik = false}) async {
    RemoteConfigService.testAcik = bayraklar;
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        yilOzetiProvider.overrideWith((ref) async => null),
        seviyeGorunurlukProvider
            .overrideWithValue(seviyeGorunurlugu(YatirimciSeviyesi.orta)),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: acik
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: const PortfolioPerformanceScreen(),
        ),
      ),
    ));
    await tester.pump();
    await bekle(tester, 40);
    if (sayfa || sec != null) {
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Filtre')).first);
      await bekle(tester);
    }
    if (sec != null) {
      await tester.tap(find.text(sec).last);
      await bekle(tester);
      if (!sayfa) {
        // Sayfayı kapat → kontrol satırındaki çip görünsün.
        await tester.tapAt(const Offset(195, 60));
        await bekle(tester);
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

  const once = {'performans_tek_akis'};
  const sonra = {'performans_tek_akis', 'goz_alici'};
  testWidgets('önce: sayfa', (t) => ciz(t, 'filtre_once', bayraklar: once));
  testWidgets('önce: Fon seçili',
      (t) => ciz(t, 'filtre_once_fon', bayraklar: once, sec: 'Fon'));
  testWidgets('önce: çip',
      (t) => ciz(t, 'filtre_once_cip', bayraklar: once, sec: 'Fon', sayfa: false));
  testWidgets('sonra: sayfa', (t) => ciz(t, 'filtre_sonra', bayraklar: sonra));
  testWidgets('sonra: Fon seçili',
      (t) => ciz(t, 'filtre_sonra_fon', bayraklar: sonra, sec: 'Fon'));
  testWidgets('sonra: çip', (t) =>
      ciz(t, 'filtre_sonra_cip', bayraklar: sonra, sec: 'Fon', sayfa: false));
  testWidgets('sonra: açık tema',
      (t) => ciz(t, 'filtre_sonra_acik', bayraklar: sonra, sec: 'Fon', acik: true));
}
