import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, FunctionException, PostgrestException;
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

  /// Global handler'ların (`main.dart`) tek fatal kararı.
  ///
  /// Bağlantı hatası ([agHatasiMi]) da geçici sunucu hatası
  /// ([geciciSunucuHatasiMi]) da çökme değildir; ikisi dışındaki her şey
  /// fatal kalır. İki ayrı soru olarak tutuldu çünkü [agHatasiMi]'yi servisler
  /// de soruyor (`yasal_onay_service`, `disclaimer_service`…) ve oradaki
  /// davranışı bu düzeltme değiştirmemeli.
  static bool fatalMi(Object? error) =>
      !agHatasiMi(error) && !geciciSunucuHatasiMi(error);

  /// Sunucu tarafı GEÇİCİ olarak yanıt veremedi mi (502/503/504, Cloudflare
  /// 520–524, PostgREST bağlantı havuzu hataları)?
  ///
  /// Üretim raporu (Crashlytics, 2026-10-06, Android): "Fatal Exception:
  /// FlutterError: PostgrestException(message: , code: 504, details: Gateway
  /// Timeout) — Error thrown runZonedGuarded". Supabase ağ geçidi isteği
  /// zaman aşımına uğratmış, kimsenin beklemediği bir sorgu zone handler'ına
  /// düşmüş ve [agHatasiMi] onu tanımadığı için `fatal: true` yazılmıştı.
  /// Uygulama çökmüyordu (zone'a düşen async hata süreci öldürmez); rapor
  /// yine de "çökmesiz kullanıcı" oranını düşürüyor ve gerçek çökmeleri
  /// gizliyordu — 2026-09-19 timeout raporunun sunucu tarafındaki ikizi.
  ///
  /// Kapsam yine DAR: 4xx (RLS, şema, kısıt ihlali) ve 500 (SQL hatası) bizim
  /// hatamızdır, fatal kalır. Yalnızca "sunucu şu an yok/yetişemedi" imzaları.
  static bool geciciSunucuHatasiMi(Object? error) {
    if (error is PostgrestException) {
      return _geciciKod(error.code);
    }
    if (error is FunctionException) {
      return _geciciKod('${error.status}');
    }
    if (error is AuthRetryableFetchException) {
      // Adı üstünde: auth istemcisinin kendisi "yeniden dene" diyor.
      return true;
    }
    // Tip kaybolmuş, metne çevrilmiş hâl (ör. başka katman `toString()`
    // yapıp taşımışsa). Kalıp `PostgrestException.toString()` biçimine bağlı.
    final m = RegExp(r'PostgrestException\(.*code: (\w+)')
        .firstMatch(error.toString());
    return m != null && _geciciKod(m.group(1));
  }

  static bool _geciciKod(String? kod) => const {
        '502', '503', '504',
        // Supabase önündeki Cloudflare: kaynak yanıt vermedi / zaman aşımı.
        '520', '521', '522', '523', '524',
        // PostgREST: veritabanına bağlanamadı (000–002), havuzdan bağlantı
        // alınamadan süre doldu (003, HTTP 504 olarak döner).
        'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003',
      }.contains(kod);

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
  ///
  /// Parametre `Future<Object?>`: `Future<bool>` (fetchAndActivate),
  /// `Future<List>` (seri ön-ısıtma) gibi sonuçlu işler de arka plana
  /// bırakılabiliyor; sonuç zaten kullanılmıyor (2026-09-20 süpürmesi,
  /// 73 → az sayıda `unawaited`, geri kalanı analitik ve UI).
  static void arkaPlan(Future<Object?> future, {required String reason}) {
    unawaited(future.then<void>((_) {}).catchError(
      (Object e, StackTrace st) => report(e, st, reason: reason),
    ));
  }
}
