import Flutter
import UIKit
import UserNotifications
import Vision

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

    // Ekran görüntüsünden metin (Vision) — `lib/services/ekstre/ekran_okuyucu.dart`.
    OcrChannel.register(messenger: engineBridge.applicationRegistrar.messenger())

    // Siri Kestirmeleri + Spotlight (`SistemEylemleri.swift`). Eklenti
    // kaydıyla girer: Spotlight dokunuşu sahne olayıdır ve yalnız
    // `addSceneDelegate` ile sıraya giren nesneye dağıtılır.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SistemEylemleri") {
      SistemEylemleri.register(registrar: registrar)
    }
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

/// Ekran görüntüsünden metin satırları → Dart (`ekran_okuyucu.dart`,
/// bayrak `ekran_goruntusu_maliyet`, 2026-10-13). Apple Vision: sistemde
/// hazır, uygulama boyutuna eklemez, görüntü cihazdan çıkmaz. ML Kit eklentisi
/// seçilmedi: iOS 15.5 alt sınırı ve ~10 MB model isterdi.
///
/// Dönen her satır: metin `t`, kutu `l/u/r/b` (piksel, sol üst köşe başlangıç)
/// ve kelimeler `k` (aynı kutularla). Kelime kutuları sütunları ayırmak için:
/// Vision bir tablo satırını tek gözlem olarak verebilir.
enum OcrChannel {
  static let name = "com.sandik.app/ocr"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "oku" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let veri = (call.arguments as? FlutterStandardTypedData)?.data,
            let gorsel = UIImage(data: veri)?.cgImage else {
        result(FlutterError(code: "gorsel", message: nil, details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let satirlar = OcrChannel.oku(gorsel)
        DispatchQueue.main.async {
          if let satirlar = satirlar {
            result(satirlar)
          } else {
            result(FlutterError(code: "ocr", message: nil, details: nil))
          }
        }
      }
    }
  }

  private static func oku(_ gorsel: CGImage) -> [[String: Any]]? {
    let istek = VNRecognizeTextRequest()
    istek.recognitionLevel = .accurate
    // Dil düzeltmesi kapalı: "THYAO"yu sözcüğe, "1.234,56"yı başka sayıya
    // çevirmesin. Türkçe destekleniyorsa önce o (ş/ğ/ı fon adlarında).
    istek.usesLanguageCorrection = false
    let destek = (try? istek.supportedRecognitionLanguages()) ?? []
    let diller = ["tr-TR", "en-US"].filter { destek.contains($0) }
    if !diller.isEmpty {
      istek.recognitionLanguages = diller
    }
    let isleyici = VNImageRequestHandler(cgImage: gorsel, orientation: .up, options: [:])
    do {
      try isleyici.perform([istek])
    } catch {
      return nil
    }
    let g = CGFloat(gorsel.width)
    let y = CGFloat(gorsel.height)
    // Vision kutusu 0–1 ve sol ALT köşe başlangıçlı; Dart sol üst bekler.
    func kutu(_ r: CGRect) -> [String: Double] {
      return [
        "l": Double(r.minX * g),
        "r": Double(r.maxX * g),
        "u": Double((1 - r.maxY) * y),
        "b": Double((1 - r.minY) * y),
      ]
    }
    var out: [[String: Any]] = []
    for gozlem in istek.results ?? [] {
      guard let aday = gozlem.topCandidates(1).first else { continue }
      let metin = aday.string
      var satir: [String: Any] = ["t": metin]
      for (a, v) in kutu(gozlem.boundingBox) { satir[a] = v }
      var kelimeler: [[String: Any]] = []
      var i = metin.startIndex
      while i < metin.endIndex {
        if metin[i] == " " {
          i = metin.index(after: i)
          continue
        }
        var j = i
        while j < metin.endIndex && metin[j] != " " {
          j = metin.index(after: j)
        }
        if let k = try? aday.boundingBox(for: i..<j) {
          var kelime: [String: Any] = ["t": String(metin[i..<j])]
          for (a, v) in kutu(k.boundingBox) { kelime[a] = v }
          kelimeler.append(kelime)
        }
        i = j
      }
      satir["k"] = kelimeler
      out.append(satir)
    }
    return out
  }
}
