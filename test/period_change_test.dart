import 'package:flutter_test/flutter_test.dart';

/// Dönem değişimi hesabının regresyon testi.
///
/// Kullanıcı tercihi: HAM değer farkı (son − ilk). Nakit akışı düzeltmesi
/// bilinçli olarak uygulanmaz — grafikteki çizginin iki ucuyla birebir
/// tutarlı olması tercih edildi. Dönem içi para girişi ayrı bir bilgi
/// satırıyla kullanıcıya bildirilir (rakamı değiştirmeden).
({double change, double? pct, bool isFlat}) periodChange({
  required double firstY,
  required double lastY,
}) {
  final change = lastY - firstY;
  final pct = firstY > 0 ? (change / firstY) * 100 : null;
  final isFlat = change.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
  return (change: change, pct: pct, isFlat: isFlat);
}

/// Dönem içi net para girişi — bilgi satırının tetikleyicisi.
double netInflow({
  required List<({DateTime date, double costTRY, bool isBuy})> lots,
  required DateTime start,
  required DateTime end,
}) {
  final startMs =
      DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
  final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
      .millisecondsSinceEpoch;
  double net = 0;
  for (final l in lots) {
    final ms = l.date.millisecondsSinceEpoch;
    if (ms < startMs || ms > endMs) continue;
    net += l.isBuy ? l.costTRY : -l.costTRY;
  }
  return net;
}

void main() {
  group('dönem değişimi', () {
    test('artışta pozitif tutar ve yüzde', () {
      final r = periodChange(firstY: 100000, lastY: 106700);
      expect(r.change, closeTo(6700, 0.01));
      expect(r.pct, closeTo(6.7, 0.01));
      expect(r.isFlat, isFalse);
    });

    test('düşüşte negatif tutar ve yüzde', () {
      final r = periodChange(firstY: 100000, lastY: 92000);
      expect(r.change, closeTo(-8000, 0.01));
      expect(r.pct, closeTo(-8.0, 0.01));
      expect(r.isFlat, isFalse);
    });

    test('değişim yoksa flat işaretlenir', () {
      final r = periodChange(firstY: 50000, lastY: 50000);
      expect(r.isFlat, isTrue);
      expect(r.pct, 0);
    });

    test('kuruş altı değişim flat sayılır', () {
      // Yuvarlanınca 0 ₺ görünen değişim için yeşil/kırmızı göstermek
      // "hareket var" yanılgısı yaratır.
      final r = periodChange(firstY: 100000, lastY: 100000.3);
      expect(r.isFlat, isTrue);
    });

    test('taban sıfırsa yüzde tanımsız, tutar yine hesaplanır', () {
      // Dönem başında portföy boştu (simülasyon dışı kenar durum).
      final r = periodChange(firstY: 0, lastY: 25000);
      expect(r.pct, isNull);
      expect(r.change, closeTo(25000, 0.01));
      expect(r.isFlat, isFalse);
    });
  });

  group('dönem içi net para girişi', () {
    final start = DateTime(2026, 7, 2);
    final end = DateTime(2026, 8, 2);

    test('dönem içindeki alım sayılır', () {
      final n = netInflow(
        lots: [
          (date: DateTime(2026, 7, 20), costTRY: 50000, isBuy: true),
        ],
        start: start,
        end: end,
      );
      expect(n, 50000);
    });

    test('dönem dışındaki alım sayılmaz', () {
      final n = netInflow(
        lots: [
          (date: DateTime(2026, 5, 1), costTRY: 50000, isBuy: true),
        ],
        start: start,
        end: end,
      );
      expect(n, 0);
    });

    test('satış net girişi azaltır', () {
      final n = netInflow(
        lots: [
          (date: DateTime(2026, 7, 10), costTRY: 50000, isBuy: true),
          (date: DateTime(2026, 7, 25), costTRY: 20000, isBuy: false),
        ],
        start: start,
        end: end,
      );
      expect(n, 30000);
    });

    test('son gün dahil edilir (gün sonuna kadar)', () {
      final n = netInflow(
        lots: [
          (date: DateTime(2026, 8, 2, 14, 30), costTRY: 10000, isBuy: true),
        ],
        start: start,
        end: end,
      );
      expect(n, 10000, reason: 'bitiş günü içindeki işlem kapsam dışı kalmamalı');
    });
  });

  test('ham fark, para girişi olduğunda getiriden yüksektir', () {
    // Kullanıcının seçtiği yöntemin bilinen davranışı — bilgi satırının
    // var olma sebebi. 100k başlangıç, 50k yeni alım, 160k bitiş.
    final r = periodChange(firstY: 100000, lastY: 160000);
    final inflow = netInflow(
      lots: [(date: DateTime(2026, 7, 15), costTRY: 50000, isBuy: true)],
      start: DateTime(2026, 7, 2),
      end: DateTime(2026, 8, 2),
    );
    expect(r.change, 60000);
    expect(inflow, 50000);
    // Gerçek getiri farkın yalnızca bir kısmı; UI bunu bilgi satırıyla söyler.
    expect(r.change - inflow, 10000);
  });
}
