import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/genel_arama_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/son_bakilanlar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Genel aramanın boş hâlindeki "Son baktıkların" bölümü (2026-10-26).
///
/// Kilitler: boşken bölüm yok; kayıt → piyasa satırıyla aynı satır, fiyatı
/// aramanın kotasyon yolundan tek istekle; takipte ve bugün portföyde olan
/// süzülür; kaydırarak ve VoiceOver özel eylemiyle kaldırılır; bölüm
/// eylemlerin ÜSTÜNDE.

const _uid = 'user-1';

VarlikKimligi _k(String t, String ad) =>
    VarlikKimligi(ticker: t, name: ad, type: AssetType.hisse, currency: 'TRY');

final _asels = _k('ASELS.IS', 'Aselsan');
final _thyao = _k('THYAO.IS', 'Türk Hava Yolları');
final _garan = _k('GARAN.IS', 'Garanti BBVA');
final _sise = _k('SISE.IS', 'Şişecam');

Asset _lot(String ticker, String ad, double adet) => Asset(
      id: '$ticker-1',
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: 10,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 12,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// THYAO bugün portföyde.
class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_lot('THYAO.IS', 'Türk Hava Yolları', 100)],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

/// GARAN takipte.
class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        WatchlistItem(
          id: 'w1',
          userId: _uid,
          ticker: 'GARAN.IS',
          name: 'Garanti BBVA',
          type: AssetType.hisse,
          currency: 'TRY',
          addedAt: DateTime(2026),
        ),
      ];
}

final _kotasyonCagrilari = <List<String>>[];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      watchlistProvider.overrideWith(_Takip.new),
    ],
    child: MaterialApp(
      home: Material(
        type: MaterialType.transparency,
        child: GenelAramaScreen(
          aramaServisi: (_) async => const [],
          kotasyonServisi: (s) async {
            _kotasyonCagrilari.add(s);
            return {
              if (s.contains('ASELS.IS'))
                'ASELS.IS':
                    YahooQuote(symbol: 'ASELS.IS', regularMarketPrice: 123.45),
            };
          },
        ),
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tohumla(List<VarlikKimligi> l) async {
  SharedPreferences.setMockInitialValues(
      {'son_bakilanlar_v1_$_uid': SonBakilanlar.kodla(l)});
  SonBakilanlar.instance.sifirlaTest();
}

final _bolum = find.byKey(const ValueKey('genel-arama-son-bakilanlar'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(_kotasyonCagrilari.clear);

  testWidgets('kayıt yoksa bölüm hiç görünmez, eylemler yerinde', (t) async {
    await _tohumla(const []);
    await _pump(t);
    expect(_bolum, findsNothing);
    expect(find.text('SON BAKTIKLARIN'), findsNothing);
    expect(find.text('EYLEMLER'), findsOneWidget);
  });

  testWidgets(
      'kayıt → satır (ad + fiyat), takip/portföydeki süzülür, '
      'eylemlerin üstünde', (t) async {
    await _tohumla([_sise, _garan, _thyao, _asels]);
    await _pump(t);
    expect(_bolum, findsOneWidget);
    expect(find.text('SON BAKTIKLARIN'), findsOneWidget);
    expect(find.text('Aselsan'), findsOneWidget);
    expect(find.text('Şişecam'), findsOneWidget);
    // GARAN takipte, THYAO portföyde: listede yok.
    expect(find.text('Garanti BBVA'), findsNothing);
    expect(find.text('Türk Hava Yolları'), findsNothing);
    // Fiyat aramanın kotasyon yolundan; bilinmeyen (SISE) yalnız adla.
    expect(find.text('₺123,45'), findsOneWidget);
    // Tek toplu istek, yalnız görünenler.
    expect(_kotasyonCagrilari, hasLength(1));
    expect(_kotasyonCagrilari.single.toSet(), {'SISE.IS', 'ASELS.IS'});
    // Bölüm eylemlerin üstünde.
    expect(t.getTopLeft(find.text('SON BAKTIKLARIN')).dy,
        lessThan(t.getTopLeft(find.text('EYLEMLER')).dy));
    // HIG: satır ≥44pt.
    final satir = find.byKey(ValueKey('son-bakilan-${_asels.key}'));
    expect(t.getSize(satir).height, greaterThanOrEqualTo(44));
  });

  testWidgets('en çok beş satır; yazınca bölüm kalkar', (t) async {
    await _tohumla([
      for (var i = 0; i < 7; i++) _k('X$i.IS', 'Varlık $i'),
    ]);
    await _pump(t);
    for (var i = 0; i < 5; i++) {
      expect(find.text('Varlık $i'), findsOneWidget);
    }
    expect(find.text('Varlık 5'), findsNothing);

    await t.enterText(
        find.byKey(const ValueKey('genel-arama-alani')), 'zzz');
    await t.pump(const Duration(milliseconds: 400));
    expect(_bolum, findsNothing);
  });

  testWidgets('sola kaydırınca kaldırılır, diske de yazılır', (t) async {
    await _tohumla([_asels, _sise]);
    await _pump(t);
    await t.drag(find.byKey(ValueKey('son-bakilan-kaydir-${_asels.key}')),
        const Offset(-600, 0));
    await t.pumpAndSettle();
    expect(find.text('Aselsan'), findsNothing);
    expect(find.text('Şişecam'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final kalan =
        SonBakilanlar.cozumle(prefs.getString('son_bakilanlar_v1_$_uid')!);
    expect(kalan.map((k) => k.ticker), ['SISE.IS']);
  });

  testWidgets('VoiceOver: etiketli tek düğüm + "Listeden kaldır" özel eylemi',
      (t) async {
    final h = t.ensureSemantics();
    await _tohumla([_asels]);
    await _pump(t);
    final dugum = t.getSemantics(
        find.bySemanticsLabel('Aselsan grafiğini ve istatistiklerini gör'));
    final kaldir = CustomSemanticsAction(label: 'Listeden kaldır');
    final id = CustomSemanticsAction.getIdentifier(kaldir);
    expect(dugum.getSemanticsData().customSemanticsActionIds, contains(id));
    expect(dugum.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    dugum.owner!.performAction(dugum.id, SemanticsAction.customAction, id);
    await t.pumpAndSettle();
    expect(_bolum, findsNothing, reason: 'tek satır kalkınca bölüm de kalkar');
    h.dispose();
  });

  testWidgets('Dynamic Type ×2: satır taşmaz', (t) async {
    await _tohumla([_k('ASELS.IS', 'Aselsan Elektronik Sanayi ve Ticaret')]);
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(t);
    expect(_bolum, findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
