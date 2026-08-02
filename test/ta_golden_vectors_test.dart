import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// Dart teknik analiz çıktısından "altın standart" vektörler üretir.
///
/// Bu dosya çift görev yapar:
///  1. Normal test: göstergeler beklenen sinyal tiplerini üretiyor mu.
///  2. Vektör üretimi: `GOLDEN=1 flutter test test/ta_golden_vectors_test.dart`
///     çalıştırıldığında TypeScript portunun karşılaştıracağı JSON'u yazar.
///
/// Neden gerekli: TA motoru artık iki dilde. Formüller sapmaya başlarsa
/// kullanıcı uygulamada bir sinyal, push'ta başka sinyal görür — sessiz ve
/// güven kırıcı bir hata. Bu vektörler sapmayı yakalar.
void main() {
  /// Deterministik test serileri — rastgelelik yok, iki dilde de aynı girdi.
  Map<String, List<double>> buildSeries() {
    final series = <String, List<double>>{};

    // 1) Düzgün yükseliş
    series['uptrend'] = [for (int i = 0; i < 120; i++) 100 + i * 0.8];

    // 2) Düzgün düşüş
    series['downtrend'] = [for (int i = 0; i < 120; i++) 200 - i * 0.9];

    // 3) Yatay (sabit)
    series['flat'] = [for (int i = 0; i < 120; i++) 150.0];

    // 4) Sinüs dalgası — osilatörleri gerçekçi biçimde salındırır
    series['sine'] = [
      for (int i = 0; i < 120; i++) 100 + 20 * sin(i * pi / 12),
    ];

    // 5) Ani çöküş (son 10 gün sert düşüş) — aşırı satım bölgesi
    series['crash'] = [
      for (int i = 0; i < 110; i++) 100 + i * 0.2,
      for (int i = 0; i < 10; i++) 122 - i * 6.0,
    ];

    // 6) Ani sıçrama — aşırı alım bölgesi
    series['spike'] = [
      for (int i = 0; i < 110; i++) 100 - i * 0.1,
      for (int i = 0; i < 10; i++) 89 + i * 5.0,
    ];

    // 7) Kısa seri — "yetersiz veri" dallarını tetikler
    series['short'] = [100, 101, 102, 103, 105];

    return series;
  }

  const types = <AssetType>[
    AssetType.hisse,
    AssetType.fon,
    AssetType.altin,
    AssetType.doviz,
    AssetType.emtia,
  ];

  const indicatorIds = <String>[
    IndicatorId.rsi,
    IndicatorId.macd,
    IndicatorId.bollinger,
    IndicatorId.ema,
    IndicatorId.stochastic,
    IndicatorId.adx,
    IndicatorId.williamsR,
    IndicatorId.cci,
  ];

  TechnicalIndicator? compute(String id, List<double> p, AssetType t) {
    switch (id) {
      case IndicatorId.rsi:
        return TechnicalAnalysisService.rsi(p, t);
      case IndicatorId.macd:
        return TechnicalAnalysisService.macd(p, t);
      case IndicatorId.bollinger:
        return TechnicalAnalysisService.bollingerBands(p, t);
      case IndicatorId.ema:
        return TechnicalAnalysisService.movingAverage(p, t);
      case IndicatorId.stochastic:
        return TechnicalAnalysisService.stochastic(p, t);
      case IndicatorId.adx:
        return TechnicalAnalysisService.adx(p, t);
      case IndicatorId.williamsR:
        return TechnicalAnalysisService.williamsR(p, t);
      case IndicatorId.cci:
        return TechnicalAnalysisService.cci(p, t);
    }
    return null;
  }

  test('altın standart vektörleri üret (GOLDEN=1 ile dosyaya yazar)', () {
    final series = buildSeries();
    final cases = <Map<String, dynamic>>[];

    for (final entry in series.entries) {
      for (final type in types) {
        final indicators = <Map<String, dynamic>>[];
        for (final id in indicatorIds) {
          final ind = compute(id, entry.value, type);
          if (ind == null) continue;
          indicators.add({
            'id': id,
            'name': ind.name,
            // Kayan nokta karşılaştırması için 6 haneye yuvarla — iki dilin
            // son bit farkları testi kırmasın.
            'value': double.parse(ind.value.toStringAsFixed(6)),
            'signal': ind.signal.name,
            'description': ind.description,
          });
        }

        final all = indicators
            .map((m) => TechnicalIndicator(
                  name: m['name'] as String,
                  value: m['value'] as double,
                  signal: SignalType.values
                      .firstWhere((s) => s.name == m['signal']),
                  description: m['description'] as String,
                ))
            .toList();
        final summary = TechnicalAnalysisService.summarize(all);

        cases.add({
          'series': entry.key,
          'type': type.name,
          'prices': entry.value
              .map((v) => double.parse(v.toStringAsFixed(6)))
              .toList(),
          'indicators': indicators,
          'summary': {
            'signal': summary.signal.name,
            'buyCount': summary.buyCount,
            'sellCount': summary.sellCount,
            'confidence':
                double.parse(summary.confidence.toStringAsFixed(6)),
          },
        });
      }
    }

    expect(cases, isNotEmpty);

    if (Platform.environment['GOLDEN'] == '1') {
      // NOT: `supabase/functions/**` altına konulmaz — orada duran her dosya
      // edge function bundle'ına dahil edilir (117 KB'lık vektör dosyası
      // ve testler production'a gitmemeli).
      final file = File('supabase/tests/ta_golden_vectors.json');
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({'cases': cases}));
      // ignore: avoid_print
      print('Altın standart yazıldı: ${file.path} (${cases.length} vaka)');
    }
  });

  test('confidence her zaman 0-100 aralığında', () {
    final series = buildSeries();
    for (final entry in series.entries) {
      for (final type in types) {
        final inds = TechnicalAnalysisService.analyze(
          _fakeAsset(type),
          entry.value,
          enabledIds: indicatorIds.toSet(),
          premiumUnlocked: true,
        );
        final s = TechnicalAnalysisService.summarize(inds);
        expect(s.confidence, inRange(0, 100),
            reason: '${entry.key}/${type.name} confidence aralık dışı');
      }
    }
  });

  test('yükseliş serisinde EMA kesişimi AL, düşüşte SAT verir', () {
    final up = [for (int i = 0; i < 120; i++) 100 + i * 0.8];
    final down = [for (int i = 0; i < 120; i++) 200 - i * 0.9];

    expect(TechnicalAnalysisService.movingAverage(up, AssetType.hisse).signal,
        SignalType.buy);
    expect(TechnicalAnalysisService.movingAverage(down, AssetType.hisse).signal,
        SignalType.sell);
  });
}

Matcher inRange(num lo, num hi) => predicate<num>(
    (v) => v >= lo && v <= hi, 'değer $lo..$hi aralığında');

/// `analyze` bir Asset ister ama fiyat geçmişi dışarıdan verildiğinde
/// yalnızca `type` alanını kullanır.
Asset _fakeAsset(AssetType type) => Asset(
      id: 'test',
      userId: 'test',
      name: 'Test',
      ticker: 'TEST',
      type: type,
      quantity: 1,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );
