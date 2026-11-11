import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// VoiceOver/TalkBack ile grafikte gün gün gezinme (2026-11-11; karar kaydı
/// `ZoomableChart._okuyucuX`). Grafik ayarlanabilir öğedir: yukarı/aşağı
/// kaydırma imleci bir nokta ileri/geri taşır, değer imleç etiketiyle
/// ("tarih, fiyat") okunur. İmleç yokken değer özet kalır; seri boşsa eylem
/// yok. Ortak bileşende olduğu için dört grafik yüzeyi de aynı davranır.
void main() {
  const fiyatlar = [40.0, 41.2, 39.8];
  final gunler = ['11 Ağu 2026', '12 Ağu 2026', '13 Ağu 2026'];

  Widget host(List<FlSpot> spots) => MaterialApp(
        home: Scaffold(
          body: ZoomableChart(
            fullMinX: 0,
            fullMaxX: 2,
            semanticLabel: 'Fiyat grafiği',
            semanticValueBuilder: (_, __) => 'özet',
            builder: (_, __) => LineChartData(
              minX: 0,
              maxX: 2,
              lineBarsData: [LineChartBarData(spots: spots)],
            ),
            crosshairLabelBuilder: (x) {
              final i = x.round();
              if (i < 0 || i >= fiyatlar.length) return null;
              return (fmtTRY(fiyatlar[i]), gunler[i]);
            },
          ),
        ),
      );

  final spots = [
    for (var i = 0; i < fiyatlar.length; i++) FlSpot(i.toDouble(), fiyatlar[i])
  ];

  SemanticsData veri(WidgetTester t) =>
      t.getSemantics(find.byType(ZoomableChart)).getSemanticsData();

  void eylem(WidgetTester t, SemanticsAction a) {
    final node = t.getSemantics(find.byType(ZoomableChart));
    expect(node.getSemanticsData().hasAction(a), isTrue);
    node.owner!.performAction(node.id, a);
  }

  testWidgets('increase/decrease eylemi var; imleç yokken değer özet',
      (tester) async {
    final h = tester.ensureSemantics();
    await tester.pumpWidget(host(spots));
    await tester.pumpAndSettle();
    final d = veri(tester);
    expect(d.hasAction(SemanticsAction.increase), isTrue);
    expect(d.hasAction(SemanticsAction.decrease), isTrue);
    expect(d.value, 'özet');
    expect(d.increasedValue, '11 Ağu 2026, ${fmtTRY(40.0)}');
    h.dispose();
  });

  testWidgets('increase imleci bir sonraki noktaya taşır, değer o noktanın '
      'metni; uçta eylem kalkar', (tester) async {
    final h = tester.ensureSemantics();
    await tester.pumpWidget(host(spots));
    await tester.pumpAndSettle();
    eylem(tester, SemanticsAction.increase);
    await tester.pump();
    expect(veri(tester).value, '11 Ağu 2026, ${fmtTRY(40.0)}');
    expect(veri(tester).decreasedValue, isEmpty,
        reason: 'ilk noktada geri gidilecek nokta yok');
    eylem(tester, SemanticsAction.increase);
    await tester.pump();
    final d = veri(tester);
    expect(d.value, '12 Ağu 2026, ${fmtTRY(41.2)}');
    expect(d.increasedValue, '13 Ağu 2026, ${fmtTRY(39.8)}');
    expect(d.decreasedValue, '11 Ağu 2026, ${fmtTRY(40.0)}');
    eylem(tester, SemanticsAction.increase);
    await tester.pump();
    expect(veri(tester).hasAction(SemanticsAction.increase), isFalse);
    eylem(tester, SemanticsAction.decrease);
    await tester.pump();
    expect(veri(tester).value, '12 Ağu 2026, ${fmtTRY(41.2)}');
    h.dispose();
  });

  testWidgets('seri boşsa eylem yok, değer özet', (tester) async {
    final h = tester.ensureSemantics();
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    final d = veri(tester);
    expect(d.hasAction(SemanticsAction.increase), isFalse);
    expect(d.hasAction(SemanticsAction.decrease), isFalse);
    expect(d.value, 'özet');
    h.dispose();
  });
}
