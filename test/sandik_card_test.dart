import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// `SandikCard` ve `SandikSectionHeader` — paylaşılan kabuk komponentleri.
///
/// Denetimde (2026-08-10) 64 kart kabuğunun elle kurulduğu ve 13 varyasyona
/// dağıldığı görüldü. Asıl bedel görsel tutarsızlık değil, **hatanın
/// tekrarlanması**: "başlık + sayaç rozeti" taşması `performance_screen`'de
/// düzeltildikten sonra `portfolio_performance_screen`'de yeniden yazıldı.
///
/// Bu testler komponentlerin o hatayı yapısal olarak imkânsız kıldığını
/// doğrular.
void main() {
  Future<void> pump(WidgetTester t, Widget child,
      {double width = 375, double scale = 1.0}) async {
    t.view.physicalSize = Size(width * 3, 800 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    ));
  }

  group('SandikSectionHeader', () {
    testWidgets('uzun başlık + sayaç dar ekranda taşmaz', (t) async {
      await pump(
        t,
        const SandikSectionHeader(
          title: 'ÇOK UZUN BİR BÖLÜM BAŞLIĞI TEKNİK SİNYALLER VE DAHASI',
          count: 12,
        ),
        width: 320,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('büyük metin ölçeğinde taşmaz — asıl regresyon', (t) async {
      // Elle yazılan hâli 1.5×'te 61px, 3×'te 415px taşıyordu.
      for (final s in [1.5, 2.0, 3.0]) {
        await pump(
          t,
          const SandikSectionHeader(title: 'TEKNİK SİNYALLER', count: 8),
          width: 320,
          scale: s,
        );
        expect(t.takeException(), isNull, reason: 'ölçek $s taştı');
      }
    });

    testWidgets('trailing aksiyonla birlikte taşmaz', (t) async {
      await pump(
        t,
        const SandikSectionHeader(
          title: 'TEKNİK ANALİZ',
          count: 3,
          trailing: Text('Ayarla'),
        ),
        width: 320,
        scale: 2.0,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('sayaç verilmezse rozet çizilmez', (t) async {
      await pump(t, const SandikSectionHeader(title: 'BÖLÜM'));
      expect(find.text('BÖLÜM'), findsOneWidget);
      // Rozet yalnızca sayı metniyle görünür.
      expect(find.textContaining(RegExp(r'^\d+$')), findsNothing);
    });
  });

  group('SandikCard', () {
    testWidgets('varsayılan: surface1 + hairline kenar', (t) async {
      await pump(t, const SandikCard(child: Text('içerik')));
      final box = t.widget<Container>(
        find.ancestor(
            of: find.text('içerik'), matching: find.byType(Container)),
      );
      final dec = box.decoration! as BoxDecoration;
      expect(dec.border, isNotNull, reason: 'düz kart kenarlı olmalı');
      expect(dec.borderRadius,
          BorderRadius.circular(SandikRadius.md));
    });

    testWidgets('bordered:false kenarı kaldırır', (t) async {
      await pump(
          t, const SandikCard(bordered: false, child: Text('içerik')));
      final box = t.widget<Container>(
        find.ancestor(
            of: find.text('içerik'), matching: find.byType(Container)),
      );
      expect((box.decoration! as BoxDecoration).border, isNull);
    });

    testWidgets('onTap verilince dokunulabilir olur', (t) async {
      var tapped = 0;
      await pump(
          t, SandikCard(onTap: () => tapped++, child: const Text('içerik')));
      await t.tap(find.text('içerik'));
      expect(tapped, 1);
    });

    testWidgets('onTap yoksa gereksiz GestureDetector kurulmaz', (t) async {
      await pump(t, const SandikCard(child: Text('içerik')));
      expect(
        find.ancestor(
          of: find.text('içerik'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}
