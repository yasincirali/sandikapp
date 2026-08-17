import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Uygulama foreground'dayken push banner göster
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    // APNs'e KAYIT — bu satır olmadan `getAPNSToken()` hep `nil` döner.
    //
    // Normalde FirebaseMessaging'in swizzling'i bunu kendisi yapar, ama
    // yalnızca `FirebaseApp.configure()` AppDelegate İÇİNDE çağrıldıysa.
    // Bu projede Firebase Dart tarafında başlatılıyor
    // (`main.dart` → `Firebase.initializeApp()`), yani bu metot çoktan
    // dönmüş oluyor ve swizzling pencereyi kaçırıyor. Cihaz APNs'e hiç
    // kayıt olmuyordu.
    //
    // Zincir sessizce kopuyordu: APNs token yok → `getToken()` null →
    // `user_push_tokens` tablosuna hiçbir iOS satırı yazılmıyor → sunucu
    // sinyal üretse bile gönderecek adres bulamıyor. Tabloda 9 token
    // vardı ve hepsi `android`'di.
    //
    // Live Activity bundan ETKİLENMEDİĞİ için hata gizlendi: onun token'ı
    // ActivityKit'ten (`pushType: .token`) gelir, bu yoldan geçmez.
    //
    // İzin isteme AYRI bir konudur ve Dart tarafında yapılır
    // (`RemotePushService.start` → `requestPermission`). Burada yalnızca
    // kayıt tetiklenir; kullanıcı izni reddederse APNs token yine gelir
    // ama sistem bildirimi göstermez.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Live Activity köprüsü.
    //
    // Kayıt BURADA yapılır, `application(_:didFinishLaunching...)` içinde
    // değil: bu proje implicit engine kullanıyor ve o noktada
    // `window.rootViewController` henüz bir `FlutterViewController`
    // olmayabilir. Engine bridge'in messenger'ı ise bu geri çağrımda
    // hazır olduğu garanti edilir.
    // Messenger, bridge'in `applicationRegistrar`'ı üzerinden alınır
    // (`FlutterApplicationRegistrar` → `FlutterBaseRegistrar.messenger()`).
    // Bridge protokolünde doğrudan bir binary messenger özelliği YOKTUR —
    // yalnızca `pluginRegistry` ve `applicationRegistrar` vardır.
    LiveActivityChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
