import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'db_logger.dart';

/// Yakalanan ama YUTULAN hataların Crashlytics'e non-fatal olarak gitmesi.
///
/// 2026-09 denetimi: 221 `catch` bloğu vardı, `recordError` yalnızca 2
/// dosyada (global handler'lar). Servis katmanındaki bilinçli `catch`'ler —
/// özellikle `auth_service`'teki 26'sı — üretimde görünmezdi: kullanıcı
/// "giriş hatası" görüyor, biz hangi sınıftan olduğunu hiç öğrenmiyorduk.
///
/// Kurallar:
/// - `sanitize()` şart: JWT/e-posta/UUID/IP Crashlytics'e gitmez (KVKK).
/// - Firebase config yoksa (yerel build, CI) sessiz no-op — çağıran taraf
///   asla yeniden fırlatma görmez.
/// - Debug'da console'a da yazar; release'te yalnızca Crashlytics.
class CrashReporter {
  CrashReporter._();

  static void report(
    Object error,
    StackTrace? stack, {
    required String reason,
  }) {
    final sanitized = DbLogger.sanitize(error.toString());
    if (kDebugMode) debugPrint('[$reason] $sanitized');
    if (Firebase.apps.isEmpty) return;
    try {
      FirebaseCrashlytics.instance.recordError(
        sanitized,
        stack,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Crashlytics'in kendisi çökerse bile çağıran akış etkilenmemeli.
    }
  }
}
