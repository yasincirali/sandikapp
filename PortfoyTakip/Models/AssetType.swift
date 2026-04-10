import SwiftUI

enum AssetType: String, CaseIterable, Codable {
    case hisse = "Hisse"
    case fon = "Fon"
    case doviz = "Döviz"
    case altin = "Altın"
    case emtia = "Emtia"
    case diger = "Diğer"

    var icon: String {
        switch self {
        case .hisse: return "chart.line.uptrend.xyaxis"
        case .fon: return "chart.pie.fill"
        case .doviz: return "dollarsign.circle.fill"
        case .altin: return "star.circle.fill"
        case .emtia: return "cube.box.fill"
        case .diger: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .hisse: return .blue
        case .fon: return .purple
        case .doviz: return .green
        case .altin: return Color(red: 0.8, green: 0.65, blue: 0.1)
        case .emtia: return .orange
        case .diger: return .gray
        }
    }

    var defaultCurrency: String {
        switch self {
        case .hisse: return "TRY"
        case .fon: return "TRY"
        case .doviz: return "USD"
        case .altin: return "TRY"
        case .emtia: return "USD"
        case .diger: return "TRY"
        }
    }

    /// Hint shown under the ticker field in AddAssetView
    var tickerHint: String {
        switch self {
        case .hisse: return "Örn: THYAO.IS, GARAN.IS (Borsa İstanbul için .IS ekleyin)"
        case .fon: return "Yahoo Finance kodu yoksa boş bırakın, fiyatı manuel girin"
        case .doviz: return "Örn: USDTRY=X, EURTRY=X, GBPTRY=X"
        case .altin: return "Örn: XAUTRY=X (gram altın TL) veya GC=F (ons, USD)"
        case .emtia: return "Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)"
        case .diger: return "Yahoo Finance sembolü veya boş bırakın"
        }
    }
}
