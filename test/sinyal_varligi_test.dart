import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/sinyal_varligi_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ücretsiz planın sınırları ve sinyal türlerinin iki taraflı eşitliği.
///
/// "Tek sinyal varlığı" kapısı 2026-10-10'da söküldü (bkz.
/// `sinyal_varligi_provider.dart` notu); sinyal bildirimi artık paywall
/// açıkken bütünüyle Premium (`sinyal_premium_kapisi_test`).
void main() {
  group('ücretsiz sınırlar', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    ProviderContainer kap({required bool paywall}) {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(paywall),
        gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
        magazaPremiumProvider.overrideWith((_) => false),
        gecerliPremiumHakkiProvider.overrideWithValue(null),
        kilitlerAskidaProvider.overrideWithValue(false),
        isPushAdminProvider.overrideWith((_) async => false),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('varsayılan sınırlar', () {
      expect(RemoteConfigService.instance.freeAssetLimit, 10);
      expect(kap(paywall: true).read(assetLimitProvider), 10);
      // 5 → 10 (yasin, 2026-10-10: "pinti görünmeyelim").
      expect(kap(paywall: true).read(watchlistLimitProvider), 10);
      // Paywall kapalı canlı kullanıcı 7'de kalır (ana kural).
      expect(kap(paywall: false).read(watchlistLimitProvider), 7);
      expect(kap(paywall: false).read(assetLimitProvider), greaterThan(1000));
    });
  });

  test('istemci türleri sunucudaki ANALYZABLE ile aynı', () {
    final ts = File('supabase/functions/analyze-signals/index.ts')
        .readAsStringSync();
    final m = RegExp(r'ANALYZABLE = new Set\(\[([^\]]*)\]').firstMatch(ts)!;
    final sunucu = RegExp(r"'(\w+)'")
        .allMatches(m.group(1)!)
        .map((e) => e.group(1))
        .toSet();
    expect(kSinyalTurleri.map((t) => t.name).toSet(), sunucu);
  });
}
