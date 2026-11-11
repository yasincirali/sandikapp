import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/sandik_yenile.dart';

import 'helpers/kaynak.dart';

/// Tek çekip yenile sarmalayıcısı (2026-11-11).
///
/// 1. Ratchet: `lib/` altında `RefreshIndicator` yalnız `SandikYenile`'nin
///    içinde yaşar. Ekran kendi `RefreshIndicator.adaptive`'ini yazarsa eşikte
///    tık o ekranda sessizce eksik kalır; bu test onu yakalar.
/// 2. Eşikte tık: yenileme eşiği geçilince çekiş başına BİR kez
///    `HapticFeedback.selectionClick`; eşiğin altında hiç. Platform kanalı
///    dinlenerek ölçülür (titreşimin gerçekten istendiği tek yer).
void main() {
  test('lib/ altında SandikYenile dışında RefreshIndicator yok', () {
    final hits = <String>[];
    // Yorum satırları sayılmaz: gerekçe yazan yorum adı anabilir.
    final kod = RegExp(r'^\s*(///|//)');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('sandik_yenile.dart')) continue;
      if (f.path.contains('/generated/')) continue;
      final satirlar = ekranKaynagiSync(f.path).split('\n');
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i];
        if (kod.hasMatch(s)) continue;
        if (RegExp(r'\bRefreshIndicator\b').hasMatch(s)) {
          hits.add('${f.path}:${i + 1}: ${s.trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'Çekip yenile için SandikYenile kullan '
            '(lib/widgets/sandik_yenile.dart):\n${hits.join('\n')}');
  });

  group('eşikte tık', () {
    late List<String> tiklar;
    var yenileme = 0;

    setUp(() {
      tiklar = [];
      yenileme = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          tiklar.add(call.arguments as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> kur(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SandikYenile(
            onRefresh: () async => yenileme++,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 48, child: Text('Satır $i')),
              ],
            ),
          ),
        ),
      ));
    }

    int secimSayisi() =>
        tiklar.where((a) => a == 'HapticFeedbackType.selectionClick').length;

    testWidgets('eşik geçilince bir kez; geri dönüp yeniden geçince yine bir',
        (t) async {
      await kur(t);

      final g = await t.startGesture(t.getCenter(find.text('Satır 0')));
      for (var i = 0; i < 40; i++) {
        await g.moveBy(const Offset(0, 20));
        await t.pump();
      }
      expect(secimSayisi(), 1, reason: 'eşik geçildi: tek tık');

      // Geri çekip yeniden eşiğin ötesine: aynı çekişte ikinci tık yok.
      for (var i = 0; i < 5; i++) {
        await g.moveBy(const Offset(0, -10));
        await t.pump();
      }
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, 20));
        await t.pump();
      }
      expect(secimSayisi(), 1);

      await g.up();
      await t.pumpAndSettle();
      expect(yenileme, 1, reason: 'onRefresh davranışı aynen');
      expect(secimSayisi(), 1);
    }, variant: const TargetPlatformVariant(
        {TargetPlatform.android, TargetPlatform.iOS}));

    testWidgets('eşiğin altında bırakılırsa tık yok, yenileme yok',
        (t) async {
      await kur(t);
      final g = await t.startGesture(t.getCenter(find.text('Satır 0')));
      for (var i = 0; i < 3; i++) {
        await g.moveBy(const Offset(0, 10));
        await t.pump();
      }
      await g.up();
      await t.pumpAndSettle();
      expect(secimSayisi(), 0);
      expect(yenileme, 0);
    });
  });
}
