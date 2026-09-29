import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/screens/otp_verification_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';

/// Kayıt akışı dar Android ekranında büyük yazıyla taşmaz (2026-09-29).
///
/// Kapalı betada "Kayıt ol"dan sonra gelen kod ekranında kalan süre ve
/// "Kod gelmedi mi? Yeniden gönder" satırları 360 dp'de taşıyordu. Taşma
/// hatası testte istisna olarak yüzeye çıkar; burada hiç çıkmamalı.
void main() {
  for (final boyut in const [Size(360, 640), Size(320, 568)]) {
    for (final olcek in const [1.0, 1.3, 1.6]) {
      for (final ekran in const ['kod', 'kayit']) {
        testWidgets('$ekran ekranı ${boyut.width.toInt()} dp, yazı x$olcek',
            (tester) async {
          tester.view.physicalSize = boyut * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(ProviderScope(
            child: MediaQuery(
              data: MediaQueryData(
                  size: boyut, textScaler: TextScaler.linear(olcek)),
              child: MaterialApp(
                locale: const Locale('tr', 'TR'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ekran == 'kod'
                    ? const OtpVerificationScreen(
                        email: 'uzun.bir.adres@gmail.com')
                    : const RegisterScreen(),
              ),
            ),
          ));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant.only(TargetPlatform.android));
      }
    }
  }
}
