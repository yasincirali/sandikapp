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

/// Filtre değişince liste BAŞA döner (emülatör testi #25, 2026-09-29).
///
/// Liste eski kaydırma ofsetinde kalıyordu: Silinenler'in dibinden dönem
/// filtresine geçince yeni sonucun ilk kayıtları ekranın üstünde, görünmez
/// kalıyordu. Bütün filtre değişiklikleri `_resetPaging`'den geçer; test
/// Silinenler çipiyle (sayfa açmadan, tek dokunuş) iki yönü de dener.
const _uid = 'user-1';
final _simdi = DateTime.now();

Asset _lot(int i, {bool silinmis = false}) => Asset(
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
      addedDate: _simdi.subtract(Duration(days: i + 1)),
      deletedAt: silinmis ? _simdi.subtract(Duration(days: i)) : null,
    );

final _defter = [
  for (var i = 0; i < 40; i++) _lot(i),
  for (var i = 40; i < 80; i++) _lot(i, silinmis: true),
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

double _ofset(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView).last).controller!.offset;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  testWidgets('filtre değişince liste başa kayar', (tester) async {
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
        home: const AllTransactionsScreen(
          allPartnerAssets: {},
          partners: [],
          initialView: '',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final liste = find.byType(ListView).last;
    await tester.drag(liste, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(_ofset(tester), greaterThan(0), reason: 'ön koşul: aşağıdayız');

    await tester.tap(find.textContaining('Silinenler'));
    await tester.pumpAndSettle();
    expect(_ofset(tester), 0, reason: 'yeni sonuç kümesi baştan görünmeli');

    await tester.drag(find.byType(ListView).last, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(_ofset(tester), greaterThan(0));

    await tester.tap(find.textContaining('Silinenler'));
    await tester.pumpAndSettle();
    expect(_ofset(tester), 0);
  });
}
