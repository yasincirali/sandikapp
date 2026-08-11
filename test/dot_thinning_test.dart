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

  // ── anchorSeparationPx ───────────────────────────────────────────────────
  //
  // Regresyon: anchor ("şimdi" / ilk nokta) çevresindeki yasak bölge normal
  // eşikle aynıydı. Grafiğin sonuna yakın yapılan alımlar bu bölgeye düştüğü
  // için KALICI olarak gizleniyordu — zoom yardımcı olmuyordu, çünkü
  // viewport'un sağ kenarı ve anchor her ölçekte orada duruyor.
  group('anchor yasak bölgesi ayrı ayarlanabilir', () {
    test('varsayılanda minSeparationPx ile aynı davranır (geriye uyum)', () {
      // 100 birim / 1000px → 1 birim = 10px. 20px eşik = 2 birim.
      final t = DotThinner.build(
        candidates: const [98.5],
        viewMinX: 0,
        viewMaxX: 100,
        plotWidthPx: 1000,
        minSeparationPx: 20,
        alwaysKeep: {100.0},
      );
      // 98.5 anchor'a 1.5 birim (15px) → 20px eşiğin altında, gizlenir.
      expect(t.shows(98.5), isFalse);
      expect(t.shows(100.0), isTrue, reason: 'anchor her zaman görünür');
    });

    test('daha küçük anchorSeparationPx uç noktaya yakın işlemi görünür kılar',
        () {
      final t = DotThinner.build(
        candidates: const [98.5],
        viewMinX: 0,
        viewMaxX: 100,
        plotWidthPx: 1000,
        minSeparationPx: 20,
        anchorSeparationPx: 8, // 0.8 birim
        alwaysKeep: {100.0},
      );
      // 1.5 birim (15px) > 8px → artık görünür.
      expect(t.shows(98.5), isTrue);
      expect(t.shows(100.0), isTrue);
    });

    test('anchor üstüne binen nokta yine gizlenir', () {
      final t = DotThinner.build(
        candidates: const [99.95],
        viewMinX: 0,
        viewMaxX: 100,
        plotWidthPx: 1000,
        minSeparationPx: 11,
        anchorSeparationPx: 8,
        alwaysKeep: {100.0},
      );
      // 0.05 birim = 0.5px → 8px eşiğin çok altında, üst üste binerdi.
      expect(t.shows(99.95), isFalse);
    });

    test('anchor eşiği normal aralık eşiğini etkilemez', () {
      // Birbirine yakın iki aday, anchor'dan uzakta: minSeparationPx geçerli.
      final t = DotThinner.build(
        candidates: const [50.0, 50.5],
        viewMinX: 0,
        viewMaxX: 100,
        plotWidthPx: 1000,
        minSeparationPx: 20, // 2 birim
        anchorSeparationPx: 8,
        alwaysKeep: {100.0},
      );
      expect(t.shows(50.0), isTrue);
      // 0.5 birim (5px) < 20px → hâlâ seyreltilir.
      expect(t.shows(50.5), isFalse);
    });
  });
}
