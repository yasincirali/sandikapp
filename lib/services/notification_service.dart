import 'package:flutter/material.dart'
    show Color, GlobalKey, NavigatorState;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/technical_signal.dart';
import '../screens/partnership_requests_screen.dart';
import '../theme/sandik.dart' show adaptiveRoute, Sandik;

const _kSignalNotificationsKey = 'pref_signal_notifications';
const _kPartnerNotificationsKey = 'pref_partner_notifications';

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
  static const _partnerInvitePayloadPrefix = 'partner_invite:';

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

    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null) {
      Future<void>.microtask(() => _handleNotificationPayload(launchPayload));
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
  }

  /// Bildirim iznini kullanıcıya sor. Onboarding tamamlandıktan sonra çağır.
  Future<void> requestPermission() async {
    if (!_initialized) await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
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

    final isBuy = signal == SignalType.buy;
    final total = buyCount + sellCount;
    // Yasal not: "AL/SAT sinyali" yerine trend yönü ifadesi kullanılıyor.
    final title = isBuy
        ? 'Yukarı trend: $assetName'
        : 'Aşağı trend: $assetName';
    final body = isBuy
        ? 'Göstergelerin çoğunluğu yukarı yönlü ($buyCount/$total). '
            'Yatırım tavsiyesi değildir.'
        : 'Göstergelerin çoğunluğu aşağı yönlü ($sellCount/$total). '
            'Yatırım tavsiyesi değildir.';

    final androidDetails = AndroidNotificationDetails(
      'signal_channel',
      'Teknik Sinyal Bildirimleri',
      channelDescription: 'AL/SAT teknik analiz sinyalleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sandik',
      // Vurgu rengi: ikonu ve uygulama adını tonlar. `colorized` KULLANMA —
      // o bildirimin tüm arka planını boyar (medya bildirimi görünümü).
      color: isBuy ? const Color(0xFF10B981) : Sandik.danger,
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
    );
  }

  void handleRemoteMessageData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type != partnerInviteType) return;

    final inviteId = data['invite_id']?.toString();
    if (inviteId == null || inviteId.isEmpty) return;
    _openPartnerInvite(inviteId);
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || !payload.startsWith(_partnerInvitePayloadPrefix)) {
      return;
    }

    final inviteId = payload.substring(_partnerInvitePayloadPrefix.length);
    _openPartnerInvite(inviteId);
  }

  void _openPartnerInvite(String inviteId) {
    final navigator = _navigatorKey?.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null) {
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        () => _openPartnerInvite(inviteId),
      );
      return;
    }

    navigator.push(
      adaptiveRoute(
        builder: (_) => PartnershipRequestsScreen(
          highlightInviteId: inviteId,
        ),
      ),
    );
  }
}
