import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/sandik_snack.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tek snackbar yolu — `sandikSnack` / `sandikSnackError`.
///
/// 2026-09 denetimi: 30 çağrı yeri kendi rengini/mürekkebini seçiyordu ve
/// beşi ham `$e` basıyordu (PostgREST tablo/kolon adı kullanıcıya gidiyordu).
/// Bu test iki şeyi kilitler:
///   1. `ScaffoldMessenger.showSnackBar` yalnızca yardımcıda çağrılır.
///   2. Hata yolu ham exception metnini ASLA göstermez.
void main() {
  Future<void> pump(WidgetTester t, void Function(BuildContext) act) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => act(context),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    // SnackBar aşağıdan kayarak gelir; animasyon bitmeden eylem dokunulamaz.
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
  }

  testWidgets('sandikSnackError ham exception metnini göstermez', (t) async {
    const raw = 'relation "public.assets" violates check constraint';
    await pump(
      t,
      (ctx) => sandikSnackError(
        ctx,
        const PostgrestException(message: raw, code: '23514'),
        prefix: 'Silinemedi',
      ),
    );
    expect(find.textContaining('public.assets'), findsNothing);
    expect(find.textContaining('Silinemedi'), findsOneWidget);
  });

  testWidgets('onUndo verilince "Geri al" eylemi çıkar ve çalışır', (t) async {
    var undone = false;
    await pump(
      t,
      (ctx) => sandikSnack(ctx, 'X takipten çıkarıldı', onUndo: () => undone = true),
    );
    expect(find.text('Geri al'), findsOneWidget);
    await t.tap(find.text('Geri al'));
    expect(undone, isTrue);
  });

  testWidgets('yeni snackbar öncekini kapatır — kuyruk birikmez', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              sandikSnack(context, 'birinci');
              sandikSnack(context, 'ikinci');
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('ikinci'), findsOneWidget);
    expect(find.text('birinci'), findsNothing);
  });

  test('showSnackBar yalnızca sandik_snack.dart içinde çağrılır', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.endsWith('utils/sandik_snack.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('showSnackBar')) hits.add('$path:${i + 1}');
      }
    }
    expect(hits, isEmpty,
        reason: 'Doğrudan showSnackBar yerine sandikSnack / sandikSnackError '
            'kullan:\n${hits.join('\n')}');
  });
}
