import 'technical_signal.dart';

class SignalAlert {
  final String assetId;
  final String assetName;
  final String assetTicker;
  final SignalType signal;
  final int buyCount;
  final int sellCount;
  final double confidence;
  final DateTime detectedAt;

  const SignalAlert({
    required this.assetId,
    required this.assetName,
    required this.assetTicker,
    required this.signal,
    required this.buyCount,
    required this.sellCount,
    required this.confidence,
    required this.detectedAt,
  });
}
