import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import 'db_logger.dart';
import 'supabase_service.dart';

const _uuid = Uuid();
const _savedEmailKey = 'saved_email';
const _pendingDisplayNameKey = 'pending_display_name';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
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
    if (!RegExp(r'[A-Za-zğüşıöçĞÜŞİÖÇ]').hasMatch(password)) {
      return 'Şifre en az bir harf içermeli.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Şifre en az bir rakam içermeli.';
    }
    return null;
  }

  // ── Mevcut oturum ──────────────────────────────────────────────────────────

  Future<AppUser?> getSessionUser() async {
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
      if (e.message.contains('already registered') ||
          e.message.contains('User already registered')) {
        throw const AuthException(
          'Bu e-posta zaten kayıtlı. Giriş yapmayı deneyin.',
        );
      }
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Kayıt hatası: $e');
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
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Doğrulama hatası: $e');
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
            'Çok sık kod istediniz. 60 saniye bekleyip tekrar deneyin.');
      }
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Kod gönderilemedi: $e');
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
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Giriş hatası: $e');
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
    } catch (e) {
      throw AuthException('Şifre sıfırlama isteği başarısız: ${_safe(e)}');
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
    if (otp.trim().isEmpty) {
      throw const AuthException('Kod girin.');
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
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Şifre güncelleme hatası: ${_safe(e)}');
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _log.log<void>(
      source: 'AuthService.logout',
      table: 'auth/sign-out',
      op: 'RPC',
      request: {},
      call: () => _client.auth.signOut(),
    );
    // Email'i cihazda bırak — sonraki girişte dolu gelsin
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
  Future<void> deleteAccount({required String password}) async {
    final user = _client.auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException('Oturum açık değil.');
    }

    // B5 fix: Re-auth Edge Function tarafında yapılır. Mobil tarafta
    // signInWithPassword çağırmayı bıraktık — client-side re-auth
    // çalıntı cihaz senaryosunda bypass edilebilirdi (saldırgan
    // doğrudan Edge Function'a istek atabilir). Artık şifre body'de
    // server'a gider ve service-role'a admin.deleteUser çağrısı öncesi
    // server password'ü doğrular.
    try {
      final response = await _client.functions
          .invoke('delete-account', body: {'password': password})
          .timeout(const Duration(seconds: 30));
      if (response.status == 200) {
        // başarılı
      } else {
        final data = response.data;
        final errCode =
            (data is Map && data['error'] is String) ? data['error'] as String : '';
        if (errCode == 'invalid_password') {
          throw const AuthException('Şifre hatalı.');
        }
        if (errCode == 'password_required') {
          throw const AuthException('Şifre gerekli.');
        }
        throw AuthException(
          'Hesap silinemedi (kod ${response.status}). '
          'Sorun devam ederse destekle iletişime geçin.',
        );
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Hesap silme hatası: ${_safe(e)}');
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
      await _recordAttempt(currentUserId);
      throw AuthException(_translateInviteError(errCode));
    } on FunctionException catch (e) {
      await _recordAttempt(currentUserId);
      throw AuthException(_translateInviteError(_extractErrorCode(e.details)));
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

  String _translateInviteError(String code) {
    switch (code) {
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

  String _safe(Object e) {
    final s = e.toString();
    if (s.length > 100) return s.substring(0, 100);
    return s;
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
      default:
        return isReject
            ? 'İptal işlemi tamamlanamadı. Tekrar dene.'
            : 'İşlem tamamlanamadı. Tekrar dene.';
    }
  }

  // ── Rate limiting (SharedPreferences — uygulama yeniden başlayınca sıfırlanmaz) ──

  static const _maxAttempts = 5;
  static const _windowMinutes = 10;
  static const _rlKeyPrefix = 'rl_attempts_';

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
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: _windowMinutes))
        .millisecondsSinceEpoch;
    final recent = stored.where((s) {
      final ms = int.tryParse(s);
      return ms != null && ms >= cutoff;
    }).toList();
    await prefs.setStringList(prefKey, recent);
    if (recent.length >= _maxAttempts) {
      throw const AuthException(
        'Çok fazla başarısız deneme. 10 dakika sonra tekrar deneyin.',
      );
    }
  }

  Future<void> _clearAttempts(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_rlKeyPrefix${key.hashCode}');
  }

  // A7 fix: payload artık PII içermediği için XOR obfuscation kaldırıldı.
}
