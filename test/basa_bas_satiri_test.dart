import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/widgets/basa_bas_satiri.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:shared_preferences/shared_preferences.dart';

/// Ar-Ge 2026-11-11 #1 + #4: Portföy kart panelinde "Güncel tutar" tekrarı
/// kalktı; yerine zarardaki pozisyonda "Başa baş için %X yükselmeli"
/// (Premium). Kilitlenen: formül (temettü dahil, panelin kâr/zararıyla aynı
/// kaynak), satırın yalnız zararda çıkması, mevduatın eski düzeni, Premium
/// görünürlük/kilit deseni.
const _uid = 'user-1';

Asset _lot({
  required String id,
  required String ticker,
  required double adet,
  required double maliyet,
  required double fiyat,
  AssetType tur = AssetType.hisse,
  AssetKind kind = AssetKind.buy,
  double temettu = 0,
  String? sozlesmeId,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
      kind: kind,
      dividendAmount: temettu,
      sozlesmeId: sozlesmeId,
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

/// Portföy ekranını kurar ve ilk kartın panelini açar.
Future<void> _paneliAc(
  WidgetTester tester,
  List<Asset> varliklar, {
  bool gorunur = true,
  bool kilitli = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
      premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });

  group('basaBasIcinGerekenYukselis', () {
    test('%20 zarar → %25 yükseliş', () {
      expect(basaBasIcinGerekenYukselis(1000, 800), closeTo(25, 1e-9));
    });

    test('%50 zarar → %100 yükseliş (asimetri)', () {
      expect(basaBasIcinGerekenYukselis(1000, 500), closeTo(100, 1e-9));
    });

    test('kârda ve tam başa başta null', () {
      expect(basaBasIcinGerekenYukselis(1000, 1200), isNull);
      expect(basaBasIcinGerekenYukselis(1000, 1000), isNull);
    });

    test('temettü maliyetten düşer: panelin kâr/zararıyla aynı eşik', () {
      // Maliyet 1000, değer 900, temettü 100 → kâr/zarar 0: satır yok.
      expect(basaBasIcinGerekenYukselis(1000, 900, temettu: 100), isNull);
      // Temettü 50 → net maliyet 950: 950/900 − 1.
      expect(basaBasIcinGerekenYukselis(1000, 900, temettu: 50),
          closeTo((950 / 900 - 1) * 100, 1e-9));
    });

    test('geçersiz girdi null (uydurma yüzde yok)', () {
      expect(basaBasIcinGerekenYukselis(1000, 0), isNull);
      expect(basaBasIcinGerekenYukselis(1000, -5), isNull);
      expect(basaBasIcinGerekenYukselis(0, 800), isNull);
      expect(basaBasIcinGerekenYukselis(double.nan, 800), isNull);
      expect(basaBasIcinGerekenYukselis(1000, double.infinity), isNull);
    });
  });

  test('oran metni büyüklüğe göre hane', () {
    expect(BasaBasSatiri.oranMetni(25), '%25');
    expect(BasaBasSatiri.oranMetni(3.25), '%3,3');
    expect(BasaBasSatiri.oranMetni(0.4), '%0,40');
  });

  group('Portföy kart paneli', () {
    // 10 adet, maliyet 250, fiyat 200 → %20 zarar.
    final zararda = _lot(
        id: 'a', ticker: 'THYAO.IS', adet: 10, maliyet: 250, fiyat: 200);

    testWidgets('zararda: "Başa baş için" + "%25 yükselmeli", tek cümle okunur',
        (tester) async {
      await _paneliAc(tester, [zararda]);
      expect(find.text('Başa baş için'), findsOneWidget);
      expect(find.text('%25 yükselmeli'), findsOneWidget);
      expect(find.bySemanticsLabel('Başa baş için %25 yükselmeli'),
          findsOneWidget);
      // Tekrar eden "Güncel tutar" satırı kalktı.
      expect(find.text('Güncel tutar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kârda: satır yok, "Güncel tutar" da yok', (tester) async {
      await _paneliAc(tester, [
        _lot(id: 'b', ticker: 'THYAO.IS', adet: 10, maliyet: 250, fiyat: 300),
      ]);
      expect(find.text('Başa baş için'), findsNothing);
      expect(find.byType(BasaBasSatiri), findsNothing);
      expect(find.text('Güncel tutar'), findsNothing);
    });

    testWidgets('temettü zararı kapatıyorsa satır yok, temettü kalır',
        (tester) async {
      await _paneliAc(tester, [
        zararda,
        _lot(
            id: 'd',
            ticker: 'THYAO.IS',
            adet: 0,
            maliyet: 0,
            fiyat: 200,
            kind: AssetKind.dividend,
            temettu: 600),
      ]);
      expect(find.byType(BasaBasSatiri), findsNothing);
      expect(find.text('Tahsil edilen temettü'), findsOneWidget);
    });

    testWidgets('ücretsiz kullanıcı, paywall açık: kilit satırı', (tester) async {
      await _paneliAc(tester, [zararda], kilitli: true);
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.text("Bu pozisyonun başa baş için gereken yükselişi Premium'da"),
          findsOneWidget);
      expect(find.text('%25 yükselmeli'), findsNothing);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'basa_bas');
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('paywall kapalı (Premium görünmez): satır yok', (tester) async {
      await _paneliAc(tester, [zararda], gorunur: false);
      expect(find.byType(BasaBasSatiri), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
      expect(find.text('Güncel tutar'), findsNothing);
    });

    testWidgets('mevduat: "Güncel tutar" kalır, başa baş yok', (tester) async {
      await _paneliAc(tester, [
        _lot(
          id: 'm',
          ticker: 'MEVDUAT:abc',
          adet: 20000,
          maliyet: 1.0,
          fiyat: 0.9,
          tur: AssetType.mevduat,
          sozlesmeId: 'abc',
        ),
      ]);
      expect(find.text('Güncel tutar'), findsOneWidget);
      expect(find.byType(BasaBasSatiri), findsNothing);
    });
  });
}
