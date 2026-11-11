import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';

const _uid = 'user-1';
const _n = 20;

Asset _asset(int i, double fiyat) => Asset(
      id: 'A$i',
      userId: _uid,
      name: 'Varlık $i',
      ticker: 'HSS$i.IS',
      type: i.isEven ? AssetType.hisse : AssetType.fon,
      quantity: 10.0 + i,
      purchasePrice: 100,
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
      createdAt: DateTime(2026, 1, 1));
}

class _FakePortfolio extends PortfolioNotifier {
  final _fiyat = <int, double>{for (var i = 0; i < _n; i++) i: 120.0 + i};
  PortfolioState _durum() => PortfolioState(
      assets: [for (var i = 0; i < _n; i++) _asset(i, _fiyat[i]!)],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0);
  @override
  Future<PortfolioState> build() async => _durum();
  void fiyat(int i, double f) {
    _fiyat[i] = f;
    state = AsyncData(_durum());
  }
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // Fiyat turu (30 sn, `tazelik_ritmi`) tek varlığın fiyatını değiştirince
  // yalnız o satır yeniden kurulmalı. Ölçüm 2026-11-11 (390×844, 20
  // pozisyon, görünen + önbellek 10 kart): önce 10 `_AssetCard` / ~876
  // eleman, sonra 1 / ~356 (kalan: halka, toplam, liste sarmalayıcıları).
  testWidgets('tek fiyat değişince yalnız o satır yeniden kurulur',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
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
      child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final not = kap.read(portfolioProvider.notifier) as _FakePortfolio;

    Future<Map<String, int>> say(void Function() eylem) async {
      final sayac = <String, int>{};
      w.debugOnRebuildDirtyWidget = (e, _) {
        final ad = e.widget.runtimeType.toString();
        sayac[ad] = (sayac[ad] ?? 0) + 1;
      };
      try {
        eylem();
        await tester.pump();
      } finally {
        w.debugOnRebuildDirtyWidget = null;
      }
      await tester.pump(const Duration(seconds: 2)); // parlama biter
      return sayac;
    }

    // En değerli satır (19) en üstte, görünür.
    final tur1 = await say(() => not.fiyat(19, 200));
    expect(tur1['_AssetCard'], 1, reason: 'yalnız fiyatı değişen satır');
    // Eksik etiketi yalnız kendi dilimini izler: değişen satırın içindeki
    // tek etiket kurulur, öbür dokuzu değil.
    expect(tur1['_VeriEksigiEtiketi'] ?? 0, lessThanOrEqualTo(1));
    expect(find.textContaining('5.800'), findsWidgets,
        reason: '29 × 200 = 5.800 satırda görünür');

    // Değer değişmeden yeniden yayın (tur fiyatı aynı getirdi): sıfır kart.
    final tur2 = await say(() => not.fiyat(19, 200));
    expect(tur2['_AssetCard'], isNull);
    expect(tur2['_VeriEksigiEtiketi'], isNull);
  });

  test('değer imzası her değişken alanın değişimini yakalar', () {
    final degisimler = <String, void Function(Asset)>{
      'name': (a) => a.name = 'x',
      'ticker': (a) => a.ticker = 'X.IS',
      'type': (a) => a.type = AssetType.altin,
      'subCategory': (a) => a.subCategory = 'gr22',
      'unitType': (a) => a.unitType = 'gram',
      'quantity': (a) => a.quantity = 1,
      'purchasePrice': (a) => a.purchasePrice = 1,
      'currency': (a) => a.currency = 'USD',
      'currentPrice': (a) => a.currentPrice = 1,
      'lastUpdated': (a) => a.lastUpdated = DateTime(2026),
      'notes': (a) => a.notes = 'n',
      'isManualPrice': (a) => a.isManualPrice = true,
      'purchaseFxRate': (a) => a.purchaseFxRate = 2,
      'commission': (a) => a.commission = 3,
      'dividendAmount': (a) => a.dividendAmount = 4,
      'maliyetBilinmiyor': (a) => a.maliyetBilinmiyor = true,
    };
    for (final MapEntry(:key, :value) in degisimler.entries) {
      final a = _asset(1, 100);
      final once = a.degerImzasi;
      expect(_asset(1, 100).degerImzasi, once, reason: 'eşit değer eşit imza');
      value(a);
      expect(a.degerImzasi, isNot(once), reason: key);
    }
  });
}
