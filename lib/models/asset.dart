import 'asset_type.dart';

/// İşlem türü — audit trail için.
/// - buy: alım (default, geriye dönük uyumluluk)
/// - sell: satım (refAssetId ile ilgili buy lot'una bağlı; net miktarda düşer)
/// - delete_log: silinen bir buy lot'unun mezar taşı (portföyden çıkar, işlem
///   defterinde "SILDI" olarak kalır)
/// - dividend: nakit temettü. **Miktarı DEĞİŞTİRMEZ** — eline geçen parayı
///   `dividendAmount` alanında taşır. Getiriye eklenir, pozisyona eklenmez.
enum AssetKind {
  buy,
  sell,
  deleteLog,
  dividend;

  String get dbValue {
    switch (this) {
      case AssetKind.buy:
        return 'buy';
      case AssetKind.sell:
        return 'sell';
      case AssetKind.deleteLog:
        return 'delete_log';
      case AssetKind.dividend:
        return 'dividend';
    }
  }

  static AssetKind fromDb(String? v) {
    switch (v) {
      case 'sell':
        return AssetKind.sell;
      case 'delete_log':
        return AssetKind.deleteLog;
      case 'dividend':
        return AssetKind.dividend;
      case 'buy':
      case null:
      default:
        return AssetKind.buy;
    }
  }
}

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

  /// İşlem türü — buy (default) / sell / delete_log
  final AssetKind kind;

  /// Sell veya delete_log satırlarının hangi buy lot'una referans verdiği.
  /// null → bağımsız kayıt (buy için normal)
  final String? refAssetId;

  /// Sell işleminde gerçekleşen birim satış fiyatı (raporlama/kar-zarar için).
  final double? sellPrice;

  /// İşlem komisyonu + masrafı — varlığın PARA BİRİMİNDE (purchasePrice ile
  /// aynı birim), işlem başına toplam (birim başına değil).
  ///
  /// Alımda maliyeti artırır. Komisyon hesaba katılmazsa kâr olduğundan
  /// yüksek görünür. Varsayılan 0 → kullanıcı girmedikçe eski davranış.
  double commission;

  /// Nakit temettü tutarı — yalnızca `kind == dividend` satırlarında anlamlı.
  /// Varlığın para biriminde, ELE GEÇEN NET tutar (stopaj sonrası).
  ///
  /// Temettü satırı miktarı değiştirmez; bu tutar realize edilmiş getiri
  /// olarak kâr/zarara eklenir.
  double dividendAmount;

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
    this.kind = AssetKind.buy,
    this.refAssetId,
    this.sellPrice,
    this.commission = 0,
    this.dividendAmount = 0,
  })  : currentPrice = currentPrice ?? purchasePrice,
        addedDate = addedDate ?? DateTime.now(),
        isManualPrice = isManualPrice ?? ticker.trim().isEmpty;

  bool get isBuy => kind == AssetKind.buy;
  bool get isSell => kind == AssetKind.sell;
  bool get isDeleteLog => kind == AssetKind.deleteLog;
  bool get isDividend => kind == AssetKind.dividend;

  /// Portföy net pozisyonuna katkı gösteren tek satırlar buy'lar. Sell'ler
  /// (negatif) ve delete_log'lar aggregator'da özel işlenir.
  ///
  /// DİKKAT: `!isBuy` ile "sell demektir" varsayımı YAPMA — temettü satırları
  /// da buy değildir ama miktara hiç dokunmaz. Miktar hesabında bu getter'ı
  /// veya açık `isSell` kontrolü kullan.
  bool get affectsPosition => kind == AssetKind.buy;

  /// Miktar hesabına hiç girmeyen satırlar (nakit hareketi / mezar taşı).
  bool get isQuantityNeutral =>
      kind == AssetKind.dividend || kind == AssetKind.deleteLog;

  /// TRY cinsinden temettü — alım kuruyla değil, TEMETTÜ ANININ kuruyla
  /// çevrilir. `purchaseFxRate` temettü satırında ödeme günü kurunu taşır.
  double get dividendTRY => dividendAmount * purchaseFxRate;

  /// Satıştan ELE GEÇEN tutar (TRY) — nakit akışı hesapları için.
  ///
  /// [totalCostTRY] bu iş için YANLIŞ araçtır: o, lot'un alım maliyetidir.
  /// Kâr/zararla satılmış bir pozisyonda cepten çıkan/cebe giren para
  /// maliyet değil, satış fiyatıdır. Dönem getirisini para giriş-çıkışından
  /// arındırırken bu fark doğrudan sonuca yansır.
  ///
  /// [sellPrice] yalnızca sell satırlarında ve migration sonrası kayıtlarda
  /// dolu; boşsa maliyete düşülür (eski davranış) — yaklaşık ama sıfırdan
  /// iyi. Komisyon satışta ele geçeni AZALTIR, bu yüzden çıkarılır.
  double get sellProceedsTRY {
    final unit = sellPrice ?? purchasePrice;
    return (quantity * unit - commission) * purchaseFxRate;
  }

  /// Toplam maliyet — komisyon DAHİL (gerçekte cebinden çıkan para).
  double get totalCost => quantity * purchasePrice + commission;
  double get totalValue => quantity * currentPrice;

  /// Maliyet TRY cinsinden — alım anındaki kur sabit tutulur (bankacılık
  /// standardı). Komisyon da aynı kurdan çevrilir: işlemle aynı anda ödendi.
  double get totalCostTRY =>
      (quantity * purchasePrice + commission) * purchaseFxRate;
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

  /// Nakit temettü kaydedilebilir mi?
  ///
  /// Yalnızca **hisse** senedi temettü dağıtır. Altın/döviz/emtia fiziksel ya
  /// da parasal varlıktır, mevduatın getirisi faizdir ve kendi alanlarında
  /// izlenir. Fonlar da dağıtım yapabilir ama TEFAS'ta bu fiyata yansıdığı
  /// için ayrıca girilmesi çift sayıma yol açar.
  bool get supportsDividend => type == AssetType.hisse;

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
      case AssetType.mevduat:
        return '₺';
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
        'kind': kind.dbValue,
        'refAssetId': refAssetId,
        'sellPrice': sellPrice,
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
        kind: AssetKind.fromDb(m['kind'] as String?),
        refAssetId: m['refAssetId'] as String?,
        sellPrice: (m['sellPrice'] as num?)?.toDouble(),
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
        'kind': kind.dbValue,
        'ref_asset_id': refAssetId,
        'sell_price': sellPrice,
        'commission': commission,
        'dividend_amount': dividendAmount,
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
        kind: AssetKind.fromDb(m['kind'] as String?),
        refAssetId: m['ref_asset_id'] as String?,
        sellPrice: (m['sell_price'] as num?)?.toDouble(),
        // Migration 0019 öncesi kayıtlarda sütun yok → 0.
        commission: (m['commission'] as num?)?.toDouble() ?? 0,
        // Migration 0020 öncesi kayıtlarda sütun yok → 0.
        dividendAmount: (m['dividend_amount'] as num?)?.toDouble() ?? 0,
      );
}
