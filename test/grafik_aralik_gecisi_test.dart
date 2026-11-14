import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';
import 'package:portfoy_takip/widgets/grafik_stili.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dönem (zaman aralığı) değişince grafik YERİNDE kalır ve yeni şekle akar
/// (yasin 2026-11-11 TestFlight: "tüm grafik sayfalarında zaman aralığı
/// değişince grafik hopluyor, ekran baştan çiziliyor gibi").
///
/// Kilitlenen sözleşme, her grafik yüzeyinde:
///  • `ZoomableChart`'ın State'i dönem değişiminde, yeni seri BEKLENİRKEN ve
///    geldikten sonra AYNI nesnedir. Sökülürse ilk çizim (soldan sağa açılış)
///    yeniden oynar — kullanıcının "baştan çiziliyor" dediği şey.
///  • Grafik kutusunun boyu beklerken ve sonra değişmez (zıplama yok).
///  • İskelet yalnız ekranda hiç grafik yokken görünür.
///  • Nokta sayısı değişen geçiş gerçek morf olarak akar (köprü), çubuk
///    sayısı değişen dönem geçişinde eski çizim aynı kutuda söner; hareketi
///    azalt açıkken hiçbiri yok.
///
/// Ağ yok: `HistoryService.seriCekici` sentetik seri verir; `_Kapi.tut`
/// açıkken yeni çekimleri bekletir (yavaş ağ).
const _uid = 'user-1';

Asset _lot({int gunOnce = 800}) => Asset(
      id: 'lot-1',
      userId: _uid,
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 90,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 150,
      addedDate: DateTime.now().subtract(Duration(days: gunOnce)),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2025, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.lot);
  final Asset lot;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [lot],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
        ownerId: _uid,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

/// Ağ kapısı: [tut] açıkken yeni çekimler [birak]'a kadar bekler.
class _Kapi {
  bool tut = false;
  final _bekleyen = <(Completer<List<(int, double)>>, String?)>[];

  Future<List<(int, double)>> cek(
      String sym, String range, String? interval) {
    if (!tut) return Future.value(_seri(interval));
    final c = Completer<List<(int, double)>>();
    _bekleyen.add((c, interval));
    return c.future;
  }

  void birak() {
    tut = false;
    for (final (c, interval) in _bekleyen) {
      c.complete(_seri(interval));
    }
    _bekleyen.clear();
  }

  static List<(int, double)> _seri(String? interval) {
    final simdi = DateTime.now();
    final gunIci = interval != null &&
        (interval.endsWith('m') || interval.endsWith('h'));
    if (gunIci) {
      final bas = DateTime(simdi.year, simdi.month, simdi.day);
      return [
        for (var i = 0; i < 288; i++)
          (
            bas.add(Duration(minutes: 5 * i)).millisecondsSinceEpoch,
            148 + (i % 20) * 0.1,
          ),
      ];
    }
    return [
      for (var g = 2200; g >= 0; g--)
        (
          DateTime(simdi.year, simdi.month, simdi.day - g, 12)
              .millisecondsSinceEpoch,
          100 + (2200 - g) * 0.02 + (g % 7),
        ),
    ];
  }
}

Future<void> _yerles(WidgetTester tester, [int kare = 30]) async {
  for (var i = 0; i < kare; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _grafik => find.byType(ZoomableChart);

Finder _donemDugmesi(String etiket) => find.descendant(
    of: find.byType(DonemSecici), matching: find.text(etiket));

/// Dönem seçicideki etikete dokunur; grafiğin State'i ve kutu boyu her
/// karede (dokunuş, bekleme, veri gelişi, morf) ilk hâliyle aynı olmalı.
Future<void> _donemDegistir(
  WidgetTester tester,
  _Kapi kapi,
  String etiket, {
  required Finder kutu,
}) async {
  final once = tester.state(_grafik);
  final boy = tester.getSize(kutu).height;
  void denetle(String an) {
    expect(_grafik, findsOneWidget, reason: '$etiket · $an: grafik söküldü');
    expect(identical(tester.state(_grafik), once), isTrue,
        reason: '$etiket · $an: ZoomableChart yeniden kuruldu → morf yerine '
            'soldan sağa ilk çizim oynar ("baştan çiziliyor")');
    expect(tester.getSize(kutu).height, boy,
        reason: '$etiket · $an: grafik kutusunun boyu değişti (zıplama)');
    expect(find.byType(SandikSkeletonChart), findsNothing,
        reason: '$etiket · $an: ekranda grafik varken iskelet');
  }

  kapi.tut = true;
  await tester.tap(_donemDugmesi(etiket));
  await tester.pump();
  denetle('dokunuş');
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    denetle('bekleme');
  }
  kapi.birak();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    denetle('veri geldi');
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  late _Kapi kapi;
  setUp(() {
    HistoryService.clearCache();
    kapi = _Kapi();
    HistoryService.seriCekici = kapi.cek;
  });
  tearDown(
      () => HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  group('ekranlar', () {
    testWidgets('Performans: Bugün ↔ dönem geçişinde grafik yerinde kalır',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio(_lot())),
          partnersProvider.overrideWith(_FakePartners.new),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(
          home: PortfolioPerformanceScreen(
            initialPeriodIdx: SummaryPeriod.birAy.index,
          ),
        ),
      ));
      await _yerles(tester);
      final kutu = find.byKey(const ValueKey('performansGrafikAlani'));
      expect(kutu, findsOneWidget);
      // 1 yıl: dönem dalı içinde (yeni controller, tohum seri).
      // Bugün: dönem dalı → gün içi dalı (eskiden kök widget türü
      // değişiyordu). 1 hf: gün içinden dönüş, tohum yok (eskiden iskelet).
      for (final etiket in ['1 yıl', 'Bugün', '1 hf', 'Bugün', '1 ay']) {
        await _donemDegistir(tester, kapi, etiket, kutu: kutu);
      }
      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });

    testWidgets(
        'Varlık detayı: dönem geçişinde grafik yerinde kalır; çubuk sayısı '
        'değişince eski çizim söner', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      // Genç lot: uzun dönemde alış öncesi parça + aktif çizgi, kısa dönemde
      // yalnız aktif çizgi — çubuk sayısı değişen gerçek kullanıcı durumu.
      final lot = _lot(gunOnce: 100);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio(lot)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: AssetDetailScreen(asset: lot, showBackButton: true),
        ),
      ));
      await _yerles(tester);
      for (final etiket in ['1 ay', 'Bugün', '1 hf', '1 ay']) {
        await _donemDegistir(tester, kapi, etiket, kutu: _grafik);
      }

      // 1 ay → 1 yıl: çubuk sayısı artar. Eskiden çizim tek karede
      // değişiyordu ("hop"); şimdi eski çizim aynı kutuda söner.
      final cizgiler =
          find.descendant(of: _grafik, matching: find.byType(LineChart));
      int cubuk() => tester
          .widget<LineChart>(cizgiler.first)
          .data
          .lineBarsData
          .length;
      final onceCubuk = cubuk();
      final once = tester.state(_grafik);
      await tester.tap(_donemDugmesi('1 yıl'));
      await tester.pump();
      expect(cubuk(), isNot(onceCubuk),
          reason: 'ön koşul: genç lotta 1 yıl çubuk sayısını değiştirir');
      expect(identical(tester.state(_grafik), once), isTrue);
      expect(cizgiler, findsNWidgets(2),
          reason: 'eski çizim üstte sönmeli; tek karede değişim "hop" okunur');
      await tester.pump(SandikMotion.state);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cizgiler, findsOneWidget,
          reason: 'sönme bitince yalnız yeni çizim kalır');

      await tester.pumpWidget(const SizedBox());
      await _yerles(tester, 12);
    });
  });

  group('ZoomableChart', () {
    LineChartData veri(int n, {int cubuk = 1}) => LineChartData(
          minX: 0,
          maxX: 100,
          minY: 0,
          maxY: 100,
          lineBarsData: [
            for (var c = 0; c < cubuk; c++)
              LineChartBarData(
                dotData: const FlDotData(show: false),
                spots: [
                  for (var i = 0; i < n; i++)
                    FlSpot(i * 100 / (n - 1), (i * 37 % 100).toDouble()),
                ],
              ),
          ],
        );

    Widget kur(LineChartData d, {Object? anahtar, bool azalt = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: azalt),
            child: Scaffold(
              body: ZoomableChart(
                fullMinX: 0,
                fullMaxX: 100,
                sifirlamaAnahtari: anahtar,
                builder: (_, __) => d,
              ),
            ),
          ),
        );

    LineChart cizgi(WidgetTester t) =>
        t.widget<LineChart>(find.byType(LineChart).first);
    List<FlSpot> noktalar(WidgetTester t) =>
        cizgi(t).data.lineBarsData.single.spots;

    testWidgets(
        'nokta sayısı artınca köprü: sıklaşmış eski → yeni, sonra gerçek seri',
        (tester) async {
      await tester.pumpWidget(kur(veri(10)));
      await tester.pump(SandikMotion.flow);

      await tester.pumpWidget(kur(veri(40)));
      // 1. kare: eski çizgi 40 noktaya sıklaşmış, süre sıfır — köşeler
      // yerinde, görünür değişiklik yok.
      expect(noktalar(tester).length, 40);
      expect(cizgi(tester).duration, Duration.zero);
      for (final p in veri(10).lineBarsData.single.spots) {
        expect(noktalar(tester), contains(p),
            reason: 'eski köşeler sıklaştırmada yerinde kalmalı');
      }
      // Sonraki karelerde geçiş saati yeni çizgiye akıtır (2026-11-14: ara
      // kareyi fl_chart değil ZoomableChart üretir; süre hep sıfır).
      await tester.pump(const Duration(milliseconds: 60));
      expect(cizgi(tester).duration, Duration.zero);
      expect(noktalar(tester).length, 40);
      expect(noktalar(tester), isNot(veri(40).lineBarsData.single.spots));
      // Akış bitince gerçek seri.
      await tester.pumpAndSettle();
      expect(cizgi(tester).duration, Duration.zero);
      expect(noktalar(tester), veri(40).lineBarsData.single.spots);
    });

    testWidgets('nokta sayısı azalınca da köprü (yeni seri sıklaşır)',
        (tester) async {
      await tester.pumpWidget(kur(veri(40)));
      await tester.pump(SandikMotion.flow);
      await tester.pumpWidget(kur(veri(10)));
      expect(noktalar(tester).length, 40);
      await tester.pumpAndSettle();
      // Hedef (yeni seri sıklaşmış) ve ardından gerçek 10 nokta.
      expect(noktalar(tester).length, 10,
          reason: 'akış bitince dokunma balonu gerçek noktaları okur');
    });

    testWidgets(
        'gösterge aç/kapa (çubuk sayısı değişir, anahtar aynı): anında, '
        'sönme yok', (tester) async {
      await tester.pumpWidget(kur(veri(10), anahtar: 'a'));
      await tester.pump(SandikMotion.flow);
      await tester.pumpWidget(kur(veri(10, cubuk: 2), anahtar: 'a'));
      expect(find.byType(LineChart), findsOneWidget);
      expect(cizgi(tester).duration, Duration.zero);
    });

    testWidgets('dönem değişimi + çubuk sayısı: eski çizim aynı kutuda söner',
        (tester) async {
      await tester.pumpWidget(kur(veri(10), anahtar: 'a'));
      await tester.pump(SandikMotion.flow);
      final once = tester.state(find.byType(ZoomableChart));
      await tester.pumpWidget(kur(veri(10, cubuk: 2), anahtar: 'b'));
      expect(find.byType(LineChart), findsNWidgets(2));
      expect(identical(tester.state(find.byType(ZoomableChart)), once), isTrue);
      await tester.pump(SandikMotion.state);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('hareketi azalt: köprü ve sönme yok, tek karede yeni seri',
        (tester) async {
      await tester.pumpWidget(kur(veri(10), anahtar: 'a', azalt: true));
      await tester.pump();
      await tester.pumpWidget(kur(veri(40), anahtar: 'a', azalt: true));
      expect(noktalar(tester).length, 40);
      expect(cizgi(tester).duration, Duration.zero);
      await tester.pumpWidget(
          kur(veri(40, cubuk: 2), anahtar: 'b', azalt: true));
      expect(find.byType(LineChart), findsOneWidget);
      expect(cizgi(tester).duration, Duration.zero);
    });

    testWidgets('dönem başı etiketi gelip gidince grafik sökülmez',
        (tester) async {
      Widget kabuk(String? etiket) => MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => GrafikStili.donemBasiUstte(
                  context,
                  etiket: etiket,
                  grafik: ZoomableChart(
                    fullMinX: 0,
                    fullMaxX: 100,
                    builder: (_, __) => veri(10),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(kabuk('Açılış · 100 ₺'));
      final once = tester.state(find.byType(ZoomableChart));
      await tester.pumpWidget(kabuk(null));
      expect(identical(tester.state(find.byType(ZoomableChart)), once), isTrue,
          reason: 'etiketsiz dönemde grafik Stack dışına çıkıp yeniden '
              'kuruluyordu');
      await tester.pumpWidget(kabuk('Açılış · 120 ₺'));
      expect(identical(tester.state(find.byType(ZoomableChart)), once), isTrue);
    });
  });
}
