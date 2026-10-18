import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/emtia_katalogu.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle › Emtia listeden seçilir (2026-10-18, yasin: "emtia
/// seçenekleri listelense, free text yerine"). Kilitlenenler:
///   · katalog ölçeği: yalnız USD/birim kote vadeliler (sent kote tahıl yok);
///   · arama ile form aynı listeyi kullanır (tek kaynak);
///   · seçim yapılmadan kayıt yok; "Diğer" eski serbest girişi açar ve
///     listeden gelen adı taşımaz;
///   · eski kayıt (listede olmayan sembol / serbest ad) "Diğer"de açılır;
///   · dar ekran ve büyük yazıda taşma yok, çipler 44pt.

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: const [], usdTry: 42, eurTry: 46, gbpTry: 54);
}

Asset _emtia(String name, String ticker) => Asset(
      id: 'e1',
      userId: 'u',
      name: name,
      ticker: ticker,
      type: AssetType.emtia,
      quantity: 10,
      purchasePrice: 30,
      currency: 'USD',
      notes: '',
      isManualPrice: ticker.isEmpty,
      currentPrice: 31,
      addedDate: DateTime(2026, 3, 14),
    );

Future<void> _pump(WidgetTester tester, Widget screen,
    {double width = 390, double olcek = 1.0}) async {
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
    ],
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
      child: MaterialApp(theme: ThemeData.dark(), home: screen),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('katalog', () {
    test('semboller tekil, hepsi USD kote Yahoo vadelisi', () {
      final s = emtiaKatalogu.map((e) => e.ticker).toList();
      expect(s.toSet().length, s.length);
      for (final t in s) {
        expect(t, endsWith('=F'));
      }
      // Sent kote vadeliler (tahıl, kahve, şeker) 100 kat ölçek hatası.
      for (final sent in ['ZW=F', 'ZC=F', 'ZS=F', 'KC=F', 'SB=F', 'CT=F']) {
        expect(emtiaSecenegi(sent), isNull, reason: sent);
      }
    });

    test('arama ile form aynı listeyi kullanır', () async {
      final hits = await SymbolSearchService.instance.search('brent');
      expect(hits.map((h) => h.ticker), contains('BZ=F'));
      for (final e in emtiaKatalogu) {
        final r = await SymbolSearchService.instance.search(e.ad);
        expect(r.map((h) => h.ticker), contains(e.ticker), reason: e.ad);
      }
    });
  });

  group('form durumu', () {
    test('yeni emtia: seçim yokken kimlik eksik', () {
      final s = AddAssetFormState.initial(prefillType: AssetType.emtia);
      expect(s.emtiaElle, isFalse);
      expect(s.kimlikEksigi(tickerText: ''), KimlikEksigi.emtia);
      expect(s.kimlikEksigi(tickerText: 'SI=F'), isNull);
    });

    test('listede olmayan eski kayıt Diğer yolunda açılır', () {
      expect(
          AddAssetFormState.initial(editingAsset: _emtia('Kakao', 'CC=F'))
              .emtiaElle,
          isTrue);
      expect(
          AddAssetFormState.initial(editingAsset: _emtia('petrol', ''))
              .emtiaElle,
          isTrue);
      expect(
          AddAssetFormState.initial(editingAsset: _emtia('Gümüş', 'SI=F'))
              .emtiaElle,
          isFalse);
    });

    test('seçim ad + sembolü yazar; Diğer listeden geleni temizler', () {
      final c = ProviderContainer(overrides: [
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ]);
      addTearDown(c.dispose);
      final args = AddAssetFormArgs(prefillType: AssetType.emtia);
      final n = c.read(addAssetFormProvider(args).notifier);
      final y = n.selectEmtia(emtiaSecenegi('BZ=F')!);
      expect((y.name, y.ticker), ('Petrol (Brent)', 'BZ=F'));
      expect(c.read(addAssetFormProvider(args)).isManualPrice, isFalse);

      final d = n.emtiaDiger(tickerText: 'BZ=F');
      expect((d.name, d.ticker), ('', ''));
      final s = c.read(addAssetFormProvider(args));
      expect(s.emtiaElle, isTrue);
      expect(s.kimlikEksigi(tickerText: ''), isNull,
          reason: 'Diğer yolunda ad alanının kendi doğrulayıcısı var');
    });
  });

  group('ekran', () {
    testWidgets('serbest metin yok, çipler var; Diğer serbest girişi açar',
        (tester) async {
      await _pump(tester,
          const AddAssetScreen(prefillType: AssetType.emtia));
      expect(find.textContaining('Gümüş', findRichText: true), findsOneWidget);
      expect(find.textContaining('Diğer (sembol yaz)', findRichText: true),
          findsOneWidget);
      expect(find.byType(TextFormField).evaluate().length, lessThan(5),
          reason: 'ad/sembol alanları Diğer seçilmeden çizilmez');
      final once = find.byType(TextFormField).evaluate().length;
      await tester.tap(
          find.textContaining('Diğer (sembol yaz)', findRichText: true));
      await tester.pump();
      expect(find.byType(TextFormField).evaluate().length, once + 2);
    });

    for (final (w, olcek) in const [(320.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
      testWidgets('${w.toInt()}pt, $olcek× yazı: taşma yok, çip ≥44',
          (tester) async {
        await _pump(tester, const AddAssetScreen(prefillType: AssetType.emtia),
            width: w, olcek: olcek);
        expect(tester.takeException(), isNull);
        final cip = find
            .ancestor(of: find.textContaining('Doğalgaz', findRichText: true), matching: find.byType(ConstrainedBox))
            .first;
        expect(tester.getSize(cip).height, greaterThanOrEqualTo(44));
      });
    }
  });
}
