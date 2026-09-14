import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/secure_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemVault implements SessionVault {
  final map = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('keystore');
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// M2: oturum token'ı SharedPreferences'tan Keychain/Keystore'a taşındı.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'sb-abc-auth-token';

  test('varsayılan anahtar supabase_flutter formülüyle aynı', () {
    expect(SecureSessionStorage.defaultKeyFor('https://abc.supabase.co'),
        key);
  });

  test('eski SharedPreferences oturumu kasaya taşınır ve silinir', () async {
    SharedPreferences.setMockInitialValues({key: '{"access_token":"x"}'});
    final vault = _MemVault();
    final s = SecureSessionStorage(vault: vault, persistSessionKey: key);
    await s.initialize();
    expect(vault.map[key], '{"access_token":"x"}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isFalse,
        reason: 'düz metin kopya kalırsa taşımanın anlamı yok');
    expect(await s.hasAccessToken(), isTrue);
  });

  test('kasada oturum varken eski kayıt onu ezmez', () async {
    SharedPreferences.setMockInitialValues({key: 'old'});
    final vault = _MemVault()..map[key] = 'new';
    final s = SecureSessionStorage(vault: vault, persistSessionKey: key);
    await s.initialize();
    expect(vault.map[key], 'new');
  });

  test('yaz / oku / sil', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = _MemVault();
    final s = SecureSessionStorage(vault: vault, persistSessionKey: key);
    await s.persistSession('s1');
    expect(await s.accessToken(), 's1');
    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });

  test('kasa okunamazsa oturum yok sayılır, exception yok', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = _MemVault()..fail = true;
    final s = SecureSessionStorage(vault: vault, persistSessionKey: key);
    expect(await s.hasAccessToken(), isFalse);
  });
}
