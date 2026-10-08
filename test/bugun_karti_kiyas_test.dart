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
import 'package:portfoy_takip/utils/tr_format.dart' show dayKey;
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bugün kartının dört parçası gerçek ağaçta: hareket + enflasyon kıyası +
/// en çok oynayan + hedef (kullanıcı şartı 2026-10-04). 2026-10-09 benchmark
/// düzeni: hüküm + rozet, oynayanlar sırası, alım gücü kutusu, hedef satırı
/// (ayrıntılar `bugun_karti_benchmark_test`).

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

/// Cuma 9 Ekim 2026, 15:00 — seans açık, tatil değil.
final _simdi = DateTime(2026, 10, 9, 15);

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
    BugunYukleyici.reelTest =
        (_) => const ReelGetiriSatiri(nominal: 48.2, inflation: 45.1);
    // Sabit hafta içi, seans açık (bkz. `bugun_karti_benchmark_test`).
    BugunKarti.saat = () => _simdi;
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
    BugunKarti.saat = DateTime.now;
  });

  Future<void> kur(WidgetTester tester, {required double genislik}) async {
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
    final gun = dayKey(_simdi);
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
    testWidgets('${genislik.toInt()}pt: dört parça, taşma yok', (tester) async {
      await kur(tester, genislik: genislik);
      expect(tester.takeException(), isNull);
      // Hareket: seri 41000 → 41700, hüküm kelimesi + dolu rozet.
      expect(find.text('Yükseldi'), findsOneWidget);
      // Enflasyon kıyası: soru + 100 lira cümlesi (48,2 / 45,1 → 102 lira).
      expect(find.text('Paran fiyatlara yetişiyor mu?'), findsOneWidget);
      expect(find.textContaining('102 lira'), findsOneWidget);
      expect(find.text('Sen öndesin'), findsOneWidget);
      expect(find.text('Getirin'), findsNothing);
      expect(find.text('TÜFE'), findsNothing);
      // Oynayanlar sırası: THYAO (+%3) ve ASELS (−%1), THYAO önde.
      // Başlık `SiganMetin`: Ahem'de kısa yazım seçilebilir.
      expect(
          sigan('Bugün en çok oynayanlar').evaluate().isNotEmpty ||
              sigan('En çok oynayan').evaluate().isNotEmpty,
          isTrue);
      expect(find.text('THYAO'), findsOneWidget);
      expect(find.text('ASELS'), findsOneWidget);
      // Okuma sırası: THYAO önce (aynı satırda solda ya da üst satırda;
      // 320pt'te çipler alt satıra kırılır — `Wrap`).
      final thy = tester.getTopLeft(find.text('THYAO'));
      final asl = tester.getTopLeft(find.text('ASELS'));
      expect(thy.dy < asl.dy || (thy.dy == asl.dy && thy.dx < asl.dx), isTrue);
      // Hedef satırı (belirlenmemiş): eylem.
      expect(sigan('Hedef belirle'), findsOneWidget);
      // D'nin dönen kutuları H'de yok.
      expect(sigan('Artıdaki varlık'), findsNothing);
      expect(sigan('Son 7 gün'), findsNothing);
    });
  }
}
