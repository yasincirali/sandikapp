import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_tipi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/grafik_tipi_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme listesi madde 5 ve 10'un kalanı — bayrak
/// `performans_ayar_sade` (varsayılan KAPALI).
///
///   a) Grafik tipi seçicisi 5 → 2 (Çizgi, Mum); kümede olmayan seçim
///      Çizgi çizilir ama seçim DEĞİŞMEZ — bayrak kapanınca geri gelir.
///   b) "Bugünkü portföyle" Performans kapsam panelinden Ayarlar ›
///      Görünüm'e; Performans aynı provider'ı okur, etkinken rozet.
///   c) Ayarlar gruplu başlıklar + katlanır "Gelişmiş"; hiçbir satır kaybolmaz.
final _tr = AppLocalizationsTr();
const _bayrak = 'performans_ayar_sade';
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
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

ProviderContainer _kap() {
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(_FakeAuth.new),
    portfolioProvider.overrideWith(_FakePortfolio.new),
    partnersProvider.overrideWith(_FakePartners.new),
    allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _boyut(WidgetTester tester, double w, {double h = 900}) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Widget _uygulama(ProviderContainer c, Widget ekran,
        {double metinOlcegi = 1.0}) =>
    UncontrolledProviderScope(
      container: c,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(metinOlcegi)),
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: ekran,
        ),
      ),
    );

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
    RemoteConfigService.testAcik = {};
    grafikTipiNotifier.value = GrafikTipi.varsayilan;
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
    grafikTipiNotifier.value = GrafikTipi.varsayilan;
  });

  test('bayrak varsayılanı KAPALI', () {
    expect(RemoteConfigService.instance.performansAyarSade, isFalse);
  });

  group('a) grafik tipi — eşleme saf', () {
    test('sade küme yalnız Çizgi ve Mum', () {
      expect(GrafikTipi.secilebilir(sade: true),
          [GrafikTipi.line, GrafikTipi.candle]);
      expect(GrafikTipi.secilebilir(sade: false), GrafikTipi.values);
    });

    test('kümede olmayan seçim Çizgi çizilir; kapalıyken aynen', () {
      for (final t in [GrafikTipi.mountain, GrafikTipi.baseline, GrafikTipi.bar]) {
        expect(GrafikTipi.etkin(t, sade: true), GrafikTipi.line, reason: t.name);
        expect(GrafikTipi.etkin(t, sade: false), t, reason: t.name);
      }
      expect(GrafikTipi.etkin(GrafikTipi.candle, sade: true), GrafikTipi.candle);
    });

    test('grafik araçları gizliyse (sade Başlangıç) her zaman Çizgi', () {
      for (final t in GrafikTipi.values) {
        expect(GrafikTipi.etkin(t, sade: false, araclar: false), GrafikTipi.line);
      }
    });
  });

  group('a) grafik tipi seçicisi', () {
    Future<void> ac(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));
      await tester.tap(find.byType(GrafikTipiSecici));
      await tester.pumpAndSettle();
    }

    testWidgets('bayrak açık: menüde iki tip', (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await ac(tester);
      expect(find.byType(PopupMenuItem<GrafikTipi>), findsNWidgets(2));
      for (final ad in ['Alan', 'Taban', 'Çubuk']) {
        expect(find.text(ad), findsNothing, reason: ad);
      }
      expect(find.text('Mum'), findsOneWidget);
    });

    testWidgets('bayrak kapalı: beş tip (eski)', (tester) async {
      await ac(tester);
      expect(find.byType(PopupMenuItem<GrafikTipi>), findsNWidgets(5));
    });

    testWidgets('kayıtlı "Alan" açıkta Çizgi görünür, kapalıda geri gelir',
        (tester) async {
      grafikTipiNotifier.value = GrafikTipi.mountain;
      RemoteConfigService.testAcik = {_bayrak};
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));
      expect(find.text('Çizgi'), findsOneWidget);
      expect(find.text('Alan'), findsNothing);
      expect(grafikTipiNotifier.value, GrafikTipi.mountain,
          reason: 'seçim yazılmaz, yalnız okunurken eşlenir');

      RemoteConfigService.testAcik = {};
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici(key: Key('y')))),
      ));
      expect(find.text('Alan'), findsOneWidget);
    });
  });

  group('b) "Bugünkü portföyle" — tek provider', () {
    Future<void> donemSec(WidgetTester tester, String donem) async {
      await tester.tap(find.text(donem));
      await _bekle(tester);
    }

    Future<void> kapsamAc(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Kapsam: ')));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }

    testWidgets('bayrak kapalı: anahtar kapsam panelinde, rozet yok',
        (tester) async {
      // Geniş: test fontu (Ahem) her harfi punto genişliğinde çizer; eski
      // anahtarın "Bugünkü portföyle" yarısı 375pt'te Ahem'le taşıyor
      // (DM Sans'la sığıyor). Bu test yerleşimi değil, varlığı ölçer.
      await _boyut(tester, 700);
      final c = _kap();
      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      await kapsamAc(tester);
      expect(find.text(_tr.modeReal), findsOneWidget);
      expect(find.text(_tr.todaysPortfolioBadge), findsOneWidget,
          reason: 'TR modeSim aynı metin — panel anahtarının sağ yarısı');
    });

    testWidgets('bayrak açık: panelde anahtar yok; Ayarlar tercihi rozet açar',
        (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await _boyut(tester, 375);
      final c = _kap();
      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      await kapsamAc(tester);
      expect(find.text(_tr.modeReal), findsNothing,
          reason: 'Gerçek|Bugünkü anahtarı Ayarlar › Görünüm\'e taşındı');
      expect(find.text(_tr.todaysPortfolioBadge), findsNothing,
          reason: 'tercih kapalı → rozet yok');

      // Ayarlar'ın yazdığı provider — Performans aynı kaynaktan okur.
      await c.read(bugunkuPortfoyleProvider.notifier).set(true);
      await _bekle(tester);
      expect(find.text(_tr.todaysPortfolioBadge), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Gün içinde simülasyonun karşılığı yok: rozet de yok.
      await donemSec(tester, 'Bugün');
      expect(find.text(_tr.todaysPortfolioBadge), findsNothing);

      await donemSec(tester, '1 ay');
      await c.read(bugunkuPortfoyleProvider.notifier).set(false);
      await _bekle(tester);
      expect(find.text(_tr.todaysPortfolioBadge), findsNothing);
    });

    testWidgets('Ayarlar anahtarı provider\'a yazar; Performans rozeti görür',
        (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await _boyut(tester, 375, h: 2000);
      final c = _kap();
      await tester.pumpWidget(
          _uygulama(c, const SettingsScreen(bolum: SettingsBolum.gorunum)));
      await _bekle(tester);
      final satir = find.text(_tr.todaysPortfolioSettingTitle);
      expect(satir, findsOneWidget);
      expect(c.read(bugunkuPortfoyleProvider), isFalse);
      await tester.ensureVisible(satir);
      // Görünüm'deki tek açma/kapama anahtarı bu satırınki.
      expect(find.byType(CupertinoSwitch), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch));
      await _bekle(tester);
      expect(c.read(bugunkuPortfoyleProvider), isTrue);

      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      expect(find.text(_tr.todaysPortfolioBadge), findsOneWidget);
    });

    testWidgets('sade Başlangıç\'ta Ayarlar satırı yok, tercih etkisiz',
        (tester) async {
      RemoteConfigService.testAcik = {_bayrak, 'seviye_anketi'};
      await _boyut(tester, 375, h: 2000);
      final c = _kap();
      await c
          .read(investorLevelIndexProvider.notifier)
          .set(YatirimciSeviyesi.baslangic.index);
      await c.read(bugunkuPortfoyleProvider.notifier).set(true);
      await tester.pumpWidget(
          _uygulama(c, const SettingsScreen(bolum: SettingsBolum.gorunum)));
      await _bekle(tester);
      expect(find.text(_tr.todaysPortfolioSettingTitle), findsNothing);

      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      expect(find.text(_tr.todaysPortfolioBadge), findsNothing);
    });

    testWidgets('320pt: rozetli Performans taşmaz', (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await _boyut(tester, 320);
      final c = _kap();
      await c.read(bugunkuPortfoyleProvider.notifier).set(true);
      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      expect(find.text(_tr.todaysPortfolioBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('c) Ayarlar — hiçbir satır kaybolmaz', () {
    // Bölüm → o bölümde mutlaka bulunması gereken satır başlıkları (eski
    // düzenin tamamı). Bildirimler'in Canlı Etkinlik kısmı iOS'a özgü;
    // test platformu Android, ayrı testte (`live_activity_settings_test`).
    final beklenen = <SettingsBolum, List<String>>{
      SettingsBolum.gorunum: [
        _tr.themeSystem,
        _tr.themeDark,
        'USD',
        _tr.investorLevel,
        _tr.language,
        _tr.textSize,
      ],
      SettingsBolum.bildirimler: [
        _tr.signalSettings,
        _tr.priceAlerts,
        _tr.quietHours,
        _tr.partnerInviteNotifications,
        _tr.briefSlotTitle,
      ],
      SettingsBolum.hesap: [
        _tr.kullaniciAdiEtiket,
        _tr.biometricLock,
        _tr.kayitliCihazlar,
        _tr.downloadMyData,
        _tr.deleteMyAccount,
      ],
      SettingsBolum.yardim: [
        _tr.contactUs,
        _tr.rateAppTitle,
        _tr.whatsNewTitle,
        _tr.replayTour,
        _tr.feedbackTitle,
        _tr.privacyPolicy,
        _tr.termsOfUse,
        _tr.kvkkNotice,
        _tr.investmentDisclaimer,
      ],
    };

    for (final acik in [false, true]) {
      for (final e in beklenen.entries) {
        testWidgets('${acik ? 'açık' : 'kapalı'}: ${e.key.name} tam',
            (tester) async {
          if (acik) RemoteConfigService.testAcik = {_bayrak};
          await _boyut(tester, 1200, h: 4000);
          await tester.pumpWidget(_uygulama(_kap(), SettingsScreen(bolum: e.key)));
          await _bekle(tester);
          for (final t in e.value) {
            expect(find.text(t), findsAtLeastNWidgets(1),
                reason: '${e.key.name}: "$t" kayboldu');
          }
        });
      }
    }

    testWidgets('açık: bölümler net başlıklı', (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await _boyut(tester, 1200, h: 4000);
      Future<void> bak(SettingsBolum b, List<String> basliklar) async {
        await tester.pumpWidget(_uygulama(_kap(), SettingsScreen(bolum: b)));
        await _bekle(tester);
        for (final t in basliklar) {
          expect(find.text(t), findsOneWidget, reason: '${b.name}: $t');
        }
      }

      await bak(SettingsBolum.gorunum,
          [_tr.settingsGroupGeneral, _tr.settingsGroupPortfolioView]);
      await bak(SettingsBolum.hesap,
          [_tr.settingsGroupSecurityAccount, _tr.settingsGroupData]);
      await bak(SettingsBolum.yardim,
          [_tr.supportUpper, _tr.settingsGroupAbout, _tr.legalUpper]);
    });

    testWidgets('açık: hub\'da teknik satırlar katlanır "Gelişmiş"te',
        (tester) async {
      RemoteConfigService.testAcik = {_bayrak};
      await _boyut(tester, 1200, h: 4000);
      await tester.pumpWidget(_uygulama(_kap(), const SettingsScreen()));
      await _bekle(tester);
      for (final b in SettingsBolum.values) {
        expect(find.text(b.baslikOf(_tr)), findsOneWidget, reason: b.name);
      }
      // Testler debug derlemede koşar → geliştirici satırı var.
      expect(find.text(_tr.settingsAdvancedUpper), findsOneWidget);
      expect(find.text('Test Crash (debug-only)'), findsNothing,
          reason: 'grup kapalı başlar');
      await tester.tap(find.text(_tr.settingsAdvancedUpper));
      await tester.pumpAndSettle();
      expect(find.text('Test Crash (debug-only)'), findsOneWidget);
    });

    testWidgets('kapalı: hub birebir eski (Gelişmiş yok, geliştirici açık)',
        (tester) async {
      await _boyut(tester, 1200, h: 4000);
      await tester.pumpWidget(_uygulama(_kap(), const SettingsScreen()));
      await _bekle(tester);
      expect(find.text(_tr.settingsAdvancedUpper), findsNothing);
      expect(find.text('Test Crash (debug-only)'), findsOneWidget);
    });

    group('açık: dar ekranda taşma yok', () {
      for (final w in <double>[320, 360]) {
        testWidgets('${w.toInt()}pt hub (Gelişmiş açık)', (tester) async {
          RemoteConfigService.testAcik = {_bayrak};
          await _boyut(tester, w, h: 1400);
          await tester.pumpWidget(_uygulama(_kap(), const SettingsScreen()));
          await _bekle(tester);
          await tester.tap(find.text(_tr.settingsAdvancedUpper));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
        for (final b in SettingsBolum.values) {
          testWidgets('${w.toInt()}pt ${b.name}', (tester) async {
            RemoteConfigService.testAcik = {_bayrak};
            await _boyut(tester, w);
            await tester.pumpWidget(_uygulama(_kap(), SettingsScreen(bolum: b)));
            await _bekle(tester);
            expect(tester.takeException(), isNull, reason: b.name);
          });
        }
      }

      testWidgets('320pt Görünüm, metin 1.6×', (tester) async {
        RemoteConfigService.testAcik = {_bayrak};
        await _boyut(tester, 320);
        await tester.pumpWidget(_uygulama(
            _kap(), const SettingsScreen(bolum: SettingsBolum.gorunum),
            metinOlcegi: 1.6));
        await _bekle(tester);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
