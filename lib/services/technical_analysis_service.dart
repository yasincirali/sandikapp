import 'dart:math';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/technical_signal.dart';
import '../utils/tr_format.dart';

/// Gösterge kimlikleri — per-category seçim ve premium gating için stable key.
class IndicatorId {
  static const rsi = 'rsi';
  static const macd = 'macd';
  static const bollinger = 'bollinger';
  static const ema = 'ema';
  static const stochastic = 'stochastic';

  // Premium göstergeler
  static const adx = 'adx';
  static const williamsR = 'williams_r';
  static const cci = 'cci';

  static const all = <String>[
    rsi,
    macd,
    bollinger,
    ema,
    stochastic,
    adx,
    williamsR,
    cci,
  ];

  static const premium = <String>{adx, williamsR, cci};

  static Set<String> recommendedFor(AssetType type) => switch (type) {
        AssetType.hisse  => {rsi, macd, bollinger, stochastic, adx},
        AssetType.fon    => {ema, rsi, macd},
        AssetType.altin  => {rsi, bollinger, ema, cci},
        AssetType.doviz  => {ema, rsi, williamsR, stochastic},
        AssetType.emtia  => {rsi, macd, bollinger, cci, adx},
        _                => {},
      };

  static String labelOf(String id) {
    switch (id) {
      case rsi:
        return 'RSI (Göreceli Güç Endeksi)';
      case macd:
        return 'MACD (Hareketli Ortalama Yakınsaması)';
      case bollinger:
        return 'Bollinger Bantları';
      case ema:
        return 'EMA Kesişim';
      case stochastic:
        return 'Stokastik Osilatör';
      case adx:
        return 'ADX (Yön Endeksi)';
      case williamsR:
        return 'Williams %R';
      case cci:
        return 'CCI (Commodity Channel Index)';
    }
    return id;
  }
}

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
    final label = 'RSI ($period)';
    if (prices.length < period + 1) {
      return TechnicalIndicator(
          name: label, value: 50, signal: SignalType.neutral,
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

    final overbought = type == AssetType.hisse ? 70.0 : 72.0;
    final oversold = type == AssetType.hisse ? 30.0 : 28.0;

    final signal = value < oversold
        ? SignalType.buy
        : value > overbought
            ? SignalType.sell
            : SignalType.neutral;

    final desc = value < oversold
        ? 'Aşırı satım bölgesi (${fmtNum(value, digits: 1)})'
        : value > overbought
            ? 'Aşırı alım bölgesi (${fmtNum(value, digits: 1)})'
            : 'Nötr bölge (${fmtNum(value, digits: 1)})';

    return TechnicalIndicator(name: label, value: value, signal: signal, description: desc);
  }

  // ── 2. MACD ───────────────────────────────────────────────────────────────

  static TechnicalIndicator macd(List<double> prices, AssetType type) {
    final fast = type == AssetType.fon ? 8 : 12;
    final slow = type == AssetType.fon ? 21 : 26;
    final sig = 9;
    final label = 'MACD ($fast,$slow,$sig)';

    if (prices.length < slow + sig) {
      return TechnicalIndicator(
          name: label, value: 0, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final macdLine = _ema(prices, fast) - _ema(prices, slow);

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
        ? 'MACD çizgisi sinyal üzerinde (+${fmtNum(histogram, digits: 2)})'
        : histogram < 0
            ? 'MACD çizgisi sinyal altında (${fmtNum(histogram, digits: 2)})'
            : 'Kesişim noktasında';

    return TechnicalIndicator(name: label, value: histogram, signal: signal, description: desc);
  }

  // ── 3. Bollinger Bantları ─────────────────────────────────────────────────

  static TechnicalIndicator bollingerBands(List<double> prices, AssetType type) {
    final period = type == AssetType.altin ? 14 : 20;
    final mult = type == AssetType.doviz ? 1.5 : 2.0;
    final label = 'Bollinger ($period, ${mult}σ)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label, value: 50, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    final variance = recent.map((p) => pow(p - sma, 2)).reduce((a, b) => a + b) / period;
    final stdDev = sqrt(variance);
    final upper = sma + stdDev * mult;
    final lower = sma - stdDev * mult;
    final current = prices.last;

    final pctB = (upper - lower) > 0 ? (current - lower) / (upper - lower) : 0.5;

    final signal = current < lower ? SignalType.buy
        : current > upper ? SignalType.sell
        : SignalType.neutral;

    final desc = current < lower
        ? 'Alt bantın altında — potansiyel dönüş'
        : current > upper
            ? 'Üst bantın üzerinde — potansiyel düzeltme'
            : '%B: ${fmtNum(pctB * 100, digits: 0)} (bant içi)';

    return TechnicalIndicator(name: label, value: pctB * 100, signal: signal, description: desc);
  }

  // ── 4. Hareketli Ortalama (EMA Kesişimi) ─────────────────────────────────

  static TechnicalIndicator movingAverage(List<double> prices, AssetType type) {
    final int shortP, longP;
    if (type == AssetType.hisse) { shortP = 20; longP = 50; }
    else if (type == AssetType.fon) { shortP = 10; longP = 30; }
    else if (type == AssetType.altin) { shortP = 14; longP = 40; }
    else if (type == AssetType.doviz) { shortP = 7; longP = 21; }
    else { shortP = 20; longP = 50; }
    final label = 'EMA Kesişim ($shortP/$longP)';

    if (prices.length < longP) {
      return TechnicalIndicator(
          name: label, value: 0, signal: SignalType.neutral,
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

    return TechnicalIndicator(name: label, value: diff, signal: signal, description: desc);
  }

  // ── 5. Stokastik Osilatör ─────────────────────────────────────────────────

  static TechnicalIndicator stochastic(List<double> prices, AssetType type) {
    final period = type == AssetType.doviz ? 9 : 14;
    final overbought = 80.0;
    final oversold = 20.0;
    final label = 'Stokastik %K ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label, value: 50, signal: SignalType.neutral,
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
        ? 'Aşırı satım (%K: ${fmtNum(k, digits: 1)})'
        : k > overbought
            ? 'Aşırı alım (%K: ${fmtNum(k, digits: 1)})'
            : 'Nötr bölge (%K: ${fmtNum(k, digits: 1)})';

    return TechnicalIndicator(name: label, value: k, signal: signal, description: desc);
  }

  // ── 6. ADX — trend gücü (PREMIUM) ─────────────────────────────────────────
  //
  // Basitleştirilmiş ADX: |ΔP| ortalamasının fiyat range'ine oranı. Klasik ADX
  // için OHLC gerekli; bizde sadece close var — proxy hesap kullanılır.

  static TechnicalIndicator adx(List<double> prices, AssetType type) {
    final period = 14;
    final label = 'ADX ($period)';

    if (prices.length < period + 1) {
      return TechnicalIndicator(
          name: label, value: 0, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period - 1);
    double sumUp = 0, sumDown = 0, sumRange = 0;
    for (int i = 1; i < recent.length; i++) {
      final d = recent[i] - recent[i - 1];
      if (d > 0) sumUp += d; else sumDown -= d;
      sumRange += d.abs();
    }
    if (sumRange == 0) {
      return TechnicalIndicator(
          name: label, value: 0, signal: SignalType.neutral,
          description: 'Yatay (trend yok)');
    }
    final directional = ((sumUp - sumDown).abs() / sumRange) * 100;

    final signal = directional > 25
        ? (sumUp > sumDown ? SignalType.buy : SignalType.sell)
        : SignalType.neutral;

    final desc = directional > 40
        ? 'Güçlü trend (${fmtNum(directional, digits: 0)})'
        : directional > 25
            ? 'Trend başlıyor (${fmtNum(directional, digits: 0)})'
            : 'Zayıf trend (${fmtNum(directional, digits: 0)})';

    return TechnicalIndicator(name: label, value: directional, signal: signal, description: desc);
  }

  // ── 7. Williams %R — aşırı alım/satım osilatörü (PREMIUM) ─────────────────

  static TechnicalIndicator williamsR(List<double> prices, AssetType type) {
    final period = 14;
    final label = 'Williams %R ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label, value: -50, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final highest = recent.reduce((a, b) => a > b ? a : b);
    final lowest = recent.reduce((a, b) => a < b ? a : b);
    final current = prices.last;
    final range = highest - lowest;
    final wr = range == 0 ? -50.0 : ((highest - current) / range) * -100;

    final signal = wr < -80 ? SignalType.buy
        : wr > -20 ? SignalType.sell
        : SignalType.neutral;

    final desc = wr < -80
        ? 'Aşırı satım (${fmtNum(wr, digits: 0)})'
        : wr > -20
            ? 'Aşırı alım (${fmtNum(wr, digits: 0)})'
            : 'Nötr bölge (${fmtNum(wr, digits: 0)})';

    return TechnicalIndicator(name: label, value: wr, signal: signal, description: desc);
  }

  // ── 8. CCI (Commodity Channel Index) (PREMIUM) ────────────────────────────

  static TechnicalIndicator cci(List<double> prices, AssetType type) {
    final period = 20;
    final label = 'CCI ($period)';

    if (prices.length < period) {
      return TechnicalIndicator(
          name: label, value: 0, signal: SignalType.neutral,
          description: 'Yetersiz veri');
    }

    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    final meanDev = recent.map((p) => (p - sma).abs()).reduce((a, b) => a + b) / period;
    final current = prices.last;
    final value = meanDev == 0 ? 0.0 : (current - sma) / (0.015 * meanDev);

    final signal = value < -100 ? SignalType.buy
        : value > 100 ? SignalType.sell
        : SignalType.neutral;

    final desc = value < -100
        ? 'Aşırı satım (${fmtNum(value, digits: 0)})'
        : value > 100
            ? 'Aşırı alım (${fmtNum(value, digits: 0)})'
            : 'Nötr bölge (${fmtNum(value, digits: 0)})';

    return TechnicalIndicator(name: label, value: value, signal: signal, description: desc);
  }

  // ── Ana analiz fonksiyonu ─────────────────────────────────────────────────

  /// [priceHistory]: gerçek fiyat geçmişi (eski→yeni sıralı). Boşsa simülasyon.
  /// [enabledIds]: null ise varsayılan set (temel 5). Aksi halde bu set'teki
  /// göstergeler hesaplanır. Premium olmayanlar için premium ID'ler
  /// [premiumUnlocked=false] ise atlanır.
  static List<TechnicalIndicator> analyze(
    Asset asset,
    List<double> priceHistory, {
    Set<String>? enabledIds,
    bool premiumUnlocked = false,
  }) {
    final prices = priceHistory.isNotEmpty ? priceHistory : _simulate(asset);
    final ids = enabledIds ?? defaultEnabledFor(asset.type);

    final result = <TechnicalIndicator>[];
    for (final id in ids) {
      if (IndicatorId.premium.contains(id) && !premiumUnlocked) continue;
      final ind = _computeById(id, prices, asset.type);
      if (ind != null) result.add(ind);
    }
    return result;
  }

  static TechnicalIndicator? _computeById(
      String id, List<double> prices, AssetType type) {
    switch (id) {
      case IndicatorId.rsi:
        return rsi(prices, type);
      case IndicatorId.macd:
        return macd(prices, type);
      case IndicatorId.bollinger:
        return bollingerBands(prices, type);
      case IndicatorId.ema:
        return movingAverage(prices, type);
      case IndicatorId.stochastic:
        return stochastic(prices, type);
      case IndicatorId.adx:
        return adx(prices, type);
      case IndicatorId.williamsR:
        return williamsR(prices, type);
      case IndicatorId.cci:
        return cci(prices, type);
    }
    return null;
  }

  /// Her varlık türü için varsayılan aktif göstergeler.
  static Set<String> defaultEnabledFor(AssetType type) {
    return <String>{
      IndicatorId.rsi,
      IndicatorId.macd,
      IndicatorId.bollinger,
      IndicatorId.ema,
      IndicatorId.stochastic,
    };
  }

  // ── Simülasyon (fiyat geçmişi yoksa) ──────────────────────────────────────

  static List<double> _simulate(Asset asset, {int days = 120}) {
    final today = DateTime.now();
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

    final dirSeed = rng.nextDouble();
    final double drift;
    if (dirSeed < 0.40) {
      drift = 0.003;
    } else if (dirSeed < 0.70) {
      drift = -0.003;
    } else {
      drift = 0.0;
    }

    final prices = <double>[];
    double p = price * pow(1 - drift, days).toDouble();
    for (int i = 0; i < days; i++) {
      prices.add(p);
      final noise = (rng.nextDouble() - 0.5) * vol;
      p = (p * (1 + drift + noise)).clamp(price * 0.3, price * 3.0);
    }

    if (prices.isNotEmpty && prices.last != 0) {
      final factor = price / prices.last;
      return prices.map((v) => v * factor).toList();
    }
    return prices;
  }

  /// Genel sinyal özeti. Toplam gösterge sayısı değişken olduğundan eşik
  /// oransal hesaplanır (%60+ buy → BUY).
  static ({SignalType signal, int buyCount, int sellCount, double confidence})
      summarize(List<TechnicalIndicator> indicators) {
    final buy = indicators.where((i) => i.signal == SignalType.buy).length;
    final sell = indicators.where((i) => i.signal == SignalType.sell).length;
    final total = indicators.length;

    if (total == 0) {
      return (signal: SignalType.neutral, buyCount: 0, sellCount: 0, confidence: 0.0);
    }
    final buyRatio = buy / total;
    final sellRatio = sell / total;

    final signal = buyRatio >= 0.6 ? SignalType.buy
        : sellRatio >= 0.6 ? SignalType.sell
        : SignalType.neutral;

    final confidence = max(buyRatio, sellRatio);

    return (signal: signal, buyCount: buy, sellCount: sell, confidence: confidence);
  }
}
