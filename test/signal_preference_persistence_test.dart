import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sinyal tercihlerinin kalıcılığını doğrular.
///
/// Kullanıcı şikâyeti: "uygulama silinip yüklendiğinde son tercihlerim
/// görünmeli". İki ayrı katman var ve ikisi de gerekli:
///
///   1. SharedPreferences — aynı kurulum içinde uygulama yeniden açılınca
///      (bu dosyada test edilir).
///   2. Sunucu (`signal_preferences`) — uygulama SİLİNİP yeniden kurulunca
///      SharedPreferences tamamen sıfırlanır; tek kurtarıcı sunucudur.
///      Yön kritik ve `syncSignalPreferencesOnLogin` içinde: sunucuda kayıt
///      varsa o kazanır. Tersi (yereli yukarı basmak) yeni kurulumda
///      VARSAYILANLARIN kullanıcının gerçek ayarını ezmesi demekti.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // `_prefsSync` modül seviyesinde ve testler arası taşınır; her testte
    // taze mock'a bağla, aksi halde önceki testin değerleri sızar.
    await initPreferencesCache();
  });

  group('eşik kalıcılığı', () {
    test('seçilen eşik SharedPreferences\'a yazılır', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(signalThresholdProvider.notifier)
          .setForType(AssetType.hisse, 85);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('pref_signal_threshold_by_type_v1');

      expect(raw, isNotNull);
      expect(raw, contains('hisse:85'),
          reason: 'tür başına eşik "typeName:deger" formatında saklanır');
    });

    test('yeniden açılışta diskteki eşik geri yüklenir', () async {
      // Önceki oturumdan kalmış tercihler.
      SharedPreferences.setMockInitialValues({
        'pref_signal_threshold_by_type_v1': ['hisse:85', 'fon:50'],
      });
      await initPreferencesCache();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build() içindeki _load() asenkron — bir tur bekle.
      container.read(signalThresholdProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(signalThresholdProvider);
      expect(state[AssetType.hisse], 85);
      expect(state[AssetType.fon], 50);
    });

    test('kaydedilmemiş türler varsayılana (70) düşer', () async {
      SharedPreferences.setMockInitialValues({
        'pref_signal_threshold_by_type_v1': ['hisse:85'],
      });
      await initPreferencesCache();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalThresholdProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(signalThresholdProvider)[AssetType.altin],
          kSignalThresholdDefault);
    });

    test('bozuk kayıt varsayılana düşer, çökmez', () async {
      SharedPreferences.setMockInitialValues({
        // 999 geçerli seçenek değil; "abc" hiç sayı değil.
        'pref_signal_threshold_by_type_v1': ['hisse:999', 'fon:abc', 'bozuk'],
      });
      await initPreferencesCache();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(signalThresholdProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(signalThresholdProvider);
      expect(state[AssetType.hisse], kSignalThresholdDefault);
      expect(state[AssetType.fon], kSignalThresholdDefault);
    });

    test('geçersiz eşik değeri hiç kaydedilmez', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // UI yalnızca 50/70/85 sunuyor; 60 kabul edilmemeli.
      await container
          .read(signalThresholdProvider.notifier)
          .setForType(AssetType.hisse, 60);

      expect(container.read(signalThresholdProvider)[AssetType.hisse],
          kSignalThresholdDefault);
    });
  });

  group('sunucudan indirme (yeniden kurulum senaryosu)', () {
    test('applyFromServer eşiği yerele yazar', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Taze kurulum: disk boş, varsayılan 70.
      expect(container.read(signalThresholdProvider)[AssetType.hisse],
          kSignalThresholdDefault);

      // Sunucudaki gerçek tercih iner.
      await container
          .read(signalThresholdProvider.notifier)
          .applyFromServer(AssetType.hisse, 85);

      expect(container.read(signalThresholdProvider)[AssetType.hisse], 85);

      // Diske de yazılmalı — sonraki açılışta ağ beklenmesin.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pref_signal_threshold_by_type_v1'),
          contains('hisse:85'));
    });

    test('applyFromServer aralık dışı değeri yok sayar', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(signalThresholdProvider.notifier)
          .applyFromServer(AssetType.hisse, 150);

      expect(container.read(signalThresholdProvider)[AssetType.hisse],
          kSignalThresholdDefault);
    });

    test('gösterge seçimi sunucudan iner ve diske yazılır', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(indicatorPrefsProvider.notifier)
          .applyFromServer(AssetType.hisse, ['rsi', 'macd']);

      expect(container.read(indicatorPrefsProvider)[AssetType.hisse],
          {'rsi', 'macd'});
    });

    test('boş gösterge listesi yereli EZMEZ', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(indicatorPrefsProvider.notifier)
          .setForType(AssetType.hisse, {'rsi', 'macd', 'adx'});

      // Sunucudan bozuk/boş kayıt gelirse kullanıcının seçimi korunmalı.
      await container
          .read(indicatorPrefsProvider.notifier)
          .applyFromServer(AssetType.hisse, const []);

      expect(container.read(indicatorPrefsProvider)[AssetType.hisse],
          {'rsi', 'macd', 'adx'});
    });
  });

  group('bildirim ana anahtarı', () {
    test('kapatma diske yazılır ve yeniden açılışta korunur', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(signalNotificationsProvider.notifier).set(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pref_signal_notifications'), false);

      // Yeni oturum. `_BoolPrefNotifier.build()` senkron okuyabilmek için
      // warm-up edilmiş cache'e bakar; gerçek uygulamada main.dart bunu
      // widget'lar kurulmadan ÖNCE yapar (main.dart:43). Cache olmadan
      // değer bir tur sonra gelir ve ilk render varsayılanı gösterir.
      await initPreferencesCache();

      final next = ProviderContainer();
      addTearDown(next.dispose);
      expect(next.read(signalNotificationsProvider), false);
    });

    test('applyFromServer ana anahtarı sunucudan indirir', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Taze kurulumda varsayılan açık.
      expect(container.read(signalNotificationsProvider), true);

      // Kullanıcı başka cihazda kapatmışsa sunucudan kapalı iner.
      await container
          .read(signalNotificationsProvider.notifier)
          .applyFromServer(false);

      expect(container.read(signalNotificationsProvider), false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pref_signal_notifications'), false);
    });
  });
}
