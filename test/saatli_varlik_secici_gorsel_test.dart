@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/saatli_bildirim.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/saatli_bildirim_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart' show OlcekHafizasi;
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/saatli_bildirim.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saatli bildirim › "Varlık seç" GÖRSEL önizlemesi (2026-11-26 yeniden
/// tasarım). Gerçek tema + DM Sans, 390×844 @2x PNG yazar; assert etmez,
/// `gorsel` etiketi varsayılanda atlanır. Önce/sonra için aynı dosya eski
/// commit'te `ON_EK=once` ile koşulur (akışın genel girişinden açar, iki
/// sürümde de aynı yol):
///   flutter test --run-skipped --dart-define=ON_EK=sonra \
///     --dart-define=CIKTI=build/gorsel test/saatli_varlik_secici_gorsel_test.dart
const _onEk = String.fromEnvironment('ON_EK', defaultValue: 'sonra');
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');

Asset _a(String ticker, String ad, AssetType t,
        {String? sub, String para = 'TRY'}) =>
    Asset(
      id: ticker,
      userId: 'u1',
      name: ad,
      ticker: ticker,
      type: t,
      subCategory: sub,
      quantity: 10,
      purchasePrice: 1,
      currency: para,
      notes: '',
    );

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          _a('ALTIN_GRAM24', 'Gram Altın (24 Ayar)', AssetType.altin,
              sub: 'ALTIN_GRAM24'),
          _a('THYAO.IS', 'Türk Hava Yolları', AssetType.hisse),
          _a('ASELS.IS', 'Aselsan', AssetType.hisse),
          _a('TUPRS.IS', 'Tüpraş', AssetType.hisse),
          _a('TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler Yabancı Hisse Fonu',
              AssetType.fon),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        WatchlistItem(
          id: 'w1',
          userId: 'u1',
          ticker: 'USDTRY=X',
          name: 'Amerikan Doları',
          type: AssetType.doviz,
          subCategory: 'USD',
          currency: 'TRY',
          addedAt: DateTime(2026, 11, 1),
        ),
      ];
}

class _Saatli extends SaatliBildirimlerNotifier {
  @override
  Future<List<SaatliBildirim>> build() async => [
        SaatliBildirim(
          id: 's1',
          userId: 'u1',
          symbol: 'THYAO.IS',
          label: 'Türk Hava Yolları',
          saatler: const [540, 780, 1080],
          createdAt: DateTime(2026, 11, 20),
        ),
      ];
}

void main() {
  setUpAll(() async {
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
    // Disk belleği yükleme future'ı önceki testin sahte saatinde kalmasın.
    PriceService.instance.sonBilinenFiyatlariTemizle();
    OlcekHafizasi.instance.temizle();
    // Fiyatlar ağa çıkmadan önbellekten (önizleme verisi; uygulamada
    // `PriceService.fetchQuotes` canlı kotasyonu getirir).
    for (final (s, f, p) in [
      ('ALTIN_GRAM24', 5712.40, 0.62),
      ('THYAO.IS', 318.75, -1.18),
      ('ASELS.IS', 164.20, 2.35),
      ('TUPRS.IS', 171.90, 0.41),
      ('TEFAS:AFT', 2.418765, 0.87),
      ('USDTRY=X', 42.31, 0.12),
    ]) {
      PriceService.instance.testIcinOnbellegeYaz(YahooQuote(
          symbol: s,
          regularMarketPrice: f,
          regularMarketChangePercent: p,
          currency: 'TRY'));
    }
  });

  Future<void> ciz(WidgetTester tester, String ad, {required bool koyu}) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    final p = koyu ? SandikPalette.dark : SandikPalette.light;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        saatliBildirimDurumuProvider.overrideWithValue(OzellikDurumu.acik),
        saatliBildirimlerProvider.overrideWith(_Saatli.new),
        portfolioProvider.overrideWith(_Portfoy.new),
        watchlistProvider.overrideWith(_Takip.new),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(
              p, koyu ? Brightness.dark : Brightness.light),
          home: Consumer(
            builder: (context, ref, _) {
              // Sağlayıcılar akıştan önce çözülsün (uygulamada çoktan dolu).
              ref.watch(portfolioProvider);
              ref.watch(watchlistProvider);
              ref.watch(saatliBildirimlerProvider);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => saatliBildirimAkisi(context, ref),
                    child: const Text('aç'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('aç'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_cikti).createSync(recursive: true);
      File('$_cikti/${_onEk}_$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('acik', (tester) => ciz(tester, 'acik', koyu: false));
  testWidgets('koyu', (tester) => ciz(tester, 'koyu', koyu: true));
}
