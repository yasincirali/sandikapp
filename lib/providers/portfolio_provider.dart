import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../services/database_service.dart';
import '../services/price_service.dart';

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

  double get gainLossPercent =>
      totalCost > 0 ? gainLoss / totalCost * 100 : 0;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PortfolioNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    final assets = await DatabaseService.instance.fetchAll();
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
  }) async {
    final asset = Asset(
      id: _uuid.v4(),
      name: name,
      ticker: ticker,
      type: type,
      quantity: quantity,
      purchasePrice: purchasePrice,
      currency: currency,
      notes: notes,
      isManualPrice: isManualPrice,
    );
    await DatabaseService.instance.insert(asset);
    final s = state.requireValue;
    state = AsyncData(s.copyWith(assets: [asset, ...s.assets]));
  }

  Future<void> updateAsset(Asset asset) async {
    await DatabaseService.instance.update(asset);
    final s = state.requireValue;
    state = AsyncData(s.copyWith(
      assets: s.assets.map((a) => a.id == asset.id ? asset : a).toList(),
    ));
  }

  Future<void> deleteAsset(String id) async {
    await DatabaseService.instance.delete(id);
    final s = state.requireValue;
    state = AsyncData(
        s.copyWith(assets: s.assets.where((a) => a.id != id).toList()));
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
    final s = state.requireValue;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));

    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    for (final a in s.assets) {
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }

    try {
      final quotes =
          await PriceService.instance.fetchQuotes(symbols.toList());

      final usd = quotes['USDTRY=X']?.regularMarketPrice ?? s.usdTry;
      final eur = quotes['EURTRY=X']?.regularMarketPrice ?? s.eurTry;
      final gbp = quotes['GBPTRY=X']?.regularMarketPrice ?? s.gbpTry;

      final updated = s.assets.map((asset) {
        if (!asset.isManualPrice && asset.ticker.isNotEmpty) {
          final price =
              quotes[asset.ticker.toUpperCase()]?.regularMarketPrice;
          if (price != null) {
            asset.currentPrice = price;
            asset.lastUpdated = DateTime.now();
            DatabaseService.instance.update(asset);
          }
        }
        return asset;
      }).toList();

      state = AsyncData(s.copyWith(
        assets: updated,
        isLoading: false,
        usdTry: usd,
        eurTry: eur,
        gbpTry: gbp,
        lastUpdated: DateTime.now(),
      ));
    } catch (e) {
      state = AsyncData(s.copyWith(
        isLoading: false,
        errorMessage: 'Fiyatlar güncellenemedi: $e',
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final portfolioProvider =
    AsyncNotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);
