import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/destek_direnc.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';

/// AI yorum kartının destek/direnç satırı ("Seviye bilgisi", 2026-10-17).
/// Kilitlenenler: sıra direnç (üstte) → içinde → destek (altta), fiyatın
/// grafikteki yönüyle aynı; ekran okuyucu tek cümle okur; dar ekranda ve
/// büyük yazıda taşma yok.
Future<void> _pump(WidgetTester t, DestekDirenc d,
    {double genislik = 390, double olcek = 1}) async {
  t.view.physicalSize = Size(genislik * 3, 800 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(
        brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: SeviyeSatiri(seviyeler: d, fiyatYaz: (v) => 'F$v'),
        ),
      ),
    ),
  ));
}

const _iki = DestekDirenc(
  destek: FiyatBolgesi(alt: 41.2, ust: 42, temas: 3),
  direnc: FiyatBolgesi(alt: 46.5, ust: 47.1, temas: 2),
);

void main() {
  testWidgets('direnç üstte, destek altta; ekran okuyucu tek cümle', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, _iki);
    final direnc = t.getTopLeft(find.bySemanticsLabel(RegExp('^Direnç')));
    final destek = t.getTopLeft(find.bySemanticsLabel(RegExp('^Destek')));
    expect(direnc.dy, lessThan(destek.dy));
    expect(find.bySemanticsLabel('Destek: F41.2 – F42.0, dönemde 3 kez dönülmüş'),
        findsOneWidget);
    h.dispose();
  });

  testWidgets('tek noktalı bölge aralık değil tek fiyat yazar', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, const DestekDirenc(
        icinde: FiyatBolgesi(alt: 10, ust: 10, temas: 2)));
    expect(find.bySemanticsLabel(RegExp(r'^Fiyatın bulunduğu bölge: F10\.0,')),
        findsOneWidget);
    h.dispose();
  });

  for (final (w, o) in const [(320.0, 2.0), (430.0, 3.1)]) {
    testWidgets('${w.toInt()}pt, $o× yazı: taşma yok', (t) async {
      await _pump(t, _iki, genislik: w, olcek: o);
      expect(t.takeException(), isNull);
    });
  }
}
