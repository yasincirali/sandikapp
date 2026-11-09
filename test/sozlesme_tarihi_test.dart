import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sozlesme_formu_ortak.dart';

/// Sözleşme formlarının tarih alanı (müşteri raporu 2026-11-10 #2): etiket
/// kutunun içinde tarihle yan yana iken 390 pt'de 1,0×'te bile
/// "Hakkı kulland…" diye kesiliyordu. Etiket artık üstte ve sarar.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const etiket = 'Hakkı kullandığın tarih';

  Future<void> ac(WidgetTester t, double olcek) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md2),
          child: Column(children: [
            SozlesmeTarihi(
              etiket: etiket,
              tarih: DateTime(2026, 5, 1),
              degisti: (_) {},
            ),
          ]),
        ),
      ),
    ));
    await t.pump();
  }

  for (final olcek in [1.0, 2.0]) {
    testWidgets('390 pt, $olcek×: etiket tam, kesilmez, taşmaz', (t) async {
      await ac(t, olcek);
      expect(t.takeException(), isNull);
      final etiketBul = find.text(etiket);
      expect(etiketBul, findsOneWidget);
      final metin = t.widget<Text>(etiketBul);
      expect(metin.overflow, isNot(TextOverflow.ellipsis));
      final paragraf = t.renderObject<RenderParagraph>(etiketBul);
      expect(paragraf.didExceedMaxLines, isFalse);
      // Etiket kutunun ÜSTÜNDE: tarih kutusunun içinde değil.
      final kutu = find.byType(SandikTappable);
      expect(find.descendant(of: kutu, matching: etiketBul), findsNothing);
      expect(
          t.getRect(etiketBul).bottom, lessThanOrEqualTo(t.getRect(kutu).top));
      expect(t.getSize(kutu).height, greaterThanOrEqualTo(SandikTouch.min));
    });
  }

  testWidgets('ekran okuyucu etiketi tarihle birlikte tek düğüm okur',
      (t) async {
    final handle = t.ensureSemantics();
    await ac(t, 1);
    expect(find.bySemanticsLabel('$etiket, 1 May 2026'), findsOneWidget);
    expect(find.bySemanticsLabel(etiket), findsNothing);
    handle.dispose();
  });
}
