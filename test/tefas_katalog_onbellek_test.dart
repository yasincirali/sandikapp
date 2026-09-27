// Fon kataloğu tercih dosyasından çıkarıldı (2026-09-28): 497 KB'lık
// `tefas_funds_cache_v1` anahtarı Android'de her açılışta tüm tercih
// dosyasıyla birlikte ayrıştırılıyor, ilk kareyi ~400 ms geciktiriyordu.
// Bu test hem temizliği hem de geri dönüşü (katalogu yine prefs'e yazmayı)
// kilitler.

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tefas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eski katalog anahtarları silinir, başka tercihlere dokunulmaz',
      () async {
    SharedPreferences.setMockInitialValues({
      'tefas_funds_cache_v1': '[{"code":"AAA"}]',
      'tefas_funds_cache_ts_v1': 1,
      'baska_tercih': true,
    });
    await TefasService.instance.eskiOnbellegiTemizle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('tefas_funds_cache_v1'), isFalse);
    expect(prefs.containsKey('tefas_funds_cache_ts_v1'), isFalse);
    expect(prefs.getBool('baska_tercih'), isTrue);
  });

  test('katalog yeniden SharedPreferences\'a yazılmıyor', () {
    final kaynak = ekranKaynagiSync('lib/services/tefas_service.dart');
    // setString yalnız küçük fiyat önbelleği için kalabilir; eski katalog
    // anahtarına yazan satır olmamalı.
    expect(kaynak.contains('setString(_eskiPrefsCacheKey'), isFalse);
    expect(kaynak.contains("setString('tefas_funds_cache"), isFalse);
    expect(kaynak.contains('getApplicationSupportDirectory'), isTrue);
  });
}
