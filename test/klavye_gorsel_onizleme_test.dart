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
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Klavye denetiminin (2026-10-08) önce/sonra görselleri — `build/gorsel/`.
///
/// Telefon 390×844, 47 pt durum çubuğu, 336 pt klavye. Klavye testte
/// çizilmez; yerini koyu gri bir blok, durum çubuğunu yarı saydam kırmızı
/// şerit gösterir (şeridin altına giren içerik hatadır). Assert etmez (`gorsel`
/// etiketi CI'da atlanır). Elle: flutter test --tags gorsel
/// test/klavye_gorsel_onizleme_test.dart

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

Asset _hisse() => Asset(
      id: 'a',
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 250,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 300,
      addedDate: DateTime(2026, 3, 14),
    );

const _klavye = 336.0;

void main() {
  final ek = Platform.environment['GORSEL_EK'] ?? 'sonra';

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      Future<void> Function() sonra) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 2);
    tester.view.viewInsets = const FakeViewPadding(bottom: _klavye * 2);
    addTearDown(tester.view.reset);
    FlutterError.onError = (_) {}; // taşma şeritleri görselde kalsın
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_FakePortfolio.new),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: RepaintBoundary(
        key: k,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
              home: ekran,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 47,
              child: IgnorePointer(
                  child: Container(color: const Color(0x99FF453A))),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _klavye,
              child: IgnorePointer(
                child: Container(
                color: const Color(0xEE3A3A3C),
                alignment: Alignment.center,
                child: const Text('klavye',
                    style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 20,
                        fontFamily: kSandikFontFamily)),
              ),
              ),
            ),
          ]),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await sonra();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/klavye_${ad}_$ek.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('hızlı al diyaloğu', (tester) async {
    await ciz(
      tester,
      'hizli_al',
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showQuickAdjustDialog(context, ref,
                asset: _hisse(), mode: QuickAdjustMode.add),
            child: const Text('ac'),
          ),
        ),
      ),
      () async {
        await tester.tap(find.text('ac'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.enterText(find.byType(TextField).first, '3');
      },
    );
  });

  testWidgets('hızlı giriş toplu', (tester) async {
    await ciz(tester, 'hizli_giris', const AddAssetScreen(), () async {
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.enterText(find.byType(TextField).last,
          List.generate(9, (i) => '${i + 1}00 dolar').join('\n'));
    });
  });

  testWidgets('yüksek sayfa (sembol arama düzeni)', (tester) async {
    await ciz(
      tester,
      'yuksek_sayfa',
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSandikSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                child: Container(
                  height: 844 * 0.75,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.all(16),
                  child: const Column(children: [
                    Text('Karşılaştırmaya ekle — başlık ve sekmeler',
                        style: TextStyle(fontSize: 18)),
                    SizedBox(height: 12),
                    TextField(
                        decoration: InputDecoration(hintText: 'Sembol ara')),
                  ]),
                ),
              ),
            ),
            child: const Text('ac'),
          ),
        ),
      ),
      () async {
        await tester.tap(find.text('ac'));
      },
    );
  });
}
