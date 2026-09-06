import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Tutunma ölçümünün cihaz tarafındaki hafızası.
///
/// [AnalyticsService] durumsuz bir gönderici olarak kalır; "bu eşik daha önce
/// geçildi mi", "kurulumdan kaç gün geçti", "bugün zaten aktif sayıldı mı"
/// gibi hatıra gerektiren sorular burada yanıtlanır ve SharedPreferences'ta
/// saklanır. Ayrım bilinçli: event tekrarı kohort sayımını sessizce bozar,
/// bu yüzden tekrarı eleyen katman tek ve test edilebilir olmalı.
///
/// **Anahtarlar kullanıcıya ön eklenmez.** Kurulum tarihi ve widget kullanımı
/// cihaz gerçekleridir; hesap değiştirince sıfırlanmaları ölçümü yanıltırdı.
/// (Aynı ayrım için bkz. `preferences_provider.dart` — sinyal tercihleri
/// kullanıcıya bağlı, tema/bakiye gizleme cihaza.)
class RetentionTracker {
  RetentionTracker._();
  static final RetentionTracker instance = RetentionTracker._();

  static const _kInstallDay = 'retention_install_day'; // int, epoch günü
  static const _kLastActiveDay = 'retention_last_active_day'; // int
  static const _kActiveDayCount = 'retention_active_days'; // int
  static const _kLastLaunchMs = 'retention_last_launch_ms'; // int
  static const _kMilestonePrefix = 'retention_milestone_';

  /// Arka plandan bu süreden kısa sürede dönüş YENİ AÇILIŞ SAYILMAZ.
  ///
  /// Bu eşik olmadan telefonu cebe koyup çıkarmak, bildirime bakıp geri dönmek
  /// ya da kamera açıp kapatmak ayrı birer "açılış" olarak sayılır ve günlük
  /// açılış metriği kullanıcının gerçek ritmini değil cihazın gürültüsünü
  /// ölçer. Yalnızca `resume` kaynağına uygulanır: bildirime dokunup dönmek
  /// arka plan süresinden bağımsız olarak gerçek bir açılıştır.
  static const oturumBoslugu = Duration(minutes: 30);

  /// Test için saat enjeksiyonu — üretimde [DateTime.now].
  DateTime Function() now = DateTime.now;

  SharedPreferences? _prefs;
  bool _initialized = false;

  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Kurulum gününü bir kez yazar. Tekrar çağrılması zararsızdır.
  ///
  /// `AnalyticsService.init()`'ten SONRA çağrılmalı: öncesinde gönderilen
  /// event'ler sessizce düşer (bkz. [AnalyticsService] no-op davranışı).
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await _p();
    if (prefs.getInt(_kInstallDay) == null) {
      await prefs.setInt(_kInstallDay, gunAnahtari(now()));
    }
    _initialized = true;
  }

  /// Yerel takvim gününün epoch gün numarası.
  ///
  /// UTC üzerinden normalize edilir: yerel `DateTime`'ın epoch değeri yaz
  /// saati geçişlerinde bir saat kayar ve gün farkı hesabı 0/2 gibi yanlış
  /// sonuç verebilirdi. Takvim günü yerelden okunur, aritmetik UTC'de yapılır.
  static int gunAnahtari(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Kurulumdan bu yana geçen gün. Kurulum günü yazılmamışsa 0.
  Future<int> daysSinceInstall() async {
    final prefs = await _p();
    final kurulum = prefs.getInt(_kInstallDay);
    if (kurulum == null) return 0;
    final fark = gunAnahtari(now()) - kurulum;
    return fark < 0 ? 0 : fark; // cihaz saati geriye alınmışsa negatife düşme
  }

  /// Uygulama açılışını kaydeder.
  ///
  /// [source]: `cold` | `resume` | `push` | `widget` | `live_activity`.
  /// Sayılmadıysa `false` döner (bkz. [oturumBoslugu]).
  Future<bool> recordLaunch({required String source}) async {
    final prefs = await _p();
    final simdi = now().millisecondsSinceEpoch;
    final sonAcilis = prefs.getInt(_kLastLaunchMs);
    if (source == 'resume' &&
        sonAcilis != null &&
        simdi - sonAcilis < oturumBoslugu.inMilliseconds) {
      return false;
    }
    await prefs.setInt(_kLastLaunchMs, simdi);
    await AnalyticsService.instance.logAppLaunch(
      source: source,
      daysSinceInstall: await daysSinceInstall(),
    );
    await _aktifGunKaydet();
    return true;
  }

  /// Günde bir kez sayılan "aktif gün" defteri.
  Future<void> _aktifGunKaydet() async {
    final prefs = await _p();
    final bugun = gunAnahtari(now());
    if (prefs.getInt(_kLastActiveDay) == bugun) return;
    await prefs.setInt(_kLastActiveDay, bugun);

    final sayi = (prefs.getInt(_kActiveDayCount) ?? 0) + 1;
    await prefs.setInt(_kActiveDayCount, sayi);
    await AnalyticsService.instance.setUserProperty(
      name: 'active_days',
      value: aktifGunKovasi(sayi),
    );

    // Kurulumdan 7 gün sonra hâlâ açan kullanıcı — D7'nin kohort karşılığı.
    if (await daysSinceInstall() >= 7) {
      await markActivation('first_week_survived');
    }
  }

  /// Kohort kesmek için aktif gün kovası.
  static String aktifGunKovasi(int n) {
    if (n <= 1) return '1';
    if (n <= 3) return '2-3';
    if (n <= 7) return '4-7';
    if (n <= 30) return '8-30';
    return '30+';
  }

  /// Bir defa ölçülen aktivasyon eşiği.
  ///
  /// Daha önce işaretlenmişse hiçbir şey yapmaz ve `false` döner. Tekrar
  /// gönderim, "ilk varlığını ekleyen kullanıcı sayısı" gibi sayımları
  /// kullanıcı başına birden çok kez artırarak sessizce şişirirdi.
  Future<bool> markActivation(String milestone) async {
    final prefs = await _p();
    final anahtar = '$_kMilestonePrefix$milestone';
    if (prefs.getBool(anahtar) ?? false) return false;
    await prefs.setBool(anahtar, true);
    await AnalyticsService.instance.logActivationMilestone(
      milestone: milestone,
      daysSinceInstall: await daysSinceInstall(),
    );
    return true;
  }

  /// Bir aktivasyon eşiğinin daha önce geçilip geçilmediği.
  Future<bool> hasActivation(String milestone) async {
    final prefs = await _p();
    return prefs.getBool('$_kMilestonePrefix$milestone') ?? false;
  }

  /// Portföydeki aktif alım sayısına göre aktivasyon eşiklerini işaretler.
  ///
  /// Eşikler kümülatiftir: 3'üncü varlıkta hem `first_asset` hem
  /// `three_assets` geçilmiş sayılır (kullanıcı toplu ekleme yaptıysa
  /// birinciyi hiç tetiklememiş olabilir).
  Future<void> recordAssetCount(int activeBuyCount) async {
    if (activeBuyCount >= 1) await markActivation('first_asset');
    if (activeBuyCount >= 3) await markActivation('three_assets');
  }

  /// Bildirim izni sonucu. [promptContext]: izin nerede istendi.
  Future<void> recordPushPermission({
    required bool granted,
    required String promptContext,
  }) async {
    await AnalyticsService.instance.logPushPermission(
      granted: granted,
      promptContext: promptContext,
    );
    await AnalyticsService.instance.setUserProperty(
      name: 'push_enabled',
      value: granted ? 'true' : 'false',
    );
    if (granted) await markActivation('push_granted');
  }

  /// Ana ekran / kilit ekranı widget'ından gelen dokunuş.
  ///
  /// Çağrı yeri henüz yok: native taraf (iOS `widgetURL`, Android
  /// `PendingIntent`) tıklama hedefi tanımlamıyor. Bu yüzeyi bağlamak
  /// widget funnel'ı işinin (Sprint 1) parçası.
  Future<void> recordWidgetTap({required String surface}) async {
    await AnalyticsService.instance.logWidgetTapped(surface: surface);
    await AnalyticsService.instance.setUserProperty(
      name: 'has_widget',
      value: 'true',
    );
    await markActivation('widget_used');
  }

  /// Testler arası durum sızmasını engeller.
  void resetForTest() {
    _prefs = null;
    _initialized = false;
    now = DateTime.now;
  }
}
