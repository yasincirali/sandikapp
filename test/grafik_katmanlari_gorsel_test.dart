@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// EMA50/EMA200 ve log mum (2026-10-10) — önce/sonra GÖRSEL önizlemesi,
/// `build/gorsel/` altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/grafik_katmanlari_gorsel_test.dart
///
/// Sayılar DEMO'dur (sabit tohumlu yapay seri, 10 yıl günlük); canlı veri
/// değildir.

const _uid = 'u1';

/// Canlı fiyat serinin son değeri: grafiğin ucu (canlı fiyata sabitlenir)
/// demo serisinden kopmasın.
final double _sonFiyat = _yapaySeri().last.$2;

Asset _lot() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: (_sonFiyat * 0.8).roundToDouble(),
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: _sonFiyat,
      addedDate: DateTime(2025, 3, 14),
    );


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
  _FakePortfolio(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _assets, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
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

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

/// 10 yıllık günlük yapay seri: yükselen trend + yavaş dalga + gürültü.
/// Sabit tohum: önce/sonra koşuları aynı çizgiyi verir.
List<(int, double)> _yapaySeri() {
  final now = DateTime.now();
  final r = math.Random(7);
  var log = math.log(40.0);
  final out = <(int, double)>[];
  for (var i = 3650; i >= 0; i--) {
    log += 0.0006 + 0.018 * (r.nextDouble() - 0.5) +
        0.004 * math.sin((3650 - i) / 120);
    out.add((now.subtract(Duration(days: i)).millisecondsSinceEpoch,
        math.exp(log)));
  }
  return out;
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
  tearDown(() =>
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  Future<void> ciz(WidgetTester tester, String ad,
      {required String donem,
      Map<String, Object> tercih = const {},
      List<Override> ek = const []}) async {
    SharedPreferences.setMockInitialValues(tercih);
    await initPreferencesCache();
    HistoryService.clearCache();
    HistoryService.seriCekici = (sym, range, interval) async => _yapaySeri();
    tester.view.physicalSize = const Size(390 * 2, 1100 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio([_lot()])),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        watchlistProvider.overrideWith(_Takip.new),
        ...ek,
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: AssetDetailScreen(asset: _lot(), showBackButton: true),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text(donem).first);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
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

  for (final donem in ['3 ay', '1 yıl', '5 yıl']) {
    final d = donem.replaceAll(' ', '').replaceAll('ı', 'i');
    testWidgets('önce / bugünkü kullanıcı ($donem)', (tester) async {
      await ciz(tester, 'katman_once_$d', donem: donem);
    });
    final gorunur = [
      premiumOzellikleriGorunurProvider.overrideWithValue(true),
      premiumKilitliProvider.overrideWithValue(false),
    ];
    testWidgets('sonra: gizliyken birebir aynı ($donem)', (tester) async {
      await ciz(tester, 'katman_sonra_gizli_$d', donem: donem);
    });
    testWidgets('sonra: EMA50 + EMA200 ($donem)', (tester) async {
      await ciz(tester, 'katman_sonra_ema_$d',
          donem: donem,
          tercih: {'pref_chart_ema50': true, 'pref_chart_ema200': true},
          ek: gorunur);
    });
    testWidgets('sonra: mum + LOG + EMA ($donem)', (tester) async {
      await ciz(tester, 'katman_sonra_mum_log_$d',
          donem: donem,
          tercih: {
            'pref_chart_ema50': true,
            'pref_chart_ema200': true,
            'pref_chart_candle': true,
            'pref_chart_log_scale': true,
          },
          ek: gorunur);
    });
    testWidgets('sonra: kilitli (paywall açık, ücretsiz) ($donem)',
        (tester) async {
      await ciz(tester, 'katman_sonra_kilitli_$d',
          donem: donem,
          tercih: {'pref_chart_ema50': true, 'pref_chart_candle': true},
          ek: [
            premiumOzellikleriGorunurProvider.overrideWithValue(true),
            premiumKilitliProvider.overrideWithValue(true),
          ]);
    });
  }
}
