import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';

import 'helpers/kaynak.dart';

/// Alarmda "52 hafta zirvesi / dibi" çipleri (Ar-Ge 2026-11-11, ücretsiz):
/// değer varlık sayfasının elindeki 1Y serisinden gelir; yoksa çip yok,
/// sheet istek atmaz.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1', email: 't@e.com', displayName: 'T', createdAt: DateTime(2026));
}

const _sembol = 'THYAO.IS';

void main() {
  final zirveAd = '52 hafta zirvesi ${alarmFiyatMetni(350.5, _sembol)}';
  final dipAd = '52 hafta dibi ${alarmFiyatMetni(240.25, _sembol)}';

  Future<void> kur(WidgetTester t, AlarmAdayi aday, {double olcek = 1}) async {
    t.view.physicalSize = const Size(375, 900) * 3;
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(_FakeAuth.new)],
      child: MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: Scaffold(body: AlarmKurSheet(adaylar: [aday], sabit: true)),
      ),
    ));
    await t.pump();
  }

  String? ozet(WidgetTester t) {
    final f = find.byKey(const ValueKey('alarmFiyatOzeti'));
    return f.evaluate().isEmpty ? null : t.widget<Text>(f).data;
  }

  const aday = AlarmAdayi(_sembol, 'THY', 300,
      maliyet: 200, yil52: (zirve: 350.5, dip: 240.25));

  testWidgets('değer varken iki çip satırın sonunda', (t) async {
    await kur(t, aday);
    final satir = find.byKey(const ValueKey('alarmHizliCipler'));
    final cipler =
        find.descendant(of: satir, matching: find.byType(SandikFiltreCipi));
    final adlar = [
      for (final e in cipler.evaluate()) (e.widget as SandikFiltreCipi).ad
    ];
    expect(adlar.sublist(adlar.length - 2), [zirveAd, dipAd]);
    // Yön yalnız renkle değil: ok ikonu da var.
    final zirve = t.widget<SandikFiltreCipi>(find.ancestor(
        of: find.text(zirveAd), matching: find.byType(SandikFiltreCipi)));
    final dip = t.widget<SandikFiltreCipi>(find.ancestor(
        of: find.text(dipAd), matching: find.byType(SandikFiltreCipi)));
    expect(zirve.ikon, Icons.arrow_upward_rounded);
    expect(dip.ikon, Icons.arrow_downward_rounded);
    expect(zirve.semantik, contains('52 hafta zirvesine'));
  });

  testWidgets('zirveye dokununca alan dolar, yön yukarı', (t) async {
    await kur(t, aday);
    await t.ensureVisible(find.text(zirveAd));
    await t.pump();
    await t.tap(find.text(zirveAd));
    await t.pump();
    expect(find.widgetWithText(TextField, '350,50'), findsOneWidget);
    expect(ozet(t), contains('çıkarsa'));
  });

  testWidgets('dibe dokununca alan dolar, yön aşağı', (t) async {
    await kur(t, aday);
    await t.ensureVisible(find.text(dipAd));
    await t.pump();
    await t.tap(find.text(dipAd));
    await t.pump();
    expect(find.widgetWithText(TextField, '240,25'), findsOneWidget);
    expect(ozet(t), contains('inerse'));
    final dip = t.widget<SandikFiltreCipi>(find.ancestor(
        of: find.text(dipAd), matching: find.byType(SandikFiltreCipi)));
    expect(dip.secili, isTrue);
  });

  testWidgets('değer yoksa (seri yüklenmedi / yıl dolmadı) çip yok', (t) async {
    await kur(t, const AlarmAdayi(_sembol, 'THY', 300, maliyet: 200));
    expect(find.textContaining('52 hafta'), findsNothing);
  });

  testWidgets('bugün zirvedeyse zirve çipi yok (hedef güncele eşit)',
      (t) async {
    await kur(
        t,
        const AlarmAdayi(_sembol, 'THY', 350.5,
            yil52: (zirve: 350.5, dip: 240.25)));
    expect(find.textContaining('52 hafta zirvesi'), findsNothing);
    expect(find.textContaining('52 hafta dibi'), findsOneWidget);
  });

  testWidgets('güncel fiyat bilinmiyorsa çip yok (yön türetilemez)', (t) async {
    await kur(
        t,
        const AlarmAdayi(_sembol, 'THY', 0,
            yil52: (zirve: 350.5, dip: 240.25)));
    expect(find.textContaining('52 hafta'), findsNothing);
  });

  for (final olcek in [1.0, 2.0]) {
    testWidgets('×$olcek yazıda taşma yok, çip ≥44pt', (t) async {
      await kur(t, aday, olcek: olcek);
      expect(t.takeException(), isNull);
      for (final ad in [zirveAd, dipAd]) {
        final cip = find.ancestor(
            of: find.text(ad), matching: find.byType(SandikTappable));
        expect(t.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min),
            reason: ad);
        expect(t.getSize(cip).width, greaterThanOrEqualTo(SandikTouch.min),
            reason: ad);
      }
    });
  }

  // Sheet açılan yerlerden yalnız varlık sayfası seriyi elinde tutar; zil ve
  // şeridin "+"'sı aynı değeri geçirir. Değer yalnız TL varlıkta ve tam yılda
  // (ABD hissesinde TL serisi alarmın dolar ölçeğinde değildir).
  test('varlık sayfası 52 hafta değerini iki girişe de geçirir', () {
    final ekran = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect('yil52: _alarmYil52'.allMatches(ekran).length, 2);
    expect(ekran, contains("_canli.asset.currency != 'TRY'"));
    expect(ekran, contains('a.ay != null'));
  });
}
