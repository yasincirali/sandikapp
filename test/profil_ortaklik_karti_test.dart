// Profil: ortağı olmayana ortaklık bölümü tek karta iner (yasin 2026-10-27,
// Ar-Ge 27 Eki #2). Ortak varken yerleşim birebir eski.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/halka_arz_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';

AppUser _kisi(String id, String ad) => AppUser(
      id: id,
      email: '$id@example.com',
      displayName: ad,
      createdAt: DateTime(2026, 1, 1),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _kisi('u1', 'Test');
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState(
        assets: <Asset>[],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _Bos extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _Dolu extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async =>
      [PartnerAccount(user: _kisi('u2', 'Ayşe'), isActive: true)];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

Future<void> _profil(WidgetTester tester,
    {required PartnersNotifier Function() ortaklar}) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      halkaArzEtkinProvider.overrideWithValue(false),
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(ortaklar),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
    ],
    child: const MaterialApp(
        home: Material(
            type: MaterialType.transparency, child: ProfileScreen())),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  testWidgets('ortak yoksa tek kart; iki başlık ve boş kart yok',
      (tester) async {
    await _profil(tester, ortaklar: _Bos.new);
    expect(find.text('Ortak portföy'), findsOneWidget);
    expect(find.text('Davet et'), findsOneWidget);
    expect(find.text('Kod gir'), findsOneWidget);
    expect(find.text('ORTAKLIK İŞLEMLERİ'), findsNothing);
    expect(find.text('ORTAKLARIM'), findsNothing);
    expect(find.text('Henüz ortağın yok'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('"Kod gir" bölümü yerinde açar, alan görünür', (tester) async {
    await _profil(tester, ortaklar: _Bos.new);
    await tester.tap(find.text('Kod gir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ORTAKLIK İŞLEMLERİ'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Ortak portföy'), findsNothing);
    // Ortak yokken boş "ORTAKLARIM" kartı açılmış bölümde de yok.
    expect(find.text('ORTAKLARIM'), findsNothing);
  });

  testWidgets('ortak varsa yerleşim eskisi gibi', (tester) async {
    await _profil(tester, ortaklar: _Dolu.new);
    expect(find.text('ORTAKLIK İŞLEMLERİ'), findsOneWidget);
    expect(find.text('ORTAKLARIM'), findsOneWidget);
    expect(find.text('Ortak portföy'), findsNothing);
  });

  testWidgets('kartın düğmeleri en az 44 pt', (tester) async {
    await _profil(tester, ortaklar: _Bos.new);
    for (final t in ['Davet et', 'Kod gir']) {
      final kutu = tester.getSize(find
          .ancestor(of: find.text(t), matching: find.byType(FilledButton))
          .first);
      expect(kutu.height, greaterThanOrEqualTo(44), reason: t);
    }
  });
}
