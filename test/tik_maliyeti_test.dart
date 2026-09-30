import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Fiyat tikinin maliyeti (animasyon denetimi 2026-10-01, ölçümden).
///
/// Uygulama 30 sn'de bir fiyat turu atar; her tur portföy defterini yeniden
/// yayınlar ve sekme ekranları yeniden kurulur. Ölçüldü ve düzeltildi:
///   · fiyatı DEĞİŞMEYEN tikte Portföy halkası ve Performans grafiği 12'şer
///     kare (180 ms) boşuna morf ediyordu — fl_chart verisi kapanış taşıdığı
///     için hiçbir zaman "eşit" sayılmıyordu;
///   · Performans'ın tür dökümü KAPALIYKEN varlık satırlarını ağaçta
///     tutuyordu: tik maliyeti varlık sayısıyla doğrusal büyüyordu
///     (200 varlıkta 1.150 widget / tik → düzeltmeden sonra ~400, sabit).
/// Bu testler üç kazancı kilitler.
const _uid = 'user-1';
const _turler = [
  AssetType.hisse,
  AssetType.altin,
  AssetType.doviz,
  AssetType.fon,
];

List<Asset> _varliklar(int n) => [
      for (var i = 0; i < n; i++)
        Asset(
          id: 'a$i',
          userId: _uid,
          name: 'Varlık $i',
          ticker: 'T${i.toString().padLeft(3, '0')}',
          type: _turler[i % _turler.length],
          quantity: 10.0 + i,
          purchasePrice: 100.0 + i,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 110.0 + i,
          addedDate: DateTime(2025, 1 + i % 12, 1 + i % 27),
        ),
    ];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 't@e.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Tikli extends PortfolioNotifier {
  _Tikli(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
        ownerId: _uid,
      );

  /// Fiyat turu: önce `isLoading`, sonra AYNI fiyatlı yeni defter.
  void degismeyenTik() {
    final s = state.valueOrNull!;
    state = AsyncData(s.copyWith(isLoading: true));
    state = AsyncData(s.copyWith(
      assets: [for (final a in s.assets) a.copyWithDeletedAt(a.deletedAt)],
      isLoading: false,
    ));
  }
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

Future<_Tikli> _kur(WidgetTester t, Widget ekran, int n) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  final notifier = _Tikli(_varliklar(n));
  await t.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => notifier),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: ekran),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  t.takeException();
  return notifier;
}

/// Tikten sonra kaç animasyon karesi daha çizildi.
Future<int> _ekKare(WidgetTester t) async {
  var kare = 0;
  while (t.binding.hasScheduledFrame && kare < 60) {
    await t.pump(const Duration(milliseconds: 16));
    kare++;
  }
  t.takeException();
  return kare;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  testWidgets('ZoomableChart: aynı çizim + yeni kapanış → morf yok',
      (t) async {
    LineChartData veri() => LineChartData(
          minX: 0,
          maxX: 10,
          minY: 0,
          maxY: 10,
          // Her kurulumda YENİ kapanış — sahiplerin yaptığı gibi.
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) => Text('${v.toInt()}'),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(spots: [
              for (var i = 0; i <= 10; i++) FlSpot(i.toDouble(), i / 2),
            ]),
          ],
        );
    Widget host() => MaterialApp(
          home: Scaffold(
            body: ZoomableChart(
              fullMinX: 0,
              fullMaxX: 10,
              builder: (_, __) => veri(),
            ),
          ),
        );
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    await t.pumpWidget(host());
    expect(await _ekKare(t), 0,
        reason: 'görünür hiçbir şey değişmedi; 180 ms morf boşa boyar');
  });

  testWidgets('Portföy: fiyatı değişmeyen tik halkayı morf ettirmez',
      (t) async {
    final n = await _kur(t, const PortfolioScreen(), 30);
    for (var i = 0; i < 3; i++) {
      n.degismeyenTik();
      await t.pump();
      expect(await _ekKare(t), 0);
    }
  });

  testWidgets('Performans: tik maliyeti varlık sayısıyla büyümez',
      (t) async {
    Future<int> kurulum(int adet) async {
      // Önceki kapsamı sök: aynı kökte ikinci ProviderScope eskisini
      // yeniden kullanır ve yeni notifier bağlanmaz.
      await t.pumpWidget(const SizedBox.shrink());
      final n = await _kur(t, const PortfolioPerformanceScreen(), adet);
      var sayac = 0;
      debugOnRebuildDirtyWidget = (_, __) => sayac++;
      n.degismeyenTik();
      await t.pump();
      debugOnRebuildDirtyWidget = null;
      await _ekKare(t);
      return sayac;
    }

    final az = await kurulum(10);
    final cok = await kurulum(200);
    expect(cok, lessThan(az * 1.5),
        reason: 'kapalı tür dökümü satırları ağaçta mı? 10 varlık: $az, '
            '200 varlık: $cok yeniden kurulum');
  });
}
