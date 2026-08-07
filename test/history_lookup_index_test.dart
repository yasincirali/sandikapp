import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// `HistoryService` fiyat serisi lookup'ı eskiden her çağrıda
/// `map.keys.toList()..sort()` + doğrusal tarama yapıyordu. Slot × varlık
/// başına çağrıldığı için grafik filtreleri saniyelerce takılıyordu.
/// Artık sıralı indeks + ikili arama kullanılıyor.
///
/// Bu testler ikili aramanın ESKİ doğrusal taramayla BİREBİR aynı sonucu
/// verdiğini garanti eder — hızlanma davranışı değiştirmemeli.
void main() {
  /// Eski implementasyonun referans hâli: `<= target` olan en büyük indeks.
  int referenceFloorIndex(List<int> sortedKeys, int target) {
    int best = -1;
    for (int i = 0; i < sortedKeys.length; i++) {
      if (sortedKeys[i] <= target) {
        best = i;
      } else {
        break;
      }
    }
    return best;
  }

  group('floorIndex — ikili arama', () {
    test('boş listede -1 döner', () {
      expect(HistoryService.floorIndexForTest(const [], 1000), -1);
    });

    test('hedef tüm anahtarlardan küçükse -1 döner', () {
      expect(HistoryService.floorIndexForTest(const [10, 20, 30], 5), -1);
    });

    test('tam eşleşmede o anahtarın indeksini döner', () {
      final keys = [10, 20, 30, 40];
      expect(HistoryService.floorIndexForTest(keys, 30), 2);
    });

    test('aradaki değerde bir önceki anahtara düşer', () {
      final keys = [10, 20, 30, 40];
      expect(HistoryService.floorIndexForTest(keys, 35), 2);
    });

    test('hedef tüm anahtarlardan büyükse son indeksi döner', () {
      final keys = [10, 20, 30, 40];
      expect(HistoryService.floorIndexForTest(keys, 9999), 3);
    });

    test('tek elemanlı liste — sınır durumları', () {
      expect(HistoryService.floorIndexForTest(const [100], 99), -1);
      expect(HistoryService.floorIndexForTest(const [100], 100), 0);
      expect(HistoryService.floorIndexForTest(const [100], 101), 0);
    });

    test('rastgele serilerde doğrusal taramayla birebir aynı sonuç', () {
      final rnd = Random(42);
      for (int iter = 0; iter < 300; iter++) {
        final n = rnd.nextInt(60) + 1;
        final keys = <int>{};
        while (keys.length < n) {
          keys.add(rnd.nextInt(5000));
        }
        final sorted = keys.toList()..sort();

        // Anahtarların kendisi, aralar ve iki uç için sorgula.
        final targets = <int>[
          sorted.first - 1,
          sorted.last + 1,
          ...sorted,
          for (int i = 0; i < 20; i++) rnd.nextInt(5200) - 100,
        ];

        for (final t in targets) {
          expect(
            HistoryService.floorIndexForTest(sorted, t),
            referenceFloorIndex(sorted, t),
            reason: 'keys=$sorted target=$t',
          );
        }
      }
    });

    test('gerçekçi zaman damgası ölçeğinde doğru çalışır', () {
      // Günlük slotlar — gerçek kullanımdaki büyüklük sınıfı.
      final start = DateTime(2025, 1, 1).millisecondsSinceEpoch;
      const dayMs = 24 * 60 * 60 * 1000;
      final keys = [for (int i = 0; i < 365; i++) start + i * dayMs];

      // Hafta sonu boşluğu benzeri: tam bir slotun ortası
      final midDay = start + 100 * dayMs + (dayMs ~/ 2);
      expect(HistoryService.floorIndexForTest(keys, midDay), 100);
      expect(HistoryService.floorIndexForTest(keys, start), 0);
      expect(HistoryService.floorIndexForTest(keys, start - 1), -1);
      expect(
          HistoryService.floorIndexForTest(keys, start + 364 * dayMs), 364);
    });
  });
}
