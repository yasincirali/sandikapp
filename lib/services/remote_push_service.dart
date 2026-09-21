import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/pref_keys.dart';

import 'notification_service.dart';
import 'push_message_router.dart';
import 'supabase_service.dart';
import 'crash_reporter.dart';

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

  /// `getToken()` en son neden fırlattı — teşhis ekranı bunu gösterir.
  ///
  /// Bu hata normalde HİÇBİR yerde görünmüyordu: `start()` çağrısı
  /// `_syncInviteDelivery` içinde `catch (_)` ile yutuluyor, Crashlytics
  /// logları da yalnızca çökme olduğunda yükleniyor. Token'ın neden
  /// yazılmadığı sorusu cevapsız kalıyordu.
  String? _sonTokenHatasi;

  /// Son `getToken()` hatası (varsa) — salt okunur teşhis.
  String? get sonTokenHatasi => _sonTokenHatasi;

  /// Cron'dan (`analyze-signals` edge function) gelen `signal_analyze_request`
  /// data-message'ı yakalandığında çağrılır. App root'ta set edilir → içinde
  /// `signalProvider.notifier.analyzePortfolio(...)` çalıştırılır.
  /// [slot] FCM data'sındaki 'morning' | 'afternoon' | 'manual' değeri.
  void Function(String slot)? _onSignalAnalyzeRequest;

  set onSignalAnalyzeRequest(void Function(String slot)? cb) {
    _onSignalAnalyzeRequest = cb;
  }

  bool get isAvailable => _available;

  Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;
    _available = Firebase.apps.isNotEmpty;
    if (!_available) return false;

    await _messaging.setAutoInitEnabled(true);

    // iOS ÖN PLAN sunumu.
    //
    // iOS varsayılan olarak uygulama ön plandayken bildirim BANNER'INI
    // göstermez — sessizce `onMessage`'a düşer. Android'de bu dal zaten elle
    // ele alınıyor (`showSignalNotification`), ama iOS'ta sistemin kendi
    // banner'ını açmak hem daha doğru görünür hem de sesi/rozeti sistem
    // yönetir.
    //
    // `alert: true` olmadan kullanıcı uygulama açıkken hiçbir şey görmez ve
    // bunu "push gelmiyor" diye okur.
    if (Platform.isIOS) {
      try {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      final userId = _activeUserId;
      if (userId == null) return;
      await _syncToken(userId, token);
    });

    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen((message) async {
      // Yönlendirme kuralları saf `pushMesajiniYonlendir`'de (test edilir);
      // burada yalnızca eylem yürütülür.
      final eylem = pushMesajiniYonlendir(
        message.data,
        notificationTitle: message.notification?.title,
        notificationBody: message.notification?.body,
      );
      switch (eylem) {
        case OrtaklikDavetiEylemi(:final inviteId, :final requesterName):
          await NotificationService.instance.showPartnerInviteNotification(
            inviteId: inviteId,
            requesterName: requesterName,
          );
        // Sunucunun ürettiği hazır sinyal bildirimi.
        //
        // Android, uygulama ÖN PLANDAYKEN `notification` payload'ını kendisi
        // GÖSTERMEZ — göstermek uygulamanın işidir. Bu dal eksikti: mesaj
        // cihaza ulaşıyor (`FLTFireMsgReceiver: broadcast received`), FCM
        // `sent` diyor, ama kullanıcı hiçbir şey görmüyordu. Arka planda ve
        // uygulama kapalıyken bildirim zaten sistem tarafından gösterilir,
        // bu yüzden burada yalnızca ön plan durumu ele alınır.
        case SinyalBildirimiEylemi(:final title, :final body, :final assetId):
          await NotificationService.instance.showSignalNotification(
            title: title,
            body: body,
            assetId: assetId,
          );
        // Cron'dan gelen "analiz zamanı" tetiği. Callback set edilmişse
        // client tarafında portföy analizini başlatır.
        case AnalizIstegiEylemi(:final slot):
          try {
            _onSignalAnalyzeRequest?.call(slot);
          } catch (_) {}
        case YokEylemi():
          break;
      }
    });

    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService.instance.handleRemoteMessageData(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      CrashReporter.arkaPlan(Future<void>.microtask(
        () => NotificationService.instance.handleRemoteMessageData(
          initialMessage.data,
          fromColdStart: true,
        ),
      ), reason: 'remote_push_service.getInitialMessage');
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

    // Debug: TestFlight'ta gerçekten hangi iznin verildiğini Crashlytics
    // log'una yaz. Firebase Console → Crashlytics → cihazın loglarında
    // görülebilir. Push hiç gelmiyorsa çoğunlukla burada authorized/denied
    // ayrımı ortaya çıkar.
    try {
      await FirebaseCrashlytics.instance.log(
          'push_permission=${settings.authorizationStatus.name} platform=$_platformName');
    } catch (_) {}

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      try {
        await FirebaseCrashlytics.instance
            .log('push_permission_denied → token sync skipped');
      } catch (_) {}
      return;
    }

    // iOS: APNs token hazır olmadan FCM token null dönebilir.
    // Kısa retry ile APNs'in register olmasını bekle.
    String? token;
    String? apnsToken;
    if (Platform.isIOS) {
      // APNs token'ı bekle — 5 retry × 2 sn = 10 sn'ye kadar.
      for (int i = 0; i < 5; i++) {
        try {
          apnsToken = await _messaging.getAPNSToken();
        } catch (_) {}
        if (apnsToken != null && apnsToken.isNotEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      // APNs token yoksa FCM token null döner. Bunu logla ki sunucudan
      // push atarken cihazın neden alıcı olarak listelenmediği anlaşılsın.
      try {
        await FirebaseCrashlytics.instance.log(
            'apns_token=${apnsToken == null ? 'NULL' : 'len=${apnsToken.length}'}');
      } catch (_) {}
      if (apnsToken != null && apnsToken.isNotEmpty) {
        for (int i = 0; i < 5; i++) {
          // `getToken()` KORUMASIZDI: fırlatırsa `start()` tümüyle çöker,
          // `_syncToken` hiç çağrılmaz ve çağıran taraf hatayı yutar
          // (`_syncInviteDelivery` → `catch (_)`) — token sessizce hiç
          // yazılmaz. APNs token'ı ÜRETİLİYOR olmasına rağmen cihazın
          // `user_push_tokens` tablosunda görünmemesi tam bu şekilde
          // açıklanabilir; sebebi de log'a yazılıyor.
          try {
            token = await _messaging.getToken();
          } catch (e) {
            _sonTokenHatasi = e.toString();
            try {
              await FirebaseCrashlytics.instance
                  .log('getToken() firlatti (deneme ${i + 1}): $e');
            } catch (_) {}
          }
          if (token != null && token.isNotEmpty) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } else {
      try {
        token = await _messaging.getToken();
      } catch (e) {
        _sonTokenHatasi = e.toString();
      }
    }
    try {
      // UUID'nin tamamı DEĞİL: Crashlytics üçüncü ülkeye giden bir işlemci,
      // tam kimlik KVKK açısından gereksiz. İlk 8 karakter korelasyona yeter.
      await FirebaseCrashlytics.instance.log(
          'fcm_token=${token == null ? 'NULL' : 'len=${token.length}'} '
          'uid8=${userId.length >= 8 ? userId.substring(0, 8) : userId}');
    } catch (_) {}
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

  /// `shared_preferences` anahtarı — cihaz kimliği burada KALICI durur.
  static const _deviceIdKey = PrefKeys.pushDeviceId;

  /// Cihaz başına kalıcı kimlik. Yoksa üretilir ve saklanır.
  ///
  /// **Neden gerekli.** FCM token'ı rotasyona uğrar (yeniden kurulum, veri
  /// temizleme, uzun süre kullanılmama). Eski satır tabloda kalırsa kullanıcı
  /// AYNI telefonda her rotasyon için bir fazla push alır — "tek sinyal, üç
  /// bildirim" şikâyetinin kaynağı buydu.
  ///
  /// `_currentToken` bu işi göremez: yalnızca bellekte durur, uygulama
  /// yeniden başlayınca `null` olur ve eski satır asla silinmez.
  ///
  /// Kimlik anonimdir — rastgele üretilir, cihazın donanım kimliğiyle
  /// ilişkisi yoktur. Uygulama silinince kaybolur; o durumda sunucudaki
  /// `(user_id, device_id)` tekilliği yeni kimlikle yeni satır açar, ama eski
  /// token zaten FCM tarafından geçersiz kılınmış olur.
  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    // `Random.secure()` — çakışma olasılığı pratikte sıfır. Kriptografik bir
    // sır değil, yalnızca ayırt edici bir etiket.
    final r = Random.secure();
    final id = cihazKimligiUret(() => r.nextInt(256));
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<void> _syncToken(String userId, String token) async {
    if (eskiTokenSilinmeli(_currentToken, token)) {
      try {
        await SupabaseService.instance.deletePushToken(_currentToken!);
      } catch (_) {
        // Eski token silinemese bile yeni token yazılsın.
      }
    }

    // Cihaz kimliği okunamazsa (prefs hatası) token yine yazılır: bildirim
    // almamaktansa fazladan bildirim almak yeğdir. Sunucudaki tekillik
    // kısıtı `device_id is not null` koşullu olduğu için bu satır kısıtı
    // tetiklemez.
    //
    // Yazım sunucuda `claim_push_token` ile (0069): token başka hesaba
    // kayıtlıysa devralınır. Aynı telefonda hesap değiştiren kullanıcı
    // eskiden RLS'e takılıp token'sız kalıyordu; çıkıştaki `stop()`
    // temizliği tek başına yetmez (bellekteki token boşsa ya da oturum
    // istemci dışında düştüyse satır kalır).
    String? deviceId;
    try {
      deviceId = await _deviceId();
    } catch (_) {}

    await SupabaseService.instance.upsertPushToken(
      userId: userId,
      token: token,
      platform: _platformName,
      deviceId: deviceId,
    );
    _currentToken = token;
  }

  String get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
