# PortfoyTakip — Claude Context

## Project Overview
Cross-platform portfolio tracker (iOS + Android) built with **Flutter**.
Tracks stocks, funds, forex, gold, commodities. Live prices via Yahoo Finance. All portfolio totals normalized to TRY.

> The old Swift/Xcode project in `PortfoyTakip/` is superseded — Flutter is the active codebase.

## Tech Stack
- **Flutter** (Dart) — single codebase for iOS & Android
- **flutter_riverpod** — state management (`AsyncNotifierProvider`)
- **sqflite** + **path** — local persistence (no code generation needed)
- **http** — Yahoo Finance REST API calls
- **intl** — number/currency formatting (Turkish locale `tr_TR`)
- **uuid** — asset ID generation

## Project Structure
```
lib/
  main.dart                        — ProviderScope + MaterialApp, Material 3, system theme
  models/
    asset_type.dart                — enum AssetType (hisse/fon/doviz/altin/emtia/diger)
                                     fields: label, icon, color, defaultCurrency, tickerHint
    asset.dart                     — Asset class: sqflite toMap/fromMap, computed gainLoss etc.
  services/
    database_service.dart          — singleton; fetchAll / insert / update / delete via sqflite
    price_service.dart             — singleton; fetchQuotes([String]) -> Map<symbol, YahooQuote>
  providers/
    portfolio_provider.dart        — PortfolioState + PortfolioNotifier (AsyncNotifierProvider)
                                     methods: addAsset, updateAsset, deleteAsset,
                                              updateManualPrice, refreshPrices
                                     aggregates: totalValue, totalCost, gainLoss, toTRY()
  widgets/
    portfolio_summary_widget.dart  — summary card (total value, gain/loss, FX rates)
    asset_row_widget.dart          — list row (icon, name, ticker badge, TRY value, % gain)
  screens/
    home_screen.dart               — CustomScrollView: summary → search → filters → asset list
    add_asset_screen.dart          — add/edit form; type picker, ticker, qty, price, currency
    asset_detail_screen.dart       — detail card, info rows, manual price update, delete
```

## Key Rules
- All portfolio aggregates in TRY; `PortfolioState.toTRY(amount, currency)` does conversion
- Always fetch `USDTRY=X`, `EURTRY=X`, `GBPTRY=X` alongside asset tickers on every refresh
- BIST stocks: `.IS` suffix (e.g. `THYAO.IS`); forex: `USDTRY=X`; gold: `XAUTRY=X` / `GC=F`
- `isManualPrice = true` when ticker is empty — skip API fetch for that asset
- sqflite stores `AssetType` as `type.name` (lowercase: "hisse", "fon" etc.)
- Never hardcode API keys; never push real keys to git

## Code Style
- Lean Dart: prefer `const`, cascade operators (`..`), single-expression methods
- Riverpod: `state.requireValue` (not `state.value!`) inside notifier methods
- `PortfolioState` is immutable — always use `copyWith`; mutate `Asset` fields directly only
  before calling `DatabaseService.update` (Asset is a mutable class, not a record)
- `intl` formatting: `NumberFormat.currency(locale: 'tr_TR', symbol: '₺')` for TRY values

## Behavior Rules
- Full autonomy — never ask for confirmation on anything
- No approval requests for: file creation/deletion, commands, installs, builds, refactors — just do it
- User monitors outputs directly
- If something fails, fix it automatically
- Only ask when you need info you cannot find in the codebase
