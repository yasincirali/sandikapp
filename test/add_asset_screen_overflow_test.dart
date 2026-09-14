import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık ekleme ekranının taşma regresyonu.
///
/// `asset_card_overflow_test.dart` ile aynı kalıp: gerçek ekranı pump et,
/// veriyi provider override'larıyla besle, iç yapıyı değil dış davranışı
/// doğrula. TECHNICAL_DEBT "Widget test kapsamı" sırada bu ekranı sayıyordu:
/// 17 alanlı form, dört giriş modu (yeni, düzenleme, sepet, ön seçim) ve
/// tür seçicinin yatay çipleri — dar ekranda taşma riski en çok burada.
///
/// Fiyat araması `addAssetPriceLookupProvider` üzerinden sahteye bağlı: form
/// ticker değişince ağa çıkmaz, test ortamında sessizce `null` görür.

const _uid = 'user-1';

Asset _asset({
  required String name,
  required String ticker,
  AssetType type = AssetType.hisse,
  double qty = 100,
  double buy = 250.75,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: buy * 1.1,
      addedDate: DateTime(2026, 3, 14),
    );

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

/// Ağa çıkmayan fiyat araması — form "bulunamadı" dalını çizer.
class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  double width = 375,
  List<Asset> portfolio = const [],
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio(portfolio)),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final uzunAdli = _asset(
    name: 'Yapı Kredi Portföy Teknoloji Değişken Fon Uzun Adlı Ürün',
    ticker: 'TEFAS:YKT',
    type: AssetType.fon,
    qty: 486.948,
    buy: 0.814,
  );

  group('varlık ekle — taşma', () {
    for (final w in <double>[320, 360, 375, 390, 430]) {
      testWidgets('${w.toInt()}pt ekranda boş form', (tester) async {
        await _pump(tester, const AddAssetScreen(), width: w);
        expect(tester.takeException(), isNull,
            reason: '${w.toInt()}pt ekranda form taşıyor');
      });
    }

    testWidgets('düzenleme modu — uzun adlı fon, 320pt', (tester) async {
      await _pump(tester, AddAssetScreen(editingAsset: uzunAdli),
          width: 320, portfolio: [uzunAdli]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sepet modu, 320pt', (tester) async {
      await _pump(tester, const AddAssetScreen(cartMode: true), width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ön seçimle (karşılaştırmadan gelen), 320pt', (tester) async {
      await _pump(
        tester,
        const AddAssetScreen(
          prefillTicker: 'THYAO.IS',
          prefillName: 'Türk Hava Yolları Anonim Ortaklığı',
          prefillType: AssetType.hisse,
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('her tür seçildiğinde form taşmaz, 320pt', (tester) async {
      // Tür değişince alan kümesi değişir (fon: TEFAS kodu; döviz: para
      // birimi; altın: ürün seçici). Her dal en dar ekranda çizilmeli.
      for (final t in AssetType.values) {
        await _pump(tester, AddAssetScreen(prefillType: t), width: 320);
        expect(tester.takeException(), isNull, reason: t.name);
      }
    });

    testWidgets('dikey yer dar — 320×560', (tester) async {
      // Küçük telefon + klavye açık senaryosunun statik karşılığı: içerik
      // kaydırılabilir olmalı, sabit yükseklikli bir kolon taşmamalı.
      tester.view.physicalSize = const Size(320 * 3, 560 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portfolioProvider.overrideWith(() => _FakePortfolio(const [])),
            addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
          ],
          child: MaterialApp(
              theme: ThemeData.dark(), home: const AddAssetScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
