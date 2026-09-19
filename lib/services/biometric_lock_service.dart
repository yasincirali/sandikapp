import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'crash_reporter.dart';

/// Doğrulama isteğinin sonucu.
///
/// **`bool` yetmiyordu.** Kullanıcı "İptal"e bastığında ile cihazda hiç
/// ekran kilidi olmadığında ekranın söyleyeceği şey aynı değil: birincisinde
/// "tekrar dene" doğru cevap, ikincisinde kullanıcı tekrar deneyerek ASLA
/// giremez. İkisini tek `false` altında toplamak kilit ekranını çıkışsız
/// bırakıyordu.
enum BiyometrikSonuc {
  /// Doğrulandı.
  basarili,

  /// Denendi, tutmadı (yanlış yüz/parmak). Tekrar denenebilir.
  reddedildi,

  /// Kullanıcı ya da sistem iptal etti: "İptal", uygulamanın arkaya gitmesi,
  /// zaman aşımı, sistem diyaloğundan başka yöntem seçme.
  iptal,

  /// Cihazda doğrulanacak bir şey YOK: ekran kilidi tanımsız, biyometri
  /// kayıtlı değil ya da donanım yok. Tekrar denemek durumu değiştirmez —
  /// kullanıcıya çıkış yolu sunulmalı.
  kullanilamaz,

  /// Geçici ya da bilinmeyen hata: UI açılamadı, çok fazla deneme sonrası
  /// kilitlenme, cihaz hatası. Tekrar denemek işe yarayabilir.
  hata;

  bool get basariliMi => this == BiyometrikSonuc.basarili;
}

/// Biyometrik / cihaz kilidi.
///
/// Değerlendirme (2026-09) §5.6: finans uygulamasında algılanan güvenin en
/// ucuz kalemi. `local_auth` sarmalanır ki ekranlar paketi doğrudan
/// görmesin ve test edilebilir bir yüzey olsun ([BiometricLockService.instance]
/// testte değiştirilebilir).
///
/// `biometricOnly: false`: Face ID/parmak izi yoksa cihaz PIN'i de kabul.
/// Amaç "başkası telefonumu alınca portföyümü görmesin"; PIN bunu sağlar.
///
/// ## `LocalAuthException` — local_auth 3.0 sözleşme değişikliği
/// Üretim çökmesi (Crashlytics, 2026-09-19): `LocalAuthDarwin.authenticate →
/// BiometricLockService.authenticate → _LockScreenState._tryUnlock`. Bu
/// sarmalayıcı yalnızca `PlatformException` yakalıyordu — 3.0 ÖNCESİNİN
/// sözleşmesi. local_auth 3.x hataları `LocalAuthException` ile fırlatıyor ve
/// **kullanıcının "İptal"e basması da bir hata** (`userCanceled`).
///
/// Sonuç iki katmanlıydı: Crashlytics'te çökme kaydı, kullanıcı tarafında
/// ise kilit ekranının donması — `_tryUnlock`'ta `await`ten sonraki satırlar
/// hiç çalışmadığı için "Doğrulanıyor…" kalıyor ve düğme bir daha
/// etkinleşmiyordu. Yani bir kez iptal eden kullanıcı uygulamaya giremiyordu.
///
/// Bu yüzden buradaki iki metot da TOTAL: `catch (e)` ile biter, hiçbir
/// koşulda fırlatmazlar. Tanınmayan hata non-fatal olarak Crashlytics'e
/// gider — sessizce yutulmaz.
class BiometricLockService {
  BiometricLockService._();

  /// Sahte alt sınıflar için. Özel kurucu (`._()`) dosya dışından
  /// çağrılamıyor, yani test sahtesi `extends` edemiyordu; kilit ekranı bu
  /// yüzden yalnızca kaynak taramasıyla korunabiliyordu. Artık gerçek widget
  /// testi yazılabiliyor (`test/kilit_ekrani_test.dart`).
  @visibleForTesting
  BiometricLockService.forTest();

  static BiometricLockService instance = BiometricLockService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Cihazda kullanılabilir bir kilit var mı (biyometrik ya da PIN).
  Future<bool> get available async {
    try {
      return await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } on MissingPluginException {
      return false;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[BiometricLock] available: $e');
      CrashReporter.report(e, st, reason: 'BiometricLockService.available');
      return false;
    }
  }

  /// Doğrulama ister. **Asla fırlatmaz** — sonucu [BiyometrikSonuc] anlatır.
  Future<BiyometrikSonuc> authenticate({
    String reason = 'sandık\'ı açmak için kimliğini doğrula',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        // Uygulama arkaya gidip dönünce sistem diyaloğu iptal etmesin.
        persistAcrossBackgrounding: true,
      );
      return ok ? BiyometrikSonuc.basarili : BiyometrikSonuc.reddedildi;
    } on LocalAuthException catch (e) {
      if (kDebugMode) debugPrint('[BiometricLock] authenticate: $e');
      return kodaGore(e);
    } on MissingPluginException {
      // Plugin kayıtlı değil (eski derleme, desteklenmeyen platform).
      return BiyometrikSonuc.kullanilamaz;
    } on PlatformException catch (e) {
      // local_auth 3.0 ÖNCESİNİN yolu. Paket artık buradan geçmiyor ama
      // kanal seviyesi hatalar (`channel-error`) hâlâ bu tipte gelebilir.
      if (kDebugMode) debugPrint('[BiometricLock] authenticate: $e');
      return BiyometrikSonuc.hata;
    } catch (e, st) {
      CrashReporter.report(e, st,
          reason: 'BiometricLockService.authenticate (bilinmeyen tip)');
      return BiyometrikSonuc.hata;
    }
  }

  /// `LocalAuthExceptionCode` → [BiyometrikSonuc].
  ///
  /// `default` bilerek var: paket dokümanı "bu enum'a yeni değer eklemek
  /// kırıcı değişiklik SAYILMAZ, istemci her zaman bir fallback koysun"
  /// diyor. Exhaustive `switch` yazmak bir sonraki paket güncellemesinde
  /// derlemeyi kırardı; burada bilinmeyen kod "hata" sayılır ve görünür olsun
  /// diye Crashlytics'e gider.
  @visibleForTesting
  static BiyometrikSonuc kodaGore(LocalAuthException e) {
    switch (e.code) {
      // Kullanıcı ya da sistem vazgeçti — hata değil, karar.
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.userRequestedFallback:
      case LocalAuthExceptionCode.timeout:
        return BiyometrikSonuc.iptal;

      // Cihazda doğrulanacak bir şey yok — tekrar denemek boşuna.
      case LocalAuthExceptionCode.noCredentialsSet:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noBiometricHardware:
        return BiyometrikSonuc.kullanilamaz;

      // Geçici: sonra ya da PIN ile olur.
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
      case LocalAuthExceptionCode.uiUnavailable:
      case LocalAuthExceptionCode.authInProgress:
        return BiyometrikSonuc.hata;

      default:
        CrashReporter.report(e, StackTrace.current,
            reason: 'BiometricLockService: ${e.code.name}');
        return BiyometrikSonuc.hata;
    }
  }

  @visibleForTesting
  static void resetForTest([BiometricLockService? fake]) {
    instance = fake ?? BiometricLockService._();
  }
}
