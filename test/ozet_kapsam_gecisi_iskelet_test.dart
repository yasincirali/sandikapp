import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

import 'helpers/kaynak.dart';

/// Özet, kapsam değişiminde BAŞKA bir defterin rakamlarını göstermemeli
/// (kullanıcı bildirimi 2026-09-22, üç turdur kapanmayan bulgu):
/// "performans özet günlük tabları seçildiğinde ortaklar arası
/// geçildiğinde ekran başka değerlerle doluyor sonrasında doğru gerçek
/// data ile doluyor."
///
/// ## Neden kaynak taraması YETMEDİ
/// Önceki iki tur bu davranışı `ekranKaynagiSync` ile, yani KODUN METNİNE
/// bakarak doğruladı: "iskelet kapısı yazılmış mı", "bayrak geçirilmiş mi".
/// İkisi de geçti — ama kapı çalışmadı. Metin doğruluğu davranış
/// doğruluğu değildir; bu test AĞACA bakar.
///
/// Emülatör Flutter'ı render edemediği için (bkz. CLAUDE.md yerel makine
/// notları) bu ekranın hataları defalarca "geçti" sanılıp gerçek cihazda
/// çıktı. `performans_kontrol_yigini_test` aynı dersin ürünü.
const _uid = 'user-1';

Asset _asset({
  required String id,
  required String userId,
  required String ticker,
  double price = 100,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 90,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: price,
      addedDate: DateTime(2026, 3, 14),
    );

AppUser _ortak() => AppUser(
      id: 'p-1',
      email: 'ortak@example.com',
      displayName: 'Test Ortak',
      createdAt: DateTime(2026, 1, 1),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Yasin Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [
          _asset(id: 'ben-1', userId: _uid, ticker: 'THYAO.IS', price: 120),
        ],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  _FakePartners(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => {
        'p-1': [
          _asset(id: 'ortak-1', userId: 'p-1', ticker: 'ASELS.IS', price: 140),
        ],
      };
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(
            () => _FakePartners([PartnerAccount(user: _ortak(), isActive: true)])),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      // `initialOzet` ile doğrudan Özet sekmesinde açılır — kullanıcının
      // bildirdiği yüzey burası.
      child: const MaterialApp(
        home: PortfolioPerformanceScreen(initialOzet: true),
      ),
    ),
  );
  await tester.pump();
  // Gün içi seri, fiyat turu + BİR KARE bekledikten sonra kurulur
  // (`TazelikRitmi.turuVeKareyiBekle`, 2026-09-24); o kare burada.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Özet gövdesi çizilmiş mi? "Nereden geldi" köprüsü yalnızca gerçek
/// özet çizildiğinde görünür.
bool _ozetGovdesiVar() => find.text('Nereden geldi').evaluate().isNotEmpty;

bool _iskeletVar() =>
    find.byType(SandikSkeleton).evaluate().isNotEmpty;

void main() {
  setUpAll(() async {
    // Gün içi motorunun saati SABİT (2026-09-24): duvar saatiyle 00:00'dan
    // hemen sonra gün içi pencerede çizilecek slot olmuyor ve "veri gelmiş
    // olmalı" ön koşulu yanlış kırmızı veriyordu (00:04'te ölçüldü).
    HistoryService.gunIciSaat = () => DateTime(2026, 9, 23, 16, 40);
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDownAll(() => HistoryService.gunIciSaat = DateTime.now);

  testWidgets('ilk karede sayı YOK — iskelet durur', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(_FakePortfolio.new),
          partnersProvider.overrideWith(() =>
              _FakePartners([PartnerAccount(user: _ortak(), isActive: true)])),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: const MaterialApp(
          home: PortfolioPerformanceScreen(initialOzet: true),
        ),
      ),
    );
    // TEK kare — seri henüz gelmedi.
    await tester.pump();

    expect(_ozetGovdesiVar(), isFalse,
        reason: 'seri gelmeden "Nereden geldi" köprüsü çizilirse '
            'kullanıcı ölçülmemiş rakam okur');
    expect(_iskeletVar(), isTrue,
        reason: 'kapı `!hasData || stale` iskelete düşmeli');
  });

  testWidgets('kapsam değişince ESKİ defterin rakamı anında kaybolur',
      (tester) async {
    await _pump(tester);
    expect(_ozetGovdesiVar(), isTrue, reason: 'ön koşul: veri gelmiş olmalı');

    final birlikte = find.text('Birlikte');
    expect(birlikte.evaluate(), isNotEmpty, reason: 'ön koşul: kapsam çipi var');
    await tester.tap(birlikte.first);
    // Geçişin İLK karesi — kullanıcının "başka değerlerle doluyor" dediği an.
    await tester.pump();

    // KÖK NEDENİN TESTİ: `FutureBuilder` future değişince `waiting`e geçer
    // ama `snapshot.data`'yı KORUR. `key: ValueKey(intradayKey)` olmadan
    // burada önceki kapsamın özeti duruyordu (emülatör logu 2026-09-22:
    // `waiting=true nokta=195` — 195 nokta eski kapsamın sonucuydu).
    expect(_ozetGovdesiVar(), isFalse,
        reason: 'ValueKey builder state\'ini sıfırlamalı; '
            'eski snapshot taşınmamalı');
    expect(_iskeletVar(), isTrue,
        reason: 'geçiş karesinde iskelet görünmeli');
    expect(tester.takeException(), isNull);
  });

  /// Tohum izolasyonunun KENDİSİ — geçiş karesini widget testinde
  /// yakalayamıyoruz (test ortamında ağ anında dönüyor, `pump()` ile aynı
  /// karede future tamamlanıyor), bu yüzden kural kaynakta doğrulanır.
  ///
  /// Kuralın ne olduğu: `_lastIntradayData` YALNIZCA damgası bu kümeyle
  /// eşleşiyorsa tohum olarak kullanılır. Eşleşmiyorsa `null` geçilir ve
  /// `hasData` false olur → Özet iskelete düşer.
  test('kaynak: tohum yalnızca AYNI kümeye aitse kullanılır', () {
    final src = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
        src.contains(
            'final tohum = _lastIntradayKey == intradayKey ? _lastIntradayData : null;'),
        isTrue,
        reason: 'başka kapsamın verisi tohum olarak kullanılmamalı');
    expect(src.contains('final data = snapshot.data ?? tohum;'), isTrue);
    // Nesne varlığına değil NOKTA SAYISINA bakılmalı: seed dolu ama
    // ölçülmemiş bir seri de "veri" sayılırdı.
    expect(src.contains('hasData: (data?.total.isNotEmpty ?? false)'), isTrue,
        reason: 'boş ama null olmayan breakdown "veri var" sayılmamalı');
  });
}
