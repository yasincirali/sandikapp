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
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/portfoy_secim_sayfasi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Portföyler arası kısmi aktarım (Premium, 0136). Bölmenin kendisi
/// sunucuda (`pozisyon_kismi_aktar`, yerel Postgres'te denendi); burada
/// akış: miktar adımı, "Tamamı" eski taşıma, "Bir kısmı" oranı, Premium
/// kilidi, sözleşmeli pozisyonda adımın atlanması.
const _uid = 'user-1';
const _a = 'pf-a';
const _b = 'pf-b';

Asset _lot(String id, String ticker, double adet,
        {String? portfoy, String? sozlesme}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: 40,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 45,
      addedDate: DateTime(2026, 3, 14),
      portfoyId: portfoy,
      sozlesmeId: sozlesme,
    );

final _sise = _lot('4', 'SISE', 7, portfoy: _a);
final _bes = _lot('5', 'BESX', 3, portfoy: _a, sozlesme: 'soz-1');

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

class _KayitliPortfolio extends PortfolioNotifier {
  final tamami = <(List<String>, String?)>[];
  final kismi = <(List<String>, double, String?)>[];
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: [_sise, _bes], ownerId: _uid);
  @override
  Future<void> pozisyonuTasi(List<Asset> lotlar, String? hedef) async =>
      tamami.add(([for (final a in lotlar) a.id], hedef));
  @override
  Future<void> pozisyonuKismiTasi(
          List<Asset> lotlar, double oran, String? hedef) async =>
      kismi.add(([for (final a in lotlar) a.id], oran, hedef));
}

class _SabitPortfoyler extends PortfoylerNotifier {
  @override
  Future<List<Portfoy>> build() async => _liste;
}

Future<_KayitliPortfolio> _ac(WidgetTester t, Asset varlik,
    {bool premium = true}) async {
  t.view.physicalSize = const Size(390 * 3, 900 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  final defter = _KayitliPortfolio();
  await t.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => defter),
      portfoylerProvider.overrideWith(_SabitPortfoyler.new),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      magazaPremiumProvider.overrideWith((_) => premium),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Consumer(
          builder: (ctx, ref, _) => TextButton(
            onPressed: () => pozisyonuTasiAkisi(ctx, ref, varlik),
            child: const Text('taşı'),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  final kap = ProviderScope.containerOf(t.element(find.text('taşı')));
  await kap.read(portfolioProvider.future);
  await kap.read(portfoylerProvider.future);
  await t.tap(find.text('taşı'));
  await t.pumpAndSettle();
  // Hedef: Çocuk.
  await t.tap(find.byKey(const ValueKey('portfoy-secenek-$_b')));
  await t.pumpAndSettle();
  return defter;
}

Future<void> _aktar(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('kismi-aktarim-dugme')));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('varsayılan Tamamı: bugünkü bütün taşıma', (t) async {
    final d = await _ac(t, _sise);
    expect(find.text('Ne kadarı aktarılsın?'), findsOneWidget);
    expect(find.byKey(const ValueKey('kismi-aktarim-miktar')), findsNothing);
    await _aktar(t);
    expect(d.tamami.single.$1, ['4']);
    expect(d.tamami.single.$2, _b);
    expect(d.kismi, isEmpty);
  });

  testWidgets('Bir kısmı: 3 / 7 oranıyla bölünür', (t) async {
    final d = await _ac(t, _sise);
    await t.tap(find.text('Bir kısmı'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('kismi-aktarim-miktar')), '3');
    await _aktar(t);
    expect(d.tamami, isEmpty);
    final (ids, oran, hedef) = d.kismi.single;
    expect(ids, ['4']);
    expect(oran, closeTo(3 / 7, 1e-12));
    expect(hedef, _b);
    expect(find.text('Ne kadarı aktarılsın?'), findsNothing,
        reason: 'başarıda sayfa kapanır');
  });

  testWidgets('elindekinden fazla: hata, istek yok', (t) async {
    final d = await _ac(t, _sise);
    await t.tap(find.text('Bir kısmı'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('kismi-aktarim-miktar')), '9');
    await _aktar(t);
    expect(find.textContaining('arasında bir miktar yaz'), findsOneWidget);
    expect(d.kismi, isEmpty);
    expect(d.tamami, isEmpty);
  });

  testWidgets('hepsini yazmak bölme değil taşıma', (t) async {
    final d = await _ac(t, _sise);
    await t.tap(find.text('Bir kısmı'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('kismi-aktarim-miktar')), '7');
    await _aktar(t);
    expect(d.tamami.single.$1, ['4']);
    expect(d.tamami.single.$2, _b);
    expect(d.kismi, isEmpty);
  });

  testWidgets('Premium yokken Bir kısmı kilitli, Tamamı çalışır', (t) async {
    final d = await _ac(t, _sise, premium: false);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text("Bir kısmını aktarmak Premium'a özel."), findsOneWidget);
    await _aktar(t);
    expect(d.tamami.single.$1, ['4']);
    expect(d.tamami.single.$2, _b);
  });

  testWidgets('sözleşmeli (BES/mevduat): miktar sorulmaz, tamamı taşınır',
      (t) async {
    final d = await _ac(t, _bes);
    expect(find.text('Ne kadarı aktarılsın?'), findsNothing);
    expect(d.tamami.single.$2, _b);
    expect(d.kismi, isEmpty);
  });
}
