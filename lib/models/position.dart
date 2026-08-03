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
    case AssetType.mevduat:
      // Vadeli mevduatta her ekleme kendi vade tarihi ve faiziyle bağımsız
      // bir hesaptır — asla aggregate edilmez. Her lot ayrı position.
      core = 'id:${a.id}';
      break;
  }
  return '$type|$core|$currency';
}

/// Birden çok sahibin ("Ben" + ortaklar) lot'larını, sahiplik sınırını
/// koruyarak tek listede pozisyonlara çevirir.
///
/// **Neden ayrı bir fonksiyon:** [positionKey] sahip bilgisi taşımaz
/// (`type|ticker|currency`). Tüm sahiplerin lot'ları tek [aggregatePositions]
/// çağrısına verilirse aynı hisseye sahip iki kişi TEK pozisyonda birleşir.
/// Bunun üç ayrı bozucu etkisi var:
///   1. Pozisyonun tek bir `representative`'i olur → `totalValue` hesabı
///      herkesin miktarına tek kişinin `currentPrice`'ını uygular.
///      Temsilcinin fiyatı çekilememişse (0) birleşik pozisyon
///      `PortfolioState.gainLoss` filtresine takılıp TAMAMEN elenir; kârda
///      olan ortağın kârı da yok olur.
///   2. Ağırlıklı maliyet sahipler arasında ortalanır → kimsenin gerçek
///      maliyeti değildir.
///   3. Net miktar havuz genelinde hesaplanır → bir sahibin satışı diğerinin
///      alımından düşülebilir.
///
/// Sonuç: "Birlikte" sekmesi, tekil sekmelerin toplamıyla tutarsız (hatta
/// ters işaretli) bir kâr/zarar gösteriyordu.
///
/// Bu fonksiyon her sahibi kendi içinde aggregate eder ve pozisyonları
/// birleştirir — böylece toplamlar her zaman parçaların toplamına eşittir.
List<Position> aggregatePositionsByOwner(Iterable<List<Asset>> ownerLots) => [
      for (final lots in ownerLots) ...aggregatePositions(lots),
    ];

/// TRY'ye çeviren dönüştürücü. Canlı kurlar `PortfolioState`'te tutulur;
/// model katmanının state'e erişimi yok, bu yüzden çağıran enjekte eder
/// (`state.toTRY`). Yalnızca TRY varlıklarla çalışan testler
/// [identityToTRY] verebilir.
typedef ToTRY = double Function(double amount, String currency);

/// Tüm varlıkları TRY kabul eden dönüştürücü — sadece test/TRY-only senaryolar.
double identityToTRY(double amount, String currency) => amount;

/// Sahiplik sınırını koruyan toplam kâr/zarar (TRY).
///
/// `PortfolioState.gainLoss` ile aynı kuralları uygular — fiyatı bilinmeyen
/// varlıklar (purchasePrice/currentPrice = 0) hesap dışıdır — ama filtreyi
/// her sahibin KENDİ pozisyonlarına ayrı ayrı uygular.
double ownerScopedGainLoss(
  Iterable<List<Asset>> ownerLots, {
  ToTRY toTRY = identityToTRY,
}) {
  double total = 0;
  for (final position in aggregatePositionsByOwner(ownerLots)) {
    final a = position.asDisplayAsset();
    if (a.purchasePrice <= 0 || a.currentPrice <= 0) continue;
    total += toTRY(a.totalValue, a.currency) - a.totalCostTRY;
  }
  return total;
}

/// Sahiplik sınırını koruyan toplam güncel değer (TRY).
double ownerScopedTotalValue(
  Iterable<List<Asset>> ownerLots, {
  ToTRY toTRY = identityToTRY,
}) {
  double total = 0;
  for (final position in aggregatePositionsByOwner(ownerLots)) {
    final a = position.asDisplayAsset();
    total += toTRY(a.totalValue, a.currency);
  }
  return total;
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
