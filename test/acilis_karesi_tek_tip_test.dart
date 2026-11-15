// Tek tip açılış (yasin 2026-11-15): "ilk açılış splash ekranı Face ID'li
// ve Face ID'siz kullanıcıda tutarlı, sade ve tek tip olmalı".
//
// Sistem açılış görselleri (iOS LaunchImage + storyboard, Android
// splash_icon) uygulamanın açılış işaretiyle AYNI boyda olmalı; biri
// değişip öteki kalırsa ilk Flutter karesinde görsel zıplar. Görseller
// `flutter test tool/acilis_gorseli_uret_test.dart` ile yeniden üretilir.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/yukleme_isareti.dart';

/// PNG IHDR'den (genişlik, yükseklik).
(int, int) _pngBoyu(String yol) {
  final b = ByteData.sublistView(File(yol).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  const boy = YuklemeIsareti.acilisBoyu;

  test('iOS LaunchImage ve storyboard açılış boyunda', () {
    const set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    expect(_pngBoyu('$set/LaunchImage.png'), (boy.round(), boy.round()));
    expect(_pngBoyu('$set/LaunchImage@3x.png'),
        ((boy * 3).round(), (boy * 3).round()));
    final sb =
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    expect(sb, contains('constant="${boy.round()}" id="Lw1-sB-k9P"'));
    expect(sb, contains('constant="${boy.round()}" id="Lh2-sB-k9Q"'));
  });

  test('Android splash_icon 240 dp tuval, ortada açılış boyunda işaret', () {
    // xxxhdpi = 4×. Tuval 960 px; işaret 448 px, kenarlardan eşit pay.
    const yol = 'android/app/src/main/res/drawable-xxxhdpi/splash_icon.png';
    expect(_pngBoyu(yol), (960, 960));
    for (final f in [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      expect(File(f).readAsStringSync(), contains('@drawable/splash_icon'),
          reason: '$f: 12 öncesinde ve pencere zemininde aynı işaret');
    }
  });
}
