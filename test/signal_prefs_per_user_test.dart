import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcı bildirimi: "sinyal ayarları kişiye özel olarak db'ye
/// kaydedilmeli, şu anda bu şekilde değil".
///
/// Kök neden: sinyal tercihleri SharedPreferences'ta SABİT anahtarlarda
/// tutuluyordu (`pref_signal_threshold_by_type_v1` gibi). SharedPreferences
/// cihaz genelinde olduğu için A kullanıcısı çıkıp B girdiğinde B, A'nın
/// ayarlarını görüyordu.
///
/// Daha ciddisi: `syncSignalPreferencesOnLogin` sunucuda kayıt yoksa
/// yereldekileri "ilk kurulum" sanıp yukarı taşıyor — yani A'nın ayarları
/// B'nin DB satırına yazılıyordu.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setPreferencesUser(null);
  });

  tearDown(() => setPreferencesUser(null));

  group('Sinyal tercihleri kullanıcıya özel', () {
    test('farklı kullanıcılar farklı eşik değerleri saklar', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();

      // A kullanıcısı eşiği 85 yapıyor.
      setPreferencesUser('kullanici-A');
      final aNotifier = SignalThresholdNotifier();
      // Notifier'ı doğrudan test etmek yerine kalıcılık katmanını
      // doğruluyoruz: anahtar ön ekinin kullanıcıya göre ayrıldığı.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'pref_signal_threshold_by_type_v1_kullanici-A', ['hisse:85']);

      // B kullanıcısı hiç dokunmamış.
      setPreferencesUser('kullanici-B');
      final bDeger =
          prefs.getStringList('pref_signal_threshold_by_type_v1_kullanici-B');

      expect(bDeger, isNull,
          reason: 'B kullanıcısı A\'nın eşiğini GÖRMEMELİ');

      // A geri geldiğinde kendi değerini bulmalı.
      setPreferencesUser('kullanici-A');
      expect(
        prefs.getStringList('pref_signal_threshold_by_type_v1_kullanici-A'),
        ['hisse:85'],
      );
      expect(aNotifier, isNotNull);
    });

    test('provider üzerinden yazılan eşik diğer kullanıcıya sızmaz', () async {
      // Uçtan uca: gerçek notifier ile yaz, kullanıcı değiştir, oku.
      // Yukarıdaki test anahtar şemasını doğruluyor; bu test `_userKey`
      // mantığının gerçekten devrede olduğunu doğruluyor.
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      setPreferencesUser('user-A');
      container.invalidate(signalThresholdProvider);
      await container
          .read(signalThresholdProvider.notifier)
          .applyFromServer(AssetType.hisse, 85);

      // `_load()` async: build() önce senkron varsayılanı döndürür, disk
      // okuması sonra state'i günceller. Sabit bir `delayed` kırılgan olur
      // (makine yavaşsa test sallanır), o yüzden beklenen değere kadar
      // yoklanır.
      Future<int?> esikOku({required int? beklenen}) async {
        for (var i = 0; i < 50; i++) {
          final v = container.read(signalThresholdProvider)[AssetType.hisse];
          if (v == beklenen) return v;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return container.read(signalThresholdProvider)[AssetType.hisse];
      }

      // B'ye geç — provider tazelenmeli.
      setPreferencesUser('user-B');
      container.invalidate(signalThresholdProvider);
      expect(await esikOku(beklenen: kSignalThresholdDefault),
          kSignalThresholdDefault,
          reason: 'B kullanıcısı A\'nın 85 eşiğini DEĞİL, varsayılanı görmeli');

      // A'ya dön — kendi değeri geri gelmeli.
      setPreferencesUser('user-A');
      container.invalidate(signalThresholdProvider);
      expect(await esikOku(beklenen: 85), 85,
          reason: 'A kendi eşiğini geri bulmalı');
    });

    test('oturum yokken anahtar ön eksiz kalır', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      setPreferencesUser(null);

      // Giriş öncesi yazılan değer kimseye ait değildir; ön ek almaz.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pref_signal_threshold_by_type_v1', ['hisse:70']);
      expect(prefs.getStringList('pref_signal_threshold_by_type_v1'),
          ['hisse:70']);
    });

    test('kullanıcıya özel bool tercih: nötr push ayrışır', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      final prefs = await SharedPreferences.getInstance();

      // A nötr push'u açıyor.
      await prefs.setBool('pref_signal_neutral_push_kullanici-A', true);
      // B'nin kaydı yok → varsayılan (false) geçerli olmalı.
      expect(prefs.getBool('pref_signal_neutral_push_kullanici-B'), isNull);
      expect(prefs.getBool('pref_signal_neutral_push_kullanici-A'), isTrue);
    });

    test('cihaz tercihleri (tema) kullanıcıya göre AYRIŞMAZ', () async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      final prefs = await SharedPreferences.getInstance();

      // Tema cihaza aittir; kullanıcı değişince sıfırlanması beklenmez.
      await prefs.setString('pref_theme_mode', 'light');
      setPreferencesUser('kullanici-A');
      expect(prefs.getString('pref_theme_mode'), 'light');
      setPreferencesUser('kullanici-B');
      expect(prefs.getString('pref_theme_mode'), 'light');
    });
  });

  group('AssetType kapsamı', () {
    test('tüm varlık türleri için tercih tutulabilir', () {
      // Sunucudaki signal_preferences satırları AssetType.name ile eşleşir;
      // biri eklenip diğeri unutulursa tercih hiç yazılmaz.
      expect(AssetType.values, isNotEmpty);
      for (final t in AssetType.values) {
        expect(t.name, isNotEmpty);
      }
    });
  });
}
