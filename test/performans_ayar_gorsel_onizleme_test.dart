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
import 'package:portfoy_takip/models/grafik_tipi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/grafik_tipi_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `performans_ayar_sade` GÖRSEL önizlemesi — `build/gorsel/` altına PNG.
///
/// Ayarlar'ın gruplu düzeni, hub'ın "Gelişmiş" grubu, Performans'taki
/// "Bugünkü portföyle" rozeti ve iki tipli grafik menüsü gerçek tema ve
/// DM Sans ile. Assert etmez; `gorsel` etiketi varsayılanda atlanır.
///   flutter test --run-skipped test/performans_ayar_gorsel_onizleme_test.dart

const _uid = 'u1';

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        username: 'deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          Asset(
            id: 'THYAO-1',
            userId: _uid,
            name: 'Türk Hava Yolları',
            ticker: 'THYAO.IS',
            type: AssetType.hisse,
            quantity: 100,
            purchasePrice: 250.75,
            currency: 'TRY',
            notes: '',
            isManualPrice: false,
            currentPrice: 312.40,
            addedDate: DateTime(2026, 3, 14),
          ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
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
    RemoteConfigService.testAcik = {'performans_ayar_sade'};
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
    grafikTipiNotifier.value = GrafikTipi.varsayilan;
  });

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {Future<void> Function()? sonra,
      bool simulasyon = false,
      double genislik = 412,
      double yukseklik = 915}) async {
    tester.view.physicalSize = Size(genislik * 2, yukseklik * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      authProvider.overrideWith(_FakeAuth.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
    ]);
    addTearDown(c.dispose);
    if (simulasyon) await c.read(bugunkuPortfoyleProvider.notifier).set(true);
    const k = ValueKey('kok');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
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
    for (var i = 0; i < 20; i++) {
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

  testWidgets('Ayarlar hub — Gelişmiş açık', (tester) async {
    await ciz(tester, 'ayar_sade_hub', const SettingsScreen(),
        sonra: () async {
      await tester.tap(find.text('GELİŞMİŞ'));
      await tester.pumpAndSettle();
    });
  });

  for (final (ad, b) in [
    ('ayar_sade_gorunum', SettingsBolum.gorunum),
    ('ayar_sade_hesap', SettingsBolum.hesap),
    ('ayar_sade_yardim', SettingsBolum.yardim),
  ]) {
    testWidgets('Ayarlar $ad', (tester) async {
      await ciz(tester, ad, SettingsScreen(bolum: b), yukseklik: 1500);
    });
  }

  testWidgets('Ayarlar Görünüm 320pt', (tester) async {
    await ciz(tester, 'ayar_sade_gorunum_320',
        const SettingsScreen(bolum: SettingsBolum.gorunum),
        genislik: 320, yukseklik: 1500);
  });

  testWidgets('Performans — Bugünkü portföyle rozeti', (tester) async {
    await ciz(tester, 'perf_sade_rozet', const PortfolioPerformanceScreen(),
        simulasyon: true, sonra: () async {
      await tester.tap(find.text('1 ay'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Kapsam: ')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    });
  });

  testWidgets('Grafik tipi menüsü — iki tip', (tester) async {
    await ciz(
        tester,
        'perf_sade_grafik_tipi',
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(SandikSpace.lg),
            child: Align(
              alignment: Alignment.topLeft,
              child: GrafikTipiSecici(gorunum: GrafikTipiGorunum.duz),
            ),
          ),
        ), sonra: () async {
      await tester.tap(find.byType(GrafikTipiSecici));
      await tester.pumpAndSettle();
    });
  });
}
