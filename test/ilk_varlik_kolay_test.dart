import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ilk_varlik_secimi.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/social_sign_in_buttons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme 2, liste madde 4 (bayrak `ilk_varlik_kolay`) ve madde 1'in
/// kalanı (sosyal giriş en üstte, bayrak `karsilama_tanitimi`).
///
/// Değişmez: bayrak KAPALIYKEN form birebir eski (komisyon açıkta, iki yol
/// düğmesi yok). Açıkken ilk varlık "seç → miktar yaz" kadar kısa.

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
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

Future<void> _pump(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: ekran),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => RemoteConfigService.testAcik = {});

  group('IlkVarlikSecimi', () {
    test('altın, dolar, euro varlığıyla hazır; fon ve hisse yalnız tür', () {
      expect(IlkVarlikSecimi.gramAltin.tur, AssetType.altin);
      expect(IlkVarlikSecimi.dolar.dovizEtiketi, 'USD');
      expect(IlkVarlikSecimi.euro.dovizEtiketi, 'EUR');
      expect(IlkVarlikSecimi.fon.varlikHazir, isFalse);
      expect(IlkVarlikSecimi.hisse.varlikHazir, isFalse);
      expect(IlkVarlikSecimi.gramAltin.varlikHazir, isTrue);
      // Vitrin (2026-10-04): çeyrek altın da varlığıyla hazır; alt türü
      // formun `selectGold`'una giden enum.
      expect(IlkVarlikSecimi.ceyrekAltin.tur, AssetType.altin);
      expect(IlkVarlikSecimi.ceyrekAltin.varlikHazir, isTrue);
      expect(IlkVarlikSecimi.ceyrekAltin.altinAltTuru, GoldSubCategory.ceyrek);
      expect(IlkVarlikSecimi.gramAltin.altinAltTuru, GoldSubCategory.gr24);
      expect(IlkVarlikSecimi.dolar.altinAltTuru, isNull);
      // Döviz etiketi `dovizOptions`'ta olmalı; yoksa `dovizOptFor` sessizce
      // USD'ye düşer ve Euro seçen dolar kaydeder.
      for (final s in IlkVarlikSecimi.values) {
        final e = s.dovizEtiketi;
        if (e == null) continue;
        expect(dovizOptions.map((o) => o.label), contains(e));
      }
    });
  });

  group('Varlık Ekle hızlı seçimle', () {
    testWidgets('gram altın seçili açılır', (tester) async {
      await _pump(tester,
          const AddAssetScreen(hizliSecim: IlkVarlikSecimi.gramAltin));
      await tester.pump();
      expect(
          find.bySemanticsLabel(
              RegExp(r'Seçili altın türü: Gram Altın \(24 Ayar\)')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('çeyrek altın seçili açılır', (tester) async {
      await _pump(tester,
          const AddAssetScreen(hizliSecim: IlkVarlikSecimi.ceyrekAltin));
      await tester.pump();
      expect(
          find.bySemanticsLabel(RegExp(r'Seçili altın türü: Çeyrek Altın')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('euro seçili açılır', (tester) async {
      await _pump(
          tester, const AddAssetScreen(hizliSecim: IlkVarlikSecimi.euro));
      await tester.pump();
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^EUR'))),
          isSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^USD'))),
          isSemantics(isSelected: false));
    });
  });

  group('bayrak ilk_varlik_kolay', () {
    testWidgets('KAPALI: form eski — komisyon açıkta, iki yol yok',
        (tester) async {
      await _pump(tester, const AddAssetScreen());
      expect(find.text('Yazarak ekle'), findsNothing);
      expect(find.text('Ekstreden aktar'), findsNothing);
      expect(find.text('Komisyon / Masraf'), findsOneWidget);
      expect(find.text('Not ekle'), findsOneWidget);
    });

    testWidgets('AÇIK: iki yol görünür, komisyon "Ayrıntı ekle" altında',
        (tester) async {
      RemoteConfigService.testAcik = {'ilk_varlik_kolay'};
      await _pump(tester, const AddAssetScreen());
      expect(find.text('Yazarak ekle'), findsOneWidget);
      expect(find.text('Ekstreden aktar'), findsOneWidget);
      expect(find.text('Not ekle'), findsNothing);
      final ayrinti = find.text('Ayrıntı ekle (komisyon, not)');
      expect(ayrinti, findsOneWidget);

      await tester.ensureVisible(ayrinti);
      await tester.tap(ayrinti);
      await tester.pumpAndSettle();
      expect(find.text('Komisyon / Masraf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AÇIK ama düzenleme: form eski', (tester) async {
      RemoteConfigService.testAcik = {'ilk_varlik_kolay'};
      await _pump(
          tester,
          AddAssetScreen(
            editingAsset: Asset(
              id: 'a1',
              userId: 'u1',
              name: 'ABD Doları',
              ticker: 'USDTRY=X',
              type: AssetType.doviz,
              subCategory: 'USD',
              unitType: 'piece',
              quantity: 10,
              purchasePrice: 40,
              currency: 'TRY',
              notes: '',
              isManualPrice: false,
              addedDate: DateTime(2026, 3, 14),
            ),
          ));
      expect(find.text('Yazarak ekle'), findsNothing);
      expect(find.text('Komisyon / Masraf'), findsOneWidget);
    });
  });

  group('sosyal giriş düzeni', () {
    Future<void> sosyal(WidgetTester tester, {required bool ustte}) =>
        tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SocialSignInButtons(
                ustte: ustte,
                platformOverride: TargetPlatform.iOS,
                googleConfiguredOverride: true,
              ),
            ),
          ),
        ));

    testWidgets('altta (eski): ayırıcı "veya" düğmelerin üstünde',
        (tester) async {
      await sosyal(tester, ustte: false);
      expect(find.text('veya'), findsOneWidget);
      expect(find.text('veya e-postayla'), findsNothing);
      final ayirici = tester.getTopLeft(find.text('veya')).dy;
      final dugme = tester.getTopLeft(find.textContaining('Apple')).dy;
      expect(ayirici, lessThan(dugme));
    });

    testWidgets('üstte: düğmeler önce, "veya e-postayla" altta',
        (tester) async {
      await sosyal(tester, ustte: true);
      expect(find.text('veya e-postayla'), findsOneWidget);
      final ayirici = tester.getTopLeft(find.text('veya e-postayla')).dy;
      final dugme = tester.getTopLeft(find.textContaining('Apple')).dy;
      expect(ayirici, greaterThan(dugme));
    });
  });
}
