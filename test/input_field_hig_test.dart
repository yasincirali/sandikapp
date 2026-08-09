import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Input alanlarının Apple HIG beklentilerine uyduğunu koruyan testler.
///
/// Bunlar kaynak koda karşı statik denetimlerdir. Widget testiyle
/// doğrulanamazlar çünkü `autofillHints` gibi özellikler platform
/// davranışını etkiler; test ortamında iOS Keychain / SMS akışı yoktur.
/// Amaç: bir alan eklenirken bu özelliklerin unutulmasını yakalamak.
void main() {
  String oku(String yol) => File(yol).readAsStringSync();

  group('Kimlik ekranları — otomatik doldurma', () {
    test('login: e-posta ve şifre autofill ipuçlarına sahip', () {
      final s = oku('lib/screens/login_screen.dart');
      expect(s.contains('AutofillHints.username'), isTrue,
          reason: 'iCloud Keychain kullanıcı adını dolduramaz');
      expect(s.contains('AutofillHints.password'), isTrue,
          reason: 'Kayıtlı şifre önerilmez');
    });

    test('login ve register AutofillGroup ile sarılı', () {
      // Grup olmadan iOS "şifreyi kaydet?" istemini GÖSTERMEZ —
      // ipuçları tek başına yetmez.
      for (final dosya in [
        'lib/screens/login_screen.dart',
        'lib/screens/register_screen.dart',
      ]) {
        expect(oku(dosya).contains('AutofillGroup'), isTrue,
            reason: '$dosya: kaydetme istemi tetiklenmez');
      }
    });

    test('register: yeni şifre newPassword ipucu kullanır', () {
      final s = oku('lib/screens/register_screen.dart');
      // `password` DEĞİL `newPassword`: güçlü şifre önerisini bu tetikler.
      expect(s.contains('AutofillHints.newPassword'), isTrue);
      expect(s.contains('AutofillHints.name'), isTrue);
      expect(s.contains('AutofillHints.email'), isTrue);
    });

    test('şifre sıfırlama: e-posta, kod ve yeni şifre ipuçlu', () {
      final s = oku('lib/screens/forgot_password_screen.dart');
      expect(s.contains('AutofillHints.email'), isTrue);
      expect(s.contains('AutofillHints.oneTimeCode'), isTrue);
      expect(s.contains('AutofillHints.newPassword'), isTrue);
    });

    test('OTP ekranı: tek seferlik kod ipucu var', () {
      final s = oku('lib/screens/otp_verification_screen.dart');
      expect(s.contains('AutofillHints.oneTimeCode'), isTrue,
          reason: 'SMS/e-posta kodu klavye üstünde önerilmez');
    });
  });

  group('Klavye davranışı', () {
    test('e-posta alanlarında otomatik düzeltme kapalı', () {
      // "ali@" gibi girdileri sistem bozabiliyor; ayrıca ilk harf
      // büyütme e-postayı geçersiz kılabiliyor.
      for (final dosya in [
        'lib/screens/login_screen.dart',
        'lib/screens/register_screen.dart',
        'lib/screens/forgot_password_screen.dart',
      ]) {
        final s = oku(dosya);
        expect(s.contains('autocorrect: false'), isTrue,
            reason: '$dosya: e-postada otomatik düzeltme açık');
      }
    });

    test('register 4 alanlı formda textInputAction zinciri var', () {
      final s = oku('lib/screens/register_screen.dart');
      // Klavyede "İleri" olmadan kullanıcı her alandan sonra klavyeyi
      // kapatıp elle dokunmak zorunda kalıyordu.
      expect('TextInputAction.next'.allMatches(s).length, greaterThanOrEqualTo(3),
          reason: 'Alanlar arası geçiş zinciri eksik');
      expect(s.contains('TextInputAction.done'), isTrue,
          reason: 'Son alan formu göndermiyor');
    });

    test('parasal alanlar ondalık klavye kullanır', () {
      for (final dosya in [
        'lib/screens/add_asset_screen.dart',
        'lib/screens/add_deposit_screen.dart',
        'lib/widgets/dividend_dialog.dart',
      ]) {
        expect(
          oku(dosya).contains('numberWithOptions(decimal: true)'),
          isTrue,
          reason: '$dosya: tam sayı klavyesi ondalık tutar girişini engeller',
        );
      }
    });

    test('sembol/kod alanlarında otomatik düzeltme kapalı', () {
      // Ticker ve ortaklık kodu sözlükte olmayan dizilerdir.
      expect(oku('lib/screens/add_asset_screen.dart').contains('autocorrect: false'),
          isTrue);
      expect(oku('lib/screens/profile_screen.dart').contains('autocorrect: false'),
          isTrue);
    });
  });

  group('OTP giriş kolaylığı', () {
    test('yapıştırılan çok haneli kod hücrelere dağıtılır', () {
      final s = oku('lib/screens/otp_verification_screen.dart');
      // `maxLength: 1` framework girişi kırpıyordu; yapıştırılan 6 haneli
      // kod onChanged'e hiç ulaşmıyordu.
      expect(s.contains('if (v.length > 1)'), isTrue,
          reason: 'Yapıştırma desteği yok — 5 haneyi elle yazmak gerekir');
      // Yorum satırlarını ayıkla: açıklamalarda `maxLength: 1` geçiyor
      // (neden kaldırıldığını anlatmak için) ama GERÇEK kodda olmamalı.
      final kod = s
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(kod.contains('maxLength: 1'), isFalse,
          reason: 'maxLength yapıştırmayı keser');
    });
  });
}
