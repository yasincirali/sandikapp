import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS uzak bildirim (FCM/sinyal push) kurulumunun YAPILANDIRMA sözleşmesi.
///
/// Bu dosyadaki hiçbir şey Dart kodunu çalıştırmaz — iOS proje dosyalarını
/// metin olarak tarar. Sebep: bu katmandaki hatalar derleme hatası
/// ÜRETMEZ, çalışma zamanında da istisna atmaz. Zincir sessizce kopar ve
/// tek belirti "push gelmiyor" olur.
///
/// Gerçek vaka (2026-08-18): `user_push_tokens` tablosunda 9 token vardı ve
/// hepsi `android`'di. iPhone'dan tek satır yoktu. Sebep `AppDelegate`
/// içinde `registerForRemoteNotifications()` çağrısının hiç olmamasıydı.
void main() {
  group('iOS push kaydı', () {
    test('AppDelegate APNs kaydını AÇIKÇA tetikler', () {
      // FirebaseMessaging'in swizzling'i bunu normalde kendisi yapar ama
      // yalnızca `FirebaseApp.configure()` AppDelegate içinde çağrıldıysa.
      // Bu projede Firebase DART tarafında başlatılıyor
      // (`main.dart` → `Firebase.initializeApp()`), yani
      // `didFinishLaunchingWithOptions` çoktan dönmüş olur ve swizzling
      // pencereyi kaçırır.
      //
      // Sonuç: `getAPNSToken()` hep null → FCM token üretilmez → sunucu
      // sinyal üretse bile iOS'a gönderecek adres bulamaz.
      //
      // Live Activity bundan ETKİLENMEZ (token'ı ActivityKit'ten gelir),
      // bu yüzden "push altyapısı çalışıyor" sanılıp hata gizlenebilir.
      final kod = _yorumsuz(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      );

      expect(
        kod,
        contains('registerForRemoteNotifications()'),
        reason: 'AppDelegate APNs kaydını tetiklemiyor — getAPNSToken() '
            'null döner ve iOS cihazlar user_push_tokens tablosuna HİÇ '
            'yazılmaz (sessiz hata: derleme ve çalışma zamanı temiz)',
      );
    });

    test('entitlements aps-environment taşır', () {
      final ent =
          File('ios/Runner/Runner.entitlements').readAsStringSync();

      expect(ent, contains('aps-environment'),
          reason: 'aps-environment yok — cihaz APNs\'e kayıt olamaz');

      // TestFlight ve App Store dağıtımları ÜRETİM token'ı üretir.
      // Ortamı derleme yeri değil DAĞITIM yöntemi belirler; `development`
      // bırakılırsa TestFlight'ta token'lar BadDeviceToken ile reddedilir.
      expect(ent, contains('<string>production</string>'),
          reason: 'aps-environment production değil — TestFlight/App Store '
              'dağıtımı üretim token üretir, sunucu bunu reddeder');
    });

    test('Info.plist remote-notification arka plan modunu tanımlar', () {
      // Uygulama arka plandayken sessiz (data-only) mesajları işleyebilmek
      // için gerekir. `analyze-signals` bu yolu kullanıyor.
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('UIBackgroundModes'),
          reason: 'UIBackgroundModes yok');
      expect(plist, contains('remote-notification'),
          reason: 'remote-notification modu yok — arka plandaki data '
              'mesajları işlenmez');
    });
  });

  group('push teşhis ekranı', () {
    test('release build de ÇALIŞIR — kDebugMode ile kapatılmamış', () {
      // Bu ekranın tek işi zincirin neresinin koptuğunu göstermek ve zincir
      // ağırlıklı olarak TESTFLIGHT'ta kopuyor: APNs ortamı, provisioning
      // profile, gerçek cihaz izni. Hiçbiri debug build'de sınanmaz.
      //
      // Gerçek vaka (2026-08-18): ayarlardaki giriş debug kapısından
      // çıkarıldı ama ekranın KENDİ içindeki `if (!kDebugMode)` gözden
      // kaçtı. TestFlight'ta menü göründü, açınca "Yalnızca debug build"
      // yazdı — araç tam ihtiyaç duyulduğu anda işe yaramaz haldeydi.
      //
      // Koruma `is_admin()` RPC'lerinde (0021_cron_health_diagnostics.sql),
      // build tipinde değil.
      final kod = _dartYorumsuz(
        File('lib/screens/push_diagnostics_screen.dart').readAsStringSync(),
      );

      expect(
        kod,
        isNot(contains('kDebugMode')),
        reason: 'push teşhis ekranı kDebugMode ile kapatılmış — TestFlight\'ta '
            'işe yaramaz, oysa teşhis edilecek hatalar TAM ORADA çıkıyor',
      );
    });

    test('ayarlardaki giriş de release de görünür', () {
      // Ekranın kendisi açık olsa bile menü girişi debug'a kilitliyse
      // kullanıcı oraya ULAŞAMAZ. İki kapı da açık olmalı.
      final kod = _dartYorumsuz(
        File('lib/screens/settings_screen.dart').readAsStringSync(),
      );

      final girisSatiri = kod
          .split('\n')
          .indexWhere((l) => l.contains('PushDiagnosticsScreen'));
      expect(girisSatiri, greaterThan(-1),
          reason: 'ayarlarda push teşhisi girişi yok');

      // Girişten önceki 15 satırda `if (kDebugMode)` varsa giriş gizlidir.
      final oncekiler = kod
          .split('\n')
          .sublist((girisSatiri - 15).clamp(0, girisSatiri), girisSatiri)
          .join('\n');

      expect(
        oncekiler,
        isNot(contains('if (kDebugMode)')),
        reason: 'push teşhisi menü girişi kDebugMode kapısının arkasında — '
            'TestFlight\'ta ekrana ulaşılamaz',
      );
    });
  });
}

/// Dart yorum satırlarını eler — Swift'teki `_yorumsuz` ile aynı gerekçe.
String _dartYorumsuz(String kaynak) => kaynak
    .split('\n')
    .where((satir) => !satir.trimLeft().startsWith('//'))
    .where((satir) => !satir.trimLeft().startsWith('///'))
    .join('\n');

/// Swift yorum satırlarını eler.
///
/// `contains` doğrudan çalıştırılırsa çağrıyı ANLATAN bir yorum satırı da
/// eşleşir ve kod o çağrıyı hiç yapmasa bile test geçer. Bu tuzağa bu
/// projede daha önce iki kez düşüldü (bkz. live_activity_session_test.dart).
String _yorumsuz(String kaynak) => kaynak
    .split('\n')
    .where((satir) => !satir.trimLeft().startsWith('//'))
    .join('\n');
