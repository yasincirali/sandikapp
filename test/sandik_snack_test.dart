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

  // ── Süre (2026-09-16) ──────────────────────────────────────────────────
  //
  // Kullanıcı bildirimi: takip listesinde sola kaydırıp silince "Geri al"
  // toast'ı alt menünün üstünde ÇOK UZUN duruyordu (5 sn). Silme kaydırmayla
  // yapılıyor, yani eylem zaten bilinçli.

  testWidgets('geri alınabilir snackbar 4 saniye durur', (t) async {
    await pump(t, (ctx) => sandikSnack(ctx, 'silindi', onUndo: () {}));
    final bar = t.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 4));
    expect(bar.action, isNotNull, reason: 'süre kuralı eyleme bağlı');
  });

  testWidgets('eylemsiz snackbar 3 saniye — daha kısa kalır', (t) async {
    await pump(t, (ctx) => sandikSnack(ctx, 'kaydedildi'));
    final bar = t.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 3));
  });

  testWidgets('açıkça verilen süre kuralı EZER', (t) async {
    await pump(
      t,
      (ctx) => sandikSnack(ctx, 'x',
          onUndo: () {}, duration: const Duration(seconds: 9)),
    );
    expect(t.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 9));
  });

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

  // ── U11 (2026-09-23 denetimi) ─────────────────────────────────────────
  //
  // Flutter 3.47'de eylemli SnackBar varsayılan olarak `persist: true`;
  // "X eklendi · Alarm kur" dakikalarca kalıp Ekle düğmesini örttü.
  testWidgets('eylemli snackbar süresi dolunca KENDİLİĞİNDEN kapanır',
      (t) async {
    await pump(
      t,
      (ctx) => sandikSnack(
        ctx,
        'X eklendi',
        action: SnackBarAction(label: 'Alarm kur', onPressed: () {}),
      ),
    );
    expect(t.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
    expect(find.text('X eklendi'), findsOneWidget);
    // 4 sn süre + çıkış animasyonu.
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('X eklendi'), findsNothing);
  });

  testWidgets('onUndo snackbar da süresi dolunca kapanır', (t) async {
    await pump(t, (ctx) => sandikSnack(ctx, 'silindi', onUndo: () {}));
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('silindi'), findsNothing);
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
