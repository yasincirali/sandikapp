import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS paketi desteklediği dilleri App Store'a bildirmeli.
///
/// ## Neden
/// App Store ürün sayfasındaki "Diller" satırı mağaza metninden değil
/// PAKETTEN okunur. Flutter uygulaması dilleri Dart tarafında (gen-l10n)
/// taşıdığı için iOS bunu kendiliğinden bilmez; `CFBundleLocalizations`
/// yoksa yalnız geliştirme bölgesi (`en`) sayılır. 2026-10-11'de canlı
/// sayfa Türkçe bir uygulama için "Diller: İngilizce" gösteriyordu
/// (iTunes Lookup `languageCodesISO2A: ["EN"]`) — Türk kullanıcı için
/// dönüşüm kaybı ve hiçbir test bunu yakalamıyordu.
///
/// Liste `lib/l10n/app_*.arb` ile aynı dilleri taşımalı: yeni dil
/// eklenince burası da güncellenir.
String _oku(String yol) =>
    File(yol).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('Info.plist CFBundleLocalizations tr ve en bildirir', () {
    final plist = _oku('ios/Runner/Info.plist');
    final blok = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(blok, isNotNull,
        reason: 'CFBundleLocalizations yok — App Store "Diller: İngilizce" der');
    final diller = RegExp(r'<string>([^<]+)</string>')
        .allMatches(blok!.group(1)!)
        .map((m) => m.group(1))
        .toSet();
    expect(diller, containsAll(<String>['tr', 'en']));
  });

  test('Bildirilen diller .arb dosyalarıyla aynı', () {
    final arb = Directory('lib/l10n')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((ad) => ad.startsWith('app_') && ad.endsWith('.arb'))
        .map((ad) => ad.substring(4, ad.length - 4))
        .toSet();
    final plist = _oku('ios/Runner/Info.plist');
    for (final dil in arb) {
      expect(plist, contains('<string>$dil</string>'),
          reason: '$dil .arb olarak var ama Info.plist bildirmiyor');
    }
  });

  test('Xcode knownRegions tr içerir', () {
    final proje = _oku('ios/Runner.xcodeproj/project.pbxproj');
    final blok = RegExp(r'knownRegions = \((.*?)\);', dotAll: true)
        .firstMatch(proje);
    expect(blok?.group(1), contains('tr,'));
  });
}
