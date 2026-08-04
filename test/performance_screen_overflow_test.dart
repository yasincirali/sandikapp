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
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Varlık performans ekranının taşma regresyonu.
///
/// Ekran 2.553 satırla en büyük ikinci dosya; `asset_card_overflow_test.dart`
/// ile aynı kalıp: gerçek ekranı pump et, veriyi ProviderScope override'ları
/// ile besle. İç yapı değil dış davranış doğrulanır.
///
/// Ağ çağrıları (fiyat geçmişi) test ortamında başarısız olur ve ekran
/// yükleme/boş durumunu çizer — taşma testi için bu YETERLİ: başlık bloğu,
/// özet kartları ve periyot seçici yine de çizilir ve asıl risk oralarda.

const _uid = 'user-1';

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
  double qty = 100,
  double buy = 250.75,
  double current = 312.40,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
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
        displayName: 'Test Kullanıcı',
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

Future<void> _pump(
  WidgetTester tester,
  Asset asset, {
  double width = 375,
  List<Asset>? lots,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio([asset])),
        partnersProvider.overrideWith(_FakePartners.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: PerformanceScreen(
          asset: asset,
          showBackButton: true,
          lots: lots,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('performans ekranı — taşma', () {
    for (final w in <double>[320, 375, 430]) {
      testWidgets('${w.toInt()}pt — hisse', (tester) async {
        await _pump(
          tester,
          _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları'),
          width: w,
        );
        expect(tester.takeException(), isNull,
            reason: '${w.toInt()}pt: performans ekranı taşıyor');
      });
    }

    testWidgets('uzun fon adı — dar ekran', (tester) async {
      await _pump(
        tester,
        _asset(
          ticker: 'TEFAS:YKT',
          name: 'Yapı Kredi Portföy Teknoloji Değişken Fon',
          type: AssetType.fon,
          qty: 486.948,
          buy: 0.814,
          current: 0.9123,
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('yabancı para birimi — dar ekran', (tester) async {
      await _pump(
        tester,
        _asset(
          ticker: 'AAPL',
          name: 'Apple Inc.',
          qty: 25,
          buy: 180.5,
          current: 214.3,
          currency: 'USD',
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok büyük tutar', (tester) async {
      await _pump(
        tester,
        _asset(
          ticker: 'BIG.IS',
          name: 'Büyük Pozisyon',
          qty: 1000000,
          buy: 1250.50,
          current: 9876.54,
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('zararda pozisyon', (tester) async {
      // Kâr/zarar satırı negatifte farklı genişlikte (eksi işareti + renk).
      await _pump(
        tester,
        _asset(
          ticker: 'LOSS.IS',
          name: 'Zarardaki Varlık',
          buy: 500,
          current: 123.45,
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok lotlu pozisyon (işlem marker\'ları)', (tester) async {
      final a = _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları');
      await _pump(
        tester,
        a,
        width: 375,
        lots: [
          a,
          _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', qty: 50),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });
}
