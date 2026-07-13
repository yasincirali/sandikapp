import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Firebase config eksikse arka plan handler'ı sessizce no-op olur.
  }
}

class RemotePushService {
  static final RemotePushService instance = RemotePushService._();
  RemotePushService._();

  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging {
    _messagingInstance ??= FirebaseMessaging.instance;
    return _messagingInstance!;
  }

  bool _initialized = false;
  bool _available = false;
  String? _activeUserId;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  /// Cron'dan (`analyze-signals` edge function) gelen `signal_analyze_request`
  /// data-message'ı yakalandığında çağrılır. App root'ta set edilir → içinde
  /// `signalProvider.notifier.analyzePortfolio(...)` çalıştırılır.
  void Function()? _onSignalAnalyzeRequest;

  set onSignalAnalyzeRequest(void Function()? cb) {
    _onSignalAnalyzeRequest = cb;
  }

  bool get isAvailable => _available;

  Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;
    _available = Firebase.apps.isNotEmpty;
    if (!_available) return false;

    await _messaging.setAutoInitEnabled(true);

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      final userId = _activeUserId;
      if (userId == null) return;
      await _syncToken(userId, token);
    });

    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      final type = data['type']?.toString();

      if (type == NotificationService.partnerInviteType) {
        final inviteId = data['invite_id']?.toString();
        if (inviteId == null || inviteId.isEmpty) return;

        final requesterName =
            data['requester_name']?.toString().trim().isNotEmpty == true
                ? data['requester_name']!.toString().trim()
                : 'Bir kullanici';

        await NotificationService.instance.showPartnerInviteNotification(
          inviteId: inviteId,
          requesterName: requesterName,
        );
        return;
      }

      if (type == NotificationService.signalAnalyzeRequestType) {
        // Cron'dan gelen "analiz zamanı" tetiği. Callback set edilmişse
        // client tarafında portföy analizini başlatır.
        try {
          _onSignalAnalyzeRequest?.call();
        } catch (_) {}
        return;
      }
    });

    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService.instance.handleRemoteMessageData(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      Future<void>.microtask(
        () => NotificationService.instance
            .handleRemoteMessageData(initialMessage.data),
      );
    }

    return true;
  }

  Future<void> start(String userId) async {
    if (!await init()) return;

    _activeUserId = userId;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    // iOS: APNs token hazır olmadan FCM token null dönebilir.
    // Kısa retry ile APNs'in register olmasını bekle.
    String? token;
    if (Platform.isIOS) {
      for (int i = 0; i < 5; i++) {
        token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    } else {
      token = await _messaging.getToken();
    }
    if (token == null || token.isEmpty) return;

    await _syncToken(userId, token);
  }

  Future<void> stop() async {
    final token = _currentToken;
    _activeUserId = null;
    _currentToken = null;

    if (token != null && token.isNotEmpty) {
      try {
        await SupabaseService.instance.deletePushToken(token);
      } catch (_) {
        // Logout sırasında token temizliği başarısız olsa da uygulama akışı sürsün.
      }
    }
  }

  Future<void> dispose() async {
    await stop();
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _openedAppSubscription = null;
  }

  Future<void> _syncToken(String userId, String token) async {
    if (_currentToken != null &&
        _currentToken != token &&
        _currentToken!.isNotEmpty) {
      try {
        await SupabaseService.instance.deletePushToken(_currentToken!);
      } catch (_) {
        // Eski token silinemese bile yeni token yazılsın.
      }
    }

    await SupabaseService.instance.upsertPushToken(
      userId: userId,
      token: token,
      platform: _platformName,
    );
    _currentToken = token;
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
