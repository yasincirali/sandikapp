import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';

/// Paywall görünürlüğü KOD kararı (yasin 2026-11-01: "rc flagleriyle
/// yönetmemeye çalışalım"): iOS'ta açık, Android'de RevenueCat kurulana kadar
/// kapalı; Remote Config okunmaz. Eski regresyon (2026-10-09, "paywall_enabled
/// true ama göremiyorum": RC etkinleşince provider yenilenmeli) test kancası
/// için hâlâ geçerli — yerel `RC_ACIK` aynı yoldan açar.
void main() {
  tearDown(() {
    RemoteConfigService.testAcik = {};
    RemoteConfigService.testKapali = {};
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS: paywall kodda açık, Android: kapalı', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(RemoteConfigService.instance.paywallEnabled, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(RemoteConfigService.instance.paywallEnabled, isFalse,
        reason: 'Android RevenueCat zinciri yok; paywall görünürse satın '
            'alınamaz');
  });

  test('testKapali iOS varsayılanını kapatır, testAcik her yerde açar', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    RemoteConfigService.testKapali = {'paywall_enabled'};
    expect(RemoteConfigService.instance.paywallEnabled, isFalse);
    RemoteConfigService.testAcik = {'paywall_enabled'};
    expect(RemoteConfigService.instance.paywallEnabled, isTrue,
        reason: 'testAcik, testKapali\'dan önce gelir');
  });

  test('etkinleşme sayacı artınca provider yeni değeri okur', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final dinleme = c.listen(paywallVisibleProvider, (_, __) {});
    addTearDown(dinleme.close);

    expect(c.read(paywallVisibleProvider), isFalse);
    RemoteConfigService.testAcik = {'paywall_enabled'};
    expect(c.read(paywallVisibleProvider), isFalse,
        reason: 'etkinleşme olmadan önbellek değişmez');
    RemoteConfigService.instance.etkinlesmeSayaci.value++;
    expect(c.read(paywallVisibleProvider), isTrue);
  });
}
