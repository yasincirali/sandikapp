import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  // 2026-11-14 (yasin, "C · kamera + yay"): ara kareyi artık fl_chart'ın
  // kendi lerp'i değil ZoomableChart'ın geçiş saati üretir; LineChart'a HEP
  // sıfır süreyle hazır kare gider. fl_chart lerp'i etiket adımını ara
  // değerlerden geçirip y etiketlerini zıplatıyordu.
  double cizilenMaxY(WidgetTester t) =>
      t.widget<LineChart>(find.byType(LineChart).first).data.maxY;

  testWidgets('veri değişince ara kareyi geçiş saati üretir, LineChart süresi sıfır',
      (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);

    await tester.pumpWidget(host(vp, 100));
    expect(tester.widget<LineChart>(find.byType(LineChart)).duration,
        Duration.zero);

    await tester.pumpWidget(host(vp, 500));
    expect(cizilenMaxY(tester), 100, reason: 'ilk kare eski çizim');
    await tester.pump(const Duration(milliseconds: 60));
    final ara = cizilenMaxY(tester);
    expect(ara, greaterThan(100));
    expect(ara, lessThan(500));
    expect(tester.widget<LineChart>(find.byType(LineChart)).duration,
        Duration.zero);
    await tester.pumpAndSettle();
    expect(cizilenMaxY(tester), 500);
  });

  testWidgets('jest sırasında geçiş yok (parmağı geciktirmesin)',
      (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);

    await tester.pumpWidget(host(vp, 100));

    final center = tester.getCenter(find.byType(ZoomableChart));
    final p1 = await tester.startGesture(center - const Offset(40, 0));
    final p2 = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    await p1.moveBy(const Offset(-25, 0));
    await p2.moveBy(const Offset(25, 0));
    await tester.pump();

    // Parmak ekrandayken veri değişirse yeni çizim tek karede gelir.
    await tester.pumpWidget(host(vp, 300));
    expect(cizilenMaxY(tester), 300);

    await p1.up();
    await p2.up();
    await tester.pumpAndSettle();

    // Jest bitince geçiş geri gelir.
    await tester.pumpWidget(host(vp, 500));
    await tester.pump(const Duration(milliseconds: 60));
    expect(cizilenMaxY(tester), lessThan(500));
    await tester.pumpAndSettle();
    expect(cizilenMaxY(tester), 500);
  });

  testWidgets('hareketi azalt: geçiş yok', (tester) async {
    final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(vp.dispose);
    Widget azalt(double m) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(vp, m));
    await tester.pumpWidget(azalt(100));
    await tester.pumpWidget(azalt(500));
    expect(cizilenMaxY(tester), 500);
  });
}
