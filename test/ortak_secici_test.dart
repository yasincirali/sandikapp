import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kapsam_kisi_secici.dart';
import 'package:portfoy_takip/widgets/modern_tab_selector.dart';
import 'package:portfoy_takip/widgets/ortak_secici.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// `OrtakSecici` — sadeleştirme madde 8 (2026-10-04).
///
/// Değişmez: bayrak `tek_ortak_secici` kapalı da açık da olsa seçim AYNI
/// durumu aynı sözleşmeyle yazar (`null` Birlikte, `''` Ben, uuid ortak).
/// Görünüş değişir, davranış değişmez. Bayrak kapalıyken çağıranın eski
/// kabuğu birebir çizilir.
AppUser _ortak(String id, String ad) => AppUser(
    id: id, email: '$id@x.com', displayName: ad, createdAt: DateTime(2026));

final _iki = [_ortak('p1', 'Ayşe Yılmaz'), _ortak('p2', 'Can Kaya')];

Widget _uygulama(List<AppUser> ortaklar, EskiOrtakSecici eski) =>
    ProviderScope(
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
                  eski: eski,
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

String? _durum(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(OrtakSecici)))
    .read(watchlistCompareViewProvider);

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  for (final acik in [false, true]) {
    for (final eski in EskiOrtakSecici.values) {
      final ad = 'bayrak ${acik ? 'AÇIK' : 'kapalı'} · ${eski.name}';

      testWidgets('$ad: çok ortakta seçim aynı provider\'ı aynı '
          'sözleşmeyle yazar', (tester) async {
        if (acik) RemoteConfigService.testAcik = {'tek_ortak_secici'};
        await tester.pumpWidget(_uygulama(_iki, eski));
        expect(_durum(tester), '', reason: 'varsayılan Ben');

        // Hangi kabuk çiziliyor?
        if (acik) {
          expect(find.byType(SandikSegment), findsOneWidget);
          expect(find.byType(ModernTabSelector), findsNothing);
          expect(find.byType(KapsamKisiSecici), findsNothing);
        } else {
          expect(find.byType(ModernTabSelector),
              eski == EskiOrtakSecici.hap ? findsOneWidget : findsNothing);
          expect(find.byType(KapsamKisiSecici),
              eski == EskiOrtakSecici.segment ? findsOneWidget : findsNothing);
          expect(find.byType(SandikSegment), findsNothing);
        }

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

      testWidgets('$ad: tek ortakta üçüncü segment tek dokunuşla seçer',
          (tester) async {
        if (acik) RemoteConfigService.testAcik = {'tek_ortak_secici'};
        await tester.pumpWidget(_uygulama([_iki.first], eski));
        await tester.tap(find.text('Ayşe'));
        await tester.pumpAndSettle();
        expect(_durum(tester), 'p1');
        expect(find.byType(PopupMenuItem<String>), findsNothing,
            reason: 'tek seçenek için menü açılmaz');
      });
    }
  }

  testWidgets('bayrak AÇIK: segmentler ekran okuyucudan etkin ve seçili '
      'durumlu', (tester) async {
    RemoteConfigService.testAcik = {'tek_ortak_secici'};
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_uygulama(_iki, EskiOrtakSecici.hap));

    expect(
        tester.getSemantics(find.bySemanticsLabel('Kimin portföyü: Ben')),
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

  testWidgets('bayrak AÇIK: dar ekranda (320pt) taşma yok', (tester) async {
    RemoteConfigService.testAcik = {'tek_ortak_secici'};
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_uygulama(
        [_ortak('p1', 'Muhammed Abdurrahman'), _ortak('p2', 'Can')],
        EskiOrtakSecici.segment));
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
