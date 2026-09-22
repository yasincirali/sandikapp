import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfolio_summary_widget.dart';

/// Kâr/zarar denetiminin (2026-09-22) senaryoları — **ekran üzerinde**.
///
/// ## Neden widget testi
/// Denetimdeki hatalar hesap katmanında ölçüldü ve orada kilitlendi
/// (`kar_zarar_tutarliligi_test`). Ama kullanıcının gördüğü şey bu kart;
/// arada bir kat daha var (hangi alan çizilir, hangi koşulla). Bu projede
/// "hesap doğru ama ekran başka şey gösteriyor" sınıfı hatalar tekrar
/// yaşandı — `ozet_kapsam_gecisi_iskelet_test` bunun ürünü.
///
/// Emülatör Flutter'ı render edemediği için (ölçüldü: ekran görüntüsü tek
/// renk siyah) elle doğrulama yapılamıyor; bu testler o boşluğu kapatır.
/// Kapsamadıkları: görsel yerleşim, taşma, hizalama.
const _uid = 'ben';

Asset _lot({
  required String id,
  String userId = _uid,
  String ticker = 'THYAO',
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double dividend = 0,
  double commission = 0,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buy,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
      dividendAmount: dividend,
      commission: commission,
    );

Future<void> _pump(WidgetTester tester, PortfolioState state,
    {bool hideBalance = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PortfolioSummaryWidget(
            state: state,
            hideBalance: hideBalance,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Ekrandaki tüm metinleri tek dizgede toplar — rakam aramak için.
String _ekranMetni() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .join(' | ');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  group('SENARYO 1 — kısmi satış', () {
    // 10 al @100, 4 sat @130. Elde 6 lot, güncel 120.
    //   değer   = 6 × 120 = 720
    //   maliyet = 6 × 100 = 600
    //   kâr     = +120  (%20)
    // ESKİ HATA: maliyet 1.400 sayılıyor, kâr +280 / %20 çıkıyordu.
    final state = PortfolioState(assets: [
      _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
      _lot(
          id: 's1',
          qty: 4,
          buy: 100,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130),
    ]);

    testWidgets('toplam net varlık kalan lotları gösterir', (tester) async {
      await _pump(tester, state);
      expect(_ekranMetni(), contains('₺720'),
          reason: '6 lot × ₺120 — satılan 4 lot değerde olmamalı');
    });

    testWidgets('kâr/zarar yalnızca AÇIK pozisyonun kârı', (tester) async {
      await _pump(tester, state);
      final metin = _ekranMetni();
      expect(metin, contains('+₺120'),
          reason: 'eskiden +₺280 yazıyordu (satış lotu maliyete giriyordu)');
      expect(metin, isNot(contains('+₺280')),
          reason: 'eski hatalı rakam ekranda olmamalı');
    });

    testWidgets('satıştan gerçekleşen AYRI satırda', (tester) async {
      await _pump(tester, state);
      final metin = _ekranMetni();
      expect(metin, contains('Satışlardan gerçekleşen'),
          reason: 'kâr kaybolmadı, yeri değişti');
      expect(metin, contains('120'),
          reason: '4 × (130 − 100) = ₺120 realize');
    });
  });

  group('SENARYO 2 — tam satış (en net kanıt)', () {
    // Her şey satıldı: elde HİÇBİR ŞEY yok.
    // ESKİ HATA: maliyet ₺400, kâr +₺80, yüzde %20 — olmayan varlıktan kâr.
    final state = PortfolioState(assets: [
      _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
      _lot(
          id: 's1',
          qty: 10,
          buy: 100,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130),
    ]);

    testWidgets('toplam sıfır', (tester) async {
      await _pump(tester, state);
      expect(_ekranMetni(), contains('₺0'));
    });

    testWidgets('REGRESYON: olmayan varlıktan kâr GÖSTERİLMEZ',
        (tester) async {
      await _pump(tester, state);
      final metin = _ekranMetni();
      // `totalCost == 0` → kâr/zarar satırı hiç çizilmez.
      expect(metin, isNot(contains('%20')),
          reason: 'eskiden elde hiçbir şey yokken %20 kâr yazıyordu');
      expect(metin, isNot(contains('+₺80')),
          reason: 'eski hatalı rakam');
    });

    testWidgets('realize kâr yine görünür', (tester) async {
      await _pump(tester, state);
      expect(_ekranMetni(), contains('Satışlardan gerçekleşen'),
          reason: '10 × (130−100) = ₺300 kaybolmamalı');
    });
  });

  group('SENARYO 3 — ortak görünümü toplanabilirliği', () {
    // Ben 10 lot @100→120. Ortak 5 al @100 + 3 sat (net 2 lot).
    // AYNI hisse: `positionKey` sahip taşımaz, havuzlanırsa ortağın
    // satışı benim lotumu düşürür.
    final ben = [_lot(id: 'b1', userId: 'ben', qty: 10, buy: 100, cur: 120)];
    final ortak = [
      _lot(id: 'o1', userId: 'ortak', qty: 5, buy: 100, cur: 120),
      _lot(
          id: 'o2',
          userId: 'ortak',
          qty: 3,
          buy: 100,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130),
    ];

    testWidgets('Birlikte toplam = Ben + Ortak', (tester) async {
      await _pump(tester, PortfolioState(assets: ben));
      final tBen = PortfolioState(assets: ben).totalValue;

      await _pump(tester, PortfolioState(assets: ortak));
      final tOrtak = PortfolioState(assets: ortak).totalValue;

      final birlikte = PortfolioState(assets: [...ben, ...ortak]);
      await _pump(tester, birlikte);

      expect(tBen + tOrtak, closeTo(birlikte.totalValue, 0.01),
          reason: 'ortağın satışı benim lotumu düşürmemeli');
      // Ben 10×120=1200, ortak 2×120=240 → 1440
      expect(_ekranMetni(), contains('₺1.440'));
    });

    testWidgets('Birlikte kâr/zarar = Ben + Ortak', (tester) async {
      final kBen = PortfolioState(assets: ben).capitalGainLoss;
      final kOrtak = PortfolioState(assets: ortak).capitalGainLoss;
      final birlikte = PortfolioState(assets: [...ben, ...ortak]);
      expect(kBen + kOrtak, closeTo(birlikte.capitalGainLoss, 0.01));

      await _pump(tester, birlikte);
      // 10×20 + 2×20 = 240
      expect(_ekranMetni(), contains('+₺240'));
    });
  });

  group('SENARYO 4 — temettü şeffaflığı', () {
    testWidgets('temettü VARSA ayrı satırda yazılır', (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 'd1',
            qty: 0,
            buy: 0,
            cur: 0,
            kind: AssetKind.dividend,
            dividend: 50),
      ]);
      await _pump(tester, state);
      final metin = _ekranMetni();

      expect(metin, contains('Bunun temettüsü'),
          reason: 'üstteki kâr temettüyü İÇERİYOR, ekran bunu söylemeli');
      expect(metin, contains('+₺250'),
          reason: 'toplam getiri = ₺200 fiyat + ₺50 temettü');
    });

    testWidgets('temettü YOKSA satır hiç çıkmaz', (tester) async {
      await _pump(
          tester,
          PortfolioState(
              assets: [_lot(id: 'b1', qty: 10, buy: 100, cur: 120)]));
      expect(_ekranMetni(), isNot(contains('Bunun temettüsü')),
          reason: 'olmayan bir satır çizilmemeli');
    });

    testWidgets('üst kâr − temettü = fiyat hareketi (kullanıcı toplayabilsin)',
        (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 'd1',
            qty: 0,
            buy: 0,
            cur: 0,
            kind: AssetKind.dividend,
            dividend: 50),
      ]);
      expect(state.gainLoss - state.totalDividend,
          closeTo(state.capitalGainLoss, 0.01),
          reason: 'iki satır birbirini açıklamalı');
    });
  });

  group('SENARYO 5 — bozulmadı (regresyon)', () {
    testWidgets('komisyon maliyete dahil', (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, commission: 25),
      ]);
      expect(state.totalCost, 1025.0);
      await _pump(tester, state);
      expect(_ekranMetni(), contains('+₺175'),
          reason: '1200 − 1025 = 175');
    });

    testWidgets('fiyatsız lot yüzdeyi bozmaz', (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 'b2', ticker: 'XXXX', qty: 5, buy: 200, cur: 0),
      ]);
      await _pump(tester, state);
      expect(_ekranMetni(), contains('+₺200'),
          reason: 'fiyatı bilinmeyen lot ölçüme girmez');
    });

    testWidgets('bakiye gizlenince temettü satırı da gizlenir',
        (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 'd1',
            qty: 0,
            buy: 0,
            cur: 0,
            kind: AssetKind.dividend,
            dividend: 50),
      ]);
      await _pump(tester, state, hideBalance: true);
      final metin = _ekranMetni();
      expect(metin, isNot(contains('₺250')),
          reason: 'gizliyken rakam sızmamalı');
      expect(metin, isNot(contains('Bunun temettüsü')));
    });

    testWidgets('zarar durumu doğru işaretlenir', (tester) async {
      final state = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 80),
      ]);
      await _pump(tester, state);
      final metin = _ekranMetni();
      expect(metin, contains('₺800'));
      expect(metin, contains('-₺200'), reason: '10 × (80 − 100)');
    });
  });
}
