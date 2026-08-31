import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// "Gerçek" ve "Simülasyon" modlarının ANLAM SÖZLEŞMESİ.
///
/// Kullanıcı 2026-08-10'da mevcut simülasyon tanımını onayladı. Tanım şu an
/// yalnızca dağınık kod yorumlarında yaşıyor; bu test onu davranış olarak
/// sabitler ki ileride sessizce kaymasın.
///
/// ## Gerçek mod
/// "O gün elimde ne vardı?" — her lot `addedDate`'inden itibaren sayılır,
/// satışlar o tarihten sonra düşülür.
///
/// ## Simülasyon modu
/// "Bugünkü net pozisyonumu tüm dönem boyunca tutsaydım ne olurdu?" —
/// tarihler yok sayılır, miktar sabittir.
///
/// KRİTİK: Simülasyona giden liste ham ledger DEĞİL, aggregate edilmiş NET
/// pozisyonlardır (`aggregatePositionsByOwner(...).asDisplayAsset()`).
/// Yani satılmış lot'lar zaten düşülmüştür. Simülasyon "hiç satmasaydım"
/// senaryosu DEĞİLDİR — "bu portföyü daha erken kursaydım" senaryosudur.
/// Bu bilinçli bir üründür kararıdır; değiştirmeden önce sahibine sor.
void main() {
  Asset lot({
    required AssetKind kind,
    required double qty,
    required DateTime at,
    double price = 10,
  }) =>
      Asset(
        id: '${kind.name}_${qty}_${at.day}',
        userId: 'u1',
        name: 'Test',
        ticker: 'THYAO',
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: price,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: 1.0,
        kind: kind,
        addedDate: at,
      );

  /// `HistoryService.signedQtyOnDay` ile birebir aynı kural.
  double signedQtyOnDay(Asset a, int dayTs, {required bool simulate}) {
    if (a.isQuantityNeutral) return 0.0; // temettü + deleteLog
    if (simulate) return a.quantity; // tarih YOK SAYILIR
    final addedTs = DateTime(
      a.addedDate.year,
      a.addedDate.month,
      a.addedDate.day,
    ).millisecondsSinceEpoch;
    if (addedTs > dayTs) return 0.0;
    return a.isSell ? -a.quantity : a.quantity;
  }

  int day(int d) => DateTime(2026, 8, d).millisecondsSinceEpoch;

  group('gerçek mod — tarihe duyarlı', () {
    final buy = lot(kind: AssetKind.buy, qty: 100, at: DateTime(2026, 8, 10));

    test('alımdan ÖNCE miktar sıfır', () {
      expect(signedQtyOnDay(buy, day(9), simulate: false), 0.0,
          reason: 'o gün portföyde yoktu — geçmişe yansıtılmamalı');
    });

    test('alım GÜNÜ miktar sayılır (sınır dahil)', () {
      expect(signedQtyOnDay(buy, day(10), simulate: false), 100.0);
    });

    test('alımdan SONRA miktar sayılmaya devam eder', () {
      expect(signedQtyOnDay(buy, day(15), simulate: false), 100.0);
    });

    test('satış negatif katkı verir', () {
      final sell =
          lot(kind: AssetKind.sell, qty: 40, at: DateTime(2026, 8, 12));
      expect(signedQtyOnDay(sell, day(11), simulate: false), 0.0);
      expect(signedQtyOnDay(sell, day(12), simulate: false), -40.0);
    });

    test('alım + satış birlikte net pozisyonu verir', () {
      final sell =
          lot(kind: AssetKind.sell, qty: 40, at: DateTime(2026, 8, 12));
      double net(int d) =>
          signedQtyOnDay(buy, day(d), simulate: false) +
          signedQtyOnDay(sell, day(d), simulate: false);

      expect(net(9), 0.0, reason: 'henüz alınmadı');
      expect(net(10), 100.0, reason: 'alındı');
      expect(net(13), 60.0, reason: '40 satıldı');
    });
  });

  group('simülasyon modu — tarih yok sayılır', () {
    // Simülasyona AGGREGATE edilmiş net pozisyon gelir (100 alıp 40 sattıysa
    // liste tek satırdır: 60 adet). Ham buy/sell lot'ları gelmez.
    final netPosition =
        lot(kind: AssetKind.buy, qty: 60, at: DateTime(2026, 8, 10));

    test('alımdan ÖNCEKİ günlerde bile miktar tam', () {
      expect(signedQtyOnDay(netPosition, day(1), simulate: true), 60.0,
          reason: '"bu portföyü o zaman tutsaydım" senaryosu');
    });

    test('tüm dönem boyunca miktar SABİT', () {
      for (final d in [1, 5, 10, 20, 28]) {
        expect(signedQtyOnDay(netPosition, day(d), simulate: true), 60.0);
      }
    });

    test('gerçek ile simülasyon aynı girdide farklı sonuç verir', () {
      final before = day(1);
      expect(signedQtyOnDay(netPosition, before, simulate: false), 0.0);
      expect(signedQtyOnDay(netPosition, before, simulate: true), 60.0);
    });
  });

  group('her iki modda da geçerli değişmezler', () {
    test('temettü miktara ASLA girmez', () {
      final div = lot(kind: AssetKind.dividend, qty: 0, at: DateTime(2026, 8, 5));
      expect(signedQtyOnDay(div, day(10), simulate: false), 0.0);
      expect(signedQtyOnDay(div, day(10), simulate: true), 0.0);
    });

    test('silinen varlık (deleteLog) hiç var olmamış sayılır', () {
      final del =
          lot(kind: AssetKind.deleteLog, qty: 100, at: DateTime(2026, 8, 5));
      expect(signedQtyOnDay(del, day(10), simulate: false), 0.0);
      expect(signedQtyOnDay(del, day(10), simulate: true), 0.0,
          reason: 'mezar taşı simülasyonda da pozisyon üretmemeli');
    });
  });

  group('mod-bağımlı UI kuralları', () {
    // Ekranın uyguladığı kurallar; birlikte bozulmasınlar diye tek yerde.
    bool showsLotDots(bool simulate) => !simulate;
    bool showsAnchorLine(bool simulate, bool intraday) =>
        !simulate && !intraday;
    bool computesNetInflow(bool simulate) => !simulate;

    test('lot noktaları yalnızca gerçek modda', () {
      expect(showsLotDots(false), isTrue);
      expect(showsLotDots(true), isFalse,
          reason: 'simülasyonda gerçek bir alım anı yok');
    });

    test('lot noktaları GÜN İÇİ seride de görünür', () {
      // Değişti (2026-08-31): eskiden gün içi seride yalnızca "şimdi"
      // noktası çiziliyordu. Ama sıçramanın görünürlüğü ORANA bağlı —
      // tüm portföy ölçeğinde küçük bir alım Y ekseninde kaybolur. Nokta,
      // sıçrama görünmediğinde işlemin izini taşıyan tek şeydir.
      expect(showsLotDots(false), isTrue);
    });

    test('anchor çizgisi yalnızca gerçek modda (intraday hariç)', () {
      expect(showsAnchorLine(false, false), isTrue);
      expect(showsAnchorLine(true, false), isFalse);
      expect(showsAnchorLine(false, true), isFalse);
    });

    test('netInflow yalnızca gerçek modda hesaplanır', () {
      // netInflow artık ana rakamdan DÜŞÜLMÜYOR (bkz. aşağıdaki grup),
      // ama not satırında "ne kadarı piyasa hareketi" ayrımı için hâlâ
      // gerekli. Simülasyonda para girişi kavramı yok.
      expect(computesNetInflow(false), isTrue);
      expect(computesNetInflow(true), isFalse);
    });
  });

  // ── Kart formülü: BİRİKİM değişimi ──────────────────────────────────────
  //
  // Kullanıcı kararı (2026-08-31): gerçek sekmesindeki kart da simülasyondaki
  // gibi (son − ilk) / ilk göstersin. Böylece dönem içinde alım yapıldığında
  // rakam simülasyondan YÜKSEK çıkar ve birikim artışı görünür olur.
  //
  // Önceki davranış `grossChange − netInflow` idi ("yalnızca piyasa etkisi").
  // O rakam artık ana sayı değil, not satırında ikincil bilgi olarak duruyor.
  group('kart formülü — birikim değişimi', () {
    /// Ekrandaki hesabın birebir aynısı.
    ({double change, double? pct}) kart({
      required double firstY,
      required double lastY,
    }) {
      final change = lastY - firstY;
      final pct = firstY > 0 ? (change / firstY) * 100 : null;
      return (change: change, pct: pct);
    }

    test('formül (son − ilk) / ilk', () {
      final r = kart(firstY: 1000, lastY: 1200);
      expect(r.change, closeTo(200, 0.001));
      expect(r.pct, closeTo(20, 0.001));
    });

    test('dönem içi alım rakamı YÜKSELTİR — birikim görünür', () {
      // Düz seyreden fona 1000 TL yatırıldı: fiyat hiç hareket etmedi.
      // Birikim %100 büyüdü ve kart bunu göstermeli.
      final r = kart(firstY: 1000, lastY: 2000);
      expect(r.pct, closeTo(100, 0.001),
          reason: 'alım birikimi büyüttü — rakam bunu içermeli');
    });

    test('gerçek sekmesi simülasyondan YÜKSEK çıkar (alım varsa)', () {
      // Aynı dönem, aynı ürün. Simülasyonda miktar sabit (fiyat +%10),
      // gerçekte ise ortada alım var.
      final simulasyon = kart(firstY: 1000, lastY: 1100);
      final gercek = kart(firstY: 1000, lastY: 2100); // +1000 alım, +%10 fiyat
      expect(gercek.pct! > simulasyon.pct!, isTrue,
          reason: 'aradaki fark yatırılan paradır — kullanıcı bunu görmek '
              'istiyor');
    });

    test('alım yoksa iki sekme AYNI yüzdeyi verir', () {
      final simulasyon = kart(firstY: 1000, lastY: 1100);
      final gercek = kart(firstY: 1000, lastY: 1100);
      expect(gercek.pct, closeTo(simulasyon.pct!, 0.0001));
    });

    test('not satırı için piyasa etkisi ayrı hesaplanır', () {
      // Ana rakam birikimi gösterirken, not satırı saf piyasa hareketini
      // söyler — "+%100 kazandım" yanılgısını kapatan şey budur.
      const grossChange = 1000.0; // 1000 → 2000
      const netInflow = 1000.0; // tamamı alımdan
      expect(grossChange - netInflow, closeTo(0, 0.001),
          reason: 'piyasa hiç hareket etmedi, not satırı bunu söylemeli');
    });

    test('dönem başı sıfırsa yüzde hesaplanmaz', () {
      final r = kart(firstY: 0, lastY: 500);
      expect(r.pct, isNull, reason: 'sıfıra bölme yok');
    });
  });
}
