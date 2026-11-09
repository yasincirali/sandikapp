import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crash_reporter.dart';

/// Mağaza aboneliğini yönetme (iptal, plan değişikliği) sayfasını açar.
///
/// iOS'ta Apple'ın UYGULAMA İÇİ abonelik sayfası kullanılır
/// (`AppStore.showManageSubscriptions`, `AppDelegate.swift` →
/// `AbonelikChannel`): kullanıcı uygulamadan çıkmadan iptal eder ve
/// sandbox/TestFlight'ta da ÇALIŞIR. Önceki yol `apps.apple.com/account/
/// subscriptions` yalnız mağaza aboneliklerini listeliyordu; sandbox
/// aboneliği orada görünmediği için iptal testi yapılamıyordu
/// (iOS 18'de Ayarlar'daki sandbox bölümü de yalnız Geliştirici menüsü
/// açıksa var; 2026-10-23). Kanal yoksa (eski derleme, test kabuğu) ya da
/// sayfa açılamazsa web adresi yedek olarak kalır.
///
/// Android'de Play'in abonelik sayfası açılır; uygulama içi karşılığı yok.
class AbonelikYonetimi {
  AbonelikYonetimi._();

  @visibleForTesting
  static const MethodChannel kanal = MethodChannel('com.sandik.app/abonelik');

  static final _webAdresi = {
    TargetPlatform.iOS: 'https://apps.apple.com/account/subscriptions',
    TargetPlatform.android:
        'https://play.google.com/store/account/subscriptions',
  };

  /// Web adresini açan kısım testte değiştirilebilir (url_launcher gerçek
  /// platform ister).
  @visibleForTesting
  static Future<bool> Function(Uri) webAc =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Döner: `true` → bir sayfa açıldı (uygulama içi ya da web).
  static Future<bool> ac() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final acildi = await kanal.invokeMethod<bool>('yonet');
        if (acildi == true) return true;
      } on MissingPluginException {
        // Kanalı olmayan derleme: aşağıdaki web yoluna düşer.
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'AbonelikYonetimi.ac');
      }
    }
    final adres = _webAdresi[defaultTargetPlatform];
    if (adres == null) return false;
    try {
      return await webAc(Uri.parse(adres));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AbonelikYonetimi.web');
      return false;
    }
  }
}
