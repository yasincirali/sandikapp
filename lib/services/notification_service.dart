import 'package:flutter/material.dart'
    show Color, GlobalKey, MaterialPageRoute, NavigatorState;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/technical_signal.dart';
import '../screens/partnership_requests_screen.dart';

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
  static const _partnerInvitePayloadPrefix = 'partner_invite:';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();

    _initialized = true;

    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null) {
      Future<void>.microtask(() => _handleNotificationPayload(launchPayload));
    }
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
      color: isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      colorized: true,
      ticker: ticker,
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

    final androidDetails = AndroidNotificationDetails(
      'partner_invite_channel',
      'Ortaklik Bildirimleri',
      channelDescription: 'Yeni ortaklik onay istekleri',
      importance: Importance.max,
      priority: Priority.high,
      color: const Color(0xFFF4B400),
      colorized: true,
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
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: '$_partnerInvitePayloadPrefix$inviteId',
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
      MaterialPageRoute(
        builder: (_) => PartnershipRequestsScreen(
          highlightInviteId: inviteId,
        ),
      ),
    );
  }
}
