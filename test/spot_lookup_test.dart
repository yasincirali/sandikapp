import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/spot_lookup.dart';

/// Crosshair snap'i eskiden tüm spot listesini doğrusal tarıyordu; parmak
/// hareket ettikçe kare başına O(n) karşılaştırma yapıyordu. Artık ikili
/// arama kullanılıyor.
///
/// Bu testler ikili aramanın doğrusal taramayla BİREBİR aynı noktayı
/// seçtiğini garanti eder — eşit mesafe (tie) durumu dahil.
void main() {
  /// Eski implementasyonun referans hâli: ilk en yakın nokta kazanır.
  int referenceNearest(List<FlSpot> spots, double x) {
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < spots.length; i++) {
      final d = (spots[i].x - x).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  List<FlSpot> spotsAt(List<double> xs) =>
      [for (final x in xs) FlSpot(x, x * 2)];

  group('nearestSpotIndex', () {
    test('boş liste -1 döner', () {
      expect(nearestSpotIndex(const [], 5), -1);
      expect(nearestSpot(const [], 5), isNull);
    });

    test('tek eleman her zaman 0', () {
      final s = spotsAt([42]);
      expect(nearestSpotIndex(s, -100), 0);
      expect(nearestSpotIndex(s, 42), 0);
      expect(nearestSpotIndex(s, 999), 0);
    });

    test('tam eşleşme kendi indeksini verir', () {
      final s = spotsAt([0, 1, 2, 3, 4]);
      for (int i = 0; i < s.length; i++) {
        expect(nearestSpotIndex(s, s[i].x), i);
      }
    });

    test('aralıkların dışında uç noktalara düşer', () {
      final s = spotsAt([10, 20, 30]);
      expect(nearestSpotIndex(s, -5), 0);
      expect(nearestSpotIndex(s, 1000), 2);
    });

    test('iki nokta arasında daha yakın olanı seçer', () {
      final s = spotsAt([0, 10]);
      expect(nearestSpotIndex(s, 4), 0);
      expect(nearestSpotIndex(s, 6), 1);
    });

    test('tam ortada (eşit mesafe) soldaki kazanır — referansla aynı', () {
      final s = spotsAt([0, 10]);
      // Doğrusal tarama `d < bestD` kullandığı için ilk (sol) nokta kazanır.
      expect(nearestSpotIndex(s, 5), referenceNearest(s, 5));
      expect(nearestSpotIndex(s, 5), 0);
    });

    test('düzensiz aralıklı seride doğrusal taramayla aynı', () {
      final s = spotsAt([0, 0.5, 0.75, 9, 40, 41, 100]);
      for (double x = -5; x <= 110; x += 0.25) {
        expect(nearestSpotIndex(s, x), referenceNearest(s, x),
            reason: 'x=$x');
      }
    });

    test('rastgele sıralı serilerde doğrusal taramayla birebir aynı', () {
      final rnd = Random(7);
      for (int iter = 0; iter < 200; iter++) {
        final n = rnd.nextInt(50) + 1;
        final xs = <double>{};
        while (xs.length < n) {
          xs.add((rnd.nextInt(10000)) / 100.0);
        }
        final sorted = xs.toList()..sort();
        final s = spotsAt(sorted);

        for (int q = 0; q < 30; q++) {
          final x = rnd.nextDouble() * 120 - 10;
          expect(nearestSpotIndex(s, x), referenceNearest(s, x),
              reason: 'xs=$sorted x=$x');
        }
        // Nokta üstü ve komşuluk sorguları
        for (final v in sorted) {
          for (final d in const [-0.001, 0.0, 0.001]) {
            expect(nearestSpotIndex(s, v + d), referenceNearest(s, v + d),
                reason: 'v=$v d=$d');
          }
        }
      }
    });

    test('kesirli gün ölçeğinde (gerçek grafik X uzayı) doğru', () {
      // 365 günlük seri, X = kesirli gün.
      final s = spotsAt([for (int i = 0; i < 365; i++) i.toDouble()]);
      expect(nearestSpotIndex(s, 100.4), 100);
      expect(nearestSpotIndex(s, 100.6), 101);
      expect(nearestSpotIndex(s, 364.9), 364);
    });
  });
}
