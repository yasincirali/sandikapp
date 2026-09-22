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
    this.totalCommission = 0,
    this.totalDividend = 0,
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

  /// Bu pozisyona giren buy lot'larının komisyon toplamı (alım para biriminde).
  final double totalCommission;

  /// Bu pozisyondan tahsil edilen nakit temettü toplamı (alım para biriminde).
  ///
  /// DİKKAT: tamamen satılmış pozisyonlar `aggregatePositions` tarafından
  /// listeden düşürülür (totalQty <= 0) — o pozisyonların temettüsü burada
  /// GÖRÜNMEZ. Portföy geneli temettü için [totalDividendTRY] kullan; o ham
  /// lot listesinden hesaplar.
  final double totalDividend;

  bool get isSingle => lots.length == 1;

  /// İlk buy lot'un tarihi — grafik "sahip olma dönemi"nin başlangıcı için.
  DateTime get firstBuyDate {
    final buys = lots.where((l) => l.isBuy);
    if (buys.isEmpty) return latestAddedDate;
    return buys
        .map((l) => l.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Aggregated toplam maliyet — komisyonlar DAHİL (alım para biriminde).
  ///
  /// Komisyon miktara oranlanamaz (işlem başına sabit bir masraftır), bu
  /// yüzden ağırlıklı fiyata gömülmez; buy lot'larının komisyon toplamı
  /// olarak ayrı taşınır ve maliyete eklenir.
  double get totalCost =>
      totalQuantity * weightedPurchasePrice + totalCommission;

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
      // Komisyon toplamı taşınmazsa pozisyon Asset'e çevrildiği anda
      // maliyetten düşer ve kâr olduğundan yüksek görünür.
      commission: totalCommission,
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

/// Karışık bir defteri (Birlikte: ben + ortaklar) sahibe göre böler —
/// [aggregatePositionsByOwner] / [ownerScopedTotalValue] girdisi.
///
/// Çağıranın elinde çoğu zaman sahibi ayrılmış listeler zaten vardır ve
/// onları doğrudan verir. Bu yardımcı, defterin TEK liste hâlinde dolaşan
/// yüzeyleri içindir (`PortfolioState.assets` bir kapsam durumu taşıyorsa):
/// `Asset.userId` her lot'ta vardır, sahiplik sınırı buradan geri kurulur.
/// Tek sahipli defterde tek grup döner — davranış değişmez.
List<List<Asset>> lotlarSahibeGore(Iterable<Asset> assets) {
  final m = <String, List<Asset>>{};
  for (final a in assets) {
    m.putIfAbsent(a.userId, () => []).add(a);
  }
  return m.values.toList(growable: false);
}

/// TRY'ye çeviren dönüştürücü. Canlı kurlar `PortfolioState`'te tutulur;
/// model katmanının state'e erişimi yok, bu yüzden çağıran enjekte eder
/// (`state.toTRY`). Yalnızca TRY varlıklarla çalışan testler
/// [identityToTRY] verebilir.
typedef ToTRY = double Function(double amount, String currency);

/// Tüm varlıkları TRY kabul eden dönüştürücü — sadece test/TRY-only senaryolar.
double identityToTRY(double amount, String currency) => amount;

/// Sahiplik sınırını koruyan toplam kâr/zarar (TRY) — temettü DAHİL.
///
/// `PortfolioState.gainLoss` ile aynı kuralları uygular — fiyatı bilinmeyen
/// varlıklar (purchasePrice/currentPrice = 0) sermaye kazancı hesabı dışıdır
/// — ama filtreyi her sahibin KENDİ pozisyonlarına ayrı ayrı uygular.
///
/// Temettü fiyat filtresine tabi değildir ve ham lot'lardan toplanır:
/// tamamen satılmış pozisyonların temettüsü de cebe girmiştir.
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
  for (final lots in ownerLots) {
    total += totalDividendTRY(lots);
  }
  return total;
}

/// Ham lot listesinden toplam nakit temettü (TRY).
///
/// [aggregatePositions] üzerinden DEĞİL, doğrudan lot'lardan hesaplar:
/// tamamen satılmış pozisyonlar aggregate sonucundan düşer ama onlardan
/// tahsil edilen temettü yine de kullanıcının cebine girmiştir.
///
/// Temettü, ödeme günü kuruyla TRY'ye çevrilir (`purchaseFxRate` temettü
/// satırında o günün kurunu taşır).
double totalDividendTRY(Iterable<Asset> lots) {
  double total = 0;
  for (final l in lots) {
    if (!l.isDividend) continue;
    // Silinmiş temettü cebe girmemiş sayılır — varlık kaydı tamamen
    // kaldırıldıysa ona bağlı temettü de getiriden düşer.
    if (l.isDeleted) continue;
    total += l.dividendTRY;
  }
  return total;
}

/// Bir sembolün oturumda görülmüş son canlı fiyatı — yoksa `null`.
///
/// [ownerScopedTotalValue] bunu ENJEKTE alır; model katmanının servise
/// erişimi yok (bkz. [ToTRY] ile aynı gerekçe).
typedef SonFiyat = double? Function(String ticker);

/// Sahiplik sınırını koruyan toplam güncel değer (TRY).
///
/// [sonFiyat] verilirse, `currentPrice`'ı OLMAYAN pozisyon oturumdaki son
/// bilinen kotasyondan fiyatlanır.
///
/// ## Neden gerekli (kullanıcı bildirimi, 2026-09-22)
/// Ortak lot'larının `currentPrice`'ı RLS yüzünden sunucuya yazılamaz;
/// `refreshPrices` onları yalnızca BELLEKTE günceller
/// (`PartnerAssetsNotifier.setAssets`). Ama `PartnerAssetsNotifier.build()`
/// `activePartnersProvider`'ı izliyor ve her tetiklendiğinde `fetchByUser`
/// ile DB'den HAM lot'ları döndürüyor — yani fiyatlı listeyi bayat
/// `current_price` ile eziyor (dosyanın kendi notu bu tuzağı zaten
/// uyarıyordu, ama yalnızca `reload()` için).
///
/// Sonuç ekranda: fiyatı düşen ortak pozisyonu toplama HİÇ girmiyor ve
/// Performans › Özet'te **Birlikte "Bugün" = Ben "Bugün"** çıkıyordu;
/// ortağın ₺572.980'i kayboluyordu. Dönem BAŞI doğruydu (seri geçmiş
/// fiyatlardan hesaplanır, `currentPrice`'a ihtiyaç duymaz), yalnızca uç
/// yanlıştı — bu yüzden kâr/zarar aradaki farkı sahte hareket olarak
/// gösteriyordu.
///
/// Son bilinen fiyat UYDURMA DEĞİLDİR: `PriceService._sonBilinenFiyat`
/// yalnızca gerçekten ÖLÇÜLMÜŞ kotasyonları taşır ve TTL ile düşmez
/// (bkz. `fiyat_kaynagi.dart` "uydurma sayı yasak" sözleşmesi). Kotasyon
/// hiç görülmemişse pozisyon yine toplama girmez — sıfır uydurulmaz.
double ownerScopedTotalValue(
  Iterable<List<Asset>> ownerLots, {
  ToTRY toTRY = identityToTRY,
  SonFiyat? sonFiyat,
}) {
  double total = 0;
  for (final position in aggregatePositionsByOwner(ownerLots)) {
    final a = position.asDisplayAsset();
    if (a.currentPrice > 0 || sonFiyat == null) {
      total += toTRY(a.totalValue, a.currency);
      continue;
    }
    // Fiyatı düşmüş pozisyon: oturumda görülmüş son kotasyona düş.
    final ticker = a.ticker.trim();
    if (ticker.isEmpty) continue;
    final p = sonFiyat(ticker);
    if (p == null || p <= 0) continue;
    total += toTRY(a.quantity * p, a.currency);
  }
  return total;
}

/// Lot listesini pozisyonlara topla.
///
/// - Sıralama: en yüksek totalValue (TRY) DESC — home ekranı için makul.
///   Farklı sıralama isteyen çağıran kendisi sıralar.
/// Kullanıcının BUGÜN gerçekten tuttuğu lot'lar.
///
/// ## Neden gerekli
/// `assets` bir LOT DEFTERİDİR: tamamen satılan bir pozisyonun alım satırı
/// silinmez, yanına `sell` satırı yazılır. İkisi de `isActive` olduğu için
/// ham listeyi gezen her yer bunları "varlık var" sayıyordu — kullanıcı o
/// hisseden hiç tutmadığı hâlde fiyat alarmı adayı, tür çipi ve dağılım
/// satırı olarak görünüyordu (kullanıcı bildirimi, TestFlight 2026-09-11).
///
/// ## `deletedAt` ile KARIŞTIRILMAMALI — ikisi ayrı kavram
///   * `deletedAt`  → kullanıcı o lot'u SİLDİ. Geçmişte durur, hiçbir
///     hesaba girmez. [Asset.isActive] bunu zaten eliyor.
///   * kapanmış pozisyon → lot'lar duruyor ve GEÇERLİ; yalnızca net miktar
///     0. Geçmiş grafiği bu satırlardan kuruluyor.
///
/// Kapanmış pozisyona `deletedAt` basmak ikisini birleştirirdi ve
/// **satıştan önceki dönem grafikten silinirdi** — satılmış varlık hiç
/// alınmamış gibi görünürdü. Bu yüzden kapanmışlık DB'ye yazılmıyor,
/// okuma anında türetiliyor.
///
/// ## Nerede kullanılır
/// "Kullanıcı bundan tutuyor mu?" sorusunun sorulduğu her yerde: ön yüz
/// listeleri, dağılım, fiyat alarmı adayları, bildirim hedefleri.
/// **Kullanılmayacağı yer:** hareket geçmişi, `HistoryService` ve tüm
/// dönem hesapları — oralarda ham defter DOĞRU olandır.
List<Asset> aktifLotlar(Iterable<Asset> assets) {
  final acikAnahtarlar = <String>{
    for (final p in aggregatePositions(assets.toList())) p.key,
  };
  return [
    for (final a in assets)
      if (a.isActive && acikAnahtarlar.contains(positionKey(a))) a,
  ];
}

/// Ön yüzde gösterilecek pozisyonlar — her biri tek satır.
///
/// `aggregatePositions` + `asDisplayAsset` bileşimi birden çok ekranda
/// elle tekrarlanıyordu; biri güncellenip diğeri kalınca aynı portföy iki
/// ekranda farklı görünüyordu.
List<Asset> gosterilecekVarliklar(Iterable<Asset> assets) =>
    aggregatePositions(assets.toList())
        .map((p) => p.asDisplayAsset())
        .toList();

/// [lot]'un ait olduğu AÇIK pozisyonun ekran görünümü: toplam miktarlı
/// görüntü varlığı + pozisyonun aktif lot'ları. Pozisyon kapalıysa
/// (tamamı satılmış / silinmiş) `null`.
///
/// ## Neden (2026-09-17, "alarmdan tıklayınca altın grafiği çizilmiyor")
/// Varlık ekranı seriyi `getPortfolioHistory([asset])` ile, yani verilen
/// TEK nesneden kurar. Portföy listesi ona `asDisplayAsset()` verir (net
/// miktarlı sentetik alım). Bildirim ve derin bağlantı yolları ise ham
/// DEFTERDEN sembolle eşleşen İLK lot'u veriyordu — o lot bir satış ya da
/// silinmiş kayıt olabilir; `HistoryService` satışı tek başına fiyatlamaz
/// (`isBuy` değil) ve seri boş döner: "veri çekilemedi". Aynı altın
/// portföyden açılınca çiziliyordu, çünkü oradan pozisyon geliyordu.
///
/// İki giriş yolu aynı nesneyi vermeli; bu yardımcı o tek kaynaktır.
({Asset asset, List<Asset> lots})? pozisyonGorunumu(
    Iterable<Asset> assets, Asset lot) {
  final anahtar = positionKey(lot);
  for (final p in aggregatePositions(assets.toList())) {
    if (p.key == anahtar) return (asset: p.asDisplayAsset(), lots: p.lots);
  }
  return null;
}

List<Position> aggregatePositions(List<Asset> assets) {
  final map = <String, List<Asset>>{};
  for (final a in assets) {
    // `isActive` iki şeyi birden eler: mezar taşları (deleteLog) ve
    // yumuşak silinmiş lot'lar. Silinen kayıtlar hareket GEÇMİŞİNDE durur
    // ama hiçbir miktara/tutara girmez.
    if (!a.isActive) continue;
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
    double commissionSum = 0;
    double dividendSum = 0;
    for (final l in lots) {
      // Temettü nakit hareketidir — miktara ASLA girmez. Bu kontrol `isSell`
      // öncesinde olmalı: aşağıdaki blok "sell değilse buy'dır" varsayar,
      // temettü oraya düşerse hayalet lot olarak miktarı şişirirdi.
      if (l.isDividend) {
        dividendSum += l.dividendAmount;
        commissionSum += l.commission;
        continue;
      }
      if (l.isSell) {
        soldQty += l.quantity;
        // Satış komisyonu da cepten çıkar → net maliyeti artırır.
        commissionSum += l.commission;
        continue;
      }
      buyQty += l.quantity;
      buyCostSum += l.quantity * l.purchasePrice;
      buyFxCostSum += l.quantity * l.purchasePrice * l.purchaseFxRate;
      commissionSum += l.commission;
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
      totalCommission: commissionSum,
      totalDividend: dividendSum,
    ));
  });
  return positions;
}
