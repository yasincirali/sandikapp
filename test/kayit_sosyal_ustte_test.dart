import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kayıt ve demo kayıt sayfası: Apple/Google formdan önce gelir (26 Kas 2026,
/// GA4: kayıt ekranını açan 318, e-posta kodu ekranına gelen 16). Şifre tekrarı
/// yok; geri dönülürse bu kilit bilinçli kaldırılmalı.
void main() {
  final kayit = File('lib/screens/register_screen.dart').readAsStringSync();
  final demo = File('lib/demo/demo_kabugu.dart').readAsStringSync();

  test('kayıt ekranında sosyal düğmeler kullanıcı adı alanından önce', () {
    final sosyal = kayit.indexOf('SocialSignInButtons(ustte: true)');
    final ad = kayit.indexOf('controller: _nameCtrl');
    expect(sosyal, greaterThan(0));
    expect(sosyal, lessThan(ad));
    expect('SocialSignInButtons('.allMatches(kayit).length, 1);
  });

  test('kayıt formunda şifre tekrarı alanı yok', () {
    expect(kayit.contains('_passConfirmCtrl'), isFalse);
  });

  test('demo kayıt sayfası gerçek container ile sosyal düğme taşır', () {
    expect(demo.contains('UncontrolledProviderScope'), isTrue);
    expect(demo.contains('SocialSignInButtons(ustte: true)'), isTrue);
    expect(demo.contains('_KayitSayfasi(kok: _kok)'), isTrue);
  });
}
