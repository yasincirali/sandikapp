import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/ilk_varlik_secimi.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';
import 'package:portfoy_takip/widgets/ilk_varlik_vitrini.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';
import 'package:portfoy_takip/widgets/portfolio_summary_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Canlı fiyat vitrini" — boş ana ekran (sadeleştirme 2, bayrak
/// `ilk_varlik_kolay`; kullanıcı seçimi 2026-10-04).
///
/// Değişmezler:
///   * Bayrak KAPALIYKEN boş ekran ve ₺0 toplam kartı birebir eski.
///   * Bayrak açıkken ₺0 kartı yok, vitrin altı kutu + "diğerleri" + ekstre.
///   * Kutu fiyatı, formun kaydedeceği sembolün fiyatı (fiyat sözleşmesi);
///     bilinmeyen fiyat yazılmaz.
///   * Hareket biter ve DURUR (boşta kare kapısı); hareketi azalt açıkken
///     hiç oynamaz.

const _uid = 'user-1';

const _kotasyon = <String, YahooQuote>{
  'ALTIN_GRAM24': YahooQuote(
      symbol: 'ALTIN_GRAM24',
      regularMarketPrice: 6541.91,
      regularMarketChangePercent: 0.45),
  'USDTRY=X': YahooQuote(
      symbol: 'USDTRY=X',
      regularMarketPrice: 42.15,
      regularMarketChangePercent: 0.12),
  'EURTRY=X': YahooQuote(
      symbol: 'EURTRY=X',
      regularMarketPrice: 48.9,
      regularMarketChangePercent: -0.08),
  'ALTIN_CEYREK': YahooQuote(
      symbol: 'ALTIN_CEYREK',
      regularMarketPrice: 10712.45,
      regularMarketChangePercent: -0.21),
};

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
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
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

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

/// Yükleyici çağrılarını sayar; dönen kotasyon testte değiştirilebilir.
class _Yukleyici {
  Map<String, YahooQuote> donen = _kotasyon;
  final istenen = <List<String>>[];
  Future<Map<String, YahooQuote>> call(List<String> s) async {
    istenen.add(s);
    return donen;
  }
}

Future<void> _anaEkran(
  WidgetTester tester, {
  double genislik = 390,
  _Yukleyici? yukleyici,
  bool hareketiAzalt = false,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final y = yukleyici ?? _Yukleyici();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      vitrinKotasyonYukleyiciProvider.overrideWithValue(y.call),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Gerçek zaman gibi ilerle: tek büyük `pump` yalnız BİR kare atar ve
/// ardışık animasyonların (iki nabız) ikincisi o karede yeni başlamış olur.
Future<void> _bekle(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// `pushGuarded` çift dokunuş penceresi GERÇEK saatle ölçülür (500 ms);
/// art arda testlerde ikinci push yutulmasın.
Future<void> _pushPenceresi(WidgetTester tester) => tester
    .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 550)));

Finder _vitrinde(Finder f) =>
    find.descendant(of: find.byType(IlkVarlikVitrini), matching: f);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('kurallar', () {
    test('kutu fiyatı formun kaydedeceği sembolden — şeritle aynı altın', () {
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.gramAltin),
          PiyasaSeridi.altinSembolu,
          reason: 'gram altın 24 ayar; şerit ve form aynı ürünü göstermeli');
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.ceyrekAltin),
          'ALTIN_CEYREK');
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.dolar), 'USDTRY=X');
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.euro), 'EURTRY=X');
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.fon), isNull);
      expect(IlkVarlikVitrini.fiyatSembolu(IlkVarlikSecimi.hisse), isNull);
      // Her hazır seçeneğin bir fiyatı olmalı; olmayanın açıklaması var.
      for (final s in IlkVarlikVitrini.siralama) {
        expect(IlkVarlikVitrini.fiyatSembolu(s) != null, s.varlikHazir,
            reason: '$s');
      }
      expect(IlkVarlikVitrini.siralama.toSet(), IlkVarlikSecimi.values.toSet(),
          reason: 'her seçenek vitrinde bir kez');
    });

    test('₺0 kartı yalnız boş defter + ortak yokken gizlenir', () {
      bool k(bool bos, bool ortak) =>
          IlkVarlikVitrini.toplamKartiYerine(bosKendi: bos, ortakVar: ortak);
      expect(k(true, false), isTrue);
      expect(k(false, false), isFalse, reason: 'dolu defter');
      expect(k(true, true), isFalse,
          reason: 'ortak varken görünüm çipi kartın üstünde — kart kalır');
    });
  });

  group('ana ekran, boş portföy', () {
    testWidgets('vitrin var, ₺0 kartı ve eski boş ekran yok',
        (tester) async {
      await _anaEkran(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(IlkVarlikVitrini), findsOneWidget);
      expect(find.byType(PortfolioSummaryWidget), findsNothing);
      expect(find.byIcon(Icons.savings_outlined), findsNothing);
      expect(find.text('Henüz varlık eklenmemiş'), findsNothing);
      expect(find.text('Başka bir tür ekle'), findsNothing);

      expect(_vitrinde(find.text('Neye sahipsin?')), findsOneWidget);
      for (final ad in [
        'Gram altın',
        'Dolar',
        'Euro',
        'Çeyrek altın',
        'Fon',
        'Hisse',
      ]) {
        expect(_vitrinde(find.text(ad)), findsOneWidget, reason: ad);
      }
      // Canlı fiyatlar ve yönleri.
      expect(_vitrinde(find.text('₺6.541,91')), findsOneWidget);
      expect(_vitrinde(find.text('₺42,15')), findsOneWidget);
      expect(_vitrinde(find.text('▼ %0,08')), findsOneWidget);
      expect(_vitrinde(find.text('₺10.712,45')), findsOneWidget);
      expect(_vitrinde(find.text("TEFAS'taki tüm fonlar")), findsOneWidget);
      expect(_vitrinde(find.text('Borsa İstanbul')), findsOneWidget);
      expect(_vitrinde(find.text('Fiyatlar canlı')), findsOneWidget);
      // Ekstre satırı.
      expect(_vitrinde(find.text('Ekstreden aktar')), findsOneWidget);
      // "Diğerleri" bağlantısı (SiganMetin `find.text`'e görünmez).
      expect(find.bySemanticsLabel('Kripto, emtia, mevduat, BES ve diğerleri'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fiyat bilinmiyorsa sayı yazılmaz, "canlı" denmez',
        (tester) async {
      await _anaEkran(tester, yukleyici: _Yukleyici()..donen = const {});
      await tester.pump(const Duration(seconds: 1));
      expect(_vitrinde(find.text('—')), findsNWidgets(4));
      expect(_vitrinde(find.text('Fiyatlar canlı')), findsNothing);
      expect(_vitrinde(find.textContaining('₺')), findsNothing);
    });

    for (final w in <double>[320, 390]) {
      testWidgets('${w.toInt()}pt: taşma yok', (tester) async {
        await _anaEkran(tester, genislik: w);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        // İki sütun: aynı satırdaki kutular aynı hizada, yan yana.
        final altin = tester.getTopLeft(_vitrinde(find.text('Gram altın')));
        final dolar = tester.getTopLeft(_vitrinde(find.text('Dolar')));
        expect(dolar.dx, greaterThan(altin.dx));
        expect(dolar.dy, altin.dy);
      });
    }

    testWidgets('320pt + büyük yazı (1,3×): taşma yok', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          vitrinKotasyonYukleyiciProvider.overrideWithValue(_Yukleyici().call),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: IlkVarlikVitrini(
                  onSec: (_) {}, onDiger: () {}, onEkstre: () {}),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('kutuya dokununca form o seçimle açılır', (tester) async {
      for (final (ad, beklenen) in [
        ('Çeyrek altın', IlkVarlikSecimi.ceyrekAltin),
        ('Euro', IlkVarlikSecimi.euro),
        ('Hisse', IlkVarlikSecimi.hisse),
      ]) {
        await _anaEkran(tester);
        await tester.pump(const Duration(seconds: 1));
        await _pushPenceresi(tester);
        await tester.tap(_vitrinde(find.text(ad)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final form = tester.widget<AddAssetScreen>(find.byType(AddAssetScreen));
        expect(form.hizliSecim, beklenen, reason: ad);
        // Sonraki tur için ağacı sök.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('"diğerleri" ön seçimsiz formu açar', (tester) async {
      await _anaEkran(tester);
      await tester.pump(const Duration(seconds: 1));
      await _pushPenceresi(tester);
      await tester.tap(
          find.bySemanticsLabel('Kripto, emtia, mevduat, BES ve diğerleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final form = tester.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(form.hizliSecim, isNull);
    });
  });

  group('hareket', () {
    Future<_Yukleyici> vitrin(WidgetTester tester,
        {bool hareketiAzalt = false}) async {
      final y = _Yukleyici();
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [vitrinKotasyonYukleyiciProvider.overrideWithValue(y.call)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: hareketiAzalt),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: IlkVarlikVitrini(
                  onSec: (_) {}, onDiger: () {}, onEkstre: () {}),
            ),
          ),
        ),
      ));
      return y;
    }

    double enDusukSaydamlik(WidgetTester tester) => tester
        .widgetList<Opacity>(_vitrinde(find.byType(Opacity)))
        .map((o) => o.opacity)
        .fold(1.0, (a, b) => a < b ? a : b);

    testWidgets('giriş bir kez oynar, biter ve ekran boşta kare çizmez',
        (tester) async {
      await vitrin(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expect(enDusukSaydamlik(tester), lessThan(1.0),
          reason: 'giriş kademeli başlamalı');
      // Giriş (480 ms) + iki nabız (2 × 560 ms) — hepsi biter.
      await _bekle(tester, 500);
      expect(enDusukSaydamlik(tester), 1.0, reason: 'giriş ~500 ms içinde');
      await _bekle(tester, 2000);
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'sonsuz animasyon boşta kare kapısını kırar');
    });

    testWidgets('aynı fiyat gelirse hiçbir şey oynamaz; değişince kayar',
        (tester) async {
      final y = await vitrin(tester);
      await _bekle(tester, 3000);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Aynı değerle nabız: kare yok.
      await TazelikRitmi.nabiz.atForTest();
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'aynı değer yeniden canlandırılmamalı');

      // Dolar değişti: yeni sayı gelir, eskisi gider.
      y.donen = {
        ..._kotasyon,
        'USDTRY=X': const YahooQuote(
            symbol: 'USDTRY=X',
            regularMarketPrice: 42.31,
            regularMarketChangePercent: 0.5),
      };
      await TazelikRitmi.nabiz.atForTest();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'değişen fiyat yumuşakça geçmeli');
      await _bekle(tester, 2000);
      expect(_vitrinde(find.text('₺42,31')), findsOneWidget);
      expect(_vitrinde(find.text('₺42,15')), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('hareketi azalt: giriş ve nabız yok, ilk karede tam',
        (tester) async {
      await vitrin(tester, hareketiAzalt: true);
      await tester.pump();
      expect(enDusukSaydamlik(tester), 1.0);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'hareketi azalt açıkken hiçbir controller koşmamalı');
      expect(_vitrinde(find.text('₺6.541,91')), findsOneWidget);
    });
  });
}
