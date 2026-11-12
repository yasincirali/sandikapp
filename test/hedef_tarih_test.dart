import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/hedef_tarihi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/hedef_sheet.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Hedefe tarih (Premium, yasin 2026-11-06).
///
/// Kilitlenenler:
/// 1. Aylık tutar düz bölme: kalan ÷ kalan TAM ay (en az 1), yukarı
///    yuvarlanır; gün geçtiyse ya da kalan ≤ 0 ise söylenmez.
/// 2. Ücretsizde satır kilitli, dokununca paywall kapısı; tarih yazılmaz.
/// 3. Premium'da çipler + "ayda yaklaşık … (getiri hariç)" cümlesi.
/// 4. 44 pt, 2× yazı, İngilizce.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('hedefAylikTutar', () {
    final bugun = DateTime(2026, 11, 6, 14, 30);

    test('12 ay: kalan ÷ 12, yukarı yuvarlanır', () {
      expect(
          hedefAylikTutar(
              kalan: 100000, tarih: DateTime(2027, 11, 6), bugun: bugun),
          8334); // 8333,33 → 8334
      expect(
          hedefAylikTutar(
              kalan: 120000, tarih: DateTime(2027, 11, 6), bugun: bugun),
          10000);
    });

    test('kısmi ay aşağı sayılır (tutar yetişmeye yeter)', () {
      expect(hedefeKalanAy(DateTime(2026, 12, 31), bugun), 1);
      expect(hedefeKalanAy(DateTime(2027, 1, 5), bugun), 1);
      expect(hedefeKalanAy(DateTime(2027, 1, 6), bugun), 2);
    });

    test('bir aydan az ya da bugün: en az 1 ay', () {
      expect(
          hedefAylikTutar(
              kalan: 50000, tarih: DateTime(2026, 11, 20), bugun: bugun),
          50000);
      expect(
          hedefAylikTutar(
              kalan: 50000, tarih: DateTime(2026, 11, 6), bugun: bugun),
          50000);
    });

    test('geçmiş gün: söylenmez', () {
      expect(
          hedefAylikTutar(
              kalan: 50000, tarih: DateTime(2026, 11, 5), bugun: bugun),
          isNull);
    });

    test('hedefe ulaşıldı (kalan ≤ 0): söylenmez', () {
      expect(
          hedefAylikTutar(kalan: 0, tarih: DateTime(2027, 6, 1), bugun: bugun),
          isNull);
      expect(
          hedefAylikTutar(
              kalan: -1000, tarih: DateTime(2027, 6, 1), bugun: bugun),
          isNull);
    });

    test('seçenekler ve kayıtlı günün çipi', () {
      expect(hedefTarihiSecenekten(HedefTarihSecenegi.birYil, bugun),
          DateTime(2027, 11, 6));
      expect(hedefTarihiSecenekten(HedefTarihSecenegi.yilSonu, bugun),
          DateTime(2026, 12, 31));
      expect(hedefTarihSecenegi(null, bugun), HedefTarihSecenegi.yok);
      expect(hedefTarihSecenegi(DateTime(2027, 11, 6), bugun),
          HedefTarihSecenegi.birYil);
      expect(hedefTarihSecenegi(DateTime(2026, 12, 31), bugun),
          HedefTarihSecenegi.yilSonu);
      expect(hedefTarihSecenegi(DateTime(2028, 3, 1), bugun),
          HedefTarihSecenegi.ozel);
    });

    test('gün geçti mi: yalnız bugünden önceki gün (bugün geçmedi)', () {
      expect(hedefGunuGecti(DateTime(2026, 11, 5), bugun), isTrue);
      expect(hedefGunuGecti(DateTime(2026, 11, 6), bugun), isFalse);
      expect(hedefGunuGecti(DateTime(2026, 11, 7), bugun), isFalse);
    });

    test("yüzdenin yönelme eki (\"%82'ye ulaştın\")", () {
      expect(sayiYonelmeEki(82), 'ye');
      expect(sayiYonelmeEki(50), 'ye');
      expect(sayiYonelmeEki(60), 'a');
      expect(sayiYonelmeEki(99), 'a');
      expect(sayiYonelmeEki(5), 'e');
    });

    test("yılın yönelme eki (Ana sayfa: \"Ara 2027'ye kadar\")", () {
      expect(yilYonelmeEki(2027), 'ye');
      expect(yilYonelmeEki(2026), 'ya');
      expect(yilYonelmeEki(2028), 'e');
      expect(yilYonelmeEki(2029), 'a');
      expect(yilYonelmeEki(2030), 'a');
      expect(yilYonelmeEki(2050), 'ye');
      expect(yilYonelmeEki(2100), 'e');
      expect(yilYonelmeEki(3000), 'e');
    });
  });

  group('hedef sayfası', () {
    Future<void> ac(
      WidgetTester tester, {
      required OzellikDurumu durum,
      double deger = 484020,
      bool gizli = false,
      Locale? dil,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [hedefTarihiDurumuProvider.overrideWithValue(durum)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: dil,
          localizationsDelegates:
              dil == null ? null : AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showHedefSheet(context, ref, deger: deger, gizli: gizli),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    Future<void> hedefYaz(WidgetTester tester, String tutar) async {
      await tester.enterText(find.byType(TextField), tutar);
      await tester.pumpAndSettle();
    }

    Future<int?> kayitliGun() async {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys()) {
        if (k.startsWith(PrefKeys.portfolioGoalDate)) return p.getInt(k);
      }
      return null;
    }

    testWidgets('ücretsiz: kilitli satır, seçenek yok, dokununca kayıt yok',
        (tester) async {
      await ac(tester, durum: OzellikDurumu.kilitli);
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.text('Hedefine tarih koy, Premium ile'), findsOneWidget);
      expect(find.text('1 yıl'), findsNothing);
      // Testte paywall RC'si kapalı: `PaywallScreen.show` sessizce döner;
      // kapı çağrısı kaynak metinden kilitli (aşağıda).
      await tester.tap(find.byType(KilitSatiri));
      await tester.pumpAndSettle();
      expect(find.text('1 yıl'), findsNothing);
      await hedefYaz(tester, '1.000.000');
      expect(find.textContaining('Ayda yaklaşık'), findsNothing);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(await kayitliGun(), isNull);
    });

    testWidgets('ücretsiz: kayıtlı gün silinmez, cümle çizilmez',
        (tester) async {
      final gun = DateTime(DateTime.now().year + 1, 1, 1);
      await ac(tester, durum: OzellikDurumu.kilitli, prefs: {
        PrefKeys.portfolioGoalTRY: 1000000,
        PrefKeys.portfolioGoalDate: gun.millisecondsSinceEpoch,
      });
      expect(find.textContaining('Ayda yaklaşık'), findsNothing);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(await kayitliGun(), gun.millisecondsSinceEpoch);
    });

    test('kilit satırı Premium kapısından geçer (olay + paywall)', () {
      final sheet = ekranKaynagiSync('lib/widgets/hedef_sheet.dart');
      expect(sheet, contains("kaynak: 'hedef_tarihi'"));
      expect(sheet, contains("ozellik: 'hedef_tarihi'"));
      final kilit = ekranKaynagiSync('lib/widgets/para_akisi_karti.dart');
      expect(
          kilit,
          contains(
              'AnalyticsService.instance.logPremiumGateShown(feature: ozellik!)'));
      expect(kilit, contains('PaywallScreen.show(context, source: kaynak)'));
    });

    testWidgets('paywall kapalı, admin değil: satır hiç yok', (tester) async {
      await ac(tester, durum: OzellikDurumu.gizli);
      expect(find.byType(KilitSatiri), findsNothing);
      expect(find.text('Ne zamana kadar?'), findsNothing);
    });

    testWidgets('Premium: seçenekler, cümle, getiri notu; gün kaydedilir',
        (tester) async {
      await ac(tester, durum: OzellikDurumu.acik);
      expect(find.text('Ne zamana kadar?'), findsOneWidget);
      for (final s in ['Yok', '1 yıl', 'Yıl sonu', 'Tarih seç']) {
        expect(find.text(s), findsOneWidget);
      }
      await hedefYaz(tester, '1.000.000');
      expect(find.textContaining('Ayda yaklaşık'), findsNothing); // gün yok
      await tester.tap(find.text('1 yıl'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final beklenen = hedefAylikTutar(
          kalan: 1000000 - 484020,
          tarih: DateTime(now.year + 1, now.month, now.day),
          bugun: now)!;
      expect(beklenen, 42999); // 515.980 ÷ 12 = 42.998,33 → yukarı
      expect(
          find.text('Ayda yaklaşık ${fmtTRY(beklenen.toDouble())} eklersen '
              'yetişirsin (getiri hariç)'),
          findsOneWidget);
      // "Getiri hariç" cümlenin içinde; ayrı satır kalmadı (2026-11-12).
      expect(find.text('Getiri hariç'), findsNothing);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(await kayitliGun(),
          DateTime(now.year + 1, now.month, now.day).millisecondsSinceEpoch);
    });

    testWidgets('Premium: hedefe ulaşıldıysa cümle yok', (tester) async {
      await ac(tester, durum: OzellikDurumu.acik, deger: 2000000);
      await hedefYaz(tester, '1.000.000');
      await tester.tap(find.text('Yıl sonu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ayda yaklaşık'), findsNothing);
      expect(find.text('Bu hedefi zaten geçtin'), findsNothing); // gizli değil
      expect(find.textContaining('zaten geçtin'), findsOneWidget);
    });

    testWidgets('Premium, bakiye gizli: tutar yazılmaz', (tester) async {
      await ac(tester, durum: OzellikDurumu.acik, gizli: true);
      await hedefYaz(tester, '1.000.000');
      await tester.tap(find.text('1 yıl'));
      await tester.pumpAndSettle();
      expect(
          find.text('Ayda yaklaşık •••• eklersen yetişirsin (getiri hariç)'),
          findsOneWidget);
    });

    testWidgets('dokunma alanı ≥ 44 pt (çipler ve kilit satırı)',
        (tester) async {
      await ac(tester, durum: OzellikDurumu.acik);
      for (final s in ['Yok', '1 yıl', 'Yıl sonu', 'Tarih seç']) {
        final cip = find.ancestor(
            of: find.text(s), matching: find.byType(SandikFiltreCipi));
        expect(
            tester.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min),
            reason: s);
      }
      await tester.pumpWidget(const SizedBox());
      await ac(tester, durum: OzellikDurumu.kilitli);
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('kilidin ekran okuyucu etiketi var', (tester) async {
      final h = tester.ensureSemantics();
      await ac(tester, durum: OzellikDurumu.kilitli);
      expect(find.bySemanticsLabel(RegExp('Kilitli')), findsOneWidget);
      h.dispose();
    });

    testWidgets('2× yazı: taşma yok', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ac(tester, durum: OzellikDurumu.acik);
      await hedefYaz(tester, '1.000.000');
      await tester.ensureVisible(find.text('1 yıl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 yıl'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('(getiri hariç)'), findsOneWidget);
    });

    testWidgets('İngilizce metin', (tester) async {
      await ac(tester, durum: OzellikDurumu.acik, dil: const Locale('en'));
      expect(find.text('When by?'), findsOneWidget);
      for (final s in ['None', '1 year', 'Year end', 'Pick a date']) {
        expect(find.text(s), findsOneWidget);
      }
      await hedefYaz(tester, '1.000.000');
      await tester.tap(find.text('1 year'));
      await tester.pumpAndSettle();
      expect(find.textContaining('a month to make it (excluding returns)'),
          findsOneWidget);
    });

    testWidgets('İngilizce kilit satırı', (tester) async {
      await ac(tester, durum: OzellikDurumu.kilitli, dil: const Locale('en'));
      expect(
          find.text('Set a date for your goal with Premium'), findsOneWidget);
    });
  });
}
