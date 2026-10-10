import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Teknik sinyal yalnız Premium (yasin, 2026-10-10: "varlık gösterge
/// sinyali özelliği tamamen premiuma geçsin") ve tek Premium kilidi.
///
/// Kilitler:
///  - Paywall kapalıyken davranış birebir eski: sinyal açık, hiçbir kilit yok
///    (canlıdaki kullanıcı etkilenmez).
///  - Paywall açık + Premium değil → yüzeyler kilitli, zilde sinyal yok.
///  - Premium (mağaza ya da admin) → açık.
///  - Başlangıç seviyesi her durumda gizler; ona kilit de gösterilmez.
///  - Bütün Premium kilitleri tek sağlayıcıdan (`premiumKilitliProvider`).
///  - Sunucu eşi `analyze-signals` → `yalnizPremiumFiltresi`
///    (supabase/tests/sinyal_yalniz_premium_test.ts).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  ProviderContainer kap({
    required bool paywall,
    bool magaza = false,
    bool admin = false,
    YatirimciSeviyesi seviye = YatirimciSeviyesi.orta,
  }) {
    final c = ProviderContainer(overrides: [
      paywallVisibleProvider.overrideWithValue(paywall),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      magazaPremiumProvider.overrideWith((_) => magaza),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
      isPushAdminProvider.overrideWith((_) async => admin),
      yatirimciSeviyesiProvider.overrideWithValue(seviye),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('paywall kapalı: sinyal açık, kilit yok', () {
    final c = kap(paywall: false);
    expect(c.read(premiumKilitliProvider), isFalse);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.acik);
    expect(c.read(zilSinyalleriGosterProvider), isTrue);
  });

  test('paywall açık, ücretsiz: sinyal kilitli, zilde sinyal yok', () {
    final c = kap(paywall: true);
    expect(c.read(premiumKilitliProvider), isTrue);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.kilitli);
    expect(c.read(zilSinyalleriGosterProvider), isFalse);
    expect(c.read(radarKilitliProvider), isTrue);
  });

  test('paywall açık, Premium: açık', () {
    final c = kap(paywall: true, magaza: true);
    expect(c.read(premiumKilitliProvider), isFalse);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.acik);
  });

  test('paywall açık, admin: açık', () async {
    final c = kap(paywall: true, admin: true);
    await c.read(isPushAdminProvider.future);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.acik);
  });

  test('Başlangıç seviyesi: gizli (kilit de yok)', () {
    expect(kap(paywall: true, seviye: YatirimciSeviyesi.baslangic)
        .read(sinyalYuzeyiProvider), SinyalYuzeyi.gizli);
    expect(kap(paywall: false, seviye: YatirimciSeviyesi.baslangic)
        .read(sinyalYuzeyiProvider), SinyalYuzeyi.gizli);
  });

  test('sinyal yüzeyleri karara bağlı: panel ve ayarlar', () {
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(detay.contains('SinyalYuzeyi.kilitli'), isTrue);
    expect(detay.contains('SinyalKilitKarti()'), isTrue);
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    expect(sayfa.contains('sinyalYuzeyiProvider'), isTrue);
    final ayar = ekranKaynagiSync('lib/screens/signal_settings_screen.dart');
    expect(ayar.contains('premiumKilitliProvider'), isTrue);
  });
}
