import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/dot_thinning.dart';

void main() {
  group('DotThinner — yoğun alım noktalarını seyreltme', () {
    test('birbirine yapışık noktalar elenir', () {
      // 0..1 aralığında 100px genişlikte 0.01 aralıklı adaylar = 1px arayla.
      // 10px minimum mesafe → kabaca her 10. nokta kalmalı.
      final candidates = List.generate(100, (i) => i * 0.01);
      final t = DotThinner.build(
        candidates: candidates,
        viewMinX: 0,
        viewMaxX: 1,
        plotWidthPx: 100,
        minSeparationPx: 10,
      );
      expect(t.visibleCount, lessThan(15));
      expect(t.visibleCount, greaterThan(5));
    });

    test('yeterince uzak noktaların hepsi korunur', () {
      final t = DotThinner.build(
        candidates: const [0.0, 0.25, 0.5, 0.75, 1.0],
        viewMinX: 0,
        viewMaxX: 1,
        plotWidthPx: 400,
        minSeparationPx: 16,
      );
      expect(t.visibleCount, 5);
      for (final x in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(t.shows(x), isTrue);
      }
    });

    test('zoom yapılınca daha fazla nokta görünür', () {
      final candidates = List.generate(100, (i) => i * 0.01);
      int visibleIn(double min, double max) => DotThinner.build(
            candidates: candidates,
            viewMinX: min,
            viewMaxX: max,
            plotWidthPx: 300,
            minSeparationPx: 16,
          ).visibleCount;

      // Tam görünüm: 0..1 arası 100 aday çok sıkışık.
      final full = visibleIn(0, 1);
      // Aynı piksel genişliğinde 0..0.1 aralığına zoom → 10 aday, hepsi rahat.
      final zoomed = visibleIn(0, 0.1);
      expect(zoomed, greaterThan(0));
      // Zoom'da o aralıktaki adayların çok daha büyük oranı görünür.
      expect(zoomed / 10, greaterThan(full / 100));
    });

    test('alwaysKeep noktaları mesafeye bakılmaksızın korunur', () {
      final t = DotThinner.build(
        candidates: const [0.50, 0.501, 0.502],
        viewMinX: 0,
        viewMaxX: 1,
        plotWidthPx: 100,
        minSeparationPx: 20,
        alwaysKeep: {0.0, 1.0},
      );
      expect(t.shows(0.0), isTrue);
      expect(t.shows(1.0), isTrue);
    });

    test('alwaysKeep noktasına yapışan aday elenir', () {
      // 1.0 korunuyor; 0.99 ona 1px mesafede → gizlenmeli.
      final t = DotThinner.build(
        candidates: const [0.99],
        viewMinX: 0,
        viewMaxX: 1,
        plotWidthPx: 100,
        minSeparationPx: 20,
        alwaysKeep: {1.0},
      );
      expect(t.shows(1.0), isTrue);
      expect(t.shows(0.99), isFalse);
    });

    test('viewport dışındaki adaylar görünmez', () {
      final t = DotThinner.build(
        candidates: const [-5.0, 0.5, 9.0],
        viewMinX: 0,
        viewMaxX: 1,
        plotWidthPx: 300,
        minSeparationPx: 16,
      );
      expect(t.shows(0.5), isTrue);
      expect(t.shows(-5.0), isFalse);
      expect(t.shows(9.0), isFalse);
    });

    test('sıfır genişlikli viewport çökmez', () {
      final t = DotThinner.build(
        candidates: const [1.0, 2.0],
        viewMinX: 5,
        viewMaxX: 5,
        plotWidthPx: 300,
      );
      expect(t.shows(1.0), isTrue);
    });
  });
}
