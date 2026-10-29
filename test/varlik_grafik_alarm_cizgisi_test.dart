import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Varlık sayfası ana grafiğinde kurulu fiyat alarmı (Ar-Ge 29 Eki 20:45 #2):
/// görünen aralıktaki etkin hedef ince kesikli yatay çizgi, açıklaması
/// kartın ÜSTÜNDE (çizim alanında değil); aralık dışı hedefin çizgisi yok,
/// etiket "grafiğin üstünde" der; LOG'da ne çizgi ne etiket.

const _uid = 'u1';
const _fiyat = 287.5;

final _thy = Asset(
  id: 'THYAO.IS-1',
  userId: _uid,
  name: 'Türk Hava Yolları',
  ticker: 'THYAO.IS',
  type: AssetType.hisse,
  quantity: 100,
  purchasePrice: 230,
  currency: 'TRY',
  notes: '',
  isManualPrice: false,
  currentPrice: _fiyat,
  addedDate: DateTime(2025, 3, 14),
);

/// Düz ama hafif dalgalı seri: Y bandı ~[283, 292].
List<(int, double)> _seri(String range, String? interval) {
  final now = DateTime.now();
  final out = <(int, double)>[];
  for (var i = 60; i >= 1; i--) {
    final t = now.subtract(Duration(days: i));
    out.add((t.millisecondsSinceEpoch, _fiyat + (i.isEven ? 4 : -4)));
  }
  out.add((now.millisecondsSinceEpoch, _fiyat));
  return out;
}

PriceAlert _alarm(String id, double hedef, String yon) => PriceAlert(
      id: id,
      userId: _uid,
      symbol: 'THYAO.IS',
      label: 'THY',
      targetPrice: hedef,
      direction: yon,
      enabled: true,
      createdAt: DateTime(2026, 10, 1),
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
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: [_thy], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
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

List<PriceAlert> _alarmlar = const [];

class _Alarmlar extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _alarmlar;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  tearDown(
      () => HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  Future<void> ac(WidgetTester tester,
      {required List<PriceAlert> alarmlar, bool log = false}) async {
    _alarmlar = alarmlar;
    SharedPreferences.setMockInitialValues(
        {if (log) 'pref_chart_log_scale': true});
    await initPreferencesCache();
    HistoryService.clearCache();
    HistoryService.seriCekici =
        (sym, range, interval) async => _seri(range, interval);
    tester.view.physicalSize = const Size(390 * 2, 1000 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        watchlistProvider.overrideWith(_Takip.new),
        priceAlertsProvider.overrideWith(_Alarmlar.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: AssetDetailScreen(asset: _thy, showBackButton: true),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('3 ay').first);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> kapat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  /// Ana grafiğin yatay ek çizgilerinin Y'leri (tüm LineChart'lar).
  Set<double> yataylar(WidgetTester tester) => {
        for (final g in tester.widgetList<LineChart>(find.byType(LineChart)))
          for (final h in g.data.extraLinesData.horizontalLines) h.y,
      };

  testWidgets('aralık içi alarm: çizgi + kartın üstünde etiket', (t) async {
    await ac(t, alarmlar: [_alarm('a', 286, 'below')]);
    expect(yataylar(t), contains(286.0));
    expect(find.text('₺286,00 ▼ altına inince'), findsOneWidget);
    expect(find.bySemanticsLabel('Fiyat alarmı ₺286,00, altına inince'),
        findsOneWidget);
    expect(t.takeException(), isNull);
    await kapat(t);
  });

  testWidgets('aralık dışı alarm: çizgi yok, Y genişlemez, etiket söyler',
      (t) async {
    await ac(t, alarmlar: [_alarm('a', 2875, 'above')]);
    expect(yataylar(t), isNot(contains(2875.0)));
    final g = t.widget<LineChart>(find.byType(LineChart).first);
    expect(g.data.maxY, lessThan(400), reason: 'Y ekseni alarma uzamamalı');
    expect(find.textContaining('grafiğin üstünde'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('birden çok alarm: en yakını yazılı, kalanı +N', (t) async {
    await ac(t, alarmlar: [
      _alarm('uzak', 2875, 'above'),
      _alarm('yakin', 289, 'above'),
    ]);
    expect(yataylar(t), contains(289.0));
    expect(find.text('₺289,00 ▲ üstüne çıkınca'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('LOG kipinde ne çizgi ne etiket', (t) async {
    await ac(t, alarmlar: [_alarm('a', 286, 'below')], log: true);
    // LOG gerçekten açık: dönem başı çizgisi log10 biriminde.
    expect(yataylar(t).every((y) => y < 10), isTrue);
    expect(yataylar(t), isNotEmpty);
    expect(yataylar(t), isNot(contains(286.0)));
    expect(find.textContaining('altına inince'), findsNothing);
    await kapat(t);
  });

  test('Karşılaştır ve LOG kipinde aday yok (kaynak kilidi)', () {
    final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(
        k.contains(
            'if (sembol == null || compareOn || logOn) return const [];'),
        isTrue,
        reason: 'Y dönüştürülmüş kipte alarm çizgisi fiyatı göstermez');
    expect(k.contains('compareOn: compareOn, logOn: logOn'), isTrue);
  });
}
