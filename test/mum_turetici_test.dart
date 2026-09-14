import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/mum_turetici.dart';

/// Mum türetici — tek değerli seriden OHLC.
///
/// Kullanıcı isteği (2026-09-12): TradingView'deki beş grafik tipi; Candle
/// "OHLC yok" diye ertelenmişti. OHLC artık elimizdeki noktalardan KOVA
/// bazında türetiliyor; bu testler cebrin doğru olduğunu, kovaların takvime
/// hizalandığını ve kova seçiminin mumları tek noktaya düşürmediğini
/// sabitler.
void main() {
  double ms(int h, [int m = 0]) =>
      DateTime(2026, 9, 10, h, m).millisecondsSinceEpoch.toDouble();

  group('mumlariTuret — OHLC cebri', () {
    test('kova içinde ilk=açılış, son=kapanış, uçlar=yüksek/düşük', () {
      final spots = [
        FlSpot(ms(10, 0), 100),
        FlSpot(ms(10, 5), 104),
        FlSpot(ms(10, 10), 98),
        FlSpot(ms(10, 15), 101),
        FlSpot(ms(10, 20), 103),
        FlSpot(ms(10, 25), 102),
      ];
      final mumlar = mumlariTuret(spots, kovaMs: 30 * 60 * 1000);
      expect(mumlar, hasLength(1));
      final m = mumlar.single;
      expect(m.acilis, 100);
      expect(m.kapanis, 102);
      expect(m.enYuksek, 104);
      expect(m.enDusuk, 98);
      expect(m.noktaSayisi, 6);
      expect(m.yukselen, isTrue);
      expect(m.x, ms(10, 0), reason: 'kova :00\'a hizalı');
      expect(m.merkezX, ms(10, 15));
    });

    test('kova sınırı takvime hizalı: 10:25 ve 10:30 ayrı mumlarda', () {
      final spots = [
        FlSpot(ms(10, 25), 100),
        FlSpot(ms(10, 30), 101),
        FlSpot(ms(10, 55), 99),
      ];
      final mumlar = mumlariTuret(spots, kovaMs: 30 * 60 * 1000);
      expect(mumlar.map((m) => m.x).toList(), [ms(10, 0), ms(10, 30)]);
      expect(mumlar[1].acilis, 101);
      expect(mumlar[1].kapanis, 99);
      expect(mumlar[1].yukselen, isFalse);
    });

    test('boş kova ÜRETİLMEZ (tatil/kapalı piyasa)', () {
      final spots = [
        FlSpot(ms(10, 0), 100),
        // 11:00–12:00 hiç nokta yok
        FlSpot(ms(13, 0), 105),
      ];
      final mumlar = mumlariTuret(spots, kovaMs: 60 * 60 * 1000);
      expect(mumlar.map((m) => m.x).toList(), [ms(10, 0), ms(13, 0)]);
    });

    test('sırasız girdi sıralanır; tek nokta doji olur', () {
      final spots = [FlSpot(ms(10, 20), 101), FlSpot(ms(10, 0), 101)];
      final mumlar = mumlariTuret(spots, kovaMs: 30 * 60 * 1000);
      expect(mumlar.single.acilis, 101);
      expect(mumlar.single.doji, isTrue);
    });

    test('boş seri ya da geçersiz kova → boş liste', () {
      expect(mumlariTuret(const [], kovaMs: 1000), isEmpty);
      expect(mumlariTuret([FlSpot(ms(10), 1)], kovaMs: 0), isEmpty);
    });

    test('haftalık kova Pazartesi\'de, aylık kova ayın 1\'inde başlar', () {
      // 10 Eylül 2026 Perşembe; haftanın Pazartesi'si 7 Eylül.
      final t = DateTime(2026, 9, 10, 15).millisecondsSinceEpoch.toDouble();
      final hafta = mumlariTuret([FlSpot(t, 1)], kovaMs: 7 * 24 * 3600e3);
      expect(hafta.single.x,
          DateTime(2026, 9, 7).millisecondsSinceEpoch.toDouble());
      final ay = mumlariTuret([FlSpot(t, 1)], kovaMs: 30 * 24 * 3600e3);
      expect(ay.single.x, DateTime(2026, 9, 1).millisecondsSinceEpoch.toDouble());
      // Eylül 30 gün: kova uzunluğu takvim ayı.
      expect(ay.single.kovaMs, 30 * 24 * 3600e3);
    });
  });

  group('mumKovasiSec — kova seçimi', () {
    const dk = 60 * 1000.0;
    const gun = 24 * 60 * dk;

    test('gün içi 5 dk\'lık 288 nokta → 30 dk (≈40 mum, ≥2 nokta)', () {
      expect(mumKovasiSec(spanMs: gun, noktaSayisi: 288), 30 * dk);
    });

    test('1 haftalık günlük seri → 1 gün olamaz (tek nokta); 7 gün olur', () {
      // 7 nokta: günlük kova mumları tek noktaya düşürürdü (düz çizgi).
      // asgariNokta=2 → en az 2 gün → adaylardan 7 gün.
      expect(mumKovasiSec(spanMs: 7 * gun, noktaSayisi: 7), 7 * gun);
    });

    test('1 yıllık günlük seri → 7 gün (≈52 mum)', () {
      expect(mumKovasiSec(spanMs: 365 * gun, noktaSayisi: 250), 7 * gun);
    });

    test('6 aylık günlük seri → 7 gün', () {
      expect(mumKovasiSec(spanMs: 180 * gun, noktaSayisi: 125), 7 * gun);
    });

    test('geçersiz girdi en küçük adayı döner', () {
      expect(mumKovasiSec(spanMs: 0, noktaSayisi: 0), mumKovaAdaylari.first);
    });

    test('adaylar artan ve takvimle hizalanabilir boyutlar', () {
      for (var i = 1; i < mumKovaAdaylari.length; i++) {
        expect(mumKovaAdaylari[i], greaterThan(mumKovaAdaylari[i - 1]));
      }
    });
  });
}
