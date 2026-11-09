import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_paylas_dugmesi.dart';

import 'helpers/kaynak.dart';

/// Paylaş düğmesinin YERİ (yasin 2026-10-31: "garip bir yerde duruyor;
/// dikkat çekmeyecek, simetri ve ahengi bozmayacak şekilde, tüm
/// uygulamada"). Kural `SandikPaylasDugmesi` belgesinde: başlık satırının
/// son öğesi, satırın dikey ortasında, simgenin sağ kenarı içeriğin sağ
/// kenarında; kartın üstüne bindirme yok.
void main() {
  Future<void> kur(WidgetTester tester, {double olcek = 1}) async {
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(320, 600),
            textScaler: TextScaler.linear(olcek)),
        child: Scaffold(
          body: Builder(
            builder: (context) => Container(
              key: const ValueKey('kart'),
              padding: const EdgeInsets.all(SandikSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SandikPaylasDugmesi.satirSonunda(
                    satir: Text('BUGÜN · CUMA 9 EKİM',
                        key: const ValueKey('baslik'),
                        style: context.t.labelMedium),
                    dugme: SandikPaylasDugmesi(
                        onPressed: () {}, tooltip: 'Paylaş'),
                  ),
                  const SizedBox(
                      key: ValueKey('icerik'), height: 40, width: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('simge başlıkla aynı ortada, sağ kenarı içeriğin kenarında',
      (tester) async {
    await kur(tester);
    final simge = tester.getRect(find.byIcon(Icons.adaptive.share));
    final baslik = tester.getRect(find.byKey(const ValueKey('baslik')));
    final kart = tester.getRect(find.byKey(const ValueKey('kart')));
    expect(simge.center.dy, moreOrLessEquals(baslik.center.dy, epsilon: 0.5));
    expect(simge.right,
        moreOrLessEquals(kart.right - SandikSpace.md, epsilon: 0.5));
    // Dokunma alanı 44 pt (Material'ın 48'i değil: satır payı bununla
    // hesaplanıyor).
    expect(tester.getSize(find.byTooltip('Paylaş')), const Size(44, 44));
  });

  testWidgets('3.1× yazı: taşma yok, simge yine satırın ortasında',
      (tester) async {
    await kur(tester, olcek: 3.1);
    expect(tester.takeException(), isNull);
    final simge = tester.getRect(find.byIcon(Icons.adaptive.share));
    final baslik = tester.getRect(find.byKey(const ValueKey('baslik')));
    expect(simge.center.dy, moreOrLessEquals(baslik.center.dy, epsilon: 0.5));
  });

  testWidgets('satır payı: 44 pt kutunun kısa satırı uzattığı kadar; büyük '
      'yazıda sıfır', (tester) async {
    late double kucuk, buyuk;
    await tester.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      home: Builder(builder: (context) {
        kucuk = SandikPaylasDugmesi.satirPayi(context, context.t.labelMedium);
        return MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(4)),
          child: Builder(builder: (c) {
            buyuk = SandikPaylasDugmesi.satirPayi(c, c.t.labelMedium);
            return const SizedBox();
          }),
        );
      }),
    ));
    expect(kucuk, greaterThan(10));
    expect(kucuk, lessThan(SandikTouch.min / 2));
    expect(buyuk, 0);
  });

  test('bindirme yok: düğme kartın köşesine Stack ile konmaz', () {
    for (final yol in [
      'lib/widgets/bugun_karti.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/widgets/sandik_paylas_dugmesi.dart',
    ]) {
      final k = ekranKaynagiSync(yol);
      expect(k.contains('SandikPaylasDugmesi.kartKosesi'), isFalse,
          reason: yol);
      expect(k.contains('Widget kartKosesi('), isFalse, reason: yol);
    }
  });
}
