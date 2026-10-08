import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart'
    show tasarrufOrani;
import 'package:portfoy_takip/services/satin_alma_service.dart'
    show denemeGunu;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Premium hakkının kaynağı (2026-10-08, paywall açılmadan önceki dört
/// bulgu). Kilitlenen davranış:
///  1. Release'te cihazdaki geliştirici anahtarı Premium SAYILMAZ: Sinyal
///     Ayarları'ndaki "Aç" düğmesi herkese ödemesiz Premium veriyordu.
///  2. Mağaza hakkı (RevenueCat anlık köprüsü) Premium sayılır.
///  3. Premium göstergeler (ADX/W%R/CCI) paywall kapalıyken hesaplanmaz
///     (eski davranış birebir), açıkken gerçek hakka bağlıdır.
///  4. Paywall metni Temmuz planının kilitlenmemiş vaatlerini satmaz;
///     satın alma taklit edilmez.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  ProviderContainer kap({
    bool paywall = true,
    bool gelistirici = false,
    bool magaza = false,
  }) {
    final c = ProviderContainer(overrides: [
      paywallVisibleProvider.overrideWithValue(paywall),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(gelistirici),
      magazaPremiumProvider.overrideWith((_) => magaza),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
      isPushAdminProvider.overrideWith((_) async => false),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('effectivePremium', () {
    test('release: cihaz anahtarı açık olsa da Premium değil', () async {
      final c = kap();
      await c.read(premiumUnlockedProvider.notifier).set(true);
      expect(c.read(premiumUnlockedProvider), isTrue);
      expect(c.read(effectivePremiumProvider), isFalse);
      expect(c.read(premiumGostergelerHesaplanirProvider), isFalse);
    });

    test('debug: geliştirici anahtarı sayılır', () async {
      final c = kap(gelistirici: true);
      await c.read(premiumUnlockedProvider.notifier).set(true);
      expect(c.read(effectivePremiumProvider), isTrue);
    });

    test('mağaza hakkı Premium sayılır', () {
      final c = kap(magaza: true);
      expect(c.read(effectivePremiumProvider), isTrue);
      expect(c.read(premiumGostergelerHesaplanirProvider), isTrue);
    });

    test('paywall kapalı: kimse Premium değil, göstergeler hesaplanmaz',
        () async {
      final c = kap(paywall: false, gelistirici: true, magaza: true);
      await c.read(premiumUnlockedProvider.notifier).set(true);
      expect(c.read(effectivePremiumProvider), isFalse);
      expect(c.read(premiumGostergelerHesaplanirProvider), isFalse);
    });
  });

  group('tasarrufOrani (mağaza fiyatı)', () {
    test('49 × 12 = 588, 399 → %32', () {
      expect(tasarrufOrani(49, 399), 32);
      expect(tasarrufOrani(49.99, 399.99), 33);
    });

    test('tasarruf yok ya da fiyat sıfır → rozet yok', () {
      expect(tasarrufOrani(49, 588), isNull);
      expect(tasarrufOrani(0, 399), isNull);
    });
  });

  group('denemeGunu: mağazada tanımlı olmayan deneme vaat edilmez', () {
    StoreProduct urun({IntroductoryPrice? intro, PricingPhase? serbest}) =>
        StoreProduct('yillik', '', '', 399, '₺399,00', 'TRY',
            introductoryPrice: intro,
            defaultOption: serbest == null
                ? null
                : SubscriptionOption('o', 'yillik:taban', 'yillik', const [],
                    const [], true, null, false, null, serbest, null, null,
                    null));

    test('deneme yok → null (düğme "Abone ol")', () {
      expect(denemeGunu(urun()), isNull);
    });

    test('iOS: ücretsiz giriş fiyatı 1 hafta → 7', () {
      expect(
          denemeGunu(urun(
              intro: const IntroductoryPrice(
                  0, '₺0', 'P1W', 1, PeriodUnit.week, 1))),
          7);
    });

    test('iOS: ücretli giriş fiyatı deneme değildir', () {
      expect(
          denemeGunu(urun(
              intro: const IntroductoryPrice(
                  9.99, '₺9,99', 'P1M', 1, PeriodUnit.month, 1))),
          isNull);
    });

    test('Android: ücretsiz faz 3 gün → 3', () {
      expect(
          denemeGunu(urun(
              serbest: const PricingPhase(
                  Period(PeriodUnit.day, 3, 'P3D'),
                  null,
                  1,
                  Price('Ücretsiz', 0, 'TRY'),
                  null))),
          3);
    });
  });

  group('kaynak taraması', () {
    test('Sinyal Ayarları gösterge anahtarını release\'te açtırmaz', () {
      final s = ekranKaynagiSync('lib/screens/signal_settings_screen.dart');
      expect(s.contains('gelistiriciAnahtariSayilirProvider'), isTrue);
      expect(s.contains("unlocked ? 'Kapat' : 'Aç'"), isFalse);
      // Cihaz anahtarına yazan tek yol geliştirici koşuluna bağlı.
      expect(RegExp(r'gelistirici\s*\?\s*\(\)\s*=>\s*ref\s*\.read\(premiumUnlockedProvider')
          .hasMatch(s), isTrue);
    });

    test('göstergeler cihaz anahtarına değil gerçek hakka bağlı', () {
      for (final yol in [
        'lib/providers/signal_provider.dart',
        'lib/screens/asset_detail/sinyal_widgetlari.dart',
      ]) {
        final s = ekranKaynagiSync(yol);
        expect(s.contains('premiumUnlockedProvider'), isFalse, reason: yol);
      }
    });

    test('paywall satın almayı taklit etmez, eski vaatleri satmaz', () {
      final s = ekranKaynagiSync('lib/screens/paywall_screen.dart');
      expect(s.contains('premiumUnlockedProvider'), isFalse);
      expect(s.contains('SatinAlmaService.instance.satinAl'), isTrue);
      expect(s.contains("'7 gün ücretsiz dene'"), isFalse);
      expect(s.contains('Günde 2 sinyal analizi ('), isFalse);
      expect(s.contains("'Sınırsız partner paylaşımı'"), isFalse);
    });
  });
}
