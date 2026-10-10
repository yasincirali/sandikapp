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
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/varlik_guncelle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Varlığı güncelle"nin GÖRSEL önizlemesi — `build/gorsel/` altına PNG,
/// önce/sonra için. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/varlik_guncelle_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur; canlı veri değildir.
const _uid = 'u1';
final _bist = StockSubCategory.bist100.label;

Asset _lot(String id, String ticker, String ad, AssetType tur, double adet,
        double fiyat,
        {AssetKind kind = AssetKind.buy, DateTime? tarih, String? sub}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
      subCategory: sub,
      quantity: adet,
      purchasePrice: fiyat * 0.9,
      sellPrice: kind == AssetKind.sell ? fiyat : null,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      kind: kind,
      addedDate: tarih ?? DateTime(2025, 3, 14),
    );

final _varliklar = [
  _lot('1', 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 400, 312.4,
      sub: _bist),
  _lot('1b', 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 150, 290,
      tarih: DateTime(2025, 6, 2), sub: _bist),
  _lot('1c', 'THYAO.IS', 'Türk Hava Yolları', AssetType.hisse, 50, 330,
      kind: AssetKind.sell, tarih: DateTime(2025, 9, 9), sub: _bist),
  _lot('2', 'ASELS.IS', 'Aselsan', AssetType.hisse, 600, 142.6),
  _lot('6', 'ALTIN_GRAM', 'Gram Altın', AssetType.altin, 6, 4300),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _varliklar, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
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
  tearDown(() => RemoteConfigService.testAcik = {});

  Future<void> ciz(
    WidgetTester tester,
    String ad,
    Widget ekran, {
    VarlikGuncellemeDurumu durum = VarlikGuncellemeDurumu.acik,
    Future<void> Function()? sonra,
    bool acik = false,
    double genislik = 390,
    double yukseklik = 844,
    double yazi = 1.0,
  }) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    tester.view.physicalSize = Size(genislik * 2, yukseklik * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        watchlistProvider.overrideWith(_Takip.new),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
        varlikGuncellemeProvider.overrideWithValue(durum),
      ],
      child: RepaintBoundary(
        key: k,
        child: MediaQuery(
          data: MediaQueryData(
              size: Size(genislik, yukseklik),
              textScaler: TextScaler.linear(yazi)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: acik
                ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
                : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
            builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(yazi)),
                child: child!),
            home: ekran,
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (sonra != null) await sonra();
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  Future<void> Function() kaydir(WidgetTester t) => () async {
        await t.drag(find.textContaining('THY').first, const Offset(-320, 0));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      };

  final thy = aggregatePositions(
          _varliklar.where((a) => a.ticker == 'THYAO.IS').toList())
      .single;
  Widget form() => AddAssetScreen(
      editingAsset: thy.asDisplayAsset(), yerineGecenLotlar: thy.lots);

  testWidgets('önce: kaydırma (özellik gizli)', (t) async {
    await ciz(t, 'kaydirma_once', const PortfolioScreen(),
        durum: VarlikGuncellemeDurumu.gizli, sonra: kaydir(t));
  });
  testWidgets('sonra: kaydırma', (t) async {
    await ciz(t, 'kaydirma_sonra', const PortfolioScreen(), sonra: kaydir(t));
  });
  testWidgets('sonra: kaydırma açık tema', (t) async {
    await ciz(t, 'kaydirma_sonra_acik', const PortfolioScreen(),
        acik: true, sonra: kaydir(t));
  });
  testWidgets('form', (t) async {
    await ciz(t, 'form_koyu', form());
  });
  testWidgets('form açık tema', (t) async {
    await ciz(t, 'form_acik', form(), acik: true);
  });
  testWidgets('form 320pt yazı x2', (t) async {
    await ciz(t, 'form_320_x2', form(), genislik: 320, yazi: 2.0);
  });
  testWidgets('onay', (t) async {
    await ciz(t, 'onay_koyu', form(), sonra: () async {
      await t.tap(find.widgetWithText(FilledButton, 'Güncelle'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    });
  });
  testWidgets('onay açık tema', (t) async {
    await ciz(t, 'onay_acik', form(), acik: true, sonra: () async {
      await t.tap(find.widgetWithText(FilledButton, 'Güncelle'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    });
  });
}
