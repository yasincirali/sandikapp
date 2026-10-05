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
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/grafik_tipi_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme listesi madde 5 ve 10'un kalanı (2026-10-04; bayrak
/// `performans_ayar_sade` 2026-10-05'te kalktı, davranış kalıcı — eski
/// düzenleri sınayan "bayrak kapalı" testleri de onunla gitti).
///
///   a) Grafik tipi seçicisi 5 → 2 (Çizgi, Mum); Alan/Taban/Çubuk enum'dan
///      silindi (seçim oturumluk, göç gerekmedi).
///   b) "Bugünkü portföyle" Performans kapsam panelinden Ayarlar ›
///      Görünüm'e; Performans aynı provider'ı okur, etkinken rozet.
///   c) Ayarlar gruplu başlıklar + katlanır "Gelişmiş"; hiçbir satır kaybolmaz.
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
    grafikTipiNotifier.value = GrafikTipi.varsayilan;
  });
  tearDown(() {
    grafikTipiNotifier.value = GrafikTipi.varsayilan;
  });

  group('a) grafik tipi — eşleme saf', () {
    test('yalnız Çizgi ve Mum; seçim olduğu gibi çizilir', () {
      expect(GrafikTipi.values, [GrafikTipi.line, GrafikTipi.candle]);
      for (final t in GrafikTipi.values) {
        expect(GrafikTipi.etkin(t), t, reason: t.name);
      }
    });

    test('grafik araçları gizliyse (sade Başlangıç) her zaman Çizgi', () {
      for (final t in GrafikTipi.values) {
        expect(GrafikTipi.etkin(t, araclar: false), GrafikTipi.line);
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

    testWidgets('menüde iki tip', (tester) async {
      await ac(tester);
      expect(find.byType(PopupMenuItem<GrafikTipi>), findsNWidgets(2));
      for (final ad in ['Alan', 'Taban', 'Çubuk']) {
        expect(find.text(ad), findsNothing, reason: ad);
      }
      expect(find.text('Mum'), findsOneWidget);
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

    testWidgets('panelde anahtar yok; Ayarlar tercihi rozet açar',
        (tester) async {
      await _boyut(tester, 375);
      final c = _kap();
      await tester.pumpWidget(_uygulama(c, const PortfolioPerformanceScreen()));
      await _bekle(tester);
      await donemSec(tester, '1 ay');
      await kapsamAc(tester);
      // Eski Gerçek|Bugünkü anahtarı (`modeReal` = "Gerçek") yok.
      expect(find.text('Gerçek'), findsNothing);
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

    for (final e in beklenen.entries) {
      testWidgets('${e.key.name} tam', (tester) async {
        await _boyut(tester, 1200, h: 4000);
        await tester.pumpWidget(_uygulama(_kap(), SettingsScreen(bolum: e.key)));
        await _bekle(tester);
        for (final t in e.value) {
          expect(find.text(t), findsAtLeastNWidgets(1),
              reason: '${e.key.name}: "$t" kayboldu');
        }
      });
    }

    testWidgets('bölümler net başlıklı', (tester) async {
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

    testWidgets('hub\'da teknik satırlar katlanır "Gelişmiş"te',
        (tester) async {
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

    group('dar ekranda taşma yok', () {
      for (final w in <double>[320, 360]) {
        testWidgets('${w.toInt()}pt hub (Gelişmiş açık)', (tester) async {
          await _boyut(tester, w, h: 1400);
          await tester.pumpWidget(_uygulama(_kap(), const SettingsScreen()));
          await _bekle(tester);
          await tester.tap(find.text(_tr.settingsAdvancedUpper));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
        for (final b in SettingsBolum.values) {
          testWidgets('${w.toInt()}pt ${b.name}', (tester) async {
            await _boyut(tester, w);
            await tester.pumpWidget(_uygulama(_kap(), SettingsScreen(bolum: b)));
            await _bekle(tester);
            expect(tester.takeException(), isNull, reason: b.name);
          });
        }
      }

      testWidgets('320pt Görünüm, metin 1.6×', (tester) async {
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
