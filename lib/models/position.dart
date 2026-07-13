import 'asset.dart';
import 'asset_type.dart';

/// Aggregated portfolio position — birden çok Asset (lot) tek pozisyon olarak.
///
/// UI seviyesinde birleştirilir; DB'de her Asset ayrı satır kalır (işlem
/// geçmişi için). Aynı ticker/type/currency/subCategory'e sahip lot'lar
/// bir Position'a düşer.
class Position {
  Position({
    required this.key,
    required this.representative,
    required this.lots,
    required this.totalQuantity,
    required this.weightedPurchasePrice,
    required this.weightedFxRate,
    required this.latestAddedDate,
  });

  /// Aggregation match anahtarı (debug/analytics için)
  final String key;

  /// Görsel meta için "temsilci" lot — en yeni alım.
  final Asset representative;

  /// Bu pozisyona giren tüm lot'lar (addedDate DESC)
  final List<Asset> lots;

  final double totalQuantity;
  final double weightedPurchasePrice;
  final double weightedFxRate;
  final DateTime latestAddedDate;

  bool get isSingle => lots.length == 1;

  /// İlk buy lot'un tarihi — grafik "sahip olma dönemi"nin başlangıcı için.
  DateTime get firstBuyDate {
    final buys = lots.where((l) => l.isBuy);
    if (buys.isEmpty) return latestAddedDate;
    return buys
        .map((l) => l.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Aggregated toplam maliyet (alım para biriminde)
  double get totalCost => totalQuantity * weightedPurchasePrice;

  /// Aggregated toplam maliyet TRY (alım anındaki kur ile)
  double get totalCostTRY => totalCost * weightedFxRate;

  /// Aggregated toplam değer (güncel piyasa fiyatı × miktar)
  double get totalValue => totalQuantity * representative.currentPrice;

  double get gainLoss => totalValue - totalCost;
  double get gainLossPercentage =>
      totalCost > 0 ? (gainLoss / totalCost) * 100 : 0;

  /// Pozisyonu tek bir "Asset" gibi görmek isteyen legacy kodlar için — yeni
  /// bir Asset instance'ı üretir (DB'ye yazılmamalı, sadece display).
  Asset asDisplayAsset() {
    final r = representative;
    return Asset(
      id: 'pos:$key',
      userId: r.userId,
      name: r.name,
      ticker: r.ticker,
      type: r.type,
      quantity: totalQuantity,
      purchasePrice: weightedPurchasePrice,
      currency: r.currency,
      notes: r.notes,
      isManualPrice: r.isManualPrice,
      subCategory: r.subCategory,
      unitType: r.unitType,
      purchaseFxRate: weightedFxRate,
      currentPrice: r.currentPrice,
      lastUpdated: r.lastUpdated,
      addedDate: firstBuyDate,
    );
  }
}

/// Aggregation kimliği — hangi lot'lar aynı pozisyonda toplanır.
///
/// Kurallar:
/// - Hisse / Fon → ticker (case-insensitive)
/// - Döviz → ticker (USDTRY=X) veya subCategory (USD)
/// - Altın → subCategory (22 Ayar / Çeyrek / ...)
/// - Emtia / Diğer → ticker varsa ticker; yoksa name (lowercased)
/// - Farklı currency → ayrı grup (maliyet bazı farklı)
/// - Farklı type → her zaman ayrı (aynı ticker ama farklı tip nadir ama olabilir)
String positionKey(Asset a) {
  final currency = a.currency.toUpperCase();
  final type = a.type.name;
  String core;
  switch (a.type) {
    case AssetType.hisse:
    case AssetType.fon:
      core = a.ticker.trim().toUpperCase();
      if (core.isEmpty) core = 'name:${a.name.trim().toLowerCase()}';
      break;
    case AssetType.doviz:
      final t = a.ticker.trim().toUpperCase();
      core = t.isNotEmpty ? t : 'sub:${(a.subCategory ?? '').toUpperCase()}';
      break;
    case AssetType.altin:
      core = 'sub:${(a.subCategory ?? '').toLowerCase()}';
      break;
    case AssetType.emtia:
    case AssetType.diger:
      final t = a.ticker.trim().toUpperCase();
      core = t.isNotEmpty ? t : 'name:${a.name.trim().toLowerCase()}';
      break;
  }
  return '$type|$core|$currency';
}

/// Lot listesini pozisyonlara topla.
///
/// - Sıralama: en yüksek totalValue (TRY) DESC — home ekranı için makul.
///   Farklı sıralama isteyen çağıran kendisi sıralar.
List<Position> aggregatePositions(List<Asset> assets) {
  final map = <String, List<Asset>>{};
  for (final a in assets) {
    if (a.isDeleteLog) continue;
    map.putIfAbsent(positionKey(a), () => []).add(a);
  }
  final positions = <Position>[];
  map.forEach((key, lots) {
    lots.sort((a, b) => b.addedDate.compareTo(a.addedDate));
    final buyLots = lots.where((l) => l.isBuy).toList();
    if (buyLots.isEmpty) return;

    double buyQty = 0;
    double buyCostSum = 0;
    double buyFxCostSum = 0;
    double soldQty = 0;
    for (final l in lots) {
      if (l.isSell) {
        soldQty += l.quantity;
        continue;
      }
      buyQty += l.quantity;
      buyCostSum += l.quantity * l.purchasePrice;
      buyFxCostSum += l.quantity * l.purchasePrice * l.purchaseFxRate;
    }

    final totalQty = buyQty - soldQty;
    if (totalQty <= 0.0000001) return;

    final weightedPrice = buyQty > 0 ? buyCostSum / buyQty : 0.0;
    final weightedFxRate = buyCostSum > 0 ? buyFxCostSum / buyCostSum : 1.0;
    final representative = buyLots.first;
    positions.add(Position(
      key: key,
      representative: representative,
      lots: lots,
      totalQuantity: totalQty,
      weightedPurchasePrice: weightedPrice,
      weightedFxRate: weightedFxRate,
      latestAddedDate: representative.addedDate,
    ));
  });
  return positions;
}
