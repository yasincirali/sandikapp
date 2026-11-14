import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Denemede abonelik satırı (Ar-Ge 12 Kas #2): "Yenileme 19 Kasım" ilk
/// ödemeyi saklıyordu. Denemede "Ücretsiz deneme · ilk ödeme …" yazar; tutar
/// yalnız mağazanın priceString'iyle güvenilir biçimde biliniyorsa.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  final bitis = DateTime(2026, 11, 19, 12);

  PremiumHakki hak({String magaza = 'app_store', bool iptal = false}) =>
      PremiumHakki(
        kaynak: 'revenuecat',
        bitis: bitis,
        urun: 'sandik_premium_yillik',
        magaza: magaza,
        iptalEdildi: iptal,
      );

  Future<void> kur(WidgetTester t, PremiumHakki h, AbonelikDonemi? d) =>
      t.pumpWidget(ProviderScope(
        overrides: [
          abonelikDonemiProvider.overrideWith((_) async => d),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PremiumAbonelikSatiri(hak: h)),
        ),
      ));

  group('abonelik satırı metni', () {
    testWidgets('ücretli dönem: yenileme', (t) async {
      await kur(t, hak(), const AbonelikDonemi(deneme: false));
      await t.pump();
      expect(find.text('Yenileme 19 Kasım 2026 · App Store'), findsOneWidget);
    });

    testWidgets('mağaza bilgisi yoksa eski metin', (t) async {
      await kur(t, hak(), null);
      await t.pump();
      expect(find.text('Yenileme 19 Kasım 2026 · App Store'), findsOneWidget);
    });

    testWidgets('deneme, tutar bilinmiyor: tutarsız', (t) async {
      await kur(t, hak(), const AbonelikDonemi(deneme: true));
      await t.pump();
      expect(find.text('Ücretsiz deneme · ilk ödeme 19 Kasım 2026 · App Store'),
          findsOneWidget);
      expect(find.textContaining('Yenileme'), findsNothing);
    });

    testWidgets('deneme, tutar biliniyor: tutar eklenir (Play)', (t) async {
      await kur(t, hak(magaza: 'play_store'),
          const AbonelikDonemi(deneme: true, ilkOdemeTutari: '₺649,99'));
      await t.pump();
      expect(
          find.text(
              'Ücretsiz deneme · ilk ödeme 19 Kasım 2026, ₺649,99 · Google Play'),
          findsOneWidget);
    });

    testWidgets('iptal edilmiş deneme: ödeme yok, "biter" der', (t) async {
      await kur(t, hak(iptal: true), const AbonelikDonemi(deneme: true));
      await t.pump();
      expect(find.text('19 Kasım 2026 tarihinde biter'), findsOneWidget);
      expect(find.textContaining('ilk ödeme'), findsNothing);
    });
  });

  group('abonelikDonemi (saf)', () {
    EntitlementInfo hakBilgisi(PeriodType p, {String? plan}) => EntitlementInfo(
          'premium',
          true,
          true,
          '2026-11-12T00:00:00Z',
          '2026-11-12T00:00:00Z',
          'sandik_yillik',
          false,
          periodType: p,
          productPlanIdentifier: plan,
        );
    StoreProduct urun(String id, String fiyat, {IntroductoryPrice? intro}) =>
        StoreProduct(id, '', '', 649.99, fiyat, 'TRY',
            introductoryPrice: intro);
    const ucretsizIntro =
        IntroductoryPrice(0, '₺0', 'P1W', 1, PeriodUnit.week, 1);
    const ucretliIntro =
        IntroductoryPrice(99, '₺99', 'P1M', 1, PeriodUnit.month, 1);

    test('normal dönem: deneme değil, tutar yok', () {
      final d = abonelikDonemi(hakBilgisi(PeriodType.normal),
          [urun('sandik_yillik', '₺649,99')]);
      expect(d.deneme, isFalse);
      expect(d.ilkOdemeTutari, isNull);
    });

    test('iOS: kimlik eşleşirse tutar', () {
      final d = abonelikDonemi(hakBilgisi(PeriodType.trial), [
        urun('sandik_aylik', '₺79,99'),
        urun('sandik_yillik', '₺649,99', intro: ucretsizIntro),
      ]);
      expect(d.deneme, isTrue);
      expect(d.ilkOdemeTutari, '₺649,99');
    });

    test('Play: abonelik:temel_plan eşleşmesi', () {
      final d = abonelikDonemi(hakBilgisi(PeriodType.trial, plan: 'yillik'),
          [urun('sandik_yillik:yillik', '₺649,99')]);
      expect(d.ilkOdemeTutari, '₺649,99');
    });

    test('ürün teklifte yoksa tutar uydurulmaz', () {
      final d = abonelikDonemi(
          hakBilgisi(PeriodType.trial), [urun('baska', '₺1'), null]);
      expect(d.deneme, isTrue);
      expect(d.ilkOdemeTutari, isNull);
    });

    test('denemenin bitişi ve yenilenmesi mağazadan okunur (hatırlatma)', () {
      const iptal = EntitlementInfo('premium', true, false,
          '2026-11-12T00:00:00Z', '2026-11-12T00:00:00Z', 'sandik_yillik', false,
          periodType: PeriodType.trial, expirationDate: '2026-11-19T00:00:00Z');
      final d = abonelikDonemi(iptal, const []);
      expect(d.bitis, DateTime.utc(2026, 11, 19));
      expect(d.yenilenecek, isFalse);
      final y = abonelikDonemi(hakBilgisi(PeriodType.trial), const []);
      expect(y.yenilenecek, isTrue);
    });

    test('ücretli giriş fazı varsa ilk ödeme liste fiyatı değil: tutar yok',
        () {
      final d = abonelikDonemi(hakBilgisi(PeriodType.trial),
          [urun('sandik_yillik', '₺649,99', intro: ucretliIntro)]);
      expect(d.ilkOdemeTutari, isNull);
    });
  });
}
