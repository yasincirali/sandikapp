import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crash_reporter.dart';

/// Bildirim izni REDDEDİLMİŞ mi, ve telefon ayarına götürme (2026-10-21).
///
/// ## Neden
/// Ar-Ge 16:45 #1, yasin "kalanlara devam et": iOS izin diyaloğunu bir kez
/// gösterir. İlk açılışta refleksle "İzin verme" diyen kişi sonra alarm
/// kurar, alarm hiç çalmaz ve "uygulama çalışmıyor" diye gider; reddedilmiş
/// izin `RemotePushService.start`'ta sessizce dönüyordu (token yazılmaz).
/// Alarm/sinyal yüzeyleri bunu yerinde söyler (`BildirimIzniUyarisi`).
///
/// Yalnız `denied` uyarılır: `notDetermined` henüz sorulmamış demektir ve
/// ilk varlıktan sonraki bağlamlı soru (`push_prompt_after_first_asset`)
/// onu sorar; burada ikinci bir diyalog açılmaz.
class BildirimIzni {
  BildirimIzni._();

  static const _kanal = MethodChannel('com.sandik.app/ayarlar');

  /// Testte izin durumunu sabitlemek için. Üretimde null.
  @visibleForTesting
  static Future<bool> Function()? testOkuyucu;

  static Future<bool> reddedildi() async {
    final t = testOkuyucu;
    if (t != null) return t();
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return false;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.denied;
    } catch (_) {
      // Firebase yoksa (test, başlatma hatası) bilinmiyor: uyarı çıkmaz.
      // Yanlış "kapalı" demek, susmaktan kötü.
      return false;
    }
  }

  /// iOS: uygulamanın Ayarlar sayfası (Bildirimler satırı orada). Android:
  /// doğrudan uygulamanın bildirim ayarı (`MainActivity` kanalı).
  static Future<void> ayarlariAc() async {
    try {
      if (Platform.isIOS) {
        await launchUrl(Uri.parse('app-settings:'));
      } else if (Platform.isAndroid) {
        await _kanal.invokeMethod<void>('bildirimAyarlari');
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BildirimIzni.ayarlariAc');
    }
  }
}
