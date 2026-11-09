import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// `SandikTappable` düz yolu (`soluk: false`, uygulamadaki yüzeylerin çoğu).
///
/// Arayüz denetimi 2026-11-10: kaydırılan listede hızlı dokunuşta kart hiç
/// kıpırdamıyordu (`onTapDown` ile `onTapUp` aynı karede geliyor, `_down`
/// açılıp kapanıyordu) ve "hareketi azalt" açıkken hiçbir geri bildirim
/// yoktu. Solma yolunun eşi: `sandik_tappable_soluk_test`.
void main() {
  const hedef = Key('hedef');

  Widget kur({
    bool azalt = false,
    bool listede = false,
    VoidCallback? onTap,
    ValueChanged<int>? build,
  }) {
    var sayac = 0;
    final Widget dugme = SandikTappable(
      haptic: SandikHaptic.none,
      onTap: onTap ?? () {},
      child: Builder(builder: (_) {
        build?.call(++sayac);
        return const SizedBox(width: 120, height: 48, key: hedef);
      }),
    );
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: azalt),
        child: listede
            ? ListView(children: [dugme, const SizedBox(height: 2000)])
            : Center(child: dugme),
      ),
    );
  }

  double olcek(WidgetTester t) {
    return t
        .widget<ScaleTransition>(find
            .descendant(
                of: find.ancestor(
                    of: find.byKey(hedef),
                    matching: find.byType(AnimatedScale)),
                matching: find.byType(ScaleTransition))
            .first)
        .scale
        .value;
  }

  double saydamlik(WidgetTester t) => t
      .renderObject<RenderAnimatedOpacity>(find
          .descendant(
              of: find.ancestor(
                  of: find.byKey(hedef),
                  matching: find.byType(AnimatedOpacity)),
              matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('basılı tutunca küçülür, bırakınca geri döner', (t) async {
    await t.pumpWidget(kur());
    final g = await t.startGesture(t.getCenter(find.byKey(hedef)));
    await t.pump(kPressTimeout);
    await t.pump();
    await t.pump(SandikMotion.press);
    expect(olcek(t), closeTo(0.97, 0.001));
    await g.up();
    await t.pumpAndSettle();
    expect(olcek(t), closeTo(1, 0.0001));
  });

  testWidgets('listede hızlı dokunuşta da geri bildirim görünür',
      (t) async {
    var tik = 0;
    await t.pumpWidget(kur(listede: true, onTap: () => tik++));
    await t.tap(find.byKey(hedef));
    await t.pump();
    await t.pump(SandikMotion.press ~/ 2);
    expect(olcek(t), lessThan(1),
        reason: 'basma tamamlanmadan bırakılmamalı');
    await t.pumpAndSettle();
    expect(olcek(t), closeTo(1, 0.0001), reason: 'basılı kalmamalı');
    expect(tik, 1);
  });

  testWidgets('art arda iki hızlı dokunuş basılı bırakmaz', (t) async {
    var tik = 0;
    await t.pumpWidget(kur(listede: true, onTap: () => tik++));
    await t.tap(find.byKey(hedef));
    await t.pump();
    await t.pump(SandikMotion.press ~/ 2);
    await t.tap(find.byKey(hedef));
    await t.pumpAndSettle();
    expect(olcek(t), closeTo(1, 0.0001));
    expect(tik, 2);
  });

  testWidgets('kaydırma başlayınca basılı hâl beklemeden kalkar', (t) async {
    await t.pumpWidget(kur(listede: true));
    final g = await t.startGesture(t.getCenter(find.byKey(hedef)));
    await t.pump(kPressTimeout);
    await t.pump();
    await g.moveBy(const Offset(0, -60));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(olcek(t), closeTo(1, 0.0001));
  });

  testWidgets('hareketi azalt: küçülme yok, solma var', (t) async {
    await t.pumpWidget(kur(azalt: true));
    final g = await t.startGesture(t.getCenter(find.byKey(hedef)));
    await t.pump(kPressTimeout);
    await t.pump();
    await t.pump(SandikMotion.press);
    expect(olcek(t), closeTo(1, 0.0001));
    expect(saydamlik(t), closeTo(0.82, 0.001));
    await g.up();
    await t.pumpAndSettle();
    expect(saydamlik(t), 1);
  });

  testWidgets('hareketi azalt: hızlı dokunuşta da solar ve geri döner',
      (t) async {
    await t.pumpWidget(kur(azalt: true, listede: true));
    await t.tap(find.byKey(hedef));
    await t.pump();
    await t.pump(SandikMotion.press ~/ 2);
    expect(saydamlik(t), lessThan(1));
    await t.pumpAndSettle();
    expect(saydamlik(t), 1);
  });

  testWidgets('basma sırasında çocuk yeniden KURULMAZ', (t) async {
    var son = 0;
    await t.pumpWidget(kur(build: (n) => son = n));
    final ilk = son;
    await t.tap(find.byKey(hedef));
    await t.pumpAndSettle();
    expect(son, ilk);
  });

  testWidgets('onTap yoksa geri bildirim yok', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(
        child:
            SandikTappable(child: SizedBox(width: 120, height: 48, key: hedef)),
      ),
    ));
    final g = await t.startGesture(t.getCenter(find.byKey(hedef)));
    await t.pump(kPressTimeout);
    await t.pump(SandikMotion.press);
    expect(olcek(t), closeTo(1, 0.0001));
    await g.up();
  });
}
