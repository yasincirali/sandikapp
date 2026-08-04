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
import 'package:portfoy_takip/screens/leaderboard_screen.dart';

/// Yarış (leaderboard) ekranının taşma regresyonu.
///
/// Ekran 1.665 satır ve kartları private; `asset_card_overflow_test.dart`
/// ile aynı kalıp kullanılıyor: ekranı gerçek haliyle pump et, veriyi
/// ProviderScope override'larıyla besle. İç yapı değil dış davranış
/// doğrulanır — ekran ileride parçalanınca test yine geçmeli.
///
/// Ekranın iki ayrı hâli var ve ikisi de farklı yerleşim çiziyor:
///   - opt-in KAPALI → `_OptInPrompt` (katılım daveti)
///   - opt-in AÇIK   → sıralama kartları + hero kart
/// İkisi de test ediliyor.

const _uid = 'user-1';

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
  double qty = 100,
  double buy = 250.75,
  double current = 312.40,
}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: current,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Çok Uzun Bir Kullanıcı Adı Soyadı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

/// Gerçek notifier polling kurar ve Supabase init olmadığı için test
/// çıktısını hata loguyla doldurur — davranış değişmez, yalnızca gürültü.
class _FakePartners extends PartnersNotifier {
  _FakePartners(this._partners);
  final List<PartnerAccount> _partners;

  @override
  Future<List<PartnerAccount>> build() async => _partners;
}

PartnerAccount _partner(String id, String name) => PartnerAccount(
      user: AppUser(
        id: id,
        email: '$id@example.com',
        displayName: name,
        createdAt: DateTime(2026, 1, 1),
      ),
      isActive: true,
    );

Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  List<Asset> assets = const [],
  List<PartnerAccount> partners = const [],
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
        partnersProvider.overrideWith(() => _FakePartners(partners)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const LeaderboardScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  group('yarış ekranı — taşma', () {
    group('opt-in kapalı (katılım daveti)', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await initPreferencesCache();
      });

      for (final w in <double>[320, 375, 430]) {
        testWidgets('${w.toInt()}pt', (tester) async {
          await _pump(tester, width: w);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}pt: katılım daveti taşıyor');
        });
      }
    });

    group('opt-in açık (sıralama)', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({
          'pref_leaderboard_opt_in': true,
        });
        await initPreferencesCache();
      });

      final assets = [
        _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları'),
        _asset(
            ticker: 'TEFAS:YKT',
            name: 'Yapı Kredi Portföy Teknoloji Değişken Fon',
            type: AssetType.fon,
            qty: 486.948,
            buy: 0.814,
            current: 0.9123),
      ];

      for (final w in <double>[320, 375, 430]) {
        testWidgets('${w.toInt()}pt — ortaksız', (tester) async {
          await _pump(tester, width: w, assets: assets);
          expect(tester.takeException(), isNull,
              reason: '${w.toInt()}pt: sıralama ekranı taşıyor');
        });
      }

      testWidgets('uzun ortak adlarıyla dar ekran', (tester) async {
        // Sıralama satırında ad + getiri yan yana; uzun ad en riskli hâl.
        await _pump(
          tester,
          width: 320,
          assets: assets,
          partners: [
            _partner('p1', 'Mehmet Emin Karahanoğlu'),
            _partner('p2', 'Ayşe Nur Büyükçelebioğlu'),
          ],
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('boş portföy', (tester) async {
        await _pump(tester, width: 375);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
