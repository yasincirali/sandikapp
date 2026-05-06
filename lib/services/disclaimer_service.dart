import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

  /// Kullanıcı kayıt sonrası onayını Supabase'e kaydeder.
  /// Hata olursa sessizce yutmaz — caller log'a yazabilir.
  Future<void> recordAcceptance({
    required String userId,
    required String appVersion,
    required String platform,
    String? deviceModel,
    String? locale,
  }) async {
    await _client.from('disclaimer_acceptances').upsert(
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
    );
  }

  /// Kullanıcının bu versiyon için onayı var mı?
  Future<bool> hasAccepted(String userId) async {
    try {
      final rows = await _client
          .from('disclaimer_acceptances')
          .select('id')
          .eq('user_id', userId)
          .eq('disclaimer_version', disclaimerVersion)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      debugPrint('DisclaimerService.hasAccepted error: $e');
      return false;
    }
  }
}
