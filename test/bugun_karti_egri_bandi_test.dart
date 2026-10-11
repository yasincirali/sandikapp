import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/utils/chart_axis.dart' show gunIciAsgariBantOrani;
import 'package:portfoy_takip/widgets/bugun_karti.dart';

/// Ana sayfa "Bugün" eğrisi ile Performans "Bugün" grafiği aynı günü aynı
/// ölçekte çizer (TestFlight bulgusu 2026-10-11: pazar gecesi ₺1,81M'lik
/// portföyde ±₺30'luk kur oynaması kartta dağ-tepe, Performans'ta düz).
void main() {
  // Bandın içinde, değerin yüksekliğe oranı (0 alt, 1 üst).
  double konum(({double min, double max}) b, double v) =>
      (v - b.min) / (b.max - b.min);

  test('kuruşluk oynama kartın yüksekliğine yayılmaz', () {
    const acilis = 1810948.0;
    final seri = [
      acilis, acilis + 12, acilis - 18, acilis + 5, acilis - 30, //
      acilis - 9, acilis + 4, acilis + 20,
    ];
    final b = gunIciEgriBandi(seri);
    final yayilim = konum(b, acilis + 20) - konum(b, acilis - 30);
    // Eski davranış (ham min/max): yayılım = 1, tüm yükseklik.
    expect(yayilim, lessThan(0.02));
    expect(b.max - b.min,
        greaterThanOrEqualTo(acilis * gunIciAsgariBantOrani));
  });

  test('gerçek gün içi hareket hâlâ görünür', () {
    const acilis = 1810948.0;
    // %2'lik düşüş — bir portföyün tipik kötü günü.
    final seri = [for (var i = 0; i <= 20; i++) acilis * (1 - 0.001 * i)];
    final b = gunIciEgriBandi(seri);
    expect(konum(b, seri.first) - konum(b, seri.last), greaterThan(0.5));
  });

  test('veri her zaman bandın içinde', () {
    final seri = [100.0, 100.4, 99.7, 101.2, 100.9];
    final b = gunIciEgriBandi(seri);
    for (final v in seri) {
      expect(v, inInclusiveRange(b.min, b.max));
    }
  });

  test('ana ekran widget / Live Activity ile aynı kural', () {
    final seri = [2489300.0, 2489350.0, 2488000.0, 2490100.0];
    final a = gunIciEgriBandi(seri);
    final w = DailySummary.niceAxisBounds(seri);
    expect((a.min, a.max), (w.min, w.max));
  });
}
