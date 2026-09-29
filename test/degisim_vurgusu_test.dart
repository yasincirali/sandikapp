import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/degisim_vurgusu.dart';

/// Ana sayfa toplamının değişim vurgusu (2026-09-29): fiyat turu değeri
/// değiştirince renk kısa süre yön rengine çıkar, sonra dinlenme rengine
/// döner. Yanlış yakma koşulları (açılış, görünüm değişimi, gizli tutar)
/// burada kilitli.
const _dinlenme = Color(0xFFC9A227);
const _palet = SandikPalette.dark;

Future<void> _kur(WidgetTester tester, double deger,
        {Object? kimlik = 'ben', bool etkin = true}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [_palet]),
      home: DegisimVurgusu(
        deger: deger,
        renk: _dinlenme,
        kimlik: kimlik,
        etkin: etkin,
        builder: (_, renk) => Text('x', style: TextStyle(color: renk)),
      ),
    ));

Color _renk(WidgetTester tester) =>
    tester.widget<Text>(find.text('x')).style!.color!;

void main() {
  testWidgets('artış: kazanç rengine çıkar, sonra dinlenme rengine döner',
      (tester) async {
    await _kur(tester, 1000);
    await _kur(tester, 1010);
    await tester.pump();
    expect(_renk(tester), _palet.gain);
    await tester.pumpAndSettle();
    expect(_renk(tester), _dinlenme);
  });

  testWidgets('düşüş: kayıp rengi', (tester) async {
    await _kur(tester, 1000);
    await _kur(tester, 990);
    await tester.pump();
    expect(_renk(tester), _palet.loss);
  });

  testWidgets('yakmaz: açılışta 0 → ilk değer', (tester) async {
    await _kur(tester, 0);
    await _kur(tester, 1000);
    await tester.pump();
    expect(_renk(tester), _dinlenme);
  });

  testWidgets('yakmaz: görünüm (kimlik) değişince', (tester) async {
    await _kur(tester, 1000, kimlik: 'ben');
    await _kur(tester, 5000, kimlik: 'ortak');
    await tester.pump();
    expect(_renk(tester), _dinlenme);
  });

  testWidgets('yakmaz: tutar gizliyken', (tester) async {
    await _kur(tester, 1000, etkin: false);
    await _kur(tester, 1010, etkin: false);
    await tester.pump();
    expect(_renk(tester), _dinlenme);
  });

  testWidgets('yakmaz: kuruştan küçük fark', (tester) async {
    await _kur(tester, 1000);
    await _kur(tester, 1000.001);
    await tester.pump();
    expect(_renk(tester), _dinlenme);
  });
}
