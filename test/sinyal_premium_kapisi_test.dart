import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Sinyal Premium modeli (yasin, 2026-10-10 akşam): "teknik göstergelerden
/// en yaygın 3 tanesi ücretsiz gösterilmeli, ancak kalanları ve custom
/// gösterge bununla push bildirimi feature'ı premium olmalı; ayrıca var olan
/// göstergeler de parametrik kullanılabilmeli premiumda". Ardından üç
/// ücretsiz göstergenin bildirimi için: "olur ama limitli sayıda".
///
/// Kilitler:
///  - Paywall kapalıyken davranış birebir eski: beş gösterge, bildirim açık,
///    ileri üçü hesaplanmaz, parametreler yalnız admin'de.
///  - Paywall açık + ücretsiz: yüzey açık, üç gösterge (RSI, MACD,
///    Bollinger), bildirim tür başına günde 1, parametre kilitli.
///  - Premium (mağaza ya da admin): sekiz gösterge, sınırsız bildirim,
///    parametre.
///  - Başlangıç seviyesi her durumda gizler.
///  - Sunucu eşi `analyze-signals` → `bildirimKurali` + `slotaSigdir`
///    (supabase/tests/sinyal_ucretsiz_bildirim_test.ts).
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

  test('paywall kapalı: eski davranış', () {
    final c = kap(paywall: false);
    expect(c.read(premiumKilitliProvider), isFalse);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.acik);
    expect(c.read(zilSinyalleriGosterProvider), isTrue);
    expect(c.read(sinyalSlotSiniriProvider), greaterThan(1000));
    expect(c.read(izinliGostergelerProvider), {
      IndicatorId.rsi,
      IndicatorId.macd,
      IndicatorId.bollinger,
      IndicatorId.ema,
      IndicatorId.stochastic,
    });
    expect(c.read(gostergeParametreDurumuProvider), OzellikDurumu.gizli);
  });

  test('paywall açık, ücretsiz: üç gösterge, günde 1 bildirim', () {
    final c = kap(paywall: true);
    expect(c.read(premiumKilitliProvider), isTrue);
    expect(c.read(sinyalYuzeyiProvider), SinyalYuzeyi.acik);
    expect(c.read(izinliGostergelerProvider), IndicatorId.ucretsiz);
    expect(c.read(sinyalSlotSiniriProvider), 1);
    expect(c.read(zilSinyalleriGosterProvider), isTrue);
    expect(c.read(gostergeParametreDurumuProvider), OzellikDurumu.kilitli);
    expect(c.read(radarKilitliProvider), isTrue);
  });

  test('paywall açık, Premium: sekiz gösterge, sınırsız bildirim, parametre',
      () {
    final c = kap(paywall: true, magaza: true);
    expect(c.read(premiumKilitliProvider), isFalse);
    expect(c.read(izinliGostergelerProvider), IndicatorId.all.toSet());
    expect(c.read(sinyalSlotSiniriProvider), greaterThan(1000));
    expect(c.read(gostergeParametreDurumuProvider), OzellikDurumu.acik);
  });

  test('paywall kapalı, admin: parametreler açık (yeni özellik önizlemesi)',
      () async {
    final c = kap(paywall: false, admin: true);
    await c.read(isPushAdminProvider.future);
    expect(c.read(gostergeParametreDurumuProvider), OzellikDurumu.acik);
  });

  test('Başlangıç seviyesi: gizli', () {
    expect(kap(paywall: true, seviye: YatirimciSeviyesi.baslangic)
        .read(sinyalYuzeyiProvider), SinyalYuzeyi.gizli);
    expect(kap(paywall: false, seviye: YatirimciSeviyesi.baslangic)
        .read(sinyalYuzeyiProvider), SinyalYuzeyi.gizli);
  });

  test('sunucunun ücretsiz bildirim kümesi istemciyle aynı', () {
    final ts = File('supabase/functions/analyze-signals/index.ts')
        .readAsStringSync();
    final m = RegExp(r'UCRETSIZ_GOSTERGELER[^=]*= \[([^\]]*)\]')
        .firstMatch(ts)!;
    final sunucu =
        RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((e) => e.group(1)).toSet();
    expect(sunucu, IndicatorId.ucretsiz);
  });

  test('ücretsiz küme en yaygın üçü; Premium kalan beşi', () {
    expect(IndicatorId.ucretsiz,
        {IndicatorId.rsi, IndicatorId.macd, IndicatorId.bollinger});
    expect(IndicatorId.all.where(IndicatorId.premiumMu).length, 5);
  });

  test('yüzeyler karara bağlı: panel, ayarlar, uygulama içi analiz', () {
    final panel = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(panel.contains('izinliGostergelerProvider'), isTrue);
    expect(panel.contains('sgnPremiumGostergeSatiri'), isTrue);
    final ayar = ekranKaynagiSync('lib/screens/signal_settings_screen.dart');
    expect(ayar.contains('sinyalSlotSiniriProvider'), isTrue);
    expect(ayar.contains('gostergeParametreDurumuProvider'), isTrue);
    final analiz = ekranKaynagiSync('lib/providers/signal_provider.dart');
    expect(analiz.contains('izinliGostergelerProvider'), isTrue);
  });
}
