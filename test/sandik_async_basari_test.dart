import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

/// `SandikAsyncButton` başarı durumu (Ar-Ge 11 Kas 19:04 #3): başarıda
/// gösterge ✓'ye döner, başarı titreşimi gelir, ✓ `SandikMotion.modal`
/// kadar görünür, kapanış ancak ondan sonra koşar; ✓ evresinde çift dokunma
/// kilidi sürer; hata yolunda ✓ yok; sinyal verilmeyen düğme eskisi gibi.
void main() {
  final busy = find.byKey(const ValueKey('busy'));
  final tik = find.byIcon(Icons.check_rounded);

  late List<String> titresimler;
  setUp(() {
    titresimler = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        titresimler.add(call.arguments as String);
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> ac(WidgetTester tester, Widget dugme,
      {bool hareketiAzalt = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: hareketiAzalt),
        child: Scaffold(body: Center(child: dugme)),
      ),
    ));
  }

  testWidgets('başarı: gösterge → ✓, titreşim, kapanış ✓ evresinden sonra',
      (tester) async {
    final sinyal = SandikBasariSinyali();
    final istek = Completer<void>();
    var cagri = 0;
    var kapandi = false;
    await ac(
      tester,
      SandikAsyncButton(
        basari: sinyal,
        onPressed: () async {
          cagri++;
          await istek.future;
          await sinyal.goster();
          kapandi = true;
        },
        child: const Text('Kaydet'),
      ),
    );

    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(busy, findsOneWidget);
    expect(tik, findsNothing);

    istek.complete();
    await tester.pump();
    await tester.pump(SandikMotion.state);
    expect(tik, findsOneWidget, reason: 'iş bitince gösterge ✓ olur');
    expect(busy, findsNothing);
    expect(titresimler, contains('HapticFeedbackType.lightImpact'),
        reason: 'başarı titreşimi (basıştaki medium\'dan ayrı)');
    expect(kapandi, isFalse, reason: '✓ görünmeden sayfa kapanmaz');

    // ✓ evresinde çift dokunma kilidi sürer.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(cagri, 1);

    await tester.pumpAndSettle();
    expect(kapandi, isTrue, reason: 'evre bitince çağıranın kapanışı koşar');
    expect(tik, findsNothing, reason: 'sayfa kapanmadıysa düğme geri gelir');
    expect(find.text('Kaydet'), findsOneWidget);
  });

  testWidgets('✓ evresi SandikMotion.modal kadar sürer', (tester) async {
    final sinyal = SandikBasariSinyali();
    var kapandi = false;
    await ac(
      tester,
      SandikAsyncButton(
        basari: sinyal,
        onPressed: () async {
          await sinyal.goster();
          kapandi = true;
        },
        child: const Text('Kaydet'),
      ),
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pump(SandikMotion.modal - SandikMotion.press);
    expect(kapandi, isFalse);
    // Bir kare payı: saat ilk karede başlar.
    await tester.pump(SandikMotion.press);
    await tester.pump(SandikMotion.press);
    expect(kapandi, isTrue);
  });

  testWidgets('hata yolu: ✓ yok, başarı titreşimi yok', (tester) async {
    final sinyal = SandikBasariSinyali();
    await ac(
      tester,
      SandikAsyncButton(
        basari: sinyal,
        // Ekranlar hatayı kendisi yakalar ve normal döner: goster() hiç
        // çağrılmaz.
        onPressed: () async {},
        child: const Text('Kaydet'),
      ),
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pump(SandikMotion.state);
    expect(tik, findsNothing);
    expect(titresimler, isNot(contains('HapticFeedbackType.lightImpact')));
    await tester.pumpAndSettle();
    expect(find.text('Kaydet'), findsOneWidget);
  });

  testWidgets('hareketi azalt: ✓ geçişsiz belirir, okuma payı kalır',
      (tester) async {
    final sinyal = SandikBasariSinyali();
    var kapandi = false;
    await ac(
      tester,
      hareketiAzalt: true,
      SandikAsyncButton(
        basari: sinyal,
        onPressed: () async {
          await sinyal.goster();
          kapandi = true;
        },
        child: const Text('Kaydet'),
      ),
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pump();
    expect(tik, findsOneWidget);
    // Geçiş yok: ölçek/sönüm sarmalayıcısı tam değerde.
    final olcek = tester.widgetList<ScaleTransition>(
        find.ancestor(of: tik, matching: find.byType(ScaleTransition)));
    for (final s in olcek) {
      expect(s.scale.value, 1);
    }
    expect(kapandi, isFalse, reason: 'bekleme hareket değil, okuma payı');
    await tester.pumpAndSettle();
    expect(kapandi, isTrue);
  });

  testWidgets('sinyalsiz düğme eskisi gibi: ✓ yok', (tester) async {
    await ac(
      tester,
      SandikAsyncButton(onPressed: () async {}, child: const Text('Kaydet')),
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tik, findsNothing);
    expect(titresimler, isNot(contains('HapticFeedbackType.lightImpact')));
  });

  testWidgets('bağlı düğme yoksa goster() beklemeden döner', (tester) async {
    final sinyal = SandikBasariSinyali();
    var dondu = false;
    await tester.pumpWidget(const SizedBox());
    unawaited(sinyal.goster().then((_) => dondu = true));
    await tester.pump();
    expect(dondu, isTrue);
  });

  testWidgets('✓ "Kaydedildi" diye okunur', (tester) async {
    final semantik = tester.ensureSemantics();
    final sinyal = SandikBasariSinyali();
    await ac(
      tester,
      SandikAsyncButton(
        basari: sinyal,
        onPressed: () => sinyal.goster(),
        child: const Text('Kaydet'),
      ),
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pump(SandikMotion.state);
    expect(find.bySemanticsLabel('Kaydedildi'), findsOneWidget);
    await tester.pumpAndSettle();
    semantik.dispose();
  });
}
