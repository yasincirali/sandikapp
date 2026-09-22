import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/milestone_service.dart';
import 'package:portfoy_takip/services/recap_service.dart';

/// Denetim 2026-09-22 — kullanıcının işaret ettiği dört kritik yüzeyde
/// bulunan BEŞ hatanın regresyon kilidi.
///
/// Kullanıcı isteği: "ana sayfa üst kart, günlük kartı ortak toplanabilirliği,
/// performans ekranı, ve al/sat/temettü/sil/ekle işlemlerinin bunları doğru
/// etkilemesi."
///
/// ## Bu dosyadaki testlerin hepsi ÖNCE KIRILDI
/// Her biri düzeltme geri alındığında kırılacak şekilde yazıldı; ölçülen
/// hatalı değerler yorumlarda duruyor. Tautolojik test (aynı ifadeyi iki
/// kez hesaplayıp karşılaştırmak) bu projede bir kez yazıldı ve fark
/// edilip silindi — buradaki beklentiler ELDE HESAPLANMIŞ sabitlerdir.
Asset _lot({
  required String id,
  String userId = 'ben',
  String ticker = 'THYAO',
  AssetType type = AssetType.hisse,
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double dividend = 0,
  double commission = 0,
  DateTime? date,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: date ?? DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
      dividendAmount: dividend,
      commission: commission,
    );

/// Altın lot'u — rozet kuralı `subCategory`'ye bakar, ticker'a değil
/// (`MilestoneService._goldLabels`). Fixture bunu taşımazsa test sessizce
/// "rozet yok" der ve hiçbir şey doğrulamaz.
Asset _altin({
  required String id,
  double qty = 10,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
}) =>
    Asset(
      id: id,
      userId: 'ben',
      name: 'Gram Altın',
      ticker: 'ALTIN_GRAM',
      type: AssetType.altin,
      subCategory: 'ALTIN_GRAM',
      quantity: qty,
      purchasePrice: 2000,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: 2400,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // BUG 1 — Bugün yapılan işlem sahte günlük kâr üretiyordu
  // ══════════════════════════════════════════════════════════════════════
  group('BUG1 — gün içi seri bayatlığı', () {
    final gunBasi = DateTime(2026, 9, 22);
    final simdi = DateTime(2026, 9, 22, 14, 0);

    /// Gün başı ₺1.000 olan DÜZ bir seans (10 lot × ₺100 → fiyat ₺120'ye
    /// çıkmış değil; seri sabit). Fiyat hiç oynamadıysa günlük kâr sıfır
    /// olmalı — işlem yapmak bunu değiştirmemeli.
    Map<int, double> seri(double deger) => {
          gunBasi.add(const Duration(hours: 10)).millisecondsSinceEpoch: deger,
          gunBasi.add(const Duration(hours: 13)).millisecondsSinceEpoch: deger,
        };

    test('TAZE seri: bugün alınan lot sahte kâr üretmez', () {
      // Sabah 10 lot @120 = ₺1.200. Saat 11'de 5 lot daha @120 = +₺600.
      //
      // TAZELENMİŞ seri gerçeği anlatır: gün ₺1.200 ile AÇILDI, alımdan
      // SONRA ₺1.800'e çıktı. Basamak nakit girişidir, hareket değil —
      // `inflowOnDay` onu çıkarır ve geriye SIFIR kalır.
      //
      // Bayat seride ise basamak HİÇ OLUŞMAZ (seri ₺1.200'de çakılı
      // kalır, yalnızca canlı uç ₺1.800 olur) ve aynı çıkarma bu kez
      // gerçek olmayan bir farkı örter → +₺200 sahte kâr.
      final assets = [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, date: DateTime(2026, 1, 1)),
        _lot(
            id: 'b2',
            qty: 5,
            buy: 120,
            cur: 120,
            date: DateTime(2026, 9, 22, 11)),
      ];
      final st = PortfolioState(assets: assets);
      final tazeSeri = {
        gunBasi.add(const Duration(hours: 10)).millisecondsSinceEpoch: 1200.0,
        gunBasi.add(const Duration(hours: 13)).millisecondsSinceEpoch: 1800.0,
      };
      final d = DailySummary.from(
        state: st,
        series: tazeSeri,
        now: simdi,
        seansGunu: gunBasi,
        kapsamLotlari: assets,
      );
      expect(d.totalTRY, 1800.0);
      expect(d.changeTRY, closeTo(0, 0.01),
          reason: 'fiyat oynamadı; alım kârın kendisi olamaz');
    });

    test('mutasyon önbelleği DÜŞÜRÜR — bayat seri ile hesap yapılmaz', () {
      // Bu, BUG1'in yapısal kilidi. Önbellek dolu, sonra defter değişti.
      // `clear()` çağrılmazsa bir sonraki çağrı ₺1.000'lik BAYAT gün başını
      // kullanır ve +₺200 sahte kâr üretir (ölçüldü, denetim 2026-09-22).
      final cache = IntradaySeriesCache.instance;
      cache.seedForTest(
        series: seri(1000),
        fetchedAt: simdi,
        ownerId: 'ben',
        seansGunu: gunBasi,
      );
      expect(cache.series, isNotEmpty, reason: 'önkoşul: önbellek dolu');

      // PortfolioNotifier._gunIciSeriyiDusur() bunu çağırır.
      cache.clear();

      expect(cache.series, isEmpty,
          reason: 'defter değiştiyse bayat gün başı KULLANILMAMALI');
      expect(cache.seansGunu, isNull);
    });

    test('bayat seri sahte kârı ÖLÇÜLÜR (düzeltmenin gerekçesi)', () {
      // Düzeltme YOKSA ne olurdu: seri ₺1.000'de kalır, canlı uç ₺1.800.
      // `inflowOnDay` ₺600 çıkarır ama fark ₺800'dür → +₺200 artakalır.
      final assets = [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, date: DateTime(2026, 1, 1)),
        _lot(
            id: 'b2',
            qty: 5,
            buy: 120,
            cur: 120,
            date: DateTime(2026, 9, 22, 11)),
      ];
      final st = PortfolioState(assets: assets);
      final bayat = DailySummary.from(
        state: st,
        series: seri(1000), // TAZELENMEMİŞ
        now: simdi,
        seansGunu: gunBasi,
        kapsamLotlari: assets,
      );
      // Bu, hatanın BÜYÜKLÜĞÜNÜ belgeler; düzeltme önbelleği düşürerek
      // bu girdinin hiç oluşmamasını sağlar.
      expect(bayat.changeTRY, closeTo(200, 0.01),
          reason: 'bayat seri +₺200 sahte kâr üretiyordu — kanıt');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // BUG 2 — ham isBuy: satılmış varlık "elimde" sayılıyordu
  // ══════════════════════════════════════════════════════════════════════
  group('BUG2 — açık pozisyon kümesi', () {
    test('RecapService tür dağılımı satılan lotu saymaz', () {
      // 10 al, 8 sat → elde 2 lot = ₺240.
      // ESKİDEN: ₺1.200 (BEŞ KAT) — ham isBuy satışı düşmüyordu.
      final assets = [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(id: 's1', qty: 8, kind: AssetKind.sell, sellPrice: 130),
      ];
      final st = PortfolioState(assets: assets);
      final r = RecapService.compute(
        period: '1Y',
        assets: assets,
        snapshots: const [],
        toTRY: st.toTRY,
        now: DateTime(2026, 9, 22),
      );
      final toplam = r.valueByType.values.fold<double>(0, (a, b) => a + b);
      expect(toplam, closeTo(240, 0.01),
          reason: 'eskiden ₺1.200 idi — elde olmayan varlık sayılıyordu');
      expect(toplam, closeTo(st.totalValue, 0.01),
          reason: 'Σ tür == üst kart toplamı');
    });

    test('tamamen satılmış varlık türü dağılımdan TAMAMEN düşer', () {
      final assets = [
        _lot(id: 'b1', ticker: 'THYAO', qty: 10),
        _lot(id: 's1', ticker: 'THYAO', qty: 10, kind: AssetKind.sell, sellPrice: 130),
        _lot(
            id: 'a1',
            ticker: 'ALTIN_GRAM',
            type: AssetType.altin,
            qty: 5,
            buy: 2000,
            cur: 2400),
      ];
      final st = PortfolioState(assets: assets);
      final r = RecapService.compute(
        period: '1Y',
        assets: assets,
        snapshots: const [],
        toTRY: st.toTRY,
        now: DateTime(2026, 9, 22),
      );
      expect(r.valueByType.containsKey(AssetType.hisse), isFalse,
          reason: 'hisse tamamen satıldı, tür listesinde olmamalı');
      expect(r.typeCount, 1);
    });

    test('Milestone: satılmış altın rozet kazandırmaz', () {
      // 10 gram altın alıp HEPSİNİ satan kullanıcı "altın biriktirici"
      // rozetini almamalı. Eskiden ham isBuy ile alıyordu.
      // `subCategory` ŞART: rozet kuralı türe değil AYARA bakar
      // (`_goldLabels`). Ticker'la eşleşme aranmaz.
      final satilmis = [
        _altin(id: 'a1', qty: 10),
        _altin(id: 'a2', qty: 10, kind: AssetKind.sell, sellPrice: 2500),
      ];
      final bos = MilestoneService.evaluate(
          assets: satilmis, totalTRY: 0, now: DateTime(2026, 9, 22));
      expect(bos.where((m) => m.kind == 'gold_count'), isEmpty,
          reason: 'elde altın yok — rozet verilmemeli');

      // Kontrol: elde TUTAN kullanıcı rozeti ALIR (test tautolojik değil).
      final tutan = [satilmis.first];
      final dolu = MilestoneService.evaluate(
          assets: tutan, totalTRY: 24000, now: DateTime(2026, 9, 22));
      expect(dolu.where((m) => m.kind == 'gold_count'), isNotEmpty,
          reason: 'gerçekten tutana rozet VERİLMELİ');
    });

    test('Milestone: çeşitlilik satılmış türleri saymaz', () {
      final assets = [
        for (final t in [AssetType.hisse, AssetType.fon, AssetType.emtia])
          _lot(id: 'b_${t.name}', ticker: t.name.toUpperCase(), type: t, qty: 10),
        // Üçünün de tamamı satıldı.
        for (final t in [AssetType.hisse, AssetType.fon, AssetType.emtia])
          _lot(
              id: 's_${t.name}',
              ticker: t.name.toUpperCase(),
              type: t,
              qty: 10,
              kind: AssetKind.sell,
              sellPrice: 130),
      ];
      final m = MilestoneService.evaluate(
          assets: assets, totalTRY: 0, now: DateTime(2026, 9, 22));
      expect(m.where((x) => x.kind == 'diversification'), isEmpty,
          reason: 'hiçbiri elde değil — çeşitlilik rozeti olmamalı');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // BUG 3 — "En sabırlı varlık" satılmış varlığı seçiyordu
  // ══════════════════════════════════════════════════════════════════════
  group('BUG3 — en sabırlı varlık', () {
    test('satılmış varlık aday DEĞİL; elde olan seçilir', () {
      // kartlar.dart ile AYNI hesap (acikPozisyonlar + firstBuyDate).
      final assets = [
        _lot(id: 'o1', ticker: 'ESKI', qty: 10, date: DateTime(2020, 1, 1)),
        _lot(
            id: 'o2',
            ticker: 'ESKI',
            qty: 10,
            kind: AssetKind.sell,
            sellPrice: 130,
            date: DateTime(2020, 6, 1)),
        _lot(id: 'y1', ticker: 'YENI', qty: 5, date: DateTime(2026, 1, 1)),
      ];
      final acik = aggregatePositionsByOwner(
          [for (final l in lotlarSahibeGore(assets)) aktifLotlar(l)]);

      Asset? enEski;
      DateTime? enEskiTarih;
      for (final p in acik) {
        final t = p.firstBuyDate;
        if (enEskiTarih == null || t.isBefore(enEskiTarih)) {
          enEskiTarih = t;
          enEski = p.asDisplayAsset();
        }
      }
      expect(enEski?.name, 'YENI',
          reason: 'eskiden 2020de SATILMIŞ olan ESKI seçiliyordu');
      expect(enEskiTarih, DateTime(2026, 1, 1));
    });

    test('üstüne alım yapmak sabrı KISALTMAZ (firstBuyDate)', () {
      // Aynı hisseye 2020de girip 2026da eklemek "6 yıldır tutuyorum"u
      // bozmamalı. Temsilci en YENİ alımdır; onun tarihi kullanılsaydı
      // kullanıcı sabırsız görünürdü.
      final assets = [
        _lot(id: 'b1', qty: 10, date: DateTime(2020, 1, 1)),
        _lot(id: 'b2', qty: 5, date: DateTime(2026, 1, 1)),
      ];
      final acik = aggregatePositionsByOwner(
          [for (final l in lotlarSahibeGore(assets)) aktifLotlar(l)]);
      expect(acik.single.firstBuyDate, DateTime(2020, 1, 1));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // BUG 4 — satış komisyonu iki kez cezalandırıyordu
  // ══════════════════════════════════════════════════════════════════════
  group('BUG4 — satış komisyonu', () {
    test('açık pozisyonun maliyetine GİRMEZ', () {
      // 10 al @100, 4 sat @130, satış komisyonu ₺50.
      // Elde 6 lot → taban ₺600 (satış komisyonu buraya ait değil).
      // ESKİDEN: ₺650, yüzde %20 yerine %10,77.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 's1',
            qty: 4,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130,
            commission: 50),
      ]);
      expect(st.totalCost, closeTo(600, 0.01),
          reason: 'eskiden ₺650 — satış komisyonu açık lota yapışıyordu');
      expect(st.capitalGainLoss, closeTo(120, 0.01));
      expect(st.gainLossPercentage, closeTo(20, 0.01),
          reason: 'eskiden %10,77');
    });

    test('gerçekleşen kâr/zarardan DÜŞÜLÜR', () {
      // 4 × (130 − 100) = ₺120 brüt, − ₺50 komisyon = ₺70 net.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 's1',
            qty: 4,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130,
            commission: 50),
      ]);
      expect(st.realizedGainLoss, closeTo(70, 0.01),
          reason: 'eskiden ₺120 — komisyon hiç düşülmüyordu');
    });

    test('ALIM komisyonu maliyette KALIR (bozulmadı)', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, commission: 25),
      ]);
      expect(st.totalCost, closeTo(1025, 0.01),
          reason: 'alım komisyonu maliyetin parçasıdır — değişmemeli');
    });

    test('tamamen satılan pozisyonda komisyon KAYBOLMAZ', () {
      // Pozisyon aggregate sonucundan düşer; realize ham defterden okur.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120, commission: 30),
        _lot(
            id: 's1',
            qty: 10,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130,
            commission: 30),
      ]);
      expect(st.totalCost, 0.0, reason: 'elde hiçbir şey yok');
      expect(st.realizedGainLoss, closeTo(270, 0.01),
          reason: '10×(130−100)=300, −₺30 satış komisyonu = ₺270');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // BUG 5 — her şeyini satmış kullanıcıda yüzde %0 diyordu
  // ══════════════════════════════════════════════════════════════════════
  group('BUG5 — yüzde paydası', () {
    test('tamamen satılmış + temettü: tutar ve yüzde ÇELİŞMEZ', () {
      // ESKİDEN: gainLoss ₺50 ama yüzde %0 — iki rakam yan yana
      // çiziliyor (portfolio_summary_widget) ve birbiriyle çelişiyordu.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
        _lot(
            id: 's1',
            qty: 10,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
        _lot(
            id: 'd1',
            qty: 0,
            buy: 0,
            cur: 0,
            kind: AssetKind.dividend,
            dividend: 50),
      ]);
      expect(st.totalCost, 0.0);
      expect(st.gainLoss, closeTo(50, 0.01));
      expect(st.gainLossPercentage, greaterThan(0),
          reason: 'kâr varken yüzde %0 yazamaz — eskiden öyleydi');
      // ₺50 / ₺1.000 yatırılmış sermaye = %5
      expect(st.gainLossPercentage, closeTo(5, 0.01));
    });

    test('OLAĞAN portföyde payda DEĞİŞMEDİ (regresyon)', () {
      // Kapanmış pozisyon yoksa davranış birebir eskisi gibi olmalı.
      final st = PortfolioState(assets: [
        _lot(id: 'b1', qty: 10, buy: 100, cur: 120),
      ]);
      expect(st.totalCost, closeTo(1000, 0.01));
      expect(st.gainLossPercentage, closeTo(20, 0.01));
      expect(st.kapanmisSermaye, 0.0,
          reason: 'kapanmış pozisyon yok — ikinci parça devreye girmemeli');
    });

    test('kapanmış sermaye AÇIK pozisyonu çift saymaz', () {
      final st = PortfolioState(assets: [
        // Açık: 10 lot, ₺1.000
        _lot(id: 'b1', ticker: 'ACIK', qty: 10, buy: 100, cur: 120),
        // Kapalı: ₺500 bağlanmıştı
        _lot(id: 'b2', ticker: 'KAPALI', qty: 5, buy: 100, cur: 120),
        _lot(
            id: 's2',
            ticker: 'KAPALI',
            qty: 5,
            buy: 100,
            cur: 120,
            kind: AssetKind.sell,
            sellPrice: 130),
      ]);
      expect(st.totalCost, closeTo(1000, 0.01), reason: 'yalnızca açık olan');
      expect(st.kapanmisSermaye, closeTo(500, 0.01),
          reason: 'yalnızca kapanmış olan — açık olan burada sayılmaz');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Kullanıcının asıl istediği değişmez: ortakların toplamı == Birlikte
  // ══════════════════════════════════════════════════════════════════════
  group('TOPLANABİLİRLİK — düzeltmelerden sonra da korunuyor', () {
    final ben = [_lot(id: 'b1', userId: 'ben', qty: 10, buy: 100, cur: 120)];
    final ortak = [
      _lot(id: 'o1', userId: 'ortak', qty: 6, buy: 100, cur: 120),
      _lot(
          id: 'o2',
          userId: 'ortak',
          qty: 4,
          buy: 100,
          cur: 120,
          kind: AssetKind.sell,
          sellPrice: 130,
          commission: 20),
    ];

    test('değer, maliyet ve kâr ÜÇÜ DE toplanır', () {
      final sBen = PortfolioState(assets: ben);
      final sOrtak = PortfolioState(assets: ortak);
      final sBirlikte = PortfolioState(assets: [...ben, ...ortak]);

      expect(sBen.totalValue + sOrtak.totalValue,
          closeTo(sBirlikte.totalValue, 0.01));
      expect(sBen.totalCost + sOrtak.totalCost,
          closeTo(sBirlikte.totalCost, 0.01));
      expect(sBen.capitalGainLoss + sOrtak.capitalGainLoss,
          closeTo(sBirlikte.capitalGainLoss, 0.01));
      expect(sBen.realizedGainLoss + sOrtak.realizedGainLoss,
          closeTo(sBirlikte.realizedGainLoss, 0.01),
          reason: 'komisyon düzeltmesi toplanabilirliği bozmamalı');
    });

    test('aynı hissede ortağın satışı benim lotumu düşürmez', () {
      final sBirlikte = PortfolioState(assets: [...ben, ...ortak]);
      // ben 10 + ortak 2 = 12 lot × ₺120
      expect(sBirlikte.totalValue, closeTo(1440, 0.01));
    });
  });
}
