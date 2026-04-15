import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import 'database_service.dart';

const _uuid = Uuid();

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _sessionKey = 'current_user_id';

  // ── Şifre hash ────────────────────────────────────────────────────────────

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
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

    final existing = await DatabaseService.instance.getUserByEmail(normalizedEmail);
    if (existing != null) {
      throw const AuthException('Bu e-posta zaten kayıtlı.');
    }

    final user = AppUser(
      id: _uuid.v4(),
      email: normalizedEmail,
      displayName: displayName.trim(),
      passwordHash: _hashPassword(password),
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.insertUser(user);
    await _saveSession(user.id);
    return user;
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final user = await DatabaseService.instance.getUserByEmail(normalizedEmail);
    if (user == null) {
      throw const AuthException('E-posta veya şifre hatalı.');
    }
    if (user.passwordHash != _hashPassword(password)) {
      throw const AuthException('E-posta veya şifre hatalı.');
    }
    await _saveSession(user.id);
    return user;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  // ── Session ───────────────────────────────────────────────────────────────

  Future<String?> getSavedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  Future<AppUser?> getSessionUser() async {
    final id = await getSavedUserId();
    if (id == null) return null;
    return DatabaseService.instance.getUserById(id);
  }

  Future<void> _saveSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, userId);
  }

  // ── OTP Kodu üret ─────────────────────────────────────────────────────────

  /// 6 haneli OTP kodu üretir, 10 dakika geçerli.
  Future<String> generatePartnerCode(String fromUserId) async {
    final rng = Random.secure();
    final code = (rng.nextInt(900000) + 100000).toString(); // 100000–999999
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));

    await DatabaseService.instance.insertInvite(
      id: _uuid.v4(),
      fromUserId: fromUserId,
      code: code,
      expiresAt: expiresAt,
    );
    return code;
  }

  // ── OTP Kodu kullan ───────────────────────────────────────────────────────

  /// [currentUserId] kodu giren kullanıcı, [code] 6 haneli OTP.
  /// Başarılıysa partnerin displayName'ini döner.
  Future<String> redeemPartnerCode({
    required String currentUserId,
    required String code,
  }) async {
    final invite = await DatabaseService.instance.getValidInvite(code.trim());
    if (invite == null) {
      throw const AuthException('Geçersiz veya süresi dolmuş kod.');
    }

    final fromUserId = invite['from_user_id'] as String;
    if (fromUserId == currentUserId) {
      throw const AuthException('Kendi kodunuzu kullanamazsınız.');
    }

    final alreadyLinked = await DatabaseService.instance
        .partnershipExists(currentUserId, fromUserId);
    if (alreadyLinked) {
      throw const AuthException('Bu kullanıcı zaten ortağınız.');
    }

    await DatabaseService.instance.markInviteUsed(invite['id'] as String);
    await DatabaseService.instance.insertPartnership(
      id: _uuid.v4(),
      userId1: fromUserId,
      userId2: currentUserId,
    );

    final partner = await DatabaseService.instance.getUserById(fromUserId);
    return partner?.displayName ?? 'Ortak';
  }
}
