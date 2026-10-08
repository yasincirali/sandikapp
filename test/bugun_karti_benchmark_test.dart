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

import 'helpers/kaynak.dart';

/// Bugün kartı — benchmark düzeni (kullanıcı seçimi 2026-10-09).
///
/// Sekiz uygulamanın ortak paydası beş bileşen: büyük tutar + delta rozeti,
/// grafik + dönem çipleri, renk = durum, oynayanlar sırası, hedef çubuğu;
/// altıncısı (alım gücü) sandık'ın farkı. Bu test üç şeyi kilitler:
///   1. saf hesap — "100 liran bugün kaç lira" formülü,
///   2. gerçek ağaçta beş bileşen ve dar ekranda taşma yok,
///   3. hareketi azalt açıkken eğri tek karede tam çizilir.

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
  group('alım gücü — saf', () {
    test('100 lira: (1+n)/(1+e) — ekrandaki 5,50 / 29,73 → 81', () {
      // 2026-10-09 ekran görüntüsündeki gerçek sayılar.
      const r = ReelGetiriSatiri(nominal: 5.50, inflation: 29.73);
      expect(r.yuzLiraBugun, closeTo(81.3, 0.05));
      expect(r.onde, isFalse);
    });
    test('öndeyken 100\'ü aşar, başa başta 100', () {
      expect(
          const ReelGetiriSatiri(nominal: 48.2, inflation: 45.1).yuzLiraBugun,
          closeTo(102.1, 0.05));
      expect(const ReelGetiriSatiri(nominal: 30, inflation: 30).yuzLiraBugun,
          closeTo(100, 1e-9));
    });
    test('negatif getiri de aynı formül — uydurma yok', () {
      expect(const ReelGetiriSatiri(nominal: -10, inflation: 25).yuzLiraBugun,
          closeTo(72, 0.01));
    });
  });

  group('kart — gerçek ağaç', () {
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
          (_) => const ReelGetiriSatiri(nominal: 5.50, inflation: 29.73);
      // Sabit hafta içi, seans açık: kart cihaz saatine göre "Piyasa
      // kapalı" / "Gün içi veri geliyor" çizebilir; test buna bağlı olmasın.
      BugunKarti.saat = () => _simdi;
    });
    tearDown(() {
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      BugunKarti.anliklariTemizle();
      IntradaySeriesCache.instance.clear();
      BugunYukleyici.reelTest = null;
      BugunKarti.saat = DateTime.now;
    });

    Future<void> kur(WidgetTester tester,
        {required double genislik,
        bool azalt = false,
        bool dusus = false}) async {
      tester.view.physicalSize = Size(genislik * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ]);
      addTearDown(container.dispose);
      final state = await container.read(portfolioProvider.future);

      final gun = dayKey(_simdi);
      int ms(int saat) => gun.add(Duration(hours: saat)).millisecondsSinceEpoch;
      final kume = state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList();
      final kThy = positionKey(_defter[0]);
      final kAsl = positionKey(_defter[1]);
      IntradaySeriesCache.instance.seedForTest(
        series: dusus
            ? {ms(10): 41700, ms(15): 41000}
            : {ms(10): 41000, ms(15): 41700},
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
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: azalt),
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(child: BugunKarti(state: state)),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
    }

    for (final genislik in [390.0, 320.0]) {
      testWidgets('${genislik.toInt()}pt: beş bileşen kurulur, taşma yok',
          (tester) async {
        await kur(tester, genislik: genislik);
        expect(tester.takeException(), isNull);
        // 1. Hüküm + rozet: "Yükseldi" ve "+₺240" — açılış 41.000, uç
        // CANLI toplam (100×312,40 + 10×1.000 = 41.240; `DailySummary`
        // son noktayı canlı toplamla değiştirir, seri 41.700 demese de).
        expect(find.text('Yükseldi'), findsOneWidget);
        expect(find.textContaining('+₺240'), findsOneWidget);
        // Yüzde rozeti yok (benchmark: tutar rozette, yüzde ekran okuyucuda).
        expect(find.textContaining('%1,71'), findsNothing);
        // 2. Dönem çipleri — Bugün seçili, diğerleri Özet kısayolu.
        for (final ad in ['Bugün', 'Hafta', 'Ay', 'Yıl']) {
          expect(find.text(ad), findsOneWidget, reason: ad);
        }
        // 3. Oynayanlar sırası + "Tümü".
        // Başlık `SiganMetin`: Ahem'de kısa yazım seçilebilir.
        expect(
            sigan('Bugün en çok oynayanlar').evaluate().isNotEmpty ||
                sigan('En çok oynayan').evaluate().isNotEmpty,
            isTrue);
        expect(find.text('THYAO'), findsOneWidget);
        expect(find.text('Tümü'), findsOneWidget);
        // 4. Alım gücü: soru, 100 → 81, hüküm rozeti, iki yüzde gri satırda.
        expect(find.text('Paran fiyatlara yetişiyor mu?'), findsOneWidget);
        expect(find.textContaining('81 lira'), findsOneWidget);
        expect(find.text('Fiyatlar önde'), findsOneWidget);
        expect(find.textContaining('Paran %5,50 büyüdü, fiyatlar %29,73 arttı'),
            findsOneWidget);
        // "puan" ana satırda yok.
        expect(find.textContaining('puan'), findsNothing);
        // 5. Hedef satırı.
        expect(sigan('Hedef belirle'), findsOneWidget);
      });
    }

    testWidgets('düşüşte hüküm "Geriledi", rozet eksi tutar', (tester) async {
      await kur(tester, genislik: 390, dusus: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Geriledi'), findsOneWidget);
      // Açılış 41.700, canlı toplam 41.240 → −₺460.
      expect(find.textContaining('−₺460'), findsOneWidget);
    });

    testWidgets('hareketi azalt: eğri ve çubuk tek karede tam', (tester) async {
      await kur(tester, genislik: 390, azalt: true);
      expect(tester.takeException(), isNull);
      // Giriş akışları `SandikMotion.of` ile sıfır süreli: ilk kareden sonra
      // TweenAnimationBuilder'lar hedefte (0 ara değer yok).
      final tweens = tester
          .widgetList<TweenAnimationBuilder<double>>(
              find.byType(TweenAnimationBuilder<double>))
          .toList();
      expect(tweens, isNotEmpty);
      for (final t in tweens) {
        expect(t.duration, Duration.zero,
            reason: 'hareketi azalt açıkken süre sıfır olmalı');
      }
    });

    testWidgets('hedef belirlenince satır ilerlemeyi yazar', (tester) async {
      await kur(tester, genislik: 390);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BugunKarti)));
      await container.read(kapsamHedefiProvider('').notifier).set(100000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(sigan('Hedefe %41'), findsOneWidget);
      expect(sigan('Hedef belirle'), findsNothing);
    });
  });

  group('kaynak sözleşmesi', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');

    test('beş bileşen ve altıncısı kaynakta', () {
      expect(src.contains('_HukumSatiri('), isTrue);
      expect(src.contains('_DeltaRozeti('), isTrue);
      expect(src.contains('_GunIciEgri('), isTrue);
      expect(src.contains('_DonemCipleri('), isTrue);
      expect(src.contains('_OynayanlarSirasi('), isTrue);
      expect(src.contains('_AlimGucuKutusu('), isTrue);
      expect(src.contains('_EylemKutusu('), isTrue);
    });

    test('önceki düzenlerin parçaları kalktı', () {
      expect(src.contains('_YuzdeRozeti'), isFalse,
          reason: 'yüzde rozeti benchmark düzeninde yok');
      expect(src.contains('kivilcimGenisligi'), isFalse,
          reason: 'satır içi kıvılcım yerine tam genişlik eğri');
      expect(src.contains('_EnflasyonKiyasi'), isFalse);
      expect(src.contains('_BilgiKutusu'), isFalse);
      expect(src.contains('_Izgara'), isFalse);
    });

    test('dönem çipleri yeni seri çekmez — Özet kısayolu', () {
      // Gün içi tek seri kuralı (2026-10-02): kart kendi seri merdivenini
      // kurmaz; çip `_ozeteGit` ile Özet'e gider.
      expect(
          src.contains(
              '_DonemCipleri(onSec: (p) => _ozeteGit(periodIdx: p.index))'),
          isTrue);
      expect(src.contains('HistoryService.'), isFalse,
          reason:
              'kart seriyi yalnız BugunYukleyici / IntradaySeriesCache\'ten alır');
    });

    test('oynayanlar sırası ≤3, aynı kural (enCokOynayanlar)', () {
      expect(
          src.contains('enCokOynayanlar(bd, lotlar: kume, now: now)'), isTrue);
    });

    test('her hareket SandikMotion.of ile (reduce-motion)', () {
      // Çıplak Duration(milliseconds:) yalnız kademe gecikmesinde ve o da
      // `SandikMotion.of`'tan geçer.
      final ciplak =
          RegExp(r'Duration\(milliseconds:\s*\d').allMatches(src).length;
      expect(ciplak, 0, reason: 'süreler SandikMotion token\'larından');
      expect(src.contains('SandikMotion.flowOf(context)'), isTrue);
      expect(src.contains('SandikMotion.stateOf(context)'), isTrue);
      expect(src.contains('SandikMotion.surfaceOf(context)'), isTrue);
    });

    test('gün içi eğri açılış seviyesini kesik çizgiyle gösterir', () {
      expect(src.contains('final tabanY = y(seri.first);'), isTrue);
    });
  });
}
