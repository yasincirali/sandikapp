import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/retention_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tutunma defterinin doğruluğu.
///
/// Bu testlerin varlık sebebi: yanlış ölçüm, ölçüm yokluğundan daha kötüdür.
/// Kurulum günü kayarsa D1/D7 kohortları; aktivasyon eşiği iki kez giderse
/// "ilk varlığını ekleyen kullanıcı sayısı" sessizce şişer ve sonraki tüm
/// kararlar bozuk bir taban çizgisine dayanır.
///
/// [AnalyticsService] burada kasıtlı olarak init edilmez; Firebase yokken
/// tüm log çağrıları no-op'tur, dolayısıyla test edilen şey yalnızca
/// defterin mantığıdır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RetentionTracker izleyici;
  late DateTime saat;

  /// 2026-09-06 10:00 yerel — sabit başlangıç.
  DateTime baslangic() => DateTime(2026, 9, 6, 10, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    saat = baslangic();
    izleyici = RetentionTracker.instance;
    izleyici.resetForTest();
    izleyici.now = () => saat;
    await izleyici.init();
  });

  tearDown(() => RetentionTracker.instance.resetForTest());

  group('kurulum günü', () {
    test('ilk init kurulum gününü yazar, sonraki initler değiştirmez',
        () async {
      expect(await izleyici.daysSinceInstall(), 0);

      // Uygulama yeniden açıldı: aynı prefs, yeni bir gün.
      saat = baslangic().add(const Duration(days: 3));
      izleyici.resetForTest();
      izleyici.now = () => saat;
      await izleyici.init();

      expect(await izleyici.daysSinceInstall(), 3,
          reason: 'kurulum günü ikinci initte üzerine yazılmamalı');
    });

    test('gün farkı takvim gününe göre hesaplanır, 24 saate göre değil',
        () async {
      // Kurulum 10:00; ertesi sabah 09:00 — 24 saat DOLMADI ama takvim
      // günü değişti. D1 kohortu takvim günü üzerinden tanımlıdır.
      saat = DateTime(2026, 9, 7, 9, 0);
      expect(await izleyici.daysSinceInstall(), 1);
    });

    test('cihaz saati geriye alınırsa negatif gün üretmez', () async {
      saat = baslangic().subtract(const Duration(days: 5));
      expect(await izleyici.daysSinceInstall(), 0);
    });
  });

  group('açılış kaydı', () {
    test('soğuk açılış her zaman sayılır', () async {
      expect(await izleyici.recordLaunch(source: 'cold'), isTrue);
      expect(await izleyici.recordLaunch(source: 'cold'), isTrue);
    });

    test('kısa arka plan dönüşü yeni açılış sayılmaz', () async {
      await izleyici.recordLaunch(source: 'cold');

      saat = baslangic().add(const Duration(minutes: 5));
      expect(await izleyici.recordLaunch(source: 'resume'), isFalse,
          reason: 'cepten çıkarmak açılış değildir');

      saat = baslangic().add(const Duration(minutes: 31));
      expect(await izleyici.recordLaunch(source: 'resume'), isTrue);
    });

    test('bildirimden dönüş boşluk kuralına takılmaz', () async {
      await izleyici.recordLaunch(source: 'cold');
      saat = baslangic().add(const Duration(minutes: 2));
      expect(await izleyici.recordLaunch(source: 'push'), isTrue,
          reason: 'bildirime dokunmak gerçek bir açılıştır');
    });
  });

  group('aktivasyon eşikleri', () {
    test('bir eşik yalnızca bir kez işaretlenir', () async {
      expect(await izleyici.markActivation('first_asset'), isTrue);
      expect(await izleyici.markActivation('first_asset'), isFalse);
      expect(await izleyici.hasActivation('first_asset'), isTrue);
    });

    test('eşikler kümülatiftir — toplu ekleme birinciyi de geçmiş sayar',
        () async {
      await izleyici.recordAssetCount(3);
      expect(await izleyici.hasActivation('first_asset'), isTrue);
      expect(await izleyici.hasActivation('three_assets'), isTrue);
    });

    test('iki varlık üçüncü eşiği geçmez', () async {
      await izleyici.recordAssetCount(2);
      expect(await izleyici.hasActivation('first_asset'), isTrue);
      expect(await izleyici.hasActivation('three_assets'), isFalse);
    });

    test('izin verilince push_granted işaretlenir, reddedilince işaretlenmez',
        () async {
      await izleyici.recordPushPermission(
          granted: false, promptContext: 'test');
      expect(await izleyici.hasActivation('push_granted'), isFalse);

      await izleyici.recordPushPermission(
          granted: true, promptContext: 'test');
      expect(await izleyici.hasActivation('push_granted'), isTrue);
    });
  });

  group('aktif gün defteri', () {
    test('birinci hafta eşiği 7. günden önce geçilmez', () async {
      await izleyici.recordLaunch(source: 'cold');
      expect(await izleyici.hasActivation('first_week_survived'), isFalse);

      saat = baslangic().add(const Duration(days: 6));
      await izleyici.recordLaunch(source: 'cold');
      expect(await izleyici.hasActivation('first_week_survived'), isFalse,
          reason: '6. gün henüz bir hafta değil');

      saat = baslangic().add(const Duration(days: 7));
      await izleyici.recordLaunch(source: 'cold');
      expect(await izleyici.hasActivation('first_week_survived'), isTrue);
    });

    test('aynı gün içindeki ikinci açılış aktif günü tekrar saymaz', () async {
      await izleyici.recordLaunch(source: 'cold');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('retention_active_days'), 1);

      saat = baslangic().add(const Duration(hours: 6));
      await izleyici.recordLaunch(source: 'cold');
      expect(prefs.getInt('retention_active_days'), 1);

      saat = baslangic().add(const Duration(days: 1));
      await izleyici.recordLaunch(source: 'cold');
      expect(prefs.getInt('retention_active_days'), 2);
    });
  });

  group('aktif gün kovası', () {
    test('kohort sınırları', () {
      expect(RetentionTracker.aktifGunKovasi(1), '1');
      expect(RetentionTracker.aktifGunKovasi(3), '2-3');
      expect(RetentionTracker.aktifGunKovasi(7), '4-7');
      expect(RetentionTracker.aktifGunKovasi(30), '8-30');
      expect(RetentionTracker.aktifGunKovasi(31), '30+');
    });
  });
}
