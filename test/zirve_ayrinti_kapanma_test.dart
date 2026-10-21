import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Zirve portföy ayrıntı sayfası aşağı çekince kapanır (yasin 2026-10-21:
/// "tepeden aşağı sürükleyince de kapanması, sadece x ile kapatabiliyorum").
///
/// Hata yalnız gövde sayfadan UZUNKEN görünüyordu: içteki kaydırma aşağı
/// çekme jestini yutuyor, sayfa yerinde kalıyordu. Bu yüzden ekran kısa
/// kısaltılır ki gövde kesin taşsın.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1', email: 'a@b.c', displayName: 'Test', createdAt: DateTime(2026));
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [
        Asset(
          id: '1',
          userId: 'u1',
          name: 'THYAO.IS',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: 1,
          purchasePrice: 400,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          addedDate: DateTime(2025, 6, 1),
        ),
      ], usdTry: 42, eurTry: 46, gbpTry: 54);
}

final _satirlar = [
  TopGainerAllocation(
    rank: 1,
    roiPct: 14.2,
    allocation: const {'hisse': 52, 'fon': 23, 'kripto': 18, 'altin': 7},
    fonDetay: const {'AFT': 15, 'TTE': 8},
    varlikDetay: const {
      'hisse': {'THYAO.IS': 21, 'ASELS.IS': 14, 'BIMAS.IS': 11, 'DIGER': 6},
      'kripto': {'BTCUSDT': 12, 'ETHUSDT': 6},
      'altin': {'ALTIN_CEYREK': 7},
    },
    ayrintiKilitli: false,
    benzerlik: 49,
  ),
];

Future<void> _bekle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('uzun gövdede tutamaktan ve içerikten aşağı çekince kapanır',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: Scaffold(
          body: ZirveGovdesi(
            donem: ZirveDonem.ay,
            onDonem: (_) {},
            rizaYukleyici: () async => true,
            durumYukleyici: (_) async => null,
            erisimYukleyici: () async => (
              aktif: true,
              metinSurumu: LeaderboardService.zirveRizaMetniSurumu,
              ilkUye: true,
              ayrintiAcik: true,
            ),
            satirYukleyici: (_) async => _satirlar,
          ),
        ),
      ),
    ));
    await _bekle(tester);

    final bag = find.textContaining(
        RegExp('Varlık varlık dağılım|Tüm varlıklar|Tür tür dağılım'));
    final sayfa = find.byType(BottomSheet);
    for (final tutamak in [true, false]) {
      // Liste uzun ekranda açılır, sayfa açıkken ekran kısaltılır: gövde
      // sayfanın %90 tavanından uzun kalır.
      tester.view.physicalSize = const Size(390, 1400);
      await _bekle(tester, 2);
      await tester.tap(bag.first);
      await _bekle(tester);
      tester.view.physicalSize = const Size(390, 600);
      await _bekle(tester, 2);
      expect(sayfa, findsOneWidget);
      // Önkoşul: gövde gerçekten kayıyor (hatanın görüldüğü durum).
      final kaydirma = tester.state<ScrollableState>(find
          .descendant(of: sayfa, matching: find.byType(Scrollable))
          .first);
      expect(kaydirma.position.maxScrollExtent, greaterThan(0));
      await tester.fling(
          tutamak
              ? find.byType(SandikTutamac)
              : find.textContaining('VARLIKLAR').first,
          const Offset(0, 500),
          2000);
      await _bekle(tester);
      expect(sayfa, findsNothing, reason: tutamak ? 'tutamak' : 'içerik');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
