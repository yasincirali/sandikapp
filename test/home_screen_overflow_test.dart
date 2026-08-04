import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';

/// Ana ekranın taşma regresyonu.
///
/// **Bu test bir kez denenip geri alınmıştı** (2026-08-04): ekran testte
/// izole edilemiyordu çünkü (a) `google_fonts` DM Sans'ı ağdan çekmeye
/// çalışıyor, (b) `DbLogger._persistAsync` her çağrıda bekleyen bir future
/// kuruyordu. İkisi de kapandı — DM Sans artık asset, `DbLogger` testte
/// `silentInTests` ile susturuluyor — bu yüzden test geri getirildi.
///
/// `leaderboard_overflow_test.dart` ile aynı kalıp: ekranı gerçek haliyle
/// pump et, veriyi ProviderScope override'larıyla besle.
///
/// Ekranın iki ayrı hâli farklı yerleşim çiziyor ve ikisi de test ediliyor:
///   - portföy BOŞ  → boş durum + "varlık ekle" düğmesi
///   - portföy DOLU → özet kartı + varlık listesi

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

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

/// Gerçek notifier Supabase'e gidiyor; sinyal listesi yerleşimi etkilediği
/// için boş/dolu iki hâl de besleniyor.
class _FakeSignals extends SignalNotifier {
  _FakeSignals(this._alerts);
  final List<SignalAlert> _alerts;

  @override
  Future<List<SignalAlert>> build() async => _alerts;
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  List<Asset> assets = const [],
  List<SignalAlert> signals = const [],
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(() => _FakeSignals(signals)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// iPhone SE (320) → iPhone 12 mini (375) → Pro Max (430) arası tarama.
const _widths = <double>[320, 360, 375, 390, 430];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });

  tearDownAll(() {
    DbLogger.silentInTests = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('ana ekran — taşma', () {
    group('portföy boş', () {
      for (final w in _widths) {
        testWidgets('${w.toInt()}pt ekranda boş durum', (tester) async {
          await _pump(tester, width: w);
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('portföy dolu', () {
      final assets = [
        _asset(ticker: 'THYAO', name: 'Türk Hava Yolları A.O.'),
        _asset(
          ticker: 'TSKB',
          name: 'Türkiye Sınai Kalkınma Bankası A.Ş. Uzun Ad',
          qty: 12500,
        ),
        _asset(
          ticker: 'GLDGR',
          name: 'Gram Altın',
          type: AssetType.altin,
          qty: 15.5,
          buy: 4820.30,
          current: 5140.75,
        ),
      ];

      for (final w in _widths) {
        testWidgets('${w.toInt()}pt ekranda varlık listesi', (tester) async {
          await _pump(tester, width: w, assets: assets);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('zarardaki portföy — negatif değerler daha geniş',
          (tester) async {
        await _pump(
          tester,
          width: 320,
          assets: [
            _asset(
              ticker: 'ZARAR',
              name: 'Çok Uzun İsimli Zarardaki Şirket A.Ş.',
              qty: 987654,
              buy: 1250.75,
              current: 310.20,
            ),
          ],
        );
        expect(tester.takeException(), isNull);
      });
    });
  });
}
