import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

import 'helpers/kaynak.dart';

/// Alarm çizgisi yeni seviyeye kayarak oturur (2026-11-11). Kayma değer
/// uzayında (`KayanYatayCizgi.y`), piksel dönüşümü fl_chart'ta. Yalnız
/// alarm seviyesi değişince; dönem/ölçek değişiminde çizgi yeni ölçekte
/// anında yerini alır. Hareketi azalt açıkken anlık.
void main() {
  const renk = Color(0xFF00AA00);

  LineChartData veri(double olcek, Map<String, double> alarmlar,
          {double? dogum = 40}) =>
      LineChartData(
        minX: 0,
        maxX: 10,
        minY: 0,
        maxY: 100 * olcek,
        lineBarsData: [
          LineChartBarData(spots: [
            for (var i = 0; i <= 10; i++) FlSpot(i.toDouble(), i * 4.0 * olcek),
          ]),
        ],
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: 10, color: renk), // dönem başı: kaymaz
          for (final e in alarmlar.entries)
            KayanYatayCizgi(
                anahtar: e.key, y: e.value, dogumY: dogum, color: renk),
        ]),
      );

  Widget host(LineChartData d, {bool azalt = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: azalt),
          child: Scaffold(
            body: ZoomableChart(
              fullMinX: 0,
              fullMaxX: 10,
              builder: (_, __) => d,
            ),
          ),
        ),
      );

  List<HorizontalLine> cizgiler(WidgetTester t) => t
      .widget<LineChart>(find.byType(LineChart).first)
      .data
      .extraLinesData
      .horizontalLines;

  double alarmY(WidgetTester t) => cizgiler(t)[1].y;

  testWidgets(
      'seviye değişince ara karede eskiyle yeni arasında, sonunda '
      'yenide', (tester) async {
    await tester.pumpWidget(host(veri(1, {'a': 50})));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(veri(1, {'a': 80})));
    expect(alarmY(tester), 50, reason: 'ilk kare eski seviyede');
    await tester.pump(SandikMotion.state ~/ 2);
    expect(alarmY(tester), allOf(greaterThan(50), lessThan(80)));
    expect(cizgiler(tester)[0].y, 10, reason: 'dönem başı çizgisi kaymaz');
    await tester.pump(SandikMotion.state);
    expect(alarmY(tester), 80);
  });

  testWidgets('hareketi azalt: hemen yeni seviyede', (tester) async {
    await tester.pumpWidget(host(veri(1, {'a': 50}), azalt: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(veri(1, {'a': 80}), azalt: true));
    expect(alarmY(tester), 80);
  });

  testWidgets('yeni alarm son fiyattan hedefe kayar', (tester) async {
    await tester.pumpWidget(host(veri(1, {})));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(veri(1, {'a': 80})));
    expect(alarmY(tester), 40, reason: 'son fiyat seviyesinden doğar');
    await tester.pump(SandikMotion.state * 2);
    expect(alarmY(tester), 80);
  });

  testWidgets('dönem değişiminde kayma yok (aralığa giren alarm da)',
      (tester) async {
    await tester.pumpWidget(host(veri(1, {'a': 50})));
    await tester.pumpAndSettle();
    // Ölçek (noktalar, eksen) değişti; alarm seviyesi aynı + yeni görünen.
    await tester.pumpWidget(host(veri(2, {'a': 50, 'b': 150})));
    await tester.pump(SandikMotion.state ~/ 2);
    final ys = cizgiler(tester).map((c) => c.y).toList();
    expect(ys, containsAll([50.0, 150.0]),
        reason: 'değer uzayında sabit; ölçekle birlikte konumlanır');
  });

  testWidgets('silinen alarm çizgisi söner', (tester) async {
    await tester.pumpWidget(host(veri(1, {'a': 50})));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(veri(1, {})));
    await tester.pump(SandikMotion.state ~/ 2);
    final solan = cizgiler(tester).where((c) => c.y == 50).single;
    expect(solan.color!.a, allOf(greaterThan(0), lessThan(1)));
    await tester.pump(SandikMotion.state);
    expect(cizgiler(tester).where((c) => c.y == 50), isEmpty);
  });

  test('varlık sayfası alarm çizgisini anahtarlı ve son noktadan verir', () {
    final src = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(src, contains('_alarmYatayCizgileri(alarmCizgileri,'));
    expect(src, contains('sonFiyat: lastSpot?.y'));
    expect(src, contains('KayanYatayCizgi('));
  });
}
