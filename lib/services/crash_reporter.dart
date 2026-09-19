import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
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
/// - Varsayılan `fatal: false`. `fatal` YALNIZCA `main.dart`'taki global
///   handler'lar tarafından verilir; oradaki karar da [agHatasiMi]'ye
///   dayanır (bağlantı hatası çökme değildir).
class CrashReporter {
  CrashReporter._();

  static void report(
    Object error,
    StackTrace? stack, {
    required String reason,
    bool fatal = false,
  }) {
    final sanitized = DbLogger.sanitize(error.toString());
    if (kDebugMode) debugPrint('[$reason] $sanitized');
    try {
      // Firebase kontrolü de try İÇİNDE: `report` bir hata YOLUNDA çağrılıyor
      // (çoğu zaman `catchError` handler'ında). Buradan fırlayan her şey yeni
      // bir yakalanmamış hata olur ve tam da önlemeye çalıştığımız sahte
      // çökme raporunu üretir.
      if (Firebase.apps.isEmpty) return;
      FirebaseCrashlytics.instance.recordError(
        sanitized,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (_) {
      // Crashlytics'in kendisi çökerse bile çağıran akış etkilenmemeli.
    }
  }

  /// Hata kullanıcının BAĞLANTISINDAN mı kaynaklanıyor?
  ///
  /// Üretim çökmesi (Crashlytics, 2026-09-19): "Fatal Exception: FlutterError
  /// → `DbLogger.log` → `SupabaseService.updateAsset`". Gerçekte olan şey bir
  /// çökme değildi — `DbLogger.defaultTimeout` (15 sn) dolmuş, doğan
  /// `TimeoutException` await edilmeyen bir future'dan zone handler'ına
  /// düşmüş, orada `fatal: true` ile kaydedilmişti. Uygulama çalışmaya devam
  /// ediyordu; buna rağmen "çökmesiz kullanıcı" oranını düşürüyor ve GERÇEK
  /// çökmeleri gürültüde gizliyordu.
  ///
  /// Bu yüzden global handler'lar (`main.dart`) fatal kararını buradan
  /// sorar: ağ/soket/timeout hataları non-fatal, geri kalan her şey fatal.
  /// Kapsam bilerek DAR — tanımadığımız hata fatal sayılır; yanlış tarafa
  /// düşmek gerekiyorsa gürültü değil, görünürlük tarafına düşsün.
  static bool agHatasiMi(Object? error) {
    // `ClientException` (package:http) TİP olarak da tanınır. Bugünkü
    // `toString()` "ClientException: <mesaj>" biçiminde, yani aşağıdaki
    // metin taraması da yakalıyor — ama o tarama SINIF ADI ÖNEKİNE bağlı;
    // önek değişirse (paket sürümü) ya da `toString()`'i ezen bir alt sınıf
    // gelirse sessizce kaçardı. Üretim raporu 2026-09-19 bu tipti
    // (`IOClient.send → DbLogger.log → SupabaseService.updateAsset`).
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is ClientException) {
      return true;
    }
    final metin = error.toString();
    for (final iz in const [
      'TimeoutException',
      'SocketException',
      'HandshakeException',
      'Failed host lookup',
      'ClientException',
      'Connection closed',
      'Connection reset',
      'Connection refused',
      'Software caused connection abort',
      'Network is unreachable',
      // `ClientException` mesajları — hata tipini kaybetmiş, metne çevrilmiş
      // hâlde geldiğinde (ör. başka bir katman `toString()` yapıp taşımışsa).
      'Connection closed before full header was received',
      'Connection attempt cancelled',
      'Request has been aborted',
    ]) {
      if (metin.contains(iz)) return true;
    }
    return false;
  }

  /// Arka plana bırakılan (await edilmeyen) işin hatasını yakalar.
  ///
  /// `unawaited()` yalnızca `unawaited_futures` lint'ini susturur — hatayı
  /// YUTMAZ. Await edilmeyen bir future hata ile biterse hata `main.dart`'taki
  /// `runZonedGuarded` handler'ına düşer ve ÇÖKME olarak raporlanır. Oysa
  /// arka plan işi (fiyat yazımı, snapshot upload, ortak listesi tazeleme)
  /// kullanıcının akışını zaten kesmiyor: başarısızlığı non-fatal bir kayıt
  /// olmalı, çökme değil.
  ///
  /// Yeni bir "ateşle ve unut" çağrısı yazarken `unawaited(...)` yerine bunu
  /// kullan — `arka_plan_hata_yutma_test` ağ dokunan çağrıları tarar.
  static void arkaPlan(Future<void> future, {required String reason}) {
    unawaited(future.catchError(
      (Object e, StackTrace st) => report(e, st, reason: reason),
    ));
  }
}
