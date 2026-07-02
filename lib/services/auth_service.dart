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

      // Email confirmation gerekiyorsa session olmayabilir — yine de profile oluştur
      if (response.session == null) {
        throw const AuthException(
            'Kayıt başarılı! E-posta adresinize doğrulama maili gönderildi. '
            'Lütfen mailinizi onaylayıp giriş yapın.');
      }

      final user = AppUser(
        id: response.user!.id,
        email: normalizedEmail,
        displayName: displayName.trim(),
        createdAt: DateTime.now(),
      );

      await SupabaseService.instance.upsertProfile(user);
      await _saveEmail(normalizedEmail);
      return user;
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      if (e.message.contains('already registered') ||
          e.message.contains('User already registered')) {
        // H2: Hesap tespitini (account enumeration) önlemek için
        // "zaten kayıtlı" mesajı yerine generic yanıt — saldırgan
        // hangi email'in sistemde olduğunu öğrenemez.
        throw const AuthException(
          'Kayıt işlemi tamamlandı. E-posta adresinizi kontrol edin.',
        );
      }
      throw AuthException(e.message);
    } catch (e) {
      throw AuthException('Kayıt hatası: $e');
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

      // B3: E-posta doğrulama server-side kontrolü
      // emailConfirmedAt null ise kullanıcı doğrulama bağlantısına tıklamamış demektir.
      if (response.user!.emailConfirmedAt == null) {
        await _client.auth.signOut();
        throw const AuthException(
          'E-posta adresin doğrulanmamış. Gelen kutunu kontrol edip doğrulama bağlantısına tıkla.',
        );
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

      final status = response.status;
      final data = response.data;
      if (status == 200 && data is Map) {
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

      // Edge function hata kodları
      final errCode =
          (data is Map && data['error'] is String) ? data['error'] as String : '';
      await _recordAttempt(currentUserId);
      throw AuthException(_translateInviteError(errCode));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Davet doğrulanamadı: ${_safe(e)}');
    }
  }

  String _translateInviteError(String code) {
    switch (code) {
      case 'invalid_code_format':
        return 'Geçersiz kod formatı.';
      case 'invite_not_found_or_expired':
        return 'Kod bulunamadı veya süresi dolmuş.';
      case 'cannot_use_own_code':
        return 'Kendi kodunuzu kullanamazsınız.';
      case 'already_claimed':
        return 'Bu kod zaten başka bir kullanıcı tarafından kullanılıyor.';
      case 'already_partners':
        return 'Bu kullanıcı zaten ortağınız.';
      default:
        return 'Davet doğrulanamadı.';
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

      final data = response.data;
      final errCode =
          (data is Map && data['error'] is String) ? data['error'] as String : '';
      throw AuthException(_translateAcceptError(errCode));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('İşlem tamamlanamadı: ${_safe(e)}');
    }
  }

  String _translateAcceptError(String code) {
    switch (code) {
      case 'invite_not_found':
        return 'Davet bulunamadı.';
      case 'forbidden':
        return 'Bu daveti işleme yetkiniz yok.';
      case 'already_processed':
        return 'Bu davet zaten işlenmiş.';
      case 'expired':
        return 'Davet süresi dolmuş.';
      case 'no_target':
        return 'Davet hedefi tanımlı değil.';
      default:
        return 'İşlem başarısız.';
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
