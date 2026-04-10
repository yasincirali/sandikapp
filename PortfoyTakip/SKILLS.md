# PortfoyTakip — Skills & Patterns

## First-time Setup (Flutter not yet initialized)
```bash
# Install Flutter SDK from flutter.dev, then:
cd C:\Users\vasin\PortfoyTakip
flutter create . --project-name portfoy_takip --org com.portfoytakip
flutter pub get

# Run on Android emulator or connected device:
flutter run

# Run on iOS (requires macOS + Xcode):
flutter run -d ios
```
> `flutter create .` generates `android/`, `ios/`, `test/` etc. without touching existing `lib/` files.

## Adding a New Asset Type
1. Add case to `AssetType` enum in [lib/models/asset_type.dart](lib/models/asset_type.dart)
2. Fill `label`, `icon`, `color`, `defaultCurrency` in the constructor
3. Add `tickerHint` switch case
4. No other changes needed — all screens use `AssetType.values`

## Adding a New Field to Asset
1. Add property to `Asset` in [lib/models/asset.dart](lib/models/asset.dart)
2. Add to `toMap()` and `fromMap()`
3. Add sqflite column: increment `version` in `DatabaseService._init()` and add `onUpgrade` handler
4. Update form in [lib/screens/add_asset_screen.dart](lib/screens/add_asset_screen.dart)

## State Flow
```
User action (add/edit/delete/refresh)
  → portfolioProvider.notifier.method()
      → DatabaseService (persist)
      → state = AsyncData(state.copyWith(...))   ← triggers UI rebuild
  → ConsumerWidget rebuilds via ref.watch(portfolioProvider)
```

## Price Refresh Flow
```
PortfolioNotifier.refreshPrices()
  → collect tickers from non-manual assets + USDTRY=X, EURTRY=X, GBPTRY=X
  → PriceService.instance.fetchQuotes(symbols)   (http, 15s timeout)
  → update asset.currentPrice + usdTry/eurTry/gbpTry in state
  → persist each changed asset via DatabaseService.update()
```

## Currency Conversion
`PortfolioState.toTRY(amount, currency)` — uses live FX rates stored in state.
Call this in widgets; never multiply by rates manually.

## sqflite Migration Pattern
```dart
// In DatabaseService._init():
return openDatabase(path,
  version: 2,                     // bump version
  onCreate: (db, _) { ... },
  onUpgrade: (db, oldV, newV) async {
    if (oldV < 2) {
      await db.execute('ALTER TABLE assets ADD COLUMN newField TEXT NOT NULL DEFAULT ""');
    }
  },
);
```

## Yahoo Finance Symbols Quick Reference
| Asset          | Symbol         |
|----------------|----------------|
| BIST stock     | `TICKER.IS`    |
| USD/TRY        | `USDTRY=X`     |
| EUR/TRY        | `EURTRY=X`     |
| GBP/TRY        | `GBPTRY=X`     |
| Gold (gram/TL) | `XAUTRY=X`     |
| Gold (oz/USD)  | `GC=F`         |
| Crude oil      | `CL=F`         |
| Natural gas    | `NG=F`         |

## Manual Price Assets
`isManualPrice = true` (auto when ticker is empty).
`refreshPrices` skips these; user updates via detail screen → `updateManualPrice()`.

## Riverpod Patterns
```dart
// Watch in ConsumerWidget:
final asyncState = ref.watch(portfolioProvider);
asyncState.when(data: (s) => ..., loading: () => ..., error: (e,_) => ...);

// Read notifier (write ops):
ref.read(portfolioProvider.notifier).addAsset(...);

// Safe value access inside notifier methods:
final s = state.requireValue;  // throws if still loading — OK in action methods
```
