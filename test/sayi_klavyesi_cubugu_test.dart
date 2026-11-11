import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sayi_klavyesi_cubugu.dart';

/// iOS sayı klavyesi "Sonraki / Bitti" çubuğu (2026-11-11): yalnız iOS'ta,
/// yalnız sayı klavyesi açıkken; Android ve metin klavyesi değişmez.
void main() {
  const sayi1 = ValueKey('sayi-1');
  const sayi2 = ValueKey('sayi-2');
  const metin = ValueKey('metin');

  Widget uygulama({double yaziOlcegi = 1}) => MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(yaziOlcegi)),
          child: SayiKlavyesiKatmani(child: child!),
        ),
        home: const Scaffold(
          body: Column(
            children: [
              TextField(
                  key: sayi1,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true)),
              TextField(key: sayi2, keyboardType: TextInputType.number),
              TextField(key: metin, keyboardType: TextInputType.text),
            ],
          ),
        ),
      );

  Future<void> kur(WidgetTester t, TargetPlatform p,
      {double yaziOlcegi = 1}) async {
    debugDefaultTargetPlatformOverride = p;
    // Test görünümünde klavye yok; açık klavyeyi alttaki boşlukla taklit et.
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(uygulama(yaziOlcegi: yaziOlcegi));
  }


  FocusNode? odak() => FocusManager.instance.primaryFocus;
  bool odakta(WidgetTester t, Key k) =>
      t.widget<EditableText>(find.descendant(
              of: find.byKey(k), matching: find.byType(EditableText)))
          .focusNode
          .hasPrimaryFocus;

  testWidgets('iOS: sayı alanında çubuk görünür, Sonraki ve Bitti çalışır',
      (t) async {
    await kur(t, TargetPlatform.iOS);
    expect(find.byType(SayiKlavyesiCubugu), findsNothing);

    await t.tap(find.byKey(sayi1));
    await t.pump();
    expect(find.byType(SayiKlavyesiCubugu), findsOneWidget);
    expect(find.text('Sonraki'), findsOneWidget);
    expect(find.text('Bitti'), findsOneWidget);
    // Düğmeler 44 pt.
    expect(t.getSize(find.widgetWithText(TextButton, 'Bitti')).height,
        greaterThanOrEqualTo(SandikTouch.min));

    await t.tap(find.text('Sonraki'));
    await t.pump();
    expect(odakta(t, sayi2), isTrue, reason: 'Sonraki ikinci alana geçer');
    // Sonraki alan metin alanı; Sonraki yine görünür (düzenlenebilir alan).
    expect(find.text('Sonraki'), findsOneWidget);

    await t.tap(find.text('Bitti'));
    await t.pump();
    expect(odak() is FocusScopeNode || odak() == null, isTrue,
        reason: 'Bitti odağı bırakır');
    expect(find.byType(SayiKlavyesiCubugu), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: metin alanında çubuk yok', (t) async {
    await kur(t, TargetPlatform.iOS);
    await t.tap(find.byKey(metin));
    await t.pump();
    expect(odakta(t, metin), isTrue);
    expect(find.byType(SayiKlavyesiCubugu), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: klavye kapalıyken (donanım klavyesi) çubuk yok',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await t.pumpWidget(uygulama());
    await t.tap(find.byKey(sayi1));
    await t.pump();
    expect(find.byType(SayiKlavyesiCubugu), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: sayı alanında çubuk yok', (t) async {
    await kur(t, TargetPlatform.android);
    await t.tap(find.byKey(sayi1));
    await t.pump();
    expect(odakta(t, sayi1), isTrue);
    expect(find.byType(SayiKlavyesiCubugu), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: yazı ×2 çubuğu taşırmaz, içerik çubuk kadar kaçınır',
      (t) async {
    await kur(t, TargetPlatform.iOS, yaziOlcegi: 2);
    await t.tap(find.byKey(sayi1));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    final cubuk = t.getSize(find.byType(SayiKlavyesiCubugu)).height;
    expect(cubuk, greaterThan(SandikTouch.min), reason: '×2 yazıda büyür');
    final ic = MediaQuery.of(t.element(find.byType(Scaffold))).viewInsets;
    expect(ic.bottom, closeTo(900 / t.view.devicePixelRatio + cubuk, 0.01));
    debugDefaultTargetPlatformOverride = null;
  });
}
