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
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';

/// **Metin ölçeği** (Dynamic Type) altında taşma regresyonu.
///
/// Mevcut taşma testleri yalnızca 320–430pt **genişlik** tarıyordu ve
/// metin ölçeğini 1.0× sabit bırakıyordu. Bu yüzden iki gerçek hata
/// gözden kaçtı — 1.0×'te ikisi de temizdi:
///
/// | Ekran | 1.0× | 1.5× | 2.0× | 3.0× |
/// |---|---|---|---|---|
/// | PortfolioPerformance @375pt | temiz | 61px | 179px | 415px |
/// | Charts @320pt | temiz | temiz | 45px | 199px |
///
/// Kök sebepler:
/// - `portfolio_performance_screen`: "TEKNİK SİNYALLER" başlığı + sayaç
///   rozeti kısıtsız `Row`'daydı; başlık büyüyünce rozeti dışarı itiyordu.
/// - `charts_screen`: lejant çipi (`Wrap` içinde) ekran genişliğini
///   aşabiliyordu. `Wrap` çipi alt satıra indirir ama TEK çip satıra
///   sığmıyorsa çaresizdir.
///
/// iOS'ta 1.5× olağandışı değil — gözü yorulan herkesin açtığı kademedir.
/// Bu yüzden ölçek ekseni kalıcı olarak teste bağlandı.

const _uid = 'user-1';

Asset _asset({
  required String name,
  required String ticker,
  required AssetType type,
  double qty = 100,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 250.75,
      currency: currency,
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
      kind: AssetKind.buy,
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

/// Uzun etiketler bilinçli: kısa adlarla taşma gizlenir.
final _portfolio = [
  _asset(
      name: 'Türkiye Sınai Kalkınma Bankası',
      ticker: 'TSKB',
      type: AssetType.hisse),
  _asset(
      name: 'Yapı Kredi Koray Gayrimenkul Yatırım Ortaklığı',
      ticker: 'YKGYO',
      type: AssetType.hisse,
      qty: 12345.678),
  _asset(name: 'Gram Altın', ticker: 'GLD', type: AssetType.altin, qty: 250.5),
  _asset(
      name: 'Amerikan Doları',
      ticker: 'USD',
      type: AssetType.doviz,
      currency: 'USD',
      qty: 9999.99),
];

Future<String?> _pumpAndCatch(
  WidgetTester tester,
  Widget screen, {
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(_portfolio)),
        partnersProvider.overrideWith(_FakePartners.new),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  final ex = tester.takeException();
  if (ex == null) return null;
  return ex.toString().split('\n').first;
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  // 3.0× iOS'un en büyük erişilebilirlik kademesine (AX5) yakındır.
  const scales = [1.0, 1.5, 2.0, 3.0];
  const widths = [320.0, 375.0, 430.0];

  group('PortfolioPerformanceScreen — metin ölçeği', () {
    for (final w in widths) {
      for (final s in scales) {
        testWidgets('${w.toInt()}pt x$s taşmamalı', (t) async {
          final err = await _pumpAndCatch(
            t,
            const PortfolioPerformanceScreen(),
            width: w,
            scale: s,
          );
          expect(err, isNull,
              reason: '${w.toInt()}pt / metin ölçeği $s: $err\n'
                  'Başlık + rozet satırlarında başlık `Flexible` olmalı.');
        });
      }
    }
  });

  group('ChartsScreen — metin ölçeği', () {
    for (final w in widths) {
      for (final s in scales) {
        testWidgets('${w.toInt()}pt x$s taşmamalı', (t) async {
          final err = await _pumpAndCatch(
            t,
            const ChartsScreen(),
            width: w,
            scale: s,
          );
          expect(err, isNull,
              reason: '${w.toInt()}pt / metin ölçeği $s: $err\n'
                  'Lejant çipi ekran genişliğini aşmamalı.');
        });
      }
    }
  });
}
