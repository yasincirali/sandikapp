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
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/leaderboard_screen.dart';
import 'package:portfoy_takip/screens/siralama_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sıralama sayfasının (bayrak `siralama_tek_sayfa`) GÖRSEL önizlemesi —
/// `build/gorsel/` altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/siralama_gorsel_onizleme_test.dart
///
/// Sunucu yok: Herkes sekmesi rıza kartını ya da boş havuzu, Ortaklarım
/// sekmesi ortakların satırlarını (getiri hesaplanamadığı için "—") çizer.
/// Amaç yerleşim: sekme şeridi, ortak dönem seçici, üst çubuk eylemleri.

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
  _FakePartners(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

PartnerAccount _ortak(String id, String ad) => PartnerAccount(
      user: AppUser(
          id: id,
          email: '$id@example.com',
          displayName: ad,
          createdAt: DateTime(2026, 1, 1)),
      isActive: true,
    );

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
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {bool optIn = true,
      bool ortakli = true,
      bool acik = false,
      double genislik = 412,
      Future<void> Function()? sonra}) async {
    SharedPreferences.setMockInitialValues(
        optIn ? {'pref_leaderboard_opt_in': true} : {});
    await initPreferencesCache();
    RemoteConfigService.testAcik = {'siralama_tek_sayfa'};
    tester.view.physicalSize = Size(genislik * 2, 915 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(() => _FakePartners(ortakli
            ? [_ortak('p1', 'Ayşe Yılmaz'), _ortak('p2', 'Mehmet Demir')]
            : const [])),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
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
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (sonra != null) {
      await sonra();
      for (var i = 0; i < 10; i++) {
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
  }

  testWidgets('Ortaklarım — ortaklı yarış', (tester) async {
    await ciz(tester, 'siralama_ortaklarim',
        SiralamaScreen(zirveRizaYukleyici: () async => true));
  });

  testWidgets('Ortaklarım — katılım daveti (opt-in kapalı)', (tester) async {
    await ciz(tester, 'siralama_ortaklarim_davet',
        SiralamaScreen(zirveRizaYukleyici: () async => false),
        optIn: false);
  });

  testWidgets('Herkes — rıza kartı', (tester) async {
    await ciz(
        tester,
        'siralama_herkes_riza',
        SiralamaScreen(
            sekme: SiralamaSekmesi.herkes,
            zirveRizaYukleyici: () async => false));
  });

  testWidgets('Herkes — katılımcı, boş havuz', (tester) async {
    await ciz(
        tester,
        'siralama_herkes_bos',
        SiralamaScreen(
            sekme: SiralamaSekmesi.herkes,
            zirveRizaYukleyici: () async => true));
  });

  testWidgets('Ortaklarım — açık tema 320pt, ortaksız', (tester) async {
    await ciz(tester, 'siralama_ortaklarim_acik_320',
        SiralamaScreen(zirveRizaYukleyici: () async => true),
        acik: true, genislik: 320, ortakli: false);
  });

  testWidgets('kıyas: bayrak kapalıyken eski Yarış', (tester) async {
    // `LeaderboardScreen` bayrağa bakmaz; bayrak kapalıyken girişler onu açar.
    await ciz(tester, 'siralama_eski_yaris', const LeaderboardScreen());
  });
}
