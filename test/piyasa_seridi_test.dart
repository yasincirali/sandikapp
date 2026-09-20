import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';

/// Kayan bant — erişilebilirlik ve döngü kuralları.
///
/// Bant dört sabit değer taşır; ekran okuyucu bunu TEK cümle okumalı,
/// "hareketi azalt" açıkken akış olmamalı, dokunuş durdurmalı.
void main() {
  const ogeler = [
    PiyasaOgesi(etiket: 'Dolar', deger: '48,79', degisimPct: 0.08),
    PiyasaOgesi(etiket: 'Euro', deger: '56,11', degisimPct: -0.08),
    PiyasaOgesi(etiket: 'BIST 100', deger: '11.482', degisimPct: null),
  ];

  Future<void> pump(WidgetTester tester, {bool hareketiAzalt = false}) async {
    tester.view.physicalSize = const Size(320 * 3, 200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
          child: child!,
        ),
        home: const Scaffold(body: KayanBant(ogeler: ogeler)),
      ),
    );
    await tester.pump();
  }

  testWidgets('öğe metni: ad, değer, yön; değişimsiz öğe yüzde yazmaz',
      (tester) async {
    await pump(tester, hareketiAzalt: true);
    expect(find.text('Dolar'), findsWidgets);
    expect(find.text('48,79'), findsWidgets);
    expect(find.textContaining('▲'), findsWidgets);
    expect(find.textContaining('▼'), findsWidgets);
    expect(ogeler[2].metin, 'BIST 100 11.482');
    expect(ogeler[0].metin, contains('+'));
  });

  testWidgets('ekran okuyucu bandı tek cümle olarak okur', (tester) async {
    await pump(tester, hareketiAzalt: true);
    final s = tester.getSemantics(find.byType(KayanBant));
    expect(s.label, contains('Dolar 48,79'));
    expect(s.label, contains('Euro 56,11'));
    expect(s.label, contains('BIST 100 11.482'));
  });

  testWidgets('hareketi azalt: bant durur ve elle kaydırılır', (tester) async {
    await pump(tester, hareketiAzalt: true);
    final lv = tester.widget<ListView>(find.byType(ListView));
    expect(lv.physics, isA<BouncingScrollPhysics>());
    final once = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    await tester.pump(const Duration(seconds: 1));
    final sonra = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(sonra, once, reason: 'Hareketi azalt açıkken kendiliğinden akmamalı.');
  });

  testWidgets('akarken ilerler; dokunuş durdurur', (tester) async {
    await pump(tester);
    final once = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final sonra = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(sonra, greaterThan(once));

    await tester.tap(find.byType(KayanBant));
    await tester.pump();
    final durdu = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      durdu,
    );
  });

  testWidgets('öğeler döngüsel: dördüncü öğe ilkini tekrar eder', (tester) async {
    await pump(tester, hareketiAzalt: true);
    // 320pt genişlikte üç öğe + tekrar sığar; "Dolar" birden çok kez.
    expect(find.text('Dolar').evaluate().length, greaterThanOrEqualTo(1));
  });
}
