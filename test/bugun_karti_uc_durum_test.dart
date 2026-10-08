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

/// Bugün kartı uç durumları (benchmark düzeni, 2026-10-09 UI/UX turu).
///
/// Emülatörde görülen iki hata bu testin doğurduğu kuraldır: oynayan çipi
/// kart dışına taştı, "Tümü ›" tek başına satır kapladı. Kural: hangi sayıda
/// oynayan, hangi genişlik, hangi yazı ölçeği, hangi tema olursa olsun
/// kartta taşma/istisna yok, hiçbir çip kart sınırının dışında durmaz ve
/// "Tümü ›" çiplerle aynı satırda değil, başlıkta durur.

Asset _asset(String ticker, double qty, double alis, double simdi,
        {AssetType type = AssetType.hisse}) =>
    Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: simdi,
      addedDate: DateTime(2026, 3, 14),
    );

final _simdi = DateTime(2026, 10, 9, 15);

/// Oynayanlar başlığı: test yazı tipi (Ahem) geniş olduğundan hangi yazımın
/// seçildiği ortama bağlı; kural "adaylardan biri TAM yazılır".
bool get baslikVar =>
    sigan('Bugün en çok oynayanlar').evaluate().isNotEmpty ||
    sigan('En çok oynayan').evaluate().isNotEmpty;

/// `SiganMetin` kendi RenderBox'ıyla çizer; `find.text` onu görmez.
Finder sigan(String metin) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return r is SiganMetinRender && r.secilen == metin;
    });

final _defter = [
  _asset('THYAO', 100, 300, 312.40),
  _asset('ASELS', 10, 1100, 1000),
  _asset('GARANTIBBVA', 50, 100, 120),
  _asset('KCHOLALTINZIRVE', 5, 200, 210),
];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
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
    BugunKarti.saat = () => _simdi;
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
    IntradaySeriesCache.instance.clear();
    BugunYukleyici.reelTest = null;
    BugunKarti.saat = DateTime.now;
  });

  /// [hareketler]: pozisyon → (açılış, kapanış) gün içi değerleri.
  Future<ProviderContainer> kur(
    WidgetTester tester, {
    required Map<int, (double, double)> hareketler,
    double genislik = 390,
    double yaziOlcegi = 1,
    Brightness tema = Brightness.light,
    ReelGetiriSatiri? reel =
        const ReelGetiriSatiri(nominal: 5.50, inflation: 29.73),
    bool gizli = false,
  }) async {
    tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    BugunYukleyici.reelTest = reel == null ? null : (_) => reel;
    if (gizli) {
      SharedPreferences.setMockInitialValues({'pref_balance_hidden': true});
      await initPreferencesCache();
    }
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ]);
    addTearDown(container.dispose);
    final state = await container.read(portfolioProvider.future);

    final gun = dayKey(_simdi);
    int ms(int saat) => gun.add(Duration(hours: saat)).millisecondsSinceEpoch;
    final kume = state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
    final byPos = <String, Map<int, double>>{};
    hareketler.forEach((i, v) {
      byPos[positionKey(_defter[i])] = {ms(10): v.$1, ms(15): v.$2};
    });
    IntradaySeriesCache.instance.seedForTest(
      series: {ms(10): 41000, ms(15): 41700},
      fetchedAt: DateTime.now(),
      seansGunu: gun,
      kume: kume,
      byPosition: byPos,
      positionType: {for (final k in byPos.keys) k: AssetType.hisse},
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(yaziOlcegi)),
        child: MaterialApp(
          theme: tema == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: BugunKarti(state: state)),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 2));
    return container;
  }

  /// Kartın sağ kenarı (padding hariç kart gövdesi).
  double kartSagKenar(WidgetTester tester) =>
      tester.getBottomRight(find.byType(BugunKarti)).dx;

  final uc = {
    0: (1000.0, 1032.0), // +%3,2
    1: (2000.0, 1900.0), // −%5
    2: (500.0, 505.0), // +%1
  };

  for (final genislik in [390.0, 320.0, 280.0]) {
    for (final olcek in [1.0, 1.5, 2.0]) {
      testWidgets(
          '${genislik.toInt()}pt, yazı ×$olcek: üç oynayan, taşma yok, çipler kart içinde',
          (tester) async {
        await kur(tester,
            hareketler: uc, genislik: genislik, yaziOlcegi: olcek);
        expect(tester.takeException(), isNull);
        for (final ad in ['THYAO', 'ASELS', 'GARANTIBBVA']) {
          final f = find.text(ad);
          expect(f, findsOneWidget, reason: ad);
          expect(tester.getBottomRight(f).dx, lessThanOrEqualTo(genislik),
              reason: '$ad ekran dışına taşmamalı');
        }
        // "Tümü" başlıkta: ilk çipin ÜSTÜNDE (aynı satırda ya da başlık
        // satırında), çiplerin arasında ayrı satır değil.
        final tumu = tester.getTopLeft(find.text('Tümü'));
        final ilkCip = tester.getTopLeft(find.text('ASELS'));
        expect(tumu.dy, lessThan(ilkCip.dy),
            reason: '"Tümü" çip satırlarının üstünde, başlıkta olmalı');
        expect(kartSagKenar(tester), lessThanOrEqualTo(genislik));
      });
    }
  }

  testWidgets('tek oynayan: çip tam genişlik, yetim satır yok', (tester) async {
    await kur(tester, hareketler: {0: (1000.0, 1032.0)});
    expect(tester.takeException(), isNull);
    expect(find.text('THYAO'), findsOneWidget);
    expect(baslikVar, isTrue);
    expect(find.text('Tümü'), findsOneWidget);
  });

  testWidgets('iki oynayan: yan yana, aynı satırda', (tester) async {
    await kur(tester, hareketler: {0: (1000.0, 1032.0), 1: (2000.0, 1900.0)});
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('THYAO')).dy,
        tester.getTopLeft(find.text('ASELS')).dy);
  });

  testWidgets('üç oynayan: 2 + 1, üçüncü çip alt satırda tam genişlik',
      (tester) async {
    await kur(tester, hareketler: uc);
    final ilk = tester.getTopLeft(find.text('ASELS'));
    final ucuncu = tester.getTopLeft(find.text('GARANTIBBVA'));
    expect(ucuncu.dy, greaterThan(ilk.dy));
  });

  testWidgets('oynayan yok: satır hiç çizilmez, kart yine tam', (tester) async {
    await kur(tester, hareketler: const {});
    expect(tester.takeException(), isNull);
    expect(baslikVar, isFalse);
    expect(find.text('Tümü'), findsNothing);
    expect(find.text('Paran fiyatlara yetişiyor mu?'), findsOneWidget);
  });

  testWidgets('gizli bakiye: çiplerde tutar maskeli', (tester) async {
    await kur(tester, hareketler: uc, gizli: true);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('₺'), findsNothing,
        reason: 'gizli modda kartta hiçbir tutar görünmemeli');
    expect(find.text('••••'), findsWidgets);
  });

  for (final tema in [Brightness.light, Brightness.dark]) {
    testWidgets('${tema.name} tema: istisna yok', (tester) async {
      await kur(tester, hareketler: uc, tema: tema);
      expect(tester.takeException(), isNull);
    });
  }

  group('alım gücü uç değerleri', () {
    testWidgets('öndeyken: "Sen öndesin", 100 lirayı aşar, çubuk taşmaz',
        (tester) async {
      await kur(tester,
          hareketler: uc,
          reel: const ReelGetiriSatiri(nominal: 48.2, inflation: 45.1));
      expect(tester.takeException(), isNull);
      expect(find.text('Sen öndesin'), findsOneWidget);
      expect(find.textContaining('102 lira'), findsOneWidget);
    });

    testWidgets('çok büyük enflasyon: istisna yok, sayı okunur',
        (tester) async {
      await kur(tester,
          hareketler: uc,
          reel: const ReelGetiriSatiri(nominal: 3, inflation: 1234.56));
      expect(tester.takeException(), isNull);
      expect(find.text('Fiyatlar önde'), findsOneWidget);
      expect(find.textContaining('lira'), findsOneWidget);
    });

    testWidgets('negatif getiri: eksi işaretli yüzde, istisna yok',
        (tester) async {
      await kur(tester,
          hareketler: uc,
          reel: const ReelGetiriSatiri(nominal: -12.5, inflation: 30));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('12,50'), findsOneWidget);
      expect(find.text('Fiyatlar önde'), findsOneWidget);
    });

    testWidgets('başa baş: "başa baş" hükmü', (tester) async {
      await kur(tester,
          hareketler: uc,
          reel: const ReelGetiriSatiri(nominal: 30, inflation: 30));
      expect(tester.takeException(), isNull);
      expect(find.text('başa baş'), findsOneWidget);
      expect(find.textContaining('100 lira'), findsOneWidget);
    });

    testWidgets('reel veri yok: kutu hiç çizilmez, kalan kart sağlam',
        (tester) async {
      await kur(tester, hareketler: uc, reel: null);
      expect(tester.takeException(), isNull);
      expect(find.text('Paran fiyatlara yetişiyor mu?'), findsNothing);
      expect(baslikVar, isTrue);
    });

    testWidgets('320pt, yazı ×2: alım gücü kutusu taşmaz', (tester) async {
      await kur(tester,
          hareketler: uc,
          genislik: 320,
          yaziOlcegi: 2,
          reel: const ReelGetiriSatiri(nominal: 5.5, inflation: 29.73));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('hedefe ulaşıldı: satır "Ulaşıldı" yazar, taşma yok',
      (tester) async {
    final container = await kur(tester, hareketler: uc);
    await container.read(kapsamHedefiProvider('').notifier).set(10000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(sigan('Hedef · Ulaşıldı'), findsWidgets);
  });
}
