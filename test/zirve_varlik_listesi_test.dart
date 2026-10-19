import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/zirve_varlik_listesi.dart';

/// Zirve portföyünün fon dışı türlerdeki kırılımı (0158).
///
/// Açık satır: sembolün okunur adı + portföy payı. Kilitli satır (`?n`,
/// sunucu maskesi): oran açık, ad yerine "••••" ve kilit; dokununca
/// paywall; ekran okuyucu "Premium'da görünür" duyar (renk tek başına
/// anlam taşımaz). Dokunma alanı ≥44 pt.
void main() {
  Future<int> pump(WidgetTester tester, Map<String, double> detay) async {
    var acildi = 0;
    tester.view.physicalSize = const Size(390 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZirveVarlikListesi(
              tur: 'hisse',
              detay: detay,
              onKilitli: () => acildi++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return acildi;
  }

  testWidgets('açık satırlar: okunur ad, pay, büyükten küçüğe', (tester) async {
    await pump(tester, const {'ASELS.IS': 8.0, 'THYAO.IS': 30.0});
    expect(find.text('THYAO'), findsOneWidget);
    expect(find.text('ASELS'), findsOneWidget);
    expect(find.text('%30'), findsOneWidget);
    expect(find.text('%8,0'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(tester.getTopLeft(find.text('THYAO')).dy,
        lessThan(tester.getTopLeft(find.text('ASELS')).dy));
  });

  testWidgets('kilitli satır: "••••", kilit, oran açık; dokununca paywall',
      (tester) async {
    final handle = tester.ensureSemantics();
    var acildi = 0;
    tester.view.physicalSize = const Size(390 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZirveVarlikListesi(
            tur: 'hisse',
            detay: const {'THYAO.IS': 30.0, '?2': 12.0},
            onKilitli: () => acildi++,
          ),
        ),
      ),
    );
    expect(find.text(ZirveKiyas.kilitliYer), findsOneWidget);
    expect(find.text("Premium'da görünür"), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('%12'), findsOneWidget);
    expect(find.bySemanticsLabel("Kilitli varlık %12. Premium'da görünür."),
        findsOneWidget);
    final kutu = tester.getSize(find.byType(InkWell));
    expect(kutu.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(InkWell));
    expect(acildi, 1);
    handle.dispose();
  });

  testWidgets('DIGER en sonda açıklamasıyla; boş kırılım çizilmez',
      (tester) async {
    await pump(tester, const {ZirveKiyas.fonDiger: 3.0, 'BTCUSDT': 9.0});
    expect(find.text('DİĞER'), findsOneWidget);
    expect(find.textContaining('her biri %1 altı'), findsOneWidget);
    await pump(tester, const {});
    expect(find.byType(Text), findsNothing);
  });
}
