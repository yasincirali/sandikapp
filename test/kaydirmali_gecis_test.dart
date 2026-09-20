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
    bool ipucu = false,
    VoidCallback? onIpucu,
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
                  etkin: true,
                  onGecis: onGecis,
                  ipucu: ipucu,
                  onIpucuGosterildi: onIpucu,
                  // Komşu kart: sürüklerken yanda görünen içerik.
                  komsu: (ileri) => SizedBox(
                      height: 120, child: Text(ileri ? 'Ayşe' : 'Birlikte')),
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
    expect(find.text('Ayşe'), findsOneWidget,
        reason: 'sürüklerken komşu kart görünür');
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
    expect(find.text('Ayşe'), findsNothing,
        reason: 'yaylanınca komşu kart pencereden çıkar');
  });

  testWidgets('sağa kaydırma geri yönü bildirir', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    await t.drag(find.text('kart'), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(yon, isFalse);
  });

  // Tek seferlik göz kırpma (2026-09-21): ilk açılışta kart sola kayıp
  // geri gelir, o an hedef adı görünür; tercih bir kez işaretlenir.
  testWidgets('ipucu: kart göz kırpar, hedef adı belirir, tercih işaretlenir',
      (t) async {
    var isaret = 0;
    await t.pumpWidget(kur(onGecis: (_) {}, ipucu: true, onIpucu: () => isaret++));
    expect(isaret, 1);
    expect(find.text('Ayşe'), findsNothing);
    // Bekleme (3× surface) + sola kayış: rozet görünür.
    await t.pump(SandikMotion.surface * 3);
    await t.pump(SandikMotion.surface);
    expect(find.text('Ayşe'), findsOneWidget);
    // Bekleme (2× surface) zamanlayıcıyla geçer; pumpAndSettle kare bekler,
    // zamanlayıcı beklemez — önce süreyi ilerlet.
    // Bekleme zamanlayıcı ile geçer, geri dönüş kare ile; ikisini de adım
    // adım ilerlet (pumpAndSettle zamanlayıcı beklemez).
    for (var i = 0; i < 12 && find.text('Ayşe').evaluate().isNotEmpty; i++) {
      await t.pump(SandikMotion.surface);
    }
    await t.pumpAndSettle();
    expect(find.text('Ayşe'), findsNothing, reason: 'geri gelince kaybolur');
    expect(isaret, 1);
  });

  testWidgets('ipucu: hareketi azalt açıkken oynamaz, yine işaretlenir',
      (t) async {
    var isaret = 0;
    await t.pumpWidget(kur(
        onGecis: (_) {}, ipucu: true, reduce: true, onIpucu: () => isaret++));
    await t.pumpAndSettle();
    expect(isaret, 1);
    expect(find.text('Ayşe'), findsNothing);
  });

  testWidgets('hareketi azalt açıkken geçiş yine çalışır', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v, reduce: true));
    await t.drag(find.text('kart'), const Offset(-160, 0));
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });
}
