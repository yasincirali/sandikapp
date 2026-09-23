import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';

/// Yasal uyarı metni ve versiyonu — değiştirilirse versiyon artırılmalı.
const disclaimerVersion = '1.0';
const disclaimerText =
    'Bu uygulama yalnızca kişisel portföy takibi ve bilgilendirme '
    'amacıyla sunulmaktadır. '
    'Gösterilen fiyat verileri, teknik analizler ve sinyaller '
    'kesinlikle yatırım tavsiyesi, alım-satım önerisi veya '
    'finansal danışmanlık niteliği taşımaz. '
    'Yatırım kararlarınızı yetkili ve lisanslı bir finansal '
    'danışmana danışarak veriniz. '
    'Geçmiş performans ve teknik göstergeler gelecekteki '
    'sonuçları garanti etmez. '
    'Uygulamayı kullanarak bu koşulları okuduğunuzu ve '
    'kabul ettiğinizi onaylıyorsunuz.';

String get disclaimerHash =>
    sha256.convert(utf8.encode(disclaimerText)).toString();

class DisclaimerService {
  static final DisclaimerService instance = DisclaimerService._();
  DisclaimerService._();

  final _client = Supabase.instance.client;

  // userId → accepted — logout'ta temizlenmeli
  final Map<String, bool> _cache = {};

  void clearCache() => _cache.clear();

  static const _timeout = Duration(seconds: 15);

  /// Onay kaydının `platform` sütunu — saf, test edilebilir.
  ///
  /// 2026-09-23 denetimi U18: ekranlar `Platform.isIOS ? 'ios' : 'android'`
  /// yazıyordu; web/masaüstü de "android" diye kaydediliyordu ve
  /// `dart:io` web'de derlenmez bile. Hukuki kayıt yanlış bilgi taşımamalı.
  static String platformEtiketi(TargetPlatform p, {bool web = kIsWeb}) {
    if (web) return 'web';
    switch (p) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'other';
    }
  }

  /// Onayı CİHAZIN gerçek bilgileriyle kaydeder; hata fırlatmaz.
  ///
  /// 2026-09-23 denetimi U18: iki ekran (`DisclaimerAcceptanceScreen`,
  /// `OtpVerificationScreen`) `app_version: '1.0.0+1'` ve `locale: 'tr_TR'`
  /// sabitleri yazıyordu — gerçek sürüm 1.1.x iken ve İngilizce arayüzde
  /// bile. KVKK/hukuki iz "hangi sürümde, hangi dilde gördü" sorusuna
  /// yanlış cevap veriyordu. Sürüm `PackageInfo`'dan (Ayarlar ve
  /// `SurumNotuService` ile aynı kaynak; `version+buildNumber`, çünkü
  /// TestFlight yalnızca build'i artırır), dil ekranın ETKİN
  /// `Localizations` yerelinden gelir.
  ///
  /// Hata eskiden iki ekranda da `catch (_) {}` ile yutuluyordu. Akış
  /// yine durmaz (kayıt düşerse `_AuthGate` onay ekranını tekrar gösterir —
  /// yedek yol budur) ama arıza artık görünür: bağlantı hatası dışındakiler
  /// Crashlytics'e non-fatal gider. Dönüş: kayıt yazıldı mı.
  Future<bool> kabulKaydet({
    required String userId,
    required String locale,
  }) async {
    try {
      await recordAcceptance(
        userId: userId,
        appVersion: await _surumEtiketi(),
        platform: platformEtiketi(defaultTargetPlatform),
        locale: locale,
      );
      return true;
    } catch (e, st) {
      if (!CrashReporter.agHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'DisclaimerService.kabulKaydet');
      }
      return false;
    }
  }

  /// `1.1.6+7` — okunamazsa 'unknown' (sütun NOT NULL; uydurma sürüm
  /// yazmaktansa bilinmediğini söylemek doğru).
  static Future<String> _surumEtiketi() async {
    try {
      final bilgi = await PackageInfo.fromPlatform();
      return '${bilgi.version}+${bilgi.buildNumber}';
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'DisclaimerService._surumEtiketi');
      return 'unknown';
    }
  }

  /// Kullanıcı kayıt sonrası onayını Supabase'e kaydeder.
  /// Hata olursa sessizce yutmaz — caller log'a yazabilir.
  Future<void> recordAcceptance({
    required String userId,
    required String appVersion,
    required String platform,
    String? deviceModel,
    String? locale,
  }) async {
    await _client
        .from('disclaimer_acceptances')
        .upsert(
          {
            'user_id': userId,
            'disclaimer_version': disclaimerVersion,
            'disclaimer_hash': disclaimerHash,
            'app_version': appVersion,
            'platform': platform,
            'device_model': deviceModel,
            'locale': locale,
          },
          onConflict: 'user_id,disclaimer_version',
          ignoreDuplicates: true,
        )
        .timeout(_timeout);
    _cache[userId] = true;
    // Kalıcı iz — sonraki açılışta ağ yoksa `hasAccepted` buna düşer.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceKey(userId), true);
  }

  /// Onayın cihazdaki kalıcı izi. Bellek cache'i uygulama kapanınca gider;
  /// bu anahtar kalır, böylece ağ yokken de "zaten onayladı" bilinebilir.
  static String _deviceKey(String userId) =>
      'disclaimer_accepted_${disclaimerVersion}_$userId';

  /// Kullanıcının bu versiyon için onayı var mı?
  ///
  /// Ağ hatasında **cihazdaki kalıcı ize** düşer. Bu, hukuki kapıyı
  /// zayıflatmaz: yalnızca daha önce onayladığı doğrulanmış kullanıcı
  /// offline geçebilir. Hiç onaylamamış kullanıcı ağsızken yine
  /// disclaimer ekranını görür.
  ///
  /// Eskiden ağ hatasında koşulsuz `false` dönüyordu; oturumu olan
  /// kullanıcı uçak modunda disclaimer ekranında kilitleniyordu — çünkü
  /// oradan onay da yazılamıyor.
  Future<bool> hasAccepted(String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId]!;
    try {
      final rows = await _client
          .from('disclaimer_acceptances')
          .select('id')
          .eq('user_id', userId)
          .eq('disclaimer_version', disclaimerVersion)
          .limit(1)
          .timeout(_timeout);
      final accepted = (rows as List).isNotEmpty;
      _cache[userId] = accepted;
      if (accepted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_deviceKey(userId), true);
      }
      return accepted;
    } catch (e) {
      debugPrint('DisclaimerService.hasAccepted error: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_deviceKey(userId)) ?? false;
    }
  }
}
