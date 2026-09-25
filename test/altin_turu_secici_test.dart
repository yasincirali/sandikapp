import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle → Altın: seçim alanı + 5 kısayol + tüm türler alt sayfası
/// (kullanıcı kararı 2026-09-25, alternatif C). Kısayol KURALI
/// `altin_kisayollari_test`'te; burada ekranın o kuralı gösterdiği ve alt
/// sayfadan seçimin forma yazıldığı doğrulanır.

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _assets, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

Asset _altin(GoldSubCategory g, double qty) => Asset(
      id: g.name,
      userId: 'u1',
      name: g.label,
      ticker: goldTickerMap[g.label]!,
      type: AssetType.altin,
      subCategory: g.label,
      unitType: g.unitType,
      quantity: qty,
      purchasePrice: 1000,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: DateTime(2026, 3, 14),
    );

Future<void> _pump(WidgetTester tester, List<Asset> portfolio) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => _FakePortfolio(portfolio)),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
    ],
    child: MaterialApp(
        theme: ThemeData.dark(),
        home: const AddAssetScreen(prefillType: AssetType.altin)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// Hiçbir tür seçili değilken ad yalnızca kısayol çipinde yazar.
Finder _kisayol(GoldSubCategory g) => find.text(g.label);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('altını olmayan kullanıcı popüler beşliyi görür', (tester) async {
    await _pump(tester, const []);
    for (final g in [
      GoldSubCategory.ceyrek,
      GoldSubCategory.gr24,
      GoldSubCategory.gr22,
      GoldSubCategory.yarim,
      GoldSubCategory.tam,
    ]) {
      expect(_kisayol(g), findsOneWidget, reason: g.label);
    }
    // Nadir türler ekranı doldurmaz; alt sayfadadır.
    expect(_kisayol(GoldSubCategory.gremse), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portföydeki tür kısayola girer', (tester) async {
    await _pump(tester, [_altin(GoldSubCategory.resat, 2)]);
    expect(_kisayol(GoldSubCategory.resat), findsOneWidget);
    // 5'e tamamlarken popülerin sonuncusu (Tam) dışarıda kalır.
    expect(_kisayol(GoldSubCategory.tam), findsNothing);
  });

  testWidgets('alt sayfadan arayıp seçilen tür alana yazılır', (tester) async {
    await _pump(tester, const []);
    await tester.tap(find.text('Altın türü seçmek için dokun...'));
    await tester.pumpAndSettle();
    expect(find.text('Altın Türleri'), findsOneWidget);
    expect(find.text('Ziynet'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'gremse');
    await tester.pumpAndSettle();
    expect(find.text('Gremse Altın'), findsOneWidget);
    expect(find.text('Hamit Altını'), findsNothing);

    await tester.tap(find.text('Gremse Altın'));
    await tester.pumpAndSettle();
    expect(find.text('Altın Türleri'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Seçili altın türü: Gremse Altın')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
