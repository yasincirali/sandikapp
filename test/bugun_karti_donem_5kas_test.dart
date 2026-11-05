import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/hedef_onerisi.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/services/bugun_yukleyici.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/donem_ozeti_yukleyici.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/hedef_sheet.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 5 Kas 19:00 (Ana sayfa ikinci tur), müşteri YAP:
///  1. Dönem segmenti kartı YERİNDE çevirir; sayı Özet'in aynı dönemdeki
///     özetiyle aynı fonksiyondan (`DonemOzetiYukleyici`).
///  2. "Hedefin yok · Hedef belirle" ✕ ile kapanır; üç günde dokunulmazsa
///     30 gün söner; sönünce Profil'de "Portföy hedefi" satırı belirir.
///  3. Başlık seçili dönemi yazar.

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

final _simdi = DateTime(2026, 10, 9, 15);

final _defter = [
  _asset('THYAO', 100, 300, 312.40),
  _asset('ASELS', 10, 1100, 1000),
];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
}

/// Haftalık sahte seri: günde bir nokta, 38.000'den 40.000'e.
PortfolioHistoryBreakdown _haftaSerisi() {
  final total = <int, double>{
    for (var g = 7; g >= 1; g--)
      dayKey(_simdi).subtract(Duration(days: g)).millisecondsSinceEpoch:
          38000 + (7 - g) * 300.0,
  };
  return PortfolioHistoryBreakdown(
    total: total,
    byType: {AssetType.hisse: total},
    byPosition: const {},
    positionType: const {},
  );
}

Finder _baslik(bool Function(String) kosul) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return e.widget is SiganMetin &&
          r is SiganMetinRender &&
          kosul(r.secilen);
    });

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  group('HedefOnerisiDurumu (saf kural)', () {
    final g1 = DateTime(2026, 11, 5, 10);
    final g2 = DateTime(2026, 11, 6, 10);
    final g3 = DateTime(2026, 11, 7, 10);

    test('varsayılan görünür; bozuk/eski kod varsayılana düşer', () {
      expect(const HedefOnerisiDurumu().gorunur(g1), isTrue);
      expect(HedefOnerisiDurumu.coz('').gorunur(g1), isTrue);
      expect(HedefOnerisiDurumu.coz('x:y').gorunur(g1), isTrue);
      expect(HedefOnerisiDurumu.coz('a:b:c:1').gorunur(g1), isTrue);
    });

    test('üç ayrı günde dokunulmazsa 30 gün söner, sonra döner', () {
      var d = const HedefOnerisiDurumu();
      d = d.gosterildi(g1);
      // Aynı gün ikinci kez sayılmaz.
      expect(identical(d.gosterildi(g1.add(const Duration(hours: 3))), d),
          isTrue);
      d = d.gosterildi(g2);
      expect(d.gorunur(g2), isTrue);
      d = d.gosterildi(g3);
      expect(d.gorunur(g3.add(const Duration(days: 1))), isFalse,
          reason: 'üçüncü gösterimden sonra söner');
      expect(d.gorunur(g3.add(const Duration(days: 29))), isFalse);
      expect(d.gorunur(g3.add(const Duration(days: 30))), isTrue,
          reason: '30 gün sonra yeniden şans');
      // Kod gidip gelir.
      expect(HedefOnerisiDurumu.coz(d.kod).kod, d.kod);
    });

    test('dokunuş sayacı sıfırlar; ✕ kalıcı kapatır', () {
      var d = const HedefOnerisiDurumu().gosterildi(g1).gosterildi(g2);
      d = d.dokunuldu();
      expect(d.gosterildi(g3).gorunur(g3.add(const Duration(days: 1))), isTrue);
      final k = d.kapatildi();
      expect(k.gorunur(g3), isFalse);
      expect(k.gorunur(DateTime(2030)), isFalse, reason: 'kapatılan dönmez');
      expect(HedefOnerisiDurumu.coz(k.kod).kapali, isTrue);
    });
  });

  group('kart', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      BugunKarti.anliklariTemizle();
      HistoryService.clearCache();
      HistoryService.seriCekici = (s, r, i) async => const [];
      IntradaySeriesCache.instance.clear();
      BugunKarti.saat = () => _simdi;
      BugunYukleyici.reelTest = null;
    });
    tearDown(() {
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      BugunKarti.anliklariTemizle();
      BugunKarti.donemSerisiTestCekici = null;
      IntradaySeriesCache.instance.clear();
      BugunKarti.saat = DateTime.now;
    });

    Future<(ProviderContainer, PortfolioState)> kur(WidgetTester tester,
        {double genislik = 390, double olcek = 1}) async {
      tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ]);
      addTearDown(container.dispose);
      final state = await container.read(portfolioProvider.future);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: BugunKarti(state: state)),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 2));
      return (container, state);
    }

    testWidgets(
        'Hafta: kart yerinde değişir, sayı Özet\'in fonksiyonuyla aynı, '
        'başlık dönemi yazar', (tester) async {
      final istenen = <SummaryPeriod>[];
      BugunKarti.donemSerisiTestCekici = (p, lotlar) async {
        istenen.add(p);
        return _haftaSerisi();
      };
      final (_, state) = await kur(tester);
      expect(find.text('Hafta'), findsOneWidget);

      await tester.tap(find.text('Hafta'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(istenen, [SummaryPeriod.birHafta]);

      // Beklenen sayı: Özet'in çağırdığı aynı fonksiyon, aynı seri ve uç.
      final beklenen = DonemOzetiYukleyici.ozet(
        period: SummaryPeriod.birHafta,
        state: state,
        breakdown: _haftaSerisi(),
        now: _simdi,
      )!;
      final s = GunlukDegisimSatiri(
          changeTRY: beklenen.piyasaTRY!, changePct: beklenen.getiriPct ?? 0);
      final tutar =
          '${s.changeTRY > 0 ? '+' : '−'}${fmtTRY(s.changeTRY.abs())}';
      expect(find.text(tutar), findsOneWidget,
          reason: 'kart Özet\'in hafta rakamını yazmalı');

      // Başlık: "Hafta · …" — canlı durumu ("Canlı · …") yok.
      expect(_baslik((m) => m.startsWith('Hafta')), findsOneWidget);
      expect(_baslik((m) => m.startsWith('Bugün')), findsNothing);
      // Performans kısayolu duruyor.
      expect(_baslik((m) => m == "Performans'ta aç"), findsOneWidget);

      // Bugün'e dönünce gün başlığı geri gelir, seri yeniden çekilmez.
      await tester.tap(find.text('Bugün').last);
      await tester.pump(const Duration(seconds: 1));
      expect(_baslik((m) => m.startsWith('Hafta')), findsNothing);
      await tester.tap(find.text('Hafta'));
      await tester.pump(const Duration(seconds: 1));
      expect(istenen, [SummaryPeriod.birHafta],
          reason: 'taze seri bellekten (1 dk)');
    });

    testWidgets('seri boşsa uydurma sayı yok, durum cümlesi', (tester) async {
      BugunKarti.donemSerisiTestCekici =
          (p, lotlar) async => const PortfolioHistoryBreakdown.empty();
      await kur(tester);
      await tester.tap(find.text('Yıl'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Bu dönemin verisi yok'), findsOneWidget);
    });

    for (final (g, o) in [(320.0, 2.0), (280.0, 1.5)]) {
      testWidgets('${g.toInt()}pt ×$o: dönem görünümünde taşma yok',
          (tester) async {
        BugunKarti.donemSerisiTestCekici = (p, l) async => _haftaSerisi();
        await kur(tester, genislik: g, olcek: o);
        await tester.tap(find.text('Ay'));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('hedef önerisi ✕ ile kapanır, Profil satırı belirir',
        (tester) async {
      final (container, _) = await kur(tester);
      expect(find.text('Hedefin yok'), findsOneWidget);
      // İlk gösterim sayıldı (kare sonrası yazılır).
      expect(
          HedefOnerisiDurumu.coz(container.read(hedefOnerisiProvider)).sayi, 1);

      await tester.tap(find.bySemanticsLabel('Hedef önerisini gizle'));
      await tester.pump();
      expect(find.text('Hedefin yok'), findsNothing);
      expect(
          HedefOnerisiDurumu.coz(container.read(hedefOnerisiProvider)).kapali,
          isTrue);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HedefProfilSatiri())),
      ));
      expect(find.text('Portföy hedefi'), findsOneWidget);
    });

    testWidgets('öneri görünürken Profil satırı yok', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HedefProfilSatiri())),
      ));
      expect(find.text('Portföy hedefi'), findsNothing);
    });
  });

  test('Performans Özet aynı seri fonksiyonunu çağırır (iki merdiven yok)',
      () {
    final ozet = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
    expect(
        ozet.contains(
            'DonemOzetiYukleyici.seri(period, chartAssets, simulate: simulate)'),
        isTrue);
    // Özet'in compute çağrısı canlı ucu ve dağılımı aynı kaynaktan alır;
    // yükleyici de öyle.
    expect(ozet.contains('DailySummary.kapsamToplami(pState, targetAssets)'),
        isTrue);
    final y = ekranKaynagiSync('lib/services/donem_ozeti_yukleyici.dart');
    expect(y.contains('canliSon: DailySummary.kapsamToplami(state, lotlar)'),
        isTrue);
    expect(y.contains('performansSeriDefterleri('), isTrue);
  });
}
