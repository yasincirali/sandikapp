import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık ekleme ekranında klavye davranışı (kullanıcı, 2026-09-25):
/// "klavye otomatik açılmamalı, textbox'a tıklayınca açmalı, dışarı
/// tıklandığında da kapatılabilmeli." Ekranın kendisi ve hızlı giriş
/// sayfası açılışta klavye açmaz; alana dokununca açılır; alanın dışına
/// (başlık, etiket, boşluk) dokununca kapanır.
///
/// Kurulum `add_asset_screen_overflow_test.dart` ile aynı: gerçek ekran,
/// provider override'ları, ağa çıkmayan fiyat araması.

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

  group('varlık ekle — klavye', () {
    testWidgets('açılışta klavye açılmaz', (tester) async {
      await _pump(tester, const AddAssetScreen());
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });

    testWidgets('alana dokununca açılır, dışarı dokununca kapanır',
        (tester) async {
      await _pump(tester, const AddAssetScreen());
      await tester.pumpAndSettle();

      final alan = find.byType(TextFormField).first;
      await tester.ensureVisible(alan);
      await tester.pumpAndSettle();
      await tester.tap(alan);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Uygulama çubuğu başlığı: alanın dışında, kendi dokunma işleyicisi
      // olmayan bir yüzey.
      await tester.tapAt(const Offset(200, 30));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<EditableText>()));
    });

    testWidgets('hızlı giriş sayfası klavyeyi kendiliğinden açmaz',
        (tester) async {
      await _pump(tester, const AddAssetScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });
}
