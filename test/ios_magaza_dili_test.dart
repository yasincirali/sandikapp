import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App Store sayfasındaki "Diller" satırı ikilideki `CFBundleLocalizations`
/// listesinden gelir. Liste yokken sayfa "İngilizce" yazıyordu (iTunes
/// lookup `languageCodesISO2A = [EN]`, ölçüm 2026-10-17); Türkçe arayan
/// kullanıcı için güven ve dönüşüm kaybı. Anahtar silinirse sessizce geri
/// döner, bu yüzden kilitli.
void main() {
  test('Info.plist uygulama dillerini Türkçe başta bildirir', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final m = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(m, isNotNull, reason: 'CFBundleLocalizations yok');
    final diller = RegExp(r'<string>(\w+)</string>')
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1))
        .toList();
    expect(diller.first, 'tr');
    expect(diller, contains('en'));
  });
}
