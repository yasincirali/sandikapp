@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
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
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portfoy_takip/screens/signal_settings_screen.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';

/// Premium seti netleştirme (2026-10-10) — önce/sonra GÖRSEL önizlemesi,
/// `build/gorsel/pn_*.png`. Assert etmez; `gorsel` etiketi CI'da atlanır.
/// Aynı dosya main'de (önce) ve dalda (sonra) koşulur:
///   flutter test --run-skipped test/premium_netlestirme_gorsel_test.dart
///
/// Kullanıcı: paywall AÇIK, Premium OLMAYAN, admin olmayan hesap. Hak
/// satırı süresi geçmiş bir hediye: hediye güvencesine takılmadan kilitler
/// görünür (dalda `kilitlerAskidaProvider`; main'de böyle bir kural yok).
/// Sayılar DEMO'dur.
const _uid = 'u1';

/// Canlı fiyat serinin son değeri: grafiğin ucu (canlı fiyata sabitlenir)
/// demo serisinden kopmasın.
final double _sonFiyat = _yapaySeri().last.$2;

Asset _lot() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: (_sonFiyat * 0.8).roundToDouble(),
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: _sonFiyat,
      addedDate: DateTime(2025, 3, 14),
    );


class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: _assets, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
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

/// 10 yıllık günlük yapay seri: yükselen trend + yavaş dalga + gürültü.
/// Sabit tohum: önce/sonra koşuları aynı çizgiyi verir.
List<(int, double)> _yapaySeri() {
  final now = DateTime.now();
  final r = math.Random(7);
  var log = math.log(40.0);
  final out = <(int, double)>[];
  for (var i = 3650; i >= 0; i--) {
    log += 0.0006 + 0.018 * (r.nextDouble() - 0.5) +
        0.004 * math.sin((3650 - i) / 120);
    out.add((now.subtract(Duration(days: i)).millisecondsSinceEpoch,
        math.exp(log)));
  }
  return out;
}


List<Asset> _onLot() => [
      for (var i = 0; i < 9; i++)
        Asset(
          id: 'L$i',
          userId: _uid,
          name: 'Varlık $i',
          ticker: 'V$i.IS',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 10,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 12,
          addedDate: DateTime(2025, 3, 14),
        ),
    ];

final _bitmisHak = PremiumHakki(
    kaynak: 'erken_kullanici', bitis: DateTime.utc(2026, 1, 1));

List<Override> _ucretsiz() => [
      paywallVisibleProvider.overrideWithValue(true),
      magazaPremiumProvider.overrideWith((_) => false),
      premiumHaklariProvider.overrideWith((_) async => [_bitmisHak]),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
    ];

List<Override> _premium() => [
      paywallVisibleProvider.overrideWithValue(true),
      magazaPremiumProvider.overrideWith((_) => true),
      premiumHaklariProvider.overrideWith((_) async => const []),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
    ];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    RemoteConfigService.testAcik = {};
  });

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {List<Override> ek = const [],
      List<Asset>? lotlar,
      double boy = 844,
      Map<String, Object> tercih = const {},
      bool deste = true,
      Future<void> Function(WidgetTester)? sonra}) async {
    RemoteConfigService.testAcik = {
      'paywall_enabled',
      if (deste) 'paywall_deste',
      'raporlar_kapisi',
    };
    SharedPreferences.setMockInitialValues(tercih);
    await initPreferencesCache();
    HistoryService.clearCache();
    HistoryService.seriCekici = (sym, range, interval) async => _yapaySeri();
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider
            .overrideWith(() => _FakePortfolio(lotlar ?? [_lot()])),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        watchlistProvider.overrideWith(_Takip.new),
        ...ek,
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: ekran,
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (sonra != null) {
      await sonra(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('varlık sayfası, ücretsiz', (t) async {
    await ciz(t, 'pn_varlik_ucretsiz',
        AssetDetailScreen(asset: _lot(), showBackButton: true),
        ek: _ucretsiz(),
        boy: 2600,
        tercih: {'pref_chart_candle': true, 'pref_chart_ema50': true});
  });
  testWidgets('varlık sayfası, Premium', (t) async {
    await ciz(t, 'pn_varlik_premium',
        AssetDetailScreen(asset: _lot(), showBackButton: true),
        ek: _premium(),
        boy: 2600,
        tercih: {'pref_chart_candle': true, 'pref_chart_ema50': true});
  });
  testWidgets('sinyal ayarları, ücretsiz', (t) async {
    await ciz(t, 'pn_sinyal_ayar_ucretsiz', const SignalSettingsScreen(),
        ek: _ucretsiz(), boy: 1500);
  });
  testWidgets('sinyal ayarları, Premium', (t) async {
    await ciz(t, 'pn_sinyal_ayar_premium', const SignalSettingsScreen(),
        ek: _premium(), boy: 1500);
  });
  testWidgets('varlık ekle, ücretsiz 9/10', (t) async {
    await ciz(t, 'pn_varlik_ekle_9', const AddAssetScreen(),
        ek: _ucretsiz(), lotlar: _onLot());
  });
  testWidgets('varlık ekle, ücretsiz 10/10', (t) async {
    await ciz(t, 'pn_varlik_ekle_10', const AddAssetScreen(),
        ek: _ucretsiz(), lotlar: [..._onLot(), _lot()]);
  });
  for (final (ad, kaynak) in [
    ('sinyal', 'sinyal_gosterge'),
    ('pine', 'grafik_ozel_gosterge'),
    ('rapor', 'aylik_rapor'),
    ('alarm', 'alarm_limit'),
  ]) {
    testWidgets('paywall destesi: $kaynak', (t) async {
      await ciz(t, 'pn_deste_$ad', PaywallScreen(source: kaynak),
          ek: _ucretsiz());
    });
  }
  testWidgets('klasik paywall: liste ve tablo', (t) async {
    await ciz(t, 'pn_paywall_tablo', const PaywallScreen(source: 'settings'),
        ek: _ucretsiz(), boy: 2600, deste: false);
  });
}
