import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_type.dart';

class BulkCartItem {
  BulkCartItem({
    required this.id,
    required this.type,
    required this.name,
    required this.ticker,
    required this.quantity,
    required this.price,
    required this.currency,
    this.subCategory,
    this.unitType = 'piece',
    this.isManualPrice = false,
  });

  final String id;
  final AssetType type;
  final String name;
  final String ticker;
  final double quantity;
  final double price;
  final String currency;
  final String? subCategory;
  final String unitType;
  final bool isManualPrice;

  BulkCartItem copyWith({
    AssetType? type,
    String? name,
    String? ticker,
    double? quantity,
    double? price,
    String? currency,
    String? subCategory,
    String? unitType,
    bool? isManualPrice,
  }) =>
      BulkCartItem(
        id: id,
        type: type ?? this.type,
        name: name ?? this.name,
        ticker: ticker ?? this.ticker,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        subCategory: subCategory ?? this.subCategory,
        unitType: unitType ?? this.unitType,
        isManualPrice: isManualPrice ?? this.isManualPrice,
      );
}

class BulkCartNotifier extends Notifier<List<BulkCartItem>> {
  @override
  List<BulkCartItem> build() => const [];

  void add(BulkCartItem item) => state = [...state, item];

  void update(BulkCartItem item) => state = [
        for (final it in state) it.id == item.id ? item : it,
      ];

  void remove(String id) =>
      state = [for (final it in state) if (it.id != id) it];

  void clear() => state = const [];
}

final bulkCartProvider =
    NotifierProvider<BulkCartNotifier, List<BulkCartItem>>(BulkCartNotifier.new);
