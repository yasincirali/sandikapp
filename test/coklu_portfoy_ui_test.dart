import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/portfoy_yonetimi_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/portfoy_secici.dart';
import 'package:portfoy_takip/widgets/portfoy_secim_sayfasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Çoklu portföy arayüzü (0133): bayrak kapalıyken HİÇBİR yeni yüzey yok ve
/// liste birebir eski; açıkken seçici, süzgeç, işlemde portföy sorusu ve
/// yönetim.
const _uid = 'user-1';
const _a = 'pf-a';
const _b = 'pf-b';

Asset _lot(String id, String ticker, double adet, double fiyat,
        {String? portfoy, double guncel = 150}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: guncel,
      addedDate: DateTime(2026, 3, 14),
      portfoyId: portfoy,
    );

// ASELS iki portföyde (A 10@100, B 10@200), THYAO Ana'da, SISE A'da.
final _defter = [
  _lot('1', 'ASELS', 10, 100, portfoy: _a),
  _lot('2', 'ASELS', 10, 200, portfoy: _b),
  _lot('3', 'THYAO', 5, 300, guncel: 320),
  _lot('4', 'SISE', 7, 40, portfoy: _a, guncel: 45),
];

const _liste = [
  Portfoy(id: _a, userId: _uid, ad: 'Emeklilik', sira: 1),
  Portfoy(id: _b, userId: _uid, ad: 'Çocuk', sira: 2),
];

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
      PortfolioState(assets: _assets, ownerId: _uid);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _SabitPortfoyler extends PortfoylerNotifier {
  _SabitPortfoyler(this.ilk);
  final List<Portfoy> ilk;
  final olusturulan = <String>[];
  @override
  Future<List<Portfoy>> build() async => ilk;
  @override
  Future<Portfoy> olustur(String ad) async {
    if (ad.trim().toLowerCase() == 'emeklilik') {
      throw const PortfoyAdiKullaniliyor();
    }
    olusturulan.add(ad);
    final p = Portfoy(id: 'yeni', userId: _uid, ad: ad, sira: 9);
    state = AsyncData([...ilk, p]);
    return p;
  }
}

List<Override> _ortak({bool premium = true}) => [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(_defter)),
      partnersProvider.overrideWith(_FakePartners.new),
      portfoylerProvider.overrideWith(() => _SabitPortfoyler(_liste)),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      magazaPremiumProvider.overrideWith((_) => premium),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
    ];

Future<void> _portfoyEkrani(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _ortak(),
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  group('Portföy ekranı', () {
    testWidgets('bayrak kapalı: seçici yok, liste havuz (bugünkü)', (t) async {
      await _portfoyEkrani(t);
      expect(find.byKey(const ValueKey('portfoy-cip-tumu')), findsNothing);
      expect(find.textContaining('ASELS'), findsWidgets);
      expect(find.byType(PortfoySecici, skipOffstage: false), findsOneWidget,
          reason: 'widget var ama sıfır boy çizer');
      expect(
          t.getSize(find.byType(PortfoySecici, skipOffstage: false)).height, 0);
      expect(find.textContaining('THYAO'), findsWidgets);
      expect(find.textContaining('SISE'), findsWidgets);
    });

    testWidgets('bayrak + paywall: seçici; portföy seçince liste süzülür',
        (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      await _portfoyEkrani(t);
      for (final k in ['tumu', 'ana', _a, _b, 'yeni', 'yonet']) {
        expect(find.byKey(ValueKey('portfoy-cip-$k')), findsOneWidget,
            reason: k);
      }
      expect(find.textContaining('THYAO'), findsWidgets);

      await t.tap(find.byKey(const ValueKey('portfoy-cip-$_a')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('THYAO'), findsNothing,
          reason: 'Ana\'daki THYAO Emeklilik görünümünde yok');
      expect(find.textContaining('SISE'), findsWidgets);
      expect(find.textContaining('ASELS'), findsWidgets);

      await t.tap(find.byKey(const ValueKey('portfoy-cip-ana')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('THYAO'), findsWidgets);
      expect(find.textContaining('SISE'), findsNothing);
      expect(find.textContaining('ASELS'), findsNothing);
    });

    testWidgets('bayrak açık ama paywall kapalı ve admin değil: görünmez',
        (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      await _portfoyEkrani(t);
      expect(find.byKey(const ValueKey('portfoy-cip-tumu')), findsNothing);
    });
  });

  group('işlemde portföy sorusu (karışık pozisyon)', () {
    Future<Asset?> calistir(WidgetTester t, Asset varlik,
        {String? secim}) async {
      Asset? sonuc;
      var bitti = false;
      await t.pumpWidget(ProviderScope(
        overrides: _ortak(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  sonuc = await islemIcinPozisyon(ctx, varlik);
                  bitti = true;
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      // Sağlayıcılar yüklensin.
      final kap = ProviderScope.containerOf(t.element(find.text('aç')));
      await kap.read(portfolioProvider.future);
      await kap.read(portfoylerProvider.future);
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      if (secim != null) {
        await t.tap(find.byKey(ValueKey('portfoy-secenek-$secim')));
        await t.pumpAndSettle();
      }
      expect(bitti, isTrue);
      return sonuc;
    }

    Asset karisik() => Asset(
          id: 'pos:x',
          userId: _uid,
          name: 'ASELS',
          ticker: 'ASELS',
          type: AssetType.hisse,
          quantity: 20,
          purchasePrice: 150,
          currency: 'TRY',
          notes: '',
          portfoyKarisik: true,
        );

    testWidgets('bayrak kapalı: soru yok, varlık aynen', (t) async {
      final v = karisik();
      final r = await calistir(t, v);
      expect(identical(r, v), isTrue);
    });

    testWidgets('bayrak açık: iki portföy sorulur, seçilenin maliyeti döner',
        (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      final r = await calistir(t, karisik(), secim: _b);
      expect(r, isNotNull);
      expect(r!.portfoyId, _b);
      expect(r.portfoyKarisik, isFalse);
      expect(r.purchasePrice, 200);
      expect(r.quantity, 10, reason: 'satış sınırı B\'nin miktarı');
    });

    testWidgets('karışık olmayan pozisyon: soru yok', (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      final tek = _lot('9', 'SISE', 7, 40, portfoy: _a);
      final r = await calistir(t, tek);
      expect(identical(r, tek), isTrue);
    });
  });

  group('ad sayfası', () {
    Future<void> ac(WidgetTester t, Future<void> Function(String) kaydet) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PortfoyAdiSayfasi(
                baslik: 'Yeni portföy', dugme: 'Oluştur', kaydet: kaydet),
          ),
        ));

    testWidgets('boş ad sunucuya gitmeden reddedilir', (t) async {
      var cagrildi = false;
      await ac(t, (_) async => cagrildi = true);
      await t.tap(find.byKey(const ValueKey('portfoy-adi-kaydet')));
      await t.pumpAndSettle();
      expect(cagrildi, isFalse);
      expect(find.textContaining('1 ile 40'), findsOneWidget);
    });

    testWidgets('aynı ad: alanın altında söylenir, sayfa açık kalır',
        (t) async {
      await ac(t, (_) async => throw const PortfoyAdiKullaniliyor());
      await t.enterText(
          find.byKey(const ValueKey('portfoy-adi-alani')), 'Emeklilik');
      await t.tap(find.byKey(const ValueKey('portfoy-adi-kaydet')));
      await t.pumpAndSettle();
      expect(find.textContaining('Bu adda bir portföyün'), findsOneWidget);
      expect(find.byType(PortfoyAdiSayfasi), findsOneWidget);
    });
  });

  group('yönetim ekranı', () {
    testWidgets('Ana sabit; adlandırılmış portföyler değerleriyle', (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      t.view.physicalSize = const Size(390 * 3, 1200 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: _ortak(),
        child: MaterialApp(
            theme: ThemeData.dark(), home: const PortfoyYonetimiScreen()),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('portfoy-satir-ana')), findsOneWidget);
      expect(find.text('Emeklilik'), findsOneWidget);
      expect(find.text('Çocuk'), findsOneWidget);
      // Sil → alt sayfa: kayıt sayısı ve "Ana'ya döner".
      await t.tap(find.byTooltip('Portföyü sil').first);
      await t.pumpAndSettle();
      expect(find.textContaining('2 kayıt Ana portföye döner'), findsOneWidget,
          reason: 'Emeklilik: ASELS + SISE');
    });
  });

  group('kaynak sözleşmesi', () {
    test('ekranlar portföy kapsamını tek sağlayıcıdan okur', () {
      for (final d in [
        'lib/screens/portfolio_screen.dart',
        'lib/screens/portfolio_performance_screen.dart',
      ]) {
        final k = ekranKaynagiSync(d);
        expect(k, contains('ref.watch(portfoyKapsamiProvider)'), reason: d);
        expect(k, contains('bilinenPortfoyler: portfoyKapsami.bilinen'),
            reason: d);
      }
    });

    test('ana sayfa, hareketler ve kıyas portföy süzgeci TAŞIMAZ (toplam)', () {
      for (final d in [
        'lib/screens/home_screen.dart',
        'lib/screens/all_transactions_screen.dart',
        'lib/providers/watchlist_provider.dart',
      ]) {
        expect(ekranKaynagiSync(d).contains('portfoyKapsami'), isFalse,
            reason: d);
      }
    });

    test('yazma yolları portföyü notifier kapısından alır', () {
      final k = ekranKaynagiSync('lib/providers/portfolio_provider.dart')
          .replaceAll(RegExp(r'\s+'), ' ');
      // Satış ve temettü pozisyonun portföyünü (karışığı reddeden yol).
      expect('portfoyId: _islemPortfoyu(asset)'.allMatches(k).length, 2);
      // Alım bayrak kapısından.
      expect(k, contains('portfoyId: _yazilacakPortfoy( portfoyId: portfoyId'));
      // Sözleşme lotları sözleşmenin portföyünü izler.
      expect(k, contains('sozlesmeId: a.sozlesmeId, s: currentState'));
    });

    test('Tümü\'de önbellek anahtarları bayrak öncesiyle aynı metin', () {
      final k =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(
          k,
          contains(
              "_portfoyAnahtari = portfoyKapsami.secim == PortfoySecimi.tumu\n        ? ''"));
    });
  });
}
