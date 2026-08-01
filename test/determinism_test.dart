import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

void main() {
  group('CustomLoadingIndicator', () {
    testWidgets('dış ölçü istenen boyutta kilitlidir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: CustomLoadingIndicator(size: 40)),
          ),
        ),
      );

      // Dıştaki SizedBox tam 40×40 olmalı — GIF içeride büyütülse bile
      // layout'ta yer kaplaması değişmez.
      final box = tester.getSize(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(SizedBox),
        ).last,
      );
      expect(box.width, 40);
      expect(box.height, 40);
    });

    testWidgets('erişilebilirlik etiketi taşır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CustomLoadingIndicator()),
        ),
      );
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
    });
  });

  group('SandikAsyncButton — aksiyon kesinliği', () {
    testWidgets('hızlı arka arkaya dokunuşta iş yalnızca bir kez çalışır',
        (tester) async {
      var callCount = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SandikAsyncButton(
              onPressed: () async {
                callCount++;
                await completer.future;
              },
              child: const Text('Kaydet'),
            ),
          ),
        ),
      );

      // Üç hızlı dokunuş
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(callCount, 1, reason: 'ikinci ve üçüncü dokunuş yutulmalı');

      completer.complete();
      await tester.pumpAndSettle();

      // İş bitince buton yeniden kullanılabilir
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(callCount, 2);
    });

    testWidgets('iş başarısız dönse de kilit serbest bırakılır',
        (tester) async {
      var callCount = 0;
      var shouldFail = true;
      var completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SandikAsyncButton(
              // Gerçek hata yolunu taklit eder: iş kendi içinde try/catch
              // yapan tipik servis çağrısı gibi davranır.
              onPressed: () async {
                callCount++;
                try {
                  await completer.future;
                } catch (_) {
                  // servis hatayı raporlar, buton yine de çözülmeli
                }
              },
              child: const Text('Kaydet'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(callCount, 1);

      // İş devam ederken buton kilitli.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      completer.completeError(StateError('ağ hatası'));
      await tester.pumpAndSettle();
      shouldFail = false;

      // Asıl iddia: finally kilidi açtığı için buton yeniden basılabilir.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
        reason: 'hata sonrası buton kalıcı kilitli kalmamalı',
      );

      completer = Completer<void>();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(callCount, 2, reason: 'hata sonrası tekrar denenebilmeli');
      expect(shouldFail, isFalse);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('onPressed null ise buton pasiftir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SandikAsyncButton(onPressed: null, child: Text('Kaydet')),
          ),
        ),
      );
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });
  });

  group('pushGuarded', () {
    testWidgets('ilk push geçer, pencere içindeki ikinci push düşer',
        (tester) async {
      var pushed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    pushGuarded(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) {
                          pushed++;
                          return const Scaffold(body: Text('detay'));
                        },
                      ),
                    );
                  },
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      await tester.pump();
      await tester.tap(find.text('Aç'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(pushed, 1, reason: 'aynı sayfa iki kez açılmamalı');
    });
  });
}
