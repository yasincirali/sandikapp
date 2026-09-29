import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/zirve_ayna_kiyas.dart';

/// Ayna kıyas — sola sen, sağa o; fon fon; çubuklar akarak değişir.
void main() {
  const sen = {'altin': 71.7, 'fon': 28.3};
  const senFon = {'TTE': 28.3};
  const ikinci = {
    'altin': 55.7,
    'kripto': 17.9,
    'hisse': 12.9,
    'doviz': 7.6,
    'fon': 5.9,
  };
  const ikinciFon = {'AFT': 5.1, ZirveKiyas.fonDiger: 0.8};
  const birinci = {'fon': 100.0};
  const birinciFon = {'DLY': 100.0};

  Widget kur({
    Map<String, double> zirve = ikinci,
    Map<String, double> zirveFon = ikinciFon,
    String ad = '2. portföy',
    double zirveRoi = 2.8,
    bool hareketiAzalt = false,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ZirveAynaKiyas(
            senPay: sen,
            senFon: senFon,
            zirvePay: zirve,
            zirveFon: zirveFon,
            zirveAd: ad,
            senRoi: -3.3,
            zirveRoi: zirveRoi,
          ),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('başlıklar, tek cümle ve tür satırları', (tester) async {
    await pump(tester, kur());
    expect(find.text('SEN'), findsOneWidget);
    expect(find.text('2. PORTFÖY'), findsOneWidget);
    expect(
        find.text('En büyük fark fon: sende %28, onda %6. '
            'Getiride o 6,1 puan önde.'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Altın: sende %72, onda %56'),
        findsOneWidget);
    // Sende olmayan tür: sol taraf tire.
    expect(find.bySemanticsLabel('Kripto: sende —, onda %18'),
        findsOneWidget);
  });

  testWidgets('fon satırının altında fon fon, "Diğer" sonda', (tester) async {
    await pump(tester, kur());
    expect(find.bySemanticsLabel('TTE: sende %28, onda —'), findsOneWidget);
    expect(find.bySemanticsLabel('AFT: sende —, onda %5,1'), findsOneWidget);
    expect(find.bySemanticsLabel('Diğer: sende —, onda %0,8'),
        findsOneWidget);
    final tte = tester.getTopLeft(find.byKey(const ValueKey('ayna-fon-TTE')));
    final diger = tester.getTopLeft(
        find.byKey(const ValueKey('ayna-fon-${ZirveKiyas.fonDiger}')));
    expect(tte.dy, lessThan(diger.dy));
  });

  double sagCubuk(WidgetTester tester, String tur) {
    final satir = find.byKey(ValueKey('ayna-$tur'));
    final kutular = find.descendant(
        of: satir, matching: find.byType(AnimatedContainer));
    // İki çubuk: 0 sen (sol), 1 o (sağ).
    return tester.getSize(kutular.at(1)).width;
  }

  testWidgets('karşı taraf değişince çubuk AKARAK değişir', (tester) async {
    await pump(tester, kur());
    final once = sagCubuk(tester, 'fon'); // %5,9
    await tester.pumpWidget(kur(
        zirve: birinci, zirveFon: birinciFon, ad: '1. portföy', zirveRoi: 3.1));
    await tester.pump(const Duration(milliseconds: 120));
    final ara = sagCubuk(tester, 'fon');
    await tester.pumpAndSettle();
    final son = sagCubuk(tester, 'fon'); // %100
    expect(ara, greaterThan(once));
    expect(ara, lessThan(son));
    expect(find.text('1. PORTFÖY'), findsOneWidget);
  });

  testWidgets('hareketi azalt: tek karede son hâl', (tester) async {
    await pump(tester, kur(hareketiAzalt: true));
    await tester.pumpWidget(kur(
        zirve: birinci,
        zirveFon: birinciFon,
        ad: '1. portföy',
        zirveRoi: 3.1,
        hareketiAzalt: true));
    await tester.pump();
    final ilk = sagCubuk(tester, 'fon');
    await tester.pumpAndSettle();
    expect(sagCubuk(tester, 'fon'), ilk);
  });
}
