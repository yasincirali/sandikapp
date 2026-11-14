import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/otp_verification_screen.dart';

/// Kod ekranında yanlış adresi fark etme (yasin 2026-11-14: "hatalı mail
/// girdiğini nasıl anlar"). Eskiden yalnız soluk bir metin vardı; artık
/// "E-postayı değiştir" düğmesi `true` ile kapanır (kayıt ekranı e-posta
/// alanını seçili açar) ve ilk bekleme dolunca adres bir kez daha yazılır.
void main() {
  final l = AppLocalizationsTr();
  const adres = 'ahmet@gmial.com';

  Future<List<Object?>> ac(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final sonuclar = <Object?>[];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final r = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const OtpVerificationScreen(email: adres),
                  ),
                );
                sonuclar.add(r);
              },
              child: const Text('ac'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ac'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    return sonuclar;
  }

  testWidgets('"E-postayı değiştir" en az 44 pt ve true ile kapanır',
      (tester) async {
    final sonuclar = await ac(tester);
    final dugme = find.widgetWithText(TextButton, l.otpEpostayiDegistir);
    expect(dugme, findsOneWidget);
    final boyut = tester.getSize(dugme);
    expect(boyut.height, greaterThanOrEqualTo(44));
    await tester.tap(dugme);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(sonuclar, [true]);
  });

  testWidgets('ilk bekleme dolunca adres bir kez daha gösterilir',
      (tester) async {
    await ac(tester);
    expect(find.text(l.otpAdresKontrol(adres)), findsNothing);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text(l.otpAdresKontrol(adres)), findsOneWidget);
  });
}
