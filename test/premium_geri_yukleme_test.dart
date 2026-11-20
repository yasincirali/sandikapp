import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';
import 'package:portfoy_takip/widgets/premium_acildi_sayfasi.dart'
    show premiumAcildiBekleme;
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

/// "Satın alımları geri yükle" tek akış (Ar-Ge 12 Kas #1): Profil › Premium
/// sayfasındaki düğme önce mağazaya hiç sormuyor, hiçbir şey söylemiyordu.
/// Artık paywall ile aynı `satinAlimlariGeriYukle`'yi çağırır.
class _SahteServis implements SatinAlmaService {
  _SahteServis(this.sonuc, {this.hazir = true});

  final bool? sonuc;
  final bool hazir;
  int cagri = 0;
  Completer<void>? bekle;

  @override
  bool get yapilandirildi => hazir;

  @override
  Future<bool?> geriYukle() async {
    cagri++;
    await bekle?.future;
    return sonuc;
  }

  @override
  Future<MagazaTeklifi?> teklif() async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late int hakOkuma;

  List<Override> ortak(_SahteServis s) => [
        satinAlmaServisiProvider.overrideWithValue(s),
        premiumHaklariProvider.overrideWith((ref) async {
          hakOkuma++;
          return const <PremiumHakki>[];
        }),
      ];

  setUp(() => hakOkuma = 0);

  Widget uygulama(_SahteServis s, Widget home) => ProviderScope(
        overrides: ortak(s),
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  Widget satir(_SahteServis s) => uygulama(
        s,
        Consumer(builder: (_, ref, __) {
          // Sağlayıcı dinlensin ki invalidate yeniden okumayı tetiklesin.
          ref.watch(premiumHaklariProvider);
          return const Scaffold(
              body: SingleChildScrollView(
                  child: PremiumAbonelikSatiri(hak: null)));
        }),
      );

  group('Profil › Premium satırı', () {
    for (final (sonuc, metin) in [
      (true, 'Aboneliğin geri yüklendi.'),
      (
        false,
        'Bu hesapta etkin bir abonelik bulunamadı. Aynı mağaza hesabıyla '
            'giriş yaptığından emin ol.'
      ),
      (null, 'Geri yükleme şu an yapılamadı. Biraz sonra yeniden dene.'),
    ]) {
      testWidgets('mağazaya sorar, sonucu söyler: $sonuc', (t) async {
        final s = _SahteServis(sonuc);
        await t.pumpWidget(satir(s));
        await t.pump();
        final ilkOkuma = hakOkuma;
        await t.tap(find.text('Satın alımları geri yükle'));
        await t.pumpAndSettle();
        expect(s.cagri, 1, reason: 'restorePurchases mağazaya gitmeli');
        expect(find.text(metin), findsOneWidget);
        expect(hakOkuma, greaterThan(ilkOkuma),
            reason: 'ardından sunucu hakları tazelenir');
      });
    }

    testWidgets('düğme SandikAsyncButton: iş sürerken ikinci dokunuş yutulur',
        (t) async {
      final s = _SahteServis(true)..bekle = Completer<void>();
      await t.pumpWidget(satir(s));
      expect(
          find.ancestor(
              of: find.text('Satın alımları geri yükle'),
              matching: find.byType(SandikAsyncButton)),
          findsOneWidget);
      await t.tap(find.text('Satın alımları geri yükle'));
      await t.pump();
      expect(find.byType(CustomLoadingIndicator), findsOneWidget,
          reason: 'etiket yerinde yükleniyor göstergesi');
      await t.tap(find.byType(SandikAsyncButton), warnIfMissed: false);
      s.bekle!.complete();
      await t.pumpAndSettle();
      expect(s.cagri, 1);
    });

    testWidgets('mağaza yapılandırılmamışsa sormaz, "kullanılamıyor" der',
        (t) async {
      final s = _SahteServis(true, hazir: false);
      await t.pumpWidget(satir(s));
      await t.pump();
      final ilkOkuma = hakOkuma;
      await t.tap(find.text('Satın alımları geri yükle'));
      await t.pumpAndSettle();
      expect(s.cagri, 0);
      expect(
          find.text(
              'Satın alma şu an kullanılamıyor. Biraz sonra yeniden dene.'),
          findsOneWidget);
      expect(hakOkuma, greaterThan(ilkOkuma),
          reason: 'eski davranış: sunucu hakları yine tazelenir');
    });
  });

  group('Paywall akışı değişmedi', () {
    // Paywall yalnız iOS'ta açık (test build'inde Android anahtarı yok).
    Future<bool?> ac(WidgetTester t, _SahteServis s) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      bool? donus;
      await t.pumpWidget(uygulama(
        s,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    donus = await PaywallScreen.show(ctx, source: 'test'),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.text('Satın alımı geri yükle').first);
      await t.pumpAndSettle();
      return donus;
    }

    // Ar-Ge 20 Kas #2: geri yükleme satın almayla aynı yolu izler —
    // "Premium açıldı" sayfası kısa görünür, paywall true ile kapanır;
    // başarı şeridi tekrar etmez (ayrıntı `paywall_akis_test`).
    testWidgets('bulundu: Premium açıldı sayfası, paywall kapanır', (t) async {
      final s = _SahteServis(true);
      await ac(t, s);
      expect(s.cagri, 1);
      expect(find.text('Aboneliğin geri yüklendi.'), findsNothing);
      await t.pump(premiumAcildiBekleme);
      await t.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      expect(find.byType(PaywallScreen), findsNothing);
    });

    testWidgets('bulunamadı: snack, paywall açık kalır', (t) async {
      final s = _SahteServis(false);
      await ac(t, s);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining('Bu hesapta etkin bir abonelik bulunamadı.'),
          findsOneWidget);
      expect(find.byType(PaywallScreen), findsOneWidget);
    });
  });
}
