import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/yukleme_isareti.dart';

/// Yükleme işareti vektöre geçti (2026-09-24, kullanıcı: "gif düzgün
/// kırpılmamış, dark modda sınırlar belli"). Burada kilitlenenler:
///
///   1. Yuvarlak kare kırpması gerçekten uygulanıyor — köşe pikseli boş,
///      merkez marka rengi. GIF'in "çerçeve" sorunu tam olarak kenar
///      pikselleriydi; kırpma düşerse köşe dolu çıkar.
///   2. "Hareketi azalt" açıkken sayaç durur (iOS HIG High severity).
///   3. Kapalıyken döner.
void main() {
  // `flutter_test_config.dart` sayacı tüm testlerde kapatır; sayacın
  // kendisi burada sınanıyor, o yüzden geçici olarak açılır.
  setUp(() => YuklemeIsareti.hareketli = true);
  tearDown(() => YuklemeIsareti.hareketli = false);

  testWidgets('köşe boş, merkez marka rengi, üst şerit parlak', (tester) async {
    await tester.runAsync(() async {
      const boyut = 100.0;
      final kayit = ui.PictureRecorder();
      final canvas = Canvas(kayit);
      YuklemeIsaretiPainter(faz: null)
          .paint(canvas, const Size(boyut, boyut));
      final resim = await kayit.endRecording().toImage(100, 100);
      final bytes = (await resim.toByteData())!;

      Color px(int x, int y) {
        final i = (y * 100 + x) * 4;
        return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      // Köşe: yarıçap 18 px (100 × 27/150); (1,1) kesinlikle dışarıda.
      expect(px(1, 1).a, 0.0,
          reason: 'yuvarlak kare kırpması köşeyi boşaltmalı');
      expect(px(98, 98).a, 0.0);
      // Kenar ortası: içeride (kırpma yalnızca köşeleri alır).
      expect(px(50, 1).a, 1.0);
      expect(px(50, 1), YuklemeIsaretiSabitleri.tepe,
          reason: 'tepede parlak şerit');
      // Merkez: dalgaların altında kalan bant (69/150 → y≈46 sınırı; y=50
      // üçüncü bandın üstünde) — sarı ya da turuncu değil, kehribar.
      expect(px(50, 50), YuklemeIsaretiSabitleri.kehribar);
      // Alt kenar ortası: en koyu bant.
      expect(px(50, 98), YuklemeIsaretiSabitleri.kahve);
    });
  });

  testWidgets('reduce-motion açıkken sayaç durur', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: YuklemeIsareti(size: 40)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'hareket tercihi yok sayılmamalı');
  });

  testWidgets('hareketli=false iken (test varsayılanı) sayaç kurulmaz',
      (tester) async {
    YuklemeIsareti.hareketli = false;
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: false),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: YuklemeIsareti(size: 40)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'pumpAndSettle kullanan 35 test dosyası buna dayanır');
  });

  testWidgets('reduce-motion kapalıyken döner', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: false),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: YuklemeIsareti(size: 40)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    // Kutu istenen ölçüde.
    expect(tester.getSize(find.byType(CustomPaint)), const Size(40, 40));
  });
}
