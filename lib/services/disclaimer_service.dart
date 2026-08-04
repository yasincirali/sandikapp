import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
