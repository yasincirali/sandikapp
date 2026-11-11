import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/services/sparkline_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/asset_sparkline.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Takip satırındaki son 1 ay mini çizgisi (Ar-Ge 11 Kas 19:04 #2).
///
/// Sözleşme: çizgi `SparklineService` serisinden gelir (kendi sembol
/// merdiveni yok); seri yoksa çizgi yok (uydurma nokta yok) ama yeri
/// korunur; dar ekran (≤360 pt) ya da büyük yazıda (≥1,5×) hiç kurulmaz ve
/// fiyat + yüzde her durumda görünür kalır. Seri ağdan değil
/// `debugCekici` kancasından gelir.
class _Liste extends WatchlistNotifier {
  _Liste(this.kalemler);
  final List<WatchlistItem> kalemler;
  @override
  Future<List<WatchlistItem>> build() async => kalemler;
}

WatchlistItem _kalem(String id, String ticker, String ad, double fiyat,
        double pct) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: fiyat,
      periodChangePct: pct,
    );

final _iki = [
  _kalem('1', 'SISE.IS', 'Şişe Cam', 38.46, -2.93),
  _kalem('2', 'XU100.IS', 'BIST 100 Endeksi', 12290.58, 1.2),
];

Future<void> _pump(
  WidgetTester tester, {
  double genislik = 390,
  double yazi = 1.0,
  List<WatchlistItem>? kalemler,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = yazi;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(() => _Liste(kalemler ?? _iki)),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

/// SISE için 1 aylık seri var, XU100 için yok.
Future<List<(int, double)>> _sahteCekici(String sembol) async =>
    sembol == 'SISE.IS'
        ? [for (var i = 0; i < 22; i++) (i, 40.0 - i * 0.1)]
        : const [];

/// "1 ay" dönem çipinde de yazıyor; yalnız çizginin altyazısı sayılır.
final _cizgiEtiketi = find.descendant(
    of: find.byType(AssetSparkline), matching: find.text('1 ay'));

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SparklineService.instance.clear();
    SparklineService.instance.debugCekici = _sahteCekici;
  });
  tearDown(() {
    SparklineService.instance.debugCekici = null;
    SparklineService.instance.clear();
  });

  void fiyatVeYuzdeGorunur() {
    expect(find.text('₺38,46'), findsOneWidget);
    expect(find.textContaining('2,93'), findsOneWidget);
    expect(find.text('12.291'), findsOneWidget);
  }

  testWidgets('390 pt: seri olan satırda çizgi + "1 ay"; olmayanda yer '
      'ayrılır ama çizgi yok', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    // İki satırda da yer ayrıldı (sütunlar aynı x'te)...
    expect(find.byType(AssetSparkline), findsNWidgets(2));
    // ...ama çizgi (ve pencere etiketi) yalnız serisi gelen satırda.
    expect(_cizgiEtiketi, findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(AssetSparkline), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    fiyatVeYuzdeGorunur();
  });

  testWidgets('çizgi ekran okuyucuda yok; satır cümlesi aynı', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    final satir = find.bySemanticsLabel(RegExp(r'^Şişe Cam, '));
    expect(satir, findsOneWidget);
    final etiket = tester.getSemantics(satir).label;
    expect(etiket, isNot(contains('1 ay')));
    expect(etiket, contains('düşüş %2,93'));
    semantics.dispose();
  });

  testWidgets('seri yok: hiçbir satırda çizgi yok, uydurma nokta yok',
      (tester) async {
    await _pump(tester, kalemler: [_iki[1]]);
    expect(tester.takeException(), isNull);
    expect(_cizgiEtiketi, findsNothing);
    expect(
      find.descendant(
          of: find.byType(AssetSparkline), matching: find.byType(CustomPaint)),
      findsNothing,
    );
    expect(find.text('12.291'), findsOneWidget);
  });

  for (final (genislik, yazi) in [(320.0, 1.0), (360.0, 1.0), (390.0, 2.0),
    (320.0, 2.0), (320.0, 3.1)]) {
    testWidgets('$genislik pt × $yazi yazı: çizgi kurulmaz, taşma yok, '
        'fiyat ve yüzde görünür', (tester) async {
      await _pump(tester, genislik: genislik, yazi: yazi);
      expect(tester.takeException(), isNull);
      expect(find.byType(AssetSparkline), findsNothing);
      expect(_cizgiEtiketi, findsNothing);
      fiyatVeYuzdeGorunur();
    });
  }
}
