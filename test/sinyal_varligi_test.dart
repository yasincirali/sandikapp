import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/sinyal_varligi_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Ücretsiz planda sinyal bildirimi tek varlıkta (yasin, 2026-10-08:
/// "sinyal 1 varlıkta ücretsiz, 2. varlık için Premium"). İstemcideki seçim
/// kuralı sunucudaki `sinyalVarligiSec` (analyze-signals) ile aynı olmalı:
/// `supabase/tests/sinyal_varlik_kapisi_test.ts` aynı vakaları sınar.
Asset _lot(String id, String ticker, AssetType tur,
        {DateTime? eklendi, bool manuel = false, String user = 'u1'}) =>
    Asset(
      id: id,
      userId: user,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: 1,
      purchasePrice: 10,
      currency: 'TRY',
      notes: '',
      addedDate: eklendi ?? DateTime(2026, 1, 1),
      isManualPrice: manuel,
    );

void main() {
  group('etkinSinyalVarligi', () {
    final thyao = _lot('b', 'THYAO', AssetType.hisse,
        eklendi: DateTime(2026, 3, 1));
    final dpp = _lot('a', 'DPP', AssetType.fon, eklendi: DateTime(2026, 2, 1));

    test('seçim yoksa en eski eklenen', () {
      final s = etkinSinyalVarligi([thyao, dpp], null);
      expect(s?.tur, AssetType.fon);
      expect(s?.ticker, 'DPP');
    });

    test('tutulan seçim kazanır, büyük/küçük harf ve boşluk önemsiz', () {
      final s = etkinSinyalVarligi(
          [thyao, dpp], (tur: AssetType.hisse, ticker: ' thyao '));
      expect(s?.tur, AssetType.hisse);
    });

    test('seçilen varlık artık yoksa yedek kural', () {
      final s = etkinSinyalVarligi(
          [thyao, dpp], (tur: AssetType.hisse, ticker: 'ASELS'));
      expect(s?.ticker, 'DPP');
    });

    test('aynı tarihte küçük id; manuel fiyatlı ve sinyalsiz tür aday değil',
        () {
      final t = DateTime(2026, 1, 1);
      final s = etkinSinyalVarligi([
        _lot('z', 'AAA', AssetType.hisse, eklendi: t),
        _lot('y', 'BBB', AssetType.hisse, eklendi: t),
        _lot('0', 'X', AssetType.hisse,
            eklendi: DateTime(2020), manuel: true),
        _lot('1', 'MEV', AssetType.mevduat, eklendi: DateTime(2020)),
      ], null);
      expect(s?.ticker, 'BBB');
    });

    test('aday yoksa null', () {
      expect(etkinSinyalVarligi(const [], null), isNull);
    });
  });

  group('kapı', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    ProviderContainer kap({required bool paywall, bool magaza = false}) {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(paywall),
        gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
        magazaPremiumProvider.overrideWith((_) => magaza),
        gecerliPremiumHakkiProvider.overrideWithValue(null),
        isPushAdminProvider.overrideWith((_) async => false),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('paywall kapalı: kapı yok, canlı davranış', () {
      expect(kap(paywall: false).read(sinyalVarlikKapisiAcikProvider), isFalse);
    });

    test('paywall açık, ücretsiz: kapı açık', () {
      expect(kap(paywall: true).read(sinyalVarlikKapisiAcikProvider), isTrue);
    });

    test('Premium: kapı yok', () {
      expect(
          kap(paywall: true, magaza: true).read(sinyalVarlikKapisiAcikProvider),
          isFalse);
    });

    test('ücretsiz sınırlar: 10 varlık, paywall açıkken 10 takip', () {
      expect(RemoteConfigService.instance.freeAssetLimit, 10);
      expect(RemoteConfigService.instance.freeSignalAssets, 1);
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
