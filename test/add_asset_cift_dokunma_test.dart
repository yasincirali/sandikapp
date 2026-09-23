import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Ekle"ye çift dokunuş — 2026-09-23 denetimi F14.
///
/// **Yakalanan hata:** `saving` bayrağı fiyat çözümünün `finally`'sinde
/// iniyor, ardından korumasız şirket adı sorgusu başlıyordu. Sorgu sürerken
/// buton yeniden etkinleşiyor; ikinci dokunuş ikinci bir `_save` başlatıp
/// aynı varlığı iki kez ekliyordu.
///
/// Sözleşme: bayrak doğrulamadan hemen sonra açılır ve kayıt bitene kadar
/// inmez; kayıt boyunca kaç dokunuş gelirse gelsin tek insert yapılır.

class _SayanPortfoy extends PortfolioNotifier {
  int ekleme = 0;

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
  }) async {
    ekleme++;
  }
}

/// Şirket adı sorgusu elle tamamlanana kadar askıda kalır — açık pencere
/// tam olarak burasıydı.
class _AskidaAd implements AddAssetPriceLookup {
  final ad = Completer<String?>();
  int adSorgusu = 0;

  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 10.0;
  @override
  Future<String?> companyName(String ticker) {
    adSorgusu++;
    return ad.future;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ad sorgusu sürerken ikinci dokunuş ikinci kayıt açmaz',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final portfoy = _SayanPortfoy();
    final lookup = _AskidaAd();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => portfoy),
        addAssetPriceLookupProvider.overrideWithValue(lookup),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        // `.IS` olmayan sembol: BIST100 seçicisine düşmez, ad boş kalır ve
        // kayıt şirket adını sorgular.
        home: const AddAssetScreen(
          prefillTicker: 'AAPL',
          prefillType: AssetType.hisse,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Miktar alanı: ipucu '0' olan ilk alan.
    await tester.enterText(find.widgetWithText(TextField, '0').first, '5');
    await tester.pump();

    final ekle = find.widgetWithText(FilledButton, 'Ekle');
    expect(ekle, findsOneWidget);
    await tester.tap(ekle);
    await tester.pump();
    await tester.pump();

    // Ad sorgusu askıda: buton kilitli olmalı (etiket yerine spinner).
    expect(lookup.adSorgusu, 1);
    final buton = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(buton.onPressed, isNull,
        reason: 'Ad sorgusu sürerken "Ekle" yeniden etkinleşti');

    // Yine de bas: kilitli butona ve doğrudan çağrıya karşı.
    await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
    await tester.pump();
    expect(lookup.adSorgusu, 1, reason: 'İkinci dokunuş ikinci kayıt açtı');

    lookup.ad.complete('Apple Inc.');
    await tester.pumpAndSettle();

    expect(portfoy.ekleme, 1, reason: 'Aynı varlık iki kez eklendi');
  });
}
