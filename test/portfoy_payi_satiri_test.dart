import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';

/// Pozisyon kartında "Portföyündeki payı" satırı + nötr çubuk
/// (Ar-Ge 11 Kas 19:04 #7). Kapalı pozisyonda satır yok.

const _uid = 'user-1';

Asset _lot(String ticker, double qty, double fiyat,
        {AssetKind kind = AssetKind.buy}) =>
    Asset(
      id: '$ticker-${kind.name}',
      userId: _uid,
      name: ticker,
      ticker: '$ticker.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
      kind: kind,
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

List<Asset> _defter = const [];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _defter,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

Future<void> _ac(WidgetTester tester, Asset asset) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: asset, showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  testWidgets('açık pozisyon: oran satırı ve 4 pt çubuk', (tester) async {
    // THYAO 30.000 + ASELS 10.000 → THYAO payı %75,0.
    final thyao = _lot('THYAO', 100, 300);
    _defter = [thyao, _lot('ASELS', 100, 100)];
    await _ac(tester, thyao);

    expect(find.text('Portföyündeki payı'), findsOneWidget);
    expect(find.text('%75,0'), findsOneWidget);
    final cubuk = find.byKey(const ValueKey('portfoyPayiCubugu'));
    expect(cubuk, findsOneWidget);
    expect(tester.getSize(cubuk).height, 4);
    // Dolgu çubuğun dörtte üçü.
    final dolgu = tester.widget<FractionallySizedBox>(find.descendant(
        of: cubuk, matching: find.byType(FractionallySizedBox)));
    expect(dolgu.widthFactor, closeTo(0.75, 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tamamen satılmış pozisyon: satır yok', (tester) async {
    final asels = _lot('ASELS', 100, 100);
    _defter = [
      _lot('THYAO', 100, 300),
      asels,
      _lot('ASELS', 100, 100, kind: AssetKind.sell),
    ];
    await _ac(tester, asels);

    expect(find.text('Portföyündeki payı'), findsNothing);
    expect(find.byKey(const ValueKey('portfoyPayiCubugu')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
