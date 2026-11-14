// Profil yeniden tasarımı (yasin 7 Kas, Ar-Ge): "ad ⌄" + yüzen cam hesap
// menüsü, tek satır Premium durumu, tek satır kilometre taşı.
//
// Kilitlenenler:
// 1. Ok yalnız iki ve daha fazla hesapta; tek hesapta ad düz metin ve
//    "Hesap ekle" Ayarlar'da satır.
// 2. Menü adın altından açılır; cam (BackdropFilter) yalnız menüde ve yalnız
//    iOS'ta, hareketi azalt açıkken ve Android'de katı zemin.
// 3. Premium: hak bilgisiyle durum metni, yoksa "Premium"; ücretsizde
//    "Premium'a geç"; kilit askıdayken satır yok. Yönet/geri yükle satıra
//    dokununca açılan sayfada (abonelik yönetimi kaybolmaz).
// 4. Dynamic Type 3.1× / 320 pt taşma yok; dokunma alanları ≥ 44 pt.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/halka_arz_provider.dart';
import 'package:portfoy_takip/providers/hesap_provider.dart';
import 'package:portfoy_takip/providers/kilometre_tasi_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/hesap_kasasi.dart';
import 'package:portfoy_takip/services/milestone_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hesap_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _ben = AppUser(
  id: 'u1',
  email: 'demo@example.com',
  displayName: 'demo_yatirimci',
  username: 'demo_yatirimci',
  createdAt: DateTime(2026, 1, 1),
);

KayitliHesap _h(String uid, String ad) => KayitliHesap(
    uid: uid,
    eposta: '$uid@example.com',
    ad: ad,
    sonKullanim: DateTime.now().subtract(const Duration(days: 1)));

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _ben;
}

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState(
      assets: <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _Ortak extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _OrtakVarlik extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Sinyal extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

final _taslar = MilestoneService.koleksiyon(kayitli: {
  for (final e in MilestoneService.valueThresholds.take(8))
    'portfolio_value:${e.toStringAsFixed(0)}',
  'portfolio_age:5y',
}, bugun: const [], totalTRY: 2700000);

Future<void> _profil(
  WidgetTester tester, {
  List<KayitliHesap>? hesaplar,
  bool premium = true,
  bool kilitli = true,
  PremiumHakki? hak,
  double olcek = 1,
  double genislik = 390,
  bool azalt = false,
}) async {
  tester.view.physicalSize = Size(genislik * 2, 844 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      halkaArzEtkinProvider.overrideWithValue(false),
      authProvider.overrideWith(_Auth.new),
      portfolioProvider.overrideWith(_Portfoy.new),
      partnersProvider.overrideWith(_Ortak.new),
      allPartnerAssetsProvider.overrideWith(_OrtakVarlik.new),
      signalProvider.overrideWith(_Sinyal.new),
      isPushAdminProvider.overrideWith((_) async => false),
      cokluHesapGorunurProvider.overrideWithValue(true),
      kayitliHesaplarProvider
          .overrideWithValue(hesaplar ?? [_h('u1', 'demo_yatirimci')]),
      paywallVisibleProvider.overrideWithValue(true),
      effectivePremiumProvider.overrideWithValue(premium),
      premiumKilitliProvider.overrideWithValue(kilitli),
      gecerliPremiumHakkiProvider.overrideWithValue(hak),
      premiumBitmisProvider.overrideWithValue(null),
      kilometreTaslariProvider.overrideWithValue(_taslar),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(olcek), disableAnimations: azalt),
        child: child!,
      ),
      home: const Material(
          type: MaterialType.transparency, child: ProfileScreen()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _menuyuAc(WidgetTester tester) async {
  await tester.tap(find.byType(HesapBasligi));
  await tester.pump();
  await tester.pump(SandikMotion.surface);
  await tester.pump();
}

final _ok = find.descendant(
    of: find.byType(HesapBasligi),
    matching: find.byIcon(Icons.keyboard_arrow_down_rounded));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  group('hesap: "ad ⌄"', () {
    testWidgets('tek hesapta ok yok, ad düz metin; Hesap ekle Ayarlar\'da',
        (tester) async {
      await _profil(tester);
      expect(find.text('demo_yatirimci'), findsOneWidget);
      expect(_ok, findsNothing);
      expect(find.text('Hesap'), findsNothing, reason: 'eski "Hesap ⌄" kalktı');
      await tester.tap(find.text('demo_yatirimci'));
      await tester.pump(SandikMotion.surface);
      expect(find.byType(HesapMenusu), findsNothing);
      await tester.scrollUntilVisible(find.text('Hesap ekle'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Hesap ekle'), findsOneWidget);
    });

    testWidgets('iki hesapta ok çıkar, menü adın altından açılır',
        (tester) async {
      final sem = tester.ensureSemantics();
      await _profil(tester,
          hesaplar: [_h('u1', 'demo_yatirimci'), _h('u2', 'aile_hesabi')]);
      expect(_ok, findsOneWidget);
      // Menüdeyken Ayarlar satırı yok (ekleme menüde).
      expect(find.text('Hesap ekle'), findsNothing);
      expect(
          find.bySemanticsLabel('Hesap değiştir, şu an demo_yatirimci'),
          findsOneWidget);
      final ad = tester.getRect(find.byType(HesapBasligi));

      await _menuyuAc(tester);
      expect(find.byType(HesapMenusu), findsOneWidget);
      expect(find.text('Bu cihazda açık'), findsOneWidget);
      expect(find.text('aile_hesabi'), findsOneWidget);
      expect(find.text('Hesap ekle'), findsOneWidget);
      expect(find.text('Hesapları düzenle'), findsOneWidget);
      // Alt sayfa değil, düğmenin altında yüzen menü.
      final menu = tester.getRect(find.descendant(
          of: find.byType(HesapMenusu), matching: find.byType(SizedBox)).first);
      expect(menu.top, greaterThanOrEqualTo(ad.bottom));

      // Dokunma alanları ≥ 44 pt.
      for (final e in find
          .descendant(
              of: find.byType(HesapMenusu),
              matching: find.byType(SandikTappable))
          .evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).height,
            greaterThanOrEqualTo(SandikTouch.min));
      }

      // Perdeye dokununca kapanır.
      await tester.tapAt(const Offset(10, 830));
      await tester.pumpAndSettle();
      expect(find.byType(HesapMenusu), findsNothing);
      sem.dispose();
    });

    testWidgets('"Hesapları düzenle" bugünkü sayfayı açar', (tester) async {
      await _profil(tester,
          hesaplar: [_h('u1', 'demo_yatirimci'), _h('u2', 'aile_hesabi')]);
      await _menuyuAc(tester);
      await tester.tap(find.text('Hesapları düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(HesapMenusu), findsNothing);
      expect(find.byType(HesapSeciciSayfasi), findsOneWidget);
      expect(find.text('Düzenle'), findsOneWidget);
    });

    testWidgets('cam yalnız menüde ve yalnız iOS\'ta; hareketi azalt katı',
        (tester) async {
      final iki = [_h('u1', 'demo_yatirimci'), _h('u2', 'aile_hesabi')];
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _profil(tester, hesaplar: iki);
        expect(find.byType(BackdropFilter), findsNothing,
            reason: 'menü kapalıyken Profil\'de cam yok');
        await _menuyuAc(tester);
        expect(
            find.descendant(
                of: find.byType(HesapMenusu),
                matching: find.byType(BackdropFilter)),
            findsOneWidget);

        await _profil(tester, hesaplar: iki, azalt: true);
        await _menuyuAc(tester);
        expect(find.byType(HesapMenusu), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      await _profil(tester, hesaplar: iki);
      await _menuyuAc(tester);
      expect(find.byType(HesapMenusu), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing,
          reason: 'Android: opak');
    });
  });

  group('Premium satırı', () {
    testWidgets('hak bilgisi yoksa yalnız "Premium"; eski kart yok',
        (tester) async {
      await _profil(tester);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Premium aktif'), findsNothing);
      expect(find.text("Premium'a geç"), findsNothing);
      // Hak bilgisi yokken de dokunulur ve "Yönet" açılır (yasin 10 Kas:
      // iptalin uygulamadaki yolu her Premium kullanıcıda olmalı).
      await tester.tap(find.text('Premium'));
      await tester.pumpAndSettle();
      expect(find.text('Yönet'), findsOneWidget);
      expect(find.text('Satın alımları geri yükle'), findsOneWidget);
      expect(
          find.text(
              'İptal ve plan değişikliği mağazanın abonelik sayfasında yapılır.'),
          findsOneWidget);
    });

    testWidgets('abonelikte tür ve yenileme; dokununca yönetim sayfası',
        (tester) async {
      final sem = tester.ensureSemantics();
      await _profil(tester,
          hak: PremiumHakki(
              kaynak: 'revenuecat',
              bitis: DateTime(2027, 11, 5, 12),
              urun: 'sandik_premium_yillik',
              magaza: 'app_store'));
      const metin = 'Premium · yıllık, 5 Kasım 2027 tarihinde yenilenir';
      expect(find.text(metin), findsOneWidget);
      final satir = find.bySemanticsLabel(RegExp('^${RegExp.escape(metin)}'));
      expect(satir, findsOneWidget);
      expect(tester.getSize(satir).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(find.text(metin));
      await tester.pumpAndSettle();
      expect(find.text('Satın alımları geri yükle'), findsOneWidget);
      expect(find.text('Yönet'), findsOneWidget);
      sem.dispose();
    });

    testWidgets("ücretsizde \"Premium'a geç\"; kilit askıdaysa satır yok",
        (tester) async {
      final sem = tester.ensureSemantics();
      await _profil(tester, premium: false);
      final gec = find.bySemanticsLabel("Premium'a geç");
      expect(gec, findsOneWidget);
      expect(tester.getSize(gec).height, greaterThanOrEqualTo(SandikTouch.min));

      await _profil(tester, premium: false, kilitli: false);
      expect(find.text("Premium'a geç"), findsNothing);
      expect(find.text('Premium'), findsNothing);
      sem.dispose();
    });
  });

  testWidgets('kilometre taşı tek satır Profil\'de', (tester) async {
    await _profil(tester);
    expect(find.text('Sıradaki: 5 milyon ₺'), findsOneWidget);
    expect(find.text('8 / 10'), findsOneWidget);
    expect(find.text('2,3 milyon ₺ kaldı'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('kilometreTasiSatiri')))
            .height,
        greaterThanOrEqualTo(SandikTouch.min));
  });

  testWidgets('Dynamic Type 3.1× ve 320 pt: taşma yok (menü dahil)',
      (tester) async {
    await _profil(tester,
        hesaplar: [_h('u1', 'demo_yatirimci'), _h('u2', 'aile_hesabi')],
        olcek: 3.1,
        genislik: 320,
        hak: PremiumHakki(
            kaynak: 'revenuecat',
            bitis: DateTime(2027, 11, 5, 12),
            urun: 'yillik'));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HesapBasligi)).height,
        greaterThanOrEqualTo(SandikTouch.min));
    await _menuyuAc(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(HesapMenusu), findsOneWidget);
  });
}
