import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle vazgeç onayı (2026-10-20 incelemesi, HIG §6 "gerçek risk").
///
/// Yarım girilmiş miktar geri/kaydırma ile sessizce kayboluyordu. Sözleşme:
/// temiz form tek geri hareketiyle kapanır; kullanıcı bir şey yazdıysa önce
/// sorulur, "Düzenlemeye dön" formda bırakır, "Sil ve çık" kapatır.

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

class _SabitFiyat implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 10.0;
  @override
  Future<String?> companyName(String ticker) async => null;
}

Future<void> _ac(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(_BosPortfoy.new),
      addAssetPriceLookupProvider.overrideWithValue(_SabitFiyat()),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const AddAssetScreen(
                  prefillTicker: 'AAPL',
                  prefillType: AssetType.hisse,
                ),
              )),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  expect(find.byType(AddAssetScreen), findsOneWidget);
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('temiz form geri hareketiyle sormadan kapanır', (tester) async {
    await _ac(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AddAssetScreen), findsNothing);
  });

  testWidgets('miktar girildiyse önce sorulur', (tester) async {
    await _ac(tester);
    await tester.enterText(find.widgetWithText(TextField, '0').first, '5');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Girdiklerin silinsin mi?'), findsOneWidget);

    await tester.tap(find.text('Düzenlemeye dön'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AddAssetScreen), findsOneWidget,
        reason: '"Düzenlemeye dön" formu kapattı');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Sil ve çık'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AddAssetScreen), findsNothing);
  });
}
