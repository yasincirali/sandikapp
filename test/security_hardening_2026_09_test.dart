import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/auth_service.dart';

/// 2026-09 değerlendirmesinin kapanan orta/düşük bulguları — kaynak taraması.
/// Her biri "yapıldı" dendikten sonra sessizce geri gelebilecek türden.
void main() {
  String oku(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  test('L12: şifre üst sınırı 72 bayt (bcrypt)', () {
    expect(AuthService.validatePassword('a1' * 40), contains('72'));
    expect(AuthService.validatePassword('sifre123'), isNull);
  });

  test('M7: davet kodu IP başına da sınırlı', () {
    final src = oku('supabase/functions/redeem-invite-code/index.ts');
    expect(src.contains("p_scope: 'redeem_invite_ip'"), isTrue);
    expect("record_rate_limit_attempt".allMatches(src).length >= 2, isTrue,
        reason: 'IP sayacı yalnızca okunuyor, hiç artmıyor');
  });

  test('M8: redeem yanıtında partner_user_id yok', () {
    final src = oku('supabase/functions/redeem-invite-code/index.ts');
    expect(src.contains('partner_user_id: invite.from_user_id'), isFalse);
  });

  test('L13: hedefin vazgeçmesi sahibin kodunu yakmaz', () {
    final src = oku('supabase/functions/accept-invite/index.ts');
    expect(src.contains("to_user_id: null, requester_name: null"), isTrue);
    expect(src.contains(".eq('to_user_id', user.id)"), isTrue,
        reason: 'sıfırlama yalnızca kendi bağlandığı davette olmalı');
  });

  test('L4: cron fonksiyonlarında Allow-Origin * yok', () {
    for (final f in [
      'analyze-signals',
      'calendar-nudge',
      'check-price-alerts',
      'daily-brief',
      'fetch-inflation',
      'weekly-summary',
    ]) {
      expect(oku('supabase/functions/$f/index.ts').contains("'Access-Control-Allow-Origin': '*'"),
          isFalse, reason: f);
    }
  });

  test('L8: dışa aktarma dosyasına ham hata metni yazılmaz', () {
    final src = oku('lib/services/data_export_service.dart');
    expect(src.contains("'_export_error': e.toString()"), isFalse);
  });

  test('M2: Supabase oturumu SecureSessionStorage ile başlatılır', () {
    final src = oku('lib/main.dart');
    expect(src.contains('localStorage: SecureSessionStorage('), isTrue);
  });

  test('L2: arkaya alınma anı diske yazılır', () {
    final src = oku('lib/main.dart');
    expect(src.contains('_persistBackgroundedAt(_backgroundedAt)'), isTrue);
    expect(src.contains('_staleSessionAtLaunch'), isTrue);
  });

  test('L14: çıkışta yerel sayaçlar ve push cihaz kimliği silinir', () {
    final src = oku('lib/services/auth_service.dart');
    expect(src.contains('prefs.remove(PrefKeys.pushDeviceId)'), isTrue);
    expect(src.contains("k.startsWith(_rlKeyPrefix)"), isTrue);
  });
}
