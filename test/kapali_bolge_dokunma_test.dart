import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/spot_lookup.dart';

/// Piyasa kapalı bölgesinde de crosshair GEZİNEBİLMELİ.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12)
/// "grafikte kapalı olan günde chart traceable değil, uzun tuttuğumda
/// kapanışa kadar gidebiliyorum."
///
/// Sebep: üç crosshair callback'i de yalnızca `primarySeg.spots`'u
/// tarıyordu. `primarySeg` "en KALIN segment" olarak seçiliyor (Y ekseni
/// için doğru kaynak) ama kapalı kuyruğu daha ince bir segment olduğu
/// için dışarıda kalıyordu. `clamp(spots.first.x, spots.last.x)` parmağı
/// kapanışta durduruyordu.
///
/// Düzeltme: dokunma TÜM çizilmiş noktaları görür (`crosshairSpots`).
void main() {
  final ekran = File('lib/screens/portfolio_performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('birleştirilmiş nokta listesi', () {
    test('crosshair kaynağı TÜM segmentleri kapsar', () {
      expect(ekran.contains('final List<FlSpot> crosshairSpots'), isTrue,
          reason: 'Birleşik kaynak yok.');
      expect(ekran.contains('for (final s in segments) ...s.spots'), isTrue,
          reason: 'Segmentler birleştirilmiyor — kuyruk dokunulamaz kalır.');
    });

    test('üç callback de AYNI kaynağı kullanır', () {
      // Farklı listelerde arama yapılırsa snap edilen X ile gösterilen
      // değer ayrışır: çizgi bir yerde, pill başka değerde durur.
      final sayi = 'final spots = crosshairSpots;'.allMatches(ekran).length;
      expect(sayi, 3,
          reason: 'Callback\'lerden biri hâlâ `primarySeg.spots` tarıyor '
              '($sayi/3 hizalı).');
    });

    test('`primarySeg` Y ekseni için KORUNUR', () {
      // Birleşik listeyi Y sınırlarında kullanmak yanlış olurdu: passive
      // segment (0 çizgisi) min'i 0'a çeker ve aktif değerler ezilir.
      expect(ekran.contains('segments.reduce((a, b) =>'), isTrue,
          reason: 'primarySeg seçimi kaldırılmış — Y ekseni bozulur.');
    });
  });

  group('etiket — gün ve tarih okunur', () {
    test('çok günlü seride TARİH de yazılır', () {
      expect(ekran.contains("DateFormat('d MMM · HH:mm', 'tr_TR')"), isTrue,
          reason: 'Kuyrukta yalnızca saat yazılıyor; "Cmt 14:00" ile '
              '"Cuma 14:00" ayırt edilemez.');
    });

    test('tek günlük seride saat YETER — gereksiz gürültü yok', () {
      expect(ekran.contains('cokGunlu'), isTrue,
          reason: 'Tarih koşulsuz eklenmiş; normal gün içi grafikte '
              'gereksiz.');
    });
  });

  group('ikili arama sözleşmesi — sıralı ve tekil', () {
    // `nearestSpotIndex` ikili arama yapıyor: girdi X'e göre SIRALI
    // olmalı. Segment birleştirme bunu bozarsa crosshair rastgele
    // noktalara atlar — sessiz ve fark edilmesi zor bir hata.
    test('birleştirme sıralama yapıyor', () {
      expect(ekran.contains('..sort((a, b) => a.x.compareTo(b.x))'), isTrue,
          reason: 'Birleşik liste sıralanmıyor.');
    });

    test('sınırdaki çakışan nokta TEKİLLEŞTİRİLİYOR', () {
      // Seans ve kuyruk segmentleri sınır noktasını paylaşıyor
      // (`s.x <= sinirX` ve `s.x >= sinirX`).
      expect(ekran.contains('birlesik[i].x != birlesik[i - 1].x'), isTrue,
          reason: 'Çift nokta eleniyor değil.');
    });

    test('nearestSpotIndex sıralı listede doğru çalışır', () {
      // Davranışın kendisini de ölç — kaynak denetimi tek başına yetmez.
      final spots = [
        const FlSpot(0, 10),
        const FlSpot(100, 11),
        const FlSpot(200, 12), // kapanış
        const FlSpot(1440, 12), // kuyruk: ertesi gün
        const FlSpot(2880, 12), // kuyruk: iki gün sonra
      ];

      // Kuyruk bölgesine dokunma kapanışa DÜŞMEMELİ.
      expect(spots[nearestSpotIndex(spots, 1400)].x, 1440);
      expect(spots[nearestSpotIndex(spots, 2900)].x, 2880);
      // Seans bölgesi de doğru kalmalı.
      expect(spots[nearestSpotIndex(spots, 90)].x, 100);
    });
  });
}
