import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tur_dokumu_kalibrasyonu.dart';

/// Performans › Bugün › "Türe göre · fiyat etkisi" (yasin 2026-11-14,
/// Cumartesi ekran görüntüsü): Fon, BES ve Mevduat aynı −%0,34 ile zararda
/// görünüyordu; üçü de hafta sonu fiyatlanmaz. İki kural birlikte kilitli:
/// Σ satır == üst kart (her zaman) ve fiyatı oynamayan satır oynamaz.
void main() {
  TurDokumuUc u(double f, double l) => (first: f, last: l);

  // Ekrandaki uygulama (`_TypeBreakdownCard._calibrate`).
  List<TurDokumuUc> uygula(List<TurDokumuUc> s, double ustF, double ustL) {
    final k = turDokumuCarpanlari(s, ustFirst: ustF, ustLast: ustL);
    return [
      for (final x in s)
        k.yalnizOynayan && !turDokumuOynadi(x)
            ? x
            : u(x.first * k.kFirst, x.last * k.kLast),
    ];
  }

  double degisim(List<TurDokumuUc> r) =>
      r.fold(0.0, (a, x) => a + x.last - x.first);

  test('ekran görüntüsü: fon/BES/mevduat sıfır, toplam üst kartı tutar', () {
    // Altın kotasyon referansından +%0,53; üst kart toplamda +196 görüyor.
    final satirlar = [
      u(1755000, 1764300), // Altın
      u(186000, 186000), // BES
      u(252000, 252000), // Mevduat
      u(485000, 485000), // Fon
    ];
    const ustF = 1755000 + 186000 + 252000 + 485000.0;
    const ustL = ustF + 196;
    final r = uygula(satirlar, ustF, ustL);
    for (final i in [1, 2, 3]) {
      expect(r[i].last - r[i].first, 0, reason: 'satır $i oynamamalı');
    }
    expect(degisim(r), closeTo(196, 0.01));
    expect(r.fold(0.0, (a, x) => a + x.first), closeTo(ustF, 0.01));
    expect(r.fold(0.0, (a, x) => a + x.last), closeTo(ustL, 0.01));
  });

  test('artık büyük olsa da toplam tutar (eski %2 sınırı yok)', () {
    final satirlar = [u(10000, 10100), u(90000, 90000)];
    final r = uygula(satirlar, 100000, 99000);
    expect(degisim(r), closeTo(-1000, 0.01));
    expect(r[1].last - r[1].first, 0);
  });

  test('oynayan satırlar artığı ağırlıklarınca paylaşır, oranlar korunur', () {
    final satirlar = [u(40000, 44000), u(30000, 31000), u(10000, 10000)];
    final r = uygula(satirlar, 80000, 85100);
    expect(r.fold(0.0, (a, x) => a + x.last), closeTo(85100, 0.01));
    expect(r[2].last - r[2].first, 0);
    expect(r[0].last / r[1].last, closeTo(44000 / 31000, 1e-9));
  });

  test('hiçbir satır oynamadıysa artık hepsine dağılır, toplam tutar', () {
    final satirlar = [u(5000, 5000), u(3000, 3000)];
    final r = uygula(satirlar, 8000, 8010);
    expect(r.fold(0.0, (a, x) => a + x.last), closeTo(8010, 0.01));
  });

  test('sıfır seride bölme yok', () {
    final k = turDokumuCarpanlari([u(0, 0)], ustFirst: 1000, ustLast: 1000);
    expect(k.kFirst.isFinite && k.kLast.isFinite, isTrue);
  });
}
