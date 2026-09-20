import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kaydirmali_gecis.dart';

/// Toplam kartındaki kaydırmalı geçiş: eşiği geçen sürükleme yön bildirir,
/// geçmeyen iptal olur; sürüklerken kenarda hedef adı görünür; "hareketi
/// azalt" açıkken de geçiş çalışır.
void main() {
  Widget kur({
    required ValueChanged<bool> onGecis,
    bool reduce = false,
    Object? anahtar = 'a',
  }) =>
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.light]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: KaydirmaliGecis(
                  anahtar: anahtar,
                  etkin: true,
                  onGecis: onGecis,
                  hedefEtiketi: (ileri) => ileri ? 'Ayşe' : 'Birlikte',
                  child: const SizedBox(height: 120, child: Text('kart')),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('eşiği geçen sola kaydırma ileri bildirir, kenarda hedef adı',
      (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    final g = await t.startGesture(t.getCenter(find.text('kart')));
    await g.moveBy(const Offset(-120, 0));
    await t.pump();
    expect(find.text('Ayşe'), findsOneWidget, reason: 'sürüklerken hedef görünür');
    await g.up();
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });

  testWidgets('eşiğin altında kalan sürükleme iptal — geri yaylanır', (t) async {
    var cagrildi = false;
    await t.pumpWidget(kur(onGecis: (_) => cagrildi = true));
    await t.drag(find.text('kart'), const Offset(-30, 0));
    await t.pumpAndSettle();
    expect(cagrildi, isFalse);
    expect(find.text('Ayşe'), findsNothing, reason: 'yaylanınca ipucu kaybolur');
  });

  testWidgets('sağa kaydırma geri yönü bildirir', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    await t.drag(find.text('kart'), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(yon, isFalse);
  });

  testWidgets('hareketi azalt açıkken geçiş yine çalışır', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v, reduce: true));
    await t.drag(find.text('kart'), const Offset(-160, 0));
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });
}
