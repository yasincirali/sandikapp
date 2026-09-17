import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show Color, GlobalKey, NavigatorState, VoidCallback;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/asset.dart';
import '../models/position.dart' show pozisyonGorunumu;
import '../models/technical_signal.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../screens/partnership_requests_screen.dart';
import '../screens/asset_detail_screen.dart';
import '../screens/asset_not_found_screen.dart';
import '../theme/sandik.dart' show adaptiveRoute, Sandik;
import '../config/pref_keys.dart';
// `alarmSembolu`: alarm kurarken kullanılan sembol kuralı. Bildirimi
// varlığa geri eşlemek için AYNI fonksiyon kullanılmalı.
import '../widgets/alarm_kur_sheet.dart' show alarmSembolu;
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'retention_tracker.dart';

// Anahtarlar preferences_provider ile AYNI kaynaktan (PrefKeys) — ikisi
// ayrışırsa Ayarlar'daki toggle bildirim yolunu etkilemez olurdu.
const _kSignalNotificationsKey = PrefKeys.signalNotifications;
const _kPartnerNotificationsKey = PrefKeys.partnerNotifications;

Future<bool> _prefEnabled(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true; // default açık
  } catch (_) {
    return true;
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const partnerInviteType = 'partner_invite';
  static const signalAnalyzeRequestType = 'signal_analyze_request';

  /// Sunucudan gelen hazır sinyal bildirimi (analyze-signals edge function
  /// → FCM `data.type`). Uygulama ÖN PLANDAYKEN Android `notification`
  /// payload'ını sistem göstermez; bu tipi görünce bildirimi biz basarız.
  static const signalAlertType = 'signal_alert';
  static const dailyBriefType = 'daily_brief';
  static const priceAlertType = 'price_alert';
  static const _partnerInvitePayloadPrefix = 'partner_invite:';
  static const _signalPayloadPrefix = 'signal_alert:';

  /// Navigator/portföy hazır değilken yeniden deneme aralığı.
  ///
  /// Bildirime uygulama KAPALIYKEN dokunulduğunda hedef ekran hemen
  /// açılamaz: navigator henüz kurulmamış, portföy henüz yüklenmemiş olur.
  /// Bu bir animasyon süresi değildir — kısa tutulur ki soğuk açılışta
  /// yönlendirme gecikmiş hissettirmesin.
  static const _yenidenDenemeAraligi = Duration(milliseconds: 300);

  /// Yeniden deneme üst sınırı — 20 × 300ms ≈ 6 sn. Sonsuz döngü olmaz;
  /// bu süre içinde açılamazsa kullanıcı zaten uygulamanın açıldığını görür.
  static const _yenidenDenemeSiniri = 20;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }
    if (_initialized) return;

    // Durum çubuğu ikonu beyaz siluet + şeffaf zemin olmalı; Android yalnızca
    // alfa kanalını kullanır. `@mipmap/ic_launcher` renkli olduğu için düz
    // beyaz kare olarak görünüyordu.
    const android = AndroidInitializationSettings('ic_stat_sandik');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationPayload(response.payload);
      },
    );

    // Android 8+ (API 26): bildirim kanalı ÖNCEDEN oluşturulmalı.
    //
    // Sunucudan gelen push `channel_id: signal_channel` taşıyor. Kanal
    // yoksa Android mesajı sessizce düşürür — FCM "başarılı" der, cihaz
    // mesajı alır, ama kullanıcı hiçbir şey görmez. Tam olarak bu yaşandı:
    // `sent: 1, failed: 0` dönerken bildirim gölgesi boş kaldı.
    //
    // Local bildirimler kanalı ilk gösterimde kendiliğinden yaratır; uzak
    // (FCM) bildirimler yaratmaz. Bu yüzden burada açıkça kuruyoruz.
    await _createAndroidChannels();

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();

    _initialized = true;

    // Açılışı bloklamaz: izin durumu sonucu beklenmeden okunur.
    unawaited(_iosIzinDurumunuOlc());

    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null) {
      unawaited(Future<void>.microtask(
          () => _handleNotificationPayload(launchPayload)));
    }
  }

  /// Android bildirim kanallarını oluşturur (API 26+).
  ///
  /// Kanal id'leri sunucu tarafıyla eşleşmek ZORUNDA:
  /// `supabase/functions/analyze-signals/index.ts` → `channel_id`.
  /// Biri değişirse diğeri de değişmeli, aksi halde uzak bildirimler
  /// sessizce düşer.
  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return; // iOS/diğer platform — kanal kavramı yok

    // Teknik sinyal bildirimleri (sunucudan FCM ile gelir).
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'signal_channel',
        'Teknik Sinyal Bildirimleri',
        description: 'Portföyünüzdeki varlıklar için trend bildirimleri',
        importance: Importance.high,
      ),
    );

    // Ortaklık davetleri.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'partner_invite_channel',
        'Ortaklik Bildirimleri',
        description: 'Yeni ortaklik onay istekleri',
        importance: Importance.max,
      ),
    );

    // Fiyat alarmları (sunucudan FCM ile gelir).
    //
    // AYRI kanal ve YÜKSEK önem: bu, kullanıcının KENDİSİNİN kurduğu tek
    // bildirim. Brifingi kapatan biri alarmlarını açık tutabilmeli, ve
    // istediği bir bildirimin sessizce bildirim gölgesine düşmesi
    // beklentiyi bozar.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'alert_channel',
        'Fiyat Alarmlari',
        description: 'Kurdugun fiyat hedefine ulasildiginda',
        importance: Importance.high,
      ),
    );

    // Sabah brifingi (sunucudan FCM ile gelir).
    //
    // AYRI kanal olması kasıtlı: kullanıcı brifingi kapatıp sinyalleri açık
    // tutabilmeli. Tek kanal, tek "kapat" düğmesi demek olurdu ve
    // rahatsız olan kullanıcı bütün bildirimleri birden kaybederdi.
    //
    // `defaultImportance`: brifing bilgilendirir, uyarmaz — ses ve
    // kesme (heads-up) hak etmiyor.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'brief_channel',
        'Gunluk Brifing',
        description: 'Portfoyunuzdeki gunluk hareket ozeti',
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// Bildirim iznini kullanıcıya sor. Onboarding tamamlandıktan sonra çağır.
  ///
  /// [promptContext] iznin NEREDE istendiği — aynı prompt'un farklı
  /// yerlerdeki kabul oranını karşılaştırabilmek için ölçülür. İzin oranı
  /// tutunmanın en büyük tek kaldıracı olduğu için sonucu kaydedilir.
  ///
  /// **iOS burada ölçülmez.** Orada izin `init()` içindeki
  /// `requestAlertPermission` ile daha önce istenmiş oluyor; buradan ikinci
  /// bir çağrı yapılmıyor ve sonuç bilinmiyor. iOS tarafı
  /// [_iosIzinDurumunuOlc] ile sistem ayarından OKUNARAK ölçülür.
  Future<void> requestPermission({String promptContext = 'unknown'}) async {
    if (!_initialized) await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    final granted = await androidPlugin.requestNotificationsPermission();
    if (granted == null) return; // platform yanıt vermedi — tahmin yürütme
    await RetentionTracker.instance.recordPushPermission(
      granted: granted,
      promptContext: promptContext,
    );
  }

  /// iOS'ta izin durumunu sistem ayarından okur ve tutunma ölçümüne yazar.
  ///
  /// iOS izni `init()` içindeki `requestAlertPermission` ile isteniyor ve o
  /// yol sonucu döndürmüyor; [requestPermission] ise Android'e özgü. Bu
  /// yüzden push opt-in oranı yalnızca Android için biliniyordu
  /// (TECHNICAL_DEBT "iOS bildirim izni ölçülemiyor"). `checkPermissions()`
  /// bir istem değil, okumadır: kullanıcı Ayarlar'dan kapatırsa da görünür.
  ///
  /// Durum yalnızca DEĞİŞİNCE kaydedilir (ilk okuma dahil). Her açılışta
  /// yazmak "izin verdi" sayısını açılış sayısına çevirirdi.
  Future<void> _iosIzinDurumunuOlc() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) return;
    try {
      final durum = await ios.checkPermissions();
      if (durum == null) return; // platform yanıt vermedi — tahmin yürütme
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefKeys.iosPushPermissionLast) == durum.isEnabled) {
        return;
      }
      // Damga ÖNCE yazılırsa ve kayıt düşerse olay kalıcı olarak kaybolur:
      // bir sonraki açılışta damga zaten yeni değerde olduğu için yukarıdaki
      // kapı erken döner. Önce kaydet, sonra damgala.
      await RetentionTracker.instance.recordPushPermission(
        granted: durum.isEnabled,
        promptContext: 'ios_check',
      );
      await prefs.setBool(PrefKeys.iosPushPermissionLast, durum.isEnabled);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'ios_push_permission_check');
    }
  }

  Future<void> sendSignalNotification({
    required String assetName,
    required String ticker,
    required SignalType signal,
    required int buyCount,
    required int sellCount,
  }) async {
    if (!await _prefEnabled(_kSignalNotificationsKey)) return;
    if (!_initialized) await init();

    final m = buildSignalMessage(
      assetName: assetName,
      ticker: ticker,
      signal: signal,
      buyCount: buyCount,
      sellCount: sellCount,
    );
    final title = m.title;
    final body = m.body;

    final androidDetails = AndroidNotificationDetails(
      'signal_channel',
      'Teknik Sinyal Bildirimleri',
      channelDescription: 'AL/SAT teknik analiz sinyalleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      // Vurgu rengi: ikonu ve uygulama adını tonlar. `colorized` KULLANMA —
      // o bildirimin tüm arka planını boyar (medya bildirimi görünümü).
      //
      // ÜÇ durum ayrı: nötr'de eskiden `danger` (kırmızı) basılıyordu ve
      // "yön belirsiz" bildirimi düşüş uyarısı gibi görünüyordu. Renk tek
      // başına anlam taşımaz — yön ayrıca ▲▼◆ ile de veriliyor.
      color: switch (signal) {
        SignalType.buy => const Color(0xFF3DB77F),
        SignalType.sell => const Color(0xFFFF6B52),
        _ => Sandik.amber,
      },
      ticker: ticker,
      styleInformation: BigTextStyleInformation(body),
    );

    await _plugin.show(
      assetName.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Sinyal bildiriminin başlık + gövdesi — İSTEMCİ ve SUNUCU aynı dili
  /// konuşmalı.
  ///
  /// Sunucudaki eşi: `analyze-signals/index.ts` → `buildMessage`. İkisi
  /// ayrışırsa kullanıcı, push'un nereden geldiğine göre farklı biçimde
  /// bildirim alır (cron → sunucu metni, uygulama içi analiz → bu metin).
  ///
  /// **Tasarım kararları:**
  ///   * Yön OKU başlıkta en solda (▲ ▼ ◆) — kilit ekranında bildirimler
  ///     yığılır ve kullanıcı önce sol kenarı tarar. Emoji yerine geometrik
  ///     şekil: finansal ciddiyeti korur, her yazı tipinde aynı görünür.
  ///   * Kısa ETİKET (ticker) kullanılır; fon adları başlığa sığmaz ve
  ///     işletim sistemi ortadan keserek ayırt edici kısmı yok eder.
  ///   * Güven yüzdesi gövdede AÇIKÇA verilir — "çoğunluğu yukarı yönlü"
  ///     ifadesi 4/6 ile 6/6 arasındaki farkı gizliyordu.
  ///   * Yasal ibare her durumda korunur.
  static ({String title, String body}) buildSignalMessage({
    required String assetName,
    required String ticker,
    required SignalType signal,
    required int buyCount,
    required int sellCount,
  }) {
    const disclaimer = 'Yatırım tavsiyesi değildir.';
    final etiket = shortAssetLabel(assetName, ticker);
    final total = buyCount + sellCount;

    if (signal == SignalType.neutral) {
      return (
        title: '◆ $etiket · yön belirsiz',
        body: 'Göstergeler bölünmüş: $buyCount yukarı, $sellCount aşağı. '
            '$disclaimer',
      );
    }

    final isBuy = signal == SignalType.buy;
    final lehte = isBuy ? buyCount : sellCount;
    final yuzde = total > 0 ? ((lehte / total) * 100).round() : 0;

    return (
      title: isBuy ? '▲ $etiket · yukarı yönlü' : '▼ $etiket · aşağı yönlü',
      body: '$lehte/$total gösterge ${isBuy ? 'yukarı' : 'aşağı'} · '
          'güven %$yuzde. $disclaimer',
    );
  }

  /// Başlıkta kullanılacak kısa varlık etiketi.
  ///
  /// Sunucudaki eşi: `analyze-signals/index.ts` → `shortLabel`.
  ///   `TEFAS:AFO` → `AFO`      (fon kodu)
  ///   `AGHOL.IS`  → `AGHOL`    (BIST kodu)
  ///   `EURTRY=X`  → adına düş  (kur çifti; "Euro" kullanıcıya daha anlamlı)
  static String shortAssetLabel(String assetName, String ticker) {
    final t = ticker.trim();
    if (t.isEmpty || t.endsWith('=X')) return assetName;

    final sade = t.contains(':')
        ? t.split(':').last
        : t.replaceAll(RegExp(r'\.IS$', caseSensitive: false), '');

    return sade.length >= 2 ? sade : assetName;
  }

  Future<void> showPartnerInviteNotification({
    required String inviteId,
    required String requesterName,
  }) async {
    if (!await _prefEnabled(_kPartnerNotificationsKey)) return;
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'partner_invite_channel',
      'Ortaklik Bildirimleri',
      channelDescription: 'Yeni ortaklik onay istekleri',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      color: Sandik.amber, // marka amber
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      inviteId.hashCode,
      'Yeni ortaklik istegi',
      '$requesterName ortaklik kodunuzu girdi.',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: '$_partnerInvitePayloadPrefix$inviteId',
    );
  }

  /// Sunucudan gelen teknik sinyal bildirimini gösterir.
  ///
  /// Yalnızca uygulama ÖN PLANDAYKEN çağrılır. Arka planda/kapalıyken FCM
  /// `notification` payload'ını Android'in kendisi gösterir; oraya ikinci
  /// bir bildirim basmak çift gösterime yol açar.
  ///
  /// Kanal `signal_channel` — sunucudaki `channel_id` ile aynı olmak
  /// zorunda (bkz. `_createAndroidChannels`).
  Future<void> showSignalNotification({
    required String title,
    required String body,
    required String assetId,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'signal_channel',
      'Teknik Sinyal Bildirimleri',
      channelDescription: 'Portföyünüzdeki varlıklar için trend bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      color: Sandik.amber, // marka amber
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      assetId.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      // PAYLOAD ŞART: bu alan boş bırakılmıştı, bu yüzden ön planda basılan
      // bildirime dokunmak hiçbir şey yapmıyordu. Tıklama bilgisiz kalıyordu
      // — hangi varlığa ait olduğu kayboluyordu.
      payload: assetId.isEmpty ? null : '$_signalPayloadPrefix$assetId',
    );
  }

  /// Uzak bildirime dokunulduğunda çalışır.
  ///
  /// [fromColdStart] uygulamanın bu bildirimle SIFIRDAN açıldığını söyler
  /// (`getInitialMessage`). O durumda açılış kaydı YAPILMAZ: soğuk açılış
  /// zaten `_initDeferredServices` içinde bir kez yazılıyor ve buradan
  /// ikinci bir kayıt aynı açılışı çift saydırırdı. Sıcak açılışta
  /// (`onMessageOpenedApp`) böyle bir çakışma yok, kaynak `push` yazılır.
  void handleRemoteMessageData(
    Map<String, dynamic> data, {
    bool fromColdStart = false,
  }) {
    final type = data['type']?.toString();

    // Hangi bildirim tipinin gerçekten açıldığını ölçmek, hangisinin
    // kapatılmayı hak ettiğini söyler (bkz. RETENTION_STRATEJISI.md §7:
    // dört hafta boyunca açılma oranı %3'ün altında kalan tip kapatılır).
    //
    // Sessiz tetikleyiciler ölçüme girmez: kullanıcı onlara dokunmuyor.
    if (type != null && type != signalAnalyzeRequestType) {
      AnalyticsService.instance.logPushOpened(type: type);
      if (!fromColdStart) {
        unawaited(RetentionTracker.instance.recordLaunch(source: 'push'));
      }
    }

    // Brifingin varış yeri ana ekrandır — uygulamanın açılması yeterli,
    // ayrıca bir yere yönlendirilmez. Bildirim tek bir varlığa değil
    // portföyün geneline dair.
    if (type == dailyBriefType) return;

    // Fiyat alarmı: alarmın kurulduğu varlığın ekranı, GÜNLÜK sekmesinde.
    //
    // ÖNCEKİ KARAR ve neden değişti (2026-09-15, kullanıcı isteği): bildirim
    // ana ekranda bırakılıyordu — gerekçe "kullanıcı fiyatı öğrenmek için
    // geliyor, alarm listesini yönetmek için değil"di. Gerekçenin ilk yarısı
    // DOĞRU, çıkarımı yanlıştı: doğru varış yeri alarm listesi değil ama ana
    // ekran da değil, alarmın konusu olan VARLIK. Ana ekran kullanıcıya
    // "hangi varlık?" sorusunu tekrar sordurtuyordu.
    //
    // Hedef sembolle taşınır (`asset_id` yok — bkz. [openPriceAlertAsset]).
    if (type == priceAlertType) {
      final symbol = data['symbol']?.toString();
      if (symbol == null || symbol.isEmpty) return;
      openPriceAlertAsset(symbol);
      return;
    }

    // Sinyal bildirimine dokunulduğunda o varlığın performans ekranı açılır
    // (grafiğin altında teknik sinyal paneli var — kullanıcının bildirimden
    // sonra görmek istediği yer orasıdır).
    //
    // Bu dal EKSİKTİ: yalnızca `partnerInviteType` ele alınıyordu, sinyal
    // bildirimine dokunmak uygulamayı açıp ana ekranda bırakıyordu.
    if (type == signalAlertType) {
      final assetId = data['asset_id']?.toString();
      if (assetId == null || assetId.isEmpty) return;
      openAssetPerformance(assetId);
      return;
    }

    if (type != partnerInviteType) return;

    final inviteId = data['invite_id']?.toString();
    if (inviteId == null || inviteId.isEmpty) return;
    _openPartnerInvite(inviteId);
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null) return;

    // Dokunulan bildirimin tipi — hangi bildirim tipinin gerçekten
    // açıldığını ölçmek, hangisinin kapatılmayı hak ettiğini söyler.
    AnalyticsService.instance.logPushOpened(
      type: payload.startsWith(_signalPayloadPrefix)
          ? signalAlertType
          : payload.startsWith(_partnerInvitePayloadPrefix)
              ? partnerInviteType
              : 'other',
    );

    if (payload.startsWith(_signalPayloadPrefix)) {
      final assetId = payload.substring(_signalPayloadPrefix.length);
      if (assetId.isNotEmpty) openAssetPerformance(assetId);
      return;
    }

    if (!payload.startsWith(_partnerInvitePayloadPrefix)) return;

    final inviteId = payload.substring(_partnerInvitePayloadPrefix.length);
    _openPartnerInvite(inviteId);
  }

  /// Çan sayfasındaki ortaklık bildirimine dokunuş — push'a dokunulmuş
  /// gibi aynı davet akışı (0066).
  void openPartnerInvite(String inviteId) => _openPartnerInvite(inviteId);

  void _openPartnerInvite(String inviteId) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null) {
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => _openPartnerInvite(inviteId),
      );
      return;
    }

    navigator.push(
      adaptiveRoute<void>(
        builder: (_) => PartnershipRequestsScreen(
          highlightInviteId: inviteId,
        ),
      ),
    );
  }

  /// Sinyal bildiriminden varlığın performans ekranına gider.
  ///
  /// [AssetDetailScreen] grafiğin ALTINDA teknik sinyal panelini gösterir —
  /// bildirimdeki "4/6 gösterge yukarı" özetinin dayanağı orada açılır.
  ///
  /// Varlık `id` üzerinden provider'dan çözülür; bildirim yalnızca `asset_id`
  /// taşır (ad ve fiyat push anında eskimiş olabilir, taşımanın anlamı yok).
  ///
  /// [deneme] yeniden deneme sayacıdır: bildirime uygulama KAPALIYKEN
  /// dokunulduğunda portföy henüz yüklenmemiş olur ve varlık bulunamaz.
  /// Sonsuz döngü olmaması için sınırlıdır — bulunamazsa sessizce vazgeçilir
  /// (kullanıcı uygulamanın açıldığını zaten görür).
  /// Dışarıdan da çağrılır (derin bağlantı `sandik://asset/<id>`,
  /// bkz. `DeepLinkRouter.hedefVarlikId`).
  ///
  /// [onNotFound]: hedef bu hesabın portföyünde yoksa (ya da portföy
  /// beklenen sürede gelmediyse) çağrılır. Push bildirimi yolu vermez —
  /// silinmiş varlığın eski bildirimi için hata göstermek yanıltıcı olur.
  /// Dış derin bağlantı (`DeepLinkService`) verir — kullanıcı bir bağlantıya
  /// dokundu, hiçbir şey olmaması "uygulama bozuk" hissi verir.
  void openAssetPerformance(
    String assetId, {
    int deneme = 0,
    VoidCallback? onNotFound,
    int? initialPeriodDays,
  }) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;

    if (navigator == null || context == null) {
      if (deneme >= _yenidenDenemeSiniri) return;
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => openAssetPerformance(
          assetId,
          deneme: deneme + 1,
          onNotFound: onNotFound,
          initialPeriodDays: initialPeriodDays,
        ),
      );
      return;
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final assets = container.read(portfolioProvider).valueOrNull?.assets;

    // Portföy henüz gelmediyse bekle — uygulama soğuk açılışta bildirimden
    // geliyorsa veri birkaç saniye sonra düşer.
    if (assets == null || assets.isEmpty) {
      if (deneme >= _yenidenDenemeSiniri) {
        // Oturum yoksa portföy hiç gelmez; giriş ekranının üstüne "varlık
        // bulunamadı" açmak yanıltıcı olur — bağlantı sessizce düşer.
        // Oturum varsa portföy gerçekten boş / hedef yok → tepki ver.
        final user = container.read(authProvider).valueOrNull;
        if (user != null) onNotFound?.call();
        return;
      }
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => openAssetPerformance(
          assetId,
          deneme: deneme + 1,
          onNotFound: onNotFound,
          initialPeriodDays: initialPeriodDays,
        ),
      );
      return;
    }

    Asset? asset;
    for (final a in assets) {
      if (a.id == assetId) {
        asset = a;
        break;
      }
    }

    // Varlık silinmiş olabilir (bildirim gönderildikten sonra). Bildirim
    // yolunda sessiz geçmek doğru: olmayan bir varlık için boş ekran açmak
    // yanıltıcı olur. Dış bağlantı yolu [onNotFound] ile kendi tepkisini verir.
    if (asset == null) {
      onNotFound?.call();
      return;
    }

    // Ekrana PORTFÖY LİSTESİYLE AYNI nesne gider: pozisyonun net miktarlı
    // görüntü varlığı + aktif lot'ları (marker'lar için). Eskiden ham lot
    // veriliyordu; eşleşen lot bir satış ya da silinmiş kayıtsa
    // `HistoryService` onu fiyatlamıyor ve grafik "veri çekilemedi"
    // diyordu — aynı altın portföyden açılınca çiziliyordu (kullanıcı
    // bildirimi 2026-09-17). Pozisyon kapalıysa (tamamı satılmış) ham
    // lot'a düşülür: kullanıcı yine de kendi kaydını görebilmeli.
    final gorunum = pozisyonGorunumu(assets, asset);

    navigator.push(
      adaptiveRoute<void>(
        builder: (_) => AssetDetailScreen(
          asset: gorunum?.asset ?? asset!,
          showBackButton: true,
          lots: gorunum?.lots ?? [asset!],
          initialPeriodDays: initialPeriodDays,
        ),
      ),
    );
  }

  /// Fiyat alarmı bildiriminden varlık ekranını açar — GÜNLÜK sekmesinde.
  ///
  /// **Neden ayrı bir yol:** alarm payload'ı `asset_id` TAŞIMAZ, `symbol`
  /// taşır (`ALTIN_GRAM`, `THYAO.IS`…). Sunucu tarafı alarmı sembol üstünden
  /// kurar ve kullanıcının hangi lot'undan geldiğini bilmez; zaten aynı
  /// sembolde birden çok lot olabilir. Eşleştirme burada, istemcide yapılır:
  /// `alarmSembolu` alarm kurarken hangi kuralı uyguladıysa aynısı tersine
  /// çevrilir — iki yönün AYNI fonksiyonu kullanması şart, aksi halde alarm
  /// kurulabilen ama bildirimi açılamayan bir varlık ortaya çıkar.
  ///
  /// **Neden GÜNLÜK:** kullanıcı "hedefi geçti" bildirimine dokunduğunda tek
  /// bir seansı sorar, trendi değil. Varsayılan sekme (1H) o soruyu
  /// cevaplamıyordu.
  ///
  /// Aynı sembolde birden çok lot varsa ilki açılır: `openAssetPerformance`
  /// zaten `positionKey` ile tüm lot'ları toplayıp grafiğe marker basar,
  /// yani hangi lot'la girildiği ekranda fark yaratmaz.
  void openPriceAlertAsset(
    String symbol, {
    int deneme = 0,
    VoidCallback? onNotFound,
  }) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;

    if (navigator == null || context == null) {
      if (deneme >= _yenidenDenemeSiniri) return;
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => openPriceAlertAsset(
          symbol,
          deneme: deneme + 1,
          onNotFound: onNotFound,
        ),
      );
      return;
    }

    final container = ProviderScope.containerOf(context, listen: false);
    final assets = container.read(portfolioProvider).valueOrNull?.assets;

    // Soğuk açılış: portföy birkaç saniye sonra düşer (bkz.
    // [openAssetPerformance] — aynı bekleme kuralı).
    if (assets == null || assets.isEmpty) {
      if (deneme >= _yenidenDenemeSiniri) {
        final user = container.read(authProvider).valueOrNull;
        if (user != null) onNotFound?.call();
        return;
      }
      Future<void>.delayed(
        _yenidenDenemeAraligi,
        () => openPriceAlertAsset(
          symbol,
          deneme: deneme + 1,
          onNotFound: onNotFound,
        ),
      );
      return;
    }

    final hedef = symbol.trim().toUpperCase();
    Asset? eslesen;
    for (final a in assets) {
      final sembol = alarmSembolu(a.ticker, a.subCategory);
      if (sembol != null && sembol.toUpperCase() == hedef) {
        eslesen = a;
        break;
      }
    }

    // Varlık satılmış/silinmiş olabilir — alarm sunucuda kalmış olsa bile.
    // Sessiz geçmek doğru: olmayan varlık için boş ekran açmak yanıltıcı.
    if (eslesen == null) {
      onNotFound?.call();
      return;
    }

    openAssetPerformance(
      eslesen.id,
      onNotFound: onNotFound,
      // days: 0 → GÜNLÜK. Desteklenmiyorsa (elle fiyatlanan varlık) ekran
      // sessizce varsayılana düşer.
      initialPeriodDays: 0,
    );
  }

  /// Dış bağlantının hedefi bulunamadığında hata ekranı. Navigator hazır
  /// değilse çağrılmaz — [openAssetPerformance] bunu zaten garanti eder.
  void showAssetNotFound() {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    navigator.push(
      adaptiveRoute<void>(builder: (_) => const AssetNotFoundScreen()),
    );
  }
}
