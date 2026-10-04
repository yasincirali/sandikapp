import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bugün kartı düzen H (bayrak `bugun_karti_kiyas`, kullanıcı seçimi
/// 2026-10-04): hareket + enflasyon kıyası + en çok oynayan + hedef.
/// Bayrak kapalıyken "D · Sakin pano" birebir (`bugun_karti_sakin_pano_test`).

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

Finder sigan(String metin) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return r is SiganMetinRender && r.secilen == metin;
    });

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

  Future<void> kur(WidgetTester tester,
      {required double genislik, required bool kiyas}) async {
    RemoteConfigService.testAcik = kiyas ? {'bugun_karti_kiyas'} : {};
    tester.view.physicalSize = Size(genislik * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ]);
    addTearDown(container.dispose);
    final state = await container.read(portfolioProvider.future);

    // Gün içi önbellek: kartın çekeceği kümeyle AYNI anahtar; THYAO +%3,
    // ASELS −%1 → en çok oynayan THYAO.
    final gun = dayKey(DateTime.now());
    int ms(int saat) => gun.add(Duration(hours: saat)).millisecondsSinceEpoch;
    final kume =
        state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
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

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: BugunKarti(state: state)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
  }

  for (final genislik in [390.0, 320.0]) {
    testWidgets('H ${genislik.toInt()}pt: dört parça, taşma yok',
        (tester) async {
      await kur(tester, genislik: genislik, kiyas: true);
      expect(tester.takeException(), isNull);
      // Enflasyon kıyası: iki çubuğun etiketleri.
      expect(find.text('Getirin'), findsOneWidget);
      expect(find.text('TÜFE'), findsOneWidget);
      // En çok oynayan: THYAO.
      // `Expanded` öğesi de aynı RenderBox'ı gösterir; bulucu iki öğe sayar.
      expect(sigan('En çok oynayan'), findsWidgets);
      expect(find.text('THYAO'), findsOneWidget);
      // Hedef kutusu (belirlenmemiş): eylem.
      expect(sigan('Hedef belirle'), findsOneWidget);
      // D'nin dönen kutuları H'de yok.
      expect(sigan('Artıdaki varlık'), findsNothing);
      expect(sigan('Son 7 gün'), findsNothing);
    });
  }

  testWidgets('bayrak KAPALI: D düzeni, en çok oynayan yok', (tester) async {
    await kur(tester, genislik: 390, kiyas: false);
    expect(tester.takeException(), isNull);
    expect(sigan('En çok oynayan'), findsNothing);
    expect(find.text('Getirin'), findsNothing);
    // D'nin takvim yaprağı başlığı.
    expect(sigan('BUGÜN'), findsOneWidget);
  });
}
