import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/sandik_acilir.dart';

/// Gösterge editörü notları (2026-11-13): tek not açık, iki ve fazlası tek
/// katlı satır; dokununca liste açılır.
void main() {
  Widget uygulama(List<String> notlar) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SandikKatliNotlar(
              notlar: notlar,
              ozet: '${notlar.length} öğe gösterilmez · Ayrıntı'),
        ),
      );

  testWidgets('tek not eskisi gibi açık', (tester) async {
    await tester.pumpWidget(uygulama(['bgcolor gösterilmez.']));
    expect(find.text('bgcolor gösterilmez.'), findsOneWidget);
    expect(find.textContaining('Ayrıntı'), findsNothing);
  });

  testWidgets('iki ve fazlası katlı, dokununca açılır', (tester) async {
    await tester.pumpWidget(uygulama(['A notu', 'B notu', 'C notu']));
    expect(find.text('3 öğe gösterilmez · Ayrıntı'), findsOneWidget);
    expect(find.text('A notu'), findsNothing);
    expect(
        tester
            .getSize(find
                .ancestor(
                    of: find.text('3 öğe gösterilmez · Ayrıntı'),
                    matching: find.byType(ConstrainedBox))
                .first)
            .height,
        greaterThanOrEqualTo(44));
    await tester.tap(find.text('3 öğe gösterilmez · Ayrıntı'));
    await tester.pumpAndSettle();
    expect(find.text('A notu'), findsOneWidget);
    expect(find.text('C notu'), findsOneWidget);
    await tester.tap(find.text('3 öğe gösterilmez · Ayrıntı'));
    await tester.pumpAndSettle();
    expect(find.text('A notu'), findsNothing);
  });
}
