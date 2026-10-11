import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';

/// Varlık detayı grafiğinin katmanları (MUM · EMA50 · EMA200, yasin
/// 2026-10-10) — kim görür; 20:38 kararıyla ücretsiz, kilit yalnız ƒx'te.
///
/// Ana kural (CLAUDE.md "Canlıdaki kullanıcı etkilenmez"): paywall kapalı
/// ve admin olmayan kullanıcıda araç çubuğu BİREBİR eskisi (MA20 · LOG).
/// Yeni bayrak yok; karar `premiumOzellikleriGorunurProvider`'da.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-100',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pump(WidgetTester tester,
    {bool gorunur = false, bool kilitli = false}) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final asset = _asset();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio([asset])),
        partnersProvider.overrideWith(_FakePartners.new),
        premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
        premiumKilitliProvider.overrideWithValue(kilitli),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: asset, showBackButton: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  // yasin 2026-10-11: mum ve EMA herkese, bayraksız; ƒx yalnız Premium
  // görünürlüğünde (paywall açık ya da admin).
  testWidgets('paywall kapalı, admin değil: mum ve EMA var, ƒx yok',
      (tester) async {
    await _pump(tester);
    expect(find.text('MA20'), findsWidgets);
    expect(find.text('LOG'), findsWidgets);
    expect(find.text('MUM'), findsOneWidget);
    expect(find.text('EMA50'), findsOneWidget);
    expect(find.text('EMA200'), findsOneWidget);
    expect(find.textContaining('ƒx'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('görünür ve Premium: çipler açılıp kapanır, tercih kalıcı',
      (tester) async {
    await _pump(tester, gorunur: true);
    for (final c in ['MUM', 'EMA50', 'EMA200', 'MA20', 'LOG']) {
      expect(find.text(c), findsOneWidget, reason: '$c çipi yok');
    }
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(AssetDetailScreen)));
    await tester.tap(find.text('EMA50'));
    await tester.pump();
    expect(container.read(chartEma50Provider), isTrue);
    await tester.tap(find.text('EMA200'));
    await tester.pump();
    expect(container.read(chartEma200Provider), isTrue);
    await tester.tap(find.text('MUM'));
    await tester.pump();
    expect(container.read(chartCandleProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paywall açık, Premium değil: Mum/EMA ücretsiz, yalnız ƒx kilitli',
      (tester) async {
    await _pump(tester, gorunur: true, kilitli: true);
    // Tek kilit: kendi göstergeni yaz (ƒx).
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AssetDetailScreen)));
    await tester.tap(find.text('EMA50'));
    await tester.pump();
    expect(container.read(chartEma50Provider), isTrue);
    await tester.tap(find.text('EMA200'));
    await tester.pump();
    expect(container.read(chartEma200Provider), isTrue);
    await tester.tap(find.text('MUM'));
    await tester.pump();
    expect(container.read(chartCandleProvider), isTrue);
    await tester.tap(find.text('MA20'));
    await tester.pump();
    expect(container.read(chartMA20Provider), isTrue);
    expect(tester.takeException(), isNull);
  });
}
