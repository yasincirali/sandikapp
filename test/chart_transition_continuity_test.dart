import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Grafik geçişlerinin akıcı olmasının TEK şartı: `LineChart` widget'ı
/// ağaçta KALMALI.
///
/// `LineChart` bir `ImplicitlyAnimatedWidget` — yeni `LineChartData`
/// verildiğinde eskisinden yenisine kendi lerp'ler. Ama widget unmount
/// edilirse (spinner ile değiştirilir, sarmalayıcı yapı değişir, ya da
/// key değişir) State ve tween sıfırlanır; kullanıcı "0'dan yeniden
/// çizim" görür. Bu testler o sürekliliği kilitler.
void main() {
  LineChartData dataFor(double maxY) => LineChartData(
        minX: 0,
        maxX: 10,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i <= 10; i++) FlSpot(i.toDouble(), i * maxY / 10),
            ],
          ),
        ],
      );

  Widget host(ChartViewport vp, double maxY) => MaterialApp(
        home: Scaffold(
          body: ZoomableChart(
            fullMinX: 0,
            fullMaxX: 10,
            viewportController: vp,
            builder: (_, __) => dataFor(maxY),
          ),
        ),
      );

  testWidgets('veri değişiminde LineChart State korunur (tween sıfırlanmaz)',
      (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);

    await tester.pumpWidget(host(vp, 100));
    final stateBefore = tester.state(find.byType(LineChart));

    // Veriyi değiştir — periyot/filtre değişimini taklit eder.
    await tester.pumpWidget(host(vp, 500));
    final stateAfter = tester.state(find.byType(LineChart));

    expect(identical(stateBefore, stateAfter), isTrue,
        reason: 'LineChart State yeniden yaratıldı → implicit animasyon '
            'sıfırlanır ve geçiş "0\'dan çizim" gibi görünür');
  });

  testWidgets('viewport controller değişince de State korunur',
      (tester) async {
    final vp1 = ChartViewport(fullMinX: 0, fullMaxX: 10);
    final vp2 = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp1.dispose);
    addTearDown(vp2.dispose);

    await tester.pumpWidget(host(vp1, 100));
    final before = tester.state(find.byType(LineChart));

    // Periyot değişiminde ekran yeni bir ChartViewport kuruyor.
    await tester.pumpWidget(host(vp2, 100));
    final after = tester.state(find.byType(LineChart));

    expect(identical(before, after), isTrue,
        reason: 'controller swap didUpdateWidget ile ele alınmalı, '
            'remount ile değil');
  });

  testWidgets('varsayılan swap süresi Sandık motion token\'ı kullanır',
      (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);

    await tester.pumpWidget(host(vp, 100));

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.duration, SandikMotion.state,
        reason: 'fl_chart varsayılanı (150ms/linear) yerine tasarım '
            'sisteminin durum geçişi token\'ı kullanılmalı');
    expect(chart.curve, SandikMotion.enter);
  });

  testWidgets('jest sırasında animasyon kapanır (parmağı geciktirmesin)',
      (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);

    await tester.pumpWidget(host(vp, 100));

    // Pinch başlat: iki parmak.
    final center = tester.getCenter(find.byType(ZoomableChart));
    final p1 = await tester.startGesture(center - const Offset(40, 0));
    final p2 = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    await p1.moveBy(const Offset(-25, 0));
    await p2.moveBy(const Offset(25, 0));
    await tester.pump();

    final during = tester.widget<LineChart>(find.byType(LineChart));
    expect(during.duration, Duration.zero,
        reason: 'jest sırasında lerp parmağın arkasında kalan lastikli '
            'bir his yaratır — kapalı olmalı');

    await p1.up();
    await p2.up();
    await tester.pumpAndSettle();

    // Jest bitince tekrar açılmalı ki periyot değişimleri morf'lansın.
    final after = tester.widget<LineChart>(find.byType(LineChart));
    expect(after.duration, SandikMotion.state,
        reason: 'jest bittikten sonra implicit animasyon geri gelmeli');
  });
}
