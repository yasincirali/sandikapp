import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/services/en_cok_oynayan.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// Bugün kartı (düzen H) "en çok oynayan" — Özet › GÜNLÜK'ün en iyi / en
/// zayıf kuralıyla AYNI seçim (`PeriodSummaryService.enIyiEnZayif`).

final _gun = DateTime(2026, 10, 3);
final _now = DateTime(2026, 10, 3, 15);
int _ms(int saat) => DateTime(2026, 10, 3, saat).millisecondsSinceEpoch;

Asset _lot(String ticker, {DateTime? alis}) => Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: alis ?? DateTime(2026, 3, 14),
    );

PortfolioHistoryBreakdown _bd(Map<String, Map<int, double>> byPosition) =>
    PortfolioHistoryBreakdown(
      total: const {},
      byType: const {},
      byPosition: byPosition,
      positionType: {for (final k in byPosition.keys) k: AssetType.hisse},
      seansGunu: _gun,
    );

void main() {
  final thy = _lot('THYAO.IS');
  final asl = _lot('ASELS.IS');
  final grn = _lot('GARAN.IS');
  final kThy = positionKey(thy);
  final kAsl = positionKey(asl);
  final kGrn = positionKey(grn);

  test('mutlak yüzdesi en büyük olan seçilir (düşüş de olabilir)', () {
    final bd = _bd({
      kThy: {_ms(10): 1000, _ms(15): 1032}, // +%3,2
      kAsl: {_ms(10): 2000, _ms(15): 1900}, // −%5
      kGrn: {_ms(10): 500, _ms(15): 505}, // +%1
    });
    final o = enCokOynayanBul(bd, lotlar: [thy, asl, grn], now: _now)!;
    expect(o.positionKey, kAsl);
    expect(o.degisimPct, closeTo(-5, 1e-9));
    expect(o.degisimTRY, closeTo(-100, 1e-9));
    expect(o.artida, isFalse);
  });

  test('Özet GÜNLÜK ile aynı varlığı ve yüzdeyi verir', () {
    final bd = _bd({
      kThy: {_ms(10): 1000, _ms(15): 1032},
      kAsl: {_ms(10): 2000, _ms(15): 1990},
    });
    final p = PeriodSummaryService.pencere(SummaryPeriod.gunluk, _now,
        seansGunu: _gun);
    final ozet = PeriodSummaryService.enIyiEnZayif(
      byPosition: bd.byPosition,
      fromMs: p.start.millisecondsSinceEpoch,
      toMs: p.end.millisecondsSinceEpoch,
      akisliPozisyonlar: const {},
      etiket: (k) => k,
    );
    final o = enCokOynayanBul(bd, lotlar: [thy, asl], now: _now)!;
    final adaylar = [ozet.enIyi, ozet.enZayif].whereType<Object>().toList();
    expect(adaylar, isNotEmpty);
    final enBuyuk = [ozet.enIyi, ozet.enZayif]
        .where((e) => e != null)
        .reduce((a, b) => a!.changePct.abs() >= b!.changePct.abs() ? a : b)!;
    expect(o.positionKey, enBuyuk.name);
    expect(o.degisimPct, closeTo(enBuyuk.changePct, 1e-9));
  });

  test('bugün alım yapılan pozisyon elenir (miktar zıplaması oynama değil)',
      () {
    final bugunAlinan = _lot('ASELS.IS', alis: DateTime(2026, 10, 3, 11));
    final bd = _bd({
      kThy: {_ms(10): 1000, _ms(15): 1010},
      kAsl: {_ms(10): 2000, _ms(15): 4000}, // alım: değer iki katı
    });
    final o = enCokOynayanBul(bd, lotlar: [thy, asl, bugunAlinan], now: _now)!;
    expect(o.positionKey, kThy);
  });

  test('düz günde ya da tek noktalı seride kutu yok', () {
    expect(
        enCokOynayanBul(_bd({kThy: {_ms(10): 1000, _ms(15): 1000}}),
            lotlar: [thy], now: _now),
        isNull);
    expect(
        enCokOynayanBul(_bd({kThy: {_ms(10): 1000}}),
            lotlar: [thy], now: _now),
        isNull);
    expect(enCokOynayanBul(_bd(const {}), lotlar: [thy], now: _now), isNull);
  });
}
