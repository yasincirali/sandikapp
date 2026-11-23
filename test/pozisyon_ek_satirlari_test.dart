import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/basa_bas_satiri.dart';
import 'package:portfoy_takip/widgets/kur_ayrismasi_satiri.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;

/// Pozisyon kartının ek satırları (Ar-Ge 2026-11-15 #1, #2).
///
/// Bekçi: "Fiyattan · Kurdan" ve başa baş satırı varlık detayında bayrak
/// (`varlik_detay_katmanli`) hangi düzeni seçerse seçsin görünür —
/// eskiden yalnız katmanlı kartta kuruluyordu ve bayrak varsayılanı kapalı.
/// Ücretsizde kilit satırı (başa başın kaynağı `varlik_basa_bas`), kârdaki
/// pozisyonda başa baş satırı da kilidi de yok.

const _uid = 'user-1';
const _bayrak = 'varlik_detay_katmanli';

/// ABD hissesi, USD. 10 × $200 @ ₺30 = ₺60.000 maliyet.
/// [fiyat] 120 → bugün 10 × 120 × 42 = ₺50.400 (zarar, başa baş %19);
/// [fiyat] 250 → ₺105.000 (kâr).
Asset _asset(double fiyat) => Asset(
      id: 'AAPL-1',
      userId: _uid,
      name: 'Apple',
      ticker: 'AAPL',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 200,
      currency: 'USD',
      notes: '',
      purchaseFxRate: 30,
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.fiyat);
  final double fiyat;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset(fiyat)],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

Future<void> _ac(WidgetTester tester,
    {required bool katmanli, required bool kilitli, double fiyat = 120}) async {
  RemoteConfigService.testAcik = katmanli ? {_bayrak} : {};
  tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(fiyat)),
      premiumOzellikleriGorunurProvider.overrideWithValue(true),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AssetDetailScreen(asset: _asset(fiyat), showBackButton: true),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({PrefKeys.yatayGrafikIpucu: true});
    await initPreferencesCache();
  });

  tearDown(() => RemoteConfigService.testAcik = {});

  for (final katmanli in [false, true]) {
    final duzen = katmanli ? 'katmanlı' : 'eski';

    testWidgets('$duzen düzen, Premium: Fiyattan · Kurdan ve başa baş',
        (tester) async {
      await _ac(tester, katmanli: katmanli, kilitli: false);
      expect(find.byType(PozisyonEkSatirlari), findsOneWidget);
      expect(find.byType(KurAyrismasiSatiri), findsOneWidget);
      expect(
          find.textContaining('Fiyattan', findRichText: true), findsOneWidget);
      expect(find.byType(BasaBasSatiri), findsOneWidget);
      // 60.000 / 50.400 − 1 = %19,05 → "%19".
      expect(find.text('%19 yükselmeli'), findsOneWidget);
      expect(find.bySemanticsLabel('Başa baş için %19 yükselmeli'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    // 2026-11-23 #3: kur ve başa baş ikisi birden kilitliyken iki amber
    // satır yerine tek birleşik kilit (aynı paywall kartı, kaynak
    // `varlik_basa_bas`).
    testWidgets('$duzen düzen, ücretsiz: tek birleşik kilit, sayı yok',
        (tester) async {
      await _ac(tester, katmanli: katmanli, kilitli: true);
      final kilitler = find.descendant(
          of: find.byType(PozisyonEkSatirlari),
          matching: find.byType(KilitSatiri));
      expect(kilitler, findsOneWidget);
      expect(tester.widget<KilitSatiri>(kilitler).kaynak, 'varlik_basa_bas');
      expect(
          find.text("Kurun payı ve başa baş için gereken yükseliş Premium'da"),
          findsOneWidget);
      expect(find.text('%19 yükselmeli'), findsNothing);
      expect(find.textContaining('Fiyattan', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('$duzen düzen, kârda: başa baş da kilidi de yok',
        (tester) async {
      await _ac(tester, katmanli: katmanli, kilitli: true, fiyat: 250);
      expect(find.byType(BasaBasSatiri), findsNothing);
      final kilitler = tester.widgetList<KilitSatiri>(find.descendant(
          of: find.byType(PozisyonEkSatirlari),
          matching: find.byType(KilitSatiri)));
      expect(kilitler.map((k) => k.kaynak), isNot(contains('varlik_basa_bas')));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
