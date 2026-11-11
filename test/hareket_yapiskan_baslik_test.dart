import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yapışkan ay başlığı (2026-11-11): uzun bir ayın ortasında başlık üstte
/// kalır; ay bitince sonraki ayın başlığı onu iter. Liste `CustomScrollView`
/// + ay başına `SliverMainAxisGroup` + `PinnedHeaderSliver`.
const _uid = 'user-1';

Asset _lot(int i, DateTime t) => Asset(
      id: 'l$i',
      userId: _uid,
      name: 'Varlık $i',
      ticker: 'V$i',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: t,
    );

// Mart'ta 28 kayıt (uzun ay), Şubat'ta 12.
final _defter = [
  for (var i = 0; i < 28; i++) _lot(i, DateTime(2026, 3, 28 - i, 12)),
  for (var i = 0; i < 12; i++) _lot(100 + i, DateTime(2026, 2, 20 - i, 12)),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: _defter);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}


Future<void> _kur(WidgetTester tester, {double yazi = 1}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(yazi)),
        child: child!,
      ),
      home: const AllTransactionsScreen(
        allPartnerAssets: {},
        partners: [],
        initialView: '',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _liste => find.byType(CustomScrollView).last;

double _listeUstu(WidgetTester tester) => tester.getTopLeft(_liste).dy;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  // Ekran ay adını uygulama diliyle yazar; test MaterialApp'i varsayılan
  // (en) dilde.
  const mart = 'March 2026';
  const subat = 'February 2026';

  testWidgets('uzun ayın ortasında ay başlığı üstte yapışık kalır',
      (tester) async {
    await _kur(tester);
    expect(find.text(mart), findsOneWidget);

    // Mart'ın ortasına in (28 satır, ekrandan uzun).
    await tester.drag(_liste, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text(mart), findsOneWidget,
        reason: 'başlık satırlarla kayıp gitmemeli');
    final ust = _listeUstu(tester);
    final baslikUst = tester.getTopLeft(find.text(mart)).dy;
    expect(baslikUst - ust, lessThan(40),
        reason: 'başlık listenin tepesine yapışmalı');
  });

  testWidgets('ay bitince sonraki ayın başlığı yapışır', (tester) async {
    await _kur(tester);
    // Şubat'ın başlığı listenin tepesine gelene kadar in.
    for (var i = 0; i < 12; i++) {
      await tester.drag(_liste, const Offset(0, -300));
      await tester.pumpAndSettle();
      if (find.text(subat).evaluate().isNotEmpty &&
          tester.getTopLeft(find.text(subat)).dy - _listeUstu(tester) < 40) {
        break;
      }
    }
    expect(tester.getTopLeft(find.text(subat)).dy - _listeUstu(tester),
        lessThan(40));
    // Mart'ın başlığı itilip gitti: ya ağaçta yok ya da listenin üstünde.
    final m = find.text(mart);
    if (m.evaluate().isNotEmpty) {
      expect(tester.getBottomLeft(m).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text(subat)).dy + 1));
    }
  });

  testWidgets('yazı ×2: yapışık başlık taşmaz', (tester) async {
    await _kur(tester, yazi: 2);
    await tester.drag(_liste, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(mart), findsOneWidget);
  });
}
