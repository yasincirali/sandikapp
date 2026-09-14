import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';

/// Oturum token'ının yazıldığı kasa — üretimde Keychain / Android Keystore.
abstract class SessionVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _SecureVault implements SessionVault {
  // Varsayılan seçenekler: iOS Keychain (cihaz kilidi açıkken erişilebilir),
  // Android Keystore ile şifrelenmiş depo. Uygulama oturumu yalnızca ön
  // planda okur; arka plan izolatı (FCM) Supabase'i başlatmaz.
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Supabase oturumunu Keychain/Keystore'da saklayan [LocalStorage].
///
/// **Neden:** `supabase_flutter` varsayılanı SharedPreferences'tır — Android'de
/// düz XML, iOS'ta düz plist; root/yedek/adb ile refresh token okunur ve
/// oturum başka cihazda sürdürülebilir (2026-09 M2). Token artık platform
/// kasasında; SharedPreferences yalnızca tercihleri taşır.
///
/// **Geçiş:** ilk çalıştırmada eski anahtar SharedPreferences'ta duruyorsa
/// kasaya taşınır ve eski kayıt silinir — kullanıcı yeniden giriş yapmaz.
/// Kasa okunamazsa (nadir: Keystore bozulması) oturum yok sayılır; kullanıcı
/// giriş ekranını görür, çökme olmaz.
class SecureSessionStorage extends LocalStorage {
  final String persistSessionKey;
  final SessionVault _vault;
  final Future<SharedPreferences> Function() _prefs;

  SecureSessionStorage({
    required this.persistSessionKey,
    @visibleForTesting SessionVault? vault,
    @visibleForTesting Future<SharedPreferences> Function()? prefs,
  })  : _vault = vault ?? _SecureVault(),
        _prefs = prefs ?? SharedPreferences.getInstance;

  /// supabase_flutter'ın varsayılan anahtarı — geçişte aynı adı okumak için
  /// birebir aynı formül (`sb-<host ilk parçası>-auth-token`).
  static String defaultKeyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    try {
      final prefs = await _prefs();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null) return;
      if (await _vault.read(persistSessionKey) == null) {
        await _vault.write(persistSessionKey, legacy);
      }
      await prefs.remove(persistSessionKey);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SecureSessionStorage.migrate');
    }
  }

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() async {
    try {
      return await _vault.read(persistSessionKey);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SecureSessionStorage.read');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _vault.delete(persistSessionKey);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SecureSessionStorage.remove');
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _vault.write(persistSessionKey, persistSessionString);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SecureSessionStorage.write');
    }
  }
}
