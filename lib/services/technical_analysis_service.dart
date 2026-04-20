import 'dart:math';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/technical_signal.dart';

class TechnicalAnalysisService {
  /// Calculates RSI (Relative Strength Index)
  static double calculateRSI(List<double> prices, {int period = 14}) {
    if (prices.length < period + 1) return 50.0;

    double gains = 0;
    double losses = 0;

    for (int i = 1; i <= period; i++) {
      final change = prices[prices.length - i] - prices[prices.length - i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses += -change;
      }
    }

    final avgGain = gains / period;
    final avgLoss = losses / period;

    if (avgLoss == 0) return 100.0;

    final rs = avgGain / avgLoss;
    final rsi = 100 - (100 / (1 + rs));

    return rsi;
  }

  /// Calculates MACD (Moving Average Convergence Divergence)
  static Map<String, double> calculateMACD(List<double> prices) {
    if (prices.length < 26) {
      return {'macd': 0, 'signal': 0, 'histogram': 0};
    }

    final ema12 = _calculateEMA(prices, 12);
    final ema26 = _calculateEMA(prices, 26);
    final macdLine = ema12 - ema26;

    final macdValues = <double>[];
    for (int i = 0; i < prices.length - 25; i++) {
      final subList = prices.sublist(i, i + 26);
      final e12 = _calculateEMA(subList, 12);
      final e26 = _calculateEMA(subList, 26);
      macdValues.add(e12 - e26);
    }

    final signalLine = _calculateEMA(macdValues, 9);
    final histogram = macdLine - signalLine;

    return {
      'macd': macdLine,
      'signal': signalLine,
      'histogram': histogram,
    };
  }

  /// Calculates Bollinger Bands
  static Map<String, double> calculateBollingerBands(List<double> prices,
      {int period = 20, double stdDevMultiplier = 2.0}) {
    if (prices.length < period) {
      return {'upper': 0, 'middle': 0, 'lower': 0};
    }

    final recentPrices = prices.sublist(prices.length - period);
    final sma = recentPrices.reduce((a, b) => a + b) / period;

    final variance =
        recentPrices.map((p) => pow(p - sma, 2)).reduce((a, b) => a + b) /
            period;
    final stdDev = sqrt(variance);

    return {
      'upper': sma + (stdDev * stdDevMultiplier),
      'middle': sma,
      'lower': sma - (stdDev * stdDevMultiplier),
    };
  }

  /// Calculates Stochastic Oscillator
  static Map<String, double> calculateStochastic(List<double> prices,
      {int period = 14}) {
    if (prices.length < period) {
      return {'k': 50.0, 'd': 50.0};
    }

    final recentPrices = prices.sublist(prices.length - period);
    final lowest = recentPrices.reduce((a, b) => a < b ? a : b);
    final highest = recentPrices.reduce((a, b) => a > b ? a : b);
    final currentPrice = prices.last;

    final range = highest - lowest;
    final k = range == 0 ? 50.0 : ((currentPrice - lowest) / range) * 100;

    return {
      'k': k,
      'd': k, // Simplified - normally would smooth with SMA
    };
  }

  /// Calculates SMA (Simple Moving Average)
  static double calculateSMA(List<double> prices, {int period = 20}) {
    if (prices.length < period) return prices.isEmpty ? 0 : prices.last;
    final recent = prices.sublist(prices.length - period);
    return recent.reduce((a, b) => a + b) / period;
  }

  /// Calculates EMA (Exponential Moving Average)
  static double _calculateEMA(List<double> prices, int period) {
    if (prices.isEmpty) return 0;
    if (prices.length == 1) return prices[0];

    final sma =
        prices.sublist(0, min(period, prices.length)).reduce((a, b) => a + b) /
            min(period, prices.length);
    final k = 2.0 / (period + 1);

    double ema = sma;
    final startIdx = min(period, prices.length);

    for (int i = startIdx; i < prices.length; i++) {
      ema = prices[i] * k + ema * (1 - k);
    }

    return ema;
  }

  /// Generates technical signals for an asset
  static TechnicalIndicator _generateSignalFromIndicator(
    String name,
    double value,
    SignalType signal,
    String description,
  ) {
    return TechnicalIndicator(
      name: name,
      value: value,
      signal: signal,
      description: description,
    );
  }

  /// Analyzes a single asset and generates signals
  static List<TechnicalIndicator> analyzeAsset(Asset asset) {
    // Simulate price history (in real app, fetch from API)
    final priceHistory = _generateSimulatedPriceHistory(asset);

    final indicators = <TechnicalIndicator>[];

    // 1. RSI Analysis
    final rsi = calculateRSI(priceHistory);
    final rsiSignal = rsi > 70
        ? SignalType.sell
        : rsi < 30
            ? SignalType.buy
            : SignalType.neutral;
    indicators.add(_generateSignalFromIndicator(
      'RSI',
      rsi,
      rsiSignal,
      'RSI: ${rsi.toStringAsFixed(2)} ${rsiSignal == SignalType.buy ? '(Sobrevenda)' : rsiSignal == SignalType.sell ? '(Sobrecompra)' : '(Neutral)'}',
    ));

    // 2. MACD Analysis
    final macd = calculateMACD(priceHistory);
    final macdSignal = macd['histogram']! > 0
        ? SignalType.buy
        : macd['histogram']! < 0
            ? SignalType.sell
            : SignalType.neutral;
    indicators.add(_generateSignalFromIndicator(
      'MACD',
      macd['histogram'] ?? 0,
      macdSignal,
      'MACD: ${(macd['histogram'] ?? 0).toStringAsFixed(4)}',
    ));

    // 3. Bollinger Bands Analysis
    final bb = calculateBollingerBands(priceHistory);
    final currentPrice = priceHistory.last;
    final bbSignal = currentPrice < bb['lower']!
        ? SignalType.buy
        : currentPrice > bb['upper']!
            ? SignalType.sell
            : SignalType.neutral;
    indicators.add(_generateSignalFromIndicator(
      'Bollinger Bands',
      currentPrice,
      bbSignal,
      'Preço: ${currentPrice.toStringAsFixed(2)}, Banda Inf: ${(bb['lower'] ?? 0).toStringAsFixed(2)}, Banda Sup: ${(bb['upper'] ?? 0).toStringAsFixed(2)}',
    ));

    // 4. SMA/EMA Analysis
    final sma20 = calculateSMA(priceHistory, period: 20);
    final ema50 = _calculateEMA(priceHistory, 50);
    final smaSignal = currentPrice > sma20 && sma20 > ema50
        ? SignalType.buy
        : currentPrice < sma20 && sma20 < ema50
            ? SignalType.sell
            : SignalType.neutral;
    indicators.add(_generateSignalFromIndicator(
      'SMA/EMA',
      currentPrice - sma20,
      smaSignal,
      'SMA20: ${sma20.toStringAsFixed(2)}, EMA50: ${ema50.toStringAsFixed(2)}',
    ));

    // 5. Stochastic Oscillator Analysis
    final stoch = calculateStochastic(priceHistory);
    final stochSignal = stoch['k']! > 80
        ? SignalType.sell
        : stoch['k']! < 20
            ? SignalType.buy
            : SignalType.neutral;
    indicators.add(_generateSignalFromIndicator(
      'Estocástico',
      stoch['k'] ?? 50,
      stochSignal,
      'K: ${(stoch['k'] ?? 50).toStringAsFixed(2)}',
    ));

    return indicators;
  }

  /// Generates simulated price history for testing
  static List<double> _generateSimulatedPriceHistory(Asset asset,
      {int days = 100}) {
    final prices = <double>[];
    double currentPrice = asset.currentPrice > 0 ? asset.currentPrice : 100.0;

    for (int i = 0; i < days; i++) {
      prices.add(currentPrice);
      // Random walk
      final change = (Random().nextDouble() - 0.5) * (currentPrice * 0.02);
      currentPrice =
          (currentPrice + change).clamp(currentPrice * 0.5, currentPrice * 1.5);
    }

    return prices;
  }

  /// Generates portfolio signal analysis
  static PortfolioSignalAnalysis generatePortfolioSignals(
    List<Asset> assets,
    double totalPortfolioValue,
    Map<String, Function(double value, String currency)> converters,
  ) {
    // Group assets by type
    final groupedByType = <AssetType, List<Asset>>{};
    for (final asset in assets) {
      groupedByType.putIfAbsent(asset.type, () => []).add(asset);
    }

    final categorySignals = <CategorySignal>[];
    int totalBuySignals = 0;
    int totalSellSignals = 0;

    for (final entry in groupedByType.entries) {
      final type = entry.key;
      final categoryAssets = entry.value;

      // Calculate total value for category
      double categoryTotal = 0;
      for (final asset in categoryAssets) {
        categoryTotal +=
            asset.totalValue; // Assuming already in TRY or can be converted
      }

      // Generate signals for each asset and aggregate
      final allIndicators = <TechnicalIndicator>[];
      for (final asset in categoryAssets) {
        allIndicators.addAll(analyzeAsset(asset));
      }

      // Calculate overall signal
      final buyCount =
          allIndicators.where((i) => i.signal == SignalType.buy).length;
      final sellCount =
          allIndicators.where((i) => i.signal == SignalType.sell).length;
      final neutralCount =
          allIndicators.where((i) => i.signal == SignalType.neutral).length;

      final overallSignal = buyCount > sellCount && buyCount > neutralCount
          ? SignalType.buy
          : sellCount > buyCount && sellCount > neutralCount
              ? SignalType.sell
              : SignalType.neutral;

      final confidence = (max(buyCount, max(sellCount, neutralCount)) /
              (allIndicators.isEmpty ? 1 : allIndicators.length))
          .clamp(0.0, 1.0);

      categorySignals.add(CategorySignal(
        category: type.label,
        indicators: allIndicators,
        overallSignal: overallSignal,
        confidence: confidence,
        totalAssets: categoryTotal,
        indicatorCount: allIndicators.length,
      ));

      totalBuySignals += buyCount;
      totalSellSignals += sellCount;
    }

    final portfolioSignal = totalBuySignals > totalSellSignals
        ? SignalType.buy
        : totalSellSignals > totalBuySignals
            ? SignalType.sell
            : SignalType.neutral;

    return PortfolioSignalAnalysis(
      categorySignals: categorySignals,
      totalPortfolioValue: totalPortfolioValue,
      portfolioSignal: portfolioSignal,
    );
  }
}
