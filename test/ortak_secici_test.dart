import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/ortak_secici.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// `OrtakSecici` — sadeleştirme madde 8 (2026-10-04).
///
/// Değişmez: seçim durumu sözleşmeyle yazar (`null` Birlikte, `''` Ben,
/// uuid ortak). 2026-10-05'e kadar bayrak `tek_ortak_secici` kapalıyken
/// eski iki kabuk (`ModernTabSelector`, `KapsamKisiSecici`) da aynı
/// sözleşmeyle sınanıyordu; kabuklar bayrakla birlikte silindi.
AppUser _ortak(String id, String ad) => AppUser(
    id: id, email: '$id@x.com', displayName: ad, createdAt: DateTime(2026));

final _iki = [_ortak('p1', 'Ayşe Yılmaz'), _ortak('p2', 'Can Kaya')];

Widget _uygulama(List<AppUser> ortaklar) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              // Takip ekranındaki çağrının aynısı: seçim provider'a yazılır.
              child: Consumer(
                builder: (context, ref, _) => OrtakSecici(
                  partners: ortaklar,
                  selectedId: ref.watch(watchlistCompareViewProvider),
                  onChanged: (v) =>
                      ref.read(watchlistCompareViewProvider.notifier).state = v,
                ),
              ),
            ),
          ),
        ),
      ),
    );

String? _durum(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OrtakSecici)))
        .read(watchlistCompareViewProvider);

void main() {
  testWidgets('çok ortakta seçim sağlayıcıya sözleşmeyle yazılır',
      (tester) async {
    await tester.pumpWidget(_uygulama(_iki));
    expect(_durum(tester), '', reason: 'varsayılan Ben');
    expect(find.byType(SandikSegment), findsOneWidget);

    await tester.tap(find.text('Birlikte'));
    await tester.pumpAndSettle();
    expect(_durum(tester), isNull, reason: 'Birlikte = null');

    await tester.tap(find.text('Ben'));
    await tester.pumpAndSettle();
    expect(_durum(tester), '', reason: 'Ben = boş metin');

    // Çok ortak: üçüncü segment listeyi açar, ortak id'si yazılır.
    await tester.tap(find.text('Ortaklar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can').last);
    await tester.pumpAndSettle();
    expect(_durum(tester), 'p2');
    expect(find.text('Can'), findsOneWidget,
        reason: 'seçili ortağın adı segmentte');

    // Ortak seçiliyken yeniden dokunuş listeyi açar → başka ortak.
    await tester.tap(find.text('Can'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayşe').last);
    await tester.pumpAndSettle();
    expect(_durum(tester), 'p1');
  });

  testWidgets('tek ortakta üçüncü segment tek dokunuşla seçer', (tester) async {
    await tester.pumpWidget(_uygulama([_iki.first]));
    await tester.tap(find.text('Ayşe'));
    await tester.pumpAndSettle();
    expect(_durum(tester), 'p1');
    expect(find.byType(PopupMenuItem<String>), findsNothing,
        reason: 'tek seçenek için menü açılmaz');
  });

  testWidgets(
      'segmentler ekran okuyucudan etkin ve seçili '
      'durumlu', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_uygulama(_iki));

    expect(tester.getSemantics(find.bySemanticsLabel('Kimin portföyü: Ben')),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true));
    expect(
        tester.getSemantics(find.bySemanticsLabel('Kimin portföyü: Birlikte')),
        isSemantics(isSelected: false, hasTapAction: true));

    tester.semantics.tap(find.semantics.byLabel('Kimin portföyü: Birlikte'));
    await tester.pumpAndSettle();
    expect(_durum(tester), isNull);

    tester.semantics.tap(find.semantics.byLabel('Kimin portföyü: Ortaklar'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2),
        reason: 'ortak listesi semantik eylemle açılmalı');
    semantics.dispose();
  });

  testWidgets('dar ekranda (320pt) taşma yok', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        _uygulama([_ortak('p1', 'Muhammed Abdurrahman'), _ortak('p2', 'Can')]));
    await tester.tap(find.text('Ortaklar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muhammed').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('ortak seçen ekranlar tek bileşeni çağırır (Ana ekran çipi ayrı)', () {
    for (final yol in [
      'lib/screens/portfolio_screen.dart',
      'lib/screens/all_transactions_screen.dart',
      'lib/screens/watchlist_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
    ]) {
      final k = ekranKaynagiSync(yol);
      expect(k, contains('OrtakSecici('), reason: yol);
      expect(k, isNot(contains('ModernTabSelector(')), reason: yol);
      expect(k, isNot(contains('KapsamKisiSecici(')), reason: yol);
    }
  });
}
