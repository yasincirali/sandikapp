import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Boş takip listesinin öneri çipleri (Gram altın · Dolar · BIST 100):
/// dokununca var olan ekleme yolu (`watchlistProvider.add`) çağrılır, çip
/// kaybolur; dolu listede ve takipteki varlıkta çip yok. "NEDEN TAKİP
/// LİSTESİ?" kutusu kalktı.
class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Liste extends WatchlistNotifier {
  _Liste(this._ilk, this.eklenen, {this.bekle});
  final List<WatchlistItem> _ilk;
  final List<WatchlistItem> eklenen;
  final Completer<void>? bekle;

  @override
  Future<List<WatchlistItem>> build() async => _ilk;

  /// Sunucuya gitmez; listeyi bilerek DEĞİŞTİRMEZ ki çipin kendi
  /// kaybolması (liste dolup boş durum gitmeden) sınansın.
  @override
  Future<void> add(WatchlistItem item) async {
    eklenen.add(item);
    if (bekle != null) await bekle!.future;
  }
}

WatchlistItem _usd() => WatchlistItem(
      id: '1',
      userId: 'u1',
      ticker: FiyatKaynagi.usdTry,
      name: 'Amerikan Doları',
      type: AssetType.doviz,
      subCategory: 'USD',
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: 40,
      periodChangePct: 1,
    );

Future<List<WatchlistItem>> _pump(
  WidgetTester tester, {
  List<WatchlistItem> ilk = const [],
  Completer<void>? bekle,
}) async {
  SharedPreferences.setMockInitialValues({});
  await initPreferencesCache();
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final eklenen = <WatchlistItem>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_Auth.new),
      watchlistProvider.overrideWith(() => _Liste(ilk, eklenen, bekle: bekle)),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  // Uygulamada oturum açıkken `authProvider` çoktan yüklü; testte kimse
  // izlemediği için ilk okuma yükleniyor görürdü.
  ProviderScope.containerOf(tester.element(find.byType(WatchlistBody)))
      .read(authProvider);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return eklenen;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('kimlik', () {
    test('aramanın ürettiği kimlik: 24 ayar gram, USD, XU100', () {
      final k = VarlikKimligi.takipOnerileri;
      expect(k.map((e) => e.ticker), [
        FiyatKaynagi.gramAltin24,
        FiyatKaynagi.usdTry,
        FiyatKaynagi.bist100,
      ]);
      expect(k[0].type, AssetType.altin);
      expect(k[0].subCategory, 'Gram Altın (24 Ayar)');
      expect(k[1].type, AssetType.doviz);
      expect(k[1].key, 'doviz|sub:USD');
      expect(k[2].type, AssetType.hisse);
      expect(k[2].key, 'hisse|XU100.IS');
    });
  });

  testWidgets('boş liste: üç çip, açıklama ve Varlık Ekle; neden kutusu yok',
      (tester) async {
    await _pump(tester);
    expect(find.text('Gram altın'), findsOneWidget);
    expect(find.text('Dolar'), findsOneWidget);
    expect(find.text('BIST 100'), findsOneWidget);
    expect(find.text('Varlık Ekle'), findsOneWidget);
    expect(find.text('NEDEN TAKİP LİSTESİ?'), findsNothing);
    expect(find.bySemanticsLabel('Gram altını takibe al'), findsOneWidget);
    expect(find.bySemanticsLabel('Doları takibe al'), findsOneWidget);
    expect(find.bySemanticsLabel("BIST 100'ü takibe al"), findsOneWidget);
    // HIG: dokunma alanı ≥ 44 pt.
    for (final t in ['Gram altın', 'Dolar', 'BIST 100']) {
      final kutu = tester.getSize(find
          .ancestor(of: find.text(t), matching: find.byType(Container))
          .first);
      expect(kutu.height, greaterThanOrEqualTo(SandikTouch.min), reason: t);
    }
  });

  testWidgets('dokununca ekleme çağrılır ve çip kaybolur', (tester) async {
    final eklenen = await _pump(tester);
    await tester.tap(find.text('Gram altın'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(eklenen, hasLength(1));
    expect(eklenen.single.ticker, FiyatKaynagi.gramAltin24);
    expect(eklenen.single.type, AssetType.altin);
    expect(eklenen.single.userId, 'u1');
    expect(find.text('Gram altın'), findsNothing);
    expect(find.text('Dolar'), findsOneWidget);
    expect(find.text('BIST 100'), findsOneWidget);
  });

  testWidgets('iş sürerken ikinci dokunuş yutulur', (tester) async {
    final bekle = Completer<void>();
    final eklenen = await _pump(tester, bekle: bekle);
    await tester.tap(find.text('Dolar'));
    await tester.pump();
    await tester.tap(find.text('Dolar'), warnIfMissed: false);
    await tester.pump();
    expect(eklenen, hasLength(1));
    bekle.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Dolar'), findsNothing);
  });

  testWidgets('dolu listede çip yok', (tester) async {
    await _pump(tester, ilk: [_usd()]);
    expect(find.text('Gram altın'), findsNothing);
    expect(find.text('BIST 100'), findsNothing);
    expect(find.text('Varlık Ekle'), findsNothing);
  });

  test('kaynak: neden kutusu ve anahtarları kalktı, demo kapısı çipte', () {
    final k = ekranKaynagiSync('lib/screens/watchlist_screen.dart');
    expect(k, isNot(contains('whyWatchlist')));
    final bas = k.indexOf('Future<void> _ekle(VarlikKimligi k)');
    expect(bas, greaterThan(0));
    final govde = k.substring(bas, k.indexOf('Widget build', bas));
    expect(govde, contains("DemoModu.yazmaKapisi('takip')"));
    expect(govde, contains('OzellikOlcumu.say(Ozellik.takipOnerisi)'));
    expect(govde, contains('watchlistProvider.notifier'));
    expect(govde, contains('WatchlistLimitException'));
  });
}
