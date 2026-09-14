import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Biyometrik / cihaz kilidi.
///
/// Değerlendirme (2026-09) §5.6: finans uygulamasında algılanan güvenin en
/// ucuz kalemi. `local_auth` sarmalanır ki ekranlar paketi doğrudan
/// görmesin ve test edilebilir bir yüzey olsun ([BiometricLockService.instance]
/// testte değiştirilebilir).
///
/// `biometricOnly: false`: Face ID/parmak izi yoksa cihaz PIN'i de kabul.
/// Amaç "başkası telefonumu alınca portföyümü görmesin"; PIN bunu sağlar.
class BiometricLockService {
  BiometricLockService._();
  static BiometricLockService instance = BiometricLockService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Cihazda kullanılabilir bir kilit var mı (biyometrik ya da PIN).
  Future<bool> get available async {
    try {
      return await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[BiometricLock] available: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Doğrulama ister. Başarısız, iptal, kilit yok → false. Asla fırlatmaz.
  Future<bool> authenticate({
    String reason = 'sandık\'ı açmak için kimliğini doğrula',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        // Uygulama arkaya gidip dönünce sistem diyaloğu iptal etmesin.
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[BiometricLock] authenticate: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @visibleForTesting
  static void resetForTest([BiometricLockService? fake]) {
    instance = fake ?? BiometricLockService._();
  }
}
