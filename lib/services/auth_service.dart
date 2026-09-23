import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/pref_keys.dart';
import '../models/user_model.dart';
import 'db_logger.dart';
import 'home_widget_service.dart';
import 'live_activity_service.dart';
import 'portfolio_cache.dart';
import 'social_auth_service.dart';
import 'supabase_service.dart';
import '../utils/friendly_error.dart';
import 'crash_reporter.dart';

const _uuid = Uuid();
const _savedEmailKey = 'saved_email';
const _pendingDisplayNameKey = 'pending_display_name';

/// Uygulamanın kimlik doğrulama istisnası. Mesajı kullanıcıya yazılmış
/// Türkçe (ya da l10n) cümledir — [KullaniciMesajli] sayesinde
/// `friendlyError` onu olduğu gibi gösterir (2026-09-23 denetimi U13).
/// Sözleşme: ham sunucu metni (`AuthApiException.message`) buraya
/// KONMAZ; `friendlyError(e)` ile çevrilerek konur.
class AuthException implements KullaniciMesajli {
  @override
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Rate limit'e takıldığında fırlatılır. Mesajın yanında **kalan
/// saniyeyi** de taşır ki UI geri sayım gösterebilsin — yalnızca
/// metin dönseydi ekran, süre dolduğunda kendini açamazdı.
class RateLimitedException extends AuthException {
  /// Tekrar denenebilmesi için kalan süre (saniye).
  final int retryAfterSeconds;

  const RateLimitedException(super.message, this.retryAfterSeconds);
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  final _log = DbLogger.instance;

  // ── Şifre gücü ────────────────────────────────────────────────────────────

  /// Şifrenin kabul edilebilir olup olmadığını döner.
  /// Null = geçerli; aksi halde kullanıcıya gösterilecek hata mesajı.
  /// B1 fix: min 8 karakter + en az bir harf + en az bir rakam.
  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'Şifre en az 8 karakter olmalı.';
    }
    // bcrypt ilk 72 baytı hash'ler; fazlası sessizce atılır ve kullanıcı
    // "uzun şifrem var" sanır (2026-09 L12). Sınırı açıkça söyle.
    if (utf8.encode(password).length > 72) {
      return 'Şifre en fazla 72 karakter olabilir.';
    }
    if (!RegExp(r'[A-Za-zğüşıöçĞÜŞİÖÇ]').hasMatch(password)) {
      return 'Şifre en az bir harf içermeli.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Şifre en az bir rakam içermeli.';
    }
    return null;
  }

  // ── Mevcut oturum ──────────────────────────────────────────────────────────

  /// Cihazda geçerli bir oturum token'ı var mı? Tamamen yerel — ağ gerekmez.
  ///
  /// "Profil çekilemedi" ile "oturum yok" ayrımı için: ilkinde kullanıcı
  /// hâlâ oturumdadır ve login ekranına atılmamalıdır.
  bool get hasLocalSession => _client.auth.currentSession != null;

  /// Mevcut oturumun kullanıcısı.
  ///
  /// `currentUser` yerel (Supabase token'ı diskte tutar) ve ağ olmadan da
  /// doludur; `getProfile` ise ağa gider. Ağ yokken profil çekimi
  /// fırlatırsa **oturum düşürülmez** — token geçerli olduğu sürece
  /// kullanıcı oturumdadır. Aksi halde uçak modunda uygulama kullanıcıyı
  /// LoginScreen'e atıyordu; oysa yapması gereken "bağlantını kontrol et"
  /// demek ve ağ gelince kaldığı yerden devam etmek.
  ///
  /// Profil çekilemediğinde token'daki bilgiden minimal bir [AppUser]
  /// kurulur; `displayName` boş kalır ve ağ gelince gerçek profille
  /// [refreshProfile] üzerinden değişir.
  Future<AppUser?> getSessionUser() async {
    final supaUser = _client.auth.currentUser;
    if (supaUser == null) return null;
    try {
      return await SupabaseService.instance.getProfile(supaUser.id);
    } catch (_) {
      return AppUser.fromSession(
        id: supaUser.id,
        email: supaUser.email,
        displayName: supaUser.userMetadata?['display_name'] as String?,
        createdAt: supaUser.createdAt,
      );
    }
  }

  /// Ağ geri geldiğinde gerçek profili tazeler.
  /// Yine başarısız olursa mevcut (minimal) kullanıcı korunur.
  Future<AppUser?> refreshProfile() async {
    final supaUser = _client.auth.currentUser;
    if (supaUser == null) return null;
    return SupabaseService.instance.getProfile(supaUser.id);
  }

  // ── Kaydedilen email ───────────────────────────────────────────────────────

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedEmailKey);
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
  }

  /// Kayıt sonrası LoginScreen'in initState'te otomatik doldurması için
  /// email'i SharedPreferences'a yazar.
  Future<void> saveEmailForLogin(String email) => _saveEmail(email);

  /// Register + OTP verify arasında displayName'i taşımak için.
  /// Verify başarılı olunca profile upsert'inde kullanılır ve silinir.
  Future<void> _savePendingDisplayName(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingDisplayNameKey, displayName);
  }

  Future<String?> _getPendingDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingDisplayNameKey);
  }

  Future<void> _clearPendingDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingDisplayNameKey);
  }

  Future<void> clearSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedEmailKey);
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<AppUser> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Geçerli bir e-posta girin.');
    }
    if (displayName.trim().isEmpty) {
      throw const AuthException('Ad soyad boş olamaz.');
    }
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      throw AuthException(passwordError);
    }

    try {
      final response = await _log.log(
        source: 'AuthService.register',
        table: 'auth/sign-up',
        op: 'RPC',
        request: {'email': normalizedEmail, 'display_name': displayName.trim()},
        call: () => _client.auth.signUp(
          email: normalizedEmail,
          password: password,
          data: {'display_name': displayName.trim()},
        ),
      );

      if (response.user == null) {
        throw const AuthException('Kayıt başarısız. Lütfen tekrar deneyin.');
      }

      // NOT: identities.isEmpty kontrolü kaldırıldı. Confirm-email AÇIKKEN
      // Supabase 2024+ changelog'a göre yeni ve unconfirmed user için de
      // identities boş dönebiliyor — duplicate ayrımını güvenle yapamayız.
      // Doğru akış: her durumda OTP ekranına yönlendir; duplicate ise
      // kullanıcı mevcut hesabının OTP'sini alır, verify başarılı → giriş.
      // "Bu e-posta zaten kayıtlı" hatası verifyOtp aşamasında da yakalanır
      // (Supabase yanlış koda 'invalid token' döner).

      // Confirm-email AÇIK — session null olmalı. Supabase register sonrası
      // otomatik OTP maili gönderir. Kullanıcı verifyOtp ile doğrulayana
      // kadar oturum açılmaz. Register'ı burada sonlandırıyoruz;
      // RegisterScreen bir sonraki adımda OtpVerificationScreen'e
      // yönlendirir.
      final user = AppUser(
        id: response.user!.id,
        email: normalizedEmail,
        displayName: displayName.trim(),
        createdAt: DateTime.now(),
      );

      // Post-signup best-effort: displayName'i email için kaydet, profil
      // upsert'i doğrulama sonrasına ertelenir (RLS auth.uid() ile
      // korunuyor, doğrulanmadan yazamayız).
      try {
        await _saveEmail(normalizedEmail);
      } catch (_) {}
      try {
        await _savePendingDisplayName(displayName.trim());
      } catch (_) {}
      return user;
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      // Hesap numaralandırma (M4): "zaten kayıtlı" demek, bu e-postanın bir
      // hesabı olduğunu doğrulamaktı. Confirm-email açıkken Supabase zaten
      // duplicate için de "kod gönderildi" davranır; bu dal yalnızca eski
      // yapılandırmalarda çalışır. Mesaj artık varlığı doğrulamıyor.
      if (e.message.contains('already registered') ||
          e.message.contains('User already registered')) {
        throw const AuthException(
          'Bu e-posta ile kayıt tamamlanamadı. Hesabın varsa giriş yap ya da '
          'şifreni sıfırla.',
        );
      }
      throw AuthException(friendlyError(e));
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Kayıt hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.register');
      throw AuthException('Kayıt hatası: ${friendlyError(e)}');
    }
  }

  // ── Email OTP (register verification) ─────────────────────────────────────

  /// Register sonrası kullanıcının email'ine gönderilen 6 haneli kodu
  /// doğrular. Başarılı olursa Supabase session açılır ve profil upsert
  /// edilir (register sırasında pending kaydedilen displayName ile).
  ///
  /// AuthGate authProvider'ı dinlediği için verifyOtp'den sonra
  /// authProvider.refresh() çağırmak session'ı UI'ya yansıtır.
  Future<AppUser> verifyRegistrationOtp({
    required String email,
    required String token,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final cleanToken = token.trim();
    if (cleanToken.length != 6 || int.tryParse(cleanToken) == null) {
      throw const AuthException('Kod 6 haneli olmalı.');
    }

    try {
      final response = await _log.log(
        source: 'AuthService.verifyRegistrationOtp',
        table: 'auth/verify-otp',
        op: 'RPC',
        request: {'email': normalizedEmail, 'type': 'signup'},
        call: () => _client.auth.verifyOTP(
          email: normalizedEmail,
          token: cleanToken,
          type: OtpType.signup,
        ),
      );

      if (response.user == null) {
        throw const AuthException('Kod doğrulanamadı. Tekrar deneyin.');
      }

      // Register sırasında kaydettiğimiz displayName'i çek; profile upsert.
      final pendingName = await _getPendingDisplayName();
      final displayName = pendingName?.trim().isNotEmpty == true
          ? pendingName!.trim()
          : (response.user!.userMetadata?['display_name'] as String?)?.trim() ??
              normalizedEmail.split('@').first;

      final user = AppUser(
        id: response.user!.id,
        email: normalizedEmail,
        displayName: displayName,
        createdAt: DateTime.now(),
      );

      try {
        await SupabaseService.instance.upsertProfile(user);
      } catch (_) {}
      try {
        await _clearPendingDisplayName();
      } catch (_) {}
      return user;
    } on AuthApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('expired') || msg.contains('invalid')) {
        throw const AuthException(
            'Kod geçersiz veya süresi doldu. Yeni kod isteyin.');
      }
      // Ham GoTrue metni (İngilizce) kullanıcıya gitmesin — U13 sözleşmesi.
      throw AuthException(friendlyError(e));
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Doğrulama hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.verifyRegistrationOtp');
      throw AuthException('Doğrulama hatası: ${friendlyError(e)}');
    }
  }

  /// Yeni OTP kodu gönderilir (kullanıcı gelen kodu yakalayamadıysa).
  Future<void> resendRegistrationOtp(String email) async {
    final normalizedEmail = email.toLowerCase().trim();
    try {
      await _log.log<void>(
        source: 'AuthService.resendRegistrationOtp',
        table: 'auth/resend',
        op: 'RPC',
        request: {'email': normalizedEmail, 'type': 'signup'},
        call: () async {
          await _client.auth.resend(
            type: OtpType.signup,
            email: normalizedEmail,
          );
        },
      );
    } on AuthApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate') || msg.contains('too many')) {
        throw const AuthException(
            'Çok sık kod istedin. 60 saniye bekleyip tekrar dene.');
      }
      // Ham GoTrue metni (İngilizce) kullanıcıya gitmesin — U13 sözleşmesi.
      throw AuthException(friendlyError(e));
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Kod gönderilemedi: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.resendRegistrationOtp');
      throw AuthException('Kod gönderilemedi: ${friendlyError(e)}');
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<AppUser> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();

    try {
      final response = await _log.log(
        source: 'AuthService.login',
        table: 'auth/sign-in-with-password',
        op: 'RPC',
        request: {'email': normalizedEmail},
        call: () => _client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        ),
      );

      if (response.user == null) {
        throw const AuthException('Giriş başarısız.');
      }

      // Confirm-email AÇIK — doğrulamamış kullanıcı login yaparsa
      // OTP ekranına yönlendir (UI bu exception'ı yakalayıp
      // OtpVerificationScreen'e push edecek).
      if (response.user!.emailConfirmedAt == null) {
        // Session'ı temizle — yarım login state'i kalmasın.
        try { await _client.auth.signOut(); } catch (_) {}
        throw const AuthException(
            'EMAIL_NOT_CONFIRMED');
      }

      var profile =
          await SupabaseService.instance.getProfile(response.user!.id);
      if (profile == null) {
        profile = AppUser(
          id: response.user!.id,
          email: normalizedEmail,
          displayName:
              response.user!.userMetadata?['display_name'] as String? ??
                  normalizedEmail.split('@').first,
          createdAt: DateTime.now(),
        );
        await SupabaseService.instance.upsertProfile(profile);
      }

      if (rememberMe) {
        await _saveEmail(normalizedEmail);
      } else {
        await clearSavedEmail();
      }
      return profile;
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      if (e.message.contains('Invalid login credentials') ||
          e.message.contains('invalid_credentials')) {
        throw const AuthException('E-posta veya şifre hatalı.');
      }
      if (e.message.contains('Email not confirmed')) {
        throw const AuthException(
            'E-posta adresinizi doğrulayın. Gelen kutunuzu kontrol edin.');
      }
      // Ham GoTrue metni (İngilizce) kullanıcıya gitmesin — U13 sözleşmesi.
      throw AuthException(friendlyError(e));
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Giriş hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.login');
      throw AuthException('Giriş hatası: ${friendlyError(e)}');
    }
  }

  // ── Sosyal giriş (Apple / Google) ─────────────────────────────────────────

  /// Hesabın şifreyle girilebilen bir kimliği var mı?
  ///
  /// Yalnızca Apple/Google ile açılmış hesapta `email` sağlayıcısı yoktur;
  /// hesap silme gibi "taze kimlik" isteyen akışlar şifre yerine sosyal
  /// yeniden doğrulamaya gider. Supabase kimlik listesi yoksa (eski
  /// oturum) şifreli varsayılır — eski davranış.
  bool get hasPasswordIdentity {
    final ids = _client.auth.currentUser?.identities;
    if (ids == null || ids.isEmpty) return true;
    return ids.any((i) => i.provider == 'email');
  }

  /// Sağlayıcıdan ID token alır, Supabase'de oturum açar, profil yoksa yazar.
  ///
  /// Sosyal hesapta OTP adımı yok: e-posta sağlayıcı tarafından
  /// doğrulanmış gelir. Yasal metin onayı `AuthGate` tarafından hâlâ
  /// istenir (DisclaimerAcceptanceScreen) — bu kapı auth yöntemine bakmaz.
  Future<AppUser> loginWithSocial(SocialProvider provider) async {
    final cred = await SocialAuthService.instance.obtain(provider);
    try {
      final response = await _log.log(
        source: 'AuthService.loginWithSocial',
        table: 'auth/sign-in-with-id-token',
        op: 'RPC',
        request: {'provider': provider.name},
        call: () => _client.auth.signInWithIdToken(
          provider: cred.oauthProvider,
          idToken: cred.idToken,
          nonce: cred.rawNonce,
        ),
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException('Giriş başarısız.');
      }
      final email = (user.email ?? cred.email ?? '').toLowerCase().trim();

      var profile = await SupabaseService.instance.getProfile(user.id);
      if (profile == null) {
        profile = AppUser(
          id: user.id,
          email: email,
          displayName: SocialAuthService.displayNameFor(cred, fallbackEmail: email),
          createdAt: DateTime.now(),
        );
        await SupabaseService.instance.upsertProfile(profile);
      }
      if (email.isNotEmpty) await _saveEmail(email);
      return profile;
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e, st) {
      CrashReporter.report(e, st, reason: 'AuthService.loginWithSocial');
      throw AuthException(
          '${provider == SocialProvider.apple ? 'Apple' : 'Google'} ile giriş '
          'yapılamadı. Biraz sonra tekrar dene.');
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Giriş hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.loginWithSocial');
      throw AuthException('Giriş hatası: ${friendlyError(e)}');
    }
  }

  // ── Şifre Sıfırlama (OTP) ─────────────────────────────────────────────────

  /// Kullanıcının e-posta adresine 6 haneli OTP kodu gönderir.
  /// Kullanıcı kodu ve yeni şifreyi tek ekranda girer, sonra
  /// [verifyPasswordResetOtp] çağrılır.
  Future<void> sendPasswordResetOtp(String email) async {
    final normalized = email.toLowerCase().trim();
    if (normalized.isEmpty || !normalized.contains('@')) {
      throw const AuthException('Geçerli bir e-posta girin.');
    }
    try {
      await _log.log<void>(
        source: 'AuthService.sendPasswordResetOtp',
        table: 'auth/reset-password-for-email',
        op: 'RPC',
        request: {'email': normalized},
        call: () => _client.auth.resetPasswordForEmail(normalized),
      );
    } on AuthApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many')) {
        throw const AuthException(
          'Çok fazla deneme. Birkaç dakika bekleyip tekrar dene.',
        );
      }
      // H2: kullanıcı yok/var enumeration — genel mesaj
      throw const AuthException(
        'İstek alındı. E-posta adresine kod gönderdik.',
      );
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Şifre sıfırlama isteği başarısız: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.sendPasswordResetOtp');
      throw AuthException('Şifre sıfırlama isteği başarısız: ${friendlyError(e)}');
    }
  }

  /// OTP kodu ile yeni şifreyi ayarlar. Başarılıysa kullanıcı otomatik
  /// giriş yapmış olur (session döner).
  Future<void> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final normalized = email.toLowerCase().trim();
    final passError = validatePassword(newPassword);
    if (passError != null) throw AuthException(passError);
    final cleanOtp = otp.trim();
    if (cleanOtp.isEmpty) {
      throw const AuthException('Kod girin.');
    }
    // Kayıt OTP'siyle aynı biçim kuralı — sunucuya biçimsiz kod gitmesin.
    if (cleanOtp.length != 6 || int.tryParse(cleanOtp) == null) {
      throw const AuthException('Kod 6 haneli olmalı.');
    }

    try {
      // 1) OTP'yi doğrula — başarılıysa geçici session açılır
      await _log.log(
        source: 'AuthService.verifyPasswordResetOtp',
        table: 'auth/verify-otp',
        op: 'RPC',
        request: {'email': normalized, 'type': 'recovery'},
        call: () => _client.auth.verifyOTP(
          email: normalized,
          token: otp.trim(),
          type: OtpType.recovery,
        ),
      );
      // 2) Yeni şifreyi ata
      await _log.log(
        source: 'AuthService.verifyPasswordResetOtp.updateUser',
        table: 'auth/update-user',
        op: 'RPC',
        request: {},
        call: () => _client.auth.updateUser(
          UserAttributes(password: newPassword),
        ),
      );
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('expired') ||
          msg.contains('token')) {
        throw const AuthException('Kod hatalı veya süresi doldu.');
      }
      // Ham GoTrue metni (İngilizce) kullanıcıya gitmesin — U13 sözleşmesi.
      throw AuthException(friendlyError(e));
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Şifre güncelleme hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.verifyPasswordResetOtp');
      throw AuthException('Şifre güncelleme hatası: ${friendlyError(e)}');
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    final uid = _client.auth.currentUser?.id;
    try {
      await _log.log<void>(
        source: 'AuthService.logout',
        table: 'auth/sign-out',
        op: 'RPC',
        request: {},
        call: () => _client.auth.signOut(),
      );
    } catch (e, st) {
      // Çevrimdışı çıkış yarıda kalıyordu (2026-09-23 denetimi F8): gotrue
      // yerel oturumu siler, sonra ağ hatasını yeniden fırlatır. Hata
      // yukarı çıkınca aşağıdaki temizlik (widget bakiyesi, Live Activity,
      // çevrimdışı defter) HİÇ çalışmıyor, uygulama da "oturumlu ama
      // oturumsuz" kalıyordu. Sunucudaki refresh token'ın iptali ağ
      // gelince önemsizdir (süresi dolar); cihazdaki iz ise hemen silinmeli.
      // Yerel kapsamlı çıkış ağa gitmez, oturumun cihazdan kalktığını
      // garanti eder.
      CrashReporter.report(e, st, reason: 'AuthService.logout (yerel çıkışa düşüldü)');
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Yerel oturum zaten silinmiş olabilir — temizlik yine sürer.
      }
    }
    // Ana ekran widget'ındaki bakiye temizlenmeli: widget verisi cihaz
    // genelinde okunabilir bir depoda durur ve çıkış yapan kullanıcının
    // toplam varlığı ana ekranda asılı kalırdı.
    await HomeWidgetService.instance.clear();
    // Kilit ekranındaki Live Activity de kapatılmalı — ana ekran
    // widget'ıyla aynı gerekçe, daha da kritik: kilit ekranı telefon
    // açılmadan görülür.
    await LiveActivityService.instance.endAll();
    // Çevrimdışı defter de kullanıcıya ait: aynı cihazdaki bir sonraki
    // hesap öncekinin portföyünü görmemeli.
    if (uid != null) await PortfolioCache.clear(uid);
    await SocialAuthService.instance.signOutGoogle();
    // Yerel deneme sayaçları ve push cihaz kimliği kullanıcıya özgü izdir;
    // aynı cihazdaki bir sonraki hesaba taşınmasın (2026-09 L14).
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_rlKeyPrefix))) {
        await prefs.remove(k);
      }
      await prefs.remove(PrefKeys.pushDeviceId);
    } catch (_) {
      // Tercih deposu okunamazsa çıkış yine tamamlanır.
    }
    // Email'i cihazda bırak — sonraki girişte dolu gelsin
  }

  static String _deleteAccountKodu(dynamic data) =>
      (data is Map && data['error'] is String) ? data['error'] as String : '';

  /// `delete-account` edge function'ının 2xx dışı yanıtını kullanıcıya
  /// gösterilecek [AuthException]'a çevirir. Saf fonksiyon — hem
  /// `response.status != 200` hem `FunctionException` yolu buradan geçer
  /// (2026-09-23 denetimi U12; `test/delete_account_error_test.dart`).
  static AuthException deleteAccountHatasi(int status, dynamic data) {
    switch (_deleteAccountKodu(data)) {
      case 'invalid_password':
        return const AuthException('Şifre hatalı.');
      case 'password_required':
        return const AuthException('Şifre gerekli.');
      case 'invalid_identity':
        return const AuthException(
            'Kimlik doğrulanamadı. Aynı hesapla tekrar dene.');
    }
    return AuthException(
      'Hesap silinemedi (kod $status). '
      'Sorun devam ederse destekle iletişime geçin.',
    );
  }

  // ── Hesap silme (KVKK Madde 11 / Play 2024 / App Store 5.1.1(v)) ─────────

  /// Kullanıcının hesabını ve tüm verisini kalıcı olarak siler.
  ///
  /// Akış:
  /// 1. Şifre re-authentication (yetkisiz silmeyi engeller)
  /// 2. Supabase Edge Function `delete-account` çağrılır
  ///    → service-role ile auth.admin.deleteUser()
  ///    → CASCADE ile assets/snapshots/partnerships silinir
  ///    → account_deletion_log'a anonim kayıt (3 yıl saklanır)
  /// 3. Yerel SharedPreferences temizlenir
  /// 4. Session sonlandırılır
  ///
  /// Şifresiz (yalnızca Apple/Google) hesapta [password] yerine sağlayıcıdan
  /// TAZE bir kimlik alınır ve sunucu onu `signInWithIdToken` ile doğrular —
  /// "bu cihazı elinde tutan, hesabın da sahibi mi" sorusunun sosyal karşılığı.
  Future<void> deleteAccount({String? password}) async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException('Oturum açık değil.');
    }

    final Map<String, dynamic> body;
    if (hasPasswordIdentity) {
      if (password == null || password.isEmpty) {
        throw const AuthException('Şifre gerekli.');
      }
      body = {'password': password};
    } else {
      final provider = _socialProviderOf(user);
      if (provider == null) {
        throw const AuthException(
            'Hesabın giriş yöntemi tanınamadı. Destekle iletişime geç.');
      }
      final cred = await SocialAuthService.instance.obtain(provider);
      body = {
        'provider': provider.name,
        'id_token': cred.idToken,
        if (cred.rawNonce != null) 'nonce': cred.rawNonce,
      };
    }

    // B5 fix: Re-auth Edge Function tarafında yapılır. Mobil tarafta
    // signInWithPassword çağırmayı bıraktık — client-side re-auth
    // çalıntı cihaz senaryosunda bypass edilebilirdi (saldırgan
    // doğrudan Edge Function'a istek atabilir). Artık şifre body'de
    // server'a gider ve service-role'a admin.deleteUser çağrısı öncesi
    // server password'ü doğrular.
    try {
      final response = await _client.functions
          .invoke('delete-account', body: body)
          .timeout(const Duration(seconds: 30));
      if (response.status != 200) {
        throw deleteAccountHatasi(response.status, response.data);
      }
    } on FunctionException catch (e) {
      // 2026-09-23 denetimi U12: `functions.invoke` 2xx DIŞI her yanıtta
      // `FunctionException` fırlatır — yukarıdaki `status != 200` dalına
      // yanlış şifrede (401) hiç gelinmiyordu. Hata aşağıdaki genel
      // `catch`'e düşüyor, kullanıcı "Bir şeyler ters gitti" görüyor ve
      // yanlış şifre Crashlytics'e çökme diye gidiyordu. Sunucunun bilinen
      // hata kodları kullanıcı hatasıdır; raporlanmaz.
      //
      // status 0 = istek hiç ulaşmadı (yeni functions_client'ta
      // `FunctionsFetchException`): bağlantı yolu gibi davran.
      if (e.status == 0) {
        throw AuthException(friendlyError(e.details ?? e));
      }
      final hata = deleteAccountHatasi(e.status, e.details);
      if (_deleteAccountKodu(e.details).isEmpty && e.status >= 500) {
        // Kodsuz 5xx bizim arızamız — görünür kalsın.
        CrashReporter.report(e, StackTrace.current,
            reason: 'AuthService.deleteAccount');
      }
      throw hata;
    } on AuthException {
      rethrow;
    } catch (e, st) {
      // Bağlantı hatası KULLANICININ ağından gelir, bizim bir
      // arızamız değil: Crashlytics'e taşımak gerçek hataları
      // gürültüde gizler (bkz. `CrashReporter.agHatasiMi`) ve
      // 'Hesap silme hatası: ...' öneki kullanıcıya hiçbir şey
      // söylemez. Mesaj olduğu gibi geçer — VPN ihtimalini de
      // o cümle taşıyor (2026-09-22).
      if (baglantiHatasiMi(e)) {
        throw AuthException(friendlyError(e));
      }
      CrashReporter.report(e, st, reason: 'AuthService.deleteAccount');
      throw AuthException('Hesap silme hatası: ${friendlyError(e)}');
    }

    // 3. Local cache temizle
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {
      // local cleanup hata verirse de devam et — sunucudan silindi
    }

    // 4. Sign out (token cleanup)
    try {
      await _client.auth.signOut();
    } catch (_) {
      // user zaten silindi, signOut hata verebilir; önemli değil
    }
  }

  /// Kullanıcının hangi sosyal sağlayıcıyla bağlı olduğu (ilk eşleşen).
  SocialProvider? _socialProviderOf(User user) {
    for (final i in user.identities ?? const <UserIdentity>[]) {
      if (i.provider == 'apple') return SocialProvider.apple;
      if (i.provider == 'google') return SocialProvider.google;
    }
    return null;
  }

  // ── Ortak kodu üret ───────────────────────────────────────────────────────

  Future<String> generatePartnerCode(String fromUserId) async {
    final profile = await SupabaseService.instance.getProfile(fromUserId);
    if (profile == null) throw const AuthException('Kullanıcı bulunamadı.');

    final rng = Random.secure();
    // 10 karakterlik alphanumeric kod (büyük harf + rakam, karışık biçim)
    // ~3.6 trilyon kombinasyon — brute-force pratikte imkânsız
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ambiguous chars (0,O,1,I) çıkarıldı
    String genPart(int len) =>
        List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
    final shortCode = '${genPart(5)}-${genPart(5)}';

    final expiresAt = DateTime.now().add(const Duration(hours: 24));
    final inviteId = _uuid.v4();

    // A7 fix: Payload artık PII taşımıyor — UUID, isim ve email kaldırıldı.
    // Server, daveti `code` üzerinden kendi tablosundan bulur.
    // Geriye kalan: yalnızca zaman damgaları (oluşturma, geçerlilik).
    final payloadJson = jsonEncode({
      't': DateTime.now().millisecondsSinceEpoch,
      'x': expiresAt.millisecondsSinceEpoch,
    });

    await SupabaseService.instance.insertInvite(
      id: inviteId,
      fromUserId: fromUserId,
      code: shortCode,
      payload: payloadJson,
      expiresAt: expiresAt,
    );

    return shortCode;
  }

  // ── Ortak kodunu kullan (onay bekleme akışı) ─────────────────────────────
  // Döner: (inviteId, fromUserDisplayName)
  // Partnership KURULMAZ — sadece invite'a to_user_id yazılır.
  // Kod sahibi onayladıktan sonra acceptInvite() çağrılır.

  Future<({String inviteId, String partnerName})> submitPartnerCode({
    required String currentUserId,
    required String code,
  }) async {
    final trimmed = code.trim().toUpperCase();
    final codePattern = RegExp(r'^([A-Z2-9]{5}-[A-Z2-9]{5})$');
    if (!codePattern.hasMatch(trimmed)) {
      throw const AuthException(
          'Geçersiz kod formatı. XXXXX-XXXXX biçiminde girin.');
    }

    // Rate-limit: son 10 dakikada 5 başarısız deneme → blokla
    await _checkRateLimit(currentUserId);

    // A1+A2 fix: davet doğrulama service-role ile Edge Function'da yapılır.
    // İstemci artık partner_invites tablosunu doğrudan okumaz/yazmaz.
    try {
      final response = await _client.functions
          .invoke('redeem-invite-code', body: {'code': trimmed})
          .timeout(const Duration(seconds: 15));

      final data = response.data;
      if (response.status == 200 && data is Map) {
        await _clearAttempts(currentUserId);
        try {
          await SupabaseService.instance
              .sendPartnerInvitePush(data['invite_id'] as String);
        } catch (_) {}
        return (
          inviteId: data['invite_id'] as String,
          partnerName:
              (data['partner_display_name'] as String?)?.trim().isNotEmpty == true
                  ? data['partner_display_name'] as String
                  : 'Kullanıcı',
        );
      }

      final errCode = _extractErrorCode(data);
      await _recordIfFailedGuess(currentUserId, errCode);
      throw _inviteException(errCode, data);
    } on FunctionException catch (e) {
      final errCode = _extractErrorCode(e.details);
      await _recordIfFailedGuess(currentUserId, errCode);
      throw _inviteException(errCode, e.details);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
  }

  String _extractErrorCode(dynamic data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return '';
  }

  /// Hata kodundan uygun istisnayı kurar. `rate_limited` durumunda
  /// kalan saniyeyi de taşıyan [RateLimitedException] döner — UI
  /// geri sayım gösterip süre dolunca alanı kendisi açabilsin diye.
  AuthException _inviteException(String code, [dynamic data]) {
    final message = _translateInviteError(code, data);
    if (code == 'rate_limited') {
      return RateLimitedException(message, _retryAfterSeconds(data));
    }
    return AuthException(message);
  }

  /// Sunucunun döndüğü `retry_after_seconds`; yoksa güvenli varsayılan.
  int _retryAfterSeconds(dynamic data) {
    if (data is Map && data['retry_after_seconds'] is num) {
      final v = (data['retry_after_seconds'] as num).toInt();
      if (v > 0) return v;
    }
    return 600;
  }

  String _translateInviteError(String code, [dynamic data]) {
    switch (code) {
      case 'rate_limited':
        // Sunucu taraflı limit (S1 fix). İstemcideki SharedPreferences
        // sayacı yalnızca gereksiz ağ isteğini önleyen bir UX katmanıdır;
        // gerçek sınır burada, sunucudan gelir.
        return 'Çok fazla başarısız deneme. '
            '${_formatRetryAfter(data)} sonra tekrar dene.';
      case 'rate_limit_unavailable':
        return 'Güvenlik kontrolü şu an yapılamıyor. Birazdan tekrar dene.';
      case 'invalid_code_format':
        return 'Kodu XXXXX-XXXXX biçiminde gir.';
      case 'invite_not_found_or_expired':
        return 'Kod bulunamadı ya da süresi dolmuş. Ortağından yeni bir kod iste.';
      case 'cannot_use_own_code':
        return 'Kendi ürettiğin kodu kullanamazsın.';
      case 'already_claimed':
        return 'Bu kod başka bir kullanıcı tarafından kullanılıyor.';
      case 'already_partners':
        return 'Bu kullanıcı zaten ortağın. Ortaklarım listende görebilirsin.';
      default:
        return 'Davet doğrulanamadı. Tekrar dene.';
    }
  }

  /// Saniyeyi okunabilir Türkçe süreye çevirir ("45 saniye", "3 dakika").
  /// Dakikaya yukarı yuvarlar: aşağı yuvarlamak kullanıcıyı erken
  /// denemeye itip yeni bir ret almasına yol açar.
  static String _formatDuration(int seconds) {
    if (seconds <= 60) return '$seconds saniye';
    final minutes = (seconds / 60).ceil();
    return '$minutes dakika';
  }

  /// Sunucunun döndüğü `retry_after_seconds` değerini okunabilir
  /// Türkçe süreye çevirir. Değer yoksa güvenli varsayılan: 10 dakika.
  String _formatRetryAfter(dynamic data) {
    int? seconds;
    if (data is Map && data['retry_after_seconds'] is num) {
      seconds = (data['retry_after_seconds'] as num).toInt();
    }
    return _formatDuration(seconds ?? 600);
  }


  // ── Kod sahibi onayladı → partnership kur (Edge Function) ────────────────

  Future<void> acceptInvite({
    required String inviteId,
    required String currentUserId,
  }) async {
    await _invokeInviteAction(inviteId: inviteId, action: 'accept');
  }

  // ── Kod sahibi reddetti (Edge Function) ──────────────────────────────────

  Future<void> rejectInvite({
    required String inviteId,
    required String currentUserId,
  }) async {
    await _invokeInviteAction(inviteId: inviteId, action: 'reject');
  }

  Future<void> _invokeInviteAction({
    required String inviteId,
    required String action,
  }) async {
    try {
      final response = await _client.functions
          .invoke('accept-invite', body: {
            'invite_id': inviteId,
            'action': action,
          })
          .timeout(const Duration(seconds: 15));
      if (response.status == 200) return;
      throw AuthException(
          _translateAcceptError(_extractErrorCode(response.data), action));
    } on FunctionException catch (e) {
      throw AuthException(
          _translateAcceptError(_extractErrorCode(e.details), action));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Bağlantı kurulamadı. İnternetini kontrol et.');
    }
  }

  String _translateAcceptError(String code, [String action = 'accept']) {
    final isReject = action == 'reject';
    switch (code) {
      case 'invite_not_found':
        return 'Davet bulunamadı. Sayfayı yenileyip tekrar dene.';
      case 'forbidden':
        return isReject
            ? 'Bu daveti iptal etme yetkin yok.'
            : 'Bu daveti işleme yetkin yok.';
      case 'already_processed':
        return isReject
            ? 'Bu davet zaten sonuçlanmış.'
            : 'Bu davet zaten yanıtlanmış.';
      case 'expired':
        return 'Davetin süresi dolmuş. Yeni bir kod üretmen gerekiyor.';
      case 'no_target':
        return 'Davet henüz kimseye gönderilmemiş.';
      // Sunucu, kodu gerçekten girilmemiş (redeem edilmemiş) daveti onaylamaz
      // (0073 / accept-invite C1 kapısı).
      case 'not_redeemed':
        return 'Bu davet henüz kod girilerek talep edilmemiş.';
      default:
        return isReject
            ? 'İptal işlemi tamamlanamadı. Tekrar dene.'
            : 'İşlem tamamlanamadı. Tekrar dene.';
    }
  }

  // ── Rate limiting (yalnızca UX katmanı) ─────────────────────────────────
  //
  // ⚠️ Bu sayaç bir GÜVENLİK sınırı DEĞİLDİR. SharedPreferences istemcide
  // durur: uygulama verisi silinerek sıfırlanabilir, ya da Edge Function'a
  // doğrudan istek atılarak tamamen atlanabilir. Tek işlevi, kilitli
  // olduğu bilinen bir kullanıcı için gereksiz ağ isteğini önlemektir.
  //
  // Gerçek sınır sunucudadır: `check_and_record_rate_limit` RPC'si
  // (migration 0028) ve onu çağıran `redeem-invite-code` Edge Function.
  // Sunucu limiti aştığında 429 + `rate_limited` döner.

  static const _maxAttempts = 5;
  static const _windowMinutes = 10;
  static const _rlKeyPrefix = 'rl_attempts_';

  /// Yerel sayaca göre kalan kilit süresi (saniye); kilit yoksa 0.
  ///
  /// Ekran ilk açıldığında geri sayımı kurabilmek için gerekir: kilit
  /// önceki oturumda oluşmuşsa kullanıcı hiçbir şey denemeden de
  /// kalan süreyi görebilmeli.
  ///
  /// NOT: Yalnızca yerel sayacı okur. Sunucudaki gerçek kilit daha
  /// uzun olabilir; o durum ilk denemede 429 ile netleşir.
  Future<int> partnerCodeLockRemainingSeconds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_rlKeyPrefix${userId.hashCode}') ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = const Duration(minutes: _windowMinutes).inMilliseconds;
    final recent = stored
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .where((ms) => ms >= now - windowMs)
        .toList()
      ..sort();
    if (recent.length < _maxAttempts) return 0;
    final remainingMs = (recent.first + windowMs) - now;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  /// Yalnızca GERÇEK tahmin hatası sayacı artırır — sunucudaki
  /// `recordFailedGuess` ile aynı ayrım (S8).
  ///
  /// `invite_not_found_or_expired` dışındaki hatalar kullanıcı
  /// hatasıdır (kendi kodu, zaten ortak, zaten talep edilmiş): kod
  /// DOĞRU bulunmuştur, saymak meşru kullanıcıyı kilitler.
  /// `rate_limited` de sayılmaz — zaten kilitliyken sayacı büyütmek
  /// pencereyi süresiz uzatırdı.
  static const _countedErrorCodes = {'invite_not_found_or_expired'};

  Future<void> _recordIfFailedGuess(String key, String errCode) async {
    if (!_countedErrorCodes.contains(errCode)) return;
    await _recordAttempt(key);
  }

  Future<void> _recordAttempt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = '$_rlKeyPrefix${key.hashCode}';
    final stored = prefs.getStringList(prefKey) ?? [];
    stored.add(DateTime.now().millisecondsSinceEpoch.toString());
    await prefs.setStringList(prefKey, stored);
  }

  Future<void> _checkRateLimit(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = '$_rlKeyPrefix${key.hashCode}';
    final stored = prefs.getStringList(prefKey) ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - const Duration(minutes: _windowMinutes).inMilliseconds;
    final recent = stored
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .where((ms) => ms >= cutoff)
        .toList()
      ..sort();
    await prefs.setStringList(
        prefKey, recent.map((ms) => ms.toString()).toList());

    if (recent.length >= _maxAttempts) {
      // Kalan süre = en eski denemenin pencereden düşmesine kalan zaman.
      // Sabit "10 dakika" demek yanıltıcıydı: kullanıcı 9 dakika beklemiş
      // olsa bile yine 10 dakika bekleyeceğini sanıyordu.
      final windowMs = const Duration(minutes: _windowMinutes).inMilliseconds;
      final remainingMs = (recent.first + windowMs) - now;
      final seconds = (remainingMs / 1000).ceil().clamp(1, windowMs ~/ 1000);
      throw RateLimitedException(
        'Çok fazla başarısız deneme. '
        '${_formatDuration(seconds)} sonra tekrar deneyin.',
        seconds,
      );
    }
  }

  Future<void> _clearAttempts(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_rlKeyPrefix${key.hashCode}');
  }

  // A7 fix: payload artık PII içermediği için XOR obfuscation kaldırıldı.
}
