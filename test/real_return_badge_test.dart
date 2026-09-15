import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/real_return_strip.dart';

/// Reel getiri rozetinin yerleşimi.
///
/// ## Neden bu testler var (2026-09-15)
/// Rozet tek akan cümleydi ("Son bir yılda enflasyonun **5,89 puan**
/// önündesin") ve dar ekranda rakam satır sonunda kalıp "puan önündesin"
/// alt satıra düşüyordu — rozetin tek önemli bilgisi ikiye bölünüyordu.
/// Ayrıca doğrulama sayıları aynı `Row`'un sağ ucundaydı ve sol taraf iki
/// satıra çıkınca dikeyde kayıyordu.
///
/// Buradaki testler rakamın kendi tipografik parçası olarak KALDIĞINI ve
/// hiçbir genişlikte taşma olmadığını sabitler.

Future<void> _pump(
  WidgetTester tester, {
  required double nominal,
  required double inflation,
  double width = 390,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [SandikPalette.dark],
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RealReturnBadge(nominal: nominal, inflation: inflation),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('yerleşim', () {
    // Ekran görüntüsündeki gerçek değerler.
    for (final w in <double>[320, 360, 390, 430]) {
      testWidgets('${w.toInt()}pt — taşma yok', (tester) async {
        await _pump(tester, nominal: 37.39, inflation: 31.51, width: w);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1.6× metin ölçeğinde taşma yok', (tester) async {
      await _pump(
        tester,
        nominal: 37.39,
        inflation: 31.51,
        width: 320,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rakam TEK parça — cümleye gömülü değil', (tester) async {
      await _pump(tester, nominal: 37.39, inflation: 31.51);

      // Puan farkı kendi `Text`'i: 37,39 − 31,51 = 5,88.
      // Cümlenin içinde olsaydı bu finder tutmazdı.
      expect(find.text('5,88'), findsOneWidget);
      expect(find.text('puan'), findsOneWidget);
    });

    testWidgets('rakam dar ekranda da bölünmez', (tester) async {
      // Asıl regresyon: 320pt'de rakamın hâlâ tek parça olması.
      await _pump(tester, nominal: 37.39, inflation: 31.51, width: 320);
      expect(find.text('5,88'), findsOneWidget);
    });

    testWidgets('doğrulama satırı kendi satırında, rakamın ALTINDA',
        (tester) async {
      await _pump(tester, nominal: 37.39, inflation: 31.51);

      final rakam = tester.getRect(find.text('5,88'));
      final dogrulama = tester.getRect(find.textContaining('TÜFE'));

      // Eskiden aynı Row'un sağ ucundaydı (yatay komşu). Artık altında.
      expect(dogrulama.top, greaterThan(rakam.bottom - 1),
          reason: 'doğrulama satırı rakamın altına inmeli');
    });
  });

  group('yön', () {
    testWidgets('önde — yukarı ok, gain rengi', (tester) async {
      await _pump(tester, nominal: 37.39, inflation: 31.51);
      expect(find.text('▲'), findsOneWidget);
      expect(find.text('▼'), findsNothing);
      expect(find.text('enflasyonun önündesin'), findsOneWidget);
    });

    testWidgets('geride — aşağı ok, mutlak değer yazılır', (tester) async {
      await _pump(tester, nominal: 12.00, inflation: 31.51);
      expect(find.text('▼'), findsOneWidget);
      expect(find.text('▲'), findsNothing);
      expect(find.text('enflasyonun gerisindesin'), findsOneWidget);
      // Eksi işareti rakamda DEĞİL — yönü ok anlatıyor.
      expect(find.text('19,51'), findsOneWidget);
    });

    testWidgets('tam başabaş önde sayılır', (tester) async {
      await _pump(tester, nominal: 31.51, inflation: 31.51);
      expect(find.text('▲'), findsOneWidget);
      expect(find.text('0,00'), findsOneWidget);
    });
  });

  group('doğrulama sayıları', () {
    // Yuvarlama YOK — iki ondalık. `digits: 0` olduğunda TÜFE %31,51
    // ekranda "%32" görünüyor ve TÜİK rakamıyla karşılaştırma tutmuyordu;
    // daha kötüsü yuvarlama pencere arızasını gizliyordu (2026-09-14).
    testWidgets('iki ondalık korunur — yuvarlanmaz', (tester) async {
      await _pump(tester, nominal: 37.39, inflation: 31.51);

      final metin = tester
          .widget<Text>(find.textContaining('TÜFE'))
          .data!;
      expect(metin, contains('%37,39'));
      expect(metin, contains('%31,51'));
      // Yuvarlanmış hâlleri GÖRÜNMEMELİ.
      expect(metin, isNot(contains('%37 ')));
      expect(metin, isNot(contains('%32')));
    });

    testWidgets('hangi sayının ne olduğu etiketli', (tester) async {
      await _pump(tester, nominal: 37.39, inflation: 31.51);
      // Çıplak yüzde ikilisi hangisinin ne olduğunu söylemiyordu.
      final metin = tester
          .widget<Text>(find.textContaining('TÜFE'))
          .data!;
      expect(metin, contains('Senin'));
      expect(metin, contains('TÜFE'));
      expect(metin, contains('son bir yıl'));
    });
  });

  group('erişilebilirlik', () {
    testWidgets('rozet TEK cümle olarak okunur', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, nominal: 37.39, inflation: 31.51);

      // Parçalara bölünmüş hâli ekran okuyucuda anlamsız sayı dizisi olurdu.
      expect(
        find.bySemanticsLabel(RegExp(r'enflasyonu yüzde 5,88 puan geçti')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
