import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/premium_kullanim_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/satin_alma_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/premium_abonelik_satiri.dart';

/// Aylık abonede "Yıllığa geçersen yılda ₺X az ödersin" (Ar-Ge 14 Kas #4):
/// tutar mağazanın iki fiyatından, yalnız aylık ve iptal edilmemiş abonede;
/// fiyat yoksa ya da fark yoksa satır yok. Satır ≥ 44 pt, düğme rolü.
void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  group('yillikFark', () {
    test('12 × aylık − yıllık, kuruşa yuvarlanır', () {
      expect(yillikFark(79.99, 649.99), 309.89);
    });

    test('fark yoksa ya da negatifse null', () {
      expect(yillikFark(50, 600), isNull);
      expect(yillikFark(50, 700), isNull);
      expect(yillikFark(0, 600), isNull);
    });

    test('mağaza para biriminde biçim', () {
      expect(fmtMagazaTutari(309.89, 'TRY'), '₺309,89');
      expect(fmtMagazaTutari(30, 'USD', dil: 'en_US'), r'$30.00');
    });
  });

  group('abonelik satırında', () {
    PremiumHakki hak({String urun = 'sandik_premium_aylik', bool iptal = false}) =>
        PremiumHakki(
          kaynak: 'revenuecat',
          bitis: DateTime(2026, 12, 19),
          urun: urun,
          magaza: 'app_store',
          iptalEdildi: iptal,
        );

    Future<void> kur(WidgetTester t, PremiumHakki h,
        {({double tutar, String paraBirimi})? tasarruf =
            (tutar: 309.89, paraBirimi: 'TRY'),
        double olcek = 1}) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          abonelikDonemiProvider
              .overrideWith((_) async => const AbonelikDonemi(deneme: false)),
          premiumKullanimProvider.overrideWithValue(const []),
          yillikTasarrufProvider.overrideWith((_) async => tasarruf),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(olcek)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(child: PremiumAbonelikSatiri(hak: h))),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    const metin = 'Yıllığa geçersen yılda ₺309,89 az ödersin';

    testWidgets('aylık abone: satır görünür, ≥ 44 pt, düğme', (t) async {
      final s = t.ensureSemantics();
      await kur(t, hak());
      expect(find.text(metin), findsOneWidget);
      final kutu = find.ancestor(
          of: find.text(metin), matching: find.byType(InkWell));
      expect(t.getSize(kutu.first).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(
          t.getSemantics(kutu.first),
          isSemantics(
              label: metin, isButton: true, hasTapAction: true));
      s.dispose();
    });

    testWidgets('yıllık abonede yok', (t) async {
      await kur(t, hak(urun: 'sandik_premium_yillik'));
      expect(find.textContaining('Yıllığa geçersen'), findsNothing);
    });

    testWidgets('iptal etmiş aylık abonede yok', (t) async {
      await kur(t, hak(iptal: true));
      expect(find.textContaining('Yıllığa geçersen'), findsNothing);
    });

    testWidgets('mağaza fiyatı yoksa yok', (t) async {
      await kur(t, hak(), tasarruf: null);
      expect(find.textContaining('Yıllığa geçersen'), findsNothing);
    });

    testWidgets('Dynamic Type 2× taşma yok', (t) async {
      await kur(t, hak(), olcek: 2);
      expect(t.takeException(), isNull);
      expect(find.text(metin), findsOneWidget);
    });
  });
}
