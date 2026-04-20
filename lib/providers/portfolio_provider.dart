import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../services/database_service.dart';
import '../services/price_service.dart';
import 'auth_provider.dart';

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

  // ---- Portfolio aggregates (all in TRY) ----

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

  double get totalCost =>
      assets.fold(0, (s, a) => s + toTRY(a.totalCost, a.currency));

  double get gainLoss => totalValue - totalCost;

  double get gainLossPercentage =>
      totalCost > 0 ? gainLoss / totalCost * 100 : 0;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PortfolioNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    // Oturum açmış kullanıcıyı izle — değişince portfolio yeniden yüklenir
    final user = ref.watch(authProvider).valueOrNull;
    final userId = user?.id ?? '';

    if (userId.isEmpty) {
      final assets = await DatabaseService.instance.fetchAll();
      return PortfolioState(assets: assets);
    }

    final assets = await DatabaseService.instance.fetchByUser(userId);
    return PortfolioState(assets: assets);
  }

  // ---- CRUD ----------------------------------------------------------------

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
    final asset = Asset(
      id: _uuid.v4(),
      userId: user?.id ?? '',
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
    );
    await DatabaseService.instance.insert(asset);
    // state.requireValue yerine güvenli erişim —
    // portfolioProvider henüz yükleniyorsa DB'den yeniden çek.
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(assets: [asset, ...current.assets]));
    } else {
      final userId = user?.id ?? '';
      final assets = userId.isEmpty
          ? await DatabaseService.instance.fetchAll()
          : await DatabaseService.instance.fetchByUser(userId);
      state = AsyncData(PortfolioState(assets: assets));
    }
  }

  Future<void> updateAsset(Asset asset) async {
    await DatabaseService.instance.update(asset);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
        assets:
            current.assets.map((a) => a.id == asset.id ? asset : a).toList(),
      ));
    }
  }

  Future<void> deleteAsset(String id) async {
    await DatabaseService.instance.delete(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(
          assets: current.assets.where((a) => a.id != id).toList()));
    }
  }

  Future<void> updateManualPrice(Asset asset, double price) async {
    asset.currentPrice = price;
    asset.lastUpdated = DateTime.now();
    await DatabaseService.instance.update(asset);
    final s = state.requireValue;
    state = AsyncData(s.copyWith(
      assets: s.assets.map((a) => a.id == asset.id ? asset : a).toList(),
    ));
  }

  // ---- Price refresh -------------------------------------------------------

  Future<void> refreshPrices() async {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));

    // Kur sembolleri + kendi varlıklarımızın sembolleri
    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    for (final a in s.assets) {
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }

    // Aktif ortakların varlıklarını yükle ve sembollerini ekle
    final activePartners = ref.read(activePartnersProvider);
    final partnerAssetsMap = <String, List<Asset>>{};
    for (final partner in activePartners) {
      final assets = await DatabaseService.instance.fetchByUser(partner.id);
      partnerAssetsMap[partner.id] = assets;
      for (final a in assets) {
        if (a.ticker.isNotEmpty && !a.isManualPrice) {
          symbols.add(a.ticker.toUpperCase());
        }
      }
    }

    try {
      // Tek seferde tüm sembolleri çek (kendi + ortak)
      final quotes = await PriceService.instance.fetchQuotes(symbols.toList());

      final usd = quotes['USDTRY=X']?.regularMarketPrice ?? s.usdTry;
      final eur = quotes['EURTRY=X']?.regularMarketPrice ?? s.eurTry;
      final gbp = quotes['GBPTRY=X']?.regularMarketPrice ?? s.gbpTry;

      final nextState = s.copyWith(usdTry: usd, eurTry: eur, gbpTry: gbp);

      // Kendi varlıklarımızı güncelle
      final updated = s.assets.map((asset) {
        if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
          final price = quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
          if (price != null) {
            asset.currentPrice = price;
            asset.lastUpdated = DateTime.now();
            DatabaseService.instance.update(asset);
          }
        }
        return asset;
      }).toList();

      // Ortak varlıklarını DB'de güncelle (artık stale snapshot değil, canlı fiyat)
      for (final assets in partnerAssetsMap.values) {
        for (final asset in assets) {
          if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
            final price =
                quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
            if (price != null) {
              asset.currentPrice = price;
              asset.lastUpdated = DateTime.now();
              await DatabaseService.instance.update(asset);
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

      // Ortak varlık provider'ını yenile (UI güncel fiyatları görsün)
      if (activePartners.isNotEmpty) {
        ref.invalidate(allPartnerAssetsProvider);
      }

      // Portföy anlık görüntüsünü kaydet
      final userId = ref.read(authProvider).valueOrNull?.id ?? '';
      await _saveSnapshot(finalState, userId: userId);
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
    await DatabaseService.instance
        .insertSnapshot(categoryValues, userId: userId);
  }

  /// Returns snapshots for chart display.
  /// [sinceMs]: epoch milliseconds cutoff (e.g. 30 days ago).
  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
          int sinceMs) =>
      DatabaseService.instance.fetchSnapshots(
        sinceMs,
        userId: ref.read(authProvider).valueOrNull?.id,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final portfolioProvider =
    AsyncNotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);

final allPartnerAssetsProvider =
    FutureProvider<Map<String, List<Asset>>>((ref) async {
  final activePartners = ref.watch(activePartnersProvider);
  final map = <String, List<Asset>>{};

  for (final p in activePartners) {
    final assets = await DatabaseService.instance.fetchByUser(p.id);
    map[p.id] = assets;
  }

  return map;
});
