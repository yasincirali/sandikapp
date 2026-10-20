import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/zirve_varlik_siralamasi.dart';

/// Zirve varlık sıralaması (okunaklılık turu 2026-10-20): tek ortak ölçek,
/// tek sayı biçimi, kilitli satır, gruplu alt sayfa, büyük yazı.
void main() {
  const fon = {'AFT': 15.0, 'TTE': 8.0};
  const varlik = {
    'hisse': {
      'THYAO.IS': 21.0,
      'ASELS.IS': 14.0,
      'BIMAS.IS': 11.0,
      'DIGER': 6.0
    },
    'kripto': {'BTCUSDT': 12.0, 'ETHUSDT': 6.0},
    'altin': {'ALTIN_CEYREK': 7.0},
  };
  const pay = {'hisse': 52.0, 'fon': 23.0, 'kripto': 18.0, 'altin': 7.0};

  Widget kur(Widget w, {double olcek = 1.0}) => MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(SandikSpace.md),
            child: w,
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, Widget w, {double olcek = 1.0}) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(kur(w, olcek: olcek));
    await tester.pumpAndSettle();
  }

  Future<String?> adYok(String _) async => null;

  List<double> oranlar(WidgetTester tester) => [
        for (final e in tester.widgetList<AnimatedFractionallySizedBox>(
            find.byType(AnimatedFractionallySizedBox)))
          e.widthFactor!,
      ];

  testWidgets('sıralı: ilk 5, türler karışık, büyükten küçüğe', (tester) async {
    await pump(
        tester,
        ZirveVarlikSiralamasi(
            fonDetay: fon, varlikDetay: varlik, enFazla: 5, adBul: adYok));
    // 21 THYAO, 15 AFT, 14 ASELS, 12 BTC, 11 BIMAS — DIGER sıralamaya girmez.
    final ys = [
      for (final ad in ['THYAO', 'AFT', 'ASELS', 'BTC', 'BIMAS'])
        tester.getTopLeft(find.text(ad)).dy,
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }
    expect(find.text('TTE'), findsNothing);
    expect(find.text(ZirveKiyas.varlikAdi('ALTIN_CEYREK')), findsNothing);
    // Renk tek başına anlam taşımaz: tür adı ikinci satırda.
    expect(find.text('Hisse'), findsWidgets);
  });

  testWidgets('tek ortak ölçek: çubuk en büyük kaleme göre', (tester) async {
    await pump(
        tester,
        ZirveVarlikSiralamasi(fonDetay: const {}, varlikDetay: const {
          'hisse': {'THYAO.IS': 21.0},
          'altin': {'ALTIN_CEYREK': 7.0},
        }, adBul: adYok));
    final o = oranlar(tester);
    expect(o, hasLength(2));
    expect(o[0], 1.0);
    // %7 altın, %21 THYAO'nun üçte biri — tür içinde tam dolu DEĞİL.
    expect(o[1], closeTo(1 / 3, 0.001));
  });

  test('tek sayı biçimi: sondaki sıfır yok, en fazla bir ondalık', () {
    expect(ZirveKiyas.pay(6.0), '%6');
    expect(ZirveKiyas.pay(21.0), '%21');
    expect(ZirveKiyas.pay(12.5), '%12,5');
    expect(ZirveKiyas.pay(0.84), '%0,8');
    expect(ZirveKiyas.pay(71.66), '%71,7');
  });

  testWidgets('satırda yazılan yüzde ZirveKiyas.pay biçiminde', (tester) async {
    await pump(
        tester,
        ZirveVarlikSiralamasi(fonDetay: const {}, varlikDetay: const {
          'kripto': {'ETHUSDT': 6.0},
        }, adBul: adYok));
    expect(find.text('%6'), findsOneWidget);
    expect(find.text('%6,0'), findsNothing);
  });

  testWidgets('kilitli satır: •••• + oran görünür, dokununca paywall',
      (tester) async {
    var acildi = 0;
    await pump(
        tester,
        ZirveVarlikSiralamasi(
          fonDetay: const {},
          varlikDetay: const {
            'hisse': {'THYAO.IS': 21.0, '?2': 14.0},
          },
          onKilitli: () => acildi++,
          adBul: adYok,
        ));
    expect(find.text(ZirveKiyas.kilitliYer), findsOneWidget);
    expect(find.text('%14'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    final kilit =
        find.bySemanticsLabel("Kilitli varlık %14. Premium'da görünür.");
    expect(kilit, findsOneWidget);
    await tester.tap(find.text(ZirveKiyas.kilitliYer));
    expect(acildi, 1);
    // Dokunma alanı ≥ 44.
    final inkwell = find.ancestor(
        of: find.text(ZirveKiyas.kilitliYer), matching: find.byType(InkWell));
    expect(
        tester.getSize(inkwell).height, greaterThanOrEqualTo(SandikTouch.min));
  });

  testWidgets('gruplu: tür başlığı + toplam, "Diğer kalemler" ve ortak ölçek',
      (tester) async {
    await pump(
        tester,
        ZirveVarlikSiralamasi(
          fonDetay: fon,
          varlikDetay: varlik,
          pay: pay,
          gruplu: true,
          adBul: adYok,
        ));
    expect(find.bySemanticsLabel('Hisse toplam %52'), findsOneWidget);
    expect(find.bySemanticsLabel('Altın toplam %7'), findsOneWidget);
    // Hisse: 52 − (21+14+11) = 6 → "Diğer kalemler".
    expect(find.bySemanticsLabel('Hisse, diğer kalemler %6'), findsOneWidget);
    // Başlıklar paya göre sıralı: Hisse, Fon, Kripto, Altın.
    final hisse = tester.getTopLeft(find.text('Hisse')).dy;
    final altin = tester.getTopLeft(find.text('Altın')).dy;
    expect(hisse, lessThan(altin));
    // Gruplu biçimde de ölçek portföyün en büyük kalemi (THYAO %21).
    expect(oranlar(tester).reduce((a, b) => a > b ? a : b), 1.0);
    expect(oranlar(tester), contains(closeTo(7 / 21, 0.001)));
  });

  for (final olcek in [2.0, 3.1]) {
    testWidgets('yazı ×$olcek: taşma yok', (tester) async {
      await pump(
        tester,
        Column(children: [
          ZirveVarlikSiralamasi(
              fonDetay: fon, varlikDetay: varlik, enFazla: 5, adBul: adYok),
          ZirveVarlikSiralamasi(
              fonDetay: fon,
              varlikDetay: varlik,
              pay: pay,
              gruplu: true,
              adBul: adYok),
        ]),
        olcek: olcek,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
