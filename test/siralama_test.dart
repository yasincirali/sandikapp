import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/leaderboard_screen.dart';
import 'package:portfoy_takip/screens/siralama_screen.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/leaderboard_hero_card.dart';
import 'package:portfoy_takip/widgets/zirve_donem_secici.dart';
import 'package:portfoy_takip/widgets/zirve_riza_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Yarış + Zirve tek "Sıralama" sayfası (sadeleştirme madde 8, 2026-10-04;
/// bayrak `siralama_tek_sayfa` 2026-10-05'te kalktı — eski iki ekran ve
/// onları sınayan "bayrak KAPALI" testleri silindi).
///
/// Kilitlenenler:
///   · Yarış girişleri Sıralama › Ortaklarım, Zirve kartı Sıralama › Herkes
///     açar — kartın dönemiyle;
///   · rıza akışları atlanmaz: Ortaklarım'da yarış katılım daveti, Herkes'te
///     zirve açık rıza kartı (0091) aynen görünür;
///   · dönem iki sekmede ortak ve seçici AYNI bileşen;
///   · 320pt'de taşma yok.

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Çok Uzun Bir Kullanıcı Adı Soyadı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

Future<void> _pump(WidgetTester tester, Widget home,
    {double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 860 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(splashFactory: InkRipple.splashFactory),
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Sonsuz yükleme animasyonları yüzünden `pumpAndSettle` bitmez; geçiş
/// için birkaç kare yeter.
Future<void> _gecis(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _optIn(bool acik) async {
  SharedPreferences.setMockInitialValues(
      acik ? {'pref_leaderboard_opt_in': true} : {});
  await initPreferencesCache();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  test('Yarış dönemleri Zirve dönemleriyle birebir (7 · 30 · 365)', () {
    // Sıralama sayfası iki sekmede dönemi İNDEKSLE taşır.
    expect(yarisDonemGunleri, [for (final d in ZirveDonem.values) d.gun]);
  });

  group('giriş kararı tek yerde', () {
    test('Sıralama, uygun sekme ve dönem', () {
      final y = yarisGirisEkrani();
      expect(y, isA<SiralamaScreen>());
      expect((y as SiralamaScreen).sekme, SiralamaSekmesi.ortaklarim);
      final z = zirveGirisEkrani(ZirveDonem.yil);
      expect(z, isA<SiralamaScreen>());
      expect((z as SiralamaScreen).sekme, SiralamaSekmesi.herkes);
      expect(z.donem, ZirveDonem.yil);
    });

    test('üç giriş noktası kararı yardımcıdan okur', () {
      // Performans kupası, Zirve kartı (Performans), Profil kartı.
      final perf =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(perf.contains('yarisGirisEkrani()'), isTrue);
      expect(perf.contains('const LeaderboardScreen()'), isFalse);
      expect(perf.contains('zirveGirisEkrani(ZirveDonem.yakin('), isTrue);
      expect(perf.contains('ZirvePortfoylerScreen('), isFalse);
      final kart = ekranKaynagiSync('lib/widgets/leaderboard_hero_card.dart');
      expect('yarisGirisEkrani()'.allMatches(kart).length, 2);
      expect(kart.contains('const LeaderboardScreen()'), isFalse);
    });
  });

  group('Profil kartından giriş', () {
    testWidgets('Sıralama › Ortaklarım açılır', (tester) async {
      await _optIn(true);
      await _pump(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: LeaderboardHeroCard())));
      // `pushGuarded` çift dokunma penceresi GERÇEK saatle (500 ms):
      // önceki testin itişi bu testi yutmasın.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tap(find.byType(LeaderboardHeroCard));
      await _gecis(tester);
      expect(find.byType(SiralamaScreen), findsOneWidget);
      expect(find.text('Sıralama'), findsOneWidget);
      expect(find.byType(YarisGovdesi), findsOneWidget,
          reason: 'Ortaklarım sekmesiyle açılmalı');
      expect(tester.takeException(), isNull);
    });
  });

  group('Sıralama sayfası', () {
    testWidgets('rıza yokken iki sekmede de eski rıza akışı', (tester) async {
      await _optIn(false);
      await _pump(
          tester, SiralamaScreen(zirveRizaYukleyici: () async => false));
      // Ortaklarım: yarış katılım daveti (opt-in kapalı) — sıralama YOK.
      expect(find.text("Yarış'a katılmadın"), findsOneWidget);
      expect(find.text("Yarış'a katıl"), findsOneWidget);
      expect(find.byType(ZirveDonemSecici), findsNothing);
      // Herkes: zirve açık rıza kartı — liste YOK.
      await tester.tap(find.text('Zirvedekiler'));
      await _gecis(tester);
      expect(find.byType(ZirveRizaKarti), findsOneWidget);
      expect(find.byType(ZirveDonemSecici), findsNothing);
      expect(find.text("Yarış'a katılmadın"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zirve kartından: Herkes sekmesi, kartın dönemi',
        (tester) async {
      await _optIn(true);
      await _pump(
          tester,
          SiralamaScreen(
            sekme: SiralamaSekmesi.herkes,
            donem: ZirveDonem.hafta,
            zirveRizaYukleyici: () async => true,
          ));
      await _gecis(tester);
      expect(find.byType(ZirveGovdesi), findsOneWidget);
      expect(find.byType(YarisGovdesi), findsNothing);
      expect(
          tester.widget<ZirveDonemSecici>(find.byType(ZirveDonemSecici)).secili,
          ZirveDonem.hafta);
    });

    testWidgets('dönem iki sekmede ortak, seçici aynı bileşen', (tester) async {
      await _optIn(true);
      await _pump(tester, SiralamaScreen(zirveRizaYukleyici: () async => true));
      // Ortaklarım (opt-in açık): seçici Zirve'ninkiyle aynı bileşen.
      expect(find.byType(ZirveDonemSecici), findsOneWidget);
      expect(find.text('30G'), findsNothing,
          reason: 'sekmeli hâlde eski 7G/30G etiketleri yok');
      await tester.tap(find.text('1Y'));
      await _gecis(tester);
      expect(
          tester.widget<ZirveDonemSecici>(find.byType(ZirveDonemSecici)).secili,
          ZirveDonem.yil);
      // Herkes'e geç: dönem korunur.
      await tester.tap(find.text('Zirvedekiler'));
      await _gecis(tester);
      expect(find.byType(ZirveGovdesi), findsOneWidget);
      expect(
          tester.widget<ZirveDonemSecici>(find.byType(ZirveDonemSecici)).secili,
          ZirveDonem.yil);
      // Geri dön: yine korunur.
      await tester.tap(find.text('Ortaklarım'));
      await _gecis(tester);
      expect(
          tester.widget<ZirveDonemSecici>(find.byType(ZirveDonemSecici)).secili,
          ZirveDonem.yil);
      expect(tester.takeException(), isNull);
    });

    // Dönem artık kabukta: gövde `didUpdateWidget` ile listeyi, havuzu ve
    // "Sen"i o dönemle yeniden ister (eskiden `_donemSec` içindeydi).
    // Gövdeyi yalnız Sıralama kabuğu çizer (eski Zirve ekranı 2026-10-05'te
    // silindi).
    testWidgets('Herkes içinde dönem değişimi gövdeyi yeniler', (tester) async {
      await _optIn(true);
      await _pump(
          tester,
          SiralamaScreen(
              sekme: SiralamaSekmesi.herkes,
              zirveRizaYukleyici: () async => true));
      await _gecis(tester);
      await tester.tap(find.text('1H'));
      await _gecis(tester);
      expect(tester.takeException(), isNull);
      expect(
          tester.widget<ZirveDonemSecici>(find.byType(ZirveDonemSecici)).secili,
          ZirveDonem.hafta);
    });

    testWidgets('Yarış eylemleri yalnız Ortaklarım sekmesinde', (tester) async {
      await _optIn(true);
      await _pump(tester, SiralamaScreen(zirveRizaYukleyici: () async => true));
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget,
          reason: 'yarıştan ayrılma menüsü');
      await tester.tap(find.text('Zirvedekiler'));
      await _gecis(tester);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    for (final w in <double>[320, 390]) {
      for (final optIn in [false, true]) {
        testWidgets(
            '${w.toInt()}pt, opt-in ${optIn ? 'açık' : 'kapalı'}: '
            'taşma yok', (tester) async {
          await _optIn(optIn);
          await _pump(
              tester,
              SiralamaScreen(
                  zirveRizaYukleyici: () async => optIn ? true : false),
              width: w);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Zirvedekiler'));
          await _gecis(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
