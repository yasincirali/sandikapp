import 'asset.dart';
import 'asset_categories.dart';
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
      core = 'sub:${altinAltAnahtari(a.subCategory)}';
      break;
    case AssetType.kripto:
      // `KRIPTO:BTC` — hisse gibi ticker; ad yedeği tickersız eski/elle
      // girilmiş satır için.
      core = a.ticker.trim().toUpperCase();
      if (core.isEmpty) core = 'name:${a.name.trim().toLowerCase()}';
      break;
    case AssetType.mevduat:
      // `MEVDUAT:<sözleşme id>` — sözleşme başına bir pozisyon.
      core = a.ticker.trim().toUpperCase();
      if (core.isEmpty) core = 'name:${a.name.trim().toLowerCase()}';
      break;
    case AssetType.bes:
      // Fon kodu + alt kategori (katkı / devlet katkısı): aynı fonda iki
      // birikim tek pozisyona düşmesin (bkz. `BesAltKategori`). Sunucu eşi
      // `positions.ts` › `pozisyonAnahtari`.
      core = '${a.ticker.trim().toUpperCase()}|'
          'sub:${(a.subCategory ?? '').toLowerCase()}';
      break;
    case AssetType.emtia:
    case AssetType.diger:
      final t = a.ticker.trim().toUpperCase();
      core = t.isNotEmpty ? t : 'name:${a.name.trim().toLowerCase()}';
      break;
  }
  return '$type|$core|$currency';
}

/// Altın alt türünün anahtar biçimi: etiketin küçük harflisi
/// (`çeyrek altın`).
///
/// ## Neden (2026-10-01)
/// `subCategory` kaynağa göre iki biçimde yazılıyor: ekleme formu etiketi
/// (`Çeyrek Altın`), CSV içe aktarma enum adını (`ceyrek`; 2026-10-01'e
/// kadar). Anahtar ham değerden kurulunca aynı çeyrek altın iki pozisyona
/// bölünüyor, Portföy'de iki ayrı satır çıkıyordu. `altinTuru` bu ayrımı
/// zaten biliyordu; anahtar bilmiyordu. Tanınmayan değer eskisi gibi
/// küçük harfe indirilir. Sunucu eşi `positions.ts` › `altinAltAnahtari`.
String altinAltAnahtari(String? subCategory) {
  final s = (subCategory ?? '').trim();
  for (final g in GoldSubCategory.values) {
    if (g.label == s || g.name == s) return g.label.toLowerCase();
  }
  return s.toLowerCase();
}

/// [positionKey]'in ticker çekirdeğini KULLANICIYA gösterilecek koda çevirir.
///
/// Anahtar fiyat sağlayıcısının sembolünü taşır (`ARDYZ.IS`, `TEFAS:AFT`,
/// `KRIPTO:BTC`); bu önek/sonekler kullanıcıya bir şey söylemez. Performans ›
/// Özet GÜNLÜK'te "günün en çok hareket edeni" ham `ARDYZ.IS` yazıyordu
/// (2026-09-29 emülatör testi). Kural `Asset.displayTicker` ve
/// `VarlikKimligi.kisaEtiket` ile aynı: kaynak öneki (`XXX:`) ve BIST'in
/// `.IS` soneki atılır. Alt kategori (`sub:`) ve ad (`name:`) çekirdekleri
/// ÇAĞIRANIN işi — burada yalnızca sembol sadeleşir.
String pozisyonKodu(String core) {
  final t = core.trim();
  final sade = t.contains(':') ? t.substring(t.lastIndexOf(':') + 1) : t;
  final kod = sade.endsWith('.IS') ? sade.substring(0, sade.length - 3) : sade;
  return kod.isEmpty ? t : kod;
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

/// "Birlikte" görünümünde AYNI varlığın farklı sahiplerdeki pozisyonları —
/// kullanıcıya TEK satır, hesapta sahip başına parçalar.
///
/// ## Neden (kullanıcı bildirimi, 2026-10-01)
/// *"Neden KCHOL 2 defa gösterilmiş, bu büyük bir hata."* Birlikte listesi
/// [aggregatePositionsByOwner] çıktısını olduğu gibi basıyordu: sahiplik
/// sınırı doğru korunuyordu ama kullanıcı iki ortağın KCHOL'ünü sahip
/// etiketi olmayan iki ayrı satır olarak görüyordu. Aynı anahtar iki kez
/// liste anahtarı (`ValueKey(key)`) olunca kaydırma paneli ve açılır kart
/// durumu da satırlar arasında karışabiliyordu.
///
/// ## Değişmez korunur
/// Birleşme GÖRÜNÜMDEDİR, hesapta değil: her parça kendi sahibinin
/// `aggregatePositions` çıktısıdır (kendi maliyeti, kendi netlemesi) ve
/// değer/maliyet parçaların TOPLAMIDIR — tek temsilcinin fiyatı herkesin
/// miktarına uygulanmaz (bkz. [aggregatePositionsByOwner] madde 1–3).
/// Ağırlıklı alış fiyatı yalnızca açılır paneldeki "ortalama maliyet" için
/// türetilir; kâr/zarar ondan hesaplanmaz.
class BirlesikPozisyon extends Position {
  BirlesikPozisyon._({
    required super.key,
    required super.representative,
    required super.lots,
    required super.totalQuantity,
    required super.weightedPurchasePrice,
    required super.weightedFxRate,
    required super.latestAddedDate,
    required super.totalCommission,
    required super.totalDividend,
    required this.parcalar,
  });

  /// Sahip başına pozisyonlar — her biri tek sahibin lot'larından kurulu.
  final List<Position> parcalar;

  factory BirlesikPozisyon.parcalardan(List<Position> parcalar) {
    assert(parcalar.length > 1);
    final enYeni = parcalar.reduce(
        (a, b) => b.latestAddedDate.isAfter(a.latestAddedDate) ? b : a);
    var miktar = 0.0, maliyet = 0.0, kurluMaliyet = 0.0;
    var komisyon = 0.0, temettu = 0.0;
    for (final p in parcalar) {
      miktar += p.totalQuantity;
      maliyet += p.totalQuantity * p.weightedPurchasePrice;
      kurluMaliyet +=
          p.totalQuantity * p.weightedPurchasePrice * p.weightedFxRate;
      komisyon += p.totalCommission;
      temettu += p.totalDividend;
    }
    return BirlesikPozisyon._(
      key: enYeni.key,
      representative: enYeni.representative,
      lots: [for (final p in parcalar) ...p.lots]
        ..sort((a, b) => b.addedDate.compareTo(a.addedDate)),
      totalQuantity: miktar,
      weightedPurchasePrice: miktar > 0 ? maliyet / miktar : 0,
      weightedFxRate: maliyet > 0 ? kurluMaliyet / maliyet : 1,
      latestAddedDate: enYeni.latestAddedDate,
      totalCommission: komisyon,
      totalDividend: temettu,
      parcalar: List.unmodifiable(parcalar),
    );
  }

  /// [userId]'nin parçası — kaydırma aksiyonları (Al/Sat/Temettü/Sil) ve
  /// varlık ekranı YALNIZCA bununla çalışır: ortağın lot'una yazılamaz (RLS)
  /// ve varlık ekranı tek sahipli pozisyon bekler (`_canli`).
  Position? parcasi(String? userId) {
    for (final p in parcalar) {
      if (p.representative.userId == userId) return p;
    }
    return null;
  }

  @override
  double get totalValue =>
      parcalar.fold(0.0, (s, p) => s + p.totalValue);

  @override
  double get totalCost => parcalar.fold(0.0, (s, p) => s + p.totalCost);

  @override
  double get totalCostTRY =>
      parcalar.fold(0.0, (s, p) => s + p.totalCostTRY);

  /// Görünen birim fiyat parçaların değerinden türetilir: satırdaki tutar
  /// (`miktar × fiyat`) ile kâr/zararın dayandığı [totalValue] aynı sayı
  /// olsun — sahiplerin fiyatı bir an farklıysa (biri tazelenmemiş) bile.
  @override
  Asset asDisplayAsset() {
    final a = super.asDisplayAsset();
    if (totalQuantity > 0) a.currentPrice = totalValue / totalQuantity;
    return a;
  }
}

/// Sahip başına kurulmuş pozisyonları, aynı [Position.key]'e düşenler TEK
/// satır olacak şekilde birleştirir (bkz. [BirlesikPozisyon]). Tek sahipli
/// pozisyon olduğu gibi döner; sıra ilk görülme sırasıdır.
List<Position> sahiplerArasiBirlestir(Iterable<Position> sahipPozisyonlari) {
  final gruplar = <String, List<Position>>{};
  for (final p in sahipPozisyonlari) {
    gruplar.putIfAbsent(p.key, () => []).add(p);
  }
  return [
    for (final g in gruplar.values)
      g.length == 1 ? g.single : BirlesikPozisyon.parcalardan(g),
  ];
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

/// Sahiplik sınırını koruyan MALİYET tabanı (TRY) — yüzdenin paydası.
///
/// [ownerScopedGainLoss] ile AYNI pozisyon kümesini ve AYNI fiyat filtresini
/// kullanır. İkisi ayrı kurallardan beslenirse yüzde, payı olmayan bir
/// paydaya bölünür.
///
/// ## Neden gerekli (denetim, 2026-09-22)
/// `PortfolioState.totalCost` ham `activeAssets` üzerinden topluyordu, yani
/// SATIŞ lot'larının maliyetini de sayıyordu. Ölçüldü: 10 al @100 + 4 sat
/// @130 defterinde taban ₺1.400 çıkıyordu — oysa elde 6 lot var, gerçek
/// taban ₺600. Yalnızca satış lot'u olan defterde taban ₺400 ve kâr +₺80
/// görünüyordu: elde hiçbir şey yokken %20 kâr.
double ownerScopedCostBasis(
  Iterable<List<Asset>> ownerLots, {
  ToTRY toTRY = identityToTRY,
}) {
  double total = 0;
  for (final position in aggregatePositionsByOwner(ownerLots)) {
    final a = position.asDisplayAsset();
    if (a.purchasePrice <= 0 || a.currentPrice <= 0) continue;
    total += a.totalCostTRY;
  }
  return total;
}

/// Sahiplik sınırını koruyan SERMAYE kazancı (TRY) — temettü HARİÇ.
///
/// [ownerScopedGainLoss]'un temettüsüz hâli. Üst kart toplam getiriyi
/// gösterir (temettü dahil), köprü/ayrıntı satırları ise fiyat hareketini
/// ayırabilsin diye ikisi ayrı taşınır.
double ownerScopedCapitalGainLoss(
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
        // Satış komisyonu AÇIK pozisyonun maliyetine GİRMEZ.
        //
        // ## Neden değişti (denetim, 2026-09-22)
        // Eskiden buraya ekleniyordu ("cepten çıkar → maliyeti artırır").
        // Ama satış komisyonu SATILAN lot'un masrafıdır; elde kalan lot'un
        // alım maliyetiyle ilgisi yoktur. İki bozucu etkisi ölçüldü:
        //
        //   1. 10 al @100 + 4 sat @130 (satış kom. ₺50) defterinde açık
        //      pozisyonun tabanı ₺650 çıkıyordu — elde 6 lot var, taban
        //      ₺600 olmalı. Yüzde %20 yerine %10,77 görünüyordu.
        //   2. Aynı ₺50 `realizedGainLoss`'tan DÜŞÜLMÜYORDU — yani masraf
        //      bir kez sayılıp yanlış yere yazılıyordu.
        //
        // Artık komisyon gerçekleşen kâr/zarara yazılır
        // (`Asset.sellProceedsTRY` onu zaten düşüyor) ve açık pozisyonun
        // tabanı saf alım maliyeti kalır. Tamamen satılan pozisyonda
        // komisyon artık KAYBOLMUYOR: pozisyon listeden düşse bile
        // realize hesabı ham defterden okur.
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
