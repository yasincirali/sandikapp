import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Takip listesini paylaş" (müşteri 2026-11-10).
///
/// Sabitlenenler: kartta tutar/adet yok (yalnız ad + "eklediğimden beri"
/// yüzdesi), en çok 6 satır ekrandaki sırayla, yüzdesi bilinmeyen satır
/// düşer, paylaşılacak satır yoksa düğme yok, kart yatırım tavsiyesi
/// notunu taşır.
WatchlistItem _kalem(String id, {double? pct, double? fiyat = 1234.5}) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: '$id.IS',
      name: 'Varlık $id',
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 12),
      currentPrice: fiyat,
      periodChangePct: pct,
    );

void main() {
  group('takipPaylasimSatirlari', () {
    test('en çok 6 satır, ekrandaki sırayla', () {
      final liste = [for (var i = 0; i < 9; i++) _kalem('$i')];
      final s = takipPaylasimSatirlari(
          liste, {for (var i = 0; i < 9; i++) '$i': i.toDouble()});
      expect(s, hasLength(takipPaylasimAzami));
      expect(takipPaylasimAzami, 6);
      expect(s.map((r) => r.ad).toList(), [
        'Varlık 0',
        'Varlık 1',
        'Varlık 2',
        'Varlık 3',
        'Varlık 4',
        'Varlık 5'
      ]);
    });

    test('yüzdesi bilinmeyen satır düşer, yerine sonraki gelir', () {
      final liste = [_kalem('a'), _kalem('b'), _kalem('c')];
      final s =
          takipPaylasimSatirlari(liste, {'a': null, 'b': 4.2, 'c': double.nan});
      expect(s.map((r) => r.ad), ['Varlık b']);
    });

    test('boş liste ya da hiç yüzde yok → boş', () {
      expect(takipPaylasimSatirlari(const [], const {}), isEmpty);
      expect(takipPaylasimSatirlari([_kalem('a')], {'a': null}), isEmpty);
    });
  });

  group('kart', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    testWidgets('tutar ve adet yok; imza ve tavsiye notu var', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark]),
        home: const Scaffold(
          body: Center(
            child: KiyasPaylasKarti(
              baslik: 'Takip listem',
              tarihAraligi: 'Eklediğimden beri',
              satirlar: [
                (ad: 'Varlık a', pct: 12.5),
                (ad: 'Varlık b', pct: -3.0),
              ],
              alt: 'sandık ile takip ediyorum',
              uyari: 'Yatırım tavsiyesi değildir.',
            ),
          ),
        ),
      ));
      final metinler = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .toList();
      expect(metinler.where((m) => m.contains('₺')), isEmpty);
      expect(metinler, contains('Yatırım tavsiyesi değildir.'));
      expect(metinler, contains('sandık ile takip ediyorum'));
      expect(metinler, contains('+%12,5'));
      expect(metinler, contains('Eklediğimden beri'));
    });
  });

  group('düğme', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pump(WidgetTester tester,
        {required List<WatchlistItem> liste,
        required List<({String ad, double pct})> satirlar}) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        watchlistProvider.overrideWith(() => _Liste(liste)),
        watchlistChartProvider.overrideWith((ref) async => const {}),
        activePartnersProvider.overrideWithValue(const []),
        watchlistLimitProvider.overrideWithValue(1 << 30),
        takipPaylasimSatirlariProvider.overrideWith((ref) async => satirlar),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const Scaffold(body: WatchlistBody()),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('paylaşılacak satır varken 44 pt düğme, etiketli',
        (tester) async {
      await pump(tester,
          liste: [_kalem('a', pct: 4.2)],
          satirlar: [(ad: 'Varlık a', pct: 4.2)]);
      final dugme = find.byTooltip('Takip listesini paylaş');
      expect(dugme, findsOneWidget);
      final boy = tester.getSize(dugme);
      expect(boy.width, greaterThanOrEqualTo(44));
      expect(boy.height, greaterThanOrEqualTo(44));
    });

    testWidgets('liste boş → düğme yok', (tester) async {
      await pump(tester, liste: const [], satirlar: const []);
      expect(find.byTooltip('Takip listesini paylaş'), findsNothing);
    });

    testWidgets('hiçbir satırın yüzdesi yok → düğme yok', (tester) async {
      await pump(tester, liste: [_kalem('a')], satirlar: const []);
      expect(find.byTooltip('Takip listesini paylaş'), findsNothing);
    });
  });
}

class _Liste extends WatchlistNotifier {
  _Liste(this.liste);
  final List<WatchlistItem> liste;

  @override
  Future<List<WatchlistItem>> build() async => liste;
}
