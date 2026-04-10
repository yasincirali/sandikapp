import SwiftUI
import SwiftData

@MainActor
@Observable
final class PortfolioViewModel {

    // Exchange rates (fetched alongside asset prices)
    private(set) var usdTry: Double = 1.0
    private(set) var eurTry: Double = 1.0
    private(set) var gbpTry: Double = 1.0

    private(set) var isLoading: Bool = false
    private(set) var lastUpdated: Date?
    var errorMessage: String?

    // MARK: - Portfolio totals (all in TRY)

    func totalValue(assets: [Asset]) -> Double {
        assets.reduce(0) { $0 + toTRY($1.totalValue, currency: $1.currency) }
    }

    func totalCost(assets: [Asset]) -> Double {
        assets.reduce(0) { $0 + toTRY($1.totalCost, currency: $1.currency) }
    }

    func totalGainLoss(assets: [Asset]) -> Double {
        totalValue(assets: assets) - totalCost(assets: assets)
    }

    func totalGainLossPercent(assets: [Asset]) -> Double {
        let cost = totalCost(assets: assets)
        guard cost > 0 else { return 0 }
        return totalGainLoss(assets: assets) / cost * 100
    }

    func assetValueTRY(_ asset: Asset) -> Double {
        toTRY(asset.totalValue, currency: asset.currency)
    }

    // MARK: - Currency conversion

    func toTRY(_ amount: Double, currency: String) -> Double {
        switch currency.uppercased() {
        case "USD": return amount * usdTry
        case "EUR": return amount * eurTry
        case "GBP": return amount * gbpTry
        default: return amount
        }
    }

    // MARK: - Price refresh

    func refreshPrices(assets: [Asset]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Always fetch major TRY rates plus all asset tickers
        var symbols: Set<String> = ["USDTRY=X", "EURTRY=X", "GBPTRY=X"]
        for asset in assets where !asset.ticker.isEmpty && !asset.isManualPrice {
            symbols.insert(asset.ticker.uppercased())
        }

        do {
            let quotes = try await PriceService.shared.fetchQuotes(for: Array(symbols))

            // Update exchange rates
            usdTry = quotes["USDTRY=X"]?.regularMarketPrice ?? usdTry
            eurTry = quotes["EURTRY=X"]?.regularMarketPrice ?? eurTry
            gbpTry = quotes["GBPTRY=X"]?.regularMarketPrice ?? gbpTry

            // Update each asset's current price
            for asset in assets where !asset.ticker.isEmpty && !asset.isManualPrice {
                if let price = quotes[asset.ticker.uppercased()]?.regularMarketPrice {
                    asset.currentPrice = price
                    asset.lastUpdated = Date()
                }
            }

            lastUpdated = Date()
        } catch {
            errorMessage = "Fiyatlar güncellenemedi: \(error.localizedDescription)"
        }
    }
}
