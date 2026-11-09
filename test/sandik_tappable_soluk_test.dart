import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// `SandikTappable(soluk: true)` — eski `SandikBasma` davranışı (Ar-Ge 5 Kas
/// 22:40 #3 ile tek bileşene katıldı; dosya eskiden `sandik_basma_test`).
///
/// Dokunma geri bildirimi (animasyon denetimi, 2026-09-30): basılıyken
/// küçülme + solma, hızlı dokunuşta da görünür, hareketi azalt açıkken
/// küçülme yok. Takılmama gerekçesi: Scale/FadeTransition — kare başına
/// build yok (sayaçla doğrulanır).
void main() {
  Widget kur({bool azalt = false, VoidCallback? onTap, ValueChanged<int>? build}) {
    var sayac = 0;
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: azalt),
        child: Center(
          child: SandikTappable(
            soluk: true,
            haptic: SandikHaptic.none,
            onTap: onTap ?? () {},
            child: Builder(builder: (_) {
              build?.call(++sayac);
              return const SizedBox(width: 120, height: 48, key: Key('hedef'));
            }),
          ),
        ),
      ),
    );
  }

  double olcek(WidgetTester t) {
    final s = t.widgetList<ScaleTransition>(find.ancestor(
        of: find.byKey(const Key('hedef')), matching: find.byType(ScaleTransition)));
    return s.isEmpty ? 1 : s.first.scale.value;
  }

  double saydamlik(WidgetTester t) => t
      .widget<FadeTransition>(find.ancestor(
          of: find.byKey(const Key('hedef')), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  testWidgets('basılıyken küçülür ve solar, bırakınca geri döner', (t) async {
    await t.pumpWidget(kur());
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('hedef'))));
    await t.pump(kPressTimeout);
    await t.pump(SandikMotion.press);
    expect(olcek(t), closeTo(0.97, 0.001));
    expect(saydamlik(t), closeTo(0.82, 0.001));
    await g.up();
    await t.pumpAndSettle();
    expect(olcek(t), 1);
    expect(saydamlik(t), 1);
  });

  testWidgets('hızlı dokunuşta da geri bildirim görünür, onTap çalışır', (t) async {
    var tik = 0;
    await t.pumpWidget(kur(onTap: () => tik++));
    await t.tap(find.byKey(const Key('hedef')));
    // İlk kare animasyonu başlatır (süre sıfırdan sayar), ikincisi ilerletir.
    await t.pump();
    await t.pump(SandikMotion.press ~/ 2);
    expect(olcek(t), lessThan(1), reason: 'basılı hâl tamamlanmadan bırakılmamalı');
    await t.pumpAndSettle();
    expect(olcek(t), 1);
    expect(tik, 1);
  });

  testWidgets('hareketi azalt: küçülme yok, solma var', (t) async {
    await t.pumpWidget(kur(azalt: true));
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('hedef'))));
    await t.pump(kPressTimeout);
    await t.pump(SandikMotion.press);
    expect(find.ancestor(of: find.byKey(const Key('hedef')), matching: find.byType(ScaleTransition)),
        findsNothing);
    expect(saydamlik(t), lessThan(1));
    await g.up();
    await t.pumpAndSettle();
  });

  testWidgets('animasyon sırasında çocuk yeniden KURULMAZ (takılma yok)', (t) async {
    var son = 0;
    await t.pumpWidget(kur(build: (n) => son = n));
    final ilk = son;
    await t.tap(find.byKey(const Key('hedef')));
    await t.pumpAndSettle();
    expect(son, ilk, reason: 'Scale/FadeTransition kare başına build etmemeli');
  });

  testWidgets('onTap yoksa geri bildirim yok (devre dışı buton)', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Center(
        child: SandikTappable(
            soluk: true,
            child: SizedBox(width: 120, height: 48, key: Key('hedef'))),
      ),
    ));
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('hedef'))));
    await t.pump(kPressTimeout);
    await t.pump(SandikMotion.press);
    expect(olcek(t), 1);
    await g.up();
  });

  testWidgets('haptic: none — dokunma ve uzun basma titreşmez', (t) async {
    final cagrilar = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (c) async {
      cagrilar.add(c);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    var uzun = 0;
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: SandikTappable(
          soluk: true,
          haptic: SandikHaptic.none,
          onTap: () {},
          onLongPress: () => uzun++,
          child: const SizedBox(width: 120, height: 48, key: Key('hedef')),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('hedef')));
    await t.longPress(find.byKey(const Key('hedef')));
    await t.pumpAndSettle();
    expect(uzun, 1);
    expect(cagrilar.where((c) => c.method == 'HapticFeedback.vibrate'), isEmpty);
  });
}
