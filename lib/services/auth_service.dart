import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import 'database_service.dart';

const _uuid = Uuid();
const adminEmail = 'vasin_dirali@hotmail.com';

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

  // ── Şifre hash (Salted SHA-256) ──────────────────────────────────────────

  String _hashPassword(String password, String email) {
    // Email'i tuz (salt) olarak kullanarak gökkuşağı tablolarını imkansız kıl
    final salt = email.toLowerCase().trim();
    final bytes = utf8.encode(password + salt);
    return sha256.convert(bytes).toString();
  }

  String _hashPasswordEmailFirst(String password, String email) {
    final salt = email.toLowerCase().trim();
    final bytes = utf8.encode(salt + password);
    return sha256.convert(bytes).toString();
  }

  String _hashPasswordRaw(String password, String email) {
    final bytes = utf8.encode(password + email);
    return sha256.convert(bytes).toString();
  }

  String _hashPasswordRawEmailFirst(String password, String email) {
    final bytes = utf8.encode(email + password);
    return sha256.convert(bytes).toString();
  }

  /// Eski hash yöntemi (Geriye dönük uyumluluk için)
  String _legacyHash(String password) {
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

    final existing =
        await DatabaseService.instance.getUserByEmail(normalizedEmail);
    if (existing != null) {
      throw const AuthException('Bu e-posta zaten kayıtlı.');
    }

    final user = AppUser(
      id: _uuid.v4(),
      email: normalizedEmail,
      displayName: displayName.trim(),
      passwordHash: _hashPassword(password, normalizedEmail),
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.insertUser(user);
    await _saveSession(user.id);
    return user;
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  bool isAdmin(String email) => email.toLowerCase().trim() == adminEmail;

  List<String> _candidateHashes({
    required String email,
    required String rawEmail,
    required String password,
  }) {
    final normalizedEmail = email.toLowerCase().trim();
    final trimmedRawEmail = rawEmail.trim();

    return {
      _hashPassword(password, normalizedEmail),
      _hashPasswordEmailFirst(password, normalizedEmail),
      if (trimmedRawEmail.isNotEmpty) _hashPassword(password, trimmedRawEmail),
      if (trimmedRawEmail.isNotEmpty)
        _hashPasswordEmailFirst(password, trimmedRawEmail),
      if (trimmedRawEmail.isNotEmpty)
        _hashPasswordRaw(password, trimmedRawEmail),
      if (trimmedRawEmail.isNotEmpty)
        _hashPasswordRawEmailFirst(password, trimmedRawEmail),
      _legacyHash(password),
    }.toList();
  }

  Future<void> _recoverLegacyDataForUser(AppUser user) async {
    final users = await DatabaseService.instance.getAllUsers();
    if (users.length != 2) return;

    final first = users.first;
    final second = users.last;
    final orphanedAssets = await DatabaseService.instance.countOrphanedAssets();
    if (orphanedAssets == 0) return;

    final firstCount =
        await DatabaseService.instance.countAssetsForUser(first.id);
    final secondCount =
        await DatabaseService.instance.countAssetsForUser(second.id);

    if (firstCount == 0 && secondCount > 0) {
      await DatabaseService.instance.claimOrphanedAssets(first.id);
      return;
    }

    if (secondCount == 0 && firstCount > 0) {
      await DatabaseService.instance.claimOrphanedAssets(second.id);
    }
  }

  Future<void> _recoverLegacyPartnerships() async {
    final users = await DatabaseService.instance.getAllUsers();
    if (users.length != 2) return;

    final first = users.first;
    final second = users.last;

    final alreadyLinked =
        await DatabaseService.instance.partnershipExists(first.id, second.id);
    if (alreadyLinked) return;

    final inviteSenderCount = await DatabaseService.instance
        .countDistinctInviteSenders([first.id, second.id]);
    if (inviteSenderCount < 2) return;

    await DatabaseService.instance.insertPartnership(
      id: _uuid.v4(),
      userId1: first.id,
      userId2: second.id,
    );
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final isAdminUser = normalizedEmail == adminEmail;

    var user = await DatabaseService.instance.getUserByEmail(normalizedEmail);

    // Admin: hesap yoksa otomatik oluştur, şifre sorma
    if (isAdminUser) {
      if (user == null) {
        user = AppUser(
          id: 'admin:$adminEmail',
          email: normalizedEmail,
          displayName: 'Admin',
          passwordHash: '',
          createdAt: DateTime.now(),
        );
        await DatabaseService.instance.insertUser(user);
      }
      await _recoverLegacyDataForUser(user);
      await _recoverLegacyPartnerships();
      await _saveSession(user.id);
      return user;
    }

    if (user == null) {
      throw const AuthException(
          'Bu e-posta için bu cihazda kayıtlı kullanıcı bulunamadı.');
    }

    final candidateHashes = _candidateHashes(
      email: normalizedEmail,
      rawEmail: email,
      password: password,
    );
    final currentHash = _hashPassword(password, normalizedEmail);

    if (candidateHashes.contains(user.passwordHash)) {
      final updatedUser = AppUser(
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        passwordHash: currentHash,
        createdAt: user.createdAt,
      );
      await DatabaseService.instance.updateUser(updatedUser);
      await _recoverLegacyDataForUser(updatedUser);
      await _recoverLegacyPartnerships();
      await _saveSession(user.id);
      return updatedUser;
    }

    throw const AuthException('E-posta veya şifre hatalı.');
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
    final user = await DatabaseService.instance.getUserById(id);
    if (user == null) return null;

    await _recoverLegacyDataForUser(user);
    await _recoverLegacyPartnerships();
    return user;
  }

  Future<void> _saveSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, userId);
  }

  // ── Ortak kodu üret ───────────────────────────────────────────────────────

  /// 6 haneli görsel kod üretir; tam paylaşım kodu "XXXXXX:base64" formatında
  /// döner. UI 6 haneyi gösterir, kopyala butonu tam kodu paylaşır.
  Future<String> generatePartnerCode(String fromUserId) async {
    final user = await DatabaseService.instance.getUserById(fromUserId);
    if (user == null) throw const AuthException('Kullanıcı bulunamadı.');

    final rng = Random.secure();
    final shortCode = (rng.nextInt(900000) + 100000).toString();
    final expiresAt = DateTime.now().add(const Duration(hours: 24));

    // Aynı cihazdaki DB araması için kaydet
    await DatabaseService.instance.insertInvite(
      id: _uuid.v4(),
      fromUserId: fromUserId,
      code: shortCode,
      expiresAt: expiresAt,
    );

    // Farklı cihazlar için kullanıcı verilerini ve varlıkları encode et
    final assets = await DatabaseService.instance.fetchByUser(fromUserId);
    final payload = jsonEncode({
      'c': shortCode,
      'i': user.id,
      'n': user.displayName,
      'e': user.email,
      't': DateTime.now().millisecondsSinceEpoch,
      'x': expiresAt.millisecondsSinceEpoch,
      'a': assets.map((a) => a.toMap()).toList(), // varlık anlık görüntüsü
    });
    final encoded =
        base64Url.encode(_obfuscate(utf8.encode(payload))).replaceAll('=', '');

    // "XXXXXX:base64payload" — UI bu formatı işler
    return '$shortCode:$encoded';
  }

  // ── Ortak kodunu kullan ───────────────────────────────────────────────────

  /// Her formattaki kodu kabul eder ve uygun yöntemi seçer.
  /// Desteklenen formatlar:
  ///   "123456"                                 → aynı cihaz DB
  ///   "123456:eyJ..."                           → farklı cihaz base64
  ///   "PortfoyTakip ortak daveti: 123456:eyJ..." → paylaş metninin tamamı
  Future<String> redeemPartnerCode({
    required String currentUserId,
    required String code,
  }) async {
    final trimmed = code.trim();

    // Saf 6 haneli → aynı cihaz DB araması
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return _redeemFromDB(currentUserId, trimmed);
    }

    // Metin içinde "XXXXXX:base64" kalıbını bul (paylaşım metni olsa bile)
    final match = RegExp(r'(\d{6}):([A-Za-z0-9_\-]+)').firstMatch(trimmed);
    if (match != null) {
      return _redeemFromEncoded(currentUserId, match.group(2)!);
    }

    // Saf base64 olabilir
    return _redeemFromEncoded(currentUserId, trimmed);
  }

  Future<String> _redeemFromDB(String currentUserId, String code) async {
    final invite = await DatabaseService.instance.getValidInvite(code);
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

  Future<String> _redeemFromEncoded(
      String currentUserId, String encoded) async {
    Map<String, dynamic> data;
    try {
      final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
      final rawBytes = base64Url.decode(padded);
      final decoded = utf8.decode(_obfuscate(rawBytes));
      data = jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException('Geçersiz kod formatı.');
    }

    final fromUserId = data['i'] as String? ?? '';
    final displayName = data['n'] as String? ?? 'Ortak';
    final email = data['e'] as String? ?? '';
    final ts = data['t'] as int? ?? 0;

    if (fromUserId.isEmpty) throw const AuthException('Geçersiz kod.');

    // Payload'daki kesin expiry'yi kullan, yoksa t'den 24 saat hesapla
    final xMs = data['x'] as int?;
    final expiresAt = xMs != null
        ? DateTime.fromMillisecondsSinceEpoch(xMs)
        : DateTime.fromMillisecondsSinceEpoch(ts)
            .add(const Duration(hours: 24));
    if (DateTime.now().isAfter(expiresAt)) {
      throw const AuthException('Kodun süresi dolmuş. Yeni bir kod üretin.');
    }
    if (fromUserId == currentUserId) {
      throw const AuthException('Kendi kodunuzu kullanamazsınız.');
    }
    final alreadyLinked = await DatabaseService.instance
        .partnershipExists(currentUserId, fromUserId);
    // Zaten ortak olsa bile varlıkları güncelle (resync) — hata fırlatma

    // Partner bu cihazda yoksa gölge kullanıcı olarak ekle / güncelle
    final existing = await DatabaseService.instance.getUserById(fromUserId);
    if (existing == null) {
      await DatabaseService.instance.insertUser(AppUser(
        id: fromUserId,
        email: email,
        displayName: displayName,
        passwordHash: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
      ));
    }

    if (!alreadyLinked) {
      await DatabaseService.instance.insertPartnership(
        id: _uuid.v4(),
        userId1: fromUserId,
        userId2: currentUserId,
      );
    }

    // Payload'daki varlıkları yerel DB'ye aktar veya güncelle (resync)
    final assetsRaw = data['a'] as List<dynamic>? ?? [];
    for (final raw in assetsRaw) {
      try {
        final map = Map<String, dynamic>.from(raw as Map);
        map['userId'] = fromUserId; // doğru sahibi garantile
        final asset = Asset(
          id: map['id'] as String,
          userId: fromUserId,
          name: map['name'] as String? ?? '',
          ticker: map['ticker'] as String? ?? '',
          type: AssetType.fromString(map['type'] as String? ?? ''),
          quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
          purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0,
          currency: map['currency'] as String? ?? 'TRY',
          currentPrice: (map['currentPrice'] as num?)?.toDouble() ?? 0,
          subCategory: map['subCategory'] as String?,
          unitType: (map['unitType'] as String?) ?? 'piece',
          notes: (map['notes'] as String?) ?? '',
          isManualPrice: (map['isManualPrice'] is int)
              ? (map['isManualPrice'] as int) == 1
              : map['isManualPrice'] as bool? ?? true,
          addedDate: map['addedDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['addedDate'] as int)
              : DateTime.now(),
          lastUpdated: map['lastUpdated'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int)
              : null,
        );
        await DatabaseService.instance.insertAssetSnapshot(asset);
      } catch (_) {
        // Tek bir varlık parse hatası diğerlerini engellemesin
      }
    }

    return displayName;
  }

  // ── Obfuscation (Basit Karartma) ──────────────────────────────────────────

  /// Paylaşılan Base64 verisinin direkt okunmasını engellemek için XOR karartma.
  /// (Askeri düzeyde şifreleme değildir ancak düz metin okunabilirliğini ortadan kaldırır)
  List<int> _obfuscate(List<int> bytes) {
    const key = [0x50, 0x54, 0x4B, 0x32, 0x30, 0x32, 0x34]; // PTK2024
    return List<int>.generate(
        bytes.length, (i) => bytes[i] ^ key[i % key.length]);
  }
}
