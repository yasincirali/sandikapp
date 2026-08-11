import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// "Alım günü" dot anahtarlarının hesabı optimize edildi:
/// eskiden her spot için `assets.any((a) => yıl/ay/gün eşleşiyor mu)` şeklinde
/// iç içe tarama yapılıyordu (spot × varlık) ve bu, viewport değiştiği HER
/// karede tekrarlanıyordu. Yeni hâl varlıkların alım günlerini bir kez
/// "gün damgası" set'ine indirip spot başına O(1) lookup yapıyor.
///
/// Bu test iki algoritmanın AYNI sonucu verdiğini doğrular. Ekrandaki private
/// metodu doğrudan çağıramadığımız için her iki algoritma da burada birebir
/// yeniden üretilir — amaç mantığın denkliğini kilitlemek.
void main() {
  // ── Eski (referans) algoritma ────────────────────────────────────────────
  Set<double> legacyBuyDayKeys(
      List<List<FlSpot>> segmentSpots, List<DateTime> addedDates, DateTime start) {
    final keys = <double>{};
    for (final spots in segmentSpots) {
      for (final spot in spots) {
        final dateAtSpot =
            start.add(Duration(minutes: (spot.x * 24 * 60).round()));
        final hasAddition = addedDates.any((d) =>
            d.year == dateAtSpot.year &&
            d.month == dateAtSpot.month &&
            d.day == dateAtSpot.day);
        if (hasAddition) keys.add(spot.x);
      }
    }
    return keys;
  }

  // ── Yeni algoritma ───────────────────────────────────────────────────────
  Set<double> fastBuyDayKeys(
      List<List<FlSpot>> segmentSpots, List<DateTime> addedDates, DateTime start) {
    final buyDays = <int>{};
    for (final d in addedDates) {
      buyDays.add(DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
    }
    final keys = <double>{};
    for (final spots in segmentSpots) {
      for (final spot in spots) {
        final dateAtSpot =
            start.add(Duration(minutes: (spot.x * 24 * 60).round()));
        final dayTs =
            DateTime(dateAtSpot.year, dateAtSpot.month, dateAtSpot.day)
                .millisecondsSinceEpoch;
        if (buyDays.contains(dayTs)) keys.add(spot.x);
      }
    }
    return keys;
  }

  group('alım günü dot anahtarları — eski/yeni denkliği', () {
    final start = DateTime(2026, 1, 1);

    List<FlSpot> dailySpots(int days) =>
        [for (int i = 0; i < days; i++) FlSpot(i.toDouble(), 100.0 + i)];

    test('alım yokken her iki algoritma da boş döner', () {
      final segs = [dailySpots(30)];
      expect(fastBuyDayKeys(segs, const [], start), isEmpty);
      expect(fastBuyDayKeys(segs, const [], start),
          legacyBuyDayKeys(segs, const [], start));
    });

    test('tek alım günü — aynı anahtar', () {
      final segs = [dailySpots(30)];
      final adds = [DateTime(2026, 1, 11, 14, 30)];
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
      // 1 Ocak + 10 gün = 11 Ocak → x = 10
      expect(fastBuyDayKeys(segs, adds, start), {10.0});
    });

    test('çok alımlı, çok segmentli senaryo — aynı sonuç', () {
      final segs = [dailySpots(200), dailySpots(50)];
      final adds = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2, 9),
        DateTime(2026, 2, 15, 23, 59),
        DateTime(2026, 5, 30),
        DateTime(2026, 3, 3, 12),
      ];
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
    });

    test('aynı gün birden çok alım — tek anahtar üretir', () {
      final segs = [dailySpots(30)];
      final adds = [
        DateTime(2026, 1, 5, 9),
        DateTime(2026, 1, 5, 15),
        DateTime(2026, 1, 5, 17, 45),
      ];
      final fast = fastBuyDayKeys(segs, adds, start);
      expect(fast, legacyBuyDayKeys(segs, adds, start));
      expect(fast.length, 1);
    });

    test('kesirli (saatlik) X değerlerinde de denk', () {
      // Saatlik seri: X kesirli gün (1/24 adımlarla).
      final hourly = [
        for (int i = 0; i < 24 * 7; i++) FlSpot(i / 24.0, 100.0 + i)
      ];
      final adds = [
        DateTime(2026, 1, 3, 10),
        DateTime(2026, 1, 6, 20),
      ];
      expect(fastBuyDayKeys([hourly], adds, start),
          legacyBuyDayKeys([hourly], adds, start));
    });

    test('aralık dışı alımlar hiçbir anahtar üretmez', () {
      final segs = [dailySpots(30)];
      final adds = [DateTime(2025, 6, 1), DateTime(2027, 6, 1)];
      expect(fastBuyDayKeys(segs, adds, start), isEmpty);
      expect(fastBuyDayKeys(segs, adds, start),
          legacyBuyDayKeys(segs, adds, start));
    });
  });

  // ── Nokta kaynağı filtresi ─────────────────────────────────────────────
  //
  // Regresyon: `_buyDayKeys` varlık listesini FİLTRESİZ tarıyordu — sadece
  // `addedDate` okunuyor, kaydın türüne bakılmıyordu. Sonuç: temettü
  // satırları, deleteLog mezar taşları ve yumuşak silinmiş lot'lar da nokta
  // üretiyordu. Bu kayıtlar crosshair'in "o gün işlem var mı" testinden
  // (`isActive` + `isBuy`/`isSell`) geçmediği için kullanıcı grafikte nokta
  // görüp basınca hiçbir alım/satım satırı göremiyordu.
  //
  // Ekrandaki private metodu doğrudan çağıramıyoruz; filtre koşulu burada
  // birebir yeniden üretilip kilitleniyor.
  group('nokta kaynağı filtresi — yalnızca aktif alım/satım', () {
    Asset lot({
      required String id,
      required DateTime addedDate,
      AssetKind kind = AssetKind.buy,
      DateTime? deletedAt,
    }) =>
        Asset(
          id: id,
          userId: 'u1',
          name: 'THYAO',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 120,
          addedDate: addedDate,
          kind: kind,
          deletedAt: deletedAt,
        );

    /// Ekrandaki filtre ile birebir aynı koşul.
    bool producesDot(Asset a) =>
        a.isActive && (a.isBuy || a.isSell);

    final day = DateTime(2026, 3, 10);

    test('aktif alım nokta üretir', () {
      expect(producesDot(lot(id: 'b', addedDate: day)), isTrue);
    });

    test('aktif satış nokta üretir', () {
      expect(
          producesDot(lot(id: 's', addedDate: day, kind: AssetKind.sell)),
          isTrue);
    });

    test('temettü satırı nokta ÜRETMEZ', () {
      // Temettü bir alım/satım değil ve miktara hiç dokunmaz.
      expect(
          producesDot(lot(id: 'd', addedDate: day, kind: AssetKind.dividend)),
          isFalse);
    });

    test('deleteLog mezar taşı nokta ÜRETMEZ', () {
      expect(
          producesDot(lot(id: 'x', addedDate: day, kind: AssetKind.deleteLog)),
          isFalse);
    });

    test('yumuşak silinmiş alım nokta ÜRETMEZ', () {
      // `isDeleteLog` tek başına bunu yakalamıyordu — eski hatanın tam yeri.
      expect(
        producesDot(lot(
          id: 'sd',
          addedDate: day,
          deletedAt: DateTime(2026, 4, 1),
        )),
        isFalse,
      );
    });

    test('yumuşak silinmiş satış nokta ÜRETMEZ', () {
      expect(
        producesDot(lot(
          id: 'sds',
          addedDate: day,
          kind: AssetKind.sell,
          deletedAt: DateTime(2026, 4, 1),
        )),
        isFalse,
      );
    });

    test('karışık ledger — yalnızca aktif alım/satım günleri kalır', () {
      final ledger = [
        lot(id: 'b1', addedDate: DateTime(2026, 1, 5)),
        lot(id: 'd1', addedDate: DateTime(2026, 1, 6), kind: AssetKind.dividend),
        lot(id: 's1', addedDate: DateTime(2026, 1, 7), kind: AssetKind.sell),
        lot(
            id: 'x1',
            addedDate: DateTime(2026, 1, 8),
            kind: AssetKind.deleteLog),
        lot(
            id: 'sd1',
            addedDate: DateTime(2026, 1, 9),
            deletedAt: DateTime(2026, 2, 1)),
      ];

      final days = ledger
          .where(producesDot)
          .map((a) => DateTime(
                  a.addedDate.year, a.addedDate.month, a.addedDate.day)
              .millisecondsSinceEpoch)
          .toSet();

      expect(days, {
        DateTime(2026, 1, 5).millisecondsSinceEpoch,
        DateTime(2026, 1, 7).millisecondsSinceEpoch,
      });
    });

    test('cache anahtarı isActive değişimini yakalar', () {
      // `id` tek başına anahtar olarak kullanıldığında yumuşak silme
      // anahtarı değiştirmiyordu → silinen lot'un noktası cache'ten
      // dönmeye devam ediyordu.
      String keyOf(List<Asset> assets) => assets
          .map((a) =>
              '${a.id}:${a.isActive ? 1 : 0}${a.isBuy ? 'b' : a.isSell ? 's' : 'x'}')
          .join(',');

      final before = [lot(id: 'b1', addedDate: day)];
      final after = [
        lot(id: 'b1', addedDate: day, deletedAt: DateTime(2026, 4, 1)),
      ];

      expect(keyOf(before), isNot(keyOf(after)));
    });
  });
}
