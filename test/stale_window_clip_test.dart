import 'package:flutter_test/flutter_test.dart';

/// Periyot değişiminde "bayat seri" davranışı.
///
/// Kullanıcı şikâyeti: interval seçiminde hâlâ loading görünüyordu. Sebep,
/// önceki periyottan devralınan serinin `stale` işaretlenip "veri yok"
/// sayılmasıydı → spinner. Düzeltme iki parçalı:
///
/// 1. Bayat seri artık ÇİZİLİR (soluk), spinner yalnızca hiç veri yokken.
/// 2. Ama bayat seri yeni pencereye KIRPILMALI: eski pencere daha genişse
///    (1Y → 1A) aralık dışı noktalar `startDate`'ten önceye düşer ve
///    grafikte negatif X'e çizilirdi — eksen kayar, çizgi sola taşardı.
///
/// Ekrandaki kırpma mantığı burada birebir yeniden üretilir.
void main() {
  /// Ekranlardaki kırpma ile aynı: yeni pencereye düşmeyen noktaları at.
  Map<int, double> clipToWindow(
      Map<int, double> raw, DateTime from, DateTime to) {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    return {
      for (final e in raw.entries)
        if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
    };
  }

  /// Tohum ancak >= 2 nokta kalırsa kullanılır; yoksa çizilecek çizgi yok.
  Map<int, double> seedOrEmpty(Map<int, double> clipped) =>
      clipped.length >= 2 ? clipped : const {};

  Map<int, double> series(DateTime start, int days) => {
        for (int i = 0; i < days; i++)
          start.add(Duration(days: i)).millisecondsSinceEpoch: 1000.0 + i,
      };

  group('bayat seri — yeni pencereye kırpma', () {
    final end = DateTime(2026, 8, 7);

    test('geniş → dar (1Y → 1A): sadece son 30 gün kalır', () {
      final yearly = series(end.subtract(const Duration(days: 365)), 365);
      final monthStart = end.subtract(const Duration(days: 30));

      final clipped = clipToWindow(yearly, monthStart, end);

      expect(clipped, isNotEmpty);
      // Pencere dışı hiçbir nokta kalmamalı — negatif X'in kaynağı buydu.
      for (final ts in clipped.keys) {
        expect(ts, greaterThanOrEqualTo(monthStart.millisecondsSinceEpoch),
            reason: 'pencere öncesi nokta kırpılmadı → grafik negatif X\'e '
                'çizilir ve eksen kayar');
        expect(ts, lessThanOrEqualTo(end.millisecondsSinceEpoch));
      }
      expect(clipped.length, lessThan(yearly.length));
    });

    test('dar → geniş (1A → 1Y): eldeki noktaların hepsi korunur', () {
      final monthly = series(end.subtract(const Duration(days: 30)), 30);
      final yearStart = end.subtract(const Duration(days: 365));

      final clipped = clipToWindow(monthly, yearStart, end);
      // Dar seri zaten geniş pencerenin içinde — hiçbir şey kaybolmamalı.
      expect(clipped.length, monthly.length);
    });

    test('hiç kesişim yoksa tohum kullanılmaz', () {
      // Çok eski bir seri, yeni pencereyle örtüşmüyor.
      final ancient = series(DateTime(2020, 1, 1), 10);
      final clipped =
          clipToWindow(ancient, end.subtract(const Duration(days: 30)), end);

      expect(clipped, isEmpty);
      expect(seedOrEmpty(clipped), isEmpty,
          reason: 'kesişim yokken bozuk bir çizgi gösterilmemeli');
    });

    test('tek nokta kalırsa tohum kullanılmaz (çizgi çizilemez)', () {
      final s = {
        end.subtract(const Duration(days: 40)).millisecondsSinceEpoch: 100.0,
        end.subtract(const Duration(days: 5)).millisecondsSinceEpoch: 200.0,
      };
      final clipped =
          clipToWindow(s, end.subtract(const Duration(days: 10)), end);

      expect(clipped.length, 1);
      expect(seedOrEmpty(clipped), isEmpty,
          reason: 'tek noktayla çizgi çizilemez — spinner daha doğru');
    });

    test('iki nokta kalırsa tohum kullanılır', () {
      final s = {
        end.subtract(const Duration(days: 8)).millisecondsSinceEpoch: 100.0,
        end.subtract(const Duration(days: 5)).millisecondsSinceEpoch: 200.0,
        end.subtract(const Duration(days: 40)).millisecondsSinceEpoch: 50.0,
      };
      final clipped =
          clipToWindow(s, end.subtract(const Duration(days: 10)), end);

      expect(clipped.length, 2);
      expect(seedOrEmpty(clipped), isNotEmpty);
    });

    test('sınır noktaları dahil (>= ve <=)', () {
      final from = end.subtract(const Duration(days: 10));
      final s = {
        from.millisecondsSinceEpoch: 1.0,
        end.millisecondsSinceEpoch: 2.0,
      };
      expect(clipToWindow(s, from, end).length, 2,
          reason: 'pencere sınırındaki noktalar korunmalı');
    });
  });

  group('spinner kararı', () {
    // Ekrandaki kural: hasData = seri boş değil (bayat olsa bile).
    bool showsSpinner({required Map<int, double> data}) => data.isEmpty;

    test('hiç veri yoksa spinner gösterilir (ilk açılış)', () {
      expect(showsSpinner(data: const {}), isTrue);
    });

    test('bayat seri varsa spinner GÖSTERİLMEZ', () {
      expect(showsSpinner(data: {1: 1.0, 2: 2.0}), isFalse,
          reason: 'kullanıcı şikâyeti: periyot değişiminde loading çıkıyordu');
    });
  });
}
