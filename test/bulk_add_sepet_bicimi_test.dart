import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/bulk_add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toplu ekleme sepeti Türkçe sayı biçimi — 2026-09-23 yeniden testi.
///
/// **Yakalanan hata:** sepet satırı `double.toString()` kullanıyordu;
/// CSV'den gelen `1.234,75` fiyat sepette "1234.75 TRY" okunuyordu, aynı
/// sayı Ekle formunda "1.234,75" görünüyordu. Tek ekranda iki biçim.

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sepet satırı adet ve fiyatı Türkçe biçimde gösterir',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_BosPortfoy.new),
    ]);
    addTearDown(container.dispose);
    container.read(bulkCartProvider.notifier).add(BulkCartItem(
          id: 'x',
          type: AssetType.diger,
          name: 'Deneme',
          ticker: '',
          quantity: 0.125,
          price: 1234.75,
          currency: 'TRY',
          addedDate: DateTime(2024, 2, 1),
          isManualPrice: true,
        ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const BulkAddAssetScreen(),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('0,125'), findsOneWidget);
    expect(find.textContaining('1.234,75 TRY'), findsOneWidget);
    expect(find.textContaining('1234.75'), findsNothing);
  });
}
