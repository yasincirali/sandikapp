import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/series_downsample.dart';

/// **"GÜNLÜK" bir TAKVİM GÜNÜDÜR — kayan 24 saat değil.**
///
/// ## Ne oluyordu
/// Kırpma penceresi son noktadan 24 saat geriye sayıyordu. Döviz gibi 7/24
/// işlem gören sembollerde bu dünün öğleden sonrasını da içine alıyor, eksen
/// "15:37 · 21:18 · 02:59 · 08:41" okunuyor ve dönem başı `%0` referansı
/// DÜNE düşüyordu. Kullanıcının sorduğu soru "bugün ne oldu"; cevabın tabanı
/// da bugünün açılışı olmalı.
///
/// Bu, uygulamanın geri kalanının zaten kullandığı tanım:
/// `getPortfolioHistoryHourlyBreakdown` gün içi grid'ini bugünün 00:00'ından
/// kurar ve `DailySummary` gece yarısını geçen önbelleği koşulsuz düşürür —
/// tam da "bugünkü değişim aslında dünden bugüne farkı gösterir" durumuna
/// düşmemek için. Takip listesi bu konvansiyonun dışında kalmıştı.
void main() {
  /// Bugünün verilen saatindeki zaman damgası.
  int bugun(int saat, [int dakika = 0]) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, saat, dakika)
        .millisecondsSinceEpoch;
  }

  /// Dünün verilen saatindeki zaman damgası.
  int dun(int saat) {
    final n = DateTime.now().subtract(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, saat).millisecondsSinceEpoch;
  }

  group('GÜNLÜK — takvim günü', () {
    test('dünün noktaları PENCEREYE GİRMEZ', () {
      // Üretim vakası: USDTRY 7/24 işlem gördüğü için Yahoo `1d` range'i
      // dünün öğleden sonrasını da döndürüyordu.
      final seri = {
        dun(15): 100.0,
        dun(21): 101.0,
        bugun(2): 102.0,
        bugun(9): 103.0,
      };

      final k = HistoryService.clipToPeriod(seri, 1);

      expect(k.containsKey(dun(15)), isFalse, reason: 'dün pencerede olamaz');
      expect(k.containsKey(dun(21)), isFalse);
      expect(k.keys.toSet(), {bugun(2), bugun(9)});
    });

    test('dönem başı referansı BUGÜNÜN ilk noktası', () {
      // `normalizeSeries` ilk noktayı %0 kabul eder; pencere yanlışsa yüzde
      // de yanlış olur. Kullanıcı bulgusu: "1 gün önceye göre değil".
      final seri = {
        dun(15): 100.0,
        bugun(0, 5): 200.0, // bugünün açılışı
        bugun(9): 202.0,
      };

      final k = HistoryService.clipToPeriod(seri, 1);
      final ilk = (k.keys.toList()..sort()).first;

      expect(k[ilk], 200.0,
          reason: 'taban bugünün açılışı olmalı, dünkü 100 değil');
    });

    test('gece yarısı SINIRDA kalır — 00:00 dahil', () {
      final seri = {dun(23): 1.0, bugun(0): 2.0, bugun(1): 3.0};
      expect(HistoryService.clipToPeriod(seri, 1).containsKey(bugun(0)), isTrue);
    });

    test('borsa kapalıyken son SEANSIN tamamı görünür', () {
      // Pazar günü GÜNLÜK seçilirse son seans Cuma'dadır. `now`'dan geriye
      // saymak grafiği boşaltırdı; çapa son noktanın GÜNÜ.
      final n = DateTime.now().subtract(const Duration(days: 3));
      int gun(int saat) =>
          DateTime(n.year, n.month, n.day, saat).millisecondsSinceEpoch;

      final seri = {gun(9): 1.0, gun(13): 2.0, gun(18): 3.0};
      final k = HistoryService.clipToPeriod(seri, 1);

      expect(k.length, 3, reason: 'o günün seansı bütün olarak kalmalı');
    });

    test('daha uzun dönemler KAYAN pencere olarak kalır', () {
      // Yalnızca GÜNLÜK takvim günüdür; "1H" bir haftalık kayan penceredir.
      final n = DateTime.now();
      int gunOnce(int g) =>
          n.subtract(Duration(days: g)).millisecondsSinceEpoch;

      final seri = {
        gunOnce(20): 1.0,
        gunOnce(5): 2.0,
        gunOnce(1): 3.0,
        gunOnce(0): 4.0,
      };

      final k = HistoryService.clipToPeriod(seri, 7);
      expect(k.length, 3, reason: 'son 7 gün: 5, 1 ve 0 gün öncesi');
    });
  });

  group('nokta seyreltme — zarf korunur', () {
    List<FlSpot> seri(int n) =>
        [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), (i % 7).toDouble())];

    test('hedefin altındaki seri OLDUĞU GİBİ döner', () {
      final s = seri(50);
      expect(seyreltSpots(s, 160), same(s));
    });

    test('seyreltilmiş seri hedefe yakın kalır', () {
      final s = seri(2000);
      final k = seyreltSpots(s, 160);
      expect(k.length, lessThanOrEqualTo(170));
      expect(k.length, greaterThan(40));
    });

    test('TEPE ve DİP korunur — grafik yalan söylemez', () {
      // En kritik değişmez: naif seyreltme (her n'inci nokta) gerçek bir
      // sıçramayı gizleyebilir.
      final s = [for (var i = 0; i < 1000; i++) FlSpot(i.toDouble(), 0.0)];
      s[437] = const FlSpot(437, 99.0); // ani tepe
      s[812] = const FlSpot(812, -55.0); // ani dip

      final k = seyreltSpots(s, 160);
      final yler = k.map((e) => e.y).toList();

      expect(yler, contains(99.0), reason: 'tepe kaybolamaz');
      expect(yler, contains(-55.0), reason: 'dip kaybolamaz');
    });

    test('X sırası ARTAN kalır', () {
      // Bozulursa fl_chart zamanda geri giden bir zikzak çizer.
      final s = [
        for (var i = 0; i < 900; i++)
          FlSpot(i.toDouble(), (i * 37 % 101).toDouble())
      ];
      final k = seyreltSpots(s, 160);

      for (var i = 1; i < k.length; i++) {
        expect(k[i].x, greaterThanOrEqualTo(k[i - 1].x),
            reason: '$i. noktada sıra bozuldu');
      }
    });

    test('uçlar HER ZAMAN korunur', () {
      final s = seri(1500);
      final k = seyreltSpots(s, 160);
      expect(k.first, s.first, reason: 'dönem başı %0 referansı');
      expect(k.last, s.last, reason: 'son değer');
    });
  });
}
