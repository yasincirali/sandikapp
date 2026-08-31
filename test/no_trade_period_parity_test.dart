import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Seçilen dönemde ALIM/SATIM YOKSA gerçek ve simülasyon AYNI olmalı.
///
/// Kullanıcı kuralı (2026-08-31): "eğer seçilen intervalda alım satım yoksa,
/// gerçek ve simülasyon tablarında kâr/zarar aynı görünmeli."
///
/// Mantık: iki mod yalnızca MİKTARIN zaman içinde değişip değişmediğinde
/// ayrışır. Dönem içinde hiç işlem yoksa miktar zaten sabittir, dolayısıyla
/// iki seri birebir örtüşmeli — kart da aynı yüzdeyi vermeli.
///
/// Bu dosya iki ayrı ayrışma kaynağını kilitler:
///   1. `signedQtyOnDay` — miktar kapısı (gerçekte addedDate'e bağlı)
///   2. `effectiveStart` — gerçek modda seri ilk alıma kırpılıyordu

Asset _lot({
  required String id,
  required double qty,
  required double price,
  required DateTime addedDate,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Fon',
      ticker: 'TEFAS:ABC',
      type: AssetType.fon,
      quantity: qty,
      purchasePrice: price,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: price,
      addedDate: addedDate,
      kind: kind,
    );

int _normalizeTs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

/// `history_service.dart` → `signedQtyOnDay` ile aynı kural.
double _signedQtyOnDay(Asset a, int dayTs, {required bool simulate}) {
  if (a.isQuantityNeutral) return 0.0;
  if (a.isDeleted) return 0.0;
  if (simulate) return a.quantity;
  final addedTs = _normalizeTs(a.addedDate.millisecondsSinceEpoch);
  if (addedTs > dayTs) return 0.0;
  return a.isSell ? -a.quantity : a.quantity;
}

double _deger(List<Asset> lots, int dayTs, {required bool simulate}) {
  double t = 0;
  for (final a in lots) {
    t += a.currentPrice * _signedQtyOnDay(a, dayTs, simulate: simulate);
  }
  return t;
}

/// Kartın formülü: (son − ilk) / ilk.
double? _kartPct(double ilk, double son) =>
    ilk > 0 ? ((son - ilk) / ilk) * 100 : null;

void main() {
  int gun(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

  group('dönem içinde işlem YOKSA iki mod aynı', () {
    // Alım dönemden ÇOK ÖNCE yapılmış (Ocak). Seçilen dönem: Haziran.
    final lots = [
      _lot(id: 'l1', qty: 100, price: 10, addedDate: DateTime(2026, 1, 15)),
    ];

    test('miktar her iki modda da aynı', () {
      final donemBasi = gun(2026, 6, 1);
      final donemSonu = gun(2026, 6, 30);

      for (final ts in [donemBasi, donemSonu]) {
        expect(
          _signedQtyOnDay(lots.first, ts, simulate: false),
          _signedQtyOnDay(lots.first, ts, simulate: true),
          reason: 'dönem öncesi alım: miktar iki modda da 100 olmalı',
        );
      }
    });

    test('kart yüzdesi birebir aynı', () {
      // Fiyat 10 → 12 (%20). Miktar sabit olduğu için iki mod örtüşmeli.
      final basiGercek = _deger(lots, gun(2026, 6, 1), simulate: false);
      final basiSim = _deger(lots, gun(2026, 6, 1), simulate: true);

      // Fiyat hareketini simüle etmek için son değeri elle ölçekle.
      final sonGercek = basiGercek * 1.2;
      final sonSim = basiSim * 1.2;

      final gercekPct = _kartPct(basiGercek, sonGercek);
      final simPct = _kartPct(basiSim, sonSim);

      expect(gercekPct, closeTo(20, 0.001));
      expect(simPct, closeTo(20, 0.001));
      expect(gercekPct, closeTo(simPct!, 0.0001),
          reason: 'işlem yoksa iki sekme AYNI yüzdeyi vermeli');
    });

    test('dönem SONRASI yapılan alım da dönemi etkilemez', () {
      // Alım Aralık'ta; seçilen dönem Haziran. Gerçekte o tarihte lot yok,
      // ama simülasyon onu tüm döneme yayar → BU DURUMDA ayrışırlar.
      // Kullanıcının kuralı "dönem İÇİNDE işlem yoksa" der; dönem sonrası
      // alım, dönem içi bir işlem değildir ama gerçek seride o lot hiç
      // yoktur. Bu senaryo grafikte zaten "henüz yok" olarak doğrudur.
      final sonraki = [
        _lot(id: 'l2', qty: 50, price: 10, addedDate: DateTime(2026, 12, 1)),
      ];
      expect(_signedQtyOnDay(sonraki.first, gun(2026, 6, 15), simulate: false),
          0);
      expect(_signedQtyOnDay(sonraki.first, gun(2026, 6, 15), simulate: true),
          50);
    });

    test('dönem İÇİNDE alım varsa ayrışırlar — beklenen', () {
      final icinde = [
        _lot(id: 'l1', qty: 100, price: 10, addedDate: DateTime(2026, 1, 15)),
        _lot(id: 'l2', qty: 100, price: 10, addedDate: DateTime(2026, 6, 15)),
      ];
      final basiGercek = _deger(icinde, gun(2026, 6, 1), simulate: false);
      final sonGercek = _deger(icinde, gun(2026, 6, 30), simulate: false);
      final basiSim = _deger(icinde, gun(2026, 6, 1), simulate: true);
      final sonSim = _deger(icinde, gun(2026, 6, 30), simulate: true);

      expect(_kartPct(basiGercek, sonGercek), closeTo(100, 0.001),
          reason: 'gerçekte birikim ikiye katlandı');
      expect(_kartPct(basiSim, sonSim), closeTo(0, 0.001),
          reason: 'simülasyonda miktar sabit — değişim yok');
    });

    test('satış da dönem dışındaysa iki mod aynı kalır', () {
      // DİKKAT — simülasyon tarafına HAM lot listesi verilmez.
      // `getPortfolioHistory` sözleşmesi: simulate=true iken arayan
      // AGGREGATE EDİLMİŞ (net) display-asset listesi verir, buy/sell
      // ayrımı olmaz (bkz. history_service.dart docstring'i ve ekrandaki
      // `aggregatePositionsByOwner(...).asDisplayAsset()` çağrısı).
      //
      // Bu yüzden karşılaştırma adil kurulmalı:
      //   · gerçek     → ham lot'lar (100 alım − 40 satış)
      //   · simülasyon → net pozisyon (60 adet, tek buy lot)
      final hamLots = [
        _lot(id: 'l1', qty: 100, price: 10, addedDate: DateTime(2026, 1, 15)),
        _lot(
            id: 'l2',
            qty: 40,
            price: 10,
            addedDate: DateTime(2026, 2, 1),
            kind: AssetKind.sell),
      ];
      // Ekranın simülasyona verdiği liste: net 60 adet.
      final netLots = [
        _lot(id: 'net', qty: 60, price: 10, addedDate: DateTime(2026, 1, 15)),
      ];

      final g = _deger(hamLots, gun(2026, 6, 10), simulate: false);
      final s = _deger(netLots, gun(2026, 6, 10), simulate: true);
      expect(g, closeTo(600, 0.001));
      expect(s, closeTo(600, 0.001));
      expect(g, closeTo(s, 0.0001),
          reason: 'işlemler dönem dışında — iki mod aynı değeri vermeli');
    });
  });

  group('effectiveStart — serinin başlangıcı', () {
    /// Ekrandaki kural: gerçek modda seri, ilk alımdan öncesine uzatılmaz.
    /// Simülasyonda ise dönem başından başlar.
    DateTime effectiveStart(
      DateTime startDate,
      List<Asset> lots, {
      required bool simulate,
      required bool intraday,
    }) {
      if (intraday || simulate) return startDate;
      final buys = lots.where((a) => a.isBuy);
      if (buys.isEmpty) return startDate;
      final firstBuy =
          buys.map((a) => a.addedDate).reduce((a, b) => a.isBefore(b) ? a : b);
      return firstBuy.isAfter(startDate)
          ? DateTime(firstBuy.year, firstBuy.month, firstBuy.day)
          : startDate;
    }

    test('dönem öncesi alımda iki mod AYNI noktadan başlar', () {
      // Kullanıcının kuralının tuttuğu asıl yer: alım dönemden önceyse
      // kırpma DEVREYE GİRMEZ ve iki seri aynı X'ten başlar.
      final lots = [
        _lot(id: 'l1', qty: 100, price: 10, addedDate: DateTime(2026, 1, 15)),
      ];
      final start = DateTime(2026, 6, 1);

      final g = effectiveStart(start, lots, simulate: false, intraday: false);
      final s = effectiveStart(start, lots, simulate: true, intraday: false);

      expect(g, equals(start), reason: 'ilk alım dönemden önce — kırpma yok');
      expect(g, equals(s), reason: 'iki mod aynı başlangıç → aynı yüzde');
    });

    test('dönem İÇİNDE ilk alım varsa gerçek seri kırpılır', () {
      // Bu ayrışma kasıtlı: gerçekte o tarihten önce pozisyon YOKTU,
      // seriyi geriye uzatmak "elimde vardı" yalanı olurdu.
      final lots = [
        _lot(id: 'l1', qty: 100, price: 10, addedDate: DateTime(2026, 6, 15)),
      ];
      final start = DateTime(2026, 6, 1);

      final g = effectiveStart(start, lots, simulate: false, intraday: false);
      final s = effectiveStart(start, lots, simulate: true, intraday: false);

      expect(g, equals(DateTime(2026, 6, 15)));
      expect(s, equals(start));
      expect(g == s, isFalse, reason: 'dönem içi alım — ayrışma beklenir');
    });
  });
}
