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
