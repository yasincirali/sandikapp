import 'asset_type.dart';
import 'technical_signal.dart';

/// Bell sheet'te ve DB'de kullanılan sinyal bildirimi.
/// [id] Supabase row id; local-only alertler için null olabilir.
class SignalAlert {
  final String? id;
  final String assetId;
  final String assetName;
  final String assetTicker;
  final AssetType assetType;
  final SignalType signal;
  final int buyCount;
  final int sellCount;
  final double confidence;
  final DateTime detectedAt;
  final DateTime? dismissedAt;

  const SignalAlert({
    this.id,
    required this.assetId,
    required this.assetName,
    required this.assetTicker,
    required this.assetType,
    required this.signal,
    required this.buyCount,
    required this.sellCount,
    required this.confidence,
    required this.detectedAt,
    this.dismissedAt,
  });

  SignalAlert copyWith({
    String? id,
    DateTime? dismissedAt,
    bool clearDismissed = false,
  }) =>
      SignalAlert(
        id: id ?? this.id,
        assetId: assetId,
        assetName: assetName,
        assetTicker: assetTicker,
        assetType: assetType,
        signal: signal,
        buyCount: buyCount,
        sellCount: sellCount,
        confidence: confidence,
        detectedAt: detectedAt,
        dismissedAt: clearDismissed ? null : (dismissedAt ?? this.dismissedAt),
      );

  bool get isDismissed => dismissedAt != null;

  factory SignalAlert.fromMap(Map<String, dynamic> m) {
    return SignalAlert(
      id: m['id'] as String?,
      assetId: m['asset_id'] as String,
      assetName: m['asset_name'] as String,
      assetTicker: (m['asset_ticker'] as String?) ?? '',
      assetType: AssetType.fromString(m['asset_type'] as String? ?? 'diger'),
      signal: _signalFromDb(m['signal'] as String),
      buyCount: (m['buy_count'] as num?)?.toInt() ?? 0,
      sellCount: (m['sell_count'] as num?)?.toInt() ?? 0,
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
      detectedAt: DateTime.parse(m['sent_at'] as String),
      dismissedAt: m['dismissed_at'] != null
          ? DateTime.parse(m['dismissed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap(String userId) => {
        'user_id': userId,
        'asset_id': assetId,
        'asset_name': assetName,
        'asset_ticker': assetTicker,
        'asset_type': assetType.name,
        'signal': _signalToDb(signal),
        'buy_count': buyCount,
        'sell_count': sellCount,
        'confidence': confidence,
      };
}

SignalType _signalFromDb(String s) {
  switch (s) {
    case 'buy':
      return SignalType.buy;
    case 'sell':
      return SignalType.sell;
    default:
      return SignalType.neutral;
  }
}

String _signalToDb(SignalType s) {
  switch (s) {
    case SignalType.buy:
      return 'buy';
    case SignalType.sell:
      return 'sell';
    case SignalType.neutral:
      return 'neutral';
  }
}
