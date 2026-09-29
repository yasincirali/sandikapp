import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/zirve_dagilim_seridi.dart';

/// Dağılım şeridi — sabit tür sırası, dilimler akarak değişir.
///
/// Sabit sıra (2026-09-29): portföyler arasında geçerken her tür aynı yerde
/// kalır, yalnız genişliği akar; göz rengi kaybetmez.
void main() {
  Widget kur(Map<String, double> pay, {bool hareketiAzalt = false}) =>
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: ZirveDagilimSeridi(pay: pay)),
          ),
        ),
      );

  double w(WidgetTester t, String tur) =>
      t.getSize(find.byKey(ValueKey('serit-$tur'))).width;
  double x(WidgetTester t, String tur) =>
      t.getTopLeft(find.byKey(ValueKey('serit-$tur'))).dx;

  testWidgets('dilimler sabit sırada, payla orantılı', (tester) async {
    await tester.pumpWidget(kur(const {'altin': 75, 'fon': 25}));
    await tester.pumpAndSettle();
    expect(w(tester, 'altin') / w(tester, 'fon'), closeTo(3, 0.05));
    // AssetType sırası: fon, altından önce gelir — büyüklükten bağımsız.
    expect(x(tester, 'fon'), lessThan(x(tester, 'altin')));
    expect(w(tester, 'kripto'), 0);
  });

  testWidgets('pay değişince dilim akarak büyür', (tester) async {
    await tester.pumpWidget(kur(const {'altin': 75, 'fon': 25}));
    await tester.pumpAndSettle();
    final once = w(tester, 'fon');
    await tester.pumpWidget(kur(const {'fon': 100}));
    await tester.pump(const Duration(milliseconds: 120));
    final ara = w(tester, 'fon');
    await tester.pumpAndSettle();
    final son = w(tester, 'fon');
    expect(ara, greaterThan(once));
    expect(ara, lessThan(son));
    expect(w(tester, 'altin'), 0);
  });

  testWidgets('hareketi azalt: anında', (tester) async {
    await tester.pumpWidget(kur(const {'altin': 75, 'fon': 25}, hareketiAzalt: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(kur(const {'fon': 100}, hareketiAzalt: true));
    await tester.pump();
    final ilk = w(tester, 'fon');
    await tester.pumpAndSettle();
    expect(w(tester, 'fon'), ilk);
  });
}
