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
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/degisim_parlamasi.dart';

import 'helpers/kaynak.dart';

/// Fiyat turu değişim parlaması (Ar-Ge 11 Kas 18:04 #2): değişen tutar kısa
/// süre yön tonunda zemin alır, yanında tek seferlik ▲/▼. Yanlış yakma
/// koşulları (açılış, aynı metin, gizli tutar, kimlik değişimi) ve hareketi
/// azalt davranışı burada kilitli.
const _palet = SandikPalette.dark;

final _ok = find.byKey(const ValueKey('degisim-parlamasi-ok'));
final _ton = find.byKey(const ValueKey('degisim-parlamasi-ton'));

Future<void> _kur(
  WidgetTester tester,
  double deger, {
  String? metin,
  Object? kimlik = 'thyao',
  bool etkin = true,
  bool azalt = false,
}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [_palet]),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: azalt),
        child: Center(
          child: DegisimParlamasi(
            deger: deger,
            metin: metin ?? deger.toString(),
            kimlik: kimlik,
            etkin: etkin,
            child: Text(metin ?? deger.toString()),
          ),
        ),
      ),
    ));

Color _tonRengi(WidgetTester tester) =>
    (tester.widget<DecoratedBox>(_ton).decoration as BoxDecoration).color!;

void main() {
  testWidgets('artış: ▲ ve kazanç tonu, token süresi sonunda ikisi de gider',
      (tester) async {
    await _kur(tester, 100);
    expect(_ok, findsNothing, reason: 'ilk kurulum yakmaz');
    await _kur(tester, 101);
    await tester.pump();
    expect(find.text('▲'), findsOneWidget);
    expect(_tonRengi(tester).withValues(alpha: 1), _palet.gain);
    expect(_tonRengi(tester).a, greaterThan(0));
    await tester.pump(SandikMotion.flow);
    expect(_ok, findsNothing);
    expect(_ton, findsNothing);
  });

  testWidgets('düşüş: ▼ ve kayıp tonu', (tester) async {
    await _kur(tester, 100);
    await _kur(tester, 99);
    await tester.pump();
    expect(find.text('▼'), findsOneWidget);
    expect(_tonRengi(tester).withValues(alpha: 1), _palet.loss);
    await tester.pumpAndSettle();
    expect(_ok, findsNothing);
  });

  testWidgets('döngü yok: tek değişim tek parlama', (tester) async {
    await _kur(tester, 100);
    await _kur(tester, 101);
    await tester.pumpAndSettle();
    // Aynı değerle yeniden kurulum (başka bir sağlayıcı yenilendi).
    await _kur(tester, 101);
    await tester.pump();
    expect(_ok, findsNothing);
  });

  testWidgets('yakmaz: aynı değer', (tester) async {
    await _kur(tester, 100);
    await _kur(tester, 100);
    await tester.pump();
    expect(_ok, findsNothing);
    expect(_ton, findsNothing);
  });

  testWidgets('yakmaz: biçimlenmiş metin değişmediyse', (tester) async {
    await _kur(tester, 100.001, metin: '₺100');
    await _kur(tester, 100.004, metin: '₺100');
    await tester.pump();
    expect(_ok, findsNothing);
  });

  testWidgets('yakmaz: açılışta 0 → ilk değer', (tester) async {
    await _kur(tester, 0);
    await _kur(tester, 100);
    await tester.pump();
    expect(_ok, findsNothing);
  });

  testWidgets('yakmaz: tutar gizliyken ve göz açılınca', (tester) async {
    await _kur(tester, 100, etkin: false);
    await _kur(tester, 110, etkin: false);
    await tester.pump();
    expect(_ok, findsNothing);
    await _kur(tester, 120);
    await tester.pump();
    expect(_ok, findsNothing, reason: 'gözü açmak fiyat hareketi değil');
  });

  testWidgets('yakmaz: kimlik değişince (adet / birim / başka satır)',
      (tester) async {
    await _kur(tester, 100, kimlik: ('thyao', 10.0));
    await _kur(tester, 200, kimlik: ('thyao', 20.0));
    await tester.pump();
    expect(_ok, findsNothing);
  });

  testWidgets('kuruşun altındaki fiyat da yakar (SHIB)', (tester) async {
    await _kur(tester, 0.0005, metin: '₺0,0005');
    await _kur(tester, 0.0006, metin: '₺0,0006');
    await tester.pump();
    expect(find.text('▲'), findsOneWidget);
  });

  testWidgets('hareketi azalt: ton yok, ok sabit durur ve tek karede kalkar',
      (tester) async {
    await _kur(tester, 100, azalt: true);
    await _kur(tester, 101, azalt: true);
    await tester.pump();
    expect(_ton, findsNothing);
    expect(find.text('▲'), findsOneWidget);
    Opacity opak() => tester.widget<Opacity>(
        find.ancestor(of: _ok, matching: find.byType(Opacity)).first);
    expect(opak().opacity, 1);
    await tester.pump(SandikMotion.flow);
    expect(opak().opacity, 1, reason: 'solma yok — ok sabit');
    await tester.pump(SandikMotion.flow);
    expect(_ok, findsNothing);
  });

  testWidgets('ok ekran okuyucuya okunmaz (canlı bölge yok)', (tester) async {
    final h = tester.ensureSemantics();
    await _kur(tester, 100);
    await _kur(tester, 101);
    await tester.pump();
    expect(find.bySemanticsLabel('▲'), findsNothing);
    h.dispose();
  });

  group('Portföy kartı', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    testWidgets('fiyat turu tutarı değiştirince kart tutarı parlar; adet '
        'değişince parlamaz', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final kap = ProviderContainer(overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
      ]);
      addTearDown(kap.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: kap,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const PortfolioScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DegisimParlamasi), findsWidgets);
      expect(_ok, findsNothing, reason: 'açılış yakmaz');

      final not = kap.read(portfolioProvider.notifier) as _FakePortfolio;
      not.fiyat(320); // fiyat turu: 312,40 → 320
      await tester.pump();
      await tester.pump();
      expect(find.text('▲'), findsOneWidget);
      await tester.pump(SandikMotion.flow);
      await tester.pump();
      expect(_ok, findsNothing);

      not.fiyat(320, adet: 200); // alış: kullanıcının eylemi
      await tester.pump();
      await tester.pump();
      expect(_ok, findsNothing);
    });
  });

  test('Takip satırı fiyatı DegisimParlamasi ile sarılı', () {
    final src = ekranKaynagiSync('lib/screens/watchlist_screen.dart');
    expect(
        RegExp(r'DegisimParlamasi\(\s*deger: item\.currentPrice')
            .hasMatch(src),
        isTrue);
  });
}

const _uid = 'user-1';

Asset _asset(double fiyat, double adet) => Asset(
      id: 'THYAO.IS',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
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
  PortfolioState _durum(double fiyat, double adet) => PortfolioState(
        assets: [_asset(fiyat, adet)],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );

  @override
  Future<PortfolioState> build() async => _durum(312.40, 100);

  void fiyat(double f, {double adet = 100}) =>
      state = AsyncData(_durum(f, adet));
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}
