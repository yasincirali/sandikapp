import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/providers/premium_kullanim_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/profile_screen.dart'
    show premiumDurumMetni, premiumSayfasiniAc;
import 'package:portfoy_takip/services/abonelik_yonetimi.dart';
import 'package:portfoy_takip/utils/sandik_snack.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';

import 'helpers/kaynak.dart';

Widget _uygulama(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  testWidgets('5: sayfadan verilen şerit sayfanın üstünde görünür', (t) async {
    await t.pumpWidget(_uygulama(Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => showSandikSheet<void>(
            context: ctx,
            baslik: 'Sayfa',
            builder: (sheetCtx) => TextButton(
              onPressed: () => sandikSnack(sheetCtx, 'sonuc-seridi'),
              child: const Text('seritGoster'),
            ),
          ),
          child: const Text('ac'),
        ),
      ),
    )));
    await t.tap(find.text('ac'));
    await t.pumpAndSettle();
    await t.tap(find.text('seritGoster'));
    await t.pumpAndSettle();
    // Şerit modal rotanın İÇİNDE (sayfanın messenger'ında) çizilir; kök
    // Scaffold'a yazılsaydı karartmanın altında kalırdı.
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('sonuc-seridi')),
        findsOneWidget,
        reason: 'şerit sayfa/karartma altında kalmamalı');
  });

  group('hak yüzeyi', () {
    final bitis = DateTime.now().add(const Duration(days: 20));
    PremiumHakki hak({bool iptal = false}) => PremiumHakki(
        kaynak: 'revenuecat',
        bitis: bitis,
        urun: 'aylik',
        magaza: 'play_store',
        iptalEdildi: iptal);
    final temel = <Override>[
      abonelikDonemiProvider.overrideWith((_) async => null),
      premiumKullanimProvider.overrideWith((_) => const []),
      yillikTasarrufProvider.overrideWith((_) async => null),
    ];
    final hakProvider = StateProvider<PremiumHakki?>((_) => null);

    setUpAll(() => initializeDateFormatting('tr'));
    tearDown(() {
      AbonelikYonetimi.webAc =
          (uri) async => false; // gerçek launchUrl testte çağrılmaz
    });

    Future<void> sayfaAc(WidgetTester t, {PremiumHakki? ilk}) async {
      final container = ProviderContainer(overrides: [
        ...temel,
        gecerliPremiumHakkiProvider.overrideWith((ref) => ref.watch(hakProvider)),
      ]);
      addTearDown(container.dispose);
      container.read(hakProvider.notifier).state = ilk;
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _uygulama(Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
                onPressed: () => premiumSayfasiniAc(ctx),
                child: const Text('ac')),
          ),
        )),
      ));
      await t.tap(find.text('ac'));
      await t.pumpAndSettle();
    }

    testWidgets('2: premiumDurumMetni denemede ilk ödemeyi söyler', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_uygulama(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final simdi = DateTime.now();
      final normal = premiumDurumMetni(ctx, hak(), simdi);
      final deneme = premiumDurumMetni(ctx, hak(), simdi, deneme: true);
      expect(normal, contains('yenilenir'));
      expect(deneme, contains('ilk ödeme'));
      expect(deneme, isNot(contains('yenilenir')));
      // İptal edilmiş denemede ödeme olmayacak: "biter".
      final iptal = premiumDurumMetni(ctx, hak(iptal: true), simdi, deneme: true);
      expect(iptal, contains('biter'));
    });

    testWidgets('3: Yönet açılamazsa yol tarifi şeridi çıkar', (t) async {
      var cagri = 0;
      AbonelikYonetimi.webAc = (uri) async {
        cagri++;
        expect(uri.queryParameters['package'], 'com.sandik.app');
        return false;
      };
      await sayfaAc(t, ilk: hak());
      await t.tap(find.text('Yönet'));
      await t.pumpAndSettle();
      expect(cagri, 1);
      expect(find.textContaining('Play Store › Ödemeler ve abonelikler'),
          findsOneWidget);
    });

    testWidgets('3: Yönet açılırsa şerit yok', (t) async {
      AbonelikYonetimi.webAc = (uri) async => true;
      await sayfaAc(t, ilk: hak());
      await t.tap(find.text('Yönet'));
      await t.pumpAndSettle();
      expect(find.textContaining('açılamadı'), findsNothing);
    });

    testWidgets('4: açık sayfa hak değişince güncellenir', (t) async {
      await sayfaAc(t, ilk: hak());
      expect(find.text('Premium · aylık'), findsOneWidget);
      final container =
          ProviderScope.containerOf(t.element(find.byType(PremiumAbonelikSatiri)));
      container.read(hakProvider.notifier).state = PremiumHakki(
          kaynak: 'revenuecat',
          bitis: bitis,
          urun: 'yillik',
          magaza: 'play_store');
      await t.pumpAndSettle();
      expect(find.text('Premium · yıllık'), findsOneWidget);
      expect(find.text('Premium · aylık'), findsNothing);
    });

    testWidgets('6: iptal edilmiş abonede yeniden başlatma ipucu', (t) async {
      await sayfaAc(t, ilk: hak(iptal: true));
      expect(find.textContaining('yeniden başlatmak'), findsOneWidget);
      expect(find.textContaining('İptal ve plan değişikliği'), findsNothing);
    });

    testWidgets('6: aktif abonede eski ipucu kalır', (t) async {
      await sayfaAc(t, ilk: hak());
      expect(find.textContaining('İptal ve plan değişikliği'), findsOneWidget);
      expect(find.textContaining('yeniden başlatmak'), findsNothing);
    });
  });

  test('1: deneme bildirimi Premium sayfası isteğini yazar', () {
    final src =
        File('lib/services/notification_service.dart').readAsStringSync();
    final blok = src.substring(src.indexOf('payload == denemeHatirlatmaPayload'));
    expect(
        blok.substring(0, 400), contains('premiumSayfasiIstegi.value = true'));
    expect(ekranKaynagiSync('lib/screens/profile_screen.dart'),
        contains('premiumSayfasiIstegi.addListener'));
  });
}
