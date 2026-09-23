import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/auth_service.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// `friendlyError` — kullanıcıya yazılmış mesaj vs ham teknik metin.
///
/// 2026-09-23 denetimi U13: boş kayıt formunda "Ad soyad girin." yerine
/// "Bir şeyler ters gitti" çıkıyordu. `_humanize` yalnızca Türkçe HARF
/// içeren metni geçiriyordu; düz ASCII Türkçe ve İngilizce arayüzün l10n
/// metinleri eleniyordu. Karar artık türle verilir ([KullaniciMesajli]).
void main() {
  group('uygulamanın AuthException\'ı olduğu gibi gösterilir', () {
    for (final m in const [
      'Ad soyad girin.', // ASCII Türkçe — eskiden kayboluyordu
      'Kod girin.',
      'Enter your full name.', // İngilizce arayüz (l10n)
      'Şifre hatalı.',
    ]) {
      test(m, () => expect(friendlyError(AuthException(m)), m));
    }

    test('RateLimitedException de mesajını korur', () {
      expect(friendlyError(const RateLimitedException('Çok fazla deneme.', 30)),
          'Çok fazla deneme.');
    });

    test('boş mesaj genel metne düşer', () {
      expect(friendlyError(const AuthException('  ')), isNot(isEmpty));
    });
  });

  group('ham teknik / İngilizce hata SIZMAZ', () {
    test('GoTrue AuthException (İngilizce) çevrilir', () {
      final m = friendlyError(const sb.AuthException('No user found.'));
      expect(m, isNot(contains('No user')));
    });

    test('düz Exception İngilizce metni geçmez', () {
      final m = friendlyError(Exception('Null check operator used'));
      expect(m, 'Bir şeyler ters gitti, tekrar dene.');
    });

    test('bağlantı hatası tek mesaja düşer', () {
      expect(friendlyError(Exception('SocketException: Failed host lookup')),
          kBaglantiHatasiMesaji);
    });
  });
}
