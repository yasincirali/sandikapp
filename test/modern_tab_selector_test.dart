import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/modern_tab_selector.dart';

/// `ModernTabSelector` — ortak sayısından bağımsız genişlik değişmezi.
///
/// Önceki hâli `totalW / count` ile bölüyordu ve hiç kaydırmıyordu: 4
/// ortakta segment ~58px'e, 8 ortakta ~38px'e düşüyordu. Ne "Birlikte"
/// sığıyordu ne de dokunma hedefi `SandikTouch.minSize` üstünde kalıyordu.
/// Buradaki testler o regresyonun geri gelmesini engeller.

AppUser _u(String id, String ad) => AppUser(
      id: id,
      email: '$id@e.com',
      displayName: ad,
      createdAt: DateTime(2026),
    );

List<AppUser> _ortaklar(int n) =>
    [for (var i = 0; i < n; i++) _u('p$i', 'Ortak$i Soyad')];

Future<void> _pump(
  WidgetTester tester, {
  required List<AppUser> partners,
  String? selectedId,
  double width = 390,
  ValueChanged<String?>? onChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [SandikPalette.dark],
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ModernTabSelector(
            partners: partners,
            selectedId: selectedId,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('sabit üç segment', () {
    // Asıl değişmez: N büyüdükçe segment sayısı ARTMAZ.
    for (final n in <int>[1, 2, 4, 8, 20]) {
      testWidgets('$n ortak → yine 3 segment', (tester) async {
        await _pump(tester, partners: _ortaklar(n));

        expect(find.text('Birlikte'), findsOneWidget);
        expect(find.text('Ben'), findsOneWidget);
        // Üçüncü: tek ortakta adı, çoklu ortakta "Ortaklar".
        expect(
          n == 1 ? find.text('Ortak0') : find.text('Ortaklar'),
          findsOneWidget,
        );
      });
    }

    testWidgets('20 ortakta bile segment genişliği daralmaz', (tester) async {
      await _pump(tester, partners: _ortaklar(20), width: 390);

      // Her segment ~130px — eski kodda 390/22 ≈ 17px olurdu.
      final birlikte = tester.getRect(find.text('Birlikte'));
      expect(birlikte.width, greaterThan(40));

      // Kabuk yüksekliği sabit 48pt kalmalı.
      final kabuk = tester.getRect(
        find.byType(ModernTabSelector),
      );
      expect(kabuk.height, 48);
    });

    testWidgets('taşma yok — 8 ortak, dar ekran', (tester) async {
      await _pump(tester, partners: _ortaklar(8), width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('seçim', () {
    testWidgets('Birlikte → null', (tester) async {
      String? alinan = 'baslangic';
      await _pump(
        tester,
        partners: _ortaklar(3),
        selectedId: '',
        onChanged: (v) => alinan = v,
      );
      await tester.tap(find.text('Birlikte'));
      expect(alinan, isNull);
    });

    testWidgets('Ben → boş string', (tester) async {
      String? alinan;
      await _pump(
        tester,
        partners: _ortaklar(3),
        onChanged: (v) => alinan = v,
      );
      await tester.tap(find.text('Ben'));
      expect(alinan, '');
    });

    testWidgets('tek ortak → menüsüz, tek dokunuşla seçilir', (tester) async {
      String? alinan;
      await _pump(
        tester,
        partners: [_u('p0', 'Sıla Yılmaz')],
        onChanged: (v) => alinan = v,
      );
      // Tek seçenek için menü açmak gereksiz dokunuş olurdu.
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tester.tap(find.text('Sıla'));
      expect(alinan, 'p0');
    });

    testWidgets('çok ortak → menü açılır ve seçim iletilir', (tester) async {
      String? alinan;
      await _pump(
        tester,
        partners: [_u('p0', 'Sıla Yılmaz'), _u('p1', 'Kerem Ak')],
        onChanged: (v) => alinan = v,
      );
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);

      await tester.tap(find.text('Ortaklar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kerem').last);
      await tester.pumpAndSettle();
      expect(alinan, 'p1');
    });

    testWidgets('seçili ortağın adı üçüncü segmentte yazar', (tester) async {
      await _pump(
        tester,
        partners: [_u('p0', 'Sıla Yılmaz'), _u('p1', 'Kerem Ak')],
        selectedId: 'p1',
      );
      expect(find.text('Kerem'), findsOneWidget);
      expect(find.text('Ortaklar'), findsNothing);
    });
  });

  group('kenar durumları', () {
    testWidgets('boş displayName çökmez', (tester) async {
      await _pump(tester, partners: [_u('p0', '   ')]);
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('bilinmeyen selectedId ortak yuvasında durur', (tester) async {
      // Silinmiş ortak: pill üçüncü yuvada kalır, etiket "Ortaklar"a düşer.
      await _pump(
        tester,
        partners: _ortaklar(3),
        selectedId: 'yok-boyle-biri',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ortaklar'), findsOneWidget);
    });

    testWidgets('büyük metin ölçeğinde taşma yok', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ModernTabSelector(
                  partners: _ortaklar(5),
                  selectedId: null,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
