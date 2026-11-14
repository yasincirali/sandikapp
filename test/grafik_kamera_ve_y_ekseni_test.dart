import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// yasin (2026-11-14, TestFlight): "zaman seçimleri arasında geçişte
/// dikey uzunluk değişiyor ve y etiketlerinin yerleri değişiyor"; seçilen
/// çözüm "C · kamera + yay", şartı kararlı ve sıçramasız.
///
/// Kilitler:
///  • Geçişin hiçbir karesinde ara değer etiketi yazılmaz: görünen her y
///    etiketi eski ya da yeni adımın katıdır (fl_chart lerp'i adımı
///    25 → 31,7 → 250 diye geçirip "31,7" gibi etiketler basıyordu).
///  • Etiket sütunu yerinde: her etiketin solu sağ rezervin solunda.
///  • Kamera: uzaklaşmada ilk kare önceki çizimle aynı pencere, Y bandı
///    kareden kareye sıçramaz, sonunda tek grafik kalır.
///  • Hareketi azalt: tek kare.
void main() {
  const genislik = 400.0;
  const rezerv = 60.0;

  LineChartData veri(double minX, double maxX, double Function(double) f,
      {double adimSayisi = 4, double kok = 0}) {
    final spots = <FlSpot>[
      for (var x = minX.floorToDouble(); x <= maxX.ceilToDouble(); x++)
        FlSpot(x, f(x + kok)),
    ];
    final ys = spots.map((s) => s.y);
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    final adim = _guzel((hi - lo) / adimSayisi);
    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: lo - adim / 2,
      maxY: hi + adim / 2,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: adim,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0x22000000), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        leftTitles: const AxisTitles(),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: rezerv,
            interval: adim,
            getTitlesWidget: (v, m) => Text('y:${_yaz(v)}',
                maxLines: 1, softWrap: false),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(spots: spots, dotData: const FlDotData(show: false)),
      ],
    );
  }

  Widget kur(LineChartData Function(double, double) kurucu,
          {required double minX,
          required double maxX,
          double? koken,
          Object? anahtar,
          bool azalt = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(genislik, 800), disableAnimations: azalt),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: genislik,
                child: ZoomableChart(
                  fullMinX: minX,
                  fullMaxX: maxX,
                  height: 300,
                  plotPaddingRight: rezerv,
                  builder: kurucu,
                  kameraKokeni: koken,
                  sifirlamaAnahtari: anahtar,
                ),
              ),
            ),
          ),
        ),
      );

  List<double> etiketler(WidgetTester t) => [
        for (final w in t.widgetList<Text>(find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith('y:'))))
          double.parse(w.data!.substring(2)),
      ];

  bool katMi(double v, double adim) {
    final k = v / adim;
    return (k - k.roundToDouble()).abs() < 1e-6;
  }

  testWidgets('morf: her karede etiketler yalnız eski ya da yeni adımın katı',
      (tester) async {
    final kucuk = veri(0, 10, (x) => 100 + x * 10); // adım 25
    final buyuk = veri(0, 10, (x) => 100 + x * 100); // adım 250
    final a1 = kucuk.titlesData.rightTitles.sideTitles.interval!;
    final a2 = buyuk.titlesData.rightTitles.sideTitles.interval!;
    expect(a1, isNot(a2));
    await tester.pumpWidget(kur((_, __) => kucuk, minX: 0, maxX: 10));
    await tester.pumpAndSettle();
    expect(etiketler(tester), isNotEmpty);

    await tester.pumpWidget(kur((_, __) => buyuk, minX: 0, maxX: 10));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final v in etiketler(tester)) {
        expect(katMi(v, a1) || katMi(v, a2), isTrue,
            reason: 'kare $i: $v ara değer etiketi');
      }
      for (final e in find
          .byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('y:'))
          .evaluate()) {
        final sol = tester.getTopLeft(find.byWidget(e.widget)).dx -
            tester.getTopLeft(find.byType(ZoomableChart)).dx;
        expect(sol, closeTo(genislik - rezerv, 0.5),
            reason: 'etiket sütunu kaymamalı');
      }
    }
    await tester.pumpAndSettle();
    expect(etiketler(tester).every((v) => katMi(v, a2)), isTrue);
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart).first)
            .data
            .titlesData
            .rightTitles
            .sideTitles
            .getTitlesWidget(150, _bosMeta)
            .runtimeType,
        SizedBox,
        reason: 'fl_chart sağ etiket yazmaz (sütunu ZoomableChart çizer)');
  });

  testWidgets('kamera: uzaklaşma ilk karede yerinde, bant sıçramaz, sonda tek grafik',
      (tester) async {
    double f(double gun) => 1000 + 300 * (gun / 30) + 40 * ((gun % 7) - 3);
    // Kısa dönem: son 30 gün, köken = gün 335 (x 0..30).
    LineChartData kisa(double a, double b) => veri(a, b, f, kok: 335);
    // Uzun dönem: 365 gün, köken = gün 0 (x 0..365), haftalık sıklık.
    LineChartData uzun(double a, double b) => veri(a, b, f);
    await tester.pumpWidget(
        kur(kisa, minX: 0, maxX: 30, koken: 335, anahtar: '1A'));
    await tester.pumpAndSettle();
    final ilk = tester.widget<LineChart>(find.byType(LineChart).first).data;

    await tester.pumpWidget(
        kur(uzun, minX: 0, maxX: 365, koken: 0, anahtar: '1Y'));
    final kare0 = tester.widget<LineChart>(find.byType(LineChart).first).data;
    // Alt grafik yeni kurucunun eski penceredeki hâli: 335..365.
    expect(kare0.minX, closeTo(335, 1e-6));
    expect(kare0.maxX, closeTo(365, 1e-6));
    expect(kare0.minY, closeTo(ilk.minY, 1e-6),
        reason: 'ilk kare önceki çizimin bandında');
    expect(kare0.maxY, closeTo(ilk.maxY, 1e-6));

    var oncekiAralik = kare0.maxY - kare0.minY;
    var oncekiMin = kare0.minX;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final d = tester.widget<LineChart>(find.byType(LineChart).first).data;
      expect(d.minX, lessThanOrEqualTo(oncekiMin + 1e-6),
          reason: 'pencere tek yönde açılır');
      final aralik = d.maxY - d.minY;
      // Yay ilk karelerde hızlıdır (pencere kare başına ~%20 açılır);
      // sıçrama = tek karede bandın yarısından fazla değişmesi.
      expect((aralik - oncekiAralik).abs(), lessThan(oncekiAralik * 0.5),
          reason: 'kare $i: Y bandı sıçradı');
      oncekiAralik = aralik;
      oncekiMin = d.minX;
    }
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    final son = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(son.minX, 0);
    expect(son.maxX, 365);
  });

  testWidgets('hareketi azalt: geçiş yok, tek karede yeni çizim',
      (tester) async {
    final kucuk = veri(0, 10, (x) => 100 + x * 10);
    final buyuk = veri(0, 10, (x) => 100 + x * 100);
    await tester.pumpWidget(
        kur((_, __) => kucuk, minX: 0, maxX: 10, azalt: true));
    await tester.pump();
    await tester.pumpWidget(
        kur((_, __) => buyuk, minX: 0, maxX: 10, azalt: true));
    final d = tester.widget<LineChart>(find.byType(LineChart).first).data;
    expect(d.maxY, buyuk.maxY);
    final a2 = buyuk.titlesData.rightTitles.sideTitles.interval!;
    expect(etiketler(tester).every((v) => katMi(v, a2)), isTrue);
  });
}

final _bosMeta = TitleMeta(
  min: 0,
  max: 1,
  parentAxisSize: 1,
  axisPosition: 0,
  appliedInterval: 1,
  sideTitles: const SideTitles(),
  formattedValue: '',
  axisSide: AxisSide.right,
);

double _guzel(double ham) {
  if (ham <= 0) return 1;
  var m = 1.0;
  while (ham / m >= 10) {
    m *= 10;
  }
  while (ham / m < 1) {
    m /= 10;
  }
  final f = ham / m;
  return (f < 1.5 ? 1 : f < 3 ? 2.5 : f < 7 ? 5 : 10) * m;
}

String _yaz(double v) => v.toStringAsFixed(4);
