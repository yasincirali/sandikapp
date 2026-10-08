import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme 2 — Portföy dağılım şeridi (bayrak `portfoy_dagilim_cubugu`).
///
/// Kilitlenen davranışlar:
/// 1. Bayrak kapalı: eski halka (PieChart) ekranda, şerit yok.
/// 2. Bayrak açık: halka yerine "Dağılım" kartı; çipler "Tür %xx,x".
/// 3. Çip halka dilimi gibi süzer; aynı çipe ya da "Tümü"ye dokunmak kaldırır.
/// 4. "Halka ›" eski halkayı alt sayfada açar; dilim/lejant dokunuşu yine
///    listeyi süzer.
const _uid = 'user-1';

Asset _lot(String id, String ticker, AssetType tur, double adet, double fiyat) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
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

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

// Hisse 3.000 (%75), fon 1.000 (%25).
final _varliklar = [
  _lot('a', 'THYAO', AssetType.hisse, 10, 300),
  _lot('b', 'AFT', AssetType.fon, 100, 10),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(_varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _satir(String ticker) => find.textContaining(ticker);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('bayrak kapalı: eski halka, şerit yok', (tester) async {
    await _pump(tester);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('Dağılım'), findsNothing);
    expect(find.text('Halka ›'), findsNothing);
  });

  testWidgets('bayrak açık: halka yerine dağılım kartı ve yüzde çipleri',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    expect(find.byType(PieChart), findsNothing);
    expect(find.text('Dağılım'), findsOneWidget);
    expect(find.text('Halka ›'), findsOneWidget);
    expect(find.textContaining('%75,0'), findsOneWidget);
    expect(find.textContaining('%25,0'), findsOneWidget);
    expect(find.text('Tümü'), findsOneWidget);
  });

  testWidgets('çip süzer; aynı çip ve "Tümü" süzgeci kaldırır',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    expect(_satir('THYAO'), findsWidgets);
    expect(_satir('AFT'), findsWidgets);

    await tester.tap(find.textContaining('%25,0'));
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AFT'), findsWidgets);

    // Aynı çipe yeniden dokunmak kaldırır.
    await tester.tap(find.textContaining('%25,0'));
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsWidgets);

    // "Tümü" de kaldırır.
    await tester.tap(find.textContaining('%75,0'));
    await tester.pumpAndSettle();
    expect(_satir('AFT'), findsNothing);
    await tester.tap(find.text('Tümü'));
    await tester.pumpAndSettle();
    expect(_satir('AFT'), findsWidgets);
    expect(_satir('THYAO'), findsWidgets);
  });

  testWidgets('çip dokunma hedefi en az 44pt', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    final boy = tester.getSize(find.ancestor(
        of: find.text('Tümü'), matching: find.byType(ConstrainedBox)).first);
    expect(boy.height, greaterThanOrEqualTo(44));
  });

  testWidgets('"Halka ›" halkayı alt sayfada açar, dilim seçimi süzer',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    await tester.tap(find.text('Halka ›'));
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsOneWidget);

    // Halkanın lejantı (dilimle aynı geri çağrı) arkadaki listeyi süzer.
    final lejant = find.descendant(
        of: find.byType(BottomSheet), matching: find.textContaining('%25,0'));
    await tester.tap(lejant);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AFT'), findsWidgets);
  });

  test('turDagilimi: büyükten küçüğe, paylar toplamı 1', () {
    final d = turDagilimi(_varliklar,
        PortfolioState(assets: _varliklar, usdTry: 42, eurTry: 46, gbpTry: 54));
    expect(d.map((e) => e.tur), [AssetType.hisse, AssetType.fon]);
    expect(d.first.pay, closeTo(0.75, 1e-9));
    expect(d.fold<double>(0, (s, e) => s + e.pay), closeTo(1, 1e-9));
  });
}
