import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Alım günü" dot anahtarlarının hesabı optimize edildi:
/// eskiden her spot için `assets.any((a) => yıl/ay/gün eşleşiyor mu)` şeklinde
/// iç içe tarama yapılıyordu (spot × varlık) ve bu, viewport değiştiği HER
/// karede tekrarlanıyordu. Yeni hâl varlıkların alım günlerini bir kez
/// "gün damgası" set'ine indirip spot başına O(1) lookup yapıyor.
///
/// Bu test iki algoritmanın AYNI sonucu verdiğini doğrular. Ekrandaki private
/// metodu doğrudan çağıramadığımız için her iki algoritma da burada birebir
/// yeniden üretilir — amaç mantığın denkliğini kilitlemek.
void main() {
  // ── Eski (referans) algoritma ────────────────────────────────────────────
  Set<double> legacyBuyDayKeys(
      List<List<FlSpot>> segmentSpots, List<DateTime> addedDates, DateTime start) {
    final keys = <double>{};
    for (final spots in segmentSpots) {
      for (final spot in spots) {
        final dateAtSpot =
            start.add(Duration(minutes: (spot.x * 24 * 60).round()));
        final hasAddition = addedDates.any((d) =>
            d.year == dateAtSpot.year &&
            d.month == dateAtSpot.month &&
            d.day == dateAtSpot.day);
        if (hasAddition) keys.add(spot.x);
      }
    }
    return keys;
  }

  // ── Yeni algoritma ───────────────────────────────────────────────────────
  Set<double> fastBuyDayKeys(
      List<List<FlSpot>> segmentSpots, List<DateTime> addedDates, DateTime start) {
    final buyDays = <int>{};
    for (final d in addedDates) {
      buyDays.add(DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
    }
    final keys = <double>{};
    for (final spots in segmentSpots) {
      for (final spot in spots) {
        final dateAtSpot =
            start.add(Duration(minutes: (spot.x * 24 * 60).round()));
        final dayTs =
            DateTime(dateAtSpot.year, dateAtSpot.month, dateAtSpot.day)
                .millisecondsSinceEpoch;
        if (buyDays.contains(dayTs)) keys.add(spot.x);
      }
    }
    return keys;
  }

  group('alım günü dot anahtarları — eski/yeni denkliği', () {
    final start = DateTime(2026, 1, 1);

    List<FlSpot> dailySpots(int days) =>
        [for (int i = 0; i < days; i++) FlSpot(i.toDouble(), 100.0 + i)];

    test('alım yokken her iki algoritma da boş döner', () {
      final segs = [dailySpots(30)];
      expect(fastBuyDayKeys(segs, const [], start), isEmpty);
      expect(fastBuyDayKeys(segs, const [], start),
          legacyBuyDayKeys(segs, const [], start));
    });

    test('tek alım günü — aynı anahtar', () {
      final segs = [dailySpots(30)];
      final adds = [DateTime(2026, 1, 11, 14, 30)];
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
      // 1 Ocak + 10 gün = 11 Ocak → x = 10
      expect(fastBuyDayKeys(segs, adds, start), {10.0});
    });

    test('çok alımlı, çok segmentli senaryo — aynı sonuç', () {
      final segs = [dailySpots(200), dailySpots(50)];
      final adds = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2, 9),
        DateTime(2026, 2, 15, 23, 59),
        DateTime(2026, 5, 30),
        DateTime(2026, 3, 3, 12),
      ];
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
    });

    test('aynı gün birden çok alım — tek anahtar üretir', () {
      final segs = [dailySpots(30)];
      final adds = [
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 5, 15),
        DateTime(2026, 1, 5, 17, 45),
      ];
      final fast = fastBuyDayKeys(segs, adds, start);
      expect(fast, legacyBuyDayKeys(segs, adds, start));
      expect(fast.length, 1);
    });

    test('kesirli (saatlik) X değerlerinde de denk', () {
      // Saatlik seri: X kesirli gün (1/24 adımlarla).
      final hourly = [
        for (int i = 0; i < 24 * 7; i++) FlSpot(i / 24.0, 100.0 + i)
      ];
      final adds = [
        DateTime(2026, 1, 3, 10),
        DateTime(2026, 1, 6, 20),
      ];
      expect(fastBuyDayKeys([hourly], adds, start),
          legacyBuyDayKeys([hourly], adds, start));
    });

    test('aralık dışı alımlar hiçbir anahtar üretmez', () {
      final segs = [dailySpots(30)];
      final adds = [DateTime(2025, 6, 1), DateTime(2027, 6, 1)];
      expect(fastBuyDayKeys(segs, adds, start), isEmpty);
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
    });
  });
}
