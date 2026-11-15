// Sistem açılış görsellerini uygulamanın açılış işaretinden üretir.
//
//   flutter test tool/acilis_gorseli_uret_test.dart
//
// Neden (yasin 2026-11-15, tek tip açılış): iOS `LaunchImage` ve Android
// `splash_icon` elle çizilmiş ayrı görsellerdi (uygulama simgesi, farklı
// boy). Artık [YuklemeIsaretiPainter]'ın faz 0 karesi, [YuklemeIsareti.
// acilisBoyu] boyunda; Flutter'ın ilk karesi bu görselin üstüne birebir
// oturur. İşaretin geometrisi ya da boyu değişirse bu betik yeniden koşar.
//
// iOS: `LaunchImage` görselin kendisi (acilisBoyu pt; @1x/@2x/@3x), storyboard
//      onu ekranın ortasına koyar.
// Android: `splash_icon` 240 dp'lik tuval (12+ sistem açılışı ikon alanı,
//      ikon zemin rengiyle) ortasında acilisBoyu dp işaret; 12 öncesinde
//      `launch_background` aynı görseli ortaya koyar. 112 dp yuvarlak kare,
//      sistemin 160 dp'lik dairesel maskesinin içinde kalır (köşe uzaklığı
//      ~71 dp < 80 dp).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/yukleme_isareti.dart';

Future<void> _yaz(String yol, double tuval, double isaret) async {
  final kayit = ui.PictureRecorder();
  final c = Canvas(kayit);
  final pay = (tuval - isaret) / 2;
  c.translate(pay, pay);
  YuklemeIsaretiPainter(faz: null).paint(c, Size(isaret, isaret));
  final img = await kayit
      .endRecording()
      .toImage(tuval.round(), tuval.round());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(yol).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('açılış görsellerini üret', (tester) async {
    await tester.runAsync(() async {
      const b = YuklemeIsareti.acilisBoyu;
      const ios = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      await _yaz('$ios/LaunchImage.png', b, b);
      await _yaz('$ios/LaunchImage@2x.png', b * 2, b * 2);
      await _yaz('$ios/LaunchImage@3x.png', b * 3, b * 3);
      const res = 'android/app/src/main/res';
      for (final (d, k) in [
        ('mdpi', 1.0),
        ('hdpi', 1.5),
        ('xhdpi', 2.0),
        ('xxhdpi', 3.0),
        ('xxxhdpi', 4.0),
      ]) {
        await _yaz('$res/drawable-$d/splash_icon.png', 240 * k, b * k);
      }
    });
  });
}
