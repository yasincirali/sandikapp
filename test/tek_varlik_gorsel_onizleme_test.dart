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
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İki varlık yüzeyinin (portföy varlık detayı + varlık sayfası) GÖRSEL
/// önizlemesi — `build/gorsel/` altına PNG. Sadeleştirme 2 madde 6 (tek
/// varlık sayfası) refactor'unun önce/sonra paritesi için: ortak gövde
/// parçaları çıkarılırken iki ekranın piksel düzeyinde aynı kalması
/// beklenir. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/tek_varlik_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur (sabit, yapay seri); canlı veri değildir.

const _uid = 'u1';

Asset _lot() => Asset(
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
      addedDate: DateTime(2025, 3, 14),
    );

const _kimlik = VarlikKimligi(
  ticker: 'THYAO.IS',
  name: 'Türk Hava Yolları',
  type: AssetType.hisse,
  currency: 'TRY',
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

/// Seri `now`'a göre kurulur (ekranlar pencereyi `DateTime.now()`'dan
/// açar); önce/sonra koşuları dakikalar arayla yapılınca eksen aynı kalır.
List<(int, double)> _yapaySeri() {
  final now = DateTime.now();
  return [
    for (var i = 400; i >= 0; i--)
      (
        now.subtract(Duration(days: i)).millisecondsSinceEpoch,
        250 + 60 * (1 - i / 400) + 8 * ((i % 13) - 6) / 6,
      ),
  ];
}

Future<Map<int, double>> _sayfaSerisi(String ticker, int gun) async {
  final now = DateTime.now();
  final n = gun <= 1 ? 48 : 60;
  final adim = gun <= 1
      ? const Duration(minutes: 10)
      : Duration(minutes: (gun * 1440 / n).round());
  return {
    for (var i = n; i >= 0; i--)
      now.subtract(adim * i).millisecondsSinceEpoch:
          300 + 12 * (1 - i / n) + 3 * ((i % 7) - 3) / 3,
  };
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
    HistoryService.clearCache();
    HistoryService.seriCekici = (sym, range, interval) async => _yapaySeri();
  });
  tearDown(() =>
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {required bool acik}) async {
    tester.view.physicalSize = const Size(390 * 2, 2200 * 2);
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
    for (var i = 0; i < 60; i++) {
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
    // Açık zamanlayıcılar (nabız, açılış kapısı) test sonunda kalmasın.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  for (final acik in [false, true]) {
    final tema = acik ? 'acik' : 'koyu';
    testWidgets('portföy varlık detayı ($tema)', (tester) async {
      await ciz(tester, 'tek_varlik_detay_$tema',
          AssetDetailScreen(asset: _lot(), showBackButton: true),
          acik: acik);
    });

    testWidgets('varlık sayfası ($tema)', (tester) async {
      await ciz(
        tester,
        'tek_varlik_sayfa_$tema',
        Builder(
          builder: (ctx) => Scaffold(
            backgroundColor: ctx.c.background,
            body: const VarlikSayfasi(
              kimlik: _kimlik,
              tamAcilis: true,
              seriYukleyici: _sayfaSerisi,
            ),
          ),
        ),
        acik: acik,
      );
    });
  }
}
