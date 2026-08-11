// Rate limit dialogu geri sayımı CANLI göstermeli.
//
// Regresyon: dialog `message` sabit String alıyordu; kullanıcı dialogu
// okurken süre eskiyordu ve "1:14 dakika" donuk kalıyordu. Artık
// liveMessage her saniye tazeleniyor, süre dolunca dialog kapanıyor.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

void main() {
  testWidgets('liveMessage saniyede bir tazelenir', (tester) async {
    var kalan = 3;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showSandikDialog(
            context: context,
            kind: SandikDialogKind.info,
            title: 'Biraz Bekle',
            message: 'başlangıç',
            liveMessage: () => kalan <= 0 ? null : '$kalan saniye kaldı',
          ),
          child: const Text('aç'),
        ),
      ),
    ));

    await tester.tap(find.text('aç'));
    await tester.pump(); // dialog açılışı
    await tester.pump(const Duration(milliseconds: 250)); // geçiş

    expect(find.text('3 saniye kaldı'), findsOneWidget,
        reason: 'liveMessage ilk değeri göstermeli');

    kalan = 2;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 saniye kaldı'), findsOneWidget,
        reason: 'saniyede bir tazelenmeli');
    expect(find.text('3 saniye kaldı'), findsNothing);

    kalan = 1;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 saniye kaldı'), findsOneWidget);

    // Süre bitti → dialog kendini kapatmalı.
    kalan = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Biraz Bekle'), findsNothing,
        reason: 'geri sayım bitince dialog kapanmalı');
  });

  testWidgets('liveMessage verilmezse sabit message gösterilir', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showSandikDialog(
            context: context,
            kind: SandikDialogKind.error,
            title: 'Hata',
            message: 'sabit mesaj',
          ),
          child: const Text('aç'),
        ),
      ),
    ));

    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('sabit mesaj'), findsOneWidget);

    // Timer kurulmadığı için bekleme sonrası da aynı kalmalı ve
    // dialog kendiliğinden kapanmamalı.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('sabit mesaj'), findsOneWidget);
    expect(find.text('Hata'), findsOneWidget);
  });
}
