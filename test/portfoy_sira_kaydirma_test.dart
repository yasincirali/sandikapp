import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sira_kaydirma.dart';

const _uid = 'user-1';
const _n = 20;

Asset _asset(int i, double fiyat) => Asset(
      id: 'A$i',
      userId: _uid,
      name: 'Varlık $i',
      ticker: 'HSS$i.IS',
      type: i.isEven ? AssetType.hisse : AssetType.fon,
      quantity: 10.0 + i,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: _uid,
      email: 'test@example.com',
      displayName: 'Test',
      createdAt: DateTime(2026, 1, 1));
}

class _FakePortfolio extends PortfolioNotifier {
  final _fiyat = <int, double>{for (var i = 0; i < _n; i++) i: 120.0 + i};
  PortfolioState _durum() => PortfolioState(
      assets: [for (var i = 0; i < _n; i++) _asset(i, _fiyat[i]!)],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0);
  @override
  Future<PortfolioState> build() async => _durum();
  void fiyat(int i, double f) {
    _fiyat[i] = f;
    state = AsyncData(_durum());
  }
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

/// Sıra değişince Portföy kartları eski yerinden yenisine kayar (FLIP,
/// 2026-11-11, `SiraKaydirmaDenetcisi`). Kilitlenen: ara karede kart eski
/// ve yeni konum arasında, sonunda yenide; hareketi azaltta anında;
/// parmak listedeyken (kaydırma/Slidable) kayma yok; kayma kartı yeniden
/// kurmaz (`_ImzaliSatir` kazancı korunur).
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<_FakePortfolio> kur(WidgetTester tester,
      {bool hareketiAzalt = false}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final kap = ProviderContainer(overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
    ]);
    addTearDown(kap.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: kap,
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: hareketiAzalt),
          child: child!,
        ),
        home: const PortfolioScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    return kap.read(portfolioProvider.notifier) as _FakePortfolio;
  }

  // Satırın GÖRÜNEN kartı (öteleme kartın üstünde, sarmalayıcıda değil).
  Finder kart(int i) => find
      .descendant(
          of: find.byWidgetPredicate((w) =>
              w is SiraKaydirmaSatiri && '${w.anahtar}'.contains('HSS$i.')),
          matching: find.byType(Slidable))
      .first;
  double y(WidgetTester t, int i) => t.getTopLeft(kart(i)).dy;

  testWidgets('fiyat turu sırayı değiştirince kart kayarak yerine geçer',
      (tester) async {
    final not = await kur(tester);
    final eski = y(tester, 15);
    final ust = y(tester, 19);
    expect(eski, greaterThan(ust));

    final kurulan = <String, int>{};
    debugOnRebuildDirtyWidget = (e, _) {
      final ad = e.widget.runtimeType.toString();
      kurulan[ad] = (kurulan[ad] ?? 0) + 1;
    };
    not.fiyat(15, 1000); // 25 × 1000: en değerli, en üste çıkar
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(kurulan['_AssetCard'], 1, reason: 'yalnız fiyatı değişen kart');
    expect(y(tester, 15), closeTo(eski, 1), reason: 'ilk karede eski yerinde');

    await tester.pump(); // denetleyici başlar
    await tester.pump(SandikMotion.surface ~/ 2);
    final ara = y(tester, 15);
    expect(ara, lessThan(eski - 1));
    expect(ara, greaterThan(ust + 1));
    // 19 bir satır aşağı iner; o da arada.
    await tester.pumpAndSettle();
    expect(y(tester, 15), closeTo(ust, 1), reason: 'sonunda en üstte');
  });

  testWidgets('hareketi azaltta kart hemen yeni yerinde', (tester) async {
    final not = await kur(tester, hareketiAzalt: true);
    final ust = y(tester, 19);
    not.fiyat(15, 1000);
    await tester.pump();
    expect(y(tester, 15), closeTo(ust, 1));
    await tester.pump();
    expect(y(tester, 15), closeTo(ust, 1));
  });

  testWidgets('parmak listedeyken sıra değişimi kaymaz', (tester) async {
    final not = await kur(tester);
    final ust = y(tester, 19);
    final parmak = await tester.startGesture(tester.getCenter(kart(17)));
    not.fiyat(15, 1000);
    await tester.pump();
    await tester.pump();
    expect(y(tester, 15), closeTo(ust, 1));
    await parmak.cancel();
    await tester.pumpAndSettle();
  });
}
