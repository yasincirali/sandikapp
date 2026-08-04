import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/charts_screen.dart';

/// Portföy ekranındaki varlık kartlarının taşma regresyonu.
///
/// `_AssetCard` charts_screen'e private ve sekiz iç içe yardımcıya bağlı
/// (`_AssetCardMetrics`, `_AssetLeadingIcon`, `_AssetDetailsPanel`,
/// `_GainLossLine`, `_ExpandChevron`, `_DetailItem`, `_rowAction`,
/// `_DepositDetailsPanel`). Ayrı widget'a çıkarmak "dev ekranları parçala"
/// borcunun parçası ve TECHNICAL_DEBT.md'de bilinçli olarak ertelendi.
///
/// Bu test o refactor'ı BEKLEMEDEN kapsama alır: `ChartsScreen`'i gerçek
/// haliyle pump eder, provider'ları override ederek veri besler. Kart
/// yerleşimi bozulursa (kolon dağıtımı, kaydırma aksiyonları, genişleyen
/// panel) taşma exception'ı olarak yakalanır.
///
/// Ekran parçalanınca bu test yine geçmeli — dış davranışı doğruluyor,
/// iç yapıyı değil.

const _uid = 'user-1';

Asset _asset({
  required String name,
  required String ticker,
  required AssetType type,
  double qty = 100,
  double buy = 250.75,
  double current = 312.40,
  String currency = 'TRY',
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: '$ticker-${kind.name}-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: current,
      addedDate: DateTime(2026, 3, 14),
      kind: kind,
    );

/// Fiyatı çekilememiş varlık — kâr/zarar satırı gizlenir, farklı yerleşim.
Asset _unpriced() => _asset(
      name: 'Fiyatsız Varlık',
      ticker: 'XXX',
      type: AssetType.diger,
      current: 0,
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

/// Ortak listesi boş — asıl konumuz kart yerleşimi. Override edilmezse
/// gerçek notifier 30 sn'lik polling'i kurar ve Supabase init olmadığı için
/// test çıktısını hata logu ile doldurur (hatalar yutulur, test yine geçer;
/// yalnızca gürültü olur).
class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pumpScreen(
  WidgetTester tester,
  List<Asset> assets, {
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
        partnersProvider.overrideWith(_FakePartners.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const ChartsScreen(),
      ),
    ),
  );
  // Async provider'ların çözülmesi + ilk layout.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  group('varlık kartı — taşma', () {
    final portfolio = [
      _asset(
          name: 'Türk Hava Yolları',
          ticker: 'THYAO.IS',
          type: AssetType.hisse),
      _asset(
        name: 'Yapı Kredi Portföy Teknoloji Değişken Fon',
        ticker: 'TEFAS:YKT',
        type: AssetType.fon,
        qty: 486.948,
        buy: 0.814,
        current: 0.9123,
      ),
      _asset(
          name: 'Gram Altın',
          ticker: '',
          type: AssetType.altin,
          qty: 12.5,
          buy: 4200,
          current: 4890),
      _asset(
          name: 'Amerikan Doları',
          ticker: 'USDTRY=X',
          type: AssetType.doviz,
          qty: 1500,
          buy: 38.2,
          current: 42.0,
          currency: 'USD'),
    ];

    for (final w in <double>[320, 360, 375, 390, 430]) {
      testWidgets('${w.toInt()}pt ekranda kart listesi', (tester) async {
        await _pumpScreen(tester, portfolio, width: w);
        expect(tester.takeException(), isNull,
            reason: '${w.toInt()}pt ekranda varlık kartı taşıyor');
      });
    }

    testWidgets('fiyatı çekilememiş varlık', (tester) async {
      await _pumpScreen(tester, [_unpriced()], width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok büyük tutar kolonu taşırmaz', (tester) async {
      // Milyarlık portföy: tutar kolonu FittedBox ile küçülmeli, taşmamalı.
      await _pumpScreen(
        tester,
        [
          _asset(
              name: 'Büyük Pozisyon',
              ticker: 'BIG.IS',
              type: AssetType.hisse,
              qty: 1000000,
              buy: 1250.50,
              current: 9876.54),
        ],
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('boş portföy', (tester) async {
      await _pumpScreen(tester, const [], width: 375);
      expect(tester.takeException(), isNull);
    });
  });
}
