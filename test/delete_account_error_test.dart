import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/auth_service.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

import 'helpers/kaynak.dart';

/// Hesap silmede yanlış şifre — 2026-09-23 denetimi U12.
///
/// `functions.invoke` 2xx dışı yanıtta `FunctionException` fırlatır;
/// `response.status != 200` dalı yanlış şifrede (401) hiç çalışmıyordu.
/// Kullanıcı "Bir şeyler ters gitti" görüyor, yanlış şifre Crashlytics'e
/// çökme diye gidiyordu.
void main() {
  group('deleteAccountHatasi — sunucu kodu → kullanıcı mesajı', () {
    test('401 invalid_password → "Şifre hatalı."', () {
      final e = AuthService.deleteAccountHatasi(
          401, {'error': 'invalid_password'});
      expect(e.message, 'Şifre hatalı.');
      // Uçtan uca: ekran `showAppError` → `friendlyError` ile gösterir.
      expect(friendlyError(e), 'Şifre hatalı.');
    });

    test('password_required ve invalid_identity', () {
      expect(
          AuthService.deleteAccountHatasi(400, {'error': 'password_required'})
              .message,
          'Şifre gerekli.');
      expect(
          AuthService.deleteAccountHatasi(401, {'error': 'invalid_identity'})
              .message,
          contains('Kimlik doğrulanamadı'));
    });

    test('bilinmeyen kod → durum kodlu genel mesaj, ham gövde yok', () {
      final e = AuthService.deleteAccountHatasi(500, 'stack trace <html>');
      expect(e.message, contains('kod 500'));
      expect(e.message, isNot(contains('html')));
    });
  });

  test('deleteAccount FunctionException yolunu ayrıca yakalar', () {
    final src = ekranKaynagiSync('lib/services/auth_service.dart');
    final start = src.indexOf('Future<void> deleteAccount(');
    final body = src.substring(start, src.indexOf('// 3. Local cache', start));
    expect(body, contains('on FunctionException catch (e)'));
    expect(body, contains('deleteAccountHatasi(e.status, e.details)'));
    // FunctionException bloğu genel catch'ten ÖNCE gelmeli; yoksa 401
    // yine "Hesap silme hatası" + Crashlytics yoluna düşer.
    expect(body.indexOf('on FunctionException'),
        lessThan(body.indexOf('catch (e, st)')));
  });
}
