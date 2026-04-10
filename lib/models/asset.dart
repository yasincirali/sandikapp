import 'asset_type.dart';

class Asset {
  final String id;
  String name;
  String ticker;
  AssetType type;
  double quantity;
  double purchasePrice;
  String currency;
  double currentPrice;
  DateTime? lastUpdated;
  final DateTime addedDate;
  String notes;
  bool isManualPrice;

  Asset({
    required this.id,
    required this.name,
    required this.ticker,
    required this.type,
    required this.quantity,
    required this.purchasePrice,
    required this.currency,
    required this.notes,
    double? currentPrice,
    this.lastUpdated,
    DateTime? addedDate,
    bool? isManualPrice,
  })  : currentPrice = currentPrice ?? purchasePrice,
        addedDate = addedDate ?? DateTime.now(),
        isManualPrice = isManualPrice ?? ticker.trim().isEmpty;

  double get totalCost => quantity * purchasePrice;
  double get totalValue => quantity * currentPrice;
  double get gainLoss => totalValue - totalCost;
  double get gainLossPercentage =>
      totalCost > 0 ? (gainLoss / totalCost) * 100 : 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'ticker': ticker,
        'type': type.name,
        'quantity': quantity,
        'purchasePrice': purchasePrice,
        'currency': currency,
        'currentPrice': currentPrice,
        'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
        'addedDate': addedDate.millisecondsSinceEpoch,
        'notes': notes,
        'isManualPrice': isManualPrice ? 1 : 0,
      };

  factory Asset.fromMap(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        name: m['name'] as String,
        ticker: m['ticker'] as String,
        type: AssetType.fromString(m['type'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        purchasePrice: (m['purchasePrice'] as num).toDouble(),
        currency: m['currency'] as String,
        currentPrice: (m['currentPrice'] as num).toDouble(),
        lastUpdated: m['lastUpdated'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['lastUpdated'] as int)
            : null,
        addedDate:
            DateTime.fromMillisecondsSinceEpoch(m['addedDate'] as int),
        notes: (m['notes'] as String?) ?? '',
        isManualPrice: (m['isManualPrice'] as int) == 1,
      );
}
