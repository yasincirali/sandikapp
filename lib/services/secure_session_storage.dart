import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

/// Kasanın iki "erişilebilirlik" katmanı: [yeni] = ilk kilit açılışından
/// sonra, [yeni] değil = eski varsayılan (yalnız kilit açıkken). Android'de
/// iki katman aynı depoya gider; ayrım yalnız iOS Keychain'de anlamlıdır.
abstract class KatmanliHamKasa {
  /// İki katman gerçekten ayrı depolar mı (yalnız Apple platformları).
  bool get katmanli;
  Future<String?> read(String key, {required bool yeni});
  Future<void> write(String key, String value, {required bool yeni});
  Future<void> delete(String key, {required bool yeni});
}

class _FlutterHamKasa implements KatmanliHamKasa {
  static const _s = FlutterSecureStorage();
  // Eski kayıtlar paketin varsayılanıyla yazıldı: `unlocked`.
  static const _eski = IOSOptions();
  static const _yeni =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  @override
  bool get katmanli => !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  @override
  Future<String?> read(String key, {required bool yeni}) =>
      _s.read(key: key, iOptions: yeni ? _yeni : _eski);
  @override
  Future<void> write(String key, String value, {required bool yeni}) =>
      _s.write(key: key, value: value, iOptions: yeni ? _yeni : _eski);
  @override
  Future<void> delete(String key, {required bool yeni}) =>
      _s.delete(key: key, iOptions: yeni ? _yeni : _eski);
}

/// Keychain/Keystore kasası — iOS'ta **ilk kilit açılışından sonra**
/// okunabilir (2026-10-13).
///
/// **Neden:** paketin varsayılanı `KeychainAccessibility.unlocked`: telefon
/// KİLİTLİYKEN okunamaz. iOS uygulamayı kilitli ekranda arkada başlatır
/// (sessiz push, Live Activity / widget güncellemesi); `main()` koşar,
/// `Supabase.initialize` oturumu okur, Keychain reddeder, okuma `null` döner
/// ve süreç "oturum yok" hâliyle canlı kalır. Kullanıcı sonra uygulamayı
/// açınca giriş ekranını görür — "uzun beklemede oturum kapandı" belirtisi.
/// Yazma da aynı nedenle düşerse kasada yenileme anahtarının ESKİ kopyası
/// kalır; rotasyon açık olduğundan bir sonraki açılışta sunucu onu reddeder
/// ve gotrue oturumu siler. `first_unlock` (Apple'ın arka plan işi yapan
/// uygulamalara önerdiği düzey) ikisini de kapatır; yedekle taşınma
/// davranışı eskisiyle aynı kalır (`_this_device` değil).
///
/// **Geçiş:** Keychain sorgusu erişilebilirliği de eşleştirir, yani yeni
/// ayarla eski kayıt GÖRÜNMEZ ve aynı anahtarla eklemek "zaten var" diye
/// düşer. Bu yüzden: okuma yeniyi bulamazsa eskiyi okur ve yeniye taşır;
/// yazma önce eski kaydı siler. Taşıma kullanıcıya görünmez, giriş istemez.
class KeychainKasasi implements SessionVault {
  KeychainKasasi({@visibleForTesting KatmanliHamKasa? ham})
      : _ham = ham ?? _FlutterHamKasa();
  final KatmanliHamKasa _ham;

  @override
  Future<String?> read(String key) async {
    final yeni = await _ham.read(key, yeni: true);
    if (yeni != null || !_ham.katmanli) return yeni;
    final eski = await _ham.read(key, yeni: false);
    if (eski == null) return null;
    // Taşıma başarısız olsa da okunan değer döner; eski kayıt yazma
    // başarısızsa geri konur ki oturum kaybolmasın.
    try {
      await _ham.delete(key, yeni: false);
      await _ham.write(key, eski, yeni: true);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'KeychainKasasi.tasi');
      try {
        await _ham.write(key, eski, yeni: false);
      } catch (_) {}
    }
    return eski;
  }

  @override
  Future<void> write(String key, String value) async {
    // Android'de katmanlar aynı kayıttır: silip yazmak yalnız bir kayıp
    // penceresi açardı.
    if (!_ham.katmanli) return _ham.write(key, value, yeni: true);
    try {
      await _ham.delete(key, yeni: false);
    } catch (_) {
      // Eski kayıt yoksa ya da silinemiyorsa yazma yine denenir.
    }
    await _ham.write(key, value, yeni: true);
  }

  @override
  Future<void> delete(String key) async {
    await _ham.delete(key, yeni: true);
    if (_ham.katmanli) await _ham.delete(key, yeni: false);
  }
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
  })  : _vault = vault ?? KeychainKasasi(),
        _prefs = prefs ?? SharedPreferences.getInstance;

  /// supabase_flutter'ın varsayılan anahtarı — geçişte aynı adı okumak için
  /// birebir aynı formül (`sb-<host ilk parçası>-auth-token`).
  static String defaultKeyFor(String projeUrl) =>
      'sb-${Uri.parse(projeUrl).host.split('.').first}-auth-token';

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
