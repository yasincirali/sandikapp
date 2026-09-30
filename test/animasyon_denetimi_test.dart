import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Animasyon denetimi (2026-10-01) — birinci kademe: kullanıcının doğrudan
/// hissettiği dört hata. Her test bir hatanın geri gelmesini kilitler.
void main() {
  group('çıkış eğrisi', () {
    test('SandikMotion.exit, enter.flipped ile birebir aynı', () {
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        expect(SandikMotion.exit.transform(t),
            closeTo(SandikMotion.enter.flipped.transform(t), 2e-3));
      }
    });

    test('tersten oynayınca ease-out: çıkışın ilk yarısında çoğu biter', () {
      // Ters yönde değer = exit(1 - geçen). Yarı sürede opaklık 0,5'in
      // ALTINDA olmalı — eski hâlde (enter tersten) 0,875'ti.
      final yaridaOpaklik = SandikMotion.exit.transform(0.5);
      expect(yaridaOpaklik, lessThan(0.2));
    });

    testWidgets('marka diyaloğu kapanırken yarı sürede büyük ölçüde solmuş',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));
      // ignore: unawaited_futures
      showAppInfo(ctx, title: 'Başlık', message: 'Mesaj');
      await tester.pumpAndSettle();

      Navigator.of(ctx).pop();
      await tester.pump();
      await tester.pump(SandikMotion.surface ~/ 2);

      final fade = tester.widget<FadeTransition>(find
          .ancestor(of: find.text('Başlık'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, lessThan(0.3),
          reason: 'kapanış ease-in kalmış: diyalog yarı sürede hâlâ görünür');
      await tester.pumpAndSettle();
    });
  });

  group('korunanPencere', () {
    (double, double) p(double lo, double hi, double yeniMax,
            {double eskiMax = 10, double yeniMin = 0}) =>
        ChartViewport.korunanPencere(
          minX: lo,
          maxX: hi,
          eskiMin: 0,
          eskiMax: eskiMax,
          yeniMin: yeniMin,
          yeniMax: yeniMax,
        );

    test('yakınlaştırılmamışsa yeni tam aralık', () {
      expect(p(0, 10, 12), (0.0, 12.0));
    });

    test('ortada yakınlaştırılmışsa aynı yerde kalır', () {
      expect(p(3, 5, 12), (3.0, 5.0));
    });

    test('sağ kenara dayalıysa kenarla birlikte kayar, genişlik korunur', () {
      expect(p(8, 10, 12), (10.0, 12.0));
    });

    test('aralık daralınca pencere içeri itilir', () {
      expect(p(6, 9, 8, eskiMax: 10), (5.0, 8.0));
    });

    test('pencere yeni aralıktan genişse tam aralık', () {
      expect(p(1, 9, 5, eskiMax: 10), (0.0, 5.0));
    });
  });

  group('ZoomableChart', () {
    LineChartData veri(double lo, double hi) => LineChartData(
          minX: lo,
          maxX: hi,
          minY: 0,
          maxY: 10,
          lineBarsData: [
            LineChartBarData(spots: [
              for (var i = 0; i <= 10; i++) FlSpot(i.toDouble(), i.toDouble()),
            ]),
          ],
        );

    Widget host(ChartViewport vp, {double fullMaxX = 10}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: ZoomableChart(
                  fullMinX: 0,
                  fullMaxX: fullMaxX,
                  height: 300,
                  enableTimeScaleDrag: false,
                  viewportController: vp,
                  builder: veri,
                ),
              ),
            ),
          ),
        );

    testWidgets('yakınlaştırılmışken tek parmak kaydırma parmağı takip eder',
        (tester) async {
      final vp = ChartViewport(fullMinX: 0, fullMaxX: 10)..set(2, 4);
      addTearDown(vp.dispose);
      await tester.pumpWidget(host(vp));

      final merkez = tester.getCenter(find.byType(ZoomableChart));
      final g = await tester.startGesture(merkez);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      // 800 px'lik alanda genişlik 2: 200 px'in kabul eşiğinden sonraki
      // ≥150 px'i pencereyi ≥0,375 sola taşır. Eski hata yalnız SON
      // karenin 20 px'ini uyguluyordu (0,05 → minX 1,95).
      expect(vp.minX, lessThan(1.7));
      expect(vp.maxX - vp.minX, closeTo(2, 1e-9), reason: 'kaydırma yakınlaştırmayı bozmamalı');
    });

    testWidgets('aralık uzayınca yakınlaştırma sıfırlanmaz', (tester) async {
      final vp = ChartViewport(fullMinX: 0, fullMaxX: 10)..set(3, 5);
      addTearDown(vp.dispose);
      await tester.pumpWidget(host(vp));
      await tester.pumpWidget(host(vp, fullMaxX: 11));
      await tester.pump();
      expect((vp.minX, vp.maxX), (3.0, 5.0));
      expect(vp.fullMaxX, 11);
    });
  });
}
