import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Kullanıcı isteği (2026-09-23): beş İŞLEM × dört EKRAN matrisi.
///
/// > "yeni varlık eklendiğinde, ekli bir varlığa al işlemiyle eklemeler,
/// > sat ile satmak, temettü eklemek, varlığı direkt tamamen silmek, sat
/// > diyerek miktarı 0'a indirmek — bunların ana ekran toplam varlık ve
/// > kâr/zarar tutarı, ana sayfa günlük kartı, performans günlük özet ve
/// > günlük grafik alanlarında nasıl göründüğü tutarlı olmalı."
///
/// ## Ne ölçülüyor
/// Dört yüzeyin AYNI defterden AYNI sayıyı üretmesi. Ekranlar farklı
/// fonksiyonlar çağırıyor; bu dosya onların ayrışmadığını kilitler:
///
/// | Yüzey | Kaynak |
/// |---|---|
/// | Ana ekran toplam | `PortfolioState.totalValue` |
/// | Ana ekran kâr/zarar | `PortfolioState.gainLoss` / `gainLossPercentage` |
/// | Bugün kartı | `DailySummary.from` + `ownerScopedTotalValue` |
/// | Performans Özet | `DailySummary.from(kapsamLotlari:)` |
///
/// Günlük GRAFİK kartı bilerek dışarıda: o HAM birikim gösteriyor (alım
/// dahil), Özet ise arındırılmış. İkisi TASARIM GEREĞİ farklı —
/// `TECHNICAL_DEBT.md` açık maddesi, kullanıcı kararı bekliyor.
const _gunBasi = 1200.0;

Asset _lot({
  required String id,
  String ticker = 'THYAO',
  String userId = 'ben',
  AssetType type = AssetType.hisse,
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double dividend = 0,
  DateTime? date,
  DateTime? deletedAt,
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
      deletedAt: deletedAt,
    );

final _seansGunu = DateTime(2026, 9, 23);
final _simdi = DateTime(2026, 9, 23, 14, 0);

/// TAZELENMİŞ seri: mutasyondan sonra `IntradaySeriesCache` düşürülür ve
/// seri yeniden çekilir, yani basamak GERÇEKTEN oluşur.
Map<int, double> _tazeSeri(double gunBasi, double son) => {
      _seansGunu.add(const Duration(hours: 10)).millisecondsSinceEpoch: gunBasi,
      _seansGunu.add(const Duration(hours: 13)).millisecondsSinceEpoch: son,
    };

/// Dört yüzeyin ürettiği sayılar.
({double anaToplam, double anaKar, double? kartDegisim, double? ozetDegisim})
    _dortYuzey(List<Asset> assets, Map<int, double> seri) {
  final st = PortfolioState(assets: assets);

  // Bugün kartı: `kapsamLotlari` VERMEZ (kişisel görünüm → state.assets).
  final kart = DailySummary.from(
    state: st,
    series: seri,
    now: _simdi,
    seansGunu: _seansGunu,
  );

  // Performans Özet: kapsamı AÇIKÇA verir.
  final ozet = DailySummary.from(
    state: st,
    series: seri,
    now: _simdi,
    seansGunu: _seansGunu,
    kapsamLotlari: assets,
  );

  return (
    anaToplam: st.totalValue,
    anaKar: st.gainLoss,
    kartDegisim: kart.changeTRY,
    ozetDegisim: ozet.changeTRY,
  );
}

void main() {
  // Başlangıç defteri: 10 lot @100, güncel 120 → ₺1.200.
  List<Asset> temel() => [_lot(id: 'b1')];

  group('İŞLEM 1 — yeni varlık eklendi', () {
    test('toplam artar, günlük kâr SIÇRAMAZ', () {
      // Bugün ₺600'lük YENİ bir varlık eklendi (5 lot @120).
      final assets = [
        ...temel(),
        _lot(
            id: 'yeni',
            ticker: 'KCHOL',
            qty: 5,
            buy: 120,
            cur: 120,
            date: DateTime(2026, 9, 23, 11)),
      ];
      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, 1800));

      expect(r.anaToplam, 1800.0, reason: '₺1.200 + ₺600');
      expect(r.kartDegisim, closeTo(0, 0.01),
          reason: 'fiyat oynamadı — yatırılan para kâr değildir');
      expect(r.ozetDegisim, closeTo(r.kartDegisim!, 0.01),
          reason: 'iki yüzey AYNI sayıyı vermeli');
    });
  });

  group('İŞLEM 2 — var olan varlığa AL', () {
    test('aynı pozisyona eklenir, günlük kâr SIÇRAMAZ', () {
      final assets = [
        ...temel(),
        _lot(id: 'al', qty: 5, buy: 120, cur: 120, date: DateTime(2026, 9, 23, 11)),
      ];
      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, 1800));

      expect(r.anaToplam, 1800.0, reason: '15 lot × ₺120');
      expect(aggregatePositions(assets), hasLength(1),
          reason: 'aynı ticker → TEK pozisyon');
      expect(r.kartDegisim, closeTo(0, 0.01));
      expect(r.ozetDegisim, closeTo(r.kartDegisim!, 0.01));
    });

    test('maliyet ağırlıklı ortalamaya döner', () {
      final assets = [
        ...temel(), // 10 @100
        _lot(id: 'al', qty: 10, buy: 140, cur: 120),
      ];
      final st = PortfolioState(assets: assets);
      expect(st.totalCost, closeTo(2400, 0.01), reason: '1000 + 1400');
      expect(st.totalValue, closeTo(2400, 0.01), reason: '20 × 120');
      expect(st.gainLoss, closeTo(0, 0.01));
    });
  });

  group('İŞLEM 3 — SAT (kısmi)', () {
    test('toplam düşer, satış nakit ÇIKIŞI arındırılır', () {
      // 4 lot @130 satıldı → elde 6 lot = ₺720.
      //
      // **Beklenen +₺40, sıfır DEĞİL** (bu test ilk yazıldığında sıfır
      // bekliyordu ve kırıldı — kod doğruydu, beklenti yanlıştı):
      //
      //   seri farkı = 720 − 1.200 = −480
      //   inflow      = −(4 × 130)  = −520   (satış = negatif akış)
      //   değişim    = −480 − (−520) = +40
      //
      // +₺40 = 4 × (130 − 120): lot'lar ₺120'den değerlenirken ₺130'a
      // satıldı. Piyasa fiyatının ÜSTÜNDE satış GERÇEK bir kazançtır ve
      // günlük kâra girmesi DOĞRUDUR. Arındırılan şey anaparanın
      // çıkışıdır, kârın kendisi değil.
      final assets = [
        ...temel(),
        _lot(
            id: 's1',
            qty: 4,
            kind: AssetKind.sell,
            sellPrice: 130,
            date: DateTime(2026, 9, 23, 11)),
      ];
      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, 720));

      expect(r.anaToplam, 720.0, reason: '6 lot × ₺120');
      expect(r.kartDegisim, closeTo(40, 0.01),
          reason: 'anapara çıkışı arındırılır, piyasa üstü satış kârı KALIR');
      expect(r.ozetDegisim, closeTo(r.kartDegisim!, 0.01),
          reason: 'iki yüzey AYNI sayıyı vermeli');
    });

    test('piyasa fiyatından satış günlük kârı OYNATMAZ', () {
      // Kontrol: satış ₺120'den (piyasa fiyatı) yapılırsa değişim sıfır.
      // Bir üstteki +₺40'ın nereden geldiğini kanıtlar.
      final assets = [
        ...temel(),
        _lot(
            id: 's1',
            qty: 4,
            kind: AssetKind.sell,
            sellPrice: 120,
            date: DateTime(2026, 9, 23, 11)),
      ];
      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, 720));
      expect(r.kartDegisim, closeTo(0, 0.01),
          reason: 'piyasa fiyatından satış saf nakit çıkışıdır');
      expect(r.ozetDegisim, closeTo(0, 0.01));
    });

    test('gerçekleşen kâr AYRI satırda, maliyete karışmaz', () {
      final st = PortfolioState(assets: [
        ...temel(),
        _lot(id: 's1', qty: 4, kind: AssetKind.sell, sellPrice: 130),
      ]);
      expect(st.totalCost, closeTo(600, 0.01), reason: 'kalan 6 lot');
      expect(st.realizedGainLoss, closeTo(120, 0.01), reason: '4 × ₺30');
      expect(st.hasRealized, isTrue);
    });
  });

  group('İŞLEM 4 — TEMETTÜ', () {
    test('miktar DEĞİŞMEZ, toplam DEĞİŞMEZ', () {
      final assets = [
        ...temel(),
        _lot(
            id: 'd1',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 50,
            date: DateTime(2026, 9, 23, 11)),
      ];
      final st = PortfolioState(assets: assets);

      expect(st.totalValue, 1200.0, reason: 'temettü miktara girmez');
      expect(aggregatePositions(assets).single.totalQuantity, 10.0);
    });

    test('kâra girer ve AYRI satırda açıklanır', () {
      final st = PortfolioState(assets: [
        ...temel(),
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 50),
      ]);
      expect(st.totalDividend, 50.0);
      expect(st.gainLoss, closeTo(250, 0.01), reason: '₺200 fiyat + ₺50');
      expect(st.gainLoss - st.totalDividend, closeTo(st.capitalGainLoss, 0.01),
          reason: 'iki satır birbirini açıklamalı');
    });

    test('günlük kâr SIÇRAMAZ — temettü kâr değil, nakit', () {
      final assets = [
        ...temel(),
        _lot(
            id: 'd1',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 50,
            date: DateTime(2026, 9, 23, 11)),
      ];
      // Seri değişmez: temettü portföy DEĞERİNİ etkilemez.
      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, _gunBasi));
      expect(r.kartDegisim, closeTo(0, 0.01));
      expect(r.ozetDegisim, closeTo(r.kartDegisim!, 0.01));
    });

    test('pozisyon paneli ile üst kart TUTAR', () {
      final assets = [
        ...temel(),
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 50),
      ];
      final st = PortfolioState(assets: assets);
      final panelToplami = aggregatePositions(assets)
          .fold<double>(0, (t, p) => t + totalDividendTRY(p.lots));
      expect(panelToplami, closeTo(st.totalDividend, 0.01));
    });
  });

  group('İŞLEM 5 — TAMAMEN SİL', () {
    test('silinen varlık HİÇBİR yüzeyde yok', () {
      final assets = [
        _lot(id: 'b1'),
        _lot(id: 'b2', ticker: 'KCHOL', qty: 5, buy: 100, cur: 120,
            deletedAt: DateTime(2026, 9, 23, 11)),
      ];
      final st = PortfolioState(assets: assets);

      expect(st.totalValue, 1200.0, reason: 'silinen ₺600 sayılmamalı');
      expect(aggregatePositions(assets), hasLength(1));
      expect(st.activeAssets.any((a) => a.id == 'b2'), isFalse);
    });

    test('silinen varlığın temettüsü de düşer', () {
      final st = PortfolioState(assets: [
        _lot(id: 'b1'),
        _lot(
            id: 'd1',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 50,
            deletedAt: DateTime(2026, 9, 23)),
      ]);
      expect(st.totalDividend, 0.0,
          reason: 'silinen temettü cebe girmemiş sayılır');
    });

    test('her şey silinince toplam SIFIR — uydurma kâr yok', () {
      final st = PortfolioState(
          assets: [_lot(id: 'b1', deletedAt: DateTime(2026, 9, 23))]);
      expect(st.totalValue, 0.0);
      expect(st.totalCost, 0.0);
      expect(st.gainLossPercentage, 0.0,
          reason: 'elde hiçbir şey yokken yüzde uydurulmaz');
    });
  });

  group('İŞLEM 6 — SAT ile miktarı 0\'a indir (kapanan pozisyon)', () {
    final kapali = [
      _lot(id: 'b1'),
      _lot(
          id: 's1',
          qty: 10,
          kind: AssetKind.sell,
          sellPrice: 130,
          date: DateTime(2026, 9, 23, 11)),
    ];

    test('pozisyon listeden düşer, toplam SIFIR', () {
      final st = PortfolioState(assets: kapali);
      expect(st.totalValue, 0.0);
      expect(aggregatePositions(kapali), isEmpty);
    });

    test('OLMAYAN varlıktan kâr GÖSTERİLMEZ', () {
      final st = PortfolioState(assets: kapali);
      expect(st.totalCost, 0.0, reason: 'satış lotu maliyete sayılmamalı');
      expect(st.capitalGainLoss, 0.0);
    });

    test('gerçekleşen kâr KAYBOLMAZ', () {
      final st = PortfolioState(assets: kapali);
      expect(st.realizedGainLoss, closeTo(300, 0.01), reason: '10 × ₺30');
    });

    test('temettü varsa yüzde ÇELİŞMEZ', () {
      final st = PortfolioState(assets: [
        ...kapali,
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 50),
      ]);
      expect(st.gainLoss, closeTo(50, 0.01));
      expect(st.gainLossPercentage, greaterThan(0),
          reason: 'tutar kâr derken yüzde %0 yazamaz');
    });

    test('günlük: iki yüzey yine TUTAR', () {
      final r = _dortYuzey(kapali, _tazeSeri(_gunBasi, 0));
      expect(r.anaToplam, 0.0);
      // Seri sıfıra indiği için değişim hesaplanamaz (open>0, last=0);
      // önemli olan İKİ YÜZEYİN AYNI ŞEYİ söylemesi.
      expect(r.kartDegisim, r.ozetDegisim);
    });
  });

  group('ÇAPRAZ — ardışık işlemler sonrası tutarlılık', () {
    test('al → sat → temettü zinciri: dört yüzey hizalı', () {
      final assets = [
        _lot(id: 'b1'), // 10 @100
        _lot(id: 'al', qty: 10, buy: 120, cur: 120,
            date: DateTime(2026, 9, 23, 10)), // +10
        _lot(id: 's1', qty: 5, kind: AssetKind.sell, sellPrice: 130,
            date: DateTime(2026, 9, 23, 11)), // −5
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 40,
            date: DateTime(2026, 9, 23, 12)),
      ];
      final st = PortfolioState(assets: assets);

      // Net 15 lot × ₺120 = ₺1.800
      expect(st.totalValue, closeTo(1800, 0.01));
      // Maliyet: ağırlıklı (10×100 + 10×120)/20 = 110 → 15 × 110 = 1650
      expect(st.totalCost, closeTo(1650, 0.01));
      expect(st.totalDividend, 40.0);
      expect(st.gainLoss, closeTo(1800 - 1650 + 40, 0.01));

      final r = _dortYuzey(assets, _tazeSeri(_gunBasi, 1800));
      expect(r.kartDegisim, closeTo(r.ozetDegisim!, 0.01),
          reason: 'zincir sonunda da iki yüzey ayrışmamalı');
    });

    test('ortak defteriyle birlikte: toplanabilirlik korunur', () {
      final ben = [_lot(id: 'b1', userId: 'ben')];
      final ortak = [
        _lot(id: 'o1', userId: 'ortak', qty: 6),
        _lot(id: 'o2', userId: 'ortak', qty: 4, kind: AssetKind.sell,
            sellPrice: 130),
        _lot(id: 'od', userId: 'ortak', qty: 0, kind: AssetKind.dividend,
            dividend: 25),
      ];
      final sBen = PortfolioState(assets: ben);
      final sOrtak = PortfolioState(assets: ortak);
      final sBirlikte = PortfolioState(assets: [...ben, ...ortak]);

      expect(sBen.totalValue + sOrtak.totalValue,
          closeTo(sBirlikte.totalValue, 0.01));
      expect(sBen.gainLoss + sOrtak.gainLoss,
          closeTo(sBirlikte.gainLoss, 0.01));
      expect(sBen.totalDividend + sOrtak.totalDividend,
          closeTo(sBirlikte.totalDividend, 0.01));
    });
  });
}
