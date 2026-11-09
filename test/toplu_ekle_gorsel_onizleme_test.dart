@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/bulk_add_asset_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toplu Ekle — ekran görüntüsünden ekleme (2026-10-19) GÖRSEL önizlemesi,
/// `build/gorsel/` altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/toplu_ekle_gorsel_onizleme_test.dart

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
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

class _Sepet extends BulkCartNotifier {
  _Sepet(this.ilk);
  final List<BulkCartItem> ilk;
  @override
  List<BulkCartItem> build() => ilk;
}

/// DEMO satırlar (gerçek kişi verisi değil).
List<BulkCartItem> _demo() {
  final b = DateTime.now();
  BulkCartItem k(String id, String ad, String t, double adet, double fiyat,
          {AssetType tur = AssetType.hisse, bool sonra = false}) =>
      BulkCartItem(
        id: id,
        type: tur,
        name: ad,
        ticker: t,
        quantity: adet,
        price: fiyat,
        currency: 'TRY',
        addedDate: b,
        maliyetSonra: sonra,
      );
  return [
    k('1', 'Türk Hava Yolları', 'THYAO.IS', 100, 250),
    k('2', 'Aselsan', 'ASELS.IS', 1250, 0, sonra: true),
    k('3', 'Marmara Capital Hisse Fonu', 'TEFAS:MAC', 3400, 0,
        tur: AssetType.fon, sonra: true),
  ];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Future<void> ciz(WidgetTester tester, String ad,
      {List<BulkCartItem> sepet = const [],
      bool acik = false,
      double olcek = 1.0,
      Widget ekran = const BulkAddAssetScreen()}) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        bulkCartProvider.overrideWith(() => _Sepet(sepet)),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: acik
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: child!,
          ),
          home: ekran,
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('boş sepet koyu', (t) => ciz(t, 'toplu_bos_koyu'));
  testWidgets('boş sepet açık', (t) => ciz(t, 'toplu_bos_acik', acik: true));
  testWidgets('boş sepet yazı 2x', (t) => ciz(t, 'toplu_bos_2x', olcek: 2));
  testWidgets('dolu sepet koyu', (t) => ciz(t, 'toplu_dolu_koyu', sepet: _demo()));
  testWidgets('dolu sepet açık',
      (t) => ciz(t, 'toplu_dolu_acik', sepet: _demo(), acik: true));
  testWidgets('dolu sepet yazı 2x',
      (t) => ciz(t, 'toplu_dolu_2x', sepet: _demo(), olcek: 2));
  testWidgets('varlık ekle formu koyu',
      (t) => ciz(t, 'varlik_ekle_koyu', ekran: const AddAssetScreen()));
  testWidgets('varlık ekle formu yazı 2x',
      (t) => ciz(t, 'varlik_ekle_2x', ekran: const AddAssetScreen(), olcek: 2));
}
