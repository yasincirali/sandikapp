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
import 'package:portfoy_takip/models/ozel_gosterge.dart';
import 'package:portfoy_takip/providers/ozel_gosterge_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/ozel_gosterge_screen.dart';
import 'package:portfoy_takip/services/gosterge_betigi/betik.dart';
import 'package:portfoy_takip/services/gosterge_betigi/katalog.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kendi göstergeni yaz — GÖRSEL önizleme (`build/gorsel/ozel_gosterge_*`).
/// yasin'e gösterilen ekran görüntüleri buradan. Assert etmez; `gorsel`
/// etiketi CI'da atlanır.
///   flutter test --run-skipped test/ozel_gosterge_gorsel_onizleme_test.dart
///
/// Sayılar DEMO'dur (sabit, yapay seri); canlı veri değildir.

const _uid = 'u1';

Asset _lot() => Asset(
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

/// Yapay ama "piyasa gibi" seri: istenen aralık adımıyla örneklenir ve
/// bugün canlı fiyata (312,40) oturur — grafik ucunda sıçrama olmaz. DEMO.
double _fiyat(double gunOnce) =>
    312.4 +
    9 * math.sin(gunOnce / 9) +
    4 * math.sin(gunOnce / 2.3) +
    1.5 * math.sin(gunOnce * 3.1) -
    0.06 * gunOnce;

List<(int, double)> _yapaySeri([String? aralik]) {
  final now = DateTime.now();
  final adim = switch (aralik) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '30m' => const Duration(minutes: 30),
    '1h' || '60m' => const Duration(hours: 1),
    '1wk' => const Duration(days: 7),
    _ => const Duration(days: 1),
  };
  final adet = math.min(800, (const Duration(days: 730).inMinutes / adim.inMinutes).floor());
  return [
    for (var i = adet; i >= 0; i--)
      (
        now.subtract(adim * i).millisecondsSinceEpoch,
        _fiyat(adim.inMinutes * i / 1440),
      ),
  ];
}

class _Gostergeler extends OzelGostergelerNotifier {
  _Gostergeler(this._l);
  final List<OzelGosterge> _l;
  @override
  Future<List<OzelGosterge>> build() async => _l;
}

OzelGosterge _g(String id, String ad, String kod, {bool grafikte = true}) =>
    OzelGosterge(id: id, userId: _uid, ad: ad, kod: kod, grafikte: grafikte);

String _sablon(String k) => kBetikSablonlari.firstWhere((s) => s.kimlik == k).kod;

final _ornekler = [
  _g('1', 'EMA kesişimi', _sablon('ema_kesisim')),
  _g('2', 'RSI (14)', _sablon('rsi')),
  _g('3', 'Bollinger', _sablon('bollinger'), grafikte: false),
  _g('4', 'Hatalı deneme', 'plot(smaa(close, 3))', grafikte: false),
];

BetikVerisi _onizlemeVerisi() {
  final s = _yapaySeri();
  final son = s.sublist(s.length - 260);
  return BetikVerisi.yalnizKapanis(
    [for (var i = 0; i < son.length; i++) i.toDouble()],
    [for (final p in son) p.$2],
  );
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
    // Kod alanı eş aralıklı yazıyla çizilir (cihazda Menlo/monospace);
    // test ortamında sistemdeki DejaVu Sans Mono yüklenir, yoksa kutular.
    final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
    if (mono.existsSync()) {
      final f = FontLoader('monospace')
        ..addFont(Future.value(
            ByteData.view(mono.readAsBytesSync().buffer)));
      await f.load();
    }
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    HistoryService.clearCache();
    HistoryService.seriCekici =
        (sym, range, interval) async => _yapaySeri(interval);
  });
  tearDown(() =>
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

  Future<void> ciz(WidgetTester tester, String ad, Widget ekran,
      {required bool acik,
      bool kilitli = false,
      bool gorunur = true,
      double boy = 2200,
      Future<void> Function()? sonra}) async {
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio([_lot()])),
        authProvider.overrideWith(_FakeAuth.new),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        signalProvider.overrideWith(_FakeSignals.new),
        watchlistProvider.overrideWith(_Takip.new),
        premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
        premiumKilitliProvider.overrideWithValue(kilitli),
        ozelGostergelerProvider.overrideWith(() => _Gostergeler(_ornekler)),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: acik
              ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
              : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: ekran,
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (sonra != null) {
      await sonra();
      for (var i = 0; i < 20; i++) {
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

  for (final acik in [false, true]) {
    final tema = acik ? 'acik' : 'koyu';
    testWidgets('varlık detayı göstergelerle ($tema)', (tester) async {
      await ciz(tester, 'ozel_gosterge_detay_$tema',
          AssetDetailScreen(asset: _lot(), showBackButton: true),
          acik: acik, boy: 1500);
    });

    testWidgets('düzenleyici şablonla ($tema)', (tester) async {
      await ciz(
        tester,
        'ozel_gosterge_editor_$tema',
        OzelGostergeEditorScreen(
          sablon: kBetikSablonlari.first,
          onizleme: _onizlemeVerisi(),
          varlikAdi: 'THYAO',
        ),
        acik: acik,
        boy: 1100,
      );
    });
  }

  testWidgets('göstergeler sayfası (koyu)', (tester) async {
    await ciz(
      tester,
      'ozel_gosterge_sayfa_koyu',
      Builder(
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.c.background,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: ctx.c.surface1,
              child: OzelGostergeListesi(onizleme: _onizlemeVerisi()),
            ),
          ),
        ),
      ),
      acik: false,
      boy: 844,
    );
  });

  testWidgets('düzenleyici RSI ayrı panel (koyu)', (tester) async {
    await ciz(
      tester,
      'ozel_gosterge_editor_rsi_koyu',
      OzelGostergeEditorScreen(
        gosterge: _ornekler[1],
        onizleme: _onizlemeVerisi(),
        varlikAdi: 'THYAO',
      ),
      acik: false,
      boy: 1100,
    );
  });

  testWidgets('düzenleyici hata (koyu)', (tester) async {
    await ciz(
      tester,
      'ozel_gosterge_editor_hata_koyu',
      OzelGostergeEditorScreen(
        gosterge: _g('9', 'Deneme', 'hizli = ema(close, 9)\nplot(hizli + )\n'),
        onizleme: _onizlemeVerisi(),
        varlikAdi: 'THYAO',
      ),
      acik: false,
      boy: 1100,
    );
  });

  testWidgets('kilitli çip (koyu)', (tester) async {
    await ciz(tester, 'ozel_gosterge_kilitli_koyu',
        AssetDetailScreen(asset: _lot(), showBackButton: true),
        acik: false, kilitli: true, boy: 900);
  });

  testWidgets('canlı kullanıcı, paywall kapalı: grafik birebir eski (koyu)',
      (tester) async {
    await ciz(tester, 'ozel_gosterge_canli_kullanici_koyu',
        AssetDetailScreen(asset: _lot(), showBackButton: true),
        acik: false, gorunur: false, boy: 900);
  });
}
