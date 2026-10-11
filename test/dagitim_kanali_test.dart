import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// RC "TestFlight" koşulunun dayandığı `dagitim` sinyali. Sürüm koşulu
/// mağaza yayınında herkese açılıyordu; bkz. `_dagitimSinyaliniYaz`.
void main() {
  String k(String? s, {bool debug = false}) =>
      RemoteConfigService.dagitimKanali(s, debug: debug);

  test('iOS TestFlight ile App Store ayrılır', () {
    expect(k('com.apple.testflight'), 'testflight');
    expect(k('com.apple'), 'app_store');
    expect(k('com.apple.simulator'), 'simulator');
  });

  test('Android Play ve bilinmeyen kaynak', () {
    expect(k('com.android.vending'), 'play');
    expect(k(null), 'diger');
    expect(k('com.amazon.venezia'), 'diger');
  });

  test('debug derleme her zaman debug (TestFlight koşuluna girmez)', () {
    expect(k('com.apple.testflight', debug: true), 'debug');
  });
}
