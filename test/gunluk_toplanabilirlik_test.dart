import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// **Değişmez:** Birlikte'nin günlük kâr/zararı, Ben + her ortağın günlük
/// kâr/zararının TOPLAMIDIR (kullanıcı kuralı 2026-09-22: "ortakların
/// günlük kâr zarar toplamı birlikteki tutarı vermeli ancak orası doğru
/// çalışmıyor").
///
/// ## Neden kırılıyordu
/// `DailySummary` serinin ucunu CANLI TOPLAMA sabitler — yazılan rakamla
/// eğrinin bittiği yer aynı olsun diye. Gün başı (`open`) ise serinin
/// kendi ölçeğinde kalır. İki taraf farklı kurallardan gelirse aradaki
/// fark SAHTE HAREKET olarak kâr/zarara yazılır.
///
/// Ayrışma tam olarak buradaydı:
///   * `ownerScopedTotalValue` (kartın ve `liveTotalTRY`'nin kaynağı)
///     kapanmış pozisyonu 0'a kırpar — `aggregatePositions` içinde
///     `totalQty <= 0 → return`.
///   * `HistoryService`'in `liveTotal`'ı (serinin ucu) her lot'u doğrudan
///     topluyordu, yani aldığından çok satmış görünen bir pozisyonun
///     NEGATİF kalıntısını da taşıyordu.
///
/// Ölçüldü (düzeltmeden önce): ben +₺50, ortak −₺20 iken Birlikte −₺450
/// gösteriyordu; doğrusu +₺30. Tekil sekmeler doğru göründüğü için arıza
/// yalnızca Birlikte'de fark ediliyordu.
///
/// Düzeltme: canlı toplam SAHİP + POZİSYON kovalarında birikir ve kapanmış
/// kova toplama girmez. Sahip anahtarı şart — `positionKey` sahip taşımaz,
/// iki sahibin aynı hissesi tek kovaya düşse birinin satışı diğerinin
/// lotunu düşerdi (bkz. [aggregatePositionsByOwner]).
Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  DateTime? addedDate,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: currentPrice,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      kind: kind,
    );

void main() {
  final now = DateTime(2026, 9, 22, 15, 0);
  final gun = DateTime(2026, 9, 22);

  Map<int, double> seri(double acilis, double son) => {
        DateTime(2026, 9, 22, 10).millisecondsSinceEpoch: acilis,
        now.millisecondsSinceEpoch: son,
      };

  group('canlı toplam sahiplik sınırına saygılı', () {
    // Ortak aldığından ÇOK satmış görünüyor (kısmi görünürlük / düzeltme
    // kaydı): 4 alım, 6 satış. Sahip bazında pozisyon KAPALI → 0.
    final ben = [
      _lot(
          userId: 'ben',
          ticker: 'THYAO',
          qty: 10,
          buyPrice: 100,
          currentPrice: 120),
    ];
    final ortak = [
      _lot(
          userId: 'ortak',
          ticker: 'THYAO',
          qty: 4,
          buyPrice: 100,
          currentPrice: 120),
      _lot(
          userId: 'ortak',
          ticker: 'THYAO',
          qty: 6,
          buyPrice: 110,
          currentPrice: 120,
          kind: AssetKind.sell),
    ];
    final birlesik = [...ben, ...ortak];

    test('kapanmış pozisyon negatif kalıntı taşımaz', () {
      expect(ownerScopedTotalValue(lotlarSahibeGore(ortak)), 0.0,
          reason: 'aldığından çok satmış pozisyon 0\'a kırpılır');
    });

    test('toplam sahipler arasında toplanabilir', () {
      final tBen = ownerScopedTotalValue(lotlarSahibeGore(ben));
      final tOrtak = ownerScopedTotalValue(lotlarSahibeGore(ortak));
      final tBirlikte = ownerScopedTotalValue(lotlarSahibeGore(birlesik));
      expect(tBen + tOrtak, tBirlikte);
      expect(tBirlikte, 1200.0);
    });

    test('iki sahibin aynı hissesi tek havuzda toplanmaz', () {
      // positionKey sahip taşımaz; sahip anahtarı olmadan ortağın 6
      // satışı benim 10 lotumu düşerdi.
      final benim = ben.first;
      final ortagin = ortak.first;
      expect(positionKey(benim), positionKey(ortagin),
          reason: 'ön koşul: anahtar gerçekten sahipsiz');
      expect(ownerScopedTotalValue(lotlarSahibeGore(birlesik)), 1200.0,
          reason: 'ortağın satışı benim lotumu düşmemeli');
    });
  });

  group('günlük kâr/zarar toplanabilir', () {
    final ben = [
      _lot(
          userId: 'ben',
          ticker: 'THYAO',
          qty: 10,
          buyPrice: 100,
          currentPrice: 120),
    ];
    final ortak = [
      _lot(
          userId: 'ortak',
          ticker: 'ASELS',
          qty: 5,
          buyPrice: 100,
          currentPrice: 140),
    ];
    final birlesik = [...ben, ...ortak];
    final state = PortfolioState(assets: birlesik);

    test('Birlikte değişimi = Ben + ortak değişimleri', () {
      // Her kapsamın serisi kendi ölçeğinde; uçlar canlı toplama oturur.
      final b = DailySummary.from(
          state: state,
          series: seri(1150, 1200),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ben);
      final o = DailySummary.from(
          state: state,
          series: seri(650, 700),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ortak);
      final birlikte = DailySummary.from(
          state: state,
          series: seri(1800, 1900),
          now: now,
          seansGunu: gun,
          kapsamLotlari: birlesik);

      expect(b.changeTRY, closeTo(50.0, 0.001));
      expect(o.changeTRY, closeTo(50.0, 0.001));
      expect(birlikte.changeTRY,
          closeTo((b.changeTRY ?? 0) + (o.changeTRY ?? 0), 0.001),
          reason: 'Birlikte parçaların toplamı olmalı');
    });

    test('toplam da toplanabilir', () {
      final b = DailySummary.from(
          state: state,
          series: seri(1150, 1200),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ben);
      final o = DailySummary.from(
          state: state,
          series: seri(650, 700),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ortak);
      final birlikte = DailySummary.from(
          state: state,
          series: seri(1800, 1900),
          now: now,
          seansGunu: gun,
          kapsamLotlari: birlesik);

      expect(b.totalTRY + o.totalTRY, closeTo(birlikte.totalTRY, 0.001));
      expect(birlikte.totalTRY, 1900.0);
    });

    test('nakit akışı da toplanabilir: her alım yalnızca sahibine', () {
      // Ortak bugün ₺700'lük alım yaptı.
      final ortakBugun = [
        ...ortak,
        _lot(
          userId: 'ortak',
          ticker: 'XU100',
          qty: 10,
          buyPrice: 70,
          currentPrice: 70,
          addedDate: DateTime(2026, 9, 22, 11),
        ),
      ];
      final defter = [...ben, ...ortakBugun];
      final st = PortfolioState(assets: defter);

      final b = DailySummary.from(
          state: st,
          series: seri(1150, 1200),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ben);
      final o = DailySummary.from(
          state: st,
          series: seri(650, 1400),
          now: now,
          seansGunu: gun,
          kapsamLotlari: ortakBugun);
      final birlikte = DailySummary.from(
          state: st,
          series: seri(1800, 2600),
          now: now,
          seansGunu: gun,
          kapsamLotlari: defter);

      // Ortağın ₺700 alımı BENİM hareketime karışmamalı.
      expect(b.changeTRY, closeTo(50.0, 0.001));
      expect(birlikte.changeTRY,
          closeTo((b.changeTRY ?? 0) + (o.changeTRY ?? 0), 0.001),
          reason: 'inflow sahibine yazılınca toplam yine tutar');
    });
  });

  test('kaynak: canlı toplam sahip+pozisyon kovalarında birikir', () {
    final src = File('lib/services/history_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    // İki yol da (gün içi + günlük) aynı kuralı uygulamalı.
    expect(
        RegExp(r"final kova = '\$\{a\.userId\}\|").allMatches(src).length +
            RegExp(r"'\$\{a\.userId\}\|\$\{positionKey\(a\)\}'")
                .allMatches(src)
                .length,
        greaterThanOrEqualTo(2),
        reason: 'gün içi ve günlük canlı toplam sahip anahtarı kullanmalı');
    expect(src.contains('if ((kovaMiktar[kova] ?? 0) <= 0.0000001) return;'),
        isTrue,
        reason: 'kapanmış pozisyon canlı toplama girmemeli');
  });
}
