import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle sadeleşmesi (müşteri raporu 31 Eki 13:15, yasin "yap"):
/// arama başta, üç alternatif yol sonda tek kartta, mikrofon yok; kimse
/// seçmeden tür seçili görünmez; "Tekrar al" çipleri; boş maliyet kartı yok.

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _assets,
      ownerId: 'ben',
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0);
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

Asset _gram(double qty, int ay) {
  final g = GoldSubCategory.gr24;
  return Asset(
    id: 'g$ay',
    userId: 'ben',
    name: g.label,
    ticker: goldTickerMap[g.label]!,
    type: AssetType.altin,
    subCategory: g.label,
    unitType: g.unitType,
    quantity: qty,
    purchasePrice: 3000,
    currency: 'TRY',
    notes: '',
    addedDate: DateTime(2026, ay, 1),
  );
}

Future<void> _ac(WidgetTester tester,
    {List<Asset> varliklar = const [],
    Widget ekran = const AddAssetScreen(),
    double metinOlcegi = 1}) async {
  RemoteConfigService.testAcik = {};
  await initializeDateFormatting('tr_TR');
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => _Portfoy(varliklar)),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(metinOlcegi)),
        child: child!,
      ),
      home: ekran,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('yeni kayıt: tür ızgarası başta, üç yol sondaki kartta',
      (tester) async {
    await _ac(tester);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing,
        reason: 'Başlıktaki mikrofon kalktı.');
    expect(find.text('BAŞKA YOLDAN EKLE'), findsOneWidget);
    for (final t in [
      'Yazarak ekle',
      'Ekstreden aktar',
      'Ekran görüntüsünden ekle',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Kart tür seçicinin ALTINDA.
    final kart = tester.getTopLeft(find.text('BAŞKA YOLDAN EKLE')).dy;
    final tur = tester
        .getTopLeft(find.byWidgetPredicate(
            (w) => w is TourAnchor && w.target == TourTarget.turSecici))
        .dy;
    expect(kart, greaterThan(tur));
    // Tur hedefleri yeni yerlerinde kurulu.
    expect(
        find.byWidgetPredicate(
            (w) => w is TourAnchor && w.target == TourTarget.hizliGiris),
        findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is TourAnchor && w.target == TourTarget.topluEkle),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kimse seçmeden hiçbir tür seçili görünmez', (tester) async {
    final handle = tester.ensureSemantics();
    await _ac(tester);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Hisse türü')),
        isSemantics(isSelected: false));
    handle.dispose();
  });

  testWidgets('tekrar al: çipe dokununca tür ve altın türü seçilir',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _ac(tester, varliklar: [_gram(10, 9), _gram(12, 10)]);
    expect(find.text('TEKRAR AL'), findsOneWidget);
    final cip = find.bySemanticsLabel(
        RegExp(r'^Gram Altın \(24 Ayar\) tekrar al, son alım 12 gr'));
    expect(cip, findsOneWidget);
    await tester.tap(cip);
    await tester.pumpAndSettle();
    expect(find.text('TEKRAR AL'), findsNothing,
        reason: 'Seçimden sonra ızgara katlanır.');
    expect(
        tester.getSemantics(
            find.bySemanticsLabel(RegExp(r'^Gram Altın \(24 Ayar\) altın'))),
        isSemantics(isSelected: true));
    // Miktar forma yazılmaz (yanlış miktarla kayıt düşmesin).
    expect(find.widgetWithText(TextField, '12'), findsNothing);
    handle.dispose();
  });

  testWidgets('altını olmayan kullanıcıda tekrar al satırı yok',
      (tester) async {
    await _ac(tester);
    expect(find.text('TEKRAR AL'), findsNothing);
  });

  testWidgets('miktar boşken içeriksiz maliyet kartı çizilmez',
      (tester) async {
    await _ac(tester, ekran: const AddAssetScreen(prefillType: AssetType.altin));
    expect(find.text('Miktar girince toplam maliyet burada görünecek.'),
        findsNothing);
    // Altın türleri tek satırda; "Tümü" alt sayfayı açar.
    expect(find.text('Hızlı seçim'), findsNothing);
    await tester.tap(find.text('Tümü'));
    await tester.pumpAndSettle();
    expect(find.text('Altın Türleri'), findsOneWidget);
  });

  testWidgets('2× metin: tekrar al ve altın satırı taşmaz', (tester) async {
    await _ac(tester, varliklar: [_gram(10, 9)], metinOlcegi: 2);
    expect(tester.takeException(), isNull);
    final cip = find.bySemanticsLabel(RegExp(r'tekrar al, son alım'));
    expect(tester.getRect(cip).width, lessThan(375 * 0.75),
        reason: 'Uzun altın adı çipi ekrandan taşırmaz.');
    await tester.tap(cip);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
