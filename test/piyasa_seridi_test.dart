import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';

/// Kayan bant — erişilebilirlik ve döngü kuralları.
///
/// Bant dört sabit değer taşır; ekran okuyucu bunu TEK cümle okumalı,
/// "hareketi azalt" açıkken akış olmamalı, dokunuş durdurmalı.
///
/// 2026-09-21: bant `ListView` + `jumpTo`'dan boyama-tabanlı çizime geçti
/// (`_RenderBant`); testler artık scroll konumunu değil `KayanBantState`'in
/// kayma değerini okur.
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

  KayanBantState bant(WidgetTester tester) =>
      tester.state<KayanBantState>(find.byType(KayanBant));

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
    final b = bant(tester);
    expect(b.akiyor, isFalse);
    final once = b.kaydirma;
    await tester.pump(const Duration(seconds: 1));
    expect(b.kaydirma, once,
        reason: 'Hareketi azalt açıkken kendiliğinden akmamalı.');

    // Parmak sola → içerik ileri (kayma artar).
    await tester.drag(find.byType(KayanBant), const Offset(-60, 0));
    await tester.pump();
    expect(b.kaydirma, greaterThan(once), reason: 'Dururken elle kaydırılır.');
  });

  testWidgets('akarken ilerler; dokunuş durdurur, ikinci dokunuş sürdürür',
      (tester) async {
    await pump(tester);
    final b = bant(tester);
    expect(b.akiyor, isTrue);
    final once = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final sonra = b.kaydirma;
    expect(sonra, greaterThan(once));

    await tester.tap(find.byType(KayanBant));
    await tester.pump();
    expect(b.akiyor, isFalse);
    final durdu = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(b.kaydirma, durdu);

    // Sürdürünce kaldığı yerden devam eder — sıçrama yok.
    await tester.tap(find.byType(KayanBant));
    await tester.pump();
    expect(b.akiyor, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(b.kaydirma, greaterThan(durdu));
    expect(b.kaydirma - durdu, lessThan(PiyasaSeridi.hiz * 0.5),
        reason: '200 ms\'de en fazla hız × 0,2 sn kadar ilerler; sıçramaz.');
  });

  testWidgets('akarken elle kaydırma yok (ticker ile çatışır)', (tester) async {
    await pump(tester);
    final b = bant(tester);
    final once = b.kaydirma;
    await tester.drag(find.byType(KayanBant), const Offset(-200, 0));
    await tester.pump();
    // Sürükleme alınmadı: kayma yalnızca geçen süre kadar ilerledi.
    expect(b.kaydirma - once, lessThan(60),
        reason: 'Akarken parmak bandı 200 pt ötelememeli.');
  });

  testWidgets('kayma yalnızca boyar: sürüklerken widget ağacı yeniden kurulmaz',
      (tester) async {
    await pump(tester, hareketiAzalt: true);
    final onceki = tester.widget(find.text('Dolar'));
    await tester.drag(find.byType(KayanBant), const Offset(-60, 0));
    await tester.pump();
    expect(identical(tester.widget(find.text('Dolar')), onceki), isTrue,
        reason: 'Kayma değişince metin widget\'ı yeniden kurulmamalı.');
  });
}
