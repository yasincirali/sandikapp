import 'dart:math';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/technical_signal.dart';

class TechnicalAnalysisService {
  // ── EMA ──────────────────────────────────────────────────────────────────

  static double _ema(List<double> prices, int period) {
    if (prices.isEmpty) return 0;
    final len = min(prices.length, period * 3);
    final sub = prices.sublist(prices.length - len);
    double ema = sub.sublist(0, min(period, sub.length)).reduce((a, b) => a + b) /
        min(period, sub.length);
    final k = 2.0 / (period + 1);
    for (int i = min(period, sub.length); i < sub.length; i++) {
      ema = sub[i] * k + ema * (1 - k);
    }
    return ema;
  }

  // ── 1. RSI ────────────────────────────────────────────────────────────────

  static TechnicalIndicator rsi(List<double> prices, AssetType type) {
    final period = type == AssetType.doviz ? 9 : 14;
    if (prices.length < period + 1) {
      return TechnicalIndicator(
          name: 'RSI', value: 50, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    double gains = 0, losses = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      final d = prices[i] - prices[i - 1];
      if (d > 0) gains += d; else losses -= d;
    }
    final avgG = gains / period;
    final avgL = losses / period;
    final value = avgL == 0 ? 100.0 : 100 - (100 / (1 + avgG / avgL));

    // Varlık türüne göre eşikler
    final overbought = type == AssetType.hisse ? 70.0 : 72.0;
    final oversold = type == AssetType.hisse ? 30.0 : 28.0;

    final signal = value < oversold
        ? SignalType.buy
        : value > overbought
            ? SignalType.sell
            : SignalType.neutral;

    final desc = value < oversold
        ? 'Aşırı satım bölgesi (${value.toStringAsFixed(1)})'
        : value > overbought
            ? 'Aşırı alım bölgesi (${value.toStringAsFixed(1)})'
            : 'Nötr bölge (${value.toStringAsFixed(1)})';

    return TechnicalIndicator(name: 'RSI ($period)', value: value, signal: signal, description: desc);
  }

  // ── 2. MACD ───────────────────────────────────────────────────────────────

  static TechnicalIndicator macd(List<double> prices, AssetType type) {
    // Fon için daha uzun periyot
    final fast = type == AssetType.fon ? 8 : 12;
    final slow = type == AssetType.fon ? 21 : 26;
    final sig = 9;

    if (prices.length < slow + sig) {
      return TechnicalIndicator(
          name: 'MACD', value: 0, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final macdLine = _ema(prices, fast) - _ema(prices, slow);

    // Signal line: EMA of recent MACD values
    final macdSeries = <double>[];
    for (int i = slow; i <= prices.length; i++) {
      final sub = prices.sublist(0, i);
      macdSeries.add(_ema(sub, fast) - _ema(sub, slow));
    }
    final signalLine = _ema(macdSeries, sig);
    final histogram = macdLine - signalLine;

    final signal = histogram > 0 ? SignalType.buy
        : histogram < 0 ? SignalType.sell
        : SignalType.neutral;

    final desc = histogram > 0
        ? 'MACD çizgisi sinyal üzerinde (+${histogram.toStringAsFixed(2)})'
        : histogram < 0
            ? 'MACD çizgisi sinyal altında (${histogram.toStringAsFixed(2)})'
            : 'Kesişim noktasında';

    return TechnicalIndicator(name: 'MACD', value: histogram, signal: signal, description: desc);
  }

  // ── 3. Bollinger Bantları ─────────────────────────────────────────────────

  static TechnicalIndicator bollingerBands(List<double> prices, AssetType type) {
    final period = type == AssetType.altin ? 14 : 20;
    final mult = type == AssetType.doviz ? 1.5 : 2.0;

    if (prices.length < period) {
      return TechnicalIndicator(
          name: 'Bollinger', value: 50, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    final variance = recent.map((p) => pow(p - sma, 2)).reduce((a, b) => a + b) / period;
    final stdDev = sqrt(variance);
    final upper = sma + stdDev * mult;
    final lower = sma - stdDev * mult;
    final current = prices.last;

    // %B değeri: 0=alt bant, 1=üst bant
    final pctB = (upper - lower) > 0 ? (current - lower) / (upper - lower) : 0.5;

    final signal = current < lower ? SignalType.buy
        : current > upper ? SignalType.sell
        : SignalType.neutral;

    final desc = current < lower
        ? 'Alt bantın altında — potansiyel dönüş'
        : current > upper
            ? 'Üst bantın üzerinde — potansiyel düzeltme'
            : '%B: ${(pctB * 100).toStringAsFixed(0)} (bant içi)';

    return TechnicalIndicator(name: 'Bollinger', value: pctB * 100, signal: signal, description: desc);
  }

  // ── 4. Hareketli Ortalama (SMA/EMA Kesişimi) ─────────────────────────────

  static TechnicalIndicator movingAverage(List<double> prices, AssetType type) {
    // Varlık türüne göre periyot seçimi
    final int shortP, longP;
    if (type == AssetType.hisse) { shortP = 20; longP = 50; }
    else if (type == AssetType.fon) { shortP = 10; longP = 30; }
    else if (type == AssetType.altin) { shortP = 14; longP = 40; }
    else if (type == AssetType.doviz) { shortP = 7; longP = 21; }
    else { shortP = 20; longP = 50; }

    if (prices.length < longP) {
      return TechnicalIndicator(
          name: 'Ort. Kesişim', value: 0, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final shortEma = _ema(prices, shortP);
    final longEma = _ema(prices, longP);
    final current = prices.last;
    final diff = ((shortEma - longEma) / longEma * 100);

    final signal = shortEma > longEma && current > shortEma ? SignalType.buy
        : shortEma < longEma && current < shortEma ? SignalType.sell
        : SignalType.neutral;

    final desc = shortEma > longEma
        ? 'EMA$shortP > EMA$longP — yükseliş trendi'
        : shortEma < longEma
            ? 'EMA$shortP < EMA$longP — düşüş trendi'
            : 'Ortalamalarda kesişim bölgesi';

    return TechnicalIndicator(name: 'EMA Kesişim', value: diff, signal: signal, description: desc);
  }

  // ── 5. Stokastik Osilatör ─────────────────────────────────────────────────

  static TechnicalIndicator stochastic(List<double> prices, AssetType type) {
    final period = type == AssetType.doviz ? 9 : 14;
    final overbought = 80.0;
    final oversold = 20.0;

    if (prices.length < period) {
      return TechnicalIndicator(
          name: 'Stokastik', value: 50, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final lowest = recent.reduce((a, b) => a < b ? a : b);
    final highest = recent.reduce((a, b) => a > b ? a : b);
    final current = prices.last;
    final range = highest - lowest;
    final k = range == 0 ? 50.0 : ((current - lowest) / range) * 100;

    final signal = k < oversold ? SignalType.buy
        : k > overbought ? SignalType.sell
        : SignalType.neutral;

    final desc = k < oversold
        ? 'Aşırı satım (%K: ${k.toStringAsFixed(1)})'
        : k > overbought
            ? 'Aşırı alım (%K: ${k.toStringAsFixed(1)})'
            : 'Nötr bölge (%K: ${k.toStringAsFixed(1)})';

    return TechnicalIndicator(name: 'Stokastik', value: k, signal: signal, description: desc);
  }

  // ── Ana analiz fonksiyonu ─────────────────────────────────────────────────

  /// [priceHistory]: gerçek fiyat geçmişi (eski→yeni sıralı).
  /// Boşsa varlığın mevcut fiyatı üzerinden simülasyon yapılır.
  static List<TechnicalIndicator> analyze(Asset asset, List<double> priceHistory) {
    final prices = priceHistory.isNotEmpty
        ? priceHistory
        : _simulate(asset);

    return [
      rsi(prices, asset.type),
      macd(prices, asset.type),
      bollingerBands(prices, asset.type),
      movingAverage(prices, asset.type),
      stochastic(prices, asset.type),
    ];
  }

  /// Gerçek veri olmadığında kullanılan simülasyon.
  /// Seed olarak ticker + günün tarihi kullanılır — her gün farklı ama
  /// aynı gün içinde tutarlı sinyal üretilir.
  static List<double> _simulate(Asset asset, {int days = 120}) {
    final today = DateTime.now();
    // Günlük değişen seed: aynı günde aynı sonuç, her gün farklı sinyal
    final seed = asset.ticker.hashCode.abs() ^
        (today.year * 10000 + today.month * 100 + today.day);
    final rng = Random(seed);

    final price = asset.currentPrice > 0 ? asset.currentPrice : 100.0;

    final vol = switch (asset.type) {
      AssetType.hisse => 0.022,
      AssetType.fon   => 0.010,
      AssetType.altin => 0.013,
      AssetType.doviz => 0.007,
      _               => 0.018,
    };

    // Rassal yön belirle: %40 AL trendi, %30 SAT trendi, %30 yatay
    final dirSeed = rng.nextDouble();
    final double drift;
    if (dirSeed < 0.40) {
      drift = 0.003; // AL trendi: hafif yukarı
    } else if (dirSeed < 0.70) {
      drift = -0.003; // SAT trendi: hafif aşağı
    } else {
      drift = 0.0; // Yatay
    }

    // Geriye dönük fiyat serisi üret
    final prices = <double>[];
    // Başlangıç fiyatını mevcut fiyattan hesapla (trend tersine)
    double p = price * pow(1 - drift, days).toDouble();
    for (int i = 0; i < days; i++) {
      prices.add(p);
      final noise = (rng.nextDouble() - 0.5) * vol;
      p = (p * (1 + drift + noise)).clamp(price * 0.3, price * 3.0);
    }

    // Son nokta tam olarak mevcut fiyat olsun
    if (prices.isNotEmpty && prices.last != 0) {
      final factor = price / prices.last;
      return prices.map((v) => v * factor).toList();
    }
    return prices;
  }

  /// Genel sinyal özetini hesaplar
  static ({SignalType signal, int buyCount, int sellCount, double confidence})
      summarize(List<TechnicalIndicator> indicators) {
    final buy = indicators.where((i) => i.signal == SignalType.buy).length;
    final sell = indicators.where((i) => i.signal == SignalType.sell).length;
    final total = indicators.length;

    final signal = buy >= 3 ? SignalType.buy
        : sell >= 3 ? SignalType.sell
        : SignalType.neutral;

    final confidence = total > 0
        ? max(buy, sell) / total
        : 0.0;

    return (signal: signal, buyCount: buy, sellCount: sell, confidence: confidence);
  }
}
