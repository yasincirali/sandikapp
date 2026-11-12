import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/recap_screen.dart' show yilOzetiProvider;
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/disclaimer_widget.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';
import 'package:portfoy_takip/widgets/sandik_paylas_dugmesi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Performans üçüncü tur (Ar-Ge 2026-11-07 12:15, artifact
/// CgxHdHoo77dJSQwg3paFzz) — beş madde:
/// 1. dönem çipleri + Filtre üst çubuğa iliştirili (3,1× yazıda değil),
/// 2. hiçbir şey değişmediyse köprü yerine tek cümle,
/// 3. "Neden böyle?" bölüm başlığı tek kartın üstünde çizilmez,
/// 4. rakam yokken paylaş düğmesi yok,
/// 5. Performans dipnotu tek satır + "Ayrıntı" alt sayfası.
final _tr = AppLocalizationsTr();
const _uid = 'user-1';

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
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          for (var i = 0; i < 3; i++)
            Asset(
              id: 'L$i',
              userId: _uid,
              name: 'Türk Hava Yolları',
              ticker: 'THYAO.IS',
              type: AssetType.hisse,
              quantity: 100,
              purchasePrice: 250.75,
              currency: 'TRY',
              notes: '',
              isManualPrice: false,
              currentPrice: 312.40,
              addedDate: DateTime(2026, 3, 14 + i),
            ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
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

const _magaza = {'performans_tek_akis', 'goz_alici'};

Future<void> _pump(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double olcek = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = olcek;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        yilOzetiProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const PortfolioPerformanceScreen(),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Dikey ana liste (gövdenin ilk kaydırıcısı).
Finder get _liste => find
    .byWidgetPredicate((w) =>
        w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;

Future<void> _kaydir(WidgetTester tester, double dy) async {
  await tester.drag(_liste, Offset(0, -dy));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _ilisik = ValueKey('performans_ilisik_kontroller');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    RemoteConfigService.testAcik = _magaza;
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  group('#1 dönem çipleri + Filtre iliştirili', () {
    testWidgets('normal yazıda satır üst çubukta, kaydırınca yerinde kalır',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(_ilisik), findsOneWidget);
      expect(find.text('1 ay'), findsOneWidget);
      expect(find.text(_tr.s2Filtre), findsOneWidget);
      final once = tester.getTopLeft(find.text('1 ay'));
      await _kaydir(tester, 500);
      final sonra = tester.getTopLeft(find.text('1 ay'));
      expect(sonra.dy, once.dy, reason: 'satır kaydırmayla kaymaz');
      // Satır kaydırılan içeriğin ÜSTÜNDE çizilir ve dokunulabilir.
      expect(find.text('1 ay').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cam kapalıyken de (başlık sabit sütun) iliştirili',
        (tester) async {
      RemoteConfigService.testAcik = {'performans_tek_akis'};
      await _pump(tester);
      expect(find.byKey(_ilisik), findsOneWidget);
      final once = tester.getTopLeft(find.text('1 ay'));
      await _kaydir(tester, 500);
      expect(tester.getTopLeft(find.text('1 ay')).dy, once.dy);
    });

    testWidgets('3,1× yazıda iliştirme kalkar, satır listeyle akar',
        (tester) async {
      await _pump(tester, olcek: 3.1);
      expect(find.byKey(_ilisik), findsNothing);
      expect(find.text('1 ay'), findsOneWidget);
      final once = tester.getTopLeft(find.text('1 ay'));
      await _kaydir(tester, 200);
      final bulunan = find.text('1 ay');
      if (bulunan.evaluate().isNotEmpty) {
        expect(tester.getTopLeft(bulunan).dy, lessThan(once.dy - 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tek akış kapalıyken eski düzen (iliştirme yok)',
        (tester) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await _pump(tester);
      expect(find.byKey(_ilisik), findsNothing);
    });

    testWidgets('tur hedefi dönem seçicide kalır (TourAnchor)',
        (tester) async {
      final src = ekranKaynagiSync(
          'lib/screens/portfolio_performance/kontroller.dart');
      expect(src, contains('target: TourTarget.donemSecici'));
      await _pump(tester);
      expect(find.byKey(_ilisik), findsOneWidget);
    });
  });

  group('taşma ve dokunma alanı', () {
    for (final (g, o) in [(390.0, 1.0), (320.0, 1.0), (320.0, 3.1), (390.0, 3.1)]) {
      testWidgets('${g.toInt()} pt, ${o}x: taşma yok', (tester) async {
        await _pump(tester, width: g, olcek: o);
        expect(tester.takeException(), isNull);
        await _kaydir(tester, 2000);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Filtre ve "Ayrıntı" ≥44 pt', (tester) async {
      await _pump(tester);
      final filtre = tester.getSize(find
          .ancestor(
              of: find.text(_tr.s2Filtre),
              matching: find.byWidgetPredicate((w) => w.runtimeType
                  .toString()
                  .startsWith('CupertinoButton')))
          .first);
      expect(filtre.height, greaterThanOrEqualTo(SandikTouch.min));
      await _kaydir(tester, 4000);
      final ayrinti =
          tester.getSize(find.byKey(const ValueKey('performans_dipnot_ayrinti')));
      expect(ayrinti.height, greaterThanOrEqualTo(SandikTouch.min));
      expect(ayrinti.width, greaterThanOrEqualTo(SandikTouch.min));
    });
  });

  group('#4 rakam yokken paylaş yok', () {
    testWidgets('veri gelmedi / değişim yok: paylaş düğmesi çizilmez',
        (tester) async {
      await _pump(tester);
      final rakamYok = find.text(_tr.todayNoDataYet).evaluate().isNotEmpty ||
          find.text(_tr.noChange).evaluate().isNotEmpty;
      expect(rakamYok, isTrue,
          reason: 'test düzeneğinde seri ağdan gelmez; manşet rakamsız');
      // 2026-11-12: düğmenin YERİ hep ayrılı (gelip giderken manşet ve
      // grafik kayıyordu); rakamsızken görünmez, dokunulmaz, ekran okuyucuya
      // kapalı. Kural aynı: paylaşılamaz.
      final dugme = find.byType(SandikPaylasDugmesi);
      expect(dugme.hitTestable(), findsNothing);
      for (final e in dugme.evaluate()) {
        final opak = e.findAncestorWidgetOfExactType<AnimatedOpacity>();
        expect(opak?.opacity, 0);
        expect(e.findAncestorWidgetOfExactType<ExcludeSemantics>()?.excluding,
            isTrue);
      }
    });

    test('kural kaynakta: düz manşette paylaş geri çağrısı null', () {
      final src = ekranKaynagiSync(
          'lib/screens/portfolio_performance/kartlar.dart');
      expect(src, contains('kart(piyasaFlat ? null : paylas)'));
    });
  });

  group('#5 Performans dipnotu', () {
    testWidgets('Performans\'ta tek satır + Ayrıntı; dokununca tam metin',
        (tester) async {
      await _pump(tester);
      await _kaydir(tester, 4000);
      expect(find.text(_tr.disclaimerText), findsNothing);
      final kisa = find.byKey(const ValueKey('performans_dipnot_kisa'));
      expect(kisa, findsOneWidget);
      // Tek satır. Sığma (kesilmeme) burada ölçülmez: test yazı tipi Ahem
      // her harfi kare çizer; DM Sans ile 390 pt'de sığdığı görsel
      // önizlemede doğrulandı.
      final rp = tester.renderObject<RenderParagraph>(kisa);
      expect(rp.maxLines, 1);
      await tester.tap(find.byKey(const ValueKey('performans_dipnot_ayrinti')));
      await tester.pumpAndSettle();
      expect(find.text(_tr.disclaimerSheetTitle), findsOneWidget);
      expect(find.text(_tr.disclaimerText), findsOneWidget);
    });

    testWidgets('320 pt normal yazıda da tek satır, taşma yok', (tester) async {
      await _pump(tester, width: 320);
      await _kaydir(tester, 4000);
      final rp = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('performans_dipnot_kisa')));
      expect(rp.maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('büyük yazıda sarmalanır (yasal cümle kesilmez)',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: const Scaffold(body: DisclaimerWidget(kisa: true)),
      ));
      final rp = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('performans_dipnot_kisa')));
      expect(rp.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('öteki ekranlar: varsayılan uzun metin aynen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: const Scaffold(body: DisclaimerWidget()),
      ));
      expect(find.text(_tr.disclaimerText), findsOneWidget);
      expect(find.text(_tr.disclaimerDetails), findsNothing);
    });

    // 2026-11-10: kısa biçim Performans'tan çan sayfasına ve varlık
    // ekranlarına yayıldı (aynı tam metin beş yerde kutuydu). Tam kutu
    // yalnız sinyal ayarında kalır: teknik sinyalin kendisini anlatan ekran.
    test('kısa biçim her yerde, tam kutu yalnız sinyal ayarında', () {
      for (final f in [
        'lib/screens/portfolio_performance_screen.dart',
        'lib/screens/home_screen.dart',
        'lib/screens/asset_detail_screen.dart',
        'lib/screens/varlik_sayfasi.dart',
      ]) {
        final k = ekranKaynagiSync(f);
        expect(k, contains('DisclaimerWidget(kisa: true)'), reason: f);
        expect(k.contains('DisclaimerWidget()'), isFalse, reason: f);
      }
      final sinyal =
          ekranKaynagiSync('lib/screens/signal_settings_screen.dart');
      expect(sinyal, contains('const DisclaimerWidget()'));
      expect(sinyal.contains('kisa: true'), isFalse);
    });
  });

  group('#2 / #3 Özet köprüsü', () {
    Future<void> kur(WidgetTester tester, PeriodSummary s,
        {bool gizli = true}) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PeriodSummaryView(summary: s, anaRakamGizli: gizli))),
      ));
      await tester.pump();
    }

    PeriodSummary ozet(SummaryPeriod p,
            {double katki = 0, double piyasa = 0}) =>
        PeriodSummary(
          period: p,
          start: DateTime(2026, 11, 7),
          end: DateTime(2026, 11, 7),
          baslangicTRY: 31240,
          sonTRY: 31240 + katki + piyasa,
          katkiTRY: katki,
          piyasaTRY: piyasa,
          getiriPct: 0,
        );

    testWidgets('fiyat etkisi ve para hareketi 0: köprü yerine tek cümle',
        (tester) async {
      await kur(tester, ozet(SummaryPeriod.gunluk));
      expect(find.text(_tr.whereItCameFrom), findsOneWidget);
      expect(find.text(_tr.noChangeBridgeToday), findsOneWidget);
      expect(find.text(_tr.periodStart), findsNothing);
      expect(find.text(_tr.marketAddedRow), findsNothing);
      expect(find.text(_tr.allChangeFromPrice), findsNothing);
    });

    testWidgets('dönemde aynı durum: dönem cümlesi', (tester) async {
      await kur(tester, ozet(SummaryPeriod.birHafta));
      expect(find.text(_tr.noChangeBridgePeriod), findsOneWidget);
    });

    testWidgets('fiyat etkisi varsa köprü çizilir', (tester) async {
      await kur(tester, ozet(SummaryPeriod.gunluk, piyasa: 420));
      expect(find.text(_tr.noChangeBridgeToday), findsNothing);
      expect(find.text(_tr.periodStart), findsOneWidget);
      expect(find.text(_tr.allChangeFromPrice), findsOneWidget);
    });

    testWidgets('para hareketi varsa köprü çizilir', (tester) async {
      await kur(tester, ozet(SummaryPeriod.birAy, katki: 5000));
      expect(find.text(_tr.noChangeBridgePeriod), findsNothing);
      expect(find.text(_tr.investedRow), findsOneWidget);
    });

    test('kuruş altı fiyat etkisi sıfır sayılır', () {
      expect(
          PeriodSummaryView.koprusuzMu(
              ozet(SummaryPeriod.gunluk, piyasa: 0.3)),
          isTrue);
      expect(
          PeriodSummaryView.koprusuzMu(ozet(SummaryPeriod.gunluk, piyasa: 3)),
          isFalse);
    });

    testWidgets('#3 tek akışta "Neden böyle?" başlığı yok', (tester) async {
      await kur(tester, ozet(SummaryPeriod.birAy, piyasa: 900));
      expect(find.text(_tr.sectionWhy), findsNothing);
      expect(find.text(_tr.whereItCameFrom), findsOneWidget);
    });

    testWidgets('#3 eski düzende ("Ne oldu?" varken) başlık kalır',
        (tester) async {
      await kur(tester, ozet(SummaryPeriod.birAy, piyasa: 900), gizli: false);
      expect(find.text(_tr.sectionResult), findsOneWidget);
      expect(find.text(_tr.sectionWhy), findsOneWidget);
    });

    testWidgets('320 pt / 3,1×: sıfır cümlesi taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PeriodSummaryView(
                    summary: ozet(SummaryPeriod.gunluk),
                    anaRakamGizli: true))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
