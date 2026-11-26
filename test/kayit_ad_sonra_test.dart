import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kayıt formu kullanıcı adı sormaz (yasin 2026-11-26); ad OTP sonrası
/// `KullaniciAdiScreen` kapısında alınır ve e-posta parçası kullanıcı adı olmaz.
void main() {
  test('kayıt ekranında ad alanı yok, kapı kalır', () {
    final s = File('lib/screens/register_screen.dart').readAsStringSync();
    expect(s.contains('_nameCtrl'), isFalse);
    expect(s.contains('KullaniciAdiDenetimi'), isFalse);
    final m = File('lib/main.dart').readAsStringSync();
    expect(m.contains('user.kullaniciAdiGerekli'), isTrue);
  });

  test('ad verilmediyse sunucuda kullanıcı adı atanmaz', () {
    final s = File('lib/services/auth_service.dart').readAsStringSync();
    expect(s.contains('if (!adVar) return user;'), isTrue);
  });
}
