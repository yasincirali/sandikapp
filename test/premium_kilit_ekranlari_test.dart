import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/screens/yillik_rapor_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';
import 'package:portfoy_takip/widgets/sinyal_kilit_karti.dart';

import 'helpers/kontrast_denetimi.dart';

/// Bütünüyle Premium olan ekranlar kilitliyken (paywall açık, Premium
/// değil) yalnız `PremiumKilitKarti` çizer: içerik yüklenmez, sayı
/// gösterilmez, kart neyin kazanılacağını söyler ve paywall'a götürür
/// (2026-10-10). İki temada da metin okunur.
class _OturumYok extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Future<void> _kur(WidgetTester tester, Brightness b, Widget ekran) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
  await tester.pumpWidget(ProviderScope(
    key: ValueKey(b),
    overrides: [
      authProvider.overrideWith(_OturumYok.new),
      premiumKilitliProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: SandikApp.buildTheme(p, b),
      home: ekran,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final ekranlar = <String, (Widget, String)>{
    'yıllık rapor': (const YillikRaporScreen(), "Yıllık rapor Premium'da"),
    'temettü tahmini': (
      const TemettuTahminiScreen(),
      "Temettü tahmini Premium'da"
    ),
    'aylık rapor': (
      AylikRaporScreen(donem: DateTime(2026, 9)),
      "Aylık rapor Premium'da"
    ),
  };

  for (final MapEntry(key: ad, value: (ekran, kilit)) in ekranlar.entries) {
    for (final b in Brightness.values) {
      testWidgets('$ad kilitli (${b.name}): tek kilit kartı, okunur',
          (tester) async {
        await _kur(tester, b, ekran);
        expect(find.byType(PremiumKilitKarti), findsOneWidget);
        expect(find.text(kilit), findsOneWidget);
        final p =
            b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
        expect(kontrastDenetle(tester, varsayilanZemin: p.background),
            isEmpty);
      });
    }
  }

  testWidgets('sinyal kilit kartı sekiz göstergeyi sayar', (tester) async {
    await _kur(tester, Brightness.dark,
        const Scaffold(body: SinyalKilitKarti()));
    expect(find.text("Teknik sinyaller Premium'da"), findsOneWidget);
    expect(find.textContaining('Williams %R'), findsOneWidget);
  });
}
