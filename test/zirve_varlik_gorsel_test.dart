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
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Zirve varlık ayrıntısı (0158) — önce/sonra görseli. `build/gorsel/`
/// altına PNG; assert etmez, `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/zirve_varlik_gorsel_test.dart
///
/// Üç hâl: `once` (eski sunucu: yalnız tür + fon), `kilitli` (yeni katılan,
/// Premium değil: en büyük kalem açık, gerisi "••••"), `acik` (ilk üye ya da
/// Premium).

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1', email: 'a@b.c', displayName: 'Test', createdAt: DateTime(2026));
}

Asset _v(String id, AssetType t, String ticker, double tl) => Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: t,
      quantity: 1,
      purchasePrice: tl,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: DateTime(2025, 6, 1),
    );

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [
        _v('1', AssetType.hisse, 'THYAO.IS', 400),
        _v('2', AssetType.hisse, 'BIMAS.IS', 150),
        _v('3', AssetType.fon, 'AFT', 250),
        _v('4', AssetType.kripto, 'BTCUSDT', 200),
      ], usdTry: 42, eurTry: 46, gbpTry: 54);
}

List<TopGainerAllocation> _satirlar(String hal) {
  final yeni = hal != 'once';
  final kilit = hal == 'kilitli';
  Map<String, Map<String, double>> v(Map<String, Map<String, double>> acik,
          Map<String, Map<String, double>> maske) =>
      !yeni ? const {} : (kilit ? maske : acik);
  return [
    TopGainerAllocation(
      rank: 1,
      roiPct: 14.2,
      allocation: const {'hisse': 52, 'fon': 23, 'kripto': 18, 'altin': 7},
      fonDetay: const {'AFT': 15, 'TTE': 8},
      varlikDetay: v(const {
        'hisse': {'THYAO.IS': 21, 'ASELS.IS': 14, 'BIMAS.IS': 11, 'DIGER': 6},
        'kripto': {'BTCUSDT': 12, 'ETHUSDT': 6},
        'altin': {'ALTIN_CEYREK': 7},
      }, const {
        'hisse': {'THYAO.IS': 21, '?2': 14, '?3': 11, 'DIGER': 6},
        'kripto': {'?1': 12, '?2': 6},
        'altin': {'?1': 7},
      }),
      ayrintiKilitli: kilit,
      benzerlik: yeni ? 49 : null,
    ),
    TopGainerAllocation(
      rank: 2,
      roiPct: 11.8,
      allocation: const {'hisse': 70, 'doviz': 30},
      fonDetay: const {},
      varlikDetay: v(const {
        'hisse': {'KCHOL.IS': 40, 'FROTO.IS': 30},
        'doviz': {'USDTRY=X': 30},
      }, const {
        'hisse': {'KCHOL.IS': 40, '?2': 30},
        'doviz': {'?1': 30},
      }),
      ayrintiKilitli: kilit,
      benzerlik: yeni ? 0 : null,
    ),
    TopGainerAllocation(
      rank: 3,
      roiPct: 9.6,
      allocation: const {'fon': 60, 'altin': 40},
      fonDetay: const {'AFT': 35, 'IPJ': 25},
      varlikDetay: v(const {
        'altin': {'ALTIN_GRAM24': 40},
      }, const {
        'altin': {'ALTIN_GRAM24': 40},
      }),
      ayrintiKilitli: kilit,
      benzerlik: yeni ? 25 : null,
    ),
  ];
}

void main() {
  setUpAll(() async {
    DbLogger.silentInTests = true;
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });

  const durumlar = [
    ('once', Brightness.dark, 1.0),
    ('kilitli', Brightness.dark, 1.0),
    ('acik', Brightness.dark, 1.0),
    ('kilitli', Brightness.light, 1.0),
    ('acik', Brightness.light, 1.0),
    ('kilitli', Brightness.dark, 2.0),
    ('acik', Brightness.dark, 2.0),
  ];
  for (final (hal, b, olcek) in durumlar) {
    testWidgets('zirve varlık — $hal ${b.name} ${olcek}x', (tester) async {
      tester.view.physicalSize = Size(390 * 2, (olcek > 1 ? 2400 : 1400) * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      const k = Key('kok');
      final ZirveErisim? erisim = hal == 'once'
          ? null
          : (
              aktif: true,
              metinSurumu: LeaderboardService.zirveRizaMetniSurumu,
              ilkUye: hal == 'acik',
              ayrintiAcik: hal == 'acik',
            );
      // "Sen" ilk karede hazır olsun (`_senYenile` bir kez okur).
      final kap = ProviderContainer(overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ]);
      addTearDown(kap.dispose);
      await tester.runAsync(() async {
        await kap.read(authProvider.future);
        await kap.read(portfolioProvider.future);
      });
      await tester.pumpWidget(UncontrolledProviderScope(
        container: kap,
        child: RepaintBoundary(
          key: k,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(
                b == Brightness.dark ? SandikPalette.dark : SandikPalette.light,
                b),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(olcek)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: ZirveGovdesi(
                  donem: ZirveDonem.ay,
                  onDonem: (_) {},
                  rizaYukleyici: () async => true,
                  durumYukleyici: (_) async => null,
                  erisimYukleyici: () async => erisim,
                  satirYukleyici: (_) async => _satirlar(hal),
                ),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      Future<void> cek(String parca) => tester.runAsync(() async {
            final r =
                tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
            final img = await r.toImage(pixelRatio: 1.0);
            final bytes =
                await img.toByteData(format: ui.ImageByteFormat.png);
            Directory('build/gorsel').createSync(recursive: true);
            File('build/gorsel/zirve_varlik_${hal}_${parca}_${b.name}_${olcek}x.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
      await cek('liste');
      // Ayrıntı alt sayfası: tür satırlarının altında varlıklar.
      final bag = find.textContaining(
          RegExp('Varlık varlık dağılım|Tüm varlıklar|Tür tür dağılım'));
      if (bag.evaluate().isNotEmpty) {
        await tester.tap(bag.first);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await cek('ayrinti');
        // Uzun gövdede de sayfa kapanabilmeli (yasin 2026-10-21: "açılıyor
        // ama kapatılamıyor"): tavan %90, başlıkta kapat düğmesi.
        final sayfa = find.byType(BottomSheet);
        expect(tester.getSize(sayfa).height,
            lessThanOrEqualTo(tester.view.physicalSize.height / 2 * 0.9 + 1));
        await tester.tap(find.byIcon(Icons.close_rounded));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(sayfa, findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
