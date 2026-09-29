import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/base_currency_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// "Bakiyeyi gizle" HER yerde (bulgu #3, 2026-09-29 emülatör testi).
///
/// Gözlenen: Ana'daki göz yalnız Ana'yı gizliyordu; Portföy toplamı
/// ₺1.388.344, kart tutarları, Performans birikimi ve ekseni açıktaydı.
/// Kök neden: `balanceHiddenProvider` bu ekranlarda hiç okunmuyordu —
/// gizleme her çağrı yerinde elle yapılıyordu. Düzeltme maskeyi
/// biçimleyiciye taşıdı (`BazPara.gizli`, `gosterimBazParaProvider`).
///
/// Ölçülen: gizliyken ekranda "₺ + rakam" KALMAZ; yüzdeler kalır (Ana'daki
/// Bugün kartıyla aynı kural); açıkken tutarlar yine yazılır.
const _uid = 'user-1';

/// Ekranda görünen tüm metin. `Text` de `RichText`'e iner; tek tarama.
List<String> _metinler(WidgetTester tester) => [
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
    ];

/// Para sembolünün hemen ardından rakam: maskesiz tutar.
final _acikTutar = RegExp(r'[₺$€]\s?[0-9]');

Asset _lot({
  required String id,
  required String ticker,
  required double adet,
  required double maliyet,
  required double fiyat,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      // Panel sparkline'ı ağa çıkmasın.
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 3, 14),
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

final _varliklar = [
  // Kârda: 10 × 250 → 10 × 300 = ₺3.000, +₺500.
  _lot(id: 'a1', ticker: 'THYAO.IS', adet: 10, maliyet: 250, fiyat: 300),
  // Zararda: 1 × 224,5 → 219,5 = −₺5, −%2,23 (bulgudaki ATATP).
  _lot(id: 'b1', ticker: 'ATATP.IS', adet: 1, maliyet: 224.5, fiyat: 219.5),
];

Future<ProviderContainer> _pumpPortfoy(WidgetTester tester,
    {required bool gizli}) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(_varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final container =
      ProviderScope.containerOf(tester.element(find.byType(PortfolioScreen)));
  // Tercih Ana'daki göz gibi ÇALIŞIRKEN değişir: ekran tepki vermeli
  // (yalnız açılışta okumak yetmez).
  await container.read(balanceHiddenProvider.notifier).set(gizli);
  await tester.pump();
  // Her iki kartın paneli de açılsın (toplam maliyet, güncel tutar).
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).at(i));
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
  });

  group('BazPara.gizli — biçimleyici maskesi', () {
    test('her baz birimde fmt / formatter / compact / axis maskeli', () {
      for (final baz in const [
        BazPara(BaseCurrency.try_, 1),
        BazPara(BaseCurrency.usd, 40),
        BazPara(BaseCurrency.eur, 45),
        BazPara(BaseCurrency.gold, 4000),
      ]) {
        final g = baz.gizlenmis();
        expect(g.gizli, isTrue);
        expect(g.birim, baz.birim, reason: 'maske birimi değiştirmez');
        expect(g.kur, baz.kur);
        for (final s in [
          g.fmt(1234567),
          g.fmt(-98765, digits: 2),
          g.formatter(digits: 2).format(42),
          g.compact(1388344),
          g.axis(1388344, 5000),
        ]) {
          expect(s, g.gizliTutar, reason: '${baz.birim}: "$s" maskesiz');
          expect(RegExp(r'[0-9]').hasMatch(s), isFalse);
        }
        // Grafik geometrisi gerçek sayıyla çizilir — yalnız etiket gizli.
        expect(g.cevir(4000), baz.cevir(4000));
      }
    });

    test('gizli değilken eski biçim birebir', () {
      const baz = BazPara(BaseCurrency.try_, 1);
      expect(baz.gizli, isFalse);
      expect(baz.fmt(1388344), '₺1.388.344');
      expect(const BazPara.lira().gizli, isFalse);
    });

    test('gosterimBazParaProvider tercihi izler, ham baz etkilenmez',
        () async {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio(const [])),
      ]);
      addTearDown(c.dispose);
      expect(c.read(gosterimBazParaProvider).gizli, isFalse);
      await c.read(balanceHiddenProvider.notifier).set(true);
      expect(c.read(gosterimBazParaProvider).gizli, isTrue);
      expect(c.read(bazParaProvider).gizli, isFalse,
          reason: 'kote fiyat yüzeyleri ham bazı okur; fiyat bakiye değil');
      await c.read(balanceHiddenProvider.notifier).set(false);
    });
  });

  group('Portföy sekmesi', () {
    testWidgets('gizliyken ₺ rakamı kalmaz (halka, kart, panel)',
        (tester) async {
      await _pumpPortfoy(tester, gizli: true);
      final sizan = _metinler(tester).where(_acikTutar.hasMatch).toList();
      expect(sizan, isEmpty, reason: 'gizliyken açık tutar: $sizan');
      // Alış para birimli toplam maliyet `baz`dan geçmiyor — elle maskeli.
      expect(find.textContaining('2.500'), findsNothing);
      expect(find.textContaining('3.000'), findsNothing);
      // Maske gerçekten çizildi (boş ekran "sızıntı yok" sayılmasın).
      expect(find.textContaining('₺••••'), findsWidgets);
      // Yüzdeler görünür kalır.
      expect(find.textContaining('%20,00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('açıkken tutarlar yazılır (maske kaçağı yok)', (tester) async {
      await _pumpPortfoy(tester, gizli: false);
      expect(find.textContaining('₺••••'), findsNothing);
      expect(find.text('₺3.000'), findsWidgets);
      expect(find.textContaining('2.500,00 TRY'), findsOneWidget);
    });
  });

  group('Performans › Özet', () {
    testWidgets('maskeli bazla özet kartında ₺ rakamı kalmaz', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final ozet = PeriodSummary(
        period: SummaryPeriod.birAy,
        start: DateTime(2026, 8, 14),
        end: DateTime(2026, 9, 13),
        baslangicTRY: 168774,
        sonTRY: 185684,
        katkiTRY: 12000,
        piyasaTRY: 4910,
        getiriPct: 2.72,
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light,
            extensions: const [SandikPalette.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeriodSummaryView(
              summary: ozet,
              baz: const BazPara(BaseCurrency.try_, 1).gizlenmis(),
            ),
          ),
        ),
      ));
      await tester.pump();
      final sizan = _metinler(tester).where(_acikTutar.hasMatch).toList();
      expect(sizan, isEmpty, reason: 'gizliyken açık tutar: $sizan');
      expect(find.textContaining('₺••••'), findsWidgets);
    });
  });

  // Ekran testleri seri servisine (ağ) bağlı Performans grafiğini ve varlık
  // ekranını kuramıyor; oralarda sözleşme kaynaktan kilitlenir: tutar yazan
  // yüzey HAM `bazParaProvider`'ı değil maskeli olanı okur. Yeni bir kart
  // ham sağlayıcıyla eklenirse gizleme orada sessizce kırılırdı.
  test('Performans + Portföy + varlık ekranı maskeli bazı okur', () {
    final ham = RegExp(r'ref\.(watch|read)\(bazParaProvider\)');
    for (final yol in const [
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/portfolio_screen.dart',
      'lib/screens/asset_detail_screen.dart',
    ]) {
      final src = ekranKaynagiSync(yol);
      expect(ham.hasMatch(src), isFalse,
          reason: '$yol ham bazParaProvider okuyor — "Bakiyeyi gizle" '
              'orada çalışmaz; gosterimBazParaProvider kullan.');
      expect(src, contains('gosterimBazParaProvider'), reason: yol);
    }
    // Temettü geçmişi kartı kendi ₺'sini yazıyor → tercihi kendisi okur.
    expect(ekranKaynagiSync('lib/widgets/temettu_gecmisi_karti.dart'),
        contains('ref.watch(balanceHiddenProvider)'));
  });
}
