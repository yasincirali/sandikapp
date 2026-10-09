import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_grubu.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy'de BIST / ABD hisse ayrımı (yasin 2026-10-09, bayrak `abd_hisse`).
///
/// Kilitlenen davranışlar:
/// 1. Bayrak kapalı: hisse tek dilim ("Hisse"), eski davranış birebir.
/// 2. Bayrak açık + portföyde ABD hissesi: halka/lejant "BIST Hisse" ve
///    "ABD Hisse" diye iki dilim; her biri listeyi ayrı süzer.
/// 3. Bayrak açık ama ABD hissesi yok: ayrım açılmaz, "Hisse" kalır.
/// 4. ABD hissesi ayrı tür DEĞİL — ayrım yalnız görünümde (`PortfoyGrubu`).
const _uid = 'user-1';

Asset _lot(String id, String ticker, AssetType tur, double adet, double fiyat,
        {String currency = 'TRY', String? sub}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      subCategory: sub,
      quantity: adet,
      purchasePrice: fiyat,
      currency: currency,
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

// THYAO 3.000 ₺ (%50), AAPL 50 $ × 42 = 2.100 ₺ (%35), fon 900 ₺ (%15).
final _thy = _lot('a', 'THYAO', AssetType.hisse, 10, 300);
final _aapl =
    _lot('b', 'AAPL', AssetType.hisse, 1, 50, currency: 'USD', sub: 'abd');
final _fon = _lot('c', 'AFT', AssetType.fon, 90, 10);
final _varliklar = [_thy, _aapl, _fon];
PortfolioState get _durum =>
    PortfolioState(assets: _varliklar, usdTry: 42, eurTry: 46, gbpTry: 54);

Future<void> _pump(WidgetTester tester, {List<Asset>? varliklar}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider
          .overrideWith(() => _FakePortfolio(varliklar ?? _varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const PortfolioScreen(),
    ),
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

  group('PortfoyGrubu', () {
    test('ayrım kapalıyken grup türün kendisi', () {
      expect(PortfoyGrubu.of(_aapl, pazarAyir: false),
          const PortfoyGrubu(AssetType.hisse));
      expect(PortfoyGrubu.of(_thy, pazarAyir: false),
          PortfoyGrubu.of(_aapl, pazarAyir: false));
      expect(const PortfoyGrubu(AssetType.hisse).kapsar(_aapl), isTrue);
      expect(const PortfoyGrubu(AssetType.hisse).kapsar(_thy), isTrue);
    });

    test('ayrım açıkken pazar ayrı grup, renk ayrık', () {
      final abd = PortfoyGrubu.of(_aapl, pazarAyir: true);
      final bist = PortfoyGrubu.of(_thy, pazarAyir: true);
      expect(abd, isNot(bist));
      expect(abd.kapsar(_aapl), isTrue);
      expect(abd.kapsar(_thy), isFalse);
      expect(bist.kapsar(_thy), isTrue);
      expect(bist.kapsar(_fon), isFalse);
      expect(abd.color, Sandik.abdHisse);
      expect(bist.color, AssetType.hisse.color);
      // Hisse dışı tür pazar taşımaz.
      expect(PortfoyGrubu.of(_fon, pazarAyir: true),
          const PortfoyGrubu(AssetType.fon));
    });

    test('ayrım yalnız bayrak açık ve ABD hissesi varken', () {
      expect(PortfoyGrubu.pazarAyrimi(_varliklar, bayrak: false), isFalse);
      expect(PortfoyGrubu.pazarAyrimi(_varliklar, bayrak: true), isTrue);
      expect(PortfoyGrubu.pazarAyrimi([_thy, _fon], bayrak: true), isFalse);
    });
  });

  test('turDagilimi: ayrımda hisse iki dilim', () {
    final tek = turDagilimi(_varliklar, _durum);
    expect(tek.map((e) => e.grup.tur), [AssetType.hisse, AssetType.fon]);
    expect(tek.first.pay, closeTo(0.85, 1e-9));

    final ayri = turDagilimi(_varliklar, _durum, pazarAyir: true);
    expect(ayri.map((e) => e.grup.abd), [false, true, null]);
    expect(ayri[0].pay, closeTo(0.50, 1e-9));
    expect(ayri[1].pay, closeTo(0.35, 1e-9));
  });

  testWidgets('bayrak kapalı: tek "Hisse" satırı', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    expect(find.text('Hisse'), findsOneWidget);
    expect(find.text('%85,0'), findsOneWidget);
    expect(find.text('ABD Hisse'), findsNothing);
  });

  testWidgets('bayrak açık: BIST ve ABD ayrı satır, ayrı süzer',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu', 'abd_hisse'};
    await _pump(tester);
    expect(find.text('BIST Hisse'), findsOneWidget);
    expect(find.text('ABD Hisse'), findsOneWidget);
    expect(find.text('%50,0'), findsOneWidget);
    expect(find.text('%35,0'), findsOneWidget);

    await tester.tap(find.text('ABD Hisse'));
    await tester.pumpAndSettle();
    expect(_satir('AAPL'), findsWidgets);
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AFT'), findsNothing);

    await tester.tap(find.text('BIST Hisse'));
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsWidgets);
    expect(_satir('AAPL'), findsNothing);

    // Aynı satıra ikinci dokunuş süzgeci kaldırır.
    await tester.tap(find.text('BIST Hisse'));
    await tester.pumpAndSettle();
    expect(_satir('AAPL'), findsWidgets);
    expect(_satir('AFT'), findsWidgets);
  });

  testWidgets('bayrak açık, ABD hissesi yok: "Hisse" kalır', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu', 'abd_hisse'};
    await _pump(tester, varliklar: [_thy, _fon]);
    expect(find.text('Hisse'), findsOneWidget);
    expect(find.text('BIST Hisse'), findsNothing);
  });

  testWidgets('büyük halka da iki dilim ve ayrı süzer', (tester) async {
    RemoteConfigService.testAcik = {'abd_hisse'};
    await _pump(tester);
    final pasta = tester.widget<PieChart>(find.byType(PieChart));
    expect(pasta.data.sections.length, 3);
    expect(pasta.data.sections[1].color, Sandik.abdHisse);

    await tester.tap(find.textContaining('ABD Hisse'));
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AAPL'), findsWidgets);
  });
}
