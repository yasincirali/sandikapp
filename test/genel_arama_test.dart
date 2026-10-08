import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/genel_arama_screen.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Genel arama (bayrak `genel_arama`, sadeleştirme 2).
///
/// Bayrak kapalı: ana ekran üst çubuğu birebir eski (yenile düğmesi).
/// Bayrak açık: aynı yuvada büyüteç; arama ekranı kendi varlığını,
/// piyasa sonucunu ve eylemleri gösterir.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
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
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset()],
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

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

Future<void> _pump(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
      watchlistProvider.overrideWith(_Takip.new),
    ],
    child: MaterialApp(
        home: Material(type: MaterialType.transparency, child: ekran)),
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
  tearDown(() => RemoteConfigService.testAcik = {});

  group('ana ekran üst çubuğu', () {
    testWidgets('bayrak kapalı: yenile düğmesi, büyüteç yok', (t) async {
      await _pump(t, const HomeScreen());
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('genel-arama-dugmesi')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('bayrak açık: aynı yuvada Ara, yenile düğmesi yok',
        (t) async {
      RemoteConfigService.testAcik = {'genel_arama'};
      await _pump(t, const HomeScreen());
      final ara = find.byKey(const ValueKey('genel-arama-dugmesi'));
      expect(ara, findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      // Aynı boy: 44pt kutu.
      final r = t.getRect(ara);
      expect(r.width, 44);
      expect(r.height, 44);
      // Yenileme aşağı çekmede kalır.
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await t.tap(ara);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GenelAramaScreen), findsOneWidget);
      // Boş sorguda eylemler öneri olarak; ana ekranın açıcıları da var.
      expect(find.text('EYLEMLER'), findsOneWidget);
      expect(find.text('Bildirimler'), findsOneWidget);
      expect(find.text('Tüm hareketler'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('arama ekranı', () {
    setUp(SymbolSearchService.clearCacheForTest);

    Future<void> yaz(WidgetTester t, String q) async {
      await t.enterText(
          find.byKey(const ValueKey('genel-arama-alani')), q);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Widget ekran() => GenelAramaScreen(
          aramaServisi: (q) async => q.toLowerCase().contains('thy')
              ? const [
                  SymbolHit(
                      ticker: 'THYAO.IS',
                      name: 'Türk Hava Yolları',
                      source: 'BIST'),
                ]
              : const [],
          kotasyonServisi: (_) async => const {},
        );

    testWidgets('boş sorgu: eylem önerileri; açıcısı verilmeyenler yok',
        (t) async {
      await _pump(t, ekran());
      expect(find.text('EYLEMLER'), findsOneWidget);
      expect(find.text('Fiyat alarmları'), findsOneWidget);
      expect(find.text('Ayarlar'), findsOneWidget);
      // Çağıran açıcı vermedi → listelenmez.
      expect(find.text('Bildirimler'), findsNothing);
      expect(find.text('Tüm hareketler'), findsNothing);
      expect(find.text('VARLIKLARIM'), findsNothing);
      expect(find.text('PİYASA'), findsNothing);
    });

    testWidgets('"thy": kendi varlığı + piyasa sonucu', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'thy');
      expect(find.text('VARLIKLARIM'), findsOneWidget);
      // Varlıklarım ve Piyasa satırı aynı alt satırı taşır.
      expect(find.text('THYAO · Hisse'), findsNWidgets(2));
      expect(find.text('PİYASA'), findsOneWidget);
      expect(find.text('Türk Hava Yolları'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('"alarm": yalnız eylem eşleşir', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'alarm');
      expect(find.text('Fiyat alarmları'), findsOneWidget);
      expect(find.text('Ayarlar'), findsNothing);
      expect(find.text('VARLIKLARIM'), findsNothing);
    });

    testWidgets('hiçbir şey eşleşmezse boş durum metni', (t) async {
      await _pump(t, ekran());
      await yaz(t, 'qqzz');
      expect(find.text('"qqzz" için sonuç yok.'), findsOneWidget);
    });
  });
}
