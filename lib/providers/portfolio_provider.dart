import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../services/price_service.dart';
import 'auth_provider.dart';
import 'signal_provider.dart';

const _uuid = Uuid();

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

  double get totalValue =>
      assets.fold(0, (s, a) => s + toTRY(a.totalValue, a.currency));

  /// Hem alım fiyatı hem güncel fiyatı bilinen varlıkların TRY maliyeti.
  /// currentPrice=0 olan varlıklar henüz fiyat çekilememiş demektir — dahil etme.
  double get totalCost => assets
      .where((a) => a.purchasePrice > 0 && a.currentPrice > 0)
      .fold(0, (s, a) => s + a.totalCostTRY);

  /// Aynı filtre: güncel değer hesabı da sadece fiyatı bilinen varlıkları kapsar.
  double get _trackedValue => assets
      .where((a) => a.purchasePrice > 0 && a.currentPrice > 0)
      .fold(0, (s, a) => s + toTRY(a.totalValue, a.currency));

  double get gainLoss => _trackedValue - totalCost;

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
    return PortfolioState(assets: assets);
  }

  // ---- CRUD ----------------------------------------------------------------

  double _fxRateForCurrency(String currency, PortfolioState s) {
    switch (currency.toUpperCase()) {
      case 'USD': return s.usdTry > 1.0 ? s.usdTry : 1.0;
      case 'EUR': return s.eurTry > 1.0 ? s.eurTry : 1.0;
      case 'GBP': return s.gbpTry > 1.0 ? s.gbpTry : 1.0;
      default: return 1.0;
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
  }) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final currentState = state.valueOrNull ?? const PortfolioState();
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
    );
    // Alım fiyatı girilmemişse ve güncel fiyat biliniyorsa, onu alım fiyatı yap.
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
      state = AsyncData(PortfolioState(assets: assets));
    }
  }

  Future<void> updateAsset(Asset asset) async {
    await SupabaseService.instance.updateAsset(asset);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets: current.assets.map((a) => a.id == asset.id ? asset : a).toList(),
      ));
    }
  }

  Future<void> deleteAsset(String id) async {
    await SupabaseService.instance.deleteAsset(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
          assets: current.assets.where((a) => a.id != id).toList()));
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

  Future<void> refreshPrices() async {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));

    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    for (final a in s.assets) {
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }

    // Aktif ortakların varlıklarını yükle
    final activePartners = ref.read(activePartnersProvider);
    final partnerAssetsMap = <String, List<Asset>>{};
    for (final partner in activePartners) {
      final assets = await SupabaseService.instance.fetchByUser(partner.id);
      partnerAssetsMap[partner.id] = assets;
      for (final a in assets) {
        if (a.ticker.isNotEmpty && !a.isManualPrice) {
          symbols.add(a.ticker.toUpperCase());
        }
      }
    }

    try {
      final quotes = await PriceService.instance.fetchQuotes(symbols.toList());

      final usd = quotes['USDTRY=X']?.regularMarketPrice ?? s.usdTry;
      final eur = quotes['EURTRY=X']?.regularMarketPrice ?? s.eurTry;
      final gbp = quotes['GBPTRY=X']?.regularMarketPrice ?? s.gbpTry;

      final nextState = s.copyWith(usdTry: usd, eurTry: eur, gbpTry: gbp);

      // Kendi varlıklarını güncelle
      final updated = s.assets.map((asset) {
        if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
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

      final finalState = nextState.copyWith(
        assets: updated,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );

      state = AsyncData(finalState);

      if (activePartners.isNotEmpty) {
        await ref.read(allPartnerAssetsProvider.notifier).reload();
      }

      // Snapshot kaydet
      final userId = ref.read(authProvider).valueOrNull?.id ?? '';
      await _saveSnapshot(finalState, userId: userId);

      // Teknik sinyal analizi
      final allAssets = [...finalState.assets];
      for (final list in partnerAssetsMap.values) {
        allAssets.addAll(list);
      }
      ref.read(signalProvider.notifier).analyzePortfolio(allAssets);
    } catch (e) {
      state = AsyncData(s.copyWith(
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
    await SupabaseService.instance.insertSnapshot(categoryValues, userId: userId);
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
    AsyncNotifierProvider<_PartnerAssetsNotifier, Map<String, List<Asset>>>(
  _PartnerAssetsNotifier.new,
);

class _PartnerAssetsNotifier
    extends AsyncNotifier<Map<String, List<Asset>>> {
  @override
  Future<Map<String, List<Asset>>> build() async {
    final activePartners = ref.watch(activePartnersProvider);
    final map = <String, List<Asset>>{};
    for (final p in activePartners) {
      map[p.id] = await SupabaseService.instance.fetchByUser(p.id);
    }
    return map;
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
      map[p.id] = await SupabaseService.instance.fetchByUser(p.id);
    }
    state = AsyncData(map);
  }
}
