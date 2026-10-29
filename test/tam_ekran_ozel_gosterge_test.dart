import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/models/ozel_gosterge.dart';
import 'package:portfoy_takip/providers/ozel_gosterge_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/ozel_gosterge_screen.dart';
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/grafik_arac_cubugu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Yatay tam ekranda kendi göstergen (ƒx) — yasin 2026-10-29: *"Yan
/// çevrildiğinde detaylı grafikte custom Pine kodu için fx girilebilmeli
/// (premium hesapta)."*
///
/// Kilitlenenler:
///  · Çip dik grafikle aynı kapıda: Premium özellikleri görünmüyorsa yok.
///  · Kilitliyse paywall yolu (göstergeler sayfası açılmaz); açıksa aynı
///    göstergeler sayfası. Dokunma alanı ≥44 pt, etiketli.
///  · Açık gösterge yatay mumlarda çalışır: çip sayıyı, lejant adı yazar;
///    ayrı panelli gösterge "dik ekranda" diye söylenir.
///  · Üstte göstergeler sayfası varken dik dönmek o sayfayı kapatmaz.
const _gun = 86400000;

List<OhlcBar> _barlar(int n, int bas) => [
      for (var i = 0; i < n; i++)
        OhlcBar(
          t: bas + i * _gun,
          acilis: 100 + 10 * math.sin(i / 9),
          enYuksek: 104 + 10 * math.sin(i / 9),
          enDusuk: 96 + 10 * math.sin(i / 9),
          kapanis: 101 + 10 * math.sin(i / 9),
          hacim: 1000 + i.toDouble(),
        ),
    ];

Asset _thy() => Asset(
      id: 'thy-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 1,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 101,
      addedDate: DateTime(2025, 3, 14),
    );

const _ustKod = '''//@version=5
indicator("Ortalama 10", overlay=true)
plot(ta.sma(close, 10), "SMA10", color.blue)
''';

const _panelKod = '''//@version=5
indicator("Momentum", overlay=false)
plot(ta.rsi(close, 14), "RSI")
hline(70)
''';

class _Gostergeler extends OzelGostergelerNotifier {
  _Gostergeler(this.liste);
  final List<OzelGosterge> liste;
  @override
  Future<List<OzelGosterge>> build() async => liste;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    MumVerisi.instance.onbellegiTemizle();
    final simdi = DateTime.now();
    final bas = DateTime(simdi.year, simdi.month, simdi.day)
        .subtract(const Duration(days: 199))
        .millisecondsSinceEpoch;
    MumVerisi.testCekici = (a, ar, b, s) async => _barlar(200, bas);
  });
  tearDown(() => MumVerisi.testCekici = null);

  Widget uygulama(
          {required bool gorunur,
          required bool kilitli,
          List<OzelGosterge> liste = const [],
          Widget? home}) =>
      ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
          ozelGostergelerProvider.overrideWith(() => _Gostergeler(liste)),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home ??
              TamEkranGrafikEkrani(
                  varlik: _thy(), ad: 'THYAO', canliBirim: 101),
        ),
      );

  Future<void> ac(WidgetTester tester,
      {required bool gorunur,
      required bool kilitli,
      List<OzelGosterge> liste = const []}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        uygulama(gorunur: gorunur, kilitli: kilitli, liste: liste));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  final cip = find.byKey(const ValueKey('tamEkranOzelGosterge'));
  // Üst çubuk yatay kayar (aralıklar + ortalamalar); çip sonda.
  Future<void> cipeKaydir(WidgetTester tester) => tester.scrollUntilVisible(
      cip, 120,
      scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right));
  Future<void> bitir(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('Premium özellikleri görünmüyorsa çip yok', (tester) async {
    await ac(tester, gorunur: false, kilitli: false);
    expect(cip, findsNothing);
    final etiketler = tester
        .widgetList<GrafikCipi>(find.byType(GrafikCipi))
        .map((c) => c.label);
    expect(etiketler.where((e) => e.startsWith('ƒx')), isEmpty);
    await bitir(tester);
  });

  testWidgets('kilitli: kilit simgesi, dokunuş paywall yolu, sayfa açılmaz',
      (tester) async {
    await ac(tester, gorunur: true, kilitli: true);
    await cipeKaydir(tester);
    expect(cip, findsOneWidget);
    expect(tester.widget<GrafikCipi>(cip).kilitli, isTrue);
    await tester.tap(cip);
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeListesi), findsNothing);
    // Paywall dik grafikle aynı kaynakla açılır (testte RC kapalı:
    // `PaywallScreen.show` sessizce döner; kaynak metinden kilitlenir).
    expect(
        ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart').contains(
            "PaywallScreen.show(context, source: 'grafik_ozel_gosterge')"),
        isTrue);
    await bitir(tester);
  });

  testWidgets('açık: dokunuş göstergeler sayfasını açar; 44 pt, etiketli',
      (tester) async {
    final anlam = tester.ensureSemantics();
    await ac(tester, gorunur: true, kilitli: false);
    await cipeKaydir(tester);
    // GrafikCipi'nin kökü GenisDokunma: görsel çip küçük, alan 44 pt.
    final r = tester.getSize(cip);
    expect(r.width, greaterThanOrEqualTo(SandikTouch.min));
    expect(r.height, greaterThanOrEqualTo(SandikTouch.min));
    expect(find.bySemanticsLabel(RegExp('Kendi göstergelerin')),
        findsWidgets);
    await tester.tap(cip);
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeListesi), findsOneWidget);
    anlam.dispose();
    await bitir(tester);
  });

  testWidgets('açık gösterge yatay mumlarda çizilir; panel dik ekranda',
      (tester) async {
    await ac(tester, gorunur: true, kilitli: false, liste: const [
      OzelGosterge(id: 'a', userId: 'u1', ad: 'Ortalama 10', kod: _ustKod),
      OzelGosterge(id: 'b', userId: 'u1', ad: 'Momentum', kod: _panelKod),
      OzelGosterge(
          id: 'c', userId: 'u1', ad: 'Kapalı', kod: _ustKod, grafikte: false),
    ]);
    await tester.pump(const Duration(milliseconds: 50));
    await cipeKaydir(tester);
    expect(tester.widget<GrafikCipi>(cip).label, 'ƒx 2');
    expect(tester.widget<GrafikCipi>(cip).active, isTrue);
    expect(find.textContaining('Ortalama 10'), findsOneWidget);
    expect(find.textContaining('SMA10'), findsOneWidget);
    expect(find.text('Momentum · ayrı panel dik ekranda'), findsOneWidget);
    expect(find.textContaining('Kapalı'), findsNothing);
    await bitir(tester);
  });

  testWidgets('göstergeler sayfası açıkken dik dönmek sayfayı kapatmaz',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(uygulama(
      gorunur: true,
      kilitli: false,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => TamEkranGrafikEkrani.ac(context,
              varlik: _thy(), ad: 'THYAO', canliBirim: 101),
          child: const Text('aç'),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    await cipeKaydir(tester);
    await tester.tap(cip);
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeListesi), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeListesi), findsOneWidget,
        reason: 'dik dönüş üstteki sayfayı kapatmamalı');
    expect(find.byType(TamEkranGrafikEkrani), findsOneWidget);

    // Sayfa kapanınca tam ekran hâlâ dikte: o zaman kendini kapatır.
    Navigator.of(tester.element(find.byType(OzelGostergeListesi))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeListesi), findsNothing);
    expect(find.byType(TamEkranGrafikEkrani), findsNothing);
    expect(find.text('aç'), findsOneWidget);
    await bitir(tester);
  });
}
