import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gorunum_kapsami.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföy hareketleri filtresi Portföy ekranının kümesini kullanır (yasin
/// 2026-10-10: "varlık filtresi olan her yere portföydeki filtreleri
/// koymalıyız … abd hisse portföyde var ancak hareketlerde yok"): `goz_alici`
/// açıkken türler defterde hareketi olanlar, ABD hissesi varsa hisse
/// BIST/ABD diye ayrı; portföy seçimi defteri daraltır.
const _uid = 'user-1';

Asset _lot(
  String id,
  AssetType type,
  DateTime added, {
  DateTime? silindi,
  String name = 'Varlık',
  String? sub,
  String cur = 'TRY',
  String? portfoy,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: name,
      ticker: id.toUpperCase(),
      type: type,
      subCategory: sub,
      portfoyId: portfoy,
      quantity: 10,
      purchasePrice: 100,
      currency: cur,
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: added,
      deletedAt: silindi,
    );

final _simdi = DateTime.now();
final _defter = [
  _lot('thyao', AssetType.hisse, _simdi.subtract(const Duration(days: 2)),
      name: 'Türk Hava Yolları'),
  _lot('asels', AssetType.hisse, _simdi.subtract(const Duration(days: 40)),
      name: 'Aselsan'),
  _lot('aft', AssetType.fon, _simdi.subtract(const Duration(days: 5)),
      name: 'Ak Portföy Teknoloji'),
  _lot('gram', AssetType.altin, _simdi.subtract(const Duration(days: 200)),
      name: 'Gram Altın', portfoy: 'p1'),
  _lot('aapl', AssetType.hisse, _simdi.subtract(const Duration(days: 3)),
      name: 'Apple', sub: 'abd', cur: 'USD'),
  _lot('sise', AssetType.hisse, _simdi.subtract(const Duration(days: 60)),
      name: 'Şişecam',
      silindi: _simdi.subtract(const Duration(days: 10))),
];

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
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pump(WidgetTester tester,
    {double genislik = 390,
    double olcek = 1,
    PortfoyKapsami kapsam = (secim: PortfoySecimi.tumu, bilinen: const <String>{})}) async {
  tester.view.physicalSize = Size(genislik * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      portfoyKapsamiProvider.overrideWithValue(kapsam),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: const AllTransactionsScreen(
        allPartnerAssets: {},
        partners: [],
        initialView: '',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> filtreyiAc(WidgetTester tester) async {
    await tester.tap(find.text('Filtrele'));
    await tester.pumpAndSettle();
  }

  testWidgets('bayrak kapalı: eski liste (her tür, BIST/ABD yok)',
      (tester) async {
    RemoteConfigService.testAcik = {'abd_hisse'};
    await _pump(tester);
    await filtreyiAc(tester);
    expect(find.text('Kripto'), findsOneWidget);
    expect(find.text('ABD Hisse'), findsNothing);
  });

  testWidgets('goz_alici: defterdeki türler + BIST/ABD; ABD seçilince yalnız '
      'ABD hissesinin hareketleri', (tester) async {
    RemoteConfigService.testAcik = {'goz_alici', 'abd_hisse'};
    await _pump(tester);
    expect(find.text('AAPL'), findsOneWidget);
    await filtreyiAc(tester);
    expect(find.text('BIST Hisse'), findsOneWidget);
    expect(find.text('ABD Hisse'), findsOneWidget);
    expect(find.text('Kripto'), findsNothing,
        reason: 'Defterde kripto hareketi yok');
    await tester.tap(find.text('ABD Hisse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 kaydı göster'));
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('THYAO'), findsNothing);
    expect(find.text('1 kayıt'), findsOneWidget);
  });

  testWidgets('portföy seçimi defteri daraltır', (tester) async {
    await _pump(tester, kapsam: (secim: 'p1', bilinen: const {'p1'}));
    expect(find.text('Gram Altın'), findsOneWidget);
    expect(find.text('THYAO'), findsNothing);
    expect(find.text('1 kayıt'), findsOneWidget);
  });
}
