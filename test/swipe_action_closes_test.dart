import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kaydırma aksiyonundan sonra panel kapanmalı.
///
/// Kullanıcı bildirimi (2026-08-11): "swipe edip sat dediğimde swipe
/// kapanmalı".
///
/// Kök sebep: panel kapanışı bir ANİMASYONDUR. Eski kod `close()` çağırıp
/// hemen ardından dialog açıyordu; dialog açılış animasyonu araya girince
/// kapanış yarıda kalıyor ve dialog kapandığında panel hâlâ açık kalıyordu.
///
/// Düzeltme sırayı tersine çevirir: önce aksiyon (dialog) beklenir, sonra
/// panel kapatılır. Bunun çalışması için callback tipinin `void` DEĞİL
/// `FutureOr<void>` olması şart — `void` ile `await` beklemez ve hata
/// sessizce geri döner.
///
/// Bu test o iki davranışı birlikte kilitler.
void main() {
  /// Gerçek `_rowAction`'ın davranışını birebir taklit eden minimal kurulum.
  Widget harness({
    required FutureOr<void> Function() onPressed,
    required List<String> log,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Slidable(
            key: const ValueKey('row'),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.5,
              children: [
                Expanded(
                  child: Builder(builder: (ctx) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final slidable = Slidable.of(ctx);
                        await onPressed();
                        log.add('aksiyon-bitti');
                        slidable?.close();
                        log.add('panel-kapatildi');
                      },
                      child: Container(
                        color: Colors.green,
                        alignment: Alignment.center,
                        child: const Text('Sat'),
                      ),
                    );
                  }),
                ),
              ],
            ),
            child: Container(
              height: 60,
              color: Colors.blue,
              child: const Text('satir'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('panel, aksiyon TAMAMLANDIKTAN sonra kapanır', (t) async {
    final log = <String>[];
    final completer = Completer<void>();

    await t.pumpWidget(harness(
      onPressed: () {
        log.add('aksiyon-basladi');
        return completer.future;
      },
      log: log,
    ));

    await t.drag(find.text('satir'), const Offset(300, 0));
    await t.pumpAndSettle();
    expect(find.text('Sat'), findsOneWidget, reason: 'panel açılmalı');

    await t.tap(find.text('Sat'), warnIfMissed: false);
    await t.pump();

    // Aksiyon henüz bitmedi → panel KAPANMAMALI.
    expect(log, ['aksiyon-basladi']);
    expect(log.contains('panel-kapatildi'), isFalse,
        reason: 'Panel, dialog daha açıkken kapanmamalı — eski hatanın '
            'tam tersi durum.');

    // Dialog kapandı.
    completer.complete();
    await t.pumpAndSettle();

    expect(log, ['aksiyon-basladi', 'aksiyon-bitti', 'panel-kapatildi'],
        reason: 'Sıra: aksiyon bitsin, SONRA panel kapansın.');
  });

  testWidgets('senkron aksiyonda da panel kapanır', (t) async {
    final log = <String>[];
    await t.pumpWidget(harness(onPressed: () {}, log: log));

    await t.drag(find.text('satir'), const Offset(300, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Sat'), warnIfMissed: false);
    await t.pumpAndSettle();

    expect(log, contains('panel-kapatildi'));
  });

  test('callback tipi FutureOr olmalı — void `await` etmez', () {
    // Bu, tip seviyesinde bir değişmez. `void Function(Position)` kalsaydı
    // `await onPressed()` derlenir ama BEKLEMEZ; panel yine erken kapanırdı
    // ve hata sessizce geri gelirdi.
    const src = 'lib/screens/charts_screen.dart';
    final file = File(src);
    final text = file.readAsStringSync();

    expect(
      RegExp(r'final FutureOr<void> Function\(Position\) onAdd')
          .hasMatch(text),
      isTrue,
      reason: '`onAdd` dialog açar; tipi FutureOr<void> olmalı.',
    );
    expect(
      RegExp(r'required FutureOr<void> Function\(\) onPressed')
          .hasMatch(text),
      isTrue,
      reason: '`_rowAction.onPressed` beklenebilir olmalı.',
    );
  });
}
