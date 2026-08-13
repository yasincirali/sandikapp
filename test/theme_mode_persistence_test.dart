import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema tercihinin cihazda kalıcı olması ve açılışta **flash yapmadan**
/// geri yüklenmesi.
///
/// Kullanıcı şikâyeti: light seçilip uygulama kapatılıp açıldığında önce koyu
/// bir kare görünüyordu. Sebep `ThemeModeNotifier.build()`'in koşulsuz
/// `ThemeMode.dark` döndürüp kaydedilmiş değeri async yüklemesiydi — ilk
/// frame yanlış temayla çiziliyordu.
///
/// Düzeltme: `initPreferencesCache()` ile ilk frame'den önce hazırlanan
/// senkron cache'ten okumak (bool tercihlerinde zaten kullanılan desen).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await initPreferencesCache(); // main.dart'ın yaptığı warm-up
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('ilk okuma — flash olmamalı', () {
    test('kayıtlı light, İLK build\'de doğrudan light döner', () async {
      final c = await containerWith({'pref_theme_mode': 'light'});

      expect(c.read(themeModeProvider), ThemeMode.light,
          reason: 'ilk frame dark çizilirse kullanıcı açılışta koyu bir kare '
              'görür — şikâyetin ta kendisi');
    });

    test('kayıtlı system, İLK build\'de system döner', () async {
      final c = await containerWith({'pref_theme_mode': 'system'});
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('kayıtlı dark, dark döner', () async {
      final c = await containerWith({'pref_theme_mode': 'dark'});
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    test('hiç kayıt yoksa cihazı takip eder (system)', () async {
      final c = await containerWith({});
      expect(c.read(themeModeProvider), ThemeMode.system,
          reason: 'Seçim yapılmamışken dark dayatmak, cihazı light olan '
              'kullanıcıya açılışta koyu splash gösteriyordu. Varsayılan '
              'cihaz ayarını takip etmeli; marka tercihi bunu ezmemeli.');
    });

    test('bozuk/tanınmayan değer varsayılana düşer', () async {
      final c = await containerWith({'pref_theme_mode': 'neon'});
      expect(c.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('yazma — cihazda kalıcı', () {
    test('set() diske yazar ve yeni oturumda geri okunur', () async {
      final c = await containerWith({});
      await c.read(themeModeProvider.notifier).set(ThemeMode.light);
      expect(c.read(themeModeProvider), ThemeMode.light);

      // "Uygulamayı kill edip geri gel": cache + container yeniden kurulur,
      // ama disk aynı kalır.
      await initPreferencesCache();
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);

      expect(fresh.read(themeModeProvider), ThemeMode.light,
          reason: 'tercih kill sonrası hatırlanmalı');
    });

    test('üç mod da tur atar (round-trip)', () async {
      for (final mode in ThemeMode.values) {
        final c = await containerWith({});
        await c.read(themeModeProvider.notifier).set(mode);

        await initPreferencesCache();
        final fresh = ProviderContainer();
        addTearDown(fresh.dispose);
        expect(fresh.read(themeModeProvider), mode);
      }
    });
  });
}
