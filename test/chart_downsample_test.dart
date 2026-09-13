import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/chart_downsample.dart';

List<(int, double)> _seri(int n, double Function(int) f) =>
    [for (var i = 0; i < n; i++) (i * 60000, f(i))];

void main() {
  group('lttb', () {
    test('kısa seri AYNEN döner — gereksiz kopya yok', () {
      final s = _seri(10, (i) => i.toDouble());
      expect(identical(lttb(s, 50), s), isTrue);
      expect(identical(lttb(s, 10), s), isTrue);
    });

    test('hedef nokta sayısına uyar', () {
      final s = _seri(2526, (i) => sin(i / 30) * 100 + 500);
      for (final hedef in [60, 100, 300]) {
        expect(lttb(s, hedef).length, hedef, reason: 'hedef=$hedef');
      }
    });

    test('ilk ve son nokta KORUNUR — eksen sınırlarıyla ayrışmasın', () {
      final s = _seri(2000, (i) => i.toDouble());
      final d = lttb(s, 120);
      expect(d.first, s.first);
      expect(d.last, s.last);
    });

    test('sentetik nokta ÜRETMEZ — her çıktı girdide fiilen var', () {
      final s = _seri(1500, (i) => sin(i / 17) * 42 + 100);
      final kume = s.toSet();
      for (final p in lttb(s, 200)) {
        expect(kume.contains(p), isTrue, reason: '$p girdide yok');
      }
    });

    test('zaman sırası korunur', () {
      final s = _seri(1800, (i) => cos(i / 23) * 10);
      final d = lttb(s, 150);
      for (var i = 1; i < d.length; i++) {
        expect(d[i].$1, greaterThan(d[i - 1].$1));
      }
    });

    test('ZİRVE korunur — ortalama alsaydı törpülenirdi', () {
      // Düz seri, ortasında tek bir keskin sıçrama. Kullanıcının GÖRMESİ
      // gereken tam olarak bu nokta.
      final s = <(int, double)>[
        for (var i = 0; i < 1000; i++) (i * 60000, i == 500 ? 9999.0 : 100.0)
      ];
      final d = lttb(s, 100);
      expect(d.map((e) => e.$2), contains(9999.0),
          reason: 'zirve düşmüş — grafik gerçek sıçramayı gizler');
    });

    test('DİP de korunur', () {
      final s = <(int, double)>[
        for (var i = 0; i < 1000; i++) (i * 60000, i == 300 ? -500.0 : 100.0)
      ];
      expect(lttb(s, 100).map((e) => e.$2), contains(-500.0));
    });

    test('dejenere hedef (<3) girdiyi aynen döndürür', () {
      final s = _seri(500, (i) => i.toDouble());
      expect(identical(lttb(s, 2), s), isTrue);
      expect(identical(lttb(s, 0), s), isTrue);
    });

    test('sabit seri çökmez', () {
      final s = _seri(900, (_) => 42.0);
      final d = lttb(s, 80);
      expect(d.length, 80);
      expect(d.every((p) => p.$2 == 42.0), isTrue);
    });
  });

  group('hedefNoktaSayisi', () {
    test('ekran genişliğinin yarısı, 60..300 arasında kırpılır', () {
      expect(hedefNoktaSayisi(400), 200);
      expect(hedefNoktaSayisi(50), 60); // alt sınır
      expect(hedefNoktaSayisi(2000), 300); // üst sınır
    });
  });
}
