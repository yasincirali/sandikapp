@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart' show LineChart;
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
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/mum_turetici.dart' show kovaBaslangici;
import 'package:shared_preferences/shared_preferences.dart';

/// Mum aralığı seçicisi (2026-10-10) — önce/sonra GÖRSEL önizlemesi,
/// `build/gorsel/` altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/mum_araligi_gorsel_test.dart
///
/// Sayılar DEMO'dur: çizgi ve mumlar aynı deterministik yapay fiyat
/// yolundan ([_fiyat]) örneklenir — canlı veri değildir (bulut kabı fiyat
/// hostlarına çıkamıyor). Gerçek kaynakların ölçümü `tool/ohlc_olcum.py`.

const _uid = 'u1';

/// Yapay fiyat yolu: trend + çok ölçekli dalga. Bugün = [son].
double _fiyat(int ms, double son) {
  final now = DateTime.now().millisecondsSinceEpoch;
  double lp(double d) =>
      0.25 * d / 365 +
      0.08 * math.sin(d / 40) +
      0.03 * math.sin(d / 7.3) +
      0.012 * math.sin(d * 3.1) +
      0.006 * math.sin(d * 29) +
      0.003 * math.sin(d * 311) +
      0.0012 * math.sin(d * 4000) +
      0.0006 * math.sin(d * 13000);
  final d = (ms - now) / 86400000;
  return son * math.exp(lp(d) - lp(0));
}

/// Varlığın işlem saati mi (yapay seri yalnız seansta nokta üretir).
bool _seansta(Asset a, DateTime t, {required bool gunIci}) {
  if (a.type == AssetType.kripto) return true;
  if (t.weekday > 5) return false;
  if (!gunIci || a.type == AssetType.fon) return true;
  final dk = t.hour * 60 + t.minute;
  return dk >= 10 * 60 && dk < 18 * 60;
}

Asset _varlik(AssetType tur, String ticker, String ad, double fiyat) => Asset(
      id: '$ticker-1',
      userId: _uid,
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: 100,
      purchasePrice: (fiyat * 0.8).roundToDouble(),
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2025, 3, 14),
    );

final _thy = _varlik(AssetType.hisse, 'THYAO.IS', 'Türk Hava Yolları', 287.5);
final _btc =
    _varlik(AssetType.kripto, 'KRIPTO:BTC', 'Bitcoin', 4091802);
final _fon = _varlik(AssetType.fon, 'TEFAS:AFT', 'Ak Portföy Yeni Teknolojiler', 2.4815);

/// Yahoo `interval` → adım.
Duration _adim(String interval) => switch (interval) {
      '1m' => const Duration(minutes: 1),
      '5m' => const Duration(minutes: 5),
      '15m' => const Duration(minutes: 15),
      '60m' || '1h' => const Duration(hours: 1),
      '1wk' => const Duration(days: 7),
      '1mo' => const Duration(days: 30),
      _ => const Duration(days: 1),
    };

Duration _donem(String range) => switch (range) {
      // Hafta sonu da son seans gelsin (motor son seans gününü seçer).
      '1d' => const Duration(days: 4),
      '5d' => const Duration(days: 7),
      '1mo' => const Duration(days: 31),
      '3mo' => const Duration(days: 92),
      '6mo' => const Duration(days: 183),
      '1y' => const Duration(days: 366),
      '2y' => const Duration(days: 731),
      _ => const Duration(days: 1830),
    };

/// Çizginin yapay serisi — mumlarla AYNI fiyat yolundan.
List<(int, double)> _seri(Asset a, String range, String interval) {
  final now = DateTime.now();
  final adim = _adim(interval);
  final gunIci = adim < const Duration(days: 1);
  final out = <(int, double)>[];
  for (var t = now.subtract(_donem(range)); t.isBefore(now); t = t.add(adim)) {
    if (!_seansta(a, t, gunIci: gunIci)) continue;
    out.add((t.millisecondsSinceEpoch, _fiyat(t.millisecondsSinceEpoch, a.currentPrice)));
  }
  out.add((now.millisecondsSinceEpoch, a.currentPrice));
  return out;
}

/// Sahte OHLC: her bar yoldan örneklenir (açılış = bar başı, kapanış = bar
/// sonu, uçlar = içerideki örneklerin uçları).
Future<List<OhlcBar>> _sahteMumlar(
    Asset a, MumAraligi aralik, DateTime bas, DateTime son) async {
  final out = <OhlcBar>[];
  final now = DateTime.now();
  var t = kovaBaslangici(bas, aralik.ms.toDouble());
  while (!t.isAfter(son)) {
    final uzunluk = barUzunluguMs(t.millisecondsSinceEpoch, aralik);
    final sonraki = t.add(Duration(milliseconds: uzunluk));
    if (_seansta(a, t, gunIci: aralik.gunIci)) {
      final t0 = t.millisecondsSinceEpoch;
      final t1 = math.min(sonraki.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      double yu = 0, du = double.infinity;
      for (var i = 0; i <= 12; i++) {
        final f = _fiyat(t0 + (t1 - t0) * i ~/ 12, a.currentPrice);
        yu = math.max(yu, f);
        du = math.min(du, f);
      }
      final o = _fiyat(t0, a.currentPrice), c = _fiyat(t1, a.currentPrice);
      final pay = (yu - du) * 0.25;
      out.add(OhlcBar(
          t: t0, acilis: o, enYuksek: yu + pay, enDusuk: du - pay, kapanis: c));
    }
    t = sonraki;
  }
  return out;
}

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
    MumVerisi.testCekici = null;
    MumVerisi.instance.onbellegiTemizle();
  });

  Future<void> ciz(
    WidgetTester tester,
    String ad, {
    required Asset varlik,
    required String donem,
    Map<String, Object> tercih = const {},
    bool premium = true,
    bool gercekMum = true,
    bool acikTema = false,
    bool imlec = false,
  }) async {
    SharedPreferences.setMockInitialValues(tercih);
    await initPreferencesCache();
    HistoryService.clearCache();
    MumVerisi.instance.onbellegiTemizle();
    HistoryService.seriCekici =
        (sym, range, interval) async => _seri(varlik, range, interval ?? '1d');
    MumVerisi.testCekici = gercekMum ? _sahteMumlar : null;
    tester.view.physicalSize = const Size(390 * 2, 1000 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio([varlik])),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        watchlistProvider.overrideWith(_Takip.new),
        if (premium) ...[
          premiumOzellikleriGorunurProvider.overrideWithValue(true),
          premiumKilitliProvider.overrideWithValue(false),
        ],
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: acikTema
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: AssetDetailScreen(asset: varlik, showBackButton: true),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text(donem).first);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    TestGesture? g;
    if (imlec) {
      final grafik = find.byType(LineChart).first;
      final r = tester.getRect(grafik);
      g = await tester.startGesture(Offset(r.left + r.width * 0.62, r.center.dy));
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveBy(const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    if (g != null) await g.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  Map<String, Object> mum(MumAraligi? a) => {
        'pref_chart_candle': true,
        if (a != null) 'pref_chart_mum_araligi': a.index,
      };

  testWidgets('önce: kapanıştan türetilmiş mum (1 yıl)', (tester) async {
    await ciz(tester, 'mum_once_1yil',
        varlik: _thy, donem: '1 yıl', tercih: mum(null), gercekMum: false);
  });
  testWidgets('önce: kapanıştan türetilmiş mum (Bugün)', (tester) async {
    await ciz(tester, 'mum_once_bugun',
        varlik: _thy, donem: 'Bugün', tercih: mum(null), gercekMum: false);
  });
  testWidgets('ücretsiz kullanıcı: değişiklik yok', (tester) async {
    await ciz(tester, 'mum_ucretsiz_1ay',
        varlik: _thy, donem: '1 ay', tercih: mum(null), premium: false);
  });
  for (final (donem, aralik) in [
    ('1 hf', MumAraligi.saat1),
    ('1 ay', MumAraligi.saat4),
    ('3 ay', MumAraligi.gun1),
    ('1 yıl', MumAraligi.hafta1),
    ('5 yıl', MumAraligi.ay1),
  ]) {
    testWidgets('sonra: THYAO $donem · ${aralik.name}', (tester) async {
      final d = donem.replaceAll(' ', '').replaceAll('ı', 'i').replaceAll('ü', 'u');
      await ciz(tester, 'mum_sonra_thy_${d}_${aralik.name}',
          varlik: _thy, donem: donem, tercih: mum(aralik));
    });
  }
  // GÜNLÜK kripto ile: 7/24 işlem görür, test hangi gün koşarsa koşsun
  // dolu bir gün çizer.
  testWidgets('sonra: BTC Bugün · otomatik (1 sa)', (tester) async {
    await ciz(tester, 'mum_sonra_btc_bugun_oto',
        varlik: _btc, donem: 'Bugün', tercih: mum(null));
  });
  testWidgets('sonra: BTC Bugün · 1 dk', (tester) async {
    await ciz(tester, 'mum_sonra_btc_bugun_dk1',
        varlik: _btc, donem: 'Bugün', tercih: mum(MumAraligi.dk1));
  });
  testWidgets('sonra: BTC Bugün · 4 sa', (tester) async {
    await ciz(tester, 'mum_sonra_btc_bugun_saat4',
        varlik: _btc, donem: 'Bugün', tercih: mum(MumAraligi.saat4));
  });
  testWidgets('sonra: fon 3 ay · gün (kapanıştan)', (tester) async {
    await ciz(tester, 'mum_sonra_fon_3ay_gun',
        varlik: _fon, donem: '3 ay', tercih: mum(MumAraligi.gun1));
  });
  testWidgets('sonra: imleç A/Y/D/K', (tester) async {
    await ciz(tester, 'mum_sonra_thy_imlec',
        varlik: _thy, donem: '3 ay', tercih: mum(MumAraligi.gun1), imlec: true);
  });
  testWidgets('sonra: açık tema, 1 ay · 4 sa', (tester) async {
    await ciz(tester, 'mum_sonra_thy_acik_4sa',
        varlik: _thy,
        donem: '1 ay',
        tercih: mum(MumAraligi.saat4),
        acikTema: true);
  });
  testWidgets('sonra: LOG + EMA ile, 5 yıl · hafta', (tester) async {
    await ciz(tester, 'mum_sonra_thy_log_ema',
        varlik: _thy,
        donem: '5 yıl',
        tercih: {
          ...mum(MumAraligi.hafta1),
          'pref_chart_log_scale': true,
          'pref_chart_ema50': true,
          'pref_chart_ema200': true,
        });
  });
}
