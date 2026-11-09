import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Müşteri raporu 2 Kas 20:45 (#1, #2):
/// - Tek akışta (`anaRakamGizli`) dönem eğrisi kartı çizilmez; sayfanın
///   başındaki büyük grafik aynı dönemi zaten gösteriyor. Sekmeli eski
///   düzende kart yerinde.
/// - Para hareketi olmayan dönemde köprüde "Yatırdığın ₺0" satırı yok,
///   dipnot "değişimin tamamı fiyattan" der.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  PeriodSummary ozet({double katki = 12000, double? temettu}) => PeriodSummary(
        period: SummaryPeriod.birYil,
        start: DateTime(2025, 9, 14),
        end: DateTime(2026, 9, 13),
        baslangicTRY: 100000,
        sonTRY: 100000 + katki + 48000 - (temettu ?? 0),
        katkiTRY: katki - (temettu ?? 0),
        piyasaTRY: 48000,
        getiriPct: 40,
        temettuTRY: temettu,
        sparkline: const [100000, 120000, 140000, 160000],
      );

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(390, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [SandikPalette.light]),
      home: Scaffold(
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(20), child: child)),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('eğri kartı sekmeli düzende var, tek akışta yok', (t) async {
    await pump(t, PeriodSummaryView(summary: ozet()));
    expect(find.text('Yıl eğrisi'), findsOneWidget);

    await pump(t, PeriodSummaryView(summary: ozet(), anaRakamGizli: true));
    expect(find.text('Yıl eğrisi'), findsNothing);
  });

  testWidgets('para hareketi yoksa Yatırdığın satırı ve uzun dipnot yok',
      (t) async {
    await pump(t, PeriodSummaryView(summary: ozet(katki: 0)));
    expect(find.text('Nereden geldi'), findsOneWidget);
    expect(find.text('Yatırdığın'), findsNothing);
    expect(find.textContaining('değişimin tamamı fiyattan'), findsOneWidget);
    expect(find.textContaining('Nakit temettü'), findsNothing);
  });

  testWidgets('para yatırıldıysa satır ve temettü dipnotu yerinde',
      (t) async {
    await pump(t, PeriodSummaryView(summary: ozet()));
    expect(find.text('Yatırdığın'), findsOneWidget);
    expect(find.textContaining('Nakit temettü'), findsOneWidget);
  });

  testWidgets('yalnız temettü varsa dipnot temettüyü açıklar', (t) async {
    await pump(t, PeriodSummaryView(summary: ozet(katki: 0, temettu: 2000)));
    expect(find.text('Yatırdığın'), findsNothing);
    expect(find.textContaining('Nakit temettü'), findsOneWidget);
  });
}
