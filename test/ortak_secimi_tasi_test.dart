import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Karttan ekrana geçişte ortak seçimi taşınır (bayrak `ortak_secimi_tasi`,
/// kullanıcı isteği 2026-10-04): "ana sayfa günlük kartından performans
/// ekranına, ortağım ya da birlikte seçiliyse yine o seçili şekilde
/// açılmalı." Bayrak kapalıyken eski davranış: Performans her zaman Ben.

Asset _asset(String ticker, double qty, double alis, double simdi) => Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: ticker,
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

/// Açılan rotayı yakalar; ekranı KURMADAN hangi argümanla açılacağını okumak
/// için (Performans ekranının tamamını test ortamında kurmak gereksiz).
class _Gozcu extends NavigatorObserver {
  Route<dynamic>? son;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) son = route;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

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
    BugunKarti.anliklariTemizle();
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
    RemoteConfigService.testAcik = {};
  });

  /// Kartı [gorunum] ile kurar, "En çok oynayan" kutusuna (THYAO) dokunur
  /// ve açılan Performans ekranının `initialView`'ını döndürür.
  Future<String?> acilanGorunum(WidgetTester tester,
      {required String? gorunum, required bool tasi}) async {
    RemoteConfigService.testAcik = {
      'bugun_karti_kiyas',
      if (tasi) 'ortak_secimi_tasi',
    };
    tester.view.physicalSize = const Size(390 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ]);
    addTearDown(container.dispose);
    final state = await container.read(portfolioProvider.future);

    final gun = dayKey(DateTime.now());
    int ms(int saat) => gun.add(Duration(hours: saat)).millisecondsSinceEpoch;
    final kume = state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
    final kThy = positionKey(_defter[0]);
    final kAsl = positionKey(_defter[1]);
    IntradaySeriesCache.instance.seedForTest(
      series: {ms(10): 41000, ms(15): 41700},
      fetchedAt: DateTime.now(),
      seansGunu: gun,
      kume: kume,
      byPosition: {
        kThy: {ms(10): 30330, ms(15): 31240},
        kAsl: {ms(10): 10100, ms(15): 9999},
      },
      positionType: {kThy: AssetType.hisse, kAsl: AssetType.hisse},
    );

    final gozcu = _Gozcu();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        navigatorObservers: [gozcu],
        home: Scaffold(
          body: SingleChildScrollView(
            child: BugunKarti(state: state, gorunum: gorunum),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();

    // `pushGuarded`'ın çift dokunma penceresi GERÇEK saate bakar (500 ms);
    // önceki testin dokunuşu pencereyi açık bırakmasın.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('THYAO'));
    await tester.pump();
    final rota = gozcu.son;
    expect(rota, isA<MaterialPageRoute<void>>());
    final ekran = (rota! as MaterialPageRoute<void>)
        .builder(tester.element(find.byType(BugunKarti)));
    expect(ekran, isA<PortfolioPerformanceScreen>());
    return (ekran as PortfolioPerformanceScreen).initialView;
  }

  group('bayrak AÇIK: kartın seçimi Performans\'a taşınır', () {
    testWidgets('ortak seçiliyken o ortak', (tester) async {
      expect(await acilanGorunum(tester, gorunum: 'ortak-1', tasi: true),
          'ortak-1');
    });
    testWidgets('Birlikte (null) seçiliyken Birlikte', (tester) async {
      expect(await acilanGorunum(tester, gorunum: null, tasi: true), isNull);
    });
    testWidgets('Ben seçiliyken Ben', (tester) async {
      expect(await acilanGorunum(tester, gorunum: '', tasi: true), '');
    });
  });

  testWidgets('bayrak KAPALI: eski davranış, her zaman Ben', (tester) async {
    expect(await acilanGorunum(tester, gorunum: 'ortak-1', tasi: false), '');
  });

  test('kaynak: Bugün kartının her Performans geçişi seçimi verir', () {
    final kart = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    final gecis = 'PortfolioPerformanceScreen('.allMatches(kart).length;
    expect(gecis, greaterThan(0));
    expect('initialView: _gecisGorunumu'.allMatches(kart).length, gecis,
        reason: 'Bugün kartından Performans açan her yer kartın ortak '
            'seçimini taşımalı (bayrak ortak_secimi_tasi).');
    final ana = ekranKaynagiSync('lib/screens/home_screen.dart');
    expect(ana, contains('gorunum: _view,'),
        reason: 'Ana ekran Bugün kartına seçili görünümü vermeli.');
  });
}
