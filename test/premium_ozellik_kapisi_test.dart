import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/fon_akisi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// Tek anahtar (yasin 2026-10-09: "Tek flag"): Premium'a özgü özellikler
/// (Balina Radarı, ekstre AI) paywall kapalıyken yalnız admin hesabına
/// görünür; paywall açılınca herkese (ücretsizde kilitli).
void main() {
  tearDown(() {
    RemoteConfigService.instance.yonetici = false;
    RemoteConfigService.testAcik = {};
  });

  ProviderContainer kap({required bool paywall, required bool admin}) {
    final c = ProviderContainer(overrides: [
      paywallVisibleProvider.overrideWithValue(paywall),
      isPushAdminProvider.overrideWith((ref) async => admin),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  for (final (paywall, admin, beklenen) in [
    (false, false, false),
    (false, true, true),
    (true, false, true),
    (true, true, true),
  ]) {
    test('paywall=$paywall admin=$admin → görünür=$beklenen', () async {
      final c = kap(paywall: paywall, admin: admin);
      await c.read(isPushAdminProvider.future);
      expect(c.read(premiumOzellikleriGorunurProvider), beklenen);
      expect(c.read(balinaRadariAcikProvider), beklenen);
    });
  }

  test('provider dışı yerler (bildirim) admin bilgisini RC üzerinden okur', () {
    // Firebase testte yok: paywall_enabled varsayılanı kapalı.
    expect(RemoteConfigService.instance.balinaRadariAcik, isFalse);
    expect(RemoteConfigService.instance.ekstreAiEsleme, isFalse);
    RemoteConfigService.instance.yonetici = true;
    expect(RemoteConfigService.instance.balinaRadariAcik, isTrue);
    expect(RemoteConfigService.instance.ekstreAiEsleme, isTrue);
  });

  test('test kancası eski bayrak adıyla açmaya devam eder', () {
    RemoteConfigService.testAcik = {'balina_radari_acik'};
    expect(RemoteConfigService.instance.balinaRadariAcik, isTrue);
    expect(RemoteConfigService.instance.ekstreAiEsleme, isFalse);
  });
}
