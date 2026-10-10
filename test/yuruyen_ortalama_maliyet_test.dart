import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/bes_hesabi.dart';

/// Açık pozisyonun maliyeti YÜRÜYEN ortalamadır: satıştan sonra gelen alım
/// yalnız elde kalanların ortalamasına karışır (`_yuruyenOrtalama`).
///
/// Kullanıcı bildirimi 2026-10-10: BES'te fon değişimi + aylık katkı
/// sonrası kartın "ana para"sı yatırılan katkıdan saptı, fark kâra yazıldı.
void main() {
  var n = 0;
  Asset al(String kod, double adet, double maliyet, double fiyat, DateTime t,
          {AssetType tur = AssetType.bes}) =>
      Asset(
        id: 'l${n++}',
        userId: 'u',
        name: kod,
        ticker: 'TEFAS:$kod',
        type: tur,
        subCategory: tur == AssetType.bes ? BesAltKategori.katki : null,
        quantity: adet,
        purchasePrice: maliyet / adet,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        lastUpdated: t,
        addedDate: t,
        sozlesmeId: tur == AssetType.bes ? 's' : null,
      );
  Asset sat(String kod, double adet, double birim, double fiyat, DateTime t,
          {AssetType tur = AssetType.bes}) =>
      Asset(
        id: 'l${n++}',
        userId: 'u',
        name: kod,
        ticker: 'TEFAS:$kod',
        type: tur,
        subCategory: tur == AssetType.bes ? BesAltKategori.katki : null,
        quantity: adet,
        purchasePrice: birim,
        sellPrice: birim,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        lastUpdated: t,
        kind: AssetKind.sell,
        addedDate: t,
        sozlesmeId: tur == AssetType.bes ? 's' : null,
      );

  test('BES: fon değişimleri + aylık katkılar → ana para == yatırılan', () {
    final lots = <Asset>[];
    var t = DateTime(2026, 1, 1);
    var fiyat = {'A': 1.0, 'B': 1.0};

    ({double maliyet, double deger}) durum() {
      for (final l in lots) {
        l.currentPrice = fiyat[l.ticker.substring(6)]!;
      }
      var c = 0.0, v = 0.0;
      for (final p in aggregatePositions(lots)) {
        c += p.totalCost;
        v += p.totalValue;
      }
      return (maliyet: c, deger: v);
    }

    void degistir(List<FonPayi> hedef) {
      t = t.add(const Duration(days: 30));
      final mevcut = <String, ({double pay, double maliyet})>{
        for (final p in aggregatePositions(lots))
          p.representative.ticker.substring(6):
              (pay: p.totalQuantity, maliyet: p.totalCost),
      };
      for (final x in BesHesabi.fonDegisimPlani(
          mevcut: mevcut, fiyatlar: fiyat, hedef: hedef)) {
        lots.add(x.satis
            ? sat(x.kod, x.pay, x.maliyet / x.pay, fiyat[x.kod]!, t)
            : al(x.kod, x.pay, x.maliyet, fiyat[x.kod]!, t));
      }
    }

    void katki(double tl, List<FonPayi> d) {
      t = t.add(const Duration(days: 30));
      for (final e in BesHesabi.katkiyiBol(tl, d).entries) {
        lots.add(al(e.key, e.value / fiyat[e.key]!, e.value, fiyat[e.key]!, t));
      }
    }

    // Açılış: birikim 150, ana para 100, %50/%50.
    lots
      ..add(al('A', 75, 50, 1, t))
      ..add(al('B', 75, 50, 1, t));
    var yatirilan = 100.0;
    fiyat = {'A': 1.2, 'B': 1.6};
    degistir(const [FonPayi(kod: 'A', oran: 100)]);
    for (var i = 0; i < 6; i++) {
      fiyat = {'A': fiyat['A']!, 'B': fiyat['B']! * 1.04};
      katki(10, const [FonPayi(kod: 'A', oran: 100)]);
      yatirilan += 10;
    }
    degistir(const [FonPayi(kod: 'A', oran: 60), FonPayi(kod: 'B', oran: 40)]);
    expect(durum().maliyet, closeTo(yatirilan, 1e-6),
        reason: 'Eski ortalamayla burada 143,38 çıkıyordu (yatırılan 160).');
    for (var i = 0; i < 6; i++) {
      fiyat = {'A': fiyat['A']!, 'B': fiyat['B']! * 1.04};
      katki(10, const [FonPayi(kod: 'A', oran: 60), FonPayi(kod: 'B', oran: 40)]);
      yatirilan += 10;
    }
    degistir(const [FonPayi(kod: 'B', oran: 100)]);
    final d = durum();
    expect(d.maliyet, closeTo(yatirilan, 1e-6));
    expect(d.deger - d.maliyet, closeTo(d.deger - 220, 1e-6));
  });

  test('hisse: kısmi satıştan sonra alım yürüyen ortalamaya karışır', () {
    final t0 = DateTime(2026, 1, 1);
    final lots = [
      al('X', 10, 1000, 200, t0, tur: AssetType.hisse),
      sat('X', 5, 100, 200, t0.add(const Duration(days: 1)),
          tur: AssetType.hisse),
      al('X', 5, 1000, 200, t0.add(const Duration(days: 2)),
          tur: AssetType.hisse),
    ];
    final p = aggregatePositions(lots).single;
    // Elde 5 @100 + 5 @200 = 1500 (eskiden Σ alım ortalaması: 1333,33).
    expect(p.totalQuantity, 10);
    expect(p.totalCost, closeTo(1500, 1e-9));
  });

  test('tamamen satılıp yeniden alınan: eski alımlar maliyete karışmaz', () {
    final t0 = DateTime(2026, 1, 1);
    final lots = [
      al('X', 10, 500, 120, t0, tur: AssetType.hisse),
      sat('X', 10, 50, 120, t0.add(const Duration(days: 1)),
          tur: AssetType.hisse),
      al('X', 4, 480, 120, t0.add(const Duration(days: 2)),
          tur: AssetType.hisse),
    ];
    expect(aggregatePositions(lots).single.totalCost, closeTo(480, 1e-9));
  });

  test('satıştan sonra alım yoksa sonuç eskisiyle birebir', () {
    final t0 = DateTime(2026, 1, 1);
    final lots = [
      al('X', 10, 1000, 150, t0, tur: AssetType.hisse),
      al('X', 10, 2000, 150, t0.add(const Duration(days: 1)),
          tur: AssetType.hisse),
      sat('X', 5, 150, 150, t0.add(const Duration(days: 2)),
          tur: AssetType.hisse),
    ];
    // Σ alım ortalaması 150 × elde 15.
    expect(aggregatePositions(lots).single.totalCost, closeTo(2250, 1e-9));
  });

  test('tarihi tutarsız defter (elde olmayanı satış) eski ortalamaya düşer',
      () {
    final t0 = DateTime(2026, 1, 1);
    final lots = [
      sat('X', 5, 100, 200, t0, tur: AssetType.hisse),
      al('X', 10, 1000, 200, t0.add(const Duration(days: 1)),
          tur: AssetType.hisse),
      al('X', 5, 1000, 200, t0.add(const Duration(days: 2)),
          tur: AssetType.hisse),
    ];
    // Eski: 2000 / 15 × 10.
    expect(aggregatePositions(lots).single.totalCost,
        closeTo(2000 / 15 * 10, 1e-9));
  });
}
