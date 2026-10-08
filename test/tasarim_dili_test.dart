import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// `docs/TASARIM_DILI.md` kurallarının kilidi (2026-10-08, yasin: "tutarlı
/// smooth animasyonları olan rigid bir app … app içi tasarım dili ve
/// komponent standartları"). Belgedeki her "TEK yol" kuralı burada bir
/// testle durur; belge değişirse test de değişir.
void main() {
  final dosyalar = [
    ...Directory('lib/screens').listSync(recursive: true),
    ...Directory('lib/widgets').listSync(recursive: true),
    ...Directory('lib/utils').listSync(recursive: true),
    ...Directory('lib/demo').listSync(recursive: true),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  List<String> iceren(RegExp desen) => [
        for (final f in dosyalar)
          if (desen.hasMatch(f.readAsStringSync())) f.path,
      ];

  test('alt sayfa tek açıcıdan: showSandikSheet', () {
    expect(iceren(RegExp(r'\bshowModalBottomSheet\b')), isEmpty,
        reason: 'Marka hareketi (cekmece) ve hareketi azalt yalnız '
            '`showSandikSheet`te.');
  });

  test('ölçek dışı hareket süresi yok (SandikMotion.of + çıplak süre)', () {
    expect(
        iceren(RegExp(
            r'SandikMotion\.of\(\s*\w+,\s*(const\s+)?Duration\(milliseconds:')),
        isEmpty,
        reason: '140/150/160 ms gibi ara değerler `stateOf` (180) idi.');
  });

  test('platform diyaloğu yok (marka diyaloğu: showSandikConfirm/Dialog)',
      () {
    expect(
        iceren(RegExp(
            r'\b(showDialog|showCupertinoDialog|showCupertinoModalPopup)\s*[<(]')),
        isEmpty);
  });

  test('düğme köşesi tek: tema = SandikRadius.md', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final tema in ['filledButtonTheme', 'outlinedButtonTheme']) {
      final i = main.indexOf('$tema:');
      final govde = main.substring(i, main.indexOf('),\n      ),', i));
      expect(govde, contains('SandikRadius.mdAll'), reason: tema);
    }
  });

  Future<void> ac(WidgetTester t, {required bool azalt}) async {
    await t.pumpWidget(MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: azalt),
        child: child!,
      ),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showSandikSheet<void>(
            context: c,
            builder: (_) => const SizedBox(height: 200, child: Text('S')),
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pump();
  }

  testWidgets('sheet: hareketi azalt → ilk karede yerinde', (t) async {
    await ac(t, azalt: true);
    await t.pump();
    final ilk = t.getTopLeft(find.text('S')).dy;
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('S')).dy, ilk);
  });

  testWidgets('sheet: cekmece eğrisi hızlı başlar', (t) async {
    await ac(t, azalt: false);
    await t.pump(SandikMotion.surface ~/ 2);
    final yarida = t.getTopLeft(find.text('S')).dy;
    await t.pumpAndSettle();
    final sonda = t.getTopLeft(find.text('S')).dy;
    // Sürenin yarısında yolun ~%90'ı alınmış olur (Flutter varsayılanı
    // legacyDecelerate'te ~%80).
    expect(yarida - sonda, lessThan(200 * 0.15));
  });
}
