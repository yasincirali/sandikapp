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
  group('KeychainKasasi: iOS ilk kilit açılışından sonra okunur (2026-10-13)',
      () {
    test('yeni katmanda varsa doğrudan döner', () async {
      final ham = _KatmanliHam(katmanli: true)..yeni[key] = 'y';
      expect(await KeychainKasasi(ham: ham).read(key), 'y');
    });

    test('eski (unlocked) kayıt okunur ve yeni katmana TAŞINIR', () async {
      final ham = _KatmanliHam(katmanli: true)..eski[key] = 'oturum';
      final k = KeychainKasasi(ham: ham);
      expect(await k.read(key), 'oturum',
          reason: 'güncelleme sonrası kullanıcı yeniden giriş yapmamalı');
      expect(ham.yeni[key], 'oturum');
      expect(ham.eski.containsKey(key), isFalse);
    });

    test('taşıma yazımı düşerse eski kayıt geri konur', () async {
      final ham = _KatmanliHam(katmanli: true)
        ..eski[key] = 'oturum'
        ..yeniYazmaHatasi = true;
      expect(await KeychainKasasi(ham: ham).read(key), 'oturum');
      expect(ham.eski[key], 'oturum', reason: 'oturum kaybolmamalı');
    });

    test('yazma önce eski kaydı siler (Keychain "zaten var" hatası)',
        () async {
      final ham = _KatmanliHam(katmanli: true)..eski[key] = 'bayat';
      await KeychainKasasi(ham: ham).write(key, 'taze');
      expect(ham.eski.containsKey(key), isFalse,
          reason: 'eski kopya kalırsa bayat yenileme anahtarı okunurdu');
      expect(ham.yeni[key], 'taze');
    });

    test('silme iki katmandan da siler', () async {
      final ham = _KatmanliHam(katmanli: true)
        ..eski[key] = 'a'
        ..yeni[key] = 'b';
      await KeychainKasasi(ham: ham).delete(key);
      expect(ham.eski, isEmpty);
      expect(ham.yeni, isEmpty);
    });

    test('Android: tek katman, silip yazma yok', () async {
      final ham = _KatmanliHam(katmanli: false);
      final k = KeychainKasasi(ham: ham);
      await k.write(key, 'v');
      expect(await k.read(key), 'v');
      expect(ham.eskiCagri, 0, reason: 'katman yoksa eski yol hiç çağrılmaz');
    });
  });
}

class _KatmanliHam implements KatmanliHamKasa {
  _KatmanliHam({required this.katmanli});
  @override
  final bool katmanli;
  final yeni = <String, String>{};
  final eski = <String, String>{};
  bool yeniYazmaHatasi = false;
  int eskiCagri = 0;

  Map<String, String> _m(bool y) {
    if (!y) eskiCagri++;
    return y ? yeni : eski;
  }

  @override
  Future<String?> read(String key, {required bool yeni}) async =>
      _m(yeni)[key];
  @override
  Future<void> write(String key, String value, {required bool yeni}) async {
    if (yeni && yeniYazmaHatasi) throw StateError('keychain');
    _m(yeni)[key] = value;
  }

  @override
  Future<void> delete(String key, {required bool yeni}) async =>
      _m(yeni).remove(key);
}
