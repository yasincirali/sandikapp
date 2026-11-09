import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// `premium_ayarlari()` (0172) yanıtının okunması. Kesim ve acil durum artık
/// Remote Config'ten değil buradan gelir; yanlış okuma ya herkesi kilitler ya
/// da kilitleri kaldırır.
void main() {
  test('tam satır', () {
    final a = PremiumSunucuAyari.satirdan({
      'kapi_acik': true,
      'hediye_kesim': '2026-11-05T00:00:00+03:00',
      'acil_kapali': false,
    });
    expect(a.kapiAcik, isTrue);
    expect(a.hediyeKesim, DateTime.utc(2026, 11, 4, 21));
    expect(a.acilKapali, isFalse);
  });

  test('kesim null (hediye verilmemiş) ve eksik alanlar güvenli tarafa düşer',
      () {
    final a =
        PremiumSunucuAyari.satirdan({'kapi_acik': false, 'hediye_kesim': null});
    expect(a.hediyeKesim, isNull);
    expect(a.acilKapali, isFalse);
    expect(PremiumSunucuAyari.varsayilan.hediyeKesim, isNull);
    expect(PremiumSunucuAyari.varsayilan.acilKapali, isFalse);
  });

  test('acil kapatma okunur', () {
    expect(
        PremiumSunucuAyari.satirdan({'acil_kapali': true}).acilKapali, isTrue);
  });

  // Müşteri raporu 2026-11-08 #4: öne dönüşte yalnız 5 dk arkada kalındıysa
  // okunur; okuma düşerse son başarılı değer korunur.
  group('öne dönüş tazelemesi', () {
    test('yalnız ≥ 5 dk arkada kalındıysa', () {
      expect(premiumAyariTazelenmeli(null), isFalse,
          reason: 'Arkaya alınma görülmediyse istek yok.');
      expect(premiumAyariTazelenmeli(const Duration(seconds: 30)), isFalse);
      expect(premiumAyariTazelenmeli(const Duration(minutes: 4, seconds: 59)),
          isFalse);
      expect(premiumAyariTazelenmeli(const Duration(minutes: 5)), isTrue);
      expect(premiumAyariTazelenmeli(const Duration(hours: 3)), isTrue);
    });

    test('main.dart: tek geçersiz kılma, eşiğin arkasında', () {
      final k = File('lib/main.dart').readAsStringSync();
      expect('ref.invalidate(premiumSunucuAyariProvider)'.allMatches(k).length,
          1);
      expect(
          RegExp(r'if \(premiumAyariTazelenmeli\(bosluk\)\) \{\s*'
                  r'ref\.invalidate\(premiumSunucuAyariProvider\);')
              .hasMatch(k),
          isTrue,
          reason: 'Her öne dönüşte istek geri gelmesin.');
    });

    test('hata: son başarılı değer, hiç yoksa varsayılan (saf)', () {
      const acil = PremiumSunucuAyari(acilKapali: true);
      expect(premiumAyariHatada(acil), same(acil));
      expect(premiumAyariHatada(null), same(PremiumSunucuAyari.varsayilan));
    });

    test('sağlayıcı: okuma düşünce önceki değer silinmez', () async {
      var dus = false;
      var cagri = 0;
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(true),
        authProvider.overrideWith(_Auth.new),
        premiumAyarOkuyucuProvider.overrideWithValue(() async {
          cagri++;
          if (dus) throw Exception('ağ yok');
          return {'kapi_acik': true, 'acil_kapali': true};
        }),
      ]);
      addTearDown(c.dispose);
      c.listen(premiumSunucuAyariProvider, (_, __) {});

      final ilk = await c.read(premiumSunucuAyariProvider.future);
      expect(ilk.acilKapali, isTrue);

      dus = true;
      c.invalidate(premiumSunucuAyariProvider);
      final ikinci = await c.read(premiumSunucuAyariProvider.future);
      expect(cagri, 2);
      expect(ikinci.acilKapali, isTrue,
          reason: 'Zayıf bağlantı acil kapatmayı bir anlığına geri almamalı.');
      expect(ikinci.kapiAcik, isTrue);
    });

    test('sağlayıcı: hiç okunamadıysa varsayılan (soğuk açılış)', () async {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(true),
        authProvider.overrideWith(_Auth.new),
        premiumAyarOkuyucuProvider
            .overrideWithValue(() async => throw Exception('ağ yok')),
      ]);
      addTearDown(c.dispose);
      c.listen(premiumSunucuAyariProvider, (_, __) {});
      expect(await c.read(premiumSunucuAyariProvider.future),
          same(PremiumSunucuAyari.varsayilan));
    });
  });
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}
