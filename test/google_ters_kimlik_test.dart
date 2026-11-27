import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google ile giriş iOS dönüşü: Info.plist'te iOS istemcisinin ters kimliği
/// şeması olmadan Google sayfası uygulamaya dönmez (rehber
/// docs/GOOGLE_GIRIS_KURULUM.md, "Hata → neden"). `sandik` şeması durur.
void main() {
  test('Info.plist hem sandik hem Google ters kimlik şemasını taşır', () {
    final s = File('ios/Runner/Info.plist').readAsStringSync();
    expect(s.contains('<string>sandik</string>'), isTrue);
    expect(
        RegExp(r'<string>com\.googleusercontent\.apps\.\d+-[a-z0-9]+</string>')
            .hasMatch(s),
        isTrue);
  });
}
