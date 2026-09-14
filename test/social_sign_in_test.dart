import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/social_auth_service.dart';

/// Apple / Google ile giriş — platform SDK'sı olmadan doğrulanabilen kısım.
void main() {
  group('availableProviders', () {
    test('iOS: Apple her zaman, Google yalnızca yapılandırıldıysa', () {
      expect(
        SocialAuthService.availableProviders(
            platform: TargetPlatform.iOS, googleConfigured: false),
        [SocialProvider.apple],
      );
      expect(
        SocialAuthService.availableProviders(
            platform: TargetPlatform.iOS, googleConfigured: true),
        [SocialProvider.apple, SocialProvider.google],
      );
    });

    test('Android: Apple yok (web akışı kapsam dışı)', () {
      expect(
        SocialAuthService.availableProviders(
            platform: TargetPlatform.android, googleConfigured: true),
        [SocialProvider.google],
      );
      expect(
        SocialAuthService.availableProviders(
            platform: TargetPlatform.android, googleConfigured: false),
        isEmpty,
        reason: 'kimlik yokken düğme çizilirse SDK anlaşılmaz hata atar',
      );
    });
  });

  group('nonce', () {
    test('rastgele, 32 karakter, tekrar etmez', () {
      final a = SocialAuthService.generateNonce();
      final b = SocialAuthService.generateNonce();
      expect(a.length, 32);
      expect(a, isNot(b));
    });

    test('Apple\'a giden değer hamın SHA-256 hex\'i', () {
      expect(
        SocialAuthService.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('displayNameFor', () {
    SocialCredential c(SocialProvider p, {String? name, String? email}) =>
        SocialCredential(
            provider: p, idToken: 't', displayName: name, email: email);

    test('sağlayıcı adı önce', () {
      expect(
        SocialAuthService.displayNameFor(
            c(SocialProvider.google, name: 'Ayşe Yılmaz', email: 'a@x.com')),
        'Ayşe Yılmaz',
      );
    });

    test('ad yoksa e-posta yerel kısmı', () {
      expect(
        SocialAuthService.displayNameFor(
            c(SocialProvider.google, email: 'ayse.y@gmail.com')),
        'ayse.y',
      );
    });

    test('Apple gizli e-posta → etiket (kod parçası ad olmaz)', () {
      expect(
        SocialAuthService.displayNameFor(c(SocialProvider.apple,
            email: 'x9k2q@privaterelay.appleid.com')),
        'Apple kullanıcısı',
      );
    });

    test('joinName boşları atar', () {
      expect(SocialAuthService.joinName(' Ali ', null), 'Ali');
      expect(SocialAuthService.joinName('', ' '), isNull);
      expect(SocialAuthService.joinName('Ali', 'Veli'), 'Ali Veli');
    });
  });

  group('delete-account taze kimlik (kaynak taraması)', () {
    final fn = File('supabase/functions/delete-account/index.ts')
        .readAsStringSync();

    test('sosyal token doğrulanıyor ve kullanıcı JWT ile eşleşmeli', () {
      expect(fn.contains('signInWithIdToken'), isTrue);
      expect(fn.contains('data.user.id !== user.id'), isTrue,
          reason: 'başkasının Google hesabıyla bu oturum silinebilirdi');
    });

    test('kimliksiz istek reddedilir (fail-closed)', () {
      expect(fn.contains('return jsonResponse({ error: "password_required" }, 400)'),
          isTrue);
    });

    test('yalnızca apple/google kabul', () {
      expect(fn.contains('provider === "apple" || provider === "google"'), isTrue);
    });
  });
}
