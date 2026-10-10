import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme 2 — Portföy küçük halkası (bayrak `portfoy_dagilim_cubugu`).
///
/// yasin'in seçimi (2026-10-08, "C"): şerit yerine küçük halka + lejant.
/// Kilitlenen davranışlar:
/// 1. Bayrak kapalı: eski büyük halka (PieChart) ekranda, küçük halka yok.
/// 2. Bayrak açık: büyük halka yerine küçük halka; lejant "Tür  %xx,x",
///    ortada toplam.
/// 3. Lejant satırı halka dilimi gibi süzer; aynı satıra yeniden dokunmak
///    kaldırır. Seçiliyken ortada türün payı görünür.
/// 4. Küçük halkaya dokunmak büyük halkayı alt sayfada açar; oradaki
///    lejant dokunuşu yine listeyi süzer.
/// 5. Dörtten fazla tür: ilk üçü + "+N tür" satırı (büyük halkayı açar).
/// 6. Halka dönerek dolar; hareketi azalt açıkken ilk karede dolu.
const _uid = 'user-1';

Asset _lot(String id, String ticker, AssetType tur, double adet, double fiyat) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

// Hisse 3.000 (%75), fon 1.000 (%25).
final _varliklar = [
  _lot('a', 'THYAO', AssetType.hisse, 10, 300),
  _lot('b', 'AFT', AssetType.fon, 100, 10),
];

Future<void> _pump(WidgetTester tester,
    {List<Asset>? varliklar, bool hareketiAzalt = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider
          .overrideWith(() => _FakePortfolio(varliklar ?? _varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: const PortfolioScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _satir(String ticker) => find.textContaining(ticker);

/// Küçük halkanın düğmesi (anlam etiketi `s3HalkayiAc`).
final _kucukHalka = find.bySemanticsLabel('Dağılımı büyük halkada aç');

/// Küçük halka kartının içinde metin (varlık satırındaki tür etiketiyle
/// karışmasın).
Finder _lejant(String metin) => find.descendant(
    of: find.byKey(const ValueKey('kucuk-halka-lejant')),
    matching: find.text(metin));

// Altı tür, her biri farklı tutarda: lejant 3 satır + "+3 tür".
final _altiTur = [
  _lot('a', 'THYAO', AssetType.hisse, 10, 600),
  _lot('b', 'AFT', AssetType.fon, 100, 50),
  _lot('c', 'GRAM', AssetType.altin, 1, 4000),
  _lot('d', 'USD', AssetType.doviz, 1, 3000),
  _lot('e', 'BTC', AssetType.kripto, 1, 2000),
  _lot('f', 'BRENT', AssetType.emtia, 1, 1000),
];

/// On tür; son ikisi %2'nin altında (300 ve 200 / 23.200). Katlanmazlar
/// (2026-10-10). Varsayılan test yüzeyinde (800pt) lejant iki sütun = 8
/// yuva; 10 öğe iki sayfa eder.
final _onTur = [
  ..._altiTur,
  _lot('g', 'BES', AssetType.bes, 1, 900),
  _lot('h', 'VADELI', AssetType.mevduat, 1, 800),
  _lot('i', 'EURB', AssetType.eurobond, 1, 300),
  _lot('j', 'DGR', AssetType.diger, 1, 200),
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('bayrak kapalı: eski halka, küçük halka yok', (tester) async {
    await _pump(tester);
    expect(find.byType(PieChart), findsOneWidget);
    expect(_kucukHalka, findsNothing);
  });

  testWidgets('bayrak açık: küçük halka, lejantta yüzdeler, ortada toplam',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    expect(find.byType(PieChart), findsNothing);
    expect(_kucukHalka, findsOneWidget);
    expect(find.text('%75,0'), findsOneWidget);
    expect(find.text('%25,0'), findsOneWidget);
    expect(find.text('toplam'), findsOneWidget);
  });

  testWidgets('lejant süzer; aynı satır süzgeci kaldırır', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    expect(_satir('THYAO'), findsWidgets);
    expect(_satir('AFT'), findsWidgets);

    await tester.tap(find.text('%25,0'));
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AFT'), findsWidgets);
    // Ortada artık toplam değil, seçili türün payı.
    expect(find.text('toplam'), findsNothing);

    await tester.tap(find.text('%25,0').last);
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsWidgets);
    expect(find.text('toplam'), findsOneWidget);
  });

  testWidgets('lejant satırı dokunma hedefi en az 44pt', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    final boy = tester.getSize(find.ancestor(
        of: find.text('%75,0'), matching: find.byType(ConstrainedBox)).first);
    expect(boy.height, greaterThanOrEqualTo(44));
  });

  testWidgets('küçük halka büyük halkayı alt sayfada açar, seçim süzer',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    await tester.tap(_kucukHalka);
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsOneWidget);

    // Büyük halkanın lejantı (dilimle aynı geri çağrı) arkadaki listeyi süzer.
    final lejant = find.descendant(
        of: find.byType(BottomSheet), matching: find.textContaining('%25,0'));
    await tester.tap(lejant);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(_satir('THYAO'), findsNothing);
    expect(_satir('AFT'), findsWidgets);
  });

  // 2026-10-09 (yasin): tür sığmayınca saklanmaz, lejant sayfalara bölünür;
  // "+N tür" satırı kalktı.
  testWidgets('altı tür tek sayfada, hepsi görünür, nokta yok',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester, varliklar: _altiTur);
    for (final ad in ['Hisse', 'Fon', 'Altın', 'Döviz', 'Kripto', 'Emtia']) {
      expect(_lejant(ad), findsOneWidget, reason: ad);
    }
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(const ValueKey('nokta-0')), findsNothing);
  });

  testWidgets(
      'on tür: küçükler katlanmaz, lejant iki sayfa + noktalar; '
      'kaydırınca küçük türler adıyla görünür', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester, varliklar: _onTur);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byKey(const ValueKey('nokta-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('nokta-1')), findsOneWidget);
    // İlk sayfa: en büyük sekiz tür; küçük ikisi sonraki sayfada.
    expect(_lejant('Hisse'), findsOneWidget);
    expect(_lejant('Mevduat'), findsOneWidget);
    expect(_lejant('Eurobond'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    // Kullanıcı kuralı 2026-10-10 ("hâlâ Diğer var"): küçük türler
    // "Diğer (2)"ye katlanmaz, kendi adıyla durur.
    expect(_lejant('Eurobond'), findsOneWidget);
    expect(_lejant('Diğer'), findsOneWidget); // gerçek "Diğer" türü
    expect(_lejant('Diğer (2)'), findsNothing);
  });

  testWidgets('kartın boyu tür sayısından bağımsız', (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    Size kart() => tester.getSize(find
        .ancestor(
            of: find.byKey(const ValueKey('kucuk-halka-lejant')),
            matching: find.byType(SandikCard))
        .first);
    await _pump(tester);
    final az = kart();
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, varliklar: _onTur);
    expect(kart().height, az.height);
  });

  testWidgets('halka dönerek dolar; hareketi azalt açıkken anında dolu',
      (tester) async {
    RemoteConfigService.testAcik = {'portfoy_dagilim_cubugu'};
    await _pump(tester);
    double ilerleme() => (tester
            .widget<CustomPaint>(find.descendant(
                of: _kucukHalka, matching: find.byType(CustomPaint)).first)
            .painter as dynamic)
        .ilerleme as double;
    // _pump 100 ms ilerletti: dolma sürüyor.
    expect(ilerleme(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(ilerleme(), 1);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, hareketiAzalt: true);
    expect(ilerleme(), 1);
  });

  test('turDagilimi: büyükten küçüğe, paylar toplamı 1', () {
    final d = turDagilimi(_varliklar,
        PortfolioState(assets: _varliklar, usdTry: 42, eurTry: 46, gbpTry: 54));
    expect(d.map((e) => e.grup.tur), [AssetType.hisse, AssetType.fon]);
    expect(d.first.pay, closeTo(0.75, 1e-9));
    expect(d.fold<double>(0, (s, e) => s + e.pay), closeTo(1, 1e-9));
  });
}
