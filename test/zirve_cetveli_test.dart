import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/zirve_cetveli.dart';

/// Getiri cetveli — konum, çakışma ve dokunma.
///
/// 2. (−%3,30) ile 3. (−%3,32) aynı noktaya düşer; katsız çizimde biri
/// ötekini örtüyordu. Burada iki işaretin ayrı katlara çıktığı ve her
/// ikisine de dokunulabildiği ölçülür.
void main() {
  const isaretler = [
    ZirveIsaret(anahtar: '1', etiket: '1.', roi: 2.70, sira: 1),
    ZirveIsaret(anahtar: '2', etiket: '2.', roi: -3.30, sira: 2),
    ZirveIsaret(anahtar: '3', etiket: '3.', roi: -3.32, sira: 3),
    ZirveIsaret(anahtar: 'sen', etiket: 'Sen', roi: -6.36, sen: true),
  ];

  Future<List<String>> pump(WidgetTester tester, {String? secili}) async {
    tester.view.physicalSize = const Size(360 * 3, 240 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final secimler = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZirveCetveli(
              isaretler: isaretler,
              secili: secili,
              onSec: secimler.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return secimler;
  }

  Offset merkez(WidgetTester tester, String anahtar) =>
      tester.getCenter(find.byKey(ValueKey('zirve-isaret-$anahtar')));

  testWidgets('işaretler getiriye göre soldan sağa dizilir', (tester) async {
    await pump(tester);
    final sen = merkez(tester, 'sen');
    final ikinci = merkez(tester, '2');
    final birinci = merkez(tester, '1');
    expect(sen.dx, lessThan(ikinci.dx));
    expect(ikinci.dx, lessThan(birinci.dx));
  });

  testWidgets('çakışan 2. ve 3. ayrı katlarda', (tester) async {
    await pump(tester);
    final ikinci = merkez(tester, '2');
    final ucuncu = merkez(tester, '3');
    // Yatayda neredeyse aynı yer…
    expect((ikinci.dx - ucuncu.dx).abs(), lessThan(4));
    // …dikeyde bir kat fark: biri eksende, öteki üstte.
    expect((ikinci.dy - ucuncu.dy).abs(), greaterThan(20));
  });

  testWidgets('her işarete dokunulabilir, seçim anahtarı döner',
      (tester) async {
    final secimler = await pump(tester, secili: '1');
    for (final k in ['1', '2', '3', 'sen']) {
      await tester.tap(find.byKey(ValueKey('zirve-dokun-$k')));
      await tester.pump();
    }
    expect(secimler, ['1', '2', '3', 'sen']);
  });

  testWidgets('erişilebilirlik: her işaret bir düğme, getiri cümlesiyle',
      (tester) async {
    await pump(tester, secili: '1');
    expect(find.bySemanticsLabel('1. portföy, %2,7 kazandı'), findsOneWidget);
    expect(find.bySemanticsLabel('Sen, %6,4 kaybetti'), findsOneWidget);
  });

  testWidgets('sıfır çizgisi ve uç etiketleri var', (tester) async {
    await pump(tester);
    expect(find.text('0'), findsOneWidget);
    // Eksen uçları: en düşük −6,36'nın altı, en yüksek 2,70'in üstü.
    expect(find.textContaining('−%'), findsOneWidget);
    expect(find.textContaining('+%'), findsOneWidget);
  });

  testWidgets('havuzdaki kullanıcı: tek Sen işareti, sırasıyla', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 240 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ZirveCetveli(
            isaretler: const [
              ZirveIsaret(anahtar: '1', etiket: '1.', roi: 3.1, sira: 1),
              ZirveIsaret(
                  anahtar: '2', etiket: 'Sen', roi: 2.8, sira: 2, sen: true),
              ZirveIsaret(anahtar: '3', etiket: '3.', roi: -0.6, sira: 3),
            ],
            secili: '2',
            onSec: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Sen, 2. sırada, %2,8 kazandı'),
        findsOneWidget);
    expect(find.text('S'), findsNothing);
    expect(find.text('Sen'), findsOneWidget);
  });

  // Hareket denetimi (2026-09-29): seçim bir dokunuş yanıtı — halka yeni
  // işarette DOĞAR, cetvel boyunca 560 ms kaymaz (eski test "yolda" olmasını
  // istiyordu). Dönem değişince ise işaretiyle BİRLİKTE süzülür.
  Widget cetvel(List<ZirveIsaret> liste, String secili) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZirveCetveli(isaretler: liste, secili: secili, onSec: (_) {}),
          ),
        ),
      );
  Offset hale(WidgetTester t) =>
      t.getCenter(find.byKey(const ValueKey('zirve-imlec')));
  Offset nokta(WidgetTester t, String k) =>
      t.getCenter(find.byKey(ValueKey('zirve-dokun-$k')));

  testWidgets('seçim değişince halka yeni işarette doğar (kaymaz)',
      (tester) async {
    await pump(tester, secili: '1');
    expect((hale(tester) - nokta(tester, '1')).distance, lessThan(1));
    await tester.pumpWidget(cetvel(isaretler, 'sen'));
    await tester.pump(const Duration(milliseconds: 16));
    // İlk karede bile yeni işaretin üstünde — yolda değil.
    expect((hale(tester) - nokta(tester, 'sen')).distance, lessThan(1));
    await tester.pumpAndSettle();
    expect((hale(tester) - nokta(tester, 'sen')).distance, lessThan(1));
  });

  testWidgets('seçim 300 ms içinde oturur (dokunuş yanıtı)', (tester) async {
    await pump(tester, secili: '1');
    await tester.pumpWidget(cetvel(isaretler, 'sen'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isFalse,
        reason: "seçim hareketi 300 ms'yi aşıyor");
  });

  testWidgets('dönem değişince halka işaretle birlikte süzülür',
      (tester) async {
    await tester.pumpWidget(cetvel(isaretler, '1'));
    await tester.pumpAndSettle();
    final eski = nokta(tester, '1');
    final yeni = [
      for (final i in isaretler)
        i.anahtar == '1'
            ? const ZirveIsaret(anahtar: '1', etiket: '1.', roi: -1, sira: 1)
            : i,
    ];
    await tester.pumpWidget(cetvel(yeni, '1'));
    await tester.pump(const Duration(milliseconds: 150));
    // Yolda: işaret de halka da yer değiştiriyor ve BİRLİKTE.
    expect((nokta(tester, '1') - eski).distance, greaterThan(5));
    expect((hale(tester) - nokta(tester, '1')).distance, lessThan(1));
    await tester.pumpAndSettle();
    expect((hale(tester) - nokta(tester, '1')).distance, lessThan(1));
  });
}
