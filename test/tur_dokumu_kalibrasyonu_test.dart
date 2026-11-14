import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tur_dokumu_kalibrasyonu.dart';

/// Performans › Bugün › "Türe göre · fiyat etkisi" (kullanıcı bildirimi
/// 2026-11-14, Cumartesi): Fon, BES ve Mevduat aynı −%0,34 ile zararda
/// görünüyordu; üçü de hafta sonu fiyatlanmaz. Altın satırının üst kartla
/// kaynak farkı tek çarpanla fiyatı oynamayan satırlara yayılıyordu.
void main() {
  TurDokumuUc u(double f, double l) => (first: f, last: l);

  // Ekrandaki uygulama: oynamayan satır ve sabit satır ölçeklenmez.
  List<TurDokumuUc> uygula(List<TurDokumuSatiri> s, double ustF, double ustL) {
    final k = turDokumuCarpanlari(s, ustFirst: ustF, ustLast: ustL);
    return [
      for (final x in s)
        x.sabit || !turDokumuOynadi(x.deger)
            ? x.deger
            : u(x.deger.first * k.kFirst, x.deger.last * k.kLast),
    ];
  }

  test('ekran görüntüsündeki durum: fiyatı oynamayan fon/BES/mevduat sıfır',
      () {
    // Altın kotasyon referansından +%0,53, üst kart altını sabit görüyor.
    final satirlar = [
      TurDokumuSatiri(u(1755000, 1764300),
          toplamda: u(1764300, 1764300), sabit: true),
      TurDokumuSatiri(u(186000, 186000)), // BES
      TurDokumuSatiri(u(252000, 252000)), // Mevduat
      TurDokumuSatiri(u(485000, 485000)), // Fon
    ];
    const ustF = 1764300 + 186000 + 252000 + 485000.0;
    const ustL = ustF + 196;
    final r = uygula(satirlar, ustF, ustL);
    for (final i in [1, 2, 3]) {
      expect(r[i].last - r[i].first, 0, reason: 'satır $i oynamamalı');
    }
    // Altın kendi kaynağının ölçtüğünü gösterir, artığı yutmaz.
    expect(r[0].last - r[0].first, closeTo(9300, 0.01));
  });

  test('oynayan satırlar küçük artığı ağırlıklarınca paylaşır, toplam tutar',
      () {
    final satirlar = [
      TurDokumuSatiri(u(40000, 44000)),
      TurDokumuSatiri(u(30000, 31000)),
      TurDokumuSatiri(u(10000, 10000)), // oynamadı
    ];
    final r = uygula(satirlar, 80000, 85100);
    expect(r.fold(0.0, (a, x) => a + x.last), closeTo(85100, 0.01));
    expect(r[2].last - r[2].first, 0);
    expect(r[0].last / r[1].last, closeTo(44000 / 31000, 1e-9));
  });

  test('çarpan %2 sınırını aşarsa kalibrasyon yok', () {
    final satirlar = [
      TurDokumuSatiri(u(10000, 10100)),
      TurDokumuSatiri(u(90000, 90000)),
    ];
    final k = turDokumuCarpanlari(satirlar, ustFirst: 100000, ustLast: 99000);
    expect(k.kLast, 1.0);
  });

  test('oynayan satır yoksa ya da seri sıfırsa çarpan 1, NaN yok', () {
    final k = turDokumuCarpanlari([TurDokumuSatiri(u(5000, 5000))],
        ustFirst: 5000, ustLast: 5100);
    expect(k.kFirst, 1.0);
    expect(k.kLast, 1.0);
    final z = turDokumuCarpanlari([TurDokumuSatiri(u(0, 0))],
        ustFirst: 1000, ustLast: 1000);
    expect(z.kFirst.isFinite && z.kLast.isFinite, isTrue);
  });
}
