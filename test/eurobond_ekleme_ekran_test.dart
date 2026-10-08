import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/eurobond_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eurobond ekleme akışı ekranda (bayrak `eurobond`, 2026-10-08): katalog
/// seçicisi, seçilmeden kayıt yok, temiz fiyat ön dolumu, işlemiş faiz
/// satırı ve kayıtta KİRLİ birim değer.
class _KaydedenPortfoy extends PortfolioNotifier {
  final kayitlar = <({String ticker, double fiyat, String para, double miktar})>[];

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
    String? sozlesmeId,
  }) async {
    kayitlar.add((
      ticker: ticker,
      fiyat: purchasePrice,
      para: currency,
      miktar: quantity,
    ));
  }
}

class _AgYok implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

final _tr28 = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Türkiye %9,875 2028',
  paraBirimi: 'USD',
  kuponOrani: 0.09875,
  vade: DateTime.utc(2028, 1, 15),
  ihracTarihi: DateTime.utc(2018, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

final _eur = EurobondSozlesmesi(
  isin: 'XS1234567896',
  ad: 'Türkiye EUR 2029',
  paraBirimi: 'EUR',
  kuponOrani: 0.04,
  vade: DateTime.utc(2029, 6, 1),
  ihracTarihi: DateTime.utc(2019, 6, 1),
  ihracci: EurobondIhracci.hazine,
  yillikKuponSayisi: 1,
);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfigService.testAcik = {'eurobond'};
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('seçici, uyarı, ön dolum ve kirli birim değerle kayıt',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final portfoy = _KaydedenPortfoy();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => portfoy),
        addAssetPriceLookupProvider.overrideWithValue(_AgYok()),
        eurobondKatalogProvider.overrideWith((ref) async => [
              (
                _tr28,
                EurobondFiyati(
                    isin: _tr28.isin,
                    temizFiyat: 104.125,
                    guncellendi: DateTime.utc(2026, 10, 8)),
              ),
              (_eur, null),
            ]),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        home: const AddAssetScreen(prefillType: AssetType.eurobond),
      ),
    ));
    await tester.pump();

    // Kimlik alanı katalog seçicisi; birim nominal.
    expect(find.text('Tahvil seçmek için dokun'), findsOneWidget);
    expect(find.text('10.000'), findsOneWidget, reason: 'nominal ön ayarı');

    // Seçmeden "Ekle": kayıt yok, satır içi uyarı.
    await tester.enterText(find.widgetWithText(TextField, '0').first, '10000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await tester.pumpAndSettle();
    expect(portfoy.kayitlar, isEmpty);
    expect(find.text('Bir eurobond seç'), findsOneWidget);

    // Seçici: yalnız USD tahvil.
    await tester.tap(find.text('Tahvil seçmek için dokun'));
    await tester.pumpAndSettle();
    expect(find.text('Türkiye %9,875 2028'), findsOneWidget);
    expect(find.text('Türkiye EUR 2029'), findsNothing,
        reason: 'EUR tahvil seriye giremez — seçicide sunulmaz');

    // Hatalı ISIN nedeniyle söylenir.
    await tester.enterText(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(TextField)),
        'US900123DF46');
    await tester.pump();
    expect(find.textContaining('kontrol hanesi'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(TextField)),
        'US900123DF45');
    await tester.pump();
    await tester.tap(find.text('Türkiye %9,875 2028'));
    await tester.pumpAndSettle();

    // Seçim formda; temiz fiyat ön doldu, uyarı kalktı, faiz satırı var.
    expect(find.text('Türkiye %9,875 2028'), findsOneWidget);
    expect(find.text('Bir eurobond seç'), findsNothing);
    expect(find.widgetWithText(TextFormField, '104,125'), findsOneWidget);
    expect(find.textContaining('İşlemiş faiz:'), findsOneWidget);
    expect(find.textContaining('Ödenen:'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await tester.pumpAndSettle();

    expect(portfoy.kayitlar, hasLength(1));
    final k = portfoy.kayitlar.single;
    expect(k.ticker, 'EUROBOND:US900123DF45');
    expect(k.para, 'USD');
    expect(k.miktar, 10000);
    expect(k.fiyat,
        closeTo(eurobondBirimDegeri(_tr28, 104.125, DateTime.now()), 1e-9),
        reason: 'kayıt temiz % değil, kirli/100 birim değer');
  });

  testWidgets('bayrak kapalıyken tür çipi yok', (tester) async {
    RemoteConfigService.testAcik = {};
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _KaydedenPortfoy()),
        addAssetPriceLookupProvider.overrideWithValue(_AgYok()),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        home: const AddAssetScreen(),
      ),
    ));
    await tester.pump();
    expect(find.text('Eurobond'), findsNothing);
  });
}
