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

// `CategorySignal` / `PortfolioSignalAnalysis` 2026-10-04'te kaldırıldı:
// eski prototipin istemci tarafı portföy geneli sinyal özetiydi; sinyal
// kararı sunucuya (`signal_state`) taşındıktan sonra hiçbir yer kurmuyordu.
