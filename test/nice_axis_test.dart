import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Grafik ekseninin OKUNABİLİR sınırlarda çizilmesi.
///
/// Sınırlar ham min/max'tan alınınca `₺2,4893M` / `₺2,4880M` gibi keyfi
/// rakamlar çıkıyordu; kullanıcı bunlardan bir şey çıkaramaz. "Nice
/// numbers" (Heckbert) kuralı sınırları 1/2/2,5/5 × 10ⁿ adımlarının
/// katlarına oturtur.
void main() {
  /// Sınırın verilen adımın tam katı olup olmadığı.
  bool katMi(double deger, double adim) =>
      (deger / adim - (deger / adim).round()).abs() < 1e-6;

  group('okunabilir sınırlar', () {
    test('sınırlar yuvarlak adımlara oturur', () {
      // Gerçek emülatör verisi — önce ₺2,4893M / ₺2,4880M çıkıyordu.
      final b = DailySummary.niceAxisBounds([
        2486107.0,
        2485002.0,
        2487315.0,
      ]);

      // Bant ~₺2.300 + %25 pay → adım ₺1.000 mertebesinde beklenir.
      final span = b.max - b.min;
      final adim = span / 4; // dört eşit bölme varsayımı

      expect(adim, greaterThan(0));
      // Sınırların ikisi de aynı adımın katı olmalı.
      expect(katMi(b.min, 500) || katMi(b.min, 1000) || katMi(b.min, 2500),
          isTrue,
          reason: 'alt sınır yuvarlak bir basamağa oturmalı: ${b.min}');
      expect(katMi(b.max, 500) || katMi(b.max, 1000) || katMi(b.max, 2500),
          isTrue,
          reason: 'üst sınır yuvarlak bir basamağa oturmalı: ${b.max}');
    });

    test('veri HER ZAMAN eksenin içinde kalır', () {
      // En kritik değişmez: sınır veriyi kesiyorsa çizgi kırpılır ve
      // grafik yalan söyler.
      final seriler = <List<double>>[
        [2486107.0, 2485002.0, 2487315.0],
        [100.0, 105.0],
        [999999.0, 1000001.0],
        [0.5, 0.7],
        [12345.678, 12999.999],
      ];

      for (final v in seriler) {
        final b = DailySummary.niceAxisBounds(v);
        final mn = v.reduce((a, x) => a < x ? a : x);
        final mx = v.reduce((a, x) => a > x ? a : x);

        expect(b.min, lessThanOrEqualTo(mn),
            reason: 'alt sınır veriyi kesiyor: $v → ${b.min}');
        expect(b.max, greaterThanOrEqualTo(mx),
            reason: 'üst sınır veriyi kesiyor: $v → ${b.max}');
      }
    });

    test('düz seride bile bant açılır', () {
      // Piyasa kapalıyken tüm noktalar aynı. Bant sıfır genişlikte
      // kalırsa sıfıra bölme olur ve iki etiket aynı rakamı gösterir.
      final b = DailySummary.niceAxisBounds([2486107.0, 2486107.0]);

      expect(b.max, greaterThan(b.min));
    });

    test('küçük portföyde de yuvarlak kalır', () {
      final b = DailySummary.niceAxisBounds([100.0, 110.0]);

      expect(b.min, lessThanOrEqualTo(100.0));
      expect(b.max, greaterThanOrEqualTo(110.0));
      // Bu ölçekte adım 5 ya da 10 olmalı; kesirli sınır beklenmez.
      expect(b.min, closeTo(b.min.roundToDouble(), 1e-6));
      expect(b.max, closeTo(b.max.roundToDouble(), 1e-6));
    });

    test('boş seri çökmez', () {
      final b = DailySummary.niceAxisBounds(const []);
      expect(b.max, greaterThan(b.min));
    });

    test('iki yüzey AYNI sınırları üretir', () {
      // Kilit ekranı ve widget aynı portföy için farklı eksen gösterirse
      // kullanıcı hangisine güveneceğini bilemez. İkisi de bu tek
      // fonksiyondan okur; burada fonksiyonun kararlı (deterministik)
      // olduğu kilitlenir.
      final v = [2486107.0, 2485002.0, 2487315.0];

      final a = DailySummary.niceAxisBounds(v);
      final b = DailySummary.niceAxisBounds(List<double>.from(v));

      expect(a.min, b.min);
      expect(a.max, b.max);
    });

    test('normalize edilen çizgi eksenin İÇİNDE kalır', () {
      // Kilit ekranı çizgiyi 0…1'e indirger ve bu aralık EKSENLE aynı
      // sınırlardan hesaplanır. Ayrışırlarsa çizgi kılavuzların dışına
      // taşar: etiket "₺2,48M" derken çizgi tuvalin tepesinde durur.
      final v = [2486107.0, 2485002.0, 2487315.0];
      final b = DailySummary.niceAxisBounds(v);
      final span = b.max - b.min;

      for (final deger in v) {
        final norm = (deger - b.min) / span;
        expect(norm, inInclusiveRange(0.0, 1.0),
            reason: '$deger eksen dışına taşıyor');
      }
    });

    test('gerçek hareket bandı genişletir', () {
      // %2lik gerçek düşüş kırpılmamalı.
      final b = DailySummary.niceAxisBounds([2500000.0, 2450000.0]);

      expect(b.min, lessThanOrEqualTo(2450000.0));
      expect(b.max, greaterThanOrEqualTo(2500000.0));
    });
  });
}
