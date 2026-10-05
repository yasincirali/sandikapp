import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/services/auth_service.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Kayıt: bağlantı kopması ve girdi kuralları (2026-09-29).
///
/// Prod olayı (iOS mağaza sürümü): `/signup` sunucuda 200 döndü, doğrulama
/// kodu e-postayla gitti, ama cevap telefona ulaşmadı. Kullanıcı "Kayıt
/// hatası: Giriş işlemi başarısız oldu" gördü ve kod ekranına geçemedi.
void main() {
  // Supabase'in bağlantı kopmasını sardığı biçim (gotrue fetch.dart).
  supa.AuthRetryableFetchException kopma() => supa.AuthRetryableFetchException(
      message: 'ClientException: Connection closed before full header was '
          'received, uri=https://x.supabase.co/auth/v1/signup');

  supa.AuthApiException guvenlikBeklemesi() => supa.AuthApiException(
        'For security purposes, you can only request this after 58 seconds.',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      );

  group('kayidiUlastir', () {
    test('ilk istek başarılıysa tek istek, cevap döner', () async {
      var n = 0;
      final r = await AuthService.kayidiUlastir(() async {
        n++;
        return 'ok';
      }, bekle: Duration.zero);
      expect(r, 'ok');
      expect(n, 1);
    });

    test('kopma → ikinci istek 429 "security purposes" → ilk istek ulaşmış '
        'sayılır (null, hata yok)', () async {
      var n = 0;
      final r = await AuthService.kayidiUlastir<String>(() async {
        n++;
        if (n == 1) throw kopma();
        throw guvenlikBeklemesi();
      }, bekle: Duration.zero);
      expect(r, isNull);
      expect(n, 2);
    });

    test('kopma → ikinci istek başarılı → cevap döner', () async {
      var n = 0;
      final r = await AuthService.kayidiUlastir(() async {
        n++;
        if (n == 1) throw const SocketException('Software caused connection abort');
        return 'ok';
      }, bekle: Duration.zero);
      expect(r, 'ok');
      expect(n, 2);
    });

    test('iki kez kopma → bağlantı hatası yukarı çıkar (kullanıcı formda '
        'kalır)', () async {
      var n = 0;
      await expectLater(
        AuthService.kayidiUlastir<String>(() async {
          n++;
          throw kopma();
        }, bekle: Duration.zero),
        throwsA(isA<supa.AuthRetryableFetchException>()),
      );
      expect(n, 2);
    });

    test('genel e-posta kotası 429 bir şey kanıtlamaz → hata yukarı çıkar',
        () async {
      var n = 0;
      await expectLater(
        AuthService.kayidiUlastir<String>(() async {
          n++;
          if (n == 1) throw kopma();
          throw supa.AuthApiException('Email rate limit exceeded',
              statusCode: '429', code: 'over_email_send_rate_limit');
        }, bekle: Duration.zero),
        throwsA(isA<supa.AuthApiException>()),
      );
    });

    test('ağ dışı hata yeniden denenmez', () async {
      var n = 0;
      await expectLater(
        AuthService.kayidiUlastir<String>(() async {
          n++;
          throw supa.AuthApiException('Signups not allowed',
              statusCode: '422');
        }, bekle: Duration.zero),
        throwsA(isA<supa.AuthApiException>()),
      );
      expect(n, 1);
    });
  });

  group('girdi kuralları', () {
    test('e-posta: sunucunun reddedeceği biçimler formda yakalanır', () {
      for (final iyi in [
        'aslihans0321@gmail.com',
        'a.b+c@alt.alan.com.tr',
        '  bosluklu@gmail.com  ',
      ]) {
        expect(AuthService.eMailGecerliMi(iyi), isTrue, reason: iyi);
      }
      for (final kotu in [
        'aslı@gmail.com',
        'ad soyad@gmail.com',
        'a..b@gmail.com',
        'ab@gmail',
        'ab@.com',
        '@gmail.com',
        'ab@gmail.c',
      ]) {
        expect(AuthService.eMailGecerliMi(kotu), isFalse, reason: kotu);
      }
    });

    test('şifre listesi ile validatePassword aynı kararı verir', () {
      for (final s in ['', 'abc', 'abcdefgh', '12345678', 'abcd1234',
          'ş' * 40 + '1']) {
        final k = AuthService.sifreKurallari(s);
        final hepsi = k.uzunluk && k.harf && k.rakam && k.sinirIcinde;
        expect(AuthService.validatePassword(s) == null, hepsi, reason: s);
      }
    });
  });

  group('sunucu girdi retleri okunur metne döner', () {
    test('geçersiz e-posta', () {
      expect(
        friendlyError(supa.AuthApiException(
            'Unable to validate email address: invalid format',
            statusCode: '400')),
        contains('E-posta adresi geçersiz'),
      );
    });
    test('60 sn güvenlik beklemesi', () {
      expect(friendlyError(guvenlikBeklemesi()), contains('bekle'));
    });
    test('tanınmayan auth hatası "giriş" demez', () {
      expect(
        friendlyError(const supa.AuthException('beklenmeyen')),
        isNot(contains('Giriş')),
      );
    });
  });

  group('kayıt formu eksikleri basmadan önce gösterir', () {
    final l = AppLocalizationsTr();

    Future<void> ac(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
          locale: Locale('tr', 'TR'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RegisterScreen(),
        ),
      ));
      await tester.pump();
    }

    Finder alan(String etiket) => find.ancestor(
        of: find.text(etiket), matching: find.byType(TextField));

    testWidgets('şifre yazarken kurallar canlı listelenir', (tester) async {
      await ac(tester);
      expect(find.text(l.sifreKuralUzunluk), findsNothing);
      await tester.enterText(alan(l.password), 'abc');
      await tester.pump();
      expect(find.text(l.sifreKuralUzunluk), findsOneWidget);
      expect(find.text(l.sifreKuralHarf), findsOneWidget);
      expect(find.text(l.sifreKuralRakam), findsOneWidget);
      // Harf var: o satır tikli; uzunluk ve rakam boş daire.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await tester.enterText(alan(l.password), 'abcd1234');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    });

    testWidgets('eksik formla "Kayıt ol" her alanın hatasını birden açar',
        (tester) async {
      await ac(tester);
      await tester.enterText(alan(l.email), 'aslı@gmail.com');
      await tester.pump();
      // Başlıktaki "Kayıt Ol" değil, formdaki düğme.
      await tester.tap(find.descendant(
          of: find.byType(ListView), matching: find.text(l.register)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l.emailInvalid), findsWidgets);
      expect(find.text(l.registerUsernameMissing), findsWidgets);
      // Şifre boş olsa da kurallar görünür (neyin gerektiği söylenir).
      expect(find.text(l.sifreKuralUzunluk), findsOneWidget);
      // Tek onay kutusu (2026-10-04): hata kutunun altında; eksik metinler
      // listede (zorunlu okuma).
      expect(find.text(l.tekOnayGerekli), findsWidgets);
      // Uyarının kendisi (tost/diyalog) kapanana kadar bekle.
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
