import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/forgot_password_screen.dart';
import 'package:portfoy_takip/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yazım önerisi giriş ve şifremi unuttum ekranlarında da var (yasin
/// 2026-11-14: "düzeltme önerisi gelmedi" — kayıttan başka ekranda da
/// e-posta yazılıyor; yanlış adresle giriş "bilgiler hatalı" diye döner,
/// kullanıcı nedenini göremez).
void main() {
  final l = AppLocalizationsTr();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (ad, ekran) in [
    ('giriş', () => const LoginScreen() as Widget),
    ('şifremi unuttum', () => const ForgotPasswordScreen() as Widget),
  ]) {
    testWidgets('$ad: gmail.con yazınca öneri çıkar, dokununca düzelir',
        (tester) async {
      tester.view.physicalSize = const Size(700, 1600) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ekran(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final alan = find.ancestor(
          of: find.text(l.email), matching: find.byType(TextField));
      await tester.enterText(alan.first, 'ali@gmail.con');
      await tester.pump();
      final oneri = find.textContaining('ali@gmail.com', findRichText: true);
      expect(oneri, findsOneWidget);
      await tester.tap(oneri);
      await tester.pump();
      expect(tester.widget<TextField>(alan.first).controller!.text,
          'ali@gmail.com');
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
