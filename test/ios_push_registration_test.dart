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
}

/// Swift yorum satırlarını eler.
///
/// `contains` doğrudan çalıştırılırsa çağrıyı ANLATAN bir yorum satırı da
/// eşleşir ve kod o çağrıyı hiç yapmasa bile test geçer. Bu tuzağa bu
/// projede daha önce iki kez düşüldü (bkz. live_activity_session_test.dart).
String _yorumsuz(String kaynak) => kaynak
    .split('\n')
    .where((satir) => !satir.trimLeft().startsWith('//'))
    .join('\n');
