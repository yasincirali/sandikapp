import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';

/// Onay dialogları tek yüzeyden: `showSandikConfirm`.
///
/// 2026-09 denetimi: 13 dosyada Material `AlertDialog`, 5 dosyada
/// `CupertinoAlertDialog`; aynı "sil" diyaloğu iki ekranda kopyaydı.
void main() {
  Future<bool?> open(WidgetTester t, {bool destructive = false}) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showSandikConfirm(
                context: context,
                title: 'Varlığı sil',
                message: 'Emin misin?',
                confirmLabel: 'Sil',
                destructive: destructive,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('onay true, vazgeç false döner', (t) async {
    await open(t);
    expect(find.text('Varlığı sil'), findsOneWidget);
    await t.tap(find.text('Sil'));
    await t.pumpAndSettle();
    expect(find.text('Varlığı sil'), findsNothing);
    // İkinci açılış: vazgeç.
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(find.text('Varlığı sil'), findsNothing);
  });

  testWidgets('bariyere dokunmak false sayılır, exception yok', (t) async {
    await open(t);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('Varlığı sil'), findsNothing);
    expect(t.takeException(), isNull);
  });

  test('CupertinoAlertDialog artık kullanılmıyor; AlertDialog yalnızca izinli yerlerde', () {
    // Kalanlar: home_screen `_kapsamSor` (üç seçenekli — onay değil),
    // settings şifre adımı + sorumluluk reddi metni (form/doküman),
    // dividend/quick_adjust (form dialogları).
    const allowedAlert = {
      'lib/screens/home_screen.dart',
      'lib/screens/settings_screen.dart',
      'lib/widgets/dividend_dialog.dart',
      'lib/widgets/quick_adjust_dialog.dart',
    };
    final cupertino = <String>[];
    final alert = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (l.contains('CupertinoAlertDialog(')) cupertino.add('$p:${i + 1}');
        if (l.contains('AlertDialog(') &&
            !l.contains('CupertinoAlertDialog(') &&
            !allowedAlert.contains(p)) {
          alert.add('$p:${i + 1}');
        }
      }
    }
    expect(cupertino, isEmpty, reason: 'showSandikConfirm kullan:\n${cupertino.join('\n')}');
    expect(alert, isEmpty, reason: 'showSandikConfirm kullan:\n${alert.join('\n')}');
  });
}
