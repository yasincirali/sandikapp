import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/klavye_kapatici.dart';

/// Uygulama geneli klavye kuralı (kullanıcı, 2026-09-25): dışarı dokununca
/// kapanır, alana geri dokununca yeniden açılır; düğmeler kendi dokunuşunu
/// kaybetmez. `main.dart` bu widget'ı `MaterialApp.builder`'a koyar; test
/// aynı yerleşimi kurar ki alt sayfa (Navigator overlay) da kapsansın.
void main() {
  Widget uygulama({VoidCallback? onDugme}) => MaterialApp(
        builder: (context, child) => KlavyeKapatici(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('alan')),
              const SizedBox(height: 200, child: Text('boşluk')),
              ElevatedButton(onPressed: onDugme, child: const Text('Düğme')),
              Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    builder: (_) => const SizedBox(
                      height: 400,
                      child: Column(children: [
                        TextField(key: Key('altAlan')),
                        SizedBox(height: 200, child: Text('altBoşluk')),
                      ]),
                    ),
                  ),
                  child: const Text('Alt sayfa'),
                ),
              ),
            ],
          ),
        ),
      );

  bool odakli(WidgetTester t, Key k) => t
      .widget<EditableText>(find.descendant(
          of: find.byKey(k), matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

  testWidgets('dışarı dokununca odak düşer, alana dönünce yeniden alınır',
      (tester) async {
    await tester.pumpWidget(uygulama());
    await tester.tap(find.byKey(const Key('alan')));
    await tester.pump();
    expect(odakli(tester, const Key('alan')), isTrue);

    await tester.tap(find.text('boşluk'));
    await tester.pump();
    expect(odakli(tester, const Key('alan')), isFalse,
        reason: 'boşluğa dokunuş klavyeyi kapatmalı (odak düşmeli)');

    await tester.tap(find.byKey(const Key('alan')));
    await tester.pump();
    expect(odakli(tester, const Key('alan')), isTrue,
        reason: 'alana geri dokununca klavye yeniden gelmeli');
  });

  testWidgets('düğme dokunuşu kapatıcıya yenilmez', (tester) async {
    var basildi = 0;
    await tester.pumpWidget(uygulama(onDugme: () => basildi++));
    await tester.tap(find.byKey(const Key('alan')));
    await tester.pump();
    await tester.tap(find.text('Düğme'));
    await tester.pump();
    expect(basildi, 1);
  });

  testWidgets('alt sayfadaki alan da aynı kurala uyar', (tester) async {
    await tester.pumpWidget(uygulama());
    await tester.tap(find.text('Alt sayfa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('altAlan')));
    await tester.pump();
    expect(odakli(tester, const Key('altAlan')), isTrue);

    await tester.tap(find.text('altBoşluk'));
    await tester.pump();
    expect(odakli(tester, const Key('altAlan')), isFalse,
        reason: 'Navigator overlay da kökteki kapatıcının altında');
  });
}
