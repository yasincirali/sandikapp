import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Widget + Canlı Etkinlik gün içi grafiği, uygulamanın GÜNLÜK grafiğiyle
/// BİREBİR aynı olmalı.
///
/// Kullanıcı üç yüzeyi aynı anda görebiliyor: uygulamadaki grafik, ana ekran
/// widget'ı ve kilit ekranı. Eğrinin şekli ya da bittiği değer ayrışırsa
/// hangisine güveneceğini bilemez.
///
/// ## Ayrışmanın iki ölçülmüş sebebi
///
/// 1. **Bayat seride canlı uç eklenmiyordu.** Uygulama, serinin ucu 5
///    dakikadan eskiyse canlı toplamı AYRI bir nokta olarak ekler. Ortak
///    katman bunu "X ekseni yok" gerekçesiyle atlıyordu; yüzeyin yazdığı
///    rakam ile eğrinin bittiği yer farklı oluyordu (₺1.040.000 vs
///    ₺1.009.800).
///
/// 2. **Nakit akışı penceresi her zaman BUGÜN'dü.** Piyasa kapalıyken seri
///    SON SEANSA aittir (hafta sonu → Cuma). Seanstan SONRA girilen bir alım
///    o seansın hareketinden düşülüyordu: Cuma'nın gerçek ₺9.800'lük
///    hareketi, Pazar girilen ₺1.000'lik alım yüzünden ₺8.800 görünüyordu.
///
/// Bu dosya, `_convertHistoryToSegments` intraday dalının kopyasını referans
/// alır ve ortak katmanın ondan sapmadığını kilitler.

/// `portfolio_performance_screen._convertHistoryToSegments` intraday dalının
/// davranışsal kopyası — FlSpot yerine (dakika, değer).
///
/// Referans olarak kopyalanmasının sebebi: gerçek metod bir `State` sınıfının
/// içinde ve `context.c` (tema) ile renk okuyor, yani widget ağacı olmadan
/// çağrılamıyor. Kopya YALNIZCA geometriyi taşır; renk/kalınlık dışarıda.
List<(double, double)> _uygulamaSpotlari(
  Map<int, double> history,
  DateTime startDate,
  DateTime now,
  double? currentTotalOverride,
) {
  final sortedTs = history.keys.toList()..sort();
  final nowMs = now.millisecondsSinceEpoch;
  final simdiDt = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final bugunMu = startDate.year == simdiDt.year &&
      startDate.month == simdiDt.month &&
      startDate.day == simdiDt.day;
  final spots = <(double, double)>[];
  double? lastNonZero;
  for (final ts in sortedTs) {
    if (ts > nowMs) break;
    final y = history[ts] ?? 0;
    if (y <= 0) continue;
    lastNonZero = y;
    final minutes = (ts - startDate.millisecondsSinceEpoch) / 60000.0;
    spots.add((minutes, y));
  }
  if (bugunMu && currentTotalOverride != null && currentTotalOverride > 0) {
    final nowMinutes = (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
    if (spots.isNotEmpty && (nowMinutes - spots.last.$1).abs() < 5) {
      spots[spots.length - 1] = (nowMinutes, currentTotalOverride);
    } else {
      spots.add((nowMinutes, currentTotalOverride));
    }
  } else if (bugunMu && lastNonZero != null && spots.isNotEmpty) {
    final nowMinutes = (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
    if ((nowMinutes - spots.last.$1).abs() >= 5) {
      spots.add((nowMinutes, lastNonZero));
    }
  }
  if (spots.length < 2) return [];
  return spots;
}

List<double> _uygulamaDegerleri(
  Map<int, double> history,
  DateTime startDate,
  DateTime now,
  double? currentTotal,
) =>
    _uygulamaSpotlari(history, startDate, now, currentTotal)
        .map((e) => e.$2)
        .toList();

Map<int, double> _seans({
  required DateTime gun,
  required int baslaDk,
  required int bitDk,
  required double Function(int i) deger,
}) {
  final out = <int, double>{};
  var i = 0;
  for (var dk = baslaDk; dk <= bitDk; dk += 5) {
    out[gun.add(Duration(minutes: dk)).millisecondsSinceEpoch] = deger(i++);
  }
  return out;
}

Asset _lot({
  required String id,
  required double qty,
  required double cur,
  required DateTime added,
  AssetKind kind = AssetKind.buy,
  double purchase = 100,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: purchase,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: cur,
      addedDate: added,
      kind: kind,
    );

PortfolioState _state(List<Asset> a) =>
    PortfolioState(assets: a, usdTry: 42, eurTry: 46, gbpTry: 54);

void main() {
  group('gün içi seri — uygulamayla birebir', () {
    test('piyasa açık, seri taze: eğri aynı', () {
      final gun = DateTime(2026, 9, 10); // Perşembe
      final now = DateTime(2026, 9, 10, 14, 2);
      final h = _seans(
          gun: gun, baslaDk: 600, bitDk: 840, deger: (i) => 1000000 + i * 500.0);
      const canli = 1025000.0;

      expect(
        DailySummary.dayValues(h, now, canli, seansGunu: gun),
        _uygulamaDegerleri(h, gun, now, canli),
      );
    });

    test('BAYAT seri (>5dk): canlı uç AYRI nokta olarak eklenir', () {
      // Ayrışmanın birinci sebebi. Uygulama ekliyordu, ortak katman
      // eklemiyordu → yüzeydeki rakam ile eğrinin ucu tutmuyordu.
      final gun = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 10, 19, 30); // kapanıştan sonra
      final h = _seans(
          gun: gun,
          baslaDk: 600,
          bitDk: 1090,
          deger: (i) => 1000000 + i * 300.0);
      const canli = 1040000.0;

      final ortak = DailySummary.dayValues(h, now, canli, seansGunu: gun);
      expect(ortak, _uygulamaDegerleri(h, gun, now, canli));
      expect(ortak.last, canli,
          reason: 'eğrinin ucu yanındaki rakamla aynı yeri göstermeli');
      expect(ortak.length, h.length + 1,
          reason: 'bayat uçta canlı değer EKLENİR, son noktayı ezmez');
    });

    test('TAZE uçta canlı değer son noktayı EZER, eklemez', () {
      // Aynı ana iki nokta koymak eğrinin ucunda dik bir çentik bırakır.
      final gun = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 10, 14, 2);
      final h = _seans(
          gun: gun, baslaDk: 600, bitDk: 840, deger: (i) => 1000000 + i * 500.0);
      const canli = 1025000.0;

      final ortak = DailySummary.dayValues(h, now, canli, seansGunu: gun);
      expect(ortak.length, h.length, reason: 'taze uçta nokta EKLENMEZ');
      expect(ortak.last, canli);
    });

    test('GEÇMİŞ seans (hafta sonu): canlı uç EKLENMEZ', () {
      // Kapanmış Cuma seansının ucuna Pazar'ın canlı değerini yazmak
      // olmamış bir hareketi grafiğe basar.
      final cuma = DateTime(2026, 9, 11);
      final pazar = DateTime(2026, 9, 13, 11, 0);
      final h = _seans(
          gun: cuma,
          baslaDk: 600,
          bitDk: 1090,
          deger: (i) => 1000000 + i * 300.0);
      const canli = 1030000.0;

      final ortak = DailySummary.dayValues(h, pazar, canli, seansGunu: cuma);
      expect(ortak, _uygulamaDegerleri(h, cuma, pazar, canli));
      expect(ortak.length, h.length, reason: 'geçmiş seansa uç eklenmez');
      expect(ortak.last, 1029400.0, reason: 'uç kapanışta kalmalı');
    });

    test('seansGunu VERİLMEZSE seriden türetilir — bugün varsayılmaz', () {
      // Güvenli varsayılan: `seansGunu` taşınmadığı bir yolda da hafta sonu
      // davranışı doğru kalmalı.
      final cuma = DateTime(2026, 9, 11);
      final pazar = DateTime(2026, 9, 13, 11, 0);
      final h = _seans(
          gun: cuma,
          baslaDk: 600,
          bitDk: 1090,
          deger: (i) => 1000000 + i * 300.0);

      expect(DailySummary.cizilenGunFromSeries(h), cuma);
      expect(
        DailySummary.dayValues(h, pazar, 1030000.0),
        DailySummary.dayValues(h, pazar, 1030000.0, seansGunu: cuma),
      );
    });

    test('gelecek ve sıfır slotlar iki tarafta da aynı elenir', () {
      final gun = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 10, 12, 0);
      final h = <int, double>{};
      for (var dk = 0; dk < 1440; dk += 5) {
        h[gun.add(Duration(minutes: dk)).millisecondsSinceEpoch] =
            dk < 600 ? 0.0 : 1000000 + (dk - 600) * 10.0;
      }
      const canli = 1006200.0;

      expect(
        DailySummary.dayValues(h, now, canli, seansGunu: gun),
        _uygulamaDegerleri(h, gun, now, canli),
      );
    });
  });

  group('nakit akışı penceresi — ÇİZİLEN gün', () {
    test('seanstan SONRA girilen alım o seansın hareketini bozmaz', () {
      // Ayrışmanın ikinci sebebi. Cuma'nın gerçek hareketi ₺9.800; Pazar
      // girilen ₺1.000'lik alım eskiden bundan düşülüyordu (₺8.800).
      final cuma = DateTime(2026, 9, 11);
      final pazar = DateTime(2026, 9, 13, 11, 0);
      final series = _seans(
          gun: cuma,
          baslaDk: 600,
          bitDk: 1090,
          deger: (i) => 1000000 + i * 100.0);

      final state = _state([
        _lot(id: 'b1', qty: 100, cur: 10000, added: DateTime(2026, 1, 1)),
        // Pazar günü (seans KAPANDIKTAN sonra) girilen alım.
        _lot(id: 'b2', qty: 10, cur: 10000, added: DateTime(2026, 9, 13, 9)),
      ]);

      final s = DailySummary.from(
        state: state,
        series: series,
        now: pazar,
        seansGunu: cuma,
      );

      // Seri 1.000.000 → 1.009.800; Cuma günü akış YOK.
      expect(s.changeTRY, closeTo(9800.0, 0.01),
          reason: 'Pazar alımı Cuma seansından düşülemez');
      expect(s.changePct, closeTo(0.98, 0.01));
    });

    test('ÇİZİLEN gün içinde girilen alım akıştan düşülür', () {
      // Arındırmanın kendisi ÇALIŞMAYA devam etmeli — yalnızca penceresi
      // değişti. Bu test, düzeltmenin arındırmayı kapatmadığını kilitler.
      final gun = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 10, 18, 30);
      final series = _seans(
          gun: gun,
          baslaDk: 600,
          bitDk: 1090,
          deger: (i) => 1000000 + i * 100.0);

      // Canlı toplam serinin ucuyla TUTARLI olmalı (110 lot × ₺9.180 =
      // ₺1.009.800), aksi halde canlı uç kuralı ölçülen şeyi değiştirir ve
      // test akışı değil, tutarsız fixture'ı ölçer.
      final state = _state([
        _lot(id: 'b1', qty: 100, cur: 9180, added: DateTime(2026, 1, 1)),
        // AYNI gün içinde girilen alım: 10 × ₺100 = ₺1.000 maliyet.
        _lot(
            id: 'b2',
            qty: 10,
            cur: 9180,
            purchase: 100,
            added: DateTime(2026, 9, 10, 11)),
      ]);

      final s = DailySummary.from(
        state: state,
        series: series,
        now: now,
        seansGunu: gun,
      );

      // Ham fark ₺9.800 ama ₺1.000'i yatırılan paradır.
      expect(s.changeTRY, closeTo(8800.0, 0.01),
          reason: 'gün içi alım arındırılmaya devam etmeli');
    });

    test('inflowOnDay pencereyi açıkça uygular', () {
      final assets = [
        _lot(id: 'x', qty: 10, cur: 100, added: DateTime(2026, 9, 11, 12)),
        _lot(id: 'y', qty: 10, cur: 100, added: DateTime(2026, 9, 13, 12)),
      ];
      expect(
        DailySummary.inflowOnDay(assets, DateTime(2026, 9, 11),
            DateTime(2026, 9, 11, 23, 59, 59)),
        1000.0,
      );
      expect(
        DailySummary.inflowOnDay(assets, DateTime(2026, 9, 13),
            DateTime(2026, 9, 13, 23, 59, 59)),
        1000.0,
      );
    });
  });
}
