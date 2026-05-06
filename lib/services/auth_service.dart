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
    if (password.length < 6) {
      throw const AuthException('Şifre en az 6 karakter olmalı.');
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
        throw const AuthException('Bu e-posta zaten kayıtlı.');
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

      await _saveEmail(normalizedEmail);
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

    // Payload sadece kimlik bilgisi taşır — varlık verisi taşınmaz
    final payloadJson = jsonEncode({
      'i': fromUserId,
      'n': profile.displayName,
      't': DateTime.now().millisecondsSinceEpoch,
      'x': expiresAt.millisecondsSinceEpoch,
    });
    final encoded = base64Url
        .encode(_obfuscate(utf8.encode(payloadJson)))
        .replaceAll('=', '');

    await SupabaseService.instance.insertInvite(
      id: inviteId,
      fromUserId: fromUserId,
      code: shortCode,
      payload: encoded,
      expiresAt: expiresAt,
    );

    return '$shortCode:$encoded';
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

    // XXXXX-XXXXX formatı veya tam kod (XXXXX-XXXXX:payload)
    String? shortCode;
    final codePattern = RegExp(r'^([A-Z2-9]{5}-[A-Z2-9]{5})');
    final match = codePattern.firstMatch(trimmed);
    if (match != null) shortCode = match.group(1);

    if (shortCode == null) {
      throw const AuthException('Geçersiz kod formatı. XXXXX-XXXXX biçiminde girin.');
    }

    // Rate-limit: son 10 dakikada 5'ten fazla başarısız deneme → blokla
    _checkRateLimit(currentUserId);

    final invite = await SupabaseService.instance.getValidInvite(shortCode);
    if (invite == null) {
      _recordAttempt(currentUserId);
      throw const AuthException('Kod bulunamadı veya süresi dolmuş.');
    }

    // Kod doğru — sayacı sıfırla
    _failedAttempts.remove(currentUserId);

    final fromUserId = invite['from_user_id'] as String;
    if (fromUserId == currentUserId) {
      throw const AuthException('Kendi kodunuzu kullanamazsınız.');
    }

    // Zaten pending bir istek var mı?
    final existingStatus = invite['status'] as String?;
    if (existingStatus == 'pending' && invite['to_user_id'] != null) {
      throw const AuthException(
          'Bu kod zaten başka bir kullanıcı tarafından kullanılıyor.');
    }

    final alreadyLinked = await SupabaseService.instance
        .partnershipExists(currentUserId, fromUserId);
    if (alreadyLinked) {
      throw const AuthException('Bu kullanıcı zaten ortağınız.');
    }

    // Invite'a to_user_id yaz — partnership henüz kurulmadı
    final requesterProfile =
        await SupabaseService.instance.getProfile(currentUserId);
    final requesterName =
        requesterProfile?.displayName.trim().isNotEmpty == true
            ? requesterProfile!.displayName.trim()
            : 'Kullanici';

    await SupabaseService.instance.setInviteTarget(
      inviteId: invite['id'] as String,
      toUserId: currentUserId,
      requesterName: requesterName,
    );

    try {
      await SupabaseService.instance
          .sendPartnerInvitePush(invite['id'] as String);
    } catch (_) {
      // Push altyapisi henuz hazir degilse davet yine de olusturulsun.
    }

    // Payload'dan ortak profilini çek ve profiles tablosuna yaz
    AppUser? partnerProfile;
    try {
      partnerProfile = await SupabaseService.instance.getProfile(fromUserId);
    } catch (_) {}

    if (partnerProfile == null) {
      try {
        final payload = invite['payload'] as String?;
        if (payload != null) {
          final decoded = _decodePayload(payload);
          if (decoded != null) {
            final name = decoded['n'] as String? ?? 'Kullanıcı';
            final email = decoded['e'] as String? ?? '';
            partnerProfile = AppUser(
              id: fromUserId,
              email: email,
              displayName: name,
              createdAt: DateTime.now(),
            );
            await SupabaseService.instance.upsertProfile(partnerProfile);
          }
        }
      } catch (_) {}
    }

    return (
      inviteId: invite['id'] as String,
      partnerName: partnerProfile?.displayName ?? 'Kullanıcı',
    );
  }

  // ── Kod sahibi onayladı → partnership kur ────────────────────────────────

  Future<void> acceptInvite({
    required String inviteId,
    required String currentUserId,
  }) async {
    final invite = await SupabaseService.instance.getInviteById(inviteId);
    if (invite == null) throw const AuthException('Davet bulunamadı.');

    final fromUserId = invite['from_user_id'] as String;
    final toUserId = invite['to_user_id'] as String?;
    if (toUserId == null) throw const AuthException('Davet hedefi yok.');

    if (fromUserId != currentUserId) {
      throw const AuthException('Bu daveti onaylama yetkiniz yok.');
    }

    await SupabaseService.instance.acceptInvite(inviteId);
    await SupabaseService.instance.insertPartnership(
      id: _uuid.v4(),
      userId1: fromUserId,
      userId2: toUserId,
    );
  }

  // ── Kod sahibi reddetti ───────────────────────────────────────────────────

  Future<void> rejectInvite({
    required String inviteId,
    required String currentUserId,
  }) async {
    final invite = await SupabaseService.instance.getInviteById(inviteId);
    if (invite == null) throw const AuthException('Davet bulunamadı.');
    if (invite['from_user_id'] != currentUserId) {
      throw const AuthException('Bu daveti reddetme yetkiniz yok.');
    }
    await SupabaseService.instance.rejectInvite(inviteId);
  }

  // ── Rate limiting ─────────────────────────────────────────────────────────

  // userId → başarısız deneme zamanları listesi
  final Map<String, List<DateTime>> _failedAttempts = {};
  static const _maxAttempts = 5;
  static const _windowMinutes = 10;

  void _recordAttempt(String userId) {
    _failedAttempts.putIfAbsent(userId, () => []).add(DateTime.now());
  }

  void _checkRateLimit(String userId) {
    final attempts = _failedAttempts[userId];
    if (attempts == null) return;
    final cutoff = DateTime.now().subtract(const Duration(minutes: _windowMinutes));
    // Eski denemeleri temizle
    attempts.removeWhere((t) => t.isBefore(cutoff));
    if (attempts.length >= _maxAttempts) {
      throw const AuthException(
        'Çok fazla başarısız deneme. 10 dakika sonra tekrar deneyin.',
      );
    }
  }

  // ── Obfuscation ───────────────────────────────────────────────────────────

  List<int> _obfuscate(List<int> bytes) {
    const key = [0x50, 0x54, 0x4B, 0x32, 0x30, 0x32, 0x34];
    return List<int>.generate(
        bytes.length, (i) => bytes[i] ^ key[i % key.length]);
  }

  Map<String, dynamic>? _decodePayload(String encoded) {
    try {
      // Padding geri ekle
      final padded = encoded.padRight(
          encoded.length + (4 - encoded.length % 4) % 4, '=');
      final bytes = base64Url.decode(padded);
      final deobfuscated = _obfuscate(bytes);
      final json = utf8.decode(deobfuscated);
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
