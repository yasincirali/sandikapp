import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/screens/lock_screen.dart';
import 'package:portfoy_takip/services/biometric_lock_service.dart';
import 'package:portfoy_takip/services/social_auth_service.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/social_sign_in_buttons.dart';

/// Giriş/kimlik yüzeylerinde istek atan düğmeler tek yükleniyor
/// davranışına bağlı (2026-10-08): iş sürerken gösterge görünür, düğme
/// pasif, ikinci dokunuş ikinci isteği atmaz; iş bitince düğme geri gelir.
void main() {
  final busy = find.byKey(const ValueKey('busy'));

  group('Apple / Google düğmeleri', () {
    late Completer<void> istek;
    late int cagri;

    Future<void> ac(WidgetTester tester) async {
      istek = Completer<void>();
      cagri = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(
              () => _BekleyenAuth(() {
                    cagri++;
                    return istek.future;
                  })),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SocialSignInButtons(
              platformOverride: TargetPlatform.iOS,
              googleConfiguredOverride: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    SandikAsyncButton dugme(WidgetTester tester, String etiket) =>
        tester.widget<SandikAsyncButton>(find.ancestor(
            of: find.text(etiket), matching: find.byType(SandikAsyncButton)));

    testWidgets('çift dokunuş tek istek; gösterge ve öteki düğme pasif',
        (tester) async {
      await ac(tester);
      await tester.tap(find.text('Apple ile devam et'));
      await tester.pump();
      await tester.tap(find.text('Apple ile devam et'), warnIfMissed: false);
      await tester.pump();

      expect(cagri, 1, reason: 'ikinci dokunuş ikinci isteği atmamalı');
      expect(busy, findsOneWidget, reason: 'yalnız dokunulan düğmede gösterge');
      expect(dugme(tester, 'Apple ile devam et').onPressed, isNull);
      expect(dugme(tester, 'Google ile devam et').onPressed, isNull,
          reason: 'Apple sürerken Google başlatılamaz');

      istek.complete();
      await tester.pumpAndSettle();
      expect(busy, findsNothing);
      expect(dugme(tester, 'Apple ile devam et').onPressed, isNotNull);
      expect(dugme(tester, 'Google ile devam et').onPressed, isNotNull);
    });
  });

  group('Kilit ekranı — hesap değiştir (çıkış)', () {
    final l = AppLocalizationsTr();

    setUp(() => BiometricLockService.resetForTest(_IptalKilit()));
    tearDown(BiometricLockService.resetForTest);

    testWidgets('çıkış sürerken gösterge, pasif, tek çağrı', (tester) async {
      final cikis = Completer<void>();
      var cagri = 0;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LockScreen(
          onUnlocked: () {},
          onKilidiKapat: () {},
          onCikisYap: () {
            cagri++;
            return cikis.future;
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.lockSwitchAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.lockSwitchAccountTitle).last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(cagri, 1);
      expect(busy, findsOneWidget);
      final dugme = find.ancestor(
          of: find.text(l.lockSwitchAccount),
          matching: find.byType(TextButton));
      expect(tester.widget<TextButton>(dugme).onPressed, isNull);

      // İkinci dokunuş onay diyaloğunu bile açmaz.
      await tester.tap(find.text(l.lockSwitchAccount), warnIfMissed: false);
      await tester.pump();
      expect(find.text(l.lockSwitchAccountBody), findsNothing);

      cikis.complete();
      await tester.pumpAndSettle();
      expect(busy, findsNothing);
      expect(tester.widget<TextButton>(dugme).onPressed, isNotNull);
      expect(cagri, 1);
    });
  });
}

class _BekleyenAuth extends AuthNotifier {
  _BekleyenAuth(this._giris);
  final Future<void> Function() _giris;

  @override
  Future<AppUser?> build() async => null;

  @override
  Future<void> loginWithSocial(SocialProvider provider) => _giris();
}

class _IptalKilit extends BiometricLockService {
  _IptalKilit() : super.forTest();

  @override
  Future<bool> get available async => true;

  @override
  Future<BiyometrikSonuc> authenticate({String reason = ''}) async =>
      BiyometrikSonuc.iptal;
}
