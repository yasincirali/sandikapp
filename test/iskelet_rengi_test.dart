import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// İskelet bloğu zeminden az ayrışan, YARI SAYDAM bir tondur.
///
/// Arayüz denetimi 2026-11-10: renk opak zemine karıştırıldığı için blok
/// koyu temada tam beyaz, açık temada neredeyse siyah çıkıyor, nabızla
/// birlikte yükleme ekranı yanıp sönüyordu ("shimmer" şikâyeti).
void main() {
  for (final (ad, palet) in [
    ('koyu', SandikPalette.dark),
    ('açık', SandikPalette.light),
  ]) {
    test('$ad tema: blok opak değil, ince çizgiden belirgin', () {
      final r = iskeletRengi(palet.hairline);
      expect(r.a, lessThan(0.25), reason: 'opak blok zemini deler');
      expect(r.a, greaterThan(palet.hairline.a),
          reason: 'ince çizgiden belirgin olmalı');
    });
  }

  testWidgets('hareketi azalt: blok aralığın ortasında sabit', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: SandikSkeleton(width: 80)),
      ),
    ));
    final o = t
        .widget<FadeTransition>(find.descendant(
            of: find.byType(SandikSkeleton),
            matching: find.byType(FadeTransition)))
        .opacity;
    final ilk = o.value;
    expect(ilk, closeTo(0.8, 0.001), reason: 'en parlak karede sabitlenmemeli');
    await t.pump(const Duration(seconds: 1));
    expect(o.value, ilk, reason: 'nabız atmamalı');
  });

  testWidgets('nabız 0,6 ile 1 arasında kalır', (t) async {
    await t.pumpWidget(
        const MaterialApp(home: Center(child: SandikSkeleton(width: 80))));
    final o = t
        .widget<FadeTransition>(find.descendant(
            of: find.byType(SandikSkeleton),
            matching: find.byType(FadeTransition)))
        .opacity;
    for (var i = 0; i < 30; i++) {
      await t.pump(SandikMotion.nabiz ~/ 30);
      expect(o.value, inInclusiveRange(0.6, 1.0));
    }
  });
}
