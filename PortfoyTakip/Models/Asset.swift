import SwiftData
import Foundation

@Model
final class Asset {
    var id: UUID
    var name: String
    /// Yahoo Finance symbol (e.g. THYAO.IS, USDTRY=X). Empty = manual price.
    var ticker: String
    var typeRaw: String
    var quantity: Double
    var purchasePrice: Double
    /// Currency in which purchase price & current price are expressed (TRY / USD / EUR / GBP)
    var currency: String
    var currentPrice: Double
    var lastUpdated: Date?
    var addedDate: Date
    var notes: String
    /// True when price is set manually by the user (ticker is empty or user overrides)
    var isManualPrice: Bool

    init(
        name: String,
        ticker: String,
        type: AssetType,
        quantity: Double,
        purchasePrice: Double,
        currency: String = "TRY",
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.ticker = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        self.typeRaw = type.rawValue
        self.quantity = quantity
        self.purchasePrice = purchasePrice
        self.currency = currency
        self.currentPrice = purchasePrice
        self.addedDate = Date()
        self.notes = notes
        self.isManualPrice = ticker.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var type: AssetType {
        AssetType(rawValue: typeRaw) ?? .diger
    }

    var totalCost: Double { quantity * purchasePrice }
    var totalValue: Double { quantity * currentPrice }
    var gainLoss: Double { totalValue - totalCost }

    var gainLossPercentage: Double {
        guard totalCost > 0 else { return 0 }
        return (gainLoss / totalCost) * 100
    }
}
