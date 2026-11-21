import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show paywallVisibleProvider;
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_acildi_sayfasi.dart';
import 'package:portfoy_takip/widgets/sinir_uyarisi.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType, PresentedOfferingContext, StoreProduct;

import 'helpers/kaynak.dart';

/// Ücretsiz sınır kapıları (Ar-Ge 21 Kas, UI/UX turu 5): satın alınca iş
/// sürer (`sinirUyarisi` true döner), vazgeçilince çıkış yolu metni kalır,
/// ortak sınırı aynı kuraldan geçer, takip kartı etiketi ve rengi.
Package _paket(String id) => Package(
      id,
      PackageType.annual,
      StoreProduct(id, '', '', 649.99, '649,99 ₺', 'TRY'),
      const PresentedOfferingContext('o', null, null),
    );

class _SahteServis implements SatinAlmaService {
  _SahteServis({this.teklifler = const [], this.sonuc});

  /// Sırayla dönen teklifler; bitince null.
  final List<MagazaTeklifi?> teklifler;
  final SatinAlmaSonucu? sonuc;
  int teklifCagri = 0;
  int satinAlCagri = 0;
  Completer<void>? bekle;

  @override
  bool get yapilandirildi => true;

  @override
  Future<MagazaTeklifi?> teklif() async {
    final i = teklifCagri++;
    return i < teklifler.length ? teklifler[i] : null;
  }

  @override
  Future<SatinAlmaSonucu> satinAl(Package paket) async {
    satinAlCagri++;
    return sonuc ?? SatinAlmaSonucu.hata;
  }

  @override
  Future<bool?> geriYukle() async {
    await bekle?.future;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}


void main() {
  bool? sonuc;

  Future<void> ac(WidgetTester t, _SahteServis s,
      Future<bool> Function(BuildContext, WidgetRef) kapi) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    sonuc = null;
    final kap = ProviderContainer(overrides: [
      satinAlmaServisiProvider.overrideWithValue(s),
      paywallVisibleProvider.overrideWithValue(true),
      premiumHaklariProvider
          .overrideWith((ref) async => const <PremiumHakki>[]),
    ]);
    addTearDown(kap.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: kap,
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  sonuc = await kapi(ctx, ref);
                },
                child: const Text('git'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('git'));
    await t.pumpAndSettle();
  }

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('satın alma: true döner, paywall kapanmış, snack yok',
      (t) async {
    final s = _SahteServis(
        teklifler: [MagazaTeklifi(yillik: _paket('y'))],
        sonuc: SatinAlmaSonucu.basarili);
    await ac(t, s, (c, r) => takipSiniriBekle(c, r, 5));
    await t.tap(find.textContaining('abone ol').first);
    await t.pumpAndSettle();
    await t.pump(premiumAcildiBekleme);
    await t.pumpAndSettle();
    expect(sonuc, isTrue);
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.textContaining('Yer açmak için'), findsNothing);
  }, variant: ios);

  testWidgets('vazgeçme: false döner, takip metni çıkış yolunu söyler',
      (t) async {
    await ac(t, _SahteServis(), (c, r) => takipSiniriBekle(c, r, 5));
    Navigator.of(t.element(find.byType(PaywallScreen))).pop();
    await t.pumpAndSettle();
    expect(sonuc, isFalse);
    expect(find.textContaining('Yer açmak için birini çıkar.'), findsOneWidget);
  }, variant: ios);

  testWidgets('alarm: vazgeçince "Yeni kurmak için birini kapat."',
      (t) async {
    await ac(t, _SahteServis(), (c, r) => alarmSiniriBekle(c, r, 20));
    Navigator.of(t.element(find.byType(PaywallScreen))).pop();
    await t.pumpAndSettle();
    expect(sonuc, isFalse);
    expect(find.textContaining('Yeni kurmak için birini kapat.'),
        findsOneWidget);
  }, variant: ios);

  testWidgets('ortak sınırı: vazgeçince ücretsiz plan metni söylenir',
      (t) async {
    await ac(t, _SahteServis(), (c, r) => ortakSiniriBekle(c, r, 1));
    Navigator.of(t.element(find.byType(PaywallScreen))).pop();
    await t.pumpAndSettle();
    expect(sonuc, isFalse);
    expect(find.textContaining('en fazla 1 ortak ekleyebilirsin'),
        findsOneWidget);
  }, variant: ios);

  test('takip: üç giriş satın alınca bir kez yeniden dener', () {
    for (final f in [
      'lib/widgets/takip_yildizi.dart',
      'lib/screens/add_watchlist_screen.dart',
      'lib/screens/watchlist_screen.dart',
    ]) {
      final k = ekranKaynagiSync(f);
      expect(k.contains('!tekrar &&'), isTrue, reason: f);
      expect(k.contains('takipSiniriBekle('), isTrue, reason: f);
    }
  });

  test('alarm ve ortak girişleri bekleyen kapıdan geçer', () {
    final alarm = ekranKaynagiSync('lib/widgets/alarm_kur_sheet.dart');
    expect(alarm.contains('!await alarmSiniriBekle('), isTrue);
    for (final f in [
      'lib/screens/profile_screen.dart',
      'lib/screens/partnership_requests_screen.dart',
    ]) {
      expect(ekranKaynagiSync(f).contains('await ortakEklenebilirMi('), isTrue,
          reason: f);
    }
    expect(
        ekranKaynagiSync('lib/screens/paywall_screen.dart')
            .contains('ortakSiniriPaywalliActi'),
        isFalse);
  });

  test('dolu takip kartı: paywall görünürken etiket Premium ipucu taşır, '
      'renk amber', () {
    final k = ekranKaynagiSync('lib/screens/watchlist_screen.dart');
    expect(k.contains('ref.watch(paywallVisibleProvider)'), isTrue);
    expect(k.contains('watchlistLimitPremiumIpucu'), isTrue);
    expect(k.contains('watchlistLimitReached(limit)'), isTrue,
        reason: 'paywall kapalıyken bugünkü metin');
    expect(k.contains('dolu ? c.amberText : c.text90'), isTrue);
    expect(k.contains('dolu ? c.loss'), isFalse);
    expect(k.contains('c.loss : c.amberFill'), isFalse);
  });
}
