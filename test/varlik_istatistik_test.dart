import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';

/// Varlık sayfasının sayıları — `DonemIstatistigi`.
///
/// Sayfa bu sayıları kendisi hesaplamaz (`varlik_sayfasi_test` kilitler);
/// kurallar burada, widget kurmadan doğrulanır.
void main() {
  final t0 = DateTime(2026, 1, 1).millisecondsSinceEpoch;
  const gun = 24 * 60 * 60 * 1000;

  Map<int, double> seri(List<double> fiyat, {int adimGun = 1}) => {
        for (var i = 0; i < fiyat.length; i++) t0 + i * adimGun * gun: fiyat[i],
      };

  group('dönem değişimi', () {
    test('(son − ilk) / ilk — uygulamanın her yerindeki formül', () {
      final ist = DonemIstatistigi.hesapla(seri([100, 90, 125]),
          periodDays: 30)!;
      expect(ist.fark, 25);
      expect(ist.degisimPct, closeTo(25, 1e-9));
      expect(ist.son, 125);
    });

    test('yuvarlanmış sıfır NÖTR sayılır', () {
      final ist = DonemIstatistigi.hesapla(seri([100, 100.001]),
          periodDays: 7)!;
      expect(ist.isFlat, isTrue);
    });

    test('iki noktadan kısa seride sonuç YOK — uydurma yok', () {
      expect(DonemIstatistigi.hesapla(seri([100]), periodDays: 30), isNull);
      expect(DonemIstatistigi.hesapla(const {}, periodDays: 30), isNull);
    });

    test('sıfır ve negatif fiyat seriye girmez', () {
      final ist = DonemIstatistigi.hesapla(seri([0, 100, -5, 110]),
          periodDays: 30)!;
      expect(ist.ilk, 100);
      expect(ist.dusuk, 100);
    });

    test('sıra harita sırasından değil ZAMANDAN', () {
      final ist = DonemIstatistigi.hesapla(
          {t0 + 2 * gun: 120, t0: 100, t0 + gun: 90}, periodDays: 30)!;
      expect(ist.ilk, 100);
      expect(ist.son, 120);
    });
  });

  group('aralık ve düşüş', () {
    test('yüksek, düşük ve bugünkü konum', () {
      final ist = DonemIstatistigi.hesapla(seri([100, 80, 120, 110]),
          periodDays: 30)!;
      expect(ist.yuksek, 120);
      expect(ist.dusuk, 80);
      expect(ist.konum, closeTo(0.75, 1e-9));
    });

    test('düz seride konum ortada', () {
      final ist =
          DonemIstatistigi.hesapla(seri([50, 50, 50]), periodDays: 30)!;
      expect(ist.konum, 0.5);
    });

    test('en büyük düşüş zirveden sonraki dipten ölçülür', () {
      // 100 → 150 (zirve) → 90 (dip): −40%. Baştaki 100'den ölçülseydi −10%.
      final ist = DonemIstatistigi.hesapla(seri([100, 150, 120, 90, 130]),
          periodDays: 30)!;
      expect(ist.enBuyukDususPct, closeTo(-40, 1e-9));
    });

    test('hiç düşmeyen seride düşüş sıfır', () {
      final ist = DonemIstatistigi.hesapla(seri([100, 101, 102]),
          periodDays: 30)!;
      expect(ist.enBuyukDususPct, 0);
    });
  });

  group('oynaklık', () {
    // Sabit tohumlu, günlük %2 sapmalı rastgele yürüyüş.
    List<double> yuruyus(int n, {int tohum = 7, double sapma = 0.02}) {
      final r = math.Random(tohum);
      final out = <double>[100];
      for (var i = 1; i < n; i++) {
        // Box–Muller
        final u1 = r.nextDouble().clamp(1e-12, 1.0);
        final u2 = r.nextDouble();
        final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
        out.add(out.last * math.exp(z * sapma));
      }
      return out;
    }

    test('kısa dönemde (gün içi, 1H) hesaplanmaz', () {
      final f = yuruyus(80);
      expect(
          DonemIstatistigi.hesapla(seri(f), periodDays: 1)!.oynaklikPct, isNull);
      expect(
          DonemIstatistigi.hesapla(seri(f), periodDays: 7)!.oynaklikPct, isNull);
    });

    test('az gözlemde hesaplanmaz — gürültü sayı olarak gösterilmez', () {
      final f = yuruyus(DonemIstatistigi.asgariGozlem);
      expect(DonemIstatistigi.hesapla(seri(f), periodDays: 30)!.oynaklikPct,
          isNull);
    });

    test('yıllık gözlem sayısı VERİDEN ölçülür: haftalık seri şişmez', () {
      // Aynı süreç iki sıklıkta örneklenir. Sabit √252 kullanılsaydı
      // haftalık seri ~√5 kat YÜKSEK çıkardı.
      final gunluk = yuruyus(365 * 3, tohum: 11);
      final haftalik = [
        for (var i = 0; i < gunluk.length; i += 7) gunluk[i],
      ];
      final g = DonemIstatistigi.hesapla(seri(gunluk), periodDays: 1825)!
          .oynaklikPct!;
      final h = DonemIstatistigi.hesapla(seri(haftalik, adimGun: 7),
              periodDays: 1825)!
          .oynaklikPct!;
      // Beklenen: %2 × √365 ≈ %38.
      expect(g, closeTo(0.02 * math.sqrt(365) * 100, 4));
      expect(h / g, inInclusiveRange(0.75, 1.3));
    });
  });
}
