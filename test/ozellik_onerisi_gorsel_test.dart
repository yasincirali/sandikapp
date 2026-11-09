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
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/varlik_guncelle.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/providers/ozellik_onerisi_provider.dart';
import 'package:portfoy_takip/services/ozellik_onerisi.dart';
import 'package:portfoy_takip/widgets/ozellik_onerisi_karti.dart';

/// Özellik önerisi GÖRSEL önizlemesi (2026-10-20): Bugün kartı + altında
/// öneri kartı (önce = öneri yok); koyu/açık × 1.0/2.0 yazı. Assert etmez;
/// `gorsel` etiketi varsayılanda atlanır.
///   flutter test --run-skipped \
///     --dart-define=CIKTI=build/gorsel test/ozellik_onerisi_gorsel_test.dart
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');
const _uid = 'u1';

Asset _lot(String id, String ticker, String ad, AssetType tur, double adet,
        double alis, double simdi,
        {bool elle = false, DateTime? tarih}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: elle,
      currentPrice: simdi,
      addedDate: tarih ?? DateTime(2026, 10, 19),
      createdAt: tarih ?? DateTime(2026, 10, 19),
    );

final _defter = [
  _lot('a', 'ASELS.IS', 'Aselsan', AssetType.hisse, 40, 152.3, 155.1),
  _lot('b', 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 100, 288, 312.4),
];

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _defter, ownerId: _uid, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _Ortaklar extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _OrtakLotlari extends PartnerAssetsNotifier {
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
    DbLogger.silentInTests = true;
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest =
        (_) => const ReelGetiriSatiri(nominal: 48.2, inflation: 45.1);
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
  });

  Future<void> ciz(WidgetTester tester, String ad,
      {required bool koyu,
      required double olcek,
      required OzellikOnerisi? oneri,
      bool portfoy = false}) async {
    final boy = portfoy ? 900.0 : (olcek > 1 ? 1100.0 : 700.0);
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_Portfoy.new),
      authProvider.overrideWith(_Auth.new),
      partnersProvider.overrideWith(_Ortaklar.new),
      allPartnerAssetsProvider.overrideWith(_OrtakLotlari.new),
      watchlistProvider.overrideWith(_Takip.new),
      varlikGuncellemeProvider.overrideWithValue(VarlikGuncellemeDurumu.gizli),
      cokluPortfoyGorunurProvider.overrideWithValue(false),
      ozellikOnerisiProvider.overrideWithValue(oneri),
    ]);
    final state = await c.read(portfolioProvider.future);
    await c.read(authProvider.future);
    const k = ValueKey('kok');
    final p = koyu ? SandikPalette.dark : SandikPalette.light;
    const hp = SandikSpace.md;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: RepaintBoundary(
        key: k,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(390, boy),
            textScaler: TextScaler.linear(olcek),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(
                p, koyu ? Brightness.dark : Brightness.light),
            home: portfoy
                ? const PortfolioScreen()
                : Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BugunKarti(
                        state: state,
                        padding: const EdgeInsets.fromLTRB(hp, hp, hp, 0),
                      ),
                      const OzellikOnerisiKarti(
                          padding:
                              EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, 0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_cikti).createSync(recursive: true);
      File('$_cikti/$ad.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  for (final oneri in <OzellikOnerisi?>[null, ...OzellikOnerisi.values]) {
    for (final koyu in [true, false]) {
      for (final olcek in [1.0, 2.0]) {
        final ad = '${oneri == null ? 'once' : 'sonra_${oneri.anahtar}'}_'
            '${koyu ? 'koyu' : 'acik'}_${olcek.toStringAsFixed(1)}x';
        testWidgets(
            ad, (t) => ciz(t, ad, koyu: koyu, olcek: olcek, oneri: oneri));
      }
    }
  }
  // Portföy sekmesi (2026-10-20 "oralara koyalım"): önce/sonra.
  for (final oneri in <OzellikOnerisi?>[null, OzellikOnerisi.alarm]) {
    for (final koyu in [true, false]) {
      for (final olcek in [1.0, 2.0]) {
        final ad = 'portfoy_${oneri == null ? 'once' : 'sonra'}_'
            '${koyu ? 'koyu' : 'acik'}_${olcek.toStringAsFixed(1)}x';
        testWidgets(
            ad,
            (t) => ciz(t, ad,
                koyu: koyu, olcek: olcek, oneri: oneri, portfoy: true));
      }
    }
  }
}
