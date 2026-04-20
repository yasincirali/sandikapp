enum SignalType { buy, sell, neutral }

class TechnicalIndicator {
  final String name;
  final double value;
  final SignalType signal;
  final String description;

  TechnicalIndicator({
    required this.name,
    required this.value,
    required this.signal,
    required this.description,
  });
}

class CategorySignal {
  final String category;
  final List<TechnicalIndicator> indicators;
  final SignalType overallSignal;
  final double confidence; // 0-1
  final double totalAssets;
  final int indicatorCount;

  CategorySignal({
    required this.category,
    required this.indicators,
    required this.overallSignal,
    required this.confidence,
    required this.totalAssets,
    required this.indicatorCount,
  });

  int get buySignals =>
      indicators.where((i) => i.signal == SignalType.buy).length;
  int get sellSignals =>
      indicators.where((i) => i.signal == SignalType.sell).length;
  int get neutralSignals =>
      indicators.where((i) => i.signal == SignalType.neutral).length;
}

class PortfolioSignalAnalysis {
  final List<CategorySignal> categorySignals;
  final double totalPortfolioValue;
  final SignalType portfolioSignal;

  PortfolioSignalAnalysis({
    required this.categorySignals,
    required this.totalPortfolioValue,
    required this.portfolioSignal,
  });

  int get totalBuySignals =>
      categorySignals.fold(0, (sum, cs) => sum + cs.buySignals);
  int get totalSellSignals =>
      categorySignals.fold(0, (sum, cs) => sum + cs.sellSignals);
  int get totalNeutralSignals =>
      categorySignals.fold(0, (sum, cs) => sum + cs.neutralSignals);
}
