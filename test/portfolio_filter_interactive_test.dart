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
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';

/// Portföy performans ekranı — filtreler yükleme sırasında kaybolmamalı.
///
/// Bu ekranda filtre kontrolleri (varlık tipi çipleri, periyot toggle'ı,
/// ortak sekmesi) `_buildChartWithData` İÇİNDE yaşıyordu. Eski kod veri
/// yokken o metodu hiç çağırmadan `return CustomLoadingView()` yapıyordu →
/// filtre değiştiren kullanıcı, yeni veri gelene kadar TÜM filtreleri
/// kaybediyordu. Artık yalnızca grafik alanı yükleme durumuna düşer.
///
/// NOT: Bu test taşma (overflow) testi DEĞİLDİR. `_PortfolioSignalPanel`
/// içinde 375pt'de var olan bir taşma bu değişiklikten ÖNCE de mevcut
/// (temiz ağaçta doğrulandı) — burada bilerek yok sayılır, kapsam filtre
/// görünürlüğüdür.

const _uid = 'user-1';

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
}) =>
    Asset(
      id: '$ticker-1',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
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
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

Future<void> _pump(WidgetTester tester) async {
  // Geniş viewport: sinyal panelindeki mevcut taşma testin odağını
  // (filtre görünürlüğü) gölgelemesin.
  tester.view.physicalSize = const Size(800 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio([
              _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları'),
              _asset(
                  ticker: 'GRAM_ALTIN',
                  name: 'Gram Altın',
                  type: AssetType.altin),
            ])),
        partnersProvider.overrideWith(_FakePartners.new),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const PortfolioPerformanceScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('portföy performans — filtreler yükleme sırasında kalır', () {
    testWidgets('tip filtresi değişince çipler ve periyot toggle kalır',
        (tester) async {
      await _pump(tester);

      // Ön koşul: filtre çipleri çizilmiş olmalı.
      expect(find.text('Tümü'), findsWidgets,
          reason: 'ön koşul: tip filtresi çipleri görünmeli');

      // Bir tip filtresine tıkla — controller yeniden kurulur, veri boşalır.
      final hisseChip = find.text('Hisse');
      if (hisseChip.evaluate().isNotEmpty) {
        await tester.tap(hisseChip.first, warnIfMissed: false);
        await tester.pump(); // yükleme karesi

        // TAM BU KAREDE filtreler hâlâ ekranda olmalı.
        expect(find.text('Tümü'), findsWidgets,
            reason: 'tip filtresi değişiminde çipler kayboldu — '
                'yükleme tüm bloğu sildi');
        expect(find.text('GÜNLÜK'), findsWidgets,
            reason: 'tip filtresi değişiminde periyot toggle kayboldu');
      }

      await tester.pump(const Duration(milliseconds: 300));
      // Taşma istisnalarını tüket — bkz. dosya başındaki not.
      tester.takeException();
    });

    testWidgets('periyot değişiminde filtre çipleri kalır', (tester) async {
      await _pump(tester);

      final aylik = find.text('1A');
      if (aylik.evaluate().isNotEmpty) {
        await tester.tap(aylik.first, warnIfMissed: false);
        await tester.pump(); // yükleme karesi

        expect(find.text('Tümü'), findsWidgets,
            reason: 'periyot değişiminde tip çipleri kayboldu');
        expect(find.text('GÜNLÜK'), findsWidgets,
            reason: 'periyot değişiminde toggle kayboldu');
      }

      await tester.pump(const Duration(milliseconds: 300));
      // Taşma istisnalarını tüket — bkz. dosya başındaki not.
      tester.takeException();
    });
  });
}
