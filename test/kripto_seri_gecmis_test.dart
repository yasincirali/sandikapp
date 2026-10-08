import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Kripto serisi grafiklere ve günlük harekete girer (2026-10-02 müşteri
/// testi).
///
/// HistoryService'in tür listelerinde kripto yoktu: seri hiç istenmiyor,
/// varlık `currentPrice` ile düz çiziliyordu. Ondo ekranı her dönemde %0,0,
/// Bugün kartı günün hareketini kriptosuz gösteriyordu. Bu testler seri
/// çekicinin kripto sembolüyle ÇAĞRILDIĞINI ve sonucun düz OLMADIĞINI kilitler.
void main() {
  Asset kripto(String kod) => Asset(
        id: 'k-$kod',
        userId: 'u1',
        name: kod,
        ticker: 'KRIPTO:$kod',
        type: AssetType.kripto,
        quantity: 100,
        purchasePrice: 20,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 24,
        addedDate: DateTime.now().subtract(const Duration(days: 400)),
      );

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.gunIciSaat = DateTime.now;
  });

  test('dönem grafiği: kripto serisi istenir ve çizgi düz değildir', () async {
    final simdi = DateTime.now();
    final bas = DateTime(simdi.year, simdi.month, simdi.day)
        .subtract(const Duration(days: 30));
    final gunler = <(int, double)>[
      for (var g = 0; g <= 30; g++)
        (bas.add(Duration(days: g)).millisecondsSinceEpoch, 20.0 + g * 0.2),
    ];
    final istenen = <String>{};
    HistoryService.seriCekici = (sym, range, interval) async {
      istenen.add(sym);
      return sym == 'KRIPTO:AAAKR' ? gunler : const [];
    };

    final bd =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: [kripto('AAAKR')],
      from: bas,
      to: simdi,
      tier: ResolutionTier.daily,
    );

    expect(istenen, contains('KRIPTO:AAAKR'));
    final degerler = bd.total.values.toSet();
    expect(degerler.length, greaterThan(1),
        reason: 'kripto currentPrice ile düz çizilmemeli');
    expect(bd.byType.keys, contains(AssetType.kripto));
  });

  test('gün içi: kripto serisi istenir, tür dökümünde gerçek veri var',
      () async {
    final gun = DateTime.now();
    final bas = DateTime(gun.year, gun.month, gun.day);
    HistoryService.gunIciSaat = () => bas.add(const Duration(hours: 14));
    final noktalar = <(int, double)>[
      for (var m = 0; m <= 14 * 60; m += 5)
        (bas.add(Duration(minutes: m)).millisecondsSinceEpoch, 24.0 - m / 1000),
    ];
    final istenen = <String>{};
    HistoryService.seriCekici = (sym, range, interval) async {
      istenen.add(sym);
      return sym == 'KRIPTO:BBBKR' ? noktalar : const [];
    };

    final bd = await HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown([kripto('BBBKR')], 24);

    expect(istenen, contains('KRIPTO:BBBKR'));
    expect(bd.gunIciVerisiYokTurler, isNot(contains(AssetType.kripto)));
    final tur = bd.byType[AssetType.kripto] ?? const {};
    expect(tur.values.toSet().length, greaterThan(1),
        reason: 'gün içi kripto düz çizilmemeli');
  });

  test('gün içi: kripto serisi boşsa grafik boşalmaz, tür "veri yok" olur',
      () async {
    final gun = DateTime.now();
    final bas = DateTime(gun.year, gun.month, gun.day);
    HistoryService.gunIciSaat = () => bas.add(const Duration(hours: 14));
    HistoryService.seriCekici = (sym, range, interval) async => const [];

    final bd = await HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown([kripto('CCCKR')], 24);

    expect(bd.gunIciVerisiYokTurler, contains(AssetType.kripto));
  });
}
