import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/screens/portfoy_yonetimi_screen.dart';
import 'package:portfoy_takip/services/hedef_ritmi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/portfoy_hedef_satiri.dart';
import 'package:portfoy_takip/widgets/portfoy_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çoklu portföyün Premium arkası (Ar-Ge 15 Kas 17:03 #1–#4).
///
/// Kilitlenenler:
/// 1. "+ Yeni"den paywall'a düşüp Premium alan kullanıcı ad sayfasına
///    devam eder, yeni portföy seçilir; almayan için akış biter.
/// 2. Portföy hedefi `portfoy_<id>` anahtarında; ritim yalnız o portföyün
///    defterinden, defter kısaysa yok. Premium bitince değer durur, gösterim
///    kapanır.
/// 3. Özet: maliyet/kâr/pay aynı kümeden; yönetim satırı Premium'da
///    "Tümünde %37 · +₺535 (+%41,8)", ücretsizde birebir eski.
/// 4. Paywall portföy kartı: gerçek varlık ve tür sayısı; veri yoksa eski.
const _uid = 'user-1';
const _a = 'pf-a';
const _b = 'pf-b';

Asset _lot(String id, String ticker, double adet, double fiyat,
        {String? portfoy,
        double guncel = 150,
        AssetType tur = AssetType.hisse,
        DateTime? tarih}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      purchaseFxRate: 1,
      notes: '',
      isManualPrice: true,
      currentPrice: guncel,
      addedDate: tarih ?? DateTime(2026, 3, 14),
      portfoyId: portfoy,
    );

// A: ASELS 10@100 (150) + SISE 7@40 (45) = 1.815, maliyet 1.280, kâr 535.
// B: ASELS 10@200 (150) = 1.500, maliyet 2.000, kâr −500.
// Ana: THYAO 5@300 (320) = 1.600, maliyet 1.500, kâr 100. Tümü 4.915.
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
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, ownerId: _uid);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _SabitPortfoyler extends PortfoylerNotifier {
  final olusturulan = <String>[];
  @override
  Future<List<Portfoy>> build() async => _liste;
  @override
  Future<Portfoy> olustur(String ad) async {
    olusturulan.add(ad);
    final p = Portfoy(id: 'yeni', userId: _uid, ad: ad, sira: 9);
    state = AsyncData([..._liste, p]);
    return p;
  }
}

List<Override> _ortak(_SabitPortfoyler portfoyler) => [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      portfoylerProvider.overrideWith(() => portfoyler),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
    ];

Future<ProviderContainer> _kur(WidgetTester t, Widget home,
    {required bool premium, _SabitPortfoyler? portfoyler}) async {
  t.view.physicalSize = const Size(390 * 3, 1400 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: _ortak(portfoyler ?? _SabitPortfoyler()),
    child: MaterialApp(theme: ThemeData.dark(), home: home),
  ));
  final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
  c.read(magazaPremiumProvider.notifier).state = premium;
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return c;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
    portfoyHedefSaati = () => DateTime(2026, 11, 15);
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
    RemoteConfigService.testKapali = {};
    portfoyHedefSaati = DateTime.now;
  });

  group('#1 + Yeni → paywall → Premium', () {
    Future<(ProviderContainer, _SabitPortfoyler, List<Portfoy?>)> ac(
        WidgetTester t) async {
      final pf = _SabitPortfoyler();
      final donen = <Portfoy?>[];
      final c = await _kur(
        t,
        Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    donen.add(await yeniPortfoyAkisi(ctx, ref)),
                child: const Text('yeni'),
              ),
            ),
          ),
        ),
        premium: false,
        portfoyler: pf,
      );
      expect(c.read(portfoySiniriDoluProvider), isTrue);
      await t.tap(find.text('yeni'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(PaywallScreen), findsOneWidget);
      return (c, pf, donen);
    }

    testWidgets('satın aldı: ad sayfası açılır, yeni portföy seçilir',
        (t) async {
      final (c, pf, donen) = await ac(t);
      c.read(magazaPremiumProvider.notifier).state = true;
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
      expect(find.byType(PortfoyAdiSayfasi), findsOneWidget,
          reason: '"+ Yeni"ye ikinci kez basmak gerekmez');
      await t.enterText(
          find.byKey(const ValueKey('portfoy-adi-alani')), 'Okul');
      await t.tap(find.byKey(const ValueKey('portfoy-adi-kaydet')));
      await t.pumpAndSettle();
      expect(pf.olusturulan, ['Okul']);
      expect(c.read(seciliPortfoyProvider), 'yeni');
      expect(donen.single?.id, 'yeni');
    });

    testWidgets('vazgeçti: ad sayfası yok, null döner', (t) async {
      final (_, pf, donen) = await ac(t);
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
      expect(find.byType(PortfoyAdiSayfasi), findsNothing);
      expect(pf.olusturulan, isEmpty);
      expect(donen, [null]);
    });
  });

  group('#2 portföy hedefi (saf)', () {
    final now = DateTime(2026, 11, 15);
    Asset alim(DateTime d, double tutar) =>
        _lot('b${d.millisecondsSinceEpoch}', 'TST', 1, tutar,
            guncel: tutar, tarih: d);

    test('hedef yok: null', () {
      expect(
          KapsamHedefDurumu.kur(
              hedef: 0, deger: 100, defter: const [], now: now),
          isNull);
    });

    test('defter kısa: oran var, ritim yok (uydurma sayı yok)', () {
      final d = KapsamHedefDurumu.kur(
        hedef: 10000,
        deger: 4200,
        defter: [alim(DateTime(2026, 10, 2), 4200)],
        now: now,
        tarih: DateTime(2027, 5, 15),
      )!;
      expect(d.yuzde, 42);
      expect(d.ritim, isNull);
      expect(d.ortalama, isNull);
    });

    test('defter uzun + gün: o defterin hızıyla plandasın', () {
      final defter = [
        alim(DateTime(2026, 5, 1), 3000),
        alim(DateTime(2026, 8, 10), 1000),
        alim(DateTime(2026, 9, 10), 1000),
        alim(DateTime(2026, 10, 10), 1000),
      ];
      final d = KapsamHedefDurumu.kur(
        hedef: 10000,
        deger: 6000,
        defter: defter,
        now: now,
        tarih: DateTime(2027, 5, 15),
      )!;
      expect(d.ortalama, closeTo(1000, 0.01));
      expect(d.ritim, isNotNull);
      expect(d.ritim!.plandasin, isTrue);
      final l = AppLocalizationsTr();
      expect(portfoyHedefMetni(l, d, gizli: false), contains('plandasın'));
      expect(portfoyHedefMetni(l, d, gizli: true), contains('••••'));
    });

    test('günsüz: ritim yok; ulaşıldı: "Ulaşıldı"', () {
      final defter = [alim(DateTime(2026, 1, 1), 100)];
      expect(
          KapsamHedefDurumu.kur(
                  hedef: 1000, deger: 500, defter: defter, now: now)!
              .ritim,
          isNull);
      final d = KapsamHedefDurumu.kur(
          hedef: 1000, deger: 1500, defter: defter, now: now)!;
      expect(d.ulasildi, isTrue);
      expect(portfoyHedefMetni(AppLocalizationsTr(), d, gizli: false),
          'Hedef · Ulaşıldı');
    });

    test('anahtar ekleyici: portfoy_<id>, Ana portfoy_ana', () {
      expect(portfoyHedefKapsami(_a), 'portfoy_$_a');
      expect(portfoyHedefKapsami(null), 'portfoy_ana');
    });
  });

  group('#2 portföy hedefi (ekran)', () {
    testWidgets('seçili portföyde ince satır; Premium bitince gizli, değer durur',
        (t) async {
      final c = await _kur(t, const Scaffold(body: PortfoyHedefSatiri()),
          premium: true);
      final kapsam = portfoyHedefKapsami(_a);
      await c.read(kapsamHedefiProvider(kapsam).notifier).set(3000);
      await t.pump();
      expect(find.byKey(const ValueKey('portfoy-hedef-satiri')), findsNothing,
          reason: 'Tümü seçiliyken satır yok');
      await c.read(seciliPortfoyProvider.notifier).set(_a);
      // Defter tembel yüklenir (yalnız bu satır izliyor): bir kare daha.
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('portfoy-hedef-satiri')), findsOneWidget);
      // 1.815 / 3.000 = %60; gün yok → ritim yok.
      expect(find.textContaining('Hedefe %60'), findsOneWidget);
      expect(find.textContaining('plandasın'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
          t.getSize(find.byKey(const ValueKey('portfoy-hedef-satiri'))).height,
          greaterThanOrEqualTo(44));

      c.read(magazaPremiumProvider.notifier).state = false;
      await t.pump();
      expect(find.byKey(const ValueKey('portfoy-hedef-satiri')), findsNothing);
      expect(c.read(kapsamHedefiProvider(kapsam)), 3000,
          reason: 'Premium bitince değer silinmez');
      expect(c.read(kapsamHedefiProvider('')), 0,
          reason: 'Ben hedefi dokunulmadan');
    });

    testWidgets('yönetim satırından hedef sayfası portföy kapsamıyla açılır',
        (t) async {
      final c = await _kur(t, const PortfoyYonetimiScreen(), premium: true);
      final satir = find.byKey(const ValueKey('portfoy-satir-$_b'));
      await t.tap(find.descendant(
          of: satir, matching: find.text('Hedef belirle')));
      await t.pumpAndSettle();
      expect(find.text('Çocuk'), findsWidgets,
          reason: 'sayfa kimin için olduğunu söyler');
      expect(c.read(kapsamHedefiProvider(portfoyHedefKapsami(_b))), 0);
    });
  });

  group('#3 özet ve yönetim satırı', () {
    test('maliyet/kâr/pay aynı kümeden; Σ pay = 1', () async {
      final c = ProviderContainer(overrides: _ortak(_SabitPortfoyler()));
      addTearDown(c.dispose);
      await c.read(portfolioProvider.future);
      await c.read(portfoylerProvider.future);
      final o = c.read(portfoyOzetleriProvider);
      expect(o[_a]!.maliyet, closeTo(1280, 0.01));
      expect(o[_a]!.kar, closeTo(535, 0.01));
      expect(o[_b]!.kar, closeTo(-500, 0.01));
      expect(o[null]!.maliyet, closeTo(1500, 0.01));
      final toplamPay = o.values.fold<double>(0, (s, e) => s + e.pay);
      expect(toplamPay, closeTo(1, 1e-9));
      expect(o[_a]!.pay, closeTo(1815 / 4915, 1e-9));
    });

    testWidgets('Premium: pay ve işaretli fark; hedef satırı', (t) async {
      await _kur(t, const PortfoyYonetimiScreen(), premium: true);
      expect(find.text('Tümünde %37 · +₺535 (+%41,8)'), findsOneWidget);
      expect(find.text('Tümünde %31 · −₺500 (−%25,0)'),
          findsOneWidget);
      expect(find.text('Tümünde %33 · +₺100 (+%6,7)'), findsOneWidget);
      expect(find.text('Hedef belirle'), findsNWidgets(3));
    });

    testWidgets('ücretsiz: satır birebir eski (pay, fark, hedef yok)',
        (t) async {
      await _kur(t, const PortfoyYonetimiScreen(), premium: false);
      expect(find.textContaining('Tümünde'), findsNothing);
      expect(find.text('Hedef belirle'), findsNothing);
      expect(find.text('Emeklilik'), findsOneWidget);
    });
  });

  group('#4 paywall portföy kartı', () {
    test('sayılar bugünkü mülkiyetten; boş defter null', () {
      final lotlar = aktifLotlar([
        ..._defter,
        _lot('5', 'USD', 100, 30, tur: AssetType.doviz, guncel: 34),
      ]);
      final s = portfoyTesvikSayilari(lotlar)!;
      expect(s.varlik, 4, reason: 'ASELS iki portföyde tek pozisyon');
      expect(s.tur, 2);
      expect(portfoyTesvikSayilari(const []), isNull);
      expect(AppLocalizationsTr().pwdPortfoyVeri(13, 4),
          '13 varlığın tek listede · 4 türde');
      expect(AppLocalizationsEn().pwdPortfoyVeri(1, 1),
          '1 asset in one list · 1 type');
    });

    testWidgets('portfoy_limit: kart kullanıcının sayısını söyler',
        (t) async {
      await _kur(t, const PaywallScreen(source: 'portfoy_limit'),
          premium: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('3 varlığın tek listede · 1 türde'),
          findsOneWidget);
    });

    testWidgets('başka kaynak: eski metin', (t) async {
      await _kur(t, const PaywallScreen(source: 'zirve'), premium: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('varlığın tek listede'), findsNothing);
    });
  });
}
