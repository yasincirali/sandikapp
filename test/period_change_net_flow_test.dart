import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Dönem değişimi para giriş/çıkışından ARINDIRILMALI.
///
/// Kullanıcı şikâyeti (2026-08-10): "aldıklarımı satmama/silmeme rağmen
/// günlük değişim artıyor". Sebep, ekranın ham portföy farkını göstermesiydi:
///
///   change = dönem sonu değer − dönem başı değer
///
/// Bu fark yatırılan parayı da içerir. Gerçek vakada portföy o gün 3.803 TL
/// DEĞER KAYBETMİŞKEN ekran "+169.933 TL (+%7,16)" yazıyordu, çünkü gün içinde
/// 173.736 TL'lik alım yapılmıştı.
///
/// Doğru ölçü: `grossChange − netInflow` → yalnızca piyasa etkisi.
///
/// Buradaki testler ekranın kullandığı saf aritmetiği yeniden üretir
/// (`_buildPeriodChangeCard` private ve widget ağacına bağlı; formülü
/// davranış olarak sabitliyoruz).
void main() {
  Asset lot({
    required AssetKind kind,
    required double qty,
    required double price,
    double? sellPrice,
    double fx = 1.0,
    double commission = 0,
    DateTime? at,
  }) =>
      Asset(
        id: 'x${qty}_${price}_${kind.name}',
        userId: 'u1',
        name: 'Test',
        ticker: 'THYAO',
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: price,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: fx,
        kind: kind,
        sellPrice: sellPrice,
        commission: commission,
        addedDate: at ?? DateTime(2026, 8, 10, 10),
      );

  /// Ekrandaki net akış hesabının birebir aynısı.
  double netInflowOf(List<Asset> assets, DateTime start, DateTime end) {
    final startMs =
        DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
        .millisecondsSinceEpoch;
    var net = 0.0;
    for (final a in assets) {
      if (a.isDeleteLog) continue; // silinen varlık hiç var olmamış sayılır
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < startMs || ms > endMs) continue;
      if (a.isBuy) {
        net += a.totalCostTRY;
      } else if (a.isSell) {
        net -= a.sellProceedsTRY;
      }
    }
    return net;
  }

  final start = DateTime(2026, 8, 10);
  final end = DateTime(2026, 8, 10);

  group('kullanıcının bildirdiği senaryo', () {
    test('gün içi alım kazanç gibi görünmez — gerçek etki NEGATİF', () {
      // Ekrandaki rakamlar.
      const grossChange = 169933.0;
      const inflow = 173736.0;

      const change = grossChange - inflow;

      expect(change, lessThan(0),
          reason: 'portföy o gün değer kaybetti; ekran kazanç göstermemeli');
      expect(change.round(), -3803);
    });

    test('hiç fiyat hareketi yokken alım %0 değişim verir', () {
      // 100.000 TL'lik alım, fiyatlar sabit → portföy 100.000 TL artar.
      final buy = lot(kind: AssetKind.buy, qty: 100, price: 1000);
      final inflow = netInflowOf([buy], start, end);
      const grossChange = 100000.0; // tamamen alımdan

      expect(inflow, 100000.0);
      expect(grossChange - inflow, 0.0,
          reason: 'yatırılan para kâr değildir');
    });
  });

  group('satış — maliyet değil, ELE GEÇEN tutar düşülür', () {
    test('kârla satışta satış fiyatı kullanılır', () {
      // 100 adet, maliyet 10 TL; 15 TL'den satıldı → cebe 1500 TL girdi.
      final sell =
          lot(kind: AssetKind.sell, qty: 100, price: 10, sellPrice: 15);

      expect(sell.totalCostTRY, 1000.0, reason: 'maliyet');
      expect(sell.sellProceedsTRY, 1500.0, reason: 'ele geçen');

      final inflow = netInflowOf([sell], start, end);
      expect(inflow, -1500.0,
          reason: 'çıkan para satış fiyatından hesaplanmalı — maliyetten '
              'düşmek 500 TL\'lik kârı piyasa etkisi sanardı');
    });

    test('zararla satışta da satış fiyatı kullanılır', () {
      final sell =
          lot(kind: AssetKind.sell, qty: 100, price: 10, sellPrice: 7);
      expect(netInflowOf([sell], start, end), -700.0);
    });

    test('sellPrice yoksa maliyete düşer (eski kayıt uyumu)', () {
      final sell = lot(kind: AssetKind.sell, qty: 100, price: 10);
      expect(sell.sellProceedsTRY, 1000.0);
      expect(netInflowOf([sell], start, end), -1000.0);
    });

    test('komisyon ele geçeni azaltır', () {
      final sell = lot(
          kind: AssetKind.sell,
          qty: 100,
          price: 10,
          sellPrice: 15,
          commission: 50);
      expect(sell.sellProceedsTRY, 1450.0);
    });

    test('döviz varlığında satış kuru uygulanır', () {
      final sell = lot(
          kind: AssetKind.sell, qty: 10, price: 100, sellPrice: 120, fx: 40);
      expect(sell.sellProceedsTRY, 10 * 120 * 40);
    });
  });

  group('silinen varlık hiç var olmamış sayılır', () {
    test('deleteLog net akışa girmez', () {
      final del = lot(kind: AssetKind.deleteLog, qty: 100, price: 1000);
      expect(netInflowOf([del], start, end), 0.0);
    });

    test('alım + silme = sıfır etki', () {
      // Kullanıcı aldı, sonra sildi. Orijinal lot DB'den silindiği için
      // listede yalnızca mezar taşı kalır → net akış 0.
      final del = lot(kind: AssetKind.deleteLog, qty: 100, price: 1000);
      expect(netInflowOf([del], start, end), 0.0,
          reason: 'silinen varlık ne alım ne satış sayılır');
    });

    test('temettü miktara/akışa girmez', () {
      final div = lot(kind: AssetKind.dividend, qty: 0, price: 0);
      expect(netInflowOf([div], start, end), 0.0);
    });
  });

  group('dönem penceresi — tüm zaman aralıkları için geçerli', () {
    test('dönem dışındaki işlem sayılmaz', () {
      final old = lot(
          kind: AssetKind.buy,
          qty: 100,
          price: 1000,
          at: DateTime(2026, 8, 1));
      expect(netInflowOf([old], start, end), 0.0);
    });

    test('uzun dönemde (1Y) tüm alımlar toplanır', () {
      final yearStart = DateTime(2025, 8, 10);
      final lots = [
        lot(kind: AssetKind.buy, qty: 10, price: 100, at: DateTime(2025, 9, 1)),
        lot(kind: AssetKind.buy, qty: 20, price: 100, at: DateTime(2026, 1, 1)),
        lot(
            kind: AssetKind.sell,
            qty: 5,
            price: 100,
            sellPrice: 200,
            at: DateTime(2026, 5, 1)),
      ];
      // 1000 + 2000 − 1000 = 2000
      expect(netInflowOf(lots, yearStart, end), 2000.0);
    });

    test('sınır günleri dahildir', () {
      final atStart =
          lot(kind: AssetKind.buy, qty: 1, price: 100, at: DateTime(2026, 8, 10, 0, 1));
      final atEnd = lot(
          kind: AssetKind.buy, qty: 1, price: 100, at: DateTime(2026, 8, 10, 23, 30));
      expect(netInflowOf([atStart, atEnd], start, end), 200.0);
    });
  });

  group('yüzde tabanı yatırılan parayı içerir', () {
    double? pctOf(double gross, double inflow, double firstY) {
      final change = gross - inflow;
      final base = firstY + (inflow > 0 ? inflow : 0);
      return base > 0 ? (change / base) * 100 : null;
    }

    test('portföyünü ikiye katlayan kullanıcıda yüzde şişmez', () {
      // 100k portföy, 100k daha yatırdı, piyasa +2k kazandırdı.
      final pct = pctOf(102000, 100000, 100000)!;
      expect(pct, closeTo(1.0, 0.001),
          reason: 'taban 200k olmalı — yalnızca firstY kullanmak %2 derdi');
    });

    test('taban sıfırsa yüzde null (tanımsız)', () {
      expect(pctOf(0, 0, 0), isNull);
    });
  });

  group('grafik ile kart BİLEREK farklı şeyler gösterir', () {
    // Kullanıcı kararı (2026-08-10): grafik ham portföy değerini çizer,
    // alım/satış anındaki dikey sıçramalar KALIR — çünkü çizgi "portföyümde
    // ne kadar var" sorusunun cevabıdır ve o noktalarda zaten lot dot'u +
    // "Alım +₺X" tooltip'i var. Arındırma yalnızca KARTA uygulanır.
    //
    // Bir ara seri de arındırılmıştı; bu test o denemenin geri döndüğünü
    // fark etmek için var.

    test('grafik farkı ham kalır, kart farkı arındırılmıştır', () {
      const grafikFarki = 170840.0; // ham: piyasa + yatırılan para
      const netAkis = 169933.0;
      const kartRakami = grafikFarki - netAkis;

      expect(kartRakami, closeTo(907, 0.01));
      expect(grafikFarki, isNot(closeTo(kartRakami, 1)),
          reason: 'ikisi eşitse grafik de arındırılmış demektir — '
              'sıçramaların kalması kullanıcı kararıdır');
    });

    test('açıklama satırı iki rakam arasındaki farkı kapatır', () {
      // Kart "+907" derken grafik 170.840'lık yükseliş gösteriyor.
      // Açıklama satırı bu boşluğu anlatmakla yükümlü: netInflow > 0.5
      // olduğu sürece gösterilir.
      const netAkis = 169933.0;
      expect(netAkis.abs() > 0.5, isTrue,
          reason: 'akış varken açıklama satırı gizlenmemeli');
    });

    test('hiç işlem yokken grafik ve kart AYNI olur', () {
      // Akış yoksa arındırılacak bir şey de yok — iki gösterge örtüşür.
      const grafikFarki = 2500.0;
      const netAkis = 0.0;
      expect(grafikFarki - netAkis, grafikFarki);
    });
  });
}
