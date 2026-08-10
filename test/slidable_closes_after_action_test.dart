import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kaydırma paneli her aksiyondan sonra kapanmalı — "Al", "Sat", "Temettü"
/// dahil.
///
/// Regresyon: aksiyon butonları `Slidable.of(context)` ile paneli kapatıyordu
/// ama verilen `context`, `Slidable`'ı KURAN build metodunun context'iydi.
/// `Slidable.of` bir InheritedWidget aramasıdır ve yalnızca aşağı doğru
/// çalışır; üstteki context'ten arama `null` döner ve `close()` sessizce
/// hiçbir şey yapmaz. Panel açık kalıyordu.
///
/// "Sil" düzelmiş GÖRÜNÜYORDU: onay dialogu listeyi yeniden kurduğu için
/// panel yan etkiyle sıfırlanıyordu — asıl hata orada da vardı.

/// Hatalı kurulum: `Slidable.of` panelin ÜSTÜNDEKİ context'ten çağrılır.
Widget _actionWithOuterContext(BuildContext outer, VoidCallback onPressed) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Slidable.of(outer)?.close();
        onPressed();
      },
      child: const SizedBox.expand(key: ValueKey('action-hit')),
    );

/// Doğru kurulum: `Builder` aramayı bir seviye aşağı taşır.
Widget _actionWithBuilder(VoidCallback onPressed) => Builder(
      builder: (inner) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Slidable.of(inner)?.close();
          onPressed();
        },
        child: const SizedBox.expand(key: ValueKey('action-hit')),
      ),
    );

/// `Slidable.of` sonucunu doğrudan gözlemek için: `close()` çağrılabildi mi?
Widget _probe({
  required bool useBuilder,
  required void Function(bool foundSlidable) report,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        // Bu, gerçek koddaki `_AssetCardState.build` context'inin eşleniği —
        // `Slidable` bunun ALTINDA kurulur.
        builder: (cardContext) => Slidable(
          key: const ValueKey('row'),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.3,
            children: [
              Expanded(
                child: useBuilder
                    ? Builder(
                        builder: (inner) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => report(Slidable.of(inner) != null),
                          child: const SizedBox.expand(
                              key: ValueKey('action-hit')),
                        ),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => report(Slidable.of(cardContext) != null),
                        child: const SizedBox.expand(
                            key: ValueKey('action-hit')),
                      ),
              ),
            ],
          ),
          child: const SizedBox(height: 80, width: double.infinity, child: Text('satır')),
        ),
      ),
    ),
  );
}

Future<void> _openPane(WidgetTester tester) async {
  await tester.drag(find.text('satır'), const Offset(-200, 0));
  await tester.pumpAndSettle();
}

/// Aksiyon butonuna dokunur.
///
/// `tester.tap` widget'ın kendi merkezini kullanır; kaydırma paneli
/// `FractionallySizedOverflowBox` içinde çizildiği için o merkez ekranın
/// dışına düşebiliyor ve dokunuş ıskalanıyor. Bunun yerine panelin GERÇEKTEN
/// göründüğü noktadan (satırın sağ kenarının hemen sağı) dokunuyoruz.
Future<void> _tapAction(WidgetTester tester) async {
  final row = tester.getRect(find.text('satır'));
  await tester.tapAt(Offset(row.right + 20, row.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kartın context\'inden Slidable BULUNAMAZ (hatanın kökü)',
      (tester) async {
    bool? found;
    await tester.pumpWidget(_probe(
      useBuilder: false,
      report: (f) => found = f,
    ));
    await _openPane(tester);
    await _tapAction(tester);
    await tester.pump();

    // Eski kodun yaptığı buydu: arama null döner, close() no-op olur.
    expect(found, isFalse,
        reason: 'Slidable.of, paneli kuran context\'ten null dönmeli — '
            'düzeltmenin neden gerektiğini sabitler');
  });

  testWidgets('Builder ile Slidable BULUNUR (düzeltme)', (tester) async {
    bool? found;
    await tester.pumpWidget(_probe(
      useBuilder: true,
      report: (f) => found = f,
    ));
    await _openPane(tester);
    await _tapAction(tester);
    await tester.pump();

    expect(found, isTrue,
        reason: 'Builder aramayı Slidable\'ın altına taşır; close() artık '
            'gerçekten paneli kapatır');
  });

  testWidgets('aksiyon sonrası panel kapanır', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (_) => Slidable(
            key: const ValueKey('row'),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.3,
              // `DrawerMotion` yalnızca flex'li çocuk kabul eder — gerçek
              // koddaki `_rowAction` da içeriği `Expanded` ile sarar.
              children: [Expanded(child: _actionWithBuilder(() => tapped++))],
            ),
            child: const SizedBox(
                height: 80, width: double.infinity, child: Text('satır')),
          ),
        ),
      ),
    ));

    await _openPane(tester);
    final openedAt = tester.getTopLeft(find.text('satır')).dx;
    expect(openedAt, lessThan(0), reason: 'panel açık olmalı');

    await _tapAction(tester);
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(tester.getTopLeft(find.text('satır')).dx, closeTo(0, 0.5),
        reason: 'aksiyondan sonra satır yerine dönmeli (panel kapalı)');
  });

  testWidgets('hatalı kurulumda panel AÇIK kalır', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (outer) => Slidable(
            key: const ValueKey('row'),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.3,
              children: [
                Expanded(child: _actionWithOuterContext(outer, () {})),
              ],
            ),
            child: const SizedBox(
                height: 80, width: double.infinity, child: Text('satır')),
          ),
        ),
      ),
    ));

    await _openPane(tester);
    await _tapAction(tester);
    await tester.pumpAndSettle();

    // Kullanıcının şikayeti tam olarak bu: "al sat ve temettü de hala açıkta".
    expect(tester.getTopLeft(find.text('satır')).dx, lessThan(-1),
        reason: 'hatalı kurulumda panel açık kalır — testin koruduğu davranış');
  });
}
