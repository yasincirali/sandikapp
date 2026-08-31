import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../services/analytics_service.dart';
import '../services/deposit_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/price_service.dart';
import '../services/sparkline_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';

const _uuid = Uuid();

/// Free tier varlık limiti aşıldığında `addAsset` bunu fırlatır. UI yakalayıp
/// paywall gösterir + `premium_gate_shown` event log'lar.
class AssetLimitExceededException implements Exception {
  final int currentCount;
  final int limit;
  const AssetLimitExceededException(this.currentCount, this.limit);
  @override
  String toString() =>
      'AssetLimitExceededException(current: $currentCount, limit: $limit)';
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PortfolioState {
  final List<Asset> assets;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;
  final double usdTry;
  final double eurTry;
  final double gbpTry;

  const PortfolioState({
    this.assets = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
    this.usdTry = 1.0,
    this.eurTry = 1.0,
    this.gbpTry = 1.0,
  });

  PortfolioState copyWith({
    List<Asset>? assets,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastUpdated,
    double? usdTry,
    double? eurTry,
    double? gbpTry,
  }) =>
      PortfolioState(
        assets: assets ?? this.assets,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        usdTry: usdTry ?? this.usdTry,
        eurTry: eurTry ?? this.eurTry,
        gbpTry: gbpTry ?? this.gbpTry,
      );

  double toTRY(double amount, String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return amount * usdTry;
      case 'EUR':
        return amount * eurTry;
      case 'GBP':
        return amount * gbpTry;
      default:
        return amount;
    }
  }

  /// Hesaplara giren kayıtlar: yumuşak silinmemiş VE mezar taşı olmayan.
  ///
  /// [assets] HAM LEDGER'dır — hareket listesi onu olduğu gibi gösterir
  /// (silinmiş bir varlığın Alım/Satım/Temettü geçmişi de görünsün diye).
  /// Toplam/maliyet/getiri hesaplayan HER ŞEY bunun yerine bu görünümü
  /// kullanmalı; aksi halde silinen varlık portföy değerine geri sızar.
  List<Asset> get activeAssets =>
      assets.where((a) => a.isActive).toList(growable: false);

  double get totalValue =>
      activeAssets.fold(0, (s, a) => s + toTRY(a.totalValue, a.currency));

  /// Hem alım fiyatı hem güncel fiyatı bilinen varlıkların TRY maliyeti.
  /// currentPrice=0 olan varlıklar henüz fiyat çekilememiş demektir — dahil etme.
  double get totalCost => activeAssets
      .where((a) => a.purchasePrice > 0 && a.currentPrice > 0)
      .fold(0, (s, a) => s + a.totalCostTRY);

  /// Aynı filtre: güncel değer hesabı da sadece fiyatı bilinen varlıkları kapsar.
  double get _trackedValue => activeAssets
      .where((a) => a.purchasePrice > 0 && a.currentPrice > 0)
      .fold(0, (s, a) => s + toTRY(a.totalValue, a.currency));

  /// Tahsil edilen nakit temettü toplamı (TRY).
  ///
  /// Fiyat filtresine TABİ DEĞİL: temettü zaten cebe girmiş realize gelirdir,
  /// varlığın güncel fiyatının bilinip bilinmemesiyle ilgisi yoktur.
  double get totalDividend => totalDividendTRY(assets);

  /// Sermaye kazancı — temettü HARİÇ (yalnızca fiyat hareketi).
  double get capitalGainLoss => _trackedValue - totalCost;

  /// Toplam getiri — sermaye kazancı + tahsil edilen temettü.
  ///
  /// Temettü eklenmezse uygulama getiriyi olduğundan DÜŞÜK gösterir; BIST'te
  /// temettü getirinin büyük parçasıdır.
  double get gainLoss => capitalGainLoss + totalDividend;

  double get gainLossPercentage =>
      totalCost > 0 ? gainLoss / totalCost * 100 : 0;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PortfolioNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const PortfolioState();

    final assets = await SupabaseService.instance.fetchByUser(user.id);
    return PortfolioState(
      assets: RemoteConfigService.instance.filterHiddenTypes(assets),
    );
  }

  // ---- CRUD ----------------------------------------------------------------

  double _fxRateForCurrency(String currency, PortfolioState s) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return s.usdTry > 1.0 ? s.usdTry : 1.0;
      case 'EUR':
        return s.eurTry > 1.0 ? s.eurTry : 1.0;
      case 'GBP':
        return s.gbpTry > 1.0 ? s.gbpTry : 1.0;
      default:
        return 1.0;
    }
  }

  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final currentState = state.valueOrNull ?? const PortfolioState();

    // ── Free tier gate: distinct pozisyon (buy lot) sayısını kontrol et ─────
    // Position aggregation'a göre count ediyoruz: aynı ticker'a ek lot ekleme
    // yeni "varlık" sayılmasın (kullanıcı zaten sahip olduğuna ekliyor).
    final limit = ref.read(assetLimitProvider);
    if (limit < (1 << 30)) {
      final existingKeys = <String>{};
      for (final a in currentState.assets) {
        // Silinmiş varlık kotayı işgal etmemeli — kullanıcı sildiği halde
        // limite takılırdı.
        if (a.isBuy && a.isActive) {
          existingKeys.add('${a.type.name}|${a.ticker}|${a.currency}');
        }
      }
      final newKey = '${type.name}|$ticker|$currency';
      if (!existingKeys.contains(newKey) && existingKeys.length >= limit) {
        AnalyticsService.instance
            .logPremiumGateShown(feature: 'asset_limit');
        throw AssetLimitExceededException(existingKeys.length, limit);
      }
    }

    final fxRate = _fxRateForCurrency(currency, currentState);

    final asset = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: name,
      ticker: ticker,
      type: type,
      quantity: quantity,
      purchasePrice: purchasePrice,
      currency: currency,
      notes: notes,
      isManualPrice: isManualPrice,
      subCategory: subCategory,
      unitType: unitType,
      purchaseFxRate: fxRate,
      kind: AssetKind.buy,
      addedDate: addedDate,
      currentPrice: initialCurrentPrice,
      commission: commission,
    );
    if (asset.purchasePrice == 0 && asset.currentPrice > 0) {
      asset.purchasePrice = asset.currentPrice;
    }

    await SupabaseService.instance.insertAsset(asset);

    AnalyticsService.instance.logAssetAdded(
      type: type.name,
      subCategory: subCategory,
    );

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(assets: [asset, ...current.assets]));
    } else {
      final assets = await SupabaseService.instance.fetchByUser(user.id);
      state = AsyncData(PortfolioState(
        assets: RemoteConfigService.instance.filterHiddenTypes(assets),
      ));
    }
  }

  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final transaction = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: asset.name,
      ticker: asset.ticker,
      type: asset.type,
      quantity: quantity,
      purchasePrice: asset.purchasePrice,
      currency: asset.currency,
      notes: asset.notes,
      isManualPrice: asset.isManualPrice,
      subCategory: asset.subCategory,
      unitType: asset.unitType,
      purchaseFxRate: asset.purchaseFxRate,
      currentPrice: asset.currentPrice,
      lastUpdated: asset.lastUpdated,
      kind: AssetKind.sell,
      refAssetId: asset.id.startsWith('pos:') ? null : asset.id,
      sellPrice: sellPrice,
    );

    await SupabaseService.instance.insertAsset(transaction);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(assets: [transaction, ...current.assets]));
    }
  }

  /// Nakit temettü kaydı ekler.
  ///
  /// Temettü satırı miktarı DEĞİŞTİRMEZ — `quantity: 0` ile yazılır ve
  /// `dividendAmount` alanında ele geçen net tutarı taşır. `purchaseFxRate`
  /// burada ÖDEME GÜNÜ kurunu tutar (alım kurunu değil), böylece TRY karşılığı
  /// temettünün alındığı günün kuruyla sabitlenir.
  Future<void> addDividend({
    required Asset asset,
    required double amount,
    DateTime? paidAt,
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    if (amount <= 0) return;
    // Yalnızca hisse temettü dağıtır — UI zaten butonu gizliyor, bu ikinci
    // savunma başka bir giriş noktası eklendiğinde kuralı korur.
    if (!asset.supportsDividend) return;

    final currentState = state.valueOrNull ?? const PortfolioState();
    final fxRate = _fxRateForCurrency(asset.currency, currentState);

    final transaction = Asset(
      id: _uuid.v4(),
      userId: user.id,
      name: asset.name,
      ticker: asset.ticker,
      type: asset.type,
      // Miktar 0 — temettü pozisyona dokunmaz.
      quantity: 0,
      purchasePrice: 0,
      currency: asset.currency,
      notes: '',
      isManualPrice: asset.isManualPrice,
      subCategory: asset.subCategory,
      unitType: asset.unitType,
      purchaseFxRate: fxRate,
      currentPrice: asset.currentPrice,
      kind: AssetKind.dividend,
      refAssetId: asset.id.startsWith('pos:') ? null : asset.id,
      addedDate: paidAt,
      dividendAmount: amount,
    );

    await SupabaseService.instance.insertAsset(transaction);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
          current.copyWith(assets: [transaction, ...current.assets]));
    }
  }

  Future<void> updateAsset(Asset asset) async {
    await SupabaseService.instance.updateAsset(asset);
    AnalyticsService.instance.logAssetUpdated(type: asset.type.name);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets:
            current.assets.map((a) => a.id == asset.id ? asset : a).toList(),
      ));
    }
  }

  Future<void> deleteAsset(String id) async {
    final current = state.valueOrNull;
    Asset? deleted;
    if (current != null) {
      for (final asset in current.assets) {
        if (asset.id == id) {
          deleted = asset;
          break;
        }
      }
    }
    Asset? transaction;
    if (deleted != null) {
      transaction = Asset(
        id: _uuid.v4(),
        userId: deleted.userId,
        name: deleted.name,
        ticker: deleted.ticker,
        type: deleted.type,
        quantity: deleted.quantity,
        purchasePrice: deleted.purchasePrice,
        currency: deleted.currency,
        notes: deleted.notes,
        isManualPrice: deleted.isManualPrice,
        subCategory: deleted.subCategory,
        unitType: deleted.unitType,
        purchaseFxRate: deleted.purchaseFxRate,
        currentPrice: deleted.currentPrice,
        lastUpdated: deleted.lastUpdated,
        kind: AssetKind.deleteLog,
        refAssetId: deleted.id,
      );
      await SupabaseService.instance.insertAsset(transaction);
      AnalyticsService.instance.logAssetDeleted(type: deleted.type.name);
    }
    await SupabaseService.instance.deleteAsset(id);
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets: [
          if (transaction != null) transaction,
          ...current.assets.where((a) => a.id != id),
        ],
      ));
    }
  }

  /// Bir pozisyonun TÜM lot'larını siler (alım + satım + temettü).
  ///
  /// Parça parça eklenmiş bir varlıkta UI'daki satır tek bir kayıt değil,
  /// aynı `positionKey`'e düşen birkaç lot'tur. Kaydırıp "Sil" dendiğinde
  /// eskiden yalnızca `representative` (= en son eklenen alım) siliniyordu;
  /// geri kalan lot'lar kaldığı için satır azalmış miktarla yeniden
  /// beliriyordu. Silme, kullanıcının gördüğü satırın tamamını kaldırmalı.
  ///
  /// Silme işlemi başına TEK deleteLog kaydı yazılır — lot başına değil.
  ///
  /// Eskiden her lot için ayrı bir mezar taşı yazılıyordu; hareket listesi
  /// ham ledger'a bağlanınca üç lot'lu bir varlığı silmek listeye üç ayrı
  /// "Silindi" satırı bırakıyordu. Artık tek satır yazılır ve kaç kaydın
  /// gittiği [Asset.deletedCount] içinde taşınır → "Silindi · 3 kayıt".
  ///
  /// Kaydın miktarı ve tutarı silinen POZİSYONUN neti üzerinden yazılır
  /// (alımlar − satışlar), böylece hareket satırı "ne kadarlık varlık
  /// gitti" sorusunu yanıtlar. Grafik ve toplamlar deleteLog'u zaten yok
  /// sayar; bu alanlar yalnızca gösterim içindir.
  Future<void> deletePositionLots(List<Asset> lots) async {
    final ids = lots.map((l) => l.id).toSet();
    if (ids.isEmpty) return;

    final current = state.valueOrNull;

    // Mezar taşları yeniden silinmez ve sayıma girmez.
    final removed = lots.where((l) => !l.isDeleteLog).toList();
    Asset? log;
    if (removed.isNotEmpty) {
      // Temsilci: en yeni ALIM (yoksa ilk kayıt) — isim/ticker/tür meta'sı
      // buradan gelir.
      final buys = removed.where((l) => l.isBuy).toList()
        ..sort((a, b) => b.addedDate.compareTo(a.addedDate));
      final rep = buys.isNotEmpty ? buys.first : removed.first;

      // Net miktar ve net maliyet — satışlar düşülür, temettü miktara
      // girmez (nakit hareketidir).
      double netQty = 0;
      double netCost = 0;
      for (final l in removed) {
        if (l.isDividend) continue;
        if (l.isSell) {
          netQty -= l.quantity;
          netCost -= l.quantity * (l.sellPrice ?? l.purchasePrice);
          continue;
        }
        netQty += l.quantity;
        netCost += l.quantity * l.purchasePrice;
      }
      final unitPrice = netQty > 0 ? netCost / netQty : rep.purchasePrice;

      log = Asset(
        id: _uuid.v4(),
        userId: rep.userId,
        name: rep.name,
        ticker: rep.ticker,
        type: rep.type,
        quantity: netQty > 0 ? netQty : 0,
        purchasePrice: unitPrice,
        currency: rep.currency,
        notes: rep.notes,
        isManualPrice: rep.isManualPrice,
        subCategory: rep.subCategory,
        unitType: rep.unitType,
        purchaseFxRate: rep.purchaseFxRate,
        currentPrice: rep.currentPrice,
        lastUpdated: rep.lastUpdated,
        kind: AssetKind.deleteLog,
        // Tek satır artık birden çok lot'u temsil ediyor; tek bir lot'a
        // referans vermek yanıltıcı olurdu.
        refAssetId: removed.length == 1 ? removed.first.id : null,
        deletedCount: removed.length,
      );

      await SupabaseService.instance.insertAsset(log);
      AnalyticsService.instance.logAssetDeleted(type: rep.type.name);
    }

    // YUMUŞAK silme: lot'lar yerinde kalır, damgalanır. Fiziksel DELETE
    // kullanılsaydı bu varlığın Alım/Satım/Temettü satırları hareket
    // geçmişinden de silinirdi ve geriye yalnızca "Silindi" mezar taşı
    // kalırdı — kullanıcı ne aldığını/sattığını okuyamazdı.
    final stampedAt = DateTime.now();
    await SupabaseService.instance
        .softDeleteAssets(ids.toList(), stampedAt);

    if (current != null) {
      state = AsyncData(current.copyWith(
        assets: [
          if (log != null) log,
          for (final a in current.assets)
            if (ids.contains(a.id)) a.copyWithDeletedAt(stampedAt) else a,
        ],
      ));
    }
  }

  Future<void> updateManualPrice(Asset asset, double price) async {
    asset.currentPrice = price;
    asset.lastUpdated = DateTime.now();
    await SupabaseService.instance.updateAsset(asset);
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(
      assets: s.assets.map((a) => a.id == asset.id ? asset : a).toList(),
    ));
  }

  // ---- Price refresh -------------------------------------------------------

  /// [force] true iken fiyat önbelleği atlanır. Kullanıcı pull-to-refresh
  /// yaptığında bayat fiyat görmemeli; ekran açılışlarında ise 45 sn'lik
  /// önbellek gereksiz ağ trafiğini keser.
  Future<void> refreshPrices({bool force = false}) async {
    // Build henüz bitmediyse (ya da user null → boş state) — bekle. Aksi
    // halde eski/boş `s.assets`'i alıp await'ten sonra güncel state'in
    // üzerine sıfır yazma race'i oluşur (bkz. varlıkların bir görünüp
    // kaybolma bug'ı).
    final built = await future;
    // future'dan sonra en güncel state artık valid.
    final s = state.valueOrNull ?? built;
    // Sadece kendi varlıkları boşsa refresh yapılacak bir şey yok.
    if (s.assets.isEmpty) return;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));

    // Sparkline serileri gün-içinde değişmediği için süresiz cache'lenir;
    // kullanıcı bilerek yenilediğinde (pull-to-refresh) tazelenmeli — aksi
    // halde gün dönse bile dünkü eğri kalırdı.
    SparklineService.instance.clear();

    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    for (final a in s.assets) {
      // Silinmiş varlık için fiyat çekmek gereksiz ağ trafiğidir.
      if (!a.isActive) continue;
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }

    // Aktif ortakların varlıklarını yükle
    final activePartners = ref.read(activePartnersProvider);
    final partnerAssetsMap = <String, List<Asset>>{};
    for (final partner in activePartners) {
      final assets = RemoteConfigService.instance.filterHiddenTypes(
        await SupabaseService.instance.fetchByUser(partner.id),
      );
      partnerAssetsMap[partner.id] = assets;
      for (final a in assets) {
        if (a.ticker.isNotEmpty && !a.isManualPrice) {
          symbols.add(a.ticker.toUpperCase());
        }
      }
    }

    try {
      final quotes = await PriceService.instance
          .fetchQuotes(symbols.toList(), forceRefresh: force);

      // await sonrası state başka bir yerden değişmiş olabilir (addAsset,
      // deleteAsset gibi). Kendi asset listesini yazmadan önce **en güncel**
      // state'i tekrar oku — aksi halde bu arada eklenen/silinen lot'lar
      // eski snapshot ile ezilir.
      final current = state.valueOrNull ?? s;
      final baseAssets = current.assets;

      final usd = quotes['USDTRY=X']?.regularMarketPrice ?? current.usdTry;
      final eur = quotes['EURTRY=X']?.regularMarketPrice ?? current.eurTry;
      final gbp = quotes['GBPTRY=X']?.regularMarketPrice ?? current.gbpTry;

      final nextState =
          current.copyWith(usdTry: usd, eurTry: eur, gbpTry: gbp);

      // Kendi varlıklarını güncelle
      final updated = baseAssets.map((asset) {
        if (asset.type == AssetType.mevduat) {
          // Vadeli mevduat — API yok, birim değeri lokal hesapla.
          final terms = DepositService.decode(asset);
          if (terms != null) {
            asset.currentPrice = DepositService.currentUnitValue(terms);
            asset.lastUpdated = DateTime.now();
            SupabaseService.instance.updateAsset(asset);
          }
        } else if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
          final price = quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
          if (price != null) {
            asset.currentPrice = price;
            asset.lastUpdated = DateTime.now();
            // Alım fiyatı girilmemişse güncel fiyatı maliyet olarak kilitle
            if (asset.purchasePrice == 0) {
              asset.purchasePrice = price;
            }
            SupabaseService.instance.updateAsset(asset);
          }
        }
        return asset;
      }).toList();

      // Ortak varlıkları sadece okunur (RLS) — fiyatları bellekte güncelliyoruz
      for (final assets in partnerAssetsMap.values) {
        for (final asset in assets) {
          if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
            final price =
                quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
            if (price != null) {
              asset.currentPrice = price;
              asset.lastUpdated = DateTime.now();
              // Not: updateAsset çağrılmıyor — RLS partner yazmasını engeller
            }
          }
        }
      }

      // Fiyatlanmış ortak listesini DOĞRUDAN yaz.
      //
      // Burada eskiden `allPartnerAssetsProvider.notifier.reload()` çağrılıyordu
      // ve o metot varlıkları DB'den YENİDEN çekiyordu — yukarıdaki fiyat
      // güncellemesini olduğu gibi çöpe atarak. Ortak lot'ları DB'de
      // `current_price` alanını taşır ama o alan yalnızca SAHİBİ uygulamayı
      // açtığında güncellenir (RLS başkasının yazmasını engeller). Sonuç:
      // ortağın varlıkları BAYAT fiyatla kalıyordu.
      //
      // Altında görünür olmasının sebebi: altın `currentPrice`'ı gram22k×kat
      // ile türetilir ve hızlı oynar. Grafik serisi ise fiyatı geçmiş
      // serisinden hesapladığı için GÜNCELDİ; yalnızca serinin son noktası
      // (canlı toplam) bayat kalıyordu. Simülasyonda tüm dönem bugünkü net
      // pozisyonla çizildiğinden bu sapma yüzdeye birebir yansıyor ve
      // "aynı altın, farklı kâr/zarar" olarak görünüyordu.
      ref.read(allPartnerAssetsProvider.notifier).setAssets(partnerAssetsMap);

      final finalState = nextState.copyWith(
        assets: updated,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );

      state = AsyncData(finalState);

      // NOT: Burada `allPartnerAssetsProvider.reload()` ÇAĞRILMAZ. O metot
      // DB'den yeniden çeker ve yukarıda uygulanan canlı fiyatları geri alır.
      // Fiyatlanmış liste zaten `setAssets` ile yazıldı.

      // Snapshot kaydet
      final userId = ref.read(authProvider).valueOrNull?.id ?? '';
      await _saveSnapshot(finalState, userId: userId);

      // NOT: Teknik sinyal analizi burada tetiklenmez. `refreshPrices` her
      // ekran açılışında/pull-to-refresh'te çağrıldığı için burada
      // `analyzePortfolio` çalıştırmak spam push'a yol açıyor. Sinyal analizi
      // artık sadece iki yerden tetiklenir:
      //   1. Günde 2 kez cron (TR 11:00 & 15:00) → analyze-signals edge
      //      function → FCM data-message → `_AuthGate._triggerSignalAnalysis`
      //   2. Uygulama açılışında `signalProvider.build()` DB'den okur
      //      (yeni analiz yapmaz, sadece geçmişi yükler).
    } catch (e) {
      final current = state.valueOrNull ?? s;
      state = AsyncData(current.copyWith(
        isLoading: false,
        errorMessage: 'Fiyatlar güncellenemedi: $e',
      ));
    }
  }

  // ---- Snapshot / history --------------------------------------------------

  Future<void> _saveSnapshot(PortfolioState s, {String userId = ''}) async {
    if (s.assets.isEmpty) return;
    final categoryValues = <String, double>{};
    for (final type in AssetType.values) {
      final val = s.assets
          .where((a) => a.type == type)
          .fold<double>(0, (sum, a) => sum + s.toTRY(a.totalValue, a.currency));
      if (val > 0) categoryValues[type.name] = val;
    }
    await SupabaseService.instance
        .insertSnapshot(categoryValues, userId: userId);
  }

  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
          int sinceMs) =>
      SupabaseService.instance.fetchSnapshots(
        sinceMs,
        userId: ref.read(authProvider).valueOrNull?.id,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final portfolioProvider =
    AsyncNotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);

final allPartnerAssetsProvider =
    AsyncNotifierProvider<PartnerAssetsNotifier, Map<String, List<Asset>>>(
  PartnerAssetsNotifier.new,
);

/// Ortakların varlıkları. Public: widget testleri `overrideWith` ile sahte
/// veri besleyebilsin (private sınıf test tarafından extend edilemiyor).
class PartnerAssetsNotifier extends AsyncNotifier<Map<String, List<Asset>>> {
  @override
  Future<Map<String, List<Asset>>> build() async {
    final activePartners = ref.watch(activePartnersProvider);
    final map = <String, List<Asset>>{};
    for (final p in activePartners) {
      map[p.id] = RemoteConfigService.instance.filterHiddenTypes(
        await SupabaseService.instance.fetchByUser(p.id),
      );
    }
    return map;
  }

  /// Fiyatlanmış ortak listesini doğrudan yaz — DB'den YENİDEN ÇEKMEDEN.
  ///
  /// `refreshPrices` ortak lot'larının `currentPrice`'ını bellekte canlı
  /// kotasyonla günceller (RLS yüzünden DB'ye yazamaz). Ardından [reload]
  /// çağrılırsa o emek boşa gider: `fetchByUser` DB'deki BAYAT `current_price`
  /// değerini geri getirir ve ortağın varlıkları eski fiyatla görünür.
  /// Bu metot, hesaplanmış listeyi olduğu gibi state'e koyar.
  void setAssets(Map<String, List<Asset>> assets) {
    state = AsyncData(assets);
  }

  // Manuel yenileme — refreshPrices() tarafından çağrılır
  Future<void> reload() async {
    final activePartners = ref.read(activePartnersProvider);
    if (activePartners.isEmpty) {
      state = const AsyncData({});
      return;
    }
    // Mevcut veriyi koru, loading state'e GEÇMEDEn arka planda yenile
    final map = <String, List<Asset>>{};
    for (final p in activePartners) {
      map[p.id] = RemoteConfigService.instance.filterHiddenTypes(
        await SupabaseService.instance.fetchByUser(p.id),
      );
    }
    state = AsyncData(map);
  }
}
