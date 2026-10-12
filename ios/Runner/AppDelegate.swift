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

    // "Saydamlığı azalt" köprüsü — Flutter bu ayarı MediaQuery'ye taşımıyor.
    SaydamlikChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// iOS Ayarlar › Erişilebilirlik › "Saydamlığı azalt" → Dart
/// (`lib/services/saydamlik_tercihi.dart`). Açıkken cam yüzeyler opak çizilir
/// (HIG). Ayrı dosya yerine burada: yeni Swift dosyası Xcode projesine
/// (pbxproj) elle eklenmek zorunda, bu kadar küçük köprü için değmez.
enum SaydamlikChannel {
  static let name = "com.sandik.app/saydamlik"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "durum" {
        result(UIAccessibility.isReduceTransparencyEnabled)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    // Blok gözlemcisi uygulama ömrü boyunca yaşar; kaldırılmayacağı için
    // jeton tutulmaz (statik değişken Swift 6 eşzamanlılık denetimine takılır).
    _ = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      channel.invokeMethod("degisti", arguments: UIAccessibility.isReduceTransparencyEnabled)
    }
  }
}
