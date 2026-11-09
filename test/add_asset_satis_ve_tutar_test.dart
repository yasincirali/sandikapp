import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ilk_varlik_secimi.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle formu, Ar-Ge raporu 2026-10-24 §1 (boş fiyatlı altın/döviz
/// maliyeti satıştan + kuyumcu farkı satırı) ve §2 (Adet / Tutar kipi).

typedef _Kayit = ({double quantity, double price, String ticker});

class _KaydedenPortfoy extends PortfolioNotifier {
  final kayitlar = <_Kayit>[];

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
    String? portfoyId,
    String yol = 'form',
    bool maliyetBilinmiyor = false,
  }) async {
    kayitlar.add((quantity: quantity, price: purchasePrice, ticker: ticker));
  }
}

/// Alış 3000, satış 3100 veren kapı (gram altın).
class _SatisliKapi implements AddAssetPriceLookup, SatisFiyatiOkuyucu {
  @override
  Future<AlisSatis?> alisSatis(String ticker) async =>
      (alis: 3000.0, satis: 3100.0);
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 3000;
  @override
  Future<String?> companyName(String ticker) async => null;
}

/// Satış bilmeyen kapı: spot sabit.
class _SpotKapi implements AddAssetPriceLookup {
  _SpotKapi(this.fiyat);
  final double fiyat;
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => fiyat;
  @override
  Future<String?> companyName(String ticker) async => 'Şirket';
}

Future<_KaydedenPortfoy> _ac(
  WidgetTester tester, {
  required AddAssetPriceLookup kapi,
  required AddAssetScreen ekran,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final portfoy = _KaydedenPortfoy();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => portfoy),
      addAssetPriceLookupProvider.overrideWithValue(kapi),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => ekran)),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return portfoy;
}

Future<void> _ekle(WidgetTester tester) async {
  final ekle = find.widgetWithText(FilledButton, 'Ekle');
  await tester.ensureVisible(ekle);
  await tester.tap(ekle);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('§1 boş fiyatlı altın: maliyet satıştan', () {
    testWidgets('kuyumcu farkı satırı görünür, kayıt satış fiyatıyla',
        (tester) async {
      final portfoy = await _ac(tester,
          kapi: _SatisliKapi(),
          ekran: const AddAssetScreen(hizliSecim: IlkVarlikSecimi.gramAltin));

      // Miktar yokken birim başına.
      expect(find.text('3.100 TRY / birim'), findsOneWidget);
      expect(
          find.text('Kuyumcu farkı %3,2. Bugün bozdursan ₺3.000,00 / birim.'),
          findsOneWidget);
      expect(find.textContaining('Zarar'), findsNothing,
          reason: 'satır "zarardasın" demez');

      await tester.enterText(find.widgetWithText(TextField, '0').first, '2');
      await tester.pump();
      expect(find.text('Kuyumcu farkı %3,2. Bugün bozdursan ₺6.000,00.'),
          findsOneWidget);

      await _ekle(tester);
      expect(portfoy.kayitlar, hasLength(1));
      expect(portfoy.kayitlar.single.price, 3100);
      expect(portfoy.kayitlar.single.quantity, 2);
    });

    testWidgets('elle fiyat yazılınca satır gider, yazılan fiyat kaydedilir',
        (tester) async {
      final portfoy = await _ac(tester,
          kapi: _SatisliKapi(),
          ekran: const AddAssetScreen(hizliSecim: IlkVarlikSecimi.gramAltin));
      await tester.enterText(find.widgetWithText(TextField, '0').first, '2');
      // 2026-10-31: boş fiyat alanının ipucu "Otomatik" değil, kayıtta
      // atanacak satış fiyatının kendisi.
      await tester.enterText(
          find.widgetWithText(TextField, '₺3.100,00'), '2950');
      await tester.pump();
      expect(find.textContaining('Kuyumcu farkı'), findsNothing);

      await _ekle(tester);
      expect(portfoy.kayitlar.single.price, 2950);
    });

    testWidgets('satış gelmeyen kaynakta bugünkü davranış: satır yok',
        (tester) async {
      final portfoy = await _ac(tester,
          kapi: _SpotKapi(3000),
          ekran: const AddAssetScreen(hizliSecim: IlkVarlikSecimi.gramAltin));
      expect(find.textContaining('Kuyumcu farkı'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, '0').first, '2');
      await tester.pump();
      await _ekle(tester);
      expect(portfoy.kayitlar.single.price, 3000);
    });
  });

  group('§2 Adet / Tutar kipi', () {
    testWidgets('varsayılan Adet; tutar girince adet yuvarlanmadan hesaplanır',
        (tester) async {
      final portfoy = await _ac(tester,
          kapi: _SpotKapi(3),
          ekran: const AddAssetScreen(
              prefillTicker: 'AAPL', prefillType: AssetType.hisse));

      expect(find.text('Adet'), findsOneWidget);
      expect(find.text('Tutar (₺)'), findsOneWidget);
      expect(find.text('Miktar'), findsOneWidget,
          reason: 'varsayılan kip Adet: form bugünkü gibi');

      await tester.tap(find.text('Tutar (₺)'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(
          find.widgetWithText(TextField, '0').first, '1.000');
      await tester.pump();
      expect(find.textContaining('Hesaplanan miktar: 333,33333333'),
          findsOneWidget);

      await _ekle(tester);
      expect(portfoy.kayitlar, hasLength(1));
      expect(portfoy.kayitlar.single.quantity, closeTo(1000 / 3, 1e-9),
          reason: 'adet kırpılmaz');
      expect(portfoy.kayitlar.single.price, 3);
    });

    testWidgets('Adet\'e dönünce hesaplanan adet alana yazılır',
        (tester) async {
      await _ac(tester,
          kapi: _SpotKapi(4),
          ekran: const AddAssetScreen(
              prefillTicker: 'AAPL', prefillType: AssetType.hisse));
      await tester.tap(find.text('Tutar (₺)'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(find.widgetWithText(TextField, '0').first, '10');
      await tester.pump();
      await tester.tap(find.text('Adet'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.widgetWithText(TextField, '2,5'), findsOneWidget);
    });

    testWidgets('fiyat yoksa adet hesaplanmaz ve kayıt gitmez', (tester) async {
      final portfoy = await _ac(tester,
          kapi: _SpotKapi(0),
          ekran: const AddAssetScreen(
              prefillTicker: 'AAPL', prefillType: AssetType.hisse));
      await tester.tap(find.text('Tutar (₺)'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(find.widgetWithText(TextField, '0').first, '1000');
      await tester.pump();
      expect(find.textContaining('Hesaplanan miktar'), findsNothing);

      await _ekle(tester);
      expect(portfoy.kayitlar, isEmpty);
      expect(find.text('Adet için fiyat gerekli'), findsOneWidget);
    });

    testWidgets('fonda tek satır ipucu', (tester) async {
      await _ac(tester,
          kapi: _SpotKapi(2),
          ekran: const AddAssetScreen(hizliSecim: IlkVarlikSecimi.fon));
      await tester.tap(find.text('Tutar (₺)'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.textContaining('Bankadaki adet farklıysa adedi düzelt'),
          findsOneWidget);
    });
  });
}
