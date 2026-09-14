import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../config/supabase_config.dart';

/// Desteklenen sosyal sağlayıcılar.
enum SocialProvider { apple, google }

/// Platform SDK'sından alınan, Supabase'e verilecek kimlik.
///
/// `rawNonce` yalnızca Apple'da dolu: Apple'a SHA-256'sı gider, Supabase'e
/// hamı — Supabase token içindeki hash ile karşılaştırır (replay koruması).
class SocialCredential {
  final SocialProvider provider;
  final String idToken;
  final String? rawNonce;

  /// Sağlayıcının verdiği ad. Apple bunu YALNIZCA ilk yetkilendirmede
  /// verir; sonraki girişlerde null gelir — profil ilk seferde yazılmalı.
  final String? displayName;
  final String? email;

  const SocialCredential({
    required this.provider,
    required this.idToken,
    this.rawNonce,
    this.displayName,
    this.email,
  });

  OAuthProvider get oauthProvider => switch (provider) {
        SocialProvider.apple => OAuthProvider.apple,
        SocialProvider.google => OAuthProvider.google,
      };
}

/// Kullanıcı sağlayıcı ekranında vazgeçti — hata değil, sessiz dönüş.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Apple / Google SDK'larıyla konuşan ince katman.
///
/// **Neden AuthService'ten ayrı:** AuthService Supabase'e bağlı ve test
/// edilebilir; platform SDK'ları ise test ortamında yok. Bu sınıf yalnızca
/// "token al" işini yapar, oturum açmayı [AuthService.loginWithSocial]
/// üstlenir. Hesap silmede de aynı yol tekrar kullanılır: sosyal hesabın
/// şifresi yoktur, "taze kimlik" yine buradan alınır.
class SocialAuthService {
  static final SocialAuthService instance = SocialAuthService._();
  SocialAuthService._();

  bool _googleReady = false;

  /// Bu platformda/derlemede hangi düğmeler gösterilmeli.
  ///
  /// Apple: yalnızca iOS/macOS (Android'de web akışı ister; kapsam dışı).
  /// Google: yapılandırma kimliği derlemeye verilmemişse düğme çizilmez —
  /// aksi halde dokununca SDK anlaşılmaz bir hata atardı.
  static List<SocialProvider> availableProviders({
    TargetPlatform? platform,
    bool googleConfigured = googleWebClientId != '',
  }) {
    final p = platform ?? defaultTargetPlatform;
    return [
      if (!kIsWeb && (p == TargetPlatform.iOS || p == TargetPlatform.macOS))
        SocialProvider.apple,
      if (googleConfigured) SocialProvider.google,
    ];
  }

  Future<SocialCredential> obtain(SocialProvider provider) => switch (provider) {
        SocialProvider.apple => _apple(),
        SocialProvider.google => _google(),
      };

  Future<SocialCredential> _apple() async {
    final rawNonce = generateNonce();
    final AuthorizationCredentialAppleID cred;
    try {
      cred = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: sha256Hex(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      rethrow;
    }
    final token = cred.identityToken;
    if (token == null || token.isEmpty) {
      throw StateError('Apple kimlik token\'ı boş döndü.');
    }
    return SocialCredential(
      provider: SocialProvider.apple,
      idToken: token,
      rawNonce: rawNonce,
      displayName: joinName(cred.givenName, cred.familyName),
      email: cred.email,
    );
  }

  Future<SocialCredential> _google() async {
    final gsi = GoogleSignIn.instance;
    if (!_googleReady) {
      await gsi.initialize(
        serverClientId: googleWebClientId,
        clientId: googleIosClientId.isEmpty ? null : googleIosClientId,
      );
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await gsi.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCancelled();
      }
      rethrow;
    }
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw StateError('Google kimlik token\'ı boş döndü.');
    }
    return SocialCredential(
      provider: SocialProvider.google,
      idToken: token,
      displayName: account.displayName,
      email: account.email,
    );
  }

  /// Çıkışta Google hesabı seçicisi sıfırlansın: aynı cihazda başka
  /// hesaba geçen kullanıcı öncekiyle otomatik bağlanmasın.
  Future<void> signOutGoogle() async {
    if (!_googleReady) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best-effort; oturum zaten Supabase tarafında kapandı.
    }
  }

  // ── Saf yardımcılar (test edilir) ─────────────────────────────────────

  static const _nonceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';

  /// Kriptografik rastgele nonce (Apple `nonce` alanı için 32 karakter).
  static String generateNonce([int length = 32]) {
    final rnd = Random.secure();
    return List.generate(length, (_) => _nonceChars[rnd.nextInt(_nonceChars.length)])
        .join();
  }

  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// Apple ad parçalarını tek ada çevirir; ikisi de boşsa null.
  static String? joinName(String? given, String? family) {
    final parts = [given, family]
        .map((s) => (s ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// Profile yazılacak görünen ad: sağlayıcı adı → e-posta yerel kısmı →
  /// sağlayıcı etiketi. Apple gizli e-posta (`@privaterelay.appleid.com`)
  /// verdiğinde yerel kısım anlamsız bir kod olur; o durumda etikete düşer.
  static String displayNameFor(SocialCredential c, {String? fallbackEmail}) {
    final fromProvider = c.displayName?.trim();
    if (fromProvider != null && fromProvider.isNotEmpty) return fromProvider;
    final email = (c.email ?? fallbackEmail ?? '').trim().toLowerCase();
    if (email.contains('@') && !email.endsWith('@privaterelay.appleid.com')) {
      return email.split('@').first;
    }
    return switch (c.provider) {
      SocialProvider.apple => 'Apple kullanıcısı',
      SocialProvider.google => 'Google kullanıcısı',
    };
  }
}
