
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Ödeme öncesi iki kapı (Premium planı, 2026-10-08):
///  1. Sinyal bildirimi: ücretsizde tür başına günde 1 (yalnız sabah ya da
///     seçilen ilk saat); Premium seçtiği sıklığı alır.
///  2. Karşılaştır: ücretsizde 2 seri (kendi serine ek bir kıyas), Premium 5.
///  3. Ortak: ücretsizde 1 (yasin kararı 2026-10-08); var olan korunur,
///     yalnız yeni ortak eklemek (kod üret / kod gir / kabul) durur.
/// Paywall kapalıyken ikisi de yoktur: canlıdaki davranış birebir.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  ProviderContainer kap({
    required bool paywall,
    bool magaza = false,
    int? ortakSayisi,
  }) {
    final c = ProviderContainer(overrides: [
      if (ortakSayisi != null)
        partnersProvider.overrideWith(() => _SabitOrtaklar(ortakSayisi)),
      paywallVisibleProvider.overrideWithValue(paywall),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      magazaPremiumProvider.overrideWith((_) => magaza),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
      isPushAdminProvider.overrideWith((_) async => false),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('sınırlar', () {
    test('paywall kapalı: kapı yok', () {
      final c = kap(paywall: false);
      expect(c.read(sinyalBildirimiKilitliProvider), isFalse);
      expect(c.read(karsilastirmaSeriSiniriProvider), kKarsilastirmaEnFazla);
    });

    test('paywall açık, ücretsiz: bildirim Premium, 2 seri', () {
      final c = kap(paywall: true);
      expect(c.read(sinyalBildirimiKilitliProvider), isTrue);
      expect(c.read(karsilastirmaSeriSiniriProvider), 2);
    });

    test('paywall açık, Premium: kapı yok', () {
      final c = kap(paywall: true, magaza: true);
      expect(c.read(sinyalBildirimiKilitliProvider), isFalse);
      expect(c.read(karsilastirmaSeriSiniriProvider), kKarsilastirmaEnFazla);
    });
  });

  group('ortak sınırı', () {
    Future<bool> dolu(ProviderContainer c) async {
      await c.read(partnersProvider.future);
      return c.read(ortakSiniriDoluProvider);
    }

    test('paywall kapalı: 3 ortakta bile dolu değil', () async {
      expect(await dolu(kap(paywall: false, ortakSayisi: 3)), isFalse);
    });

    test('ücretsiz: 0 ortakta boş, 1 ortakta dolu', () async {
      expect(await dolu(kap(paywall: true, ortakSayisi: 0)), isFalse);
      expect(await dolu(kap(paywall: true, ortakSayisi: 1)), isTrue);
    });

    test('Premium: sınır yok', () async {
      expect(await dolu(kap(paywall: true, magaza: true, ortakSayisi: 4)),
          isFalse);
    });

    test('üç giriş de kapıdan geçer', () {
      final profil = ekranKaynagiSync('lib/screens/profile_screen.dart');
      expect('ortakSiniriPaywalliActi('.allMatches(profil).length, 3);
      final istek =
          ekranKaynagiSync('lib/screens/partnership_requests_screen.dart');
      expect(istek.contains('ortakSiniriPaywalliActi('), isTrue);
    });
  });

  test('Karşılaştır sabit 5 yerine sınır sağlayıcısını okur', () {
    final src = ekranKaynagiSync('lib/screens/comparison_screen.dart');
    expect(src.contains('_selected.length >= 5'), isFalse);
    expect(src.contains('karsilastirmaSeriSiniriProvider'), isTrue);
  });

  test('Sinyal Ayarları eski "günde 1 bildirim" kapısını taşımaz', () {
    // 2026-10-10: bildirim paywall açıkken bütünüyle Premium; slot kalktı.
    final src = ekranKaynagiSync('lib/screens/signal_settings_screen.dart');
    expect(src.contains('sinyalSlotSiniriProvider'), isFalse);
    expect(src.contains('slotaSigdir('), isFalse);
    expect(src.contains('sinyalBildirimiKilitliProvider'), isTrue);
  });
}

class _SabitOrtaklar extends PartnersNotifier {
  _SabitOrtaklar(this.n);
  final int n;

  @override
  Future<List<PartnerAccount>> build() async => [
        for (var i = 0; i < n; i++)
          PartnerAccount(
            user: AppUser(
                id: 'o$i',
                email: '',
                displayName: 'Ortak $i',
                createdAt: DateTime(2026)),
            isActive: true,
          ),
      ];
}
