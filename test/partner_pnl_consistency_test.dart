import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// "Birlikte" sekmesindeki kâr/zarar, tekil sekmelerin toplamına eşit olmalı.
///
/// **Bug:** Birlikte sekmesi tüm sahiplerin lot'larını TEK havuzda
/// `aggregatePositions`'a veriyordu. `positionKey` sahip bilgisi taşımaz
/// (`type|ticker|currency`) — aynı hisseye sahip iki kişinin lot'ları tek
/// pozisyona düşer. O pozisyonun TEK bir `representative` lot'u vardır ve
/// `totalValue = totalQuantity * representative.currentPrice` hesabı
/// herkesin miktarına tek kişinin fiyatını uygular.
///
/// En görünür hâli: bir tarafın fiyatı henüz çekilememişse (currentPrice=0)
/// ve temsilci o lot olursa, `PortfolioState.gainLoss` filtresi
/// (`currentPrice > 0`) birleşmiş pozisyonun TAMAMINI eler — kârda olan
/// ortağın kârı da yok olur.
///
/// **Doğru davranış:** her sahip kendi içinde aggregate edilir, sonra toplanır.
/// [ownerScopedGainLoss] bunu yapar.

Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  AssetKind kind = AssetKind.buy,
  double fx = 1.0,
  String currency = 'TRY',
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: currency,
      notes: '',
      isManualPrice: false,
      purchaseFxRate: fx,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

/// Tek sahiplik kapsamında P/L — tekil sekmelerin ("Ben", "Ortak") hesabı.
double _singleOwnerPnl(List<Asset> assets) => PortfolioState(
      assets: aggregatePositions(assets).map((p) => p.asDisplayAsset()).toList(),
    ).gainLoss;

/// BUGGY: tüm sahipleri tek havuzda aggregate eden eski "Birlikte" hesabı.
double _pooledPnl(List<List<Asset>> owners) =>
    _singleOwnerPnl([for (final o in owners) ...o]);

void main() {
  group('birlikte sekmesi kâr/zarar tutarlılığı', () {
    test('iki ortak da kârdayken birlikte de kâr ve tam toplam olmalı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 110,
            currentPrice: 120),
      ];

      expect(_singleOwnerPnl(mine), closeTo(200, 0.01), reason: 'Ben sekmesi');
      expect(_singleOwnerPnl(partner), closeTo(100, 0.01),
          reason: 'Ortak sekmesi');

      final combined = ownerScopedGainLoss([mine, partner]);
      expect(combined, closeTo(300, 0.01));
      expect(combined, greaterThan(0),
          reason: 'iki taraf da kârdayken toplam negatif olamaz');
    });

    test('fiyatı çekilememiş varlık diğer ortağın kârını silmemeli', () {
      // Regresyon: asıl kullanıcı şikâyetinin en sert hâli.
      // Benim varlığımın fiyatı henüz gelmedi (currentPrice=0) → benim P/L'im 0.
      // Ortak aynı hisseden kârda (+700).
      final mine = [
        _lot(
            userId: 'me', ticker: 'X', qty: 10, buyPrice: 100, currentPrice: 0),
      ];
      final partner = [
        _lot(
            userId: 'p1', ticker: 'X', qty: 10, buyPrice: 50, currentPrice: 120),
      ];

      expect(_singleOwnerPnl(mine), closeTo(0, 0.01));
      expect(_singleOwnerPnl(partner), closeTo(700, 0.01));

      // Eski havuzlanmış hesap ortağın kârını tamamen yutuyordu.
      expect(_pooledPnl([mine, partner]), closeTo(0, 0.01),
          reason: 'bug davranışı: birleşen pozisyon fiyatsız temsilci yüzünden elenir');

      // Düzeltilmiş hesap parçaların toplamını verir.
      expect(ownerScopedGainLoss([mine, partner]), closeTo(700, 0.01));
    });

    test('aynı hissede farklı maliyetler ortaklanmamalı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'ASELS',
            qty: 5,
            buyPrice: 50,
            currentPrice: 60),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'ASELS',
            qty: 15,
            buyPrice: 80,
            currentPrice: 60),
      ];

      expect(_singleOwnerPnl(mine), closeTo(50, 0.01));
      expect(_singleOwnerPnl(partner), closeTo(-300, 0.01));
      expect(ownerScopedGainLoss([mine, partner]), closeTo(-250, 0.01));
    });

    test('bir ortağın satışı diğerinin pozisyonunu etkilememeli', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final partner = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120,
            kind: AssetKind.sell),
      ];

      expect(_singleOwnerPnl(partner), closeTo(0, 0.01),
          reason: 'pozisyon kapandı');
      expect(ownerScopedGainLoss([mine, partner]), closeTo(200, 0.01));
    });

    test('üç taraf: birlikte her zaman parçaların toplamı', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
      ];
      final p1 = [
        _lot(
            userId: 'p1',
            ticker: 'THYAO',
            qty: 4,
            buyPrice: 130,
            currentPrice: 120),
        _lot(
            userId: 'p1',
            ticker: 'ASELS',
            qty: 2,
            buyPrice: 50,
            currentPrice: 55),
      ];
      final p2 = [
        _lot(
            userId: 'p2',
            ticker: 'ASELS',
            qty: 8,
            buyPrice: 40,
            currentPrice: 55),
      ];

      final parts =
          _singleOwnerPnl(mine) + _singleOwnerPnl(p1) + _singleOwnerPnl(p2);
      expect(ownerScopedGainLoss([mine, p1, p2]), closeTo(parts, 0.01));
    });

    test('tek sahiplik varken davranış değişmez', () {
      final mine = [
        _lot(
            userId: 'me',
            ticker: 'THYAO',
            qty: 10,
            buyPrice: 100,
            currentPrice: 120),
        _lot(
            userId: 'me',
            ticker: 'ASELS',
            qty: 5,
            buyPrice: 40,
            currentPrice: 55),
      ];
      // Ortak yokken sahip-bazlı hesap eski hesapla birebir aynı olmalı.
      expect(ownerScopedGainLoss([mine]), closeTo(_singleOwnerPnl(mine), 0.01));
    });
  });

  group('sahip-bazlı toplam değer', () {
    test('birlikte toplam değer parçaların toplamı', () {
      final mine = [
        _lot(
            userId: 'me', ticker: 'X', qty: 10, buyPrice: 100, currentPrice: 0),
      ];
      final partner = [
        _lot(
            userId: 'p1', ticker: 'X', qty: 10, buyPrice: 50, currentPrice: 120),
      ];
      // Fiyatsız lot değere 0 katkı verir; ortağınki 10*120 = 1200.
      expect(ownerScopedTotalValue([mine, partner]), closeTo(1200, 0.01));
    });
  });

  // ── Performans ekranı: ortak sekmesi ────────────────────────────────────
  //
  // Kullanıcının bildirdiği hata (2026-08-31): "ortağım 3 ay, ben 6 ay önce
  // aldığım altın günlük grafikte farklı kâr/zarar oranıyla görünüyor,
  // hatta birimiz kârdayken diğeri zararda."
  group('ortak sekmesi — pozisyon bazlı hesap', () {
    test('ortağın TÜM lot\'ları sayılır (match.first değil)', () {
      // Ortak aynı üründen üç kez almış. Ekran eskiden `assets.where(...)
      // .first` ile YALNIZCA ilk lot'u alıyordu; oran tek alıma göre
      // hesaplanıyordu.
      final partnerLots = [
        _lot(
            userId: 'p1',
            ticker: 'ALTIN_GRAM',
            qty: 10,
            buyPrice: 100,
            currentPrice: 200),
        _lot(
            userId: 'p1',
            ticker: 'ALTIN_GRAM',
            qty: 10,
            buyPrice: 300,
            currentPrice: 200),
        _lot(
            userId: 'p1',
            ticker: 'ALTIN_GRAM',
            qty: 10,
            buyPrice: 200,
            currentPrice: 200),
      ];

      final positions = aggregatePositions(partnerLots);
      expect(positions.length, 1, reason: 'üç lot tek pozisyona inmeli');

      final p = positions.single;
      expect(p.totalQuantity, closeTo(30, 0.001),
          reason: 'miktar 30 olmalı — tek lot alınsaydı 10 çıkardı');
      // Ağırlıklı ortalama maliyet: (100+300+200)/3 = 200.
      expect(p.weightedPurchasePrice, closeTo(200, 0.001));
      // Maliyet == güncel fiyat → başabaş. Yalnızca ilk lot alınsaydı
      // (100 maliyet, 200 fiyat) %100 KÂR görünürdü.
      expect(p.gainLossPercentage, closeTo(0, 0.001),
          reason: 'ağırlıklı ortalama başabaş vermeli');
    });

    test('farklı tarihte alanların TOPLAM kâr/zararı farklı olur — bu doğru',
        () {
      // Ben 6 ay önce ucuza, ortak 3 ay önce pahalıya aldı. Toplam
      // (alıştan bugüne) kâr/zarar oranlarının FARKLI olması gerçeğin
      // kendisidir — burada bastırılmamalı.
      final benim = [
        _lot(
            userId: 'me',
            ticker: 'ALTIN_GRAM',
            qty: 10,
            buyPrice: 100,
            currentPrice: 150),
      ];
      final ortak = [
        _lot(
            userId: 'p1',
            ticker: 'ALTIN_GRAM',
            qty: 10,
            buyPrice: 200,
            currentPrice: 150),
      ];

      final benimPct = aggregatePositions(benim).single.gainLossPercentage;
      final ortakPct = aggregatePositions(ortak).single.gainLossPercentage;

      expect(benimPct, closeTo(50, 0.001), reason: 'ucuza alan kârda');
      expect(ortakPct, closeTo(-25, 0.001), reason: 'pahalıya alan zararda');
      // İşaretlerin ters olması BEKLENEN davranış — maliyet farkı gerçek.
      expect(benimPct > 0 && ortakPct < 0, isTrue);
    });

    test('DÖNEM değişimi yüzdesi sahipten BAĞIMSIZ — asıl düzeltme', () {
      // Asıl hata buradaydı: dönem değişimi yüzdesi, serinin ilk noktası
      // sahibin ORTALAMA MALİYETİ ile değiştirildiği ve seri sahibin alım
      // gününde kesildiği için kişiye göre değişiyordu.
      //
      // Düzeltme sonrası yüzde ham piyasa serisinden hesaplanır:
      //   pct = (son - ilk) / ilk
      // Bu, sahibin maliyetini ve alım tarihini HİÇ kullanmaz.
      //
      // Aşağıdaki hesap ekrandaki formülün birebir aynısıdır; iki farklı
      // miktar (10 ve 7) ve iki farklı maliyet verilse de yüzde AYNI çıkar.
      double donemYuzdesi({
        required double ilkPiyasa,
        required double sonPiyasa,
        required double qty,
      }) {
        // historyMap toplam pozisyon değeri taşır → birim fiyata bölünür.
        final divisor = qty > 0 ? qty : 1.0;
        final f = (ilkPiyasa * qty) / divisor;
        final l = (sonPiyasa * qty) / divisor;
        return ((l - f) / f) * 100;
      }

      // Altın dönem içinde 180 → 200 oldu: +%11.11.
      final benim = donemYuzdesi(ilkPiyasa: 180, sonPiyasa: 200, qty: 10);
      final ortak = donemYuzdesi(ilkPiyasa: 180, sonPiyasa: 200, qty: 7);

      expect(benim, closeTo(11.111, 0.01));
      expect(ortak, closeTo(11.111, 0.01),
          reason: 'aynı dönem + aynı ürün → miktardan bağımsız AYNI yüzde');
      expect(benim, closeTo(ortak, 0.0001),
          reason: 'iki ortak aynı yüzdeyi görmeli');
    });

    test('dönem TUTARI miktara göre değişir — yüzde sabit kalırken', () {
      // Yüzde ortak, tutar kişiye özgü: aynı %11.11 hareketi 10 gramda
      // 200 TL, 7 gramda 140 TL eder. Bu ayrım kasıtlı.
      double donemTutari({
        required double ilk,
        required double son,
        required double qty,
      }) =>
          (son - ilk) * qty;

      expect(donemTutari(ilk: 180, son: 200, qty: 10), closeTo(200, 0.001));
      expect(donemTutari(ilk: 180, son: 200, qty: 7), closeTo(140, 0.001));
    });
  });
}
