import 'package:flutter/material.dart';
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
import 'package:portfoy_takip/widgets/ortak_secici.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';
import 'package:portfoy_takip/widgets/raporlar_kapisi.dart';
import 'package:portfoy_takip/widgets/tur_filtre_izgarasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Sadeleştirme 2 — S2 (`performans_tek_akis`) ve S6 (`raporlar_kapisi`).
///
/// Her iki bayrak için iki yön sınanır: KAPALI → bugünkü ekran birebir
/// (Grafik | Özet anahtarı, kapsam çipi, kupa), AÇIK → yeni düzen (tek
/// kontrol satırı + Filtre alt sayfası; Raporlar kapısı). Grafiğin serisi
/// testte ağdan gelmez; dönem kartının ikincil cümlesi bu yüzden saf
/// işlevden (`performansBakiyeCumlesi`), Özet'in ana rakamsız hâli
/// `PeriodSummaryView` üzerinden sınanır.
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
          Asset(
            id: 'THYAO-1',
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
            addedDate: DateTime(2026, 3, 14),
          ),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  _FakePartners(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

AppUser _ortak() => AppUser(
      id: 'p-1',
      email: 'mehmet@example.com',
      displayName: 'Mehmet Yılmaz',
      createdAt: DateTime(2026, 1, 1),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<PartnerAccount> partners = const [],
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(_FakeAuth.new),
    portfolioProvider.overrideWith(_FakePortfolio.new),
    partnersProvider.overrideWith(() => _FakePartners(partners)),
    allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
    // Yıl özeti ağdan (anlık görüntü + TÜFE) ölçülür; test belirlenimci
    // kalsın diye satır kapalı.
    yilOzetiProvider.overrideWith((ref) async => null),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const PortfolioPerformanceScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return c;
}

Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  group('S2 performans_tek_akis — kapalı: bugünkü düzen', () {
    testWidgets('Grafik | Özet anahtarı ve kapsam çipi var, Filtre yok',
        (tester) async {
      await _pump(tester);
      expect(PortfolioPerformanceScreen.tekAkisAcik, isFalse);
      expect(find.text(_tr.tabChart), findsOneWidget);
      expect(find.text(_tr.tabSummary), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Kapsam: ')), findsOneWidget);
      expect(find.bySemanticsLabel(_tr.s2Filtre), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ortak varken kişi seçici ekranın ilk satırında',
        (tester) async {
      await _pump(tester,
          partners: [PartnerAccount(user: _ortak(), isActive: true)]);
      expect(find.byType(OrtakSecici), findsOneWidget);
    });
  });

  group('S2 performans_tek_akis — açık: tek akış', () {
    setUp(() => RemoteConfigService.testAcik = {'performans_tek_akis'});

    testWidgets('anahtar yok; tek satır: dönem seçici + Filtre çipi',
        (tester) async {
      await _pump(tester);
      expect(PortfolioPerformanceScreen.tekAkisAcik, isTrue);
      expect(find.text(_tr.tabChart), findsNothing);
      expect(find.text(_tr.tabSummary), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Kapsam: ')), findsNothing);
      expect(find.text(_tr.s2Filtre), findsOneWidget);

      // Filtre çipi dönem seçiciyle AYNI satırda (dikey merkezler hizalı).
      final donem = tester.getCenter(find.text('1 ay'));
      final filtre = tester.getCenter(find.text(_tr.s2Filtre));
      expect((donem.dy - filtre.dy).abs(), lessThan(4));
      expect(filtre.dx, greaterThan(donem.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('kişi seçici ekranda değil, Filtre sayfasında',
        (tester) async {
      await _pump(tester,
          partners: [PartnerAccount(user: _ortak(), isActive: true)]);
      expect(find.byType(OrtakSecici), findsNothing);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      expect(find.text(_tr.s2FiltreKisi), findsOneWidget);
      expect(find.byType(OrtakSecici), findsOneWidget);
    });

    testWidgets('Filtre sayfası: kategori seçimi çipe sayı yazar',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      // Ortak yok → kişi bölümü yok.
      expect(find.text(_tr.s2FiltreKisi), findsNothing);
      expect(find.text(_tr.s2FiltreKategori), findsOneWidget);
      // Orta seviye (varsayılan) grafik araçlarını açar → anahtar var.
      expect(find.text(_tr.todaysPortfolioSettingTitle), findsOneWidget);

      // Tür değişince grafik iskelete döner (sonsuz parıltı) —
      // `pumpAndSettle` yerine sabit kareler.
      await tester.tap(find.text(AssetType.fon.labelOf(_tr)));
      await _bekle(tester);
      Navigator.of(tester.element(find.text(_tr.s2FiltreKategori))).pop();
      await _bekle(tester);
      expect(find.text(_tr.s2FiltreSayili(1)), findsOneWidget);
      expect(find.bySemanticsLabel(_tr.s2FiltreEtkin(1)), findsOneWidget);
    });

    testWidgets('"Bugünkü portföyle" anahtarı Ayarlar tercihine yazar',
        (tester) async {
      final c = await _pump(tester);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      expect(c.read(bugunkuPortfoyleProvider), isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(c.read(bugunkuPortfoyleProvider), isTrue);
      Navigator.of(tester.element(find.text(_tr.s2FiltreKategori))).pop();
      await tester.pumpAndSettle();
      // Rozet davranışı aynı: 1 ay'da (gün içi değil) rozet görünür.
      await tester.tap(find.text('1 ay'));
      await _bekle(tester);
      expect(find.text(_tr.todaysPortfolioBadge), findsOneWidget);
      expect(find.text(_tr.s2FiltreSayili(1)), findsOneWidget);
    });

    testWidgets('320pt: taşma yok, çip yalnız ikon', (tester) async {
      await _pump(tester, width: 320);
      expect(find.text(_tr.s2Filtre), findsNothing);
      expect(find.bySemanticsLabel(_tr.s2Filtre), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Filtre sayfası — goz_alici açık: 3×3 tür ızgarası', () {
    setUp(() => RemoteConfigService.testAcik = {
          'performans_tek_akis',
          'goz_alici',
        });

    testWidgets('ızgara: tüm türler eşit kare, elde olmayan seçilebilir',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      expect(find.byType(TurFiltreIzgarasi), findsOneWidget);
      // Kareler simetrik: Hisse/Fon/Döviz aynı satırda, aynı genişlikte.
      final kare = find.descendant(
          of: find.byType(TurFiltreIzgarasi),
          matching: find.text(AssetType.fon.labelOf(_tr)));
      final hisse = find.descendant(
          of: find.byType(TurFiltreIzgarasi),
          matching: find.text(AssetType.hisse.labelOf(_tr)));
      expect((tester.getCenter(kare).dy - tester.getCenter(hisse).dy).abs(),
          lessThan(1));
      // Filtre yokken Sıfırla tıklanamaz; dip düğmesi sonucu söyler.
      expect(find.text(_tr.s2FiltreGoster(1)), findsOneWidget);

      await tester.tap(find.text(AssetType.fon.labelOf(_tr)));
      await _bekle(tester);
      // Fon elde yok → sonuç 0 → düğme "Tamam".
      expect(find.text(_tr.s2FiltreTamam), findsOneWidget);
      await tester.tap(find.text(_tr.s2FiltreTamam));
      await _bekle(tester);
      // Çip sayıyı değil NEYİ yazar.
      expect(find.text(AssetType.fon.labelOf(_tr)), findsOneWidget);
      expect(find.bySemanticsLabel(_tr.s2FiltreEtkin(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sıfırla kategoriyi ve "bugünkü portföyle"yi varsayılana alır',
        (tester) async {
      final c = await _pump(tester);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AssetType.hisse.labelOf(_tr)).last);
      await _bekle(tester);
      await tester.tap(find.byType(Switch));
      await _bekle(tester);
      expect(c.read(bugunkuPortfoyleProvider), isTrue);
      await tester.tap(find.text(_tr.s2FiltreSifirla));
      await _bekle(tester);
      expect(c.read(bugunkuPortfoyleProvider), isFalse);
      Navigator.of(tester.element(find.text(_tr.s2FiltreKategori))).pop();
      await _bekle(tester);
      expect(find.text(_tr.s2Filtre), findsOneWidget);
    });

    testWidgets('eurobond açık (10 tür): artan kare Tümü satırına geçer',
        (tester) async {
      RemoteConfigService.testAcik = {
        'performans_tek_akis',
        'goz_alici',
        'eurobond',
      };
      await _pump(tester);
      await tester.tap(find.text(_tr.s2Filtre));
      await tester.pumpAndSettle();
      final izgara = find.byType(TurFiltreIzgarasi);
      Offset merkez(String t) => tester.getCenter(
          find.descendant(of: izgara, matching: find.text(t)));
      final tumu = merkez(_tr.allTypes);
      // Artan kare listenin SONUNDAKİ tür (Diğer); Eurobond ızgarada.
      final euro = merkez(AssetType.diger.labelOf(_tr));
      expect((tumu.dy - euro.dy).abs(), lessThan(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320pt: sayfa taşmaz', (tester) async {
      await _pump(tester, width: 320);
      await tester.tap(find.bySemanticsLabel(_tr.s2Filtre));
      await tester.pumpAndSettle();
      expect(find.byType(TurFiltreIzgarasi), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('S2 dönem kartı ikincil cümlesi (saf)', () {
    String fmt(double v) => '₺${v.round()}';

    test('akış yoksa cümle yok', () {
      expect(
          performansBakiyeCumlesi(_tr,
              degisim: 500, yatirilan: 0.2, tutar: fmt),
          isNull);
    });

    test('bakiye arttı + alım: "bunun … kadarı yeni alım"', () {
      expect(
          performansBakiyeCumlesi(_tr,
              degisim: 12000, yatirilan: 10000, tutar: fmt),
          'Bakiye ₺12000 arttı; bunun ₺10000 kadarı yeni alım.');
    });

    test('bakiye düştü + alım: parça-bütün kurulmaz', () {
      expect(
          performansBakiyeCumlesi(_tr,
              degisim: -3000, yatirilan: 5000, tutar: fmt),
          'Bakiye ₺3000 azaldı; dönemde ₺5000 yeni alım yaptın.');
    });

    test('satış: işaret tutarda değil kalıpta', () {
      expect(
          performansBakiyeCumlesi(_tr,
              degisim: -8000, yatirilan: -6000, tutar: fmt),
          'Bakiye ₺8000 azaldı; bunun ₺6000 kadarı satış.');
      expect(
          performansBakiyeCumlesi(_tr,
              degisim: 1000, yatirilan: -6000, tutar: fmt),
          'Bakiye ₺1000 arttı; dönemde ₺6000 satış yaptın.');
    });
  });

  group('S2 Özet ana rakamsız (PeriodSummaryView)', () {
    final ozet = PeriodSummary(
      period: SummaryPeriod.birAy,
      start: DateTime(2026, 8, 14),
      end: DateTime(2026, 9, 13),
      baslangicTRY: 168774,
      sonTRY: 185684,
      katkiTRY: 12000,
      piyasaTRY: 4910,
      getiriPct: 2.72,
    );

    Future<void> kur(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: Scaffold(body: SingleChildScrollView(child: w)),
      ));
      await tester.pump();
    }

    testWidgets('varsayılan: ana rakam kartı var (eski düzen)',
        (tester) async {
      await kur(tester, PeriodSummaryView(summary: ozet));
      expect(find.textContaining('Paranın getirisi'), findsOneWidget);
      expect(find.text(_tr.sectionResult), findsOneWidget);
    });

    testWidgets('anaRakamGizli: manşet tekrar etmez, köprü + ek kalır',
        (tester) async {
      await kur(
          tester,
          PeriodSummaryView(
            summary: ozet,
            anaRakamGizli: true,
            nedenEki: const Text('TÜR DÖKÜMÜ'),
          ));
      expect(find.textContaining('Paranın getirisi'), findsNothing);
      expect(find.text(_tr.sectionWhy), findsOneWidget);
      expect(find.text('TÜR DÖKÜMÜ'), findsOneWidget);
      // Ek NEDEN'in içinde, başlığın altında.
      expect(tester.getTopLeft(find.text('TÜR DÖKÜMÜ')).dy,
          greaterThan(tester.getTopLeft(find.text(_tr.sectionWhy)).dy));
    });
  });

  group('S2 tur metni bayrağa göre dallanır', () {
    final src = ekranKaynagiSync('lib/screens/onboarding_screen.dart');
    test('Performans, dönem ve kapsam adımları tek akışı anlatır', () {
      expect('PortfolioPerformanceScreen.tekAkisAcik'.allMatches(src).length,
          greaterThanOrEqualTo(4));
      expect(src.contains('Seçtiğin dönem her ekranda geçerli olur.'), isTrue);
      expect(src.contains('RemoteConfigService.instance.donemHafizasi'),
          isTrue);
    });
  });

  group('S6 raporlar_kapisi', () {
    testWidgets('kapalı: kupa var, Raporlar yok', (tester) async {
      await _pump(tester);
      expect(find.bySemanticsLabel(_tr.raceTitle), findsOneWidget);
      expect(find.byType(RaporlarDugmesi), findsNothing);
    });

    testWidgets('açık: kupa yerine Raporlar; sayfada Sıralama satırı',
        (tester) async {
      RemoteConfigService.testAcik = {'raporlar_kapisi'};
      await _pump(tester);
      expect(find.bySemanticsLabel(_tr.raceTitle), findsNothing);
      expect(find.bySemanticsLabel(_tr.s6Raporlar), findsOneWidget);
      // Aynı kabuk: 44pt.
      final kutu = tester.getSize(find.byIcon(Icons.assessment_rounded).first);
      expect(kutu.width, lessThanOrEqualTo(SandikTouch.min));

      await tester.tap(find.byIcon(Icons.assessment_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_tr.s6Raporlar), findsOneWidget);
      expect(find.text(_tr.s6Siralama), findsOneWidget);
      // Balina radarı kapalı → Haftanın özeti ve Aylık rapor yok;
      // yıl özeti verisi yok → satır yok.
      expect(find.text(_tr.weekTitle), findsNothing);
      expect(find.text(_tr.s6AylikRapor), findsNothing);
      expect(find.text(_tr.s6YilOzeti), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('açık + balina radarı: Haftanın özeti satırı', (tester) async {
      RemoteConfigService.testAcik = {'raporlar_kapisi', 'balina_radari_acik'};
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.assessment_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_tr.weekTitle), findsOneWidget);
    });
  });
}
