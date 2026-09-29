import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/zirve_fon_listesi.dart';

/// Zirve portföyünün fon kırılımı — kod, resmi ad, pay, "sende" kıyası.
///
/// Ad kullanıcının kaydından DEĞİL, TEFAS kataloğundan gelir; burada
/// katalog sahte bir bulucuyla verilir. Katalogda olmayan kod yalnız kodla
/// yazılır, uydurma ad yok.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Map<String, double> fon,
    Map<String, double>? sen,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZirveFonListesi(
              fonDetay: fon,
              senFonDetay: sen,
              adBul: (kod) async => const {
                'AFT': 'Ak Portföy Yeni Teknolojiler Yabancı Hisse Senedi Fonu',
                'TTE': 'İş Portföy BIST Teknoloji Ağırlık Sınırlamalı Endeks Hisse Senedi Fonu',
              }[kod],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('kod, resmi ad ve portföy payı; büyükten küçüğe', (tester) async {
    await pump(tester, fon: const {'TTE': 12.5, 'AFT': 25.0});
    expect(find.text('AFT'), findsOneWidget);
    expect(find.text('TTE'), findsOneWidget);
    expect(find.textContaining('Yeni Teknolojiler'), findsOneWidget);
    expect(find.text('%25'), findsOneWidget);
    expect(find.text('%13'), findsOneWidget);
    expect(tester.getTopLeft(find.text('AFT')).dy,
        lessThan(tester.getTopLeft(find.text('TTE')).dy));
  });

  testWidgets('"diğer" en sonda, açıklamasıyla; katalogda olmayan kodun adı boş',
      (tester) async {
    await pump(tester,
        fon: const {'XYZ': 5.0, ZirveKiyas.fonDiger: 1.2, 'AFT': 20.0});
    expect(find.text('DİĞER'), findsOneWidget);
    expect(find.textContaining('her biri %1 altı'), findsOneWidget);
    expect(find.text('XYZ'), findsOneWidget);
    expect(tester.getTopLeft(find.text('DİĞER')).dy,
        greaterThan(tester.getTopLeft(find.text('XYZ')).dy));
  });

  testWidgets('kıyas: sende olan ve olmayan fon', (tester) async {
    await pump(tester,
        fon: const {'AFT': 20.0, 'TTE': 8.0}, sen: const {'AFT': 3.5});
    expect(find.text('sende %3,5'), findsOneWidget);
    expect(find.text('sende yok'), findsOneWidget);
  });

  testWidgets('boş kırılım hiçbir şey çizmez', (tester) async {
    await pump(tester, fon: const {});
    expect(find.byType(Text), findsNothing);
  });
}
