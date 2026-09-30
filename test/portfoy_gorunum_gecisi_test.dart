import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/widgets/gorunum_cipi.dart';

/// Regresyon (kullanıcı bildirimi, 2026-10-01): Portföy'de "Birlikte"den
/// ortağa geçince kırmızı ekran —
/// `sliver_multi_box_adaptor.dart: 'child == null || indexOf(child) >
/// index': is not true`.
///
/// Kök neden (bu testle doğrulandı): kartlar dış `ListView`'in doğrudan
/// çocukları ve `ValueKey(pozisyon anahtarı)` taşıyor. Birlikte listesi iki
/// sahibin KCHOL'ünü İKİ kart olarak basıyordu → aynı anahtar iki kez.
/// Görünüm değişince sliver öğesi iki eski kartı aynı yeni indekse eşliyor,
/// biri öksüz kalıp render listesinde eski yerinde duruyor ve çocuk sırası
/// bozuluyor. `sahiplerArasiBirlestir` (Birlikte'de aynı varlık tek satır)
/// anahtarları tekil kıldı; birleştirme geri alınınca bu test üç
/// senaryoda da aynı iddiayla kırılıyor. Senaryo kullanıcınınki: iki
/// sahipte ORTAK varlıklar (KCHOL, çeyrek), liste ekrandan uzun.

const _uid = 'user-1';
const _pid = 'partner-1';

Asset _lot(String owner, String ticker, double qty, double fiyat,
        {AssetType type = AssetType.hisse, String? sub}) =>
    Asset(
      id: '$owner-$ticker-$qty',
      userId: owner,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: fiyat * 0.9,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      subCategory: sub,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
    );

final _benim = [
  _lot(_uid, 'KCHOL.IS', 1001, 208.4),
  _lot(_uid, 'ALTIN_CEYREK', 15, 10544,
      type: AssetType.altin, sub: 'Çeyrek Altın'),
  _lot(_uid, 'KRIPTO:ONDO', 10000, 24.55, type: AssetType.kripto),
  _lot(_uid, 'USDTRY=X', 2200, 49.01, type: AssetType.doviz, sub: 'USD'),
  _lot(_uid, 'THYAO.IS', 300, 310),
  _lot(_uid, 'GARAN.IS', 500, 120),
];
final _ortagin = [
  _lot(_pid, 'ALTIN_GRAM', 100, 6010,
      type: AssetType.altin, sub: '22 Ayar Gram Altın'),
  _lot(_pid, 'ALTIN_CUMHURIYET', 6, 43795,
      type: AssetType.altin, sub: 'Cumhuriyet Altını'),
  _lot(_pid, 'KCHOL.IS', 620, 208.4),
  _lot(_pid, 'ALTIN_CEYREK', 10, 10544,
      type: AssetType.altin, sub: 'Çeyrek Altın'),
  _lot(_pid, 'ASELS.IS', 200, 150),
  _lot(_pid, 'SISE.IS', 400, 45),
];

final _ortak = AppUser(
  id: _pid,
  email: 'p@x',
  displayName: 'Mehmet Yılmaz',
  createdAt: DateTime(2026, 1, 1),
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 't@x',
        displayName: 'Ben',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _benim, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => {_pid: _ortagin};
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    GorunumCipi.hafizayiSifirla();
  });

  Future<void> pumpEkran(WidgetTester tester) async {
    // Telefon boyu: liste ekrandan uzun, kartlar tembel kurulur.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(_FakePartners.new),
        activePartnersProvider.overrideWith((ref) => [_ortak]),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> sec(WidgetTester tester, String etiket) async {
    await tester.tap(find.text(etiket).first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  for (final kaydirma in [0.0, 300.0, 700.0]) {
    testWidgets('Birlikte → ortak geçişi çökmez (kaydırma $kaydirma)',
        (tester) async {
      await pumpEkran(tester);
      await sec(tester, 'Birlikte');
      if (kaydirma > 0) {
        await tester.drag(find.byType(ListView).first, Offset(0, -kaydirma));
        await tester.pumpAndSettle();
      }
      // Seçici kaydırılıp gözden çıktıysa geri gel (kullanıcı da öyle yapar).
      if (find.text('Mehmet').evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
      }
      await sec(tester, 'Mehmet');
      expect(tester.takeException(), isNull);
      await sec(tester, 'Birlikte');
      await sec(tester, 'Ben');
      await sec(tester, 'Mehmet');
      expect(tester.takeException(), isNull);
    });
  }
}
