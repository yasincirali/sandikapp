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
import 'package:intl/intl.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/onboarding_screen.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tanıtım turunun "Bugün ne oldu?" adımı — uzun hedefte spot ve açıklama
/// kartı (kullanıcı bulgusu 2026-10-12). `build/gorsel/` altına PNG; assert
/// etmez, `gorsel` etiketi CI'da atlanır.
///   GORSEL_AD=sonra flutter test --run-skipped test/tur_uzun_hedef_gorsel_test.dart

Asset _asset(String ticker, double qty, double alis, double simdi) => Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: '$ticker.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: simdi,
      addedDate: DateTime(2026, 3, 14),
    );

final _defter = [
  _asset('THYAO', 100, 300, 312.40),
  _asset('ASELS', 10, 1100, 1000),
];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = (_) =>
        const ReelGetiriSatiri(nominal: 48.2, inflation: 45.1);
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
  });

  final ad = Platform.environment['GORSEL_AD'] ?? 'sonra';
  for (final b in [Brightness.dark, Brightness.light]) {
    for (final genislik in [390.0]) {
      testWidgets('tur bugün — ${b.name}', (tester) async {
        tester.view.physicalSize = Size(genislik * 2, 844 * 2);
        tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(overrides: [
          portfolioProvider.overrideWith(_FakePortfolio.new),
        ]);
        addTearDown(container.dispose);
        final state = await container.read(portfolioProvider.future);
        final gun = dayKey(DateTime.now());
        int ms(int dk) =>
            gun.add(Duration(minutes: dk)).millisecondsSinceEpoch;
        final kThy = positionKey(_defter[0]);
        final kAsl = positionKey(_defter[1]);
        // Gün içi şekil: açılıştan sonra hafif düşüş, öğleden sonra yükseliş.
        final toplam = <int, double>{};
        final thy = <int, double>{};
        final asl = <int, double>{};
        for (var i = 0; i <= 60; i++) {
          final t = 600 + i * 5;
          final egri = i < 20 ? -i * 12.0 : (i - 20) * 22.0 - 240;
          toplam[ms(t)] = 41000 + egri;
          thy[ms(t)] = 30330 + egri * 0.9;
          asl[ms(t)] = 10100 - i * 1.6;
        }
        IntradaySeriesCache.instance.seedForTest(
          series: toplam,
          fetchedAt: DateTime.now(),
          seansGunu: gun,
          kume: state.activeAssets.toList(),
          byPosition: {kThy: thy, kAsl: asl},
          positionType: {kThy: AssetType.hisse, kAsl: AssetType.hisse},
        );
        final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
        const k = ValueKey('kok');
        Widget kutu(String yazi, double boy) => Padding(
              padding: const EdgeInsets.all(SandikSpace.md),
              child: SizedBox(
                height: boy,
                child: SandikCard(child: Center(child: Text(yazi))),
              ),
            );
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: k,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('tr'),
              theme: SandikApp.buildTheme(p, b),
              builder: (context, child) => OnboardingTourHost(child: child!),
              home: Scaffold(
                appBar: AppBar(title: const Text('Ana sayfa')),
                body: ListView(
                  children: [
                    kutu('Toplam varlık', 150),
                    TourAnchor(
                      target: TourTarget.bugunKarti,
                      child: BugunKarti(state: state),
                    ),
                    kutu('Hareketler', 300),
                  ],
                ),
                bottomNavigationBar: TourAnchor(
                  target: TourTarget.altMenu,
                  child: SizedBox(height: 84, child: kutu('Alt menü', 50)),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(seconds: 12));
        OnboardingScreen.baslatTur(onBitti: (_) {}, kisa: true);
        for (var i = 0; i < 40; i++) {
          if (find.text('Bugün ne oldu?').evaluate().isNotEmpty) break;
          final ileri = find.text('Devam').evaluate().isNotEmpty
              ? find.text('Devam')
              : find.text('Başlayalım');
          for (var j = 0; j < 6 && ileri.evaluate().isEmpty; j++) {
            await tester.pump(const Duration(milliseconds: 450));
          }
          if (ileri.evaluate().isNotEmpty) await tester.tap(ileri.first);
          for (var j = 0; j < 5; j++) {
            await tester.pump(const Duration(milliseconds: 450));
          }
        }
        expect(find.text('Bugün ne oldu?'), findsOneWidget);
        for (var j = 0; j < 6; j++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.runAsync(() async {
          final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
          final img = await r.toImage(pixelRatio: 1.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/gorsel').createSync(recursive: true);
          File('build/gorsel/tur_bugun_${ad}_${b.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        OnboardingScreen.turuKapatTestIcin();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  }
}
