import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// Regresyon (yasin, 2026-10-09: "paywall_enabled true ama göremiyorum"):
/// açılış fetch'i ilk kareden SONRA bittiğinde `paywallVisibleProvider`
/// eski değeri süreç boyunca tutuyordu. Etkinleşme sayacı artınca provider
/// yeni değeri okumalı.
void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  test('RC etkinleşince paywall aynı oturumda görünür olur', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Provider canlı kalsın (ekranın onu izlemesi gibi).
    final dinleme = c.listen(paywallVisibleProvider, (_, __) {});
    addTearDown(dinleme.close);

    expect(c.read(paywallVisibleProvider), isFalse);

    // Console'da açıldı, fetch ilk kareden sonra etkinleşti.
    RemoteConfigService.testAcik = {'paywall_enabled'};
    expect(c.read(paywallVisibleProvider), isFalse,
        reason: 'etkinleşme olmadan önbellek değişmez');
    RemoteConfigService.instance.etkinlesmeSayaci.value++;

    expect(c.read(paywallVisibleProvider), isTrue);
  });
}
