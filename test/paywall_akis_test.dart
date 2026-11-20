import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show magazaPremiumProvider;
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';
import 'package:portfoy_takip/widgets/premium_acildi_sayfasi.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType, PresentedOfferingContext, StoreProduct;

/// Premium satın alma akışı (Ar-Ge 20 Kas, UI/UX turu 1): teklif yeniden
/// denemesi, başarı/geri yükleme ortak kapanışı, Aile onayı, geri yükle
/// göstergesi, büyük yazı ve erişilebilirlik.
Package _paket(String id) => Package(
      id,
      PackageType.annual,
      StoreProduct(id, '', '', 649.99, '649,99 ₺', 'TRY'),
      const PresentedOfferingContext('o', null, null),
    );

class _SahteServis implements SatinAlmaService {
  _SahteServis({this.teklifler = const [], this.sonuc, this.geriYuk});

  /// Sırayla dönen teklifler; bitince null.
  final List<MagazaTeklifi?> teklifler;
  final SatinAlmaSonucu? sonuc;
  final bool? geriYuk;
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
    return geriYuk;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late ProviderContainer kap;
  final donusler = <bool?>[];

  Future<void> ac(WidgetTester t, _SahteServis s,
      {double olcek = 1, bool hareketAz = false}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    donusler.clear();
    kap = ProviderContainer(overrides: [
      satinAlmaServisiProvider.overrideWithValue(s),
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
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(olcek),
              disableAnimations: hareketAz),
          child: child!,
        ),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    donusler.add(await PaywallScreen.show(ctx, source: 'test')),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
  }

  // Paywall yalnız iOS'ta açık (test build'inde Android anahtarı yok).
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  final cta = find.text('Yıllık abone ol');
  const kullanilamaz =
      'Satın alma şu an kullanılamıyor. Biraz sonra yeniden dene.';

  testWidgets('#1 teklif yoksa bir kez yeniden sorar, yine yoksa snack',
      (t) async {
    final s = _SahteServis();
    await ac(t, s);
    expect(s.teklifCagri, 1);
    await t.tap(cta);
    await t.pumpAndSettle();
    expect(s.teklifCagri, 2, reason: 'dokununca bir kez yeniden denenir');
    expect(s.satinAlCagri, 0, reason: 'paket yokken başarı uydurulmaz');
    expect(find.text(kullanilamaz), findsOneWidget);
    expect(find.byType(PaywallScreen), findsOneWidget);
  }, variant: ios);

  testWidgets('#1 yeniden deneme teklifi getirirse satın almaya geçer',
      (t) async {
    final s = _SahteServis(
        teklifler: [null, MagazaTeklifi(yillik: _paket('y'))],
        sonuc: SatinAlmaSonucu.vazgecti);
    await ac(t, s);
    await t.tap(cta);
    await t.pumpAndSettle();
    expect(s.satinAlCagri, 1);
    expect(find.text(kullanilamaz), findsNothing);
  }, variant: ios);

  for (final hareketAz in [false, true]) {
    testWidgets(
        '#2 başarı: sayfa kendiliğinden kapanır, paywall true '
        '(hareketi azalt: $hareketAz)', (t) async {
      final s = _SahteServis(
          teklifler: [MagazaTeklifi(yillik: _paket('y'))],
          sonuc: SatinAlmaSonucu.basarili);
      await ac(t, s, hareketAz: hareketAz);
      await t.tap(find.textContaining('abone ol').first);
      await t.pumpAndSettle();
      expect(find.byType(PremiumAcildiSayfasi), findsOneWidget);
      await t.pump(premiumAcildiBekleme);
      await t.pumpAndSettle();
      expect(find.byType(PremiumAcildiSayfasi), findsNothing);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(donusler, [true]);
    }, variant: ios);
  }

  testWidgets('#2 geri yükleme de aynı yol: sayfa, sonra true', (t) async {
    final s = _SahteServis(geriYuk: true);
    await ac(t, s);
    await t.tap(find.text('Satın alımı geri yükle'));
    await t.pumpAndSettle();
    expect(find.byType(PremiumAcildiSayfasi), findsOneWidget);
    expect(find.text('Aboneliğin geri yüklendi.'), findsNothing,
        reason: 'başarıyı sayfa söyler, şerit tekrar etmez');
    await t.pump(premiumAcildiBekleme);
    await t.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(donusler, [true]);
  }, variant: ios);

  testWidgets('#2 sayfaya dokunulursa kendiliğinden kapanmaz', (t) async {
    final s = _SahteServis(geriYuk: true);
    await ac(t, s);
    await t.tap(find.text('Satın alımı geri yükle'));
    await t.pumpAndSettle();
    await t.tap(find.byType(PremiumAcildiSayfasi), warnIfMissed: false);
    await t.pump(premiumAcildiBekleme * 2);
    await t.pumpAndSettle();
    expect(find.byType(PremiumAcildiSayfasi), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('premium_acildi_don')));
    await t.pumpAndSettle();
    expect(donusler, [true]);
  }, variant: ios);

  testWidgets('#3 Aile onayı: snack, paywall false ile kapanır', (t) async {
    final s = _SahteServis(
        teklifler: [MagazaTeklifi(yillik: _paket('y'))],
        sonuc: SatinAlmaSonucu.beklemede);
    await ac(t, s);
    await t.tap(find.textContaining('abone ol').first);
    await t.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(donusler, [false]);
    expect(find.textContaining('onay bekliyor'), findsOneWidget);
  }, variant: ios);

  testWidgets('#3 hak sonradan gelince açık paywall kendini kapatır',
      (t) async {
    await ac(t, _SahteServis());
    expect(find.byType(PaywallScreen), findsOneWidget);
    kap.read(magazaPremiumProvider.notifier).state = true;
    await t.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(donusler, [true]);
  }, variant: ios);

  testWidgets('#4 geri yükle meşgulken gösterge; bulunamadı yön verir',
      (t) async {
    final s = _SahteServis(geriYuk: false)..bekle = Completer<void>();
    await ac(t, s);
    await t.tap(find.text('Satın alımı geri yükle'));
    await t.pump();
    expect(find.byType(CustomLoadingIndicator), findsWidgets);
    s.bekle!.complete();
    await t.pumpAndSettle();
    expect(
        find.text('Bu hesapta etkin bir abonelik bulunamadı. Aynı mağaza '
            'hesabıyla giriş yaptığından emin ol.'),
        findsOneWidget);
    expect(find.byType(PaywallScreen), findsOneWidget);
  }, variant: ios);

  testWidgets('#5 3.1× yazıda taşma yok, etiketler görünür', (t) async {
    await ac(t, _SahteServis(), olcek: 3.1);
    expect(t.takeException(), isNull);
    expect(find.text('Satın alımı geri yükle'), findsOneWidget);
    expect(cta, findsOneWidget);
  }, variant: ios);

  testWidgets('#6 meşgul CTA "Yükleniyor" der; kapat ipucu "Kapat"', (t) async {
    final s = _SahteServis(geriYuk: false)..bekle = Completer<void>();
    await ac(t, s);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    final h = t.ensureSemantics();
    await t.tap(find.text('Satın alımı geri yükle'));
    await t.pump();
    expect(find.bySemanticsLabel(RegExp('Yıllık abone ol')), findsOneWidget);
    expect(
        t.getSemantics(find.bySemanticsLabel(RegExp('Yıllık abone ol'))).value,
        'Yükleniyor');
    s.bekle!.complete();
    await t.pumpAndSettle();
    h.dispose();
  }, variant: ios);
}
