import 'asset_type.dart';

class Asset {
  final String id;
  final String userId;
  String name;
  String ticker;
  AssetType type;
  String? subCategory; // Altın: gr22, çeyrek vb. | Fon: bankFund, bist100 vb. | Hisse: bist100, other
  String unitType; // Birim: piece, gram, ounce, etc. (varsayılan: piece)
  double quantity;
  double purchasePrice;
  String currency;
  double currentPrice;
  DateTime? lastUpdated;
  final DateTime addedDate;
  String notes;
  bool isManualPrice;
  double purchaseFxRate;

  Asset({
    required this.id,
    required this.userId,
    required this.name,
    required this.ticker,
    required this.type,
    required this.quantity,
    required this.purchasePrice,
    required this.currency,
    required this.notes,
    this.subCategory,
    this.unitType = 'piece',
    this.purchaseFxRate = 1.0,
    double? currentPrice,
    this.lastUpdated,
    DateTime? addedDate,
    bool? isManualPrice,
  })  : currentPrice = currentPrice ?? purchasePrice,
        addedDate = addedDate ?? DateTime.now(),
        isManualPrice = isManualPrice ?? ticker.trim().isEmpty;

  double get totalCost => quantity * purchasePrice;
  double get totalValue => quantity * currentPrice;
  /// Maliyet TRY cinsinden — alım anındaki kur sabit tutulur (bankacılık standardı).
  double get totalCostTRY => quantity * purchasePrice * purchaseFxRate;
  double get gainLoss => totalValue - totalCost;
  double get gainLossPercentage =>
      totalCost > 0 ? (gainLoss / totalCost) * 100 : 0;

  /// Temizlenmiş ticker kodu — sadece fon ve hisse için anlamlı
  String? get displayTicker {
    if (ticker.trim().isEmpty) return null;
    final t = ticker.replaceAll('.IS', '').replaceAll('=X', '').trim();
    return t.isEmpty ? null : t;
  }

  /// Fon/Hisse için ticker gösterilmeli mi?
  bool get showTicker =>
      displayTicker != null && (type == AssetType.fon || type == AssetType.hisse);

  /// Döviz varlığı için para sembolü ($ € £ vb.)
  String? get currencySymbol =>
      type == AssetType.doviz ? currencySymbolFor(ticker, currency) : null;

  /// Miktar için kullanılacak birim etiketi (adet/lot/gr/oz/₺-$ vb.).
  /// Ekranlarda "1 lot", "2,5 gr", "$100" gibi göstermek için kullanılır.
  String get unitLabel {
    switch (type) {
      case AssetType.doviz:
        return currencySymbol ?? currency.toUpperCase();
      case AssetType.hisse:
      case AssetType.fon:
        return 'lot';
      case AssetType.altin:
      case AssetType.emtia:
        switch (unitType) {
          case 'gram':
          case 'gr':
            return 'gr';
          case 'ounce':
          case 'oz':
            return 'oz';
          case 'kilogram':
          case 'kg':
            return 'kg';
          case 'liter':
          case 'lt':
            return 'lt';
          case 'barrel':
          case 'bbl':
            return 'bbl';
          default:
            return 'adet';
        }
      case AssetType.diger:
        return 'adet';
    }
  }

  /// Birim para birimden önce mi gelmeli? (Döviz sembolleri prefix, diğerleri suffix.)
  bool get unitIsPrefix => type == AssetType.doviz;

  /// SQLite uyumlu map (partner kod payload'ı için kullanılır)
  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'name': name,
        'ticker': ticker,
        'type': type.name,
        'subCategory': subCategory,
        'unitType': unitType,
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
        userId: (m['userId'] as String?) ?? '',
        name: m['name'] as String,
        ticker: m['ticker'] as String,
        type: AssetType.fromString(m['type'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        purchasePrice: (m['purchasePrice'] as num).toDouble(),
        currency: m['currency'] as String,
        currentPrice: (m['currentPrice'] as num).toDouble(),
        subCategory: m['subCategory'] as String?,
        unitType: (m['unitType'] as String?) ?? 'piece',
        lastUpdated: m['lastUpdated'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['lastUpdated'] as int)
            : null,
        addedDate: DateTime.fromMillisecondsSinceEpoch(m['addedDate'] as int),
        notes: (m['notes'] as String?) ?? '',
        isManualPrice: (m['isManualPrice'] as int) == 1,
      );

  /// Supabase snake_case sütunlarına map
  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'ticker': ticker,
        'type': type.name,
        'sub_category': subCategory,
        'unit_type': unitType,
        'quantity': quantity,
        'purchase_price': purchasePrice,
        'currency': currency,
        'current_price': currentPrice,
        'last_updated': lastUpdated?.toUtc().toIso8601String(),
        'added_date': addedDate.toUtc().toIso8601String(),
        'notes': notes,
        'is_manual_price': isManualPrice,
        'purchase_fx_rate': purchaseFxRate,
      };

  factory Asset.fromSupabase(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        name: m['name'] as String,
        ticker: (m['ticker'] as String?) ?? '',
        type: AssetType.fromString(m['type'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        purchasePrice: (m['purchase_price'] as num).toDouble(),
        currency: m['currency'] as String,
        currentPrice: (m['current_price'] as num).toDouble(),
        subCategory: m['sub_category'] as String?,
        unitType: (m['unit_type'] as String?) ?? 'piece',
        lastUpdated: m['last_updated'] != null
            ? DateTime.parse(m['last_updated'] as String)
            : null,
        addedDate: m['added_date'] != null
            ? DateTime.parse(m['added_date'] as String)
            : DateTime.now(),
        notes: (m['notes'] as String?) ?? '',
        isManualPrice: m['is_manual_price'] as bool? ?? false,
        purchaseFxRate: (m['purchase_fx_rate'] as num?)?.toDouble() ?? 1.0,
      );
}
