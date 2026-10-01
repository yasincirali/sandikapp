import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/tefas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    String? sozlesmeId,
  }) async {
    ekleme++;
  }
}

class _SabitFiyat implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 10.0;
  @override
  Future<String?> companyName(String ticker) async => 'Şirket';
}

/// Varlık seçilmeden kayıt yok (kullanıcı bildirimi 2026-09-29).
///
/// Hisse seçmeden "Ekle" adsız, sembolsüz bir lot yazıyordu; altın ve döviz
/// hiç doğrulanmıyordu. Kural `AddAssetFormState.kimlikEksigi`'nde; ekran
/// onu tek bir FormField ile satır içi uyarıya çevirir.
void main() {
  AddAssetFormState bos(AssetType t) =>
      AddAssetFormState.initial(prefillType: t, now: DateTime(2026, 9, 29));

  group('seçilmemiş varlık kaydı engeller', () {
    test('hisse: ne BIST seçimi ne sembol', () {
      expect(bos(AssetType.hisse).kimlikEksigi(tickerText: ''),
          KimlikEksigi.hisse);
      expect(bos(AssetType.hisse).kimlikEksigi(tickerText: '   '),
          KimlikEksigi.hisse);
    });

    test('fon, altın, döviz, kripto', () {
      expect(bos(AssetType.fon).kimlikEksigi(tickerText: ''), KimlikEksigi.fon);
      expect(bos(AssetType.altin).kimlikEksigi(tickerText: ''),
          KimlikEksigi.altin);
      expect(bos(AssetType.doviz).kimlikEksigi(tickerText: ''),
          KimlikEksigi.doviz);
      expect(bos(AssetType.kripto).kimlikEksigi(tickerText: ''),
          KimlikEksigi.kripto);
    });

    test('emtia serbest adlıdır — kuralı ad alanında', () {
      expect(bos(AssetType.emtia).kimlikEksigi(tickerText: ''), isNull);
    });

    test('düzenleme muaf: eski sembolsüz kayıt düzeltilebilir', () {
      expect(
          bos(AssetType.hisse).kimlikEksigi(tickerText: '', muaf: true), isNull);
    });
  });

  group('seçim yapılınca geçer', () {
    ProviderContainer kur() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('hisse: elle yazılan sembol', () {
      final c = kur();
      final args = AddAssetFormArgs();
      c.read(addAssetFormProvider(args).notifier).tickerTyped('THYAO');
      expect(
          c.read(addAssetFormProvider(args)).kimlikEksigi(tickerText: 'THYAO'),
          isNull);
    });

    test('hisse: sembol yazılıp silinse bile sonraki BIST seçimi geçer', () {
      // Silinen sembol elle fiyat bayrağını açıyordu; seçim bayrağı
      // indirmezse `resolveIdentity` seçilen hisseyi boş sembolle yazardı.
      final c = kur();
      final args = AddAssetFormArgs();
      final n = c.read(addAssetFormProvider(args).notifier);
      n.tickerTyped('X');
      n.tickerTyped('');
      final y = n.selectBist100('THYAO.IS');
      final s = c.read(addAssetFormProvider(args));
      expect(s.kimlikEksigi(tickerText: y.ticker!), isNull);
      expect(
          s.resolveIdentity(nameText: '', tickerText: y.ticker!).ticker,
          'THYAO.IS');
    });

    test('altın, döviz, fon', () {
      final c = kur();
      final altin = AddAssetFormArgs(prefillType: AssetType.altin);
      c.read(addAssetFormProvider(altin).notifier)
          .selectGold(GoldSubCategory.values.first);
      expect(c.read(addAssetFormProvider(altin)).kimlikEksigi(tickerText: ''),
          isNull);

      final doviz = AddAssetFormArgs(prefillType: AssetType.doviz);
      final y = c
          .read(addAssetFormProvider(doviz).notifier)
          .selectDoviz(dovizOptions.first);
      expect(
          c
              .read(addAssetFormProvider(doviz))
              .kimlikEksigi(tickerText: y.ticker ?? ''),
          isNull);

      final fon = AddAssetFormArgs(prefillType: AssetType.fon);
      c.read(addAssetFormProvider(fon).notifier).selectFund(
            TefasFund(
                code: 'AFT',
                name: 'Ak Portföy',
                price: 1,
                fundType: '',
                managerName: ''),
            priceEmpty: true,
          );
      expect(
          c.read(addAssetFormProvider(fon)).kimlikEksigi(tickerText: ''), isNull);
    });
  });

  group('ekran: satır içi uyarı', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('hisse seçmeden "Ekle" kaydetmez, uyarı alanın altında',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final portfoy = _SayanPortfoy();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => portfoy),
          addAssetPriceLookupProvider.overrideWithValue(_SabitFiyat()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const AddAssetScreen(),
        ),
      ));
      await tester.pump();

      // Açılışta uyarı yok — boş form suçlanmaz.
      const uyari = 'Listeden bir hisse seç ya da sembolünü yaz';
      expect(find.text(uyari), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, '0').first, '5');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
      await tester.pumpAndSettle();

      expect(portfoy.ekleme, 0, reason: 'Hisse seçilmeden kayıt yazıldı');
      expect(find.text(uyari), findsOneWidget);

      // Sembol yazılınca uyarı bir sonraki dokunuşu beklemeden kalkar.
      await tester.enterText(find.byType(TextFormField).first, 'THYAO');
      await tester.pump();
      expect(find.text(uyari), findsNothing);
    });
  });
}
