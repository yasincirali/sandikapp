import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/disclaimer_widget.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';

/// `donem_hafizasi` (Sadeleştirme 2): tek ortak dönem.
///
/// Bayrak kapalıyken her yüzey eski varsayılanını korur (Takip 1A, varlık
/// detayı 1H, varlık sayfası 1Y); açıkken hepsi [seciliDonemProvider]'ı
/// okur/yazar, gösteremediği dönemde en yakını gösterir ama ortak değeri
/// değiştirmez.

const _uid = 'user-1';

Asset _asset({bool elle = false}) => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: elle ? '' : 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: elle,
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
  _FakePortfolio(this._a);
  final Asset _a;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_a],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _BosTakip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

const _thy = VarlikKimligi(
  ticker: 'THYAO.IS',
  name: 'Türk Hava Yolları',
  type: AssetType.hisse,
  currency: 'TRY',
);

Future<Map<int, double>> _seri(String ticker, int gun) async {
  final son = DateTime(2026, 9, 28, 17).millisecondsSinceEpoch;
  final bas = son - Duration(days: gun == 1 ? 0 : gun).inMilliseconds -
      const Duration(hours: 8).inMilliseconds;
  return {bas: 100.0, son: 100.0 + gun / 10};
}

DonemSecici _secici(WidgetTester t) =>
    t.widget<DonemSecici>(find.byType(DonemSecici));

ProviderContainer _kap(WidgetTester t, Type tur) =>
    ProviderScope.containerOf(t.element(find.byType(tur)));

Future<void> _detay(WidgetTester t, Asset a) async {
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(a)),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: a, showBackButton: true),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _takip(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 3, 900 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      watchlistProvider.overrideWith(_BosTakip.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(_asset())),
    ],
    child: const MaterialApp(home: Scaffold(body: WatchlistBody())),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _sayfa(WidgetTester t, YatirimciSeviyesi seviye) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => _FakePortfolio(_asset())),
      watchlistProvider.overrideWith(_BosTakip.new),
      yatirimciSeviyesiProvider.overrideWithValue(seviye),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: VarlikSayfasi(kimlik: _thy, tamAcilis: true, seriYukleyici: _seri),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Tembel liste: panel ve yasal ibare ekranın altında; ibare görünene
/// kadar kaydırılır (ibare iki seviyede de yerinde kalır).
Future<void> _sonaKaydir(WidgetTester t) async {
  await t.scrollUntilVisible(find.byType(DisclaimerWidget), 300,
      scrollable: find.byType(Scrollable).last);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  group('sağlayıcı', () {
    test('başlangıç GÜNLÜK (Performans\'ın bugünkü varsayılanı)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(seciliDonemProvider), SummaryPeriod.gunluk);
    });

    test('gösterilemeyen dönem en yakına düşer: GÜNLÜK → 1H', () {
      final gunluksuz = SummaryPeriod.values.sublist(1);
      expect(gosterilebilirDonem(SummaryPeriod.gunluk, gunluksuz),
          SummaryPeriod.birHafta);
      expect(gosterilebilirDonem(SummaryPeriod.altiAy, gunluksuz),
          SummaryPeriod.altiAy);
      // Eşitlikte uzun dönem: 3A yoksa 1A ve 6A eşit uzak → 6A.
      expect(
          gosterilebilirDonem(SummaryPeriod.ucAy, [
            SummaryPeriod.birAy,
            SummaryPeriod.altiAy,
          ]),
          SummaryPeriod.altiAy);
    });

    test('bayrak kapalı: Takip kendi 1A\'sında, ortak dönemi izlemez', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(watchlistPeriodProvider), SummaryPeriod.birAy.index);
      c.read(seciliDonemProvider.notifier).state = SummaryPeriod.besYil;
      expect(c.read(watchlistPeriodProvider), SummaryPeriod.birAy.index);
    });

    test('bayrak açık: Takip ortak dönemden türer', () {
      RemoteConfigService.testAcik = {'donem_hafizasi'};
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(watchlistPeriodProvider), SummaryPeriod.gunluk.index);
      c.read(seciliDonemProvider.notifier).state = SummaryPeriod.besYil;
      expect(c.read(watchlistPeriodProvider), SummaryPeriod.besYil.index);
    });
  });

  group('Takip listesi', () {
    testWidgets('bayrak kapalı: 1A açılır, seçim ortak döneme yazılmaz',
        (t) async {
      await _takip(t);
      expect(_secici(t).secili, SummaryPeriod.birAy.index);
      _secici(t).onSec(SummaryPeriod.altiAy.index);
      await t.pump();
      final c = _kap(t, WatchlistBody);
      expect(_secici(t).secili, SummaryPeriod.altiAy.index);
      expect(c.read(seciliDonemProvider), SummaryPeriod.gunluk);
    });

    testWidgets('bayrak açık: ortak dönemi gösterir ve yazar', (t) async {
      RemoteConfigService.testAcik = {'donem_hafizasi'};
      await _takip(t);
      final c = _kap(t, WatchlistBody);
      expect(_secici(t).secili, SummaryPeriod.gunluk.index);

      _secici(t).onSec(SummaryPeriod.birYil.index);
      await t.pump();
      expect(c.read(seciliDonemProvider), SummaryPeriod.birYil);
      expect(_secici(t).secili, SummaryPeriod.birYil.index);

      // Başka yüzeyde seçilen dönem burada da seçili.
      c.read(seciliDonemProvider.notifier).state = SummaryPeriod.ucAy;
      await t.pump();
      expect(_secici(t).secili, SummaryPeriod.ucAy.index);
    });
  });

  group('varlık detayı', () {
    testWidgets('bayrak kapalı: HAFTALIK varsayılanı korunur', (t) async {
      await _detay(t, _asset());
      expect(_secici(t).donemler[_secici(t).secili], SummaryPeriod.birHafta);
      _secici(t).onSec(SummaryPeriod.altiAy.index);
      await t.pump();
      expect(_kap(t, AssetDetailScreen).read(seciliDonemProvider),
          SummaryPeriod.gunluk);
    });

    testWidgets('bayrak açık: ortak dönemle açılır, seçim yazılır, dışarıdan '
        'değişim izlenir', (t) async {
      RemoteConfigService.testAcik = {'donem_hafizasi'};
      await _detay(t, _asset());
      final c = _kap(t, AssetDetailScreen);
      expect(_secici(t).donemler[_secici(t).secili], SummaryPeriod.gunluk);

      _secici(t).onSec(SummaryPeriod.altiAy.index);
      await t.pump();
      expect(c.read(seciliDonemProvider), SummaryPeriod.altiAy);
      expect(_secici(t).donemler[_secici(t).secili], SummaryPeriod.altiAy);

      c.read(seciliDonemProvider.notifier).state = SummaryPeriod.besYil;
      await t.pump();
      expect(_secici(t).donemler[_secici(t).secili], SummaryPeriod.besYil);
    });

    testWidgets('bayrak açık, GÜNLÜK\'süz varlık: 1H gösterilir, ortak '
        'GÜNLÜK değişmez; seçim DEĞERLE eşlenir', (t) async {
      RemoteConfigService.testAcik = {'donem_hafizasi'};
      await _detay(t, _asset(elle: true));
      final c = _kap(t, AssetDetailScreen);
      expect(_secici(t).donemler.first, SummaryPeriod.birHafta);
      expect(_secici(t).donemler[_secici(t).secili], SummaryPeriod.birHafta);
      expect(c.read(seciliDonemProvider), SummaryPeriod.gunluk);

      // Ham indeks 2 bu listede 3A'dır (SummaryPeriod.values'ta 1A olurdu).
      _secici(t).onSec(2);
      await t.pump();
      expect(c.read(seciliDonemProvider), SummaryPeriod.ucAy);
    });
  });

  group('varlık sayfası', () {
    testWidgets('bayrak kapalı: 1Y varsayılanı', (t) async {
      await _sayfa(t, YatirimciSeviyesi.orta);
      expect(_secici(t).secili, SummaryPeriod.birYil.index);
    });

    testWidgets('bayrak açık: ortak dönemle açılır ve yazar', (t) async {
      RemoteConfigService.testAcik = {'donem_hafizasi'};
      await _sayfa(t, YatirimciSeviyesi.orta);
      expect(_secici(t).secili, SummaryPeriod.gunluk.index);
      _secici(t).onSec(SummaryPeriod.ucAy.index);
      await t.pump();
      expect(_kap(t, VarlikSayfasi).read(seciliDonemProvider),
          SummaryPeriod.ucAy);
    });

    // Varlık detayıyla aynı seviye kapısı (bayraksız hata düzeltmesi).
    testWidgets('teknik sinyal paneli Başlangıç\'ta yok', (t) async {
      await _sayfa(t, YatirimciSeviyesi.baslangic);
      await _sonaKaydir(t);
      expect(find.byType(TechnicalSignalPanel), findsNothing);
    });

    testWidgets('teknik sinyal paneli Orta\'da var', (t) async {
      await _sayfa(t, YatirimciSeviyesi.orta);
      await _sonaKaydir(t);
      expect(find.byType(TechnicalSignalPanel), findsOneWidget);
    });
  });
}
