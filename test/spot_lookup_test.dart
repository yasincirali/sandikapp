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

  // ── coveringSpotIndex ────────────────────────────────────────────────────
  //
  // İşlem noktalarını çizerken "en yakın" değil "içine düştüğü bar" gerekir.
  // 6A/1Y periyotlarında veri `ResolutionTier.weekly` gelir ve her nokta
  // haftanın PAZARTESİSİNE snap edilir; çarşamba yapılan bir alım hiçbir
  // spot'un günüyle eşleşmez. Bu yüzden noktalar hiç çizilmiyordu.
  group('coveringSpotIndex — işlemi kapsayan bar', () {
    /// Referans: doğrusal tarama ile `spot.x <= x` olan son indeks.
    int referenceCovering(List<FlSpot> spots, double x) {
      int best = -1;
      for (int i = 0; i < spots.length; i++) {
        if (spots[i].x <= x) best = i;
      }
      return best;
    }

    test('boş liste -1 döner', () {
      expect(coveringSpotIndex(const [], 5.0), -1);
    });

    test('ilk noktadan önceki X için -1 döner', () {
      final s = spotsAt([10.0, 20.0, 30.0]);
      expect(coveringSpotIndex(s, 9.99), -1);
    });

    test('nokta üstünde o noktanın kendisini döner', () {
      final s = spotsAt([0.0, 7.0, 14.0, 21.0]);
      expect(coveringSpotIndex(s, 0.0), 0);
      expect(coveringSpotIndex(s, 7.0), 1);
      expect(coveringSpotIndex(s, 21.0), 3);
    });

    test('iki nokta arasında SOLDAKİNİ döner (ileri yuvarlamaz)', () {
      final s = spotsAt([0.0, 7.0, 14.0]);
      // 13.9 → 7 (index 1). "En yakın" 14'ü (index 2) seçerdi — yanlış bar.
      expect(coveringSpotIndex(s, 13.9), 1);
      expect(nearestSpotIndex(s, 13.9), 2, reason: 'ikisi farklı davranmalı');
    });

    test('son noktadan sonraki X için son noktayı döner', () {
      final s = spotsAt([0.0, 7.0, 14.0]);
      expect(coveringSpotIndex(s, 999.0), 2);
    });

    test('HAFTALIK snap senaryosu — hafta içi işlem o haftanın barına düşer',
        () {
      // Pazartesilere snap edilmiş 1 yıllık seri (7 gün adım).
      final weekly = spotsAt([for (int w = 0; w < 52; w++) (w * 7).toDouble()]);

      // 3. haftanın çarşambası: 14 + 2 = 16. gün.
      // Eski eşitlik kontrolü hiçbir spot bulamıyordu (16 ∉ {0,7,14,21...}).
      final i = coveringSpotIndex(weekly, 16.0);
      expect(i, 2);
      expect(weekly[i].x, 14.0, reason: 'o haftanın pazartesisi');

      // Haftanın her günü AYNI bara düşmeli — kritik değişmez.
      for (final offset in const [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) {
        expect(coveringSpotIndex(weekly, 14.0 + offset), 2,
            reason: 'offset=$offset');
      }
      // 7. gün artık SONRAKİ haftadır.
      expect(coveringSpotIndex(weekly, 21.0), 3);
    });

    test('doğrusal referansla birebir aynı (rastgele)', () {
      final rnd = Random(99);
      for (int t = 0; t < 300; t++) {
        final n = 1 + rnd.nextInt(40);
        final xs = <double>{};
        while (xs.length < n) {
          xs.add((rnd.nextDouble() * 200).roundToDouble());
        }
        final sorted = xs.toList()..sort();
        final s = spotsAt(sorted);
        for (int q = 0; q < 25; q++) {
          final x = rnd.nextDouble() * 220 - 10;
          expect(coveringSpotIndex(s, x), referenceCovering(s, x),
              reason: 'x=$x spots=$sorted');
        }
        // Nokta üstü ve komşulukları
        for (final v in sorted) {
          for (final d in const [-0.001, 0.0, 0.001]) {
            expect(coveringSpotIndex(s, v + d), referenceCovering(s, v + d),
                reason: 'v=$v d=$d');
          }
        }
      }
    });
  });
}
