import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Zirve "Seninle ortak" (Ar-Ge 2026-11-15 #1–#3):
/// 1. Premium alınınca açık ayrıntı sayfasındaki kilit hemen kalkar.
/// 2. Premium'da "Onda olup sende olmayanlar" (en büyük 3, yeni istek yok).
/// 3. Ücretsizde vitrinin açık en büyük kalemi ortaksa gerçek yarım sonuç.
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

TopGainerAllocation _satir({required bool kilitli, required String enBuyuk}) =>
    TopGainerAllocation(
      rank: 1,
      roiPct: 14.2,
      allocation: const {'hisse': 46, 'fon': 15},
      fonDetay: kilitli ? const {'?3': 15} : const {'AFT': 15},
      varlikDetay: {
        'hisse': kilitli
            ? {enBuyuk: 21, '?1': 14, '?2': 11}
            : {enBuyuk: 21, 'ASELS.IS': 14, 'BIMAS.IS': 11},
      },
      ayrintiKilitli: kilitli,
      benzerlik: 21,
    );

final _kilit = StateProvider<bool>((_) => true);

Future<void> _bekle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<ProviderContainer> _kur(WidgetTester tester,
    {String enBuyuk = 'THYAO.IS'}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final kap = ProviderContainer(overrides: [
    authProvider.overrideWith(_FakeAuth.new),
    portfolioProvider.overrideWith(_FakePortfolio.new),
    premiumKilitliProvider.overrideWith((ref) => ref.watch(_kilit)),
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
            ilkUye: false,
            ayrintiAcik: !kap.read(_kilit),
          ),
          satirYukleyici: (_) async =>
              [_satir(kilitli: kap.read(_kilit), enBuyuk: enBuyuk)],
        ),
      ),
    ),
  ));
  await _bekle(tester);
  final bag = find.textContaining(
      RegExp('Varlık varlık dağılım|Tüm varlıklar|Tür tür dağılım'));
  await tester.tap(bag.first);
  await _bekle(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
  return kap;
}

Finder _sayfada(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

Future<void> _kapat(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('ZirveKiyas.ondaOlupSendeOlmayan', () {
    test('kullanıcıda olmayan en büyük 3 açık kalem, büyükten küçüğe', () {
      final l = ZirveKiyas.ondaOlupSendeOlmayan(
        senFon: const {'AFT': 10},
        senVarlik: const {
          'hisse': {'THYAO.IS': 50},
        },
        zirveFon: const {'AFT': 30, 'TTE': 8, 'DIGER': 20},
        zirveVarlik: const {
          'hisse': {'THYAO.IS': 21, 'ASELS.IS': 14, '?1': 40},
          'kripto': {'BTCUSDT': 12, 'ETHUSDT': 6},
        },
      );
      expect([for (final e in l) e.kod], ['ASELS.IS', 'BTCUSDT', 'TTE']);
      expect(l.first.tur, 'hisse');
      expect(l.first.pay, 14);
    });

    test('kilitli ve DIGER sayılmaz; payı 0 olan "sende yok"', () {
      final l = ZirveKiyas.ondaOlupSendeOlmayan(
        senFon: const {},
        senVarlik: const {
          'hisse': {'ASELS.IS': 0},
        },
        zirveFon: const {'?2': 30, 'DIGER': 9},
        zirveVarlik: const {
          'hisse': {'ASELS.IS': 14},
        },
      );
      expect([for (final e in l) e.kod], ['ASELS.IS']);
    });

    test('hepsi kullanıcıda varsa boş; enFazla uyulur', () {
      expect(
          ZirveKiyas.ondaOlupSendeOlmayan(
            senFon: const {'AFT': 1},
            senVarlik: const {},
            zirveFon: const {'AFT': 30},
            zirveVarlik: const {},
          ),
          isEmpty);
      expect(
          ZirveKiyas.ondaOlupSendeOlmayan(
            senFon: const {},
            senVarlik: const {},
            zirveFon: const {'A1A': 3, 'B1B': 2, 'C1C': 1},
            zirveVarlik: const {},
            enFazla: 2,
          ).length,
          2);
    });
  });

  group('ZirveKiyas.vitrinOrtagi', () {
    const zirveVarlik = <String, Map<String, double>>{
      'hisse': {'THYAO.IS': 21, '?1': 14},
    };
    const zirveFon = <String, double>{'?2': 30};

    test('açık en büyük kalem kullanıcıda da varsa onu döner', () {
      final ortak = ZirveKiyas.ortakKalemler(
        senFon: const {},
        senVarlik: const {
          'hisse': {'THYAO.IS': 12},
        },
        zirveFon: zirveFon,
        zirveVarlik: zirveVarlik,
      );
      final v = ZirveKiyas.vitrinOrtagi(
          zirveFon: zirveFon, zirveVarlik: zirveVarlik, ortak: ortak);
      expect(v, isNotNull);
      expect(v!.kod, 'THYAO.IS');
      expect(ZirveKiyas.vitrinOrtagiCumlesi(v, benzerlik: 12),
          'Ortak varlıklarından biri THYAO: sende %12, onda %21');
      // Benzerlik bu kalemden büyükse başka ortak gerçekten var.
      expect(ZirveKiyas.vitrinOrtagiCumlesi(v, benzerlik: 20),
          "Ortak varlıklarından biri THYAO: sende %12, onda %21 · "
          "Gerisi Premium'da");
    });

    test('açık kalem kullanıcıda yoksa null', () {
      final ortak = ZirveKiyas.ortakKalemler(
        senFon: const {},
        senVarlik: const {
          'hisse': {'ASELS.IS': 12},
        },
        zirveFon: zirveFon,
        zirveVarlik: zirveVarlik,
      );
      expect(
          ZirveKiyas.vitrinOrtagi(
              zirveFon: zirveFon, zirveVarlik: zirveVarlik, ortak: ortak),
          isNull);
    });

    test('açık kalem yoksa null', () {
      expect(
          ZirveKiyas.vitrinOrtagi(
              zirveFon: const {'?1': 10},
              zirveVarlik: const {},
              ortak: const []),
          isNull);
    });
  });

  testWidgets(
      'kilitli sayfa açıkken Premium açılınca maskeli kod ve kilit düğmesi '
      'sayfa kapanmadan gider; iki yönlü liste görünür', (tester) async {
    final kap = await _kur(tester);
    // Kilitli: yarım sonuç (THYAO ortak ve vitrinde açık) + düğme + maske.
    expect(_sayfada(find.text('Ortak varlıkları gör · Premium')),
        findsOneWidget);
    expect(
        _sayfada(find.textContaining('Ortak varlıklarından biri THYAO')),
        findsOneWidget);
    expect(_sayfada(find.textContaining(ZirveKiyas.kilitliYer)),
        findsWidgets);
    expect(_sayfada(find.text('Onda olup sende olmayanlar')), findsNothing);

    kap.read(_kilit.notifier).state = false;
    await _bekle(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
        _sayfada(find.text('Ortak varlıkları gör · Premium')), findsNothing);
    expect(_sayfada(find.textContaining(ZirveKiyas.kilitliYer)), findsNothing);
    expect(_sayfada(find.textContaining('ASELS')), findsWidgets);
    expect(_sayfada(find.text('Onda olup sende olmayanlar')), findsOneWidget);
    expect(_sayfada(find.bySemanticsLabel('AFT: onda %15')), findsOneWidget);
    expect(_sayfada(find.textContaining('yatırım tavsiyesi değildir')),
        findsOneWidget);
    await _kapat(tester);
  });

  testWidgets('vitrinin açık kalemi ortak değilse yarım sonuç çıkmaz',
      (tester) async {
    await _kur(tester, enBuyuk: 'KCHOL.IS');
    expect(_sayfada(find.text('Ortak varlıkları gör · Premium')),
        findsOneWidget);
    expect(_sayfada(find.textContaining('Ortak varlıklarından biri')),
        findsNothing);
    await _kapat(tester);
  });
}
