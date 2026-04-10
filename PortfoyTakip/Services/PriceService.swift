import Foundation

// MARK: - Yahoo Finance API Models

struct YahooFinanceResponse: Decodable {
    let quoteResponse: QuoteResult

    struct QuoteResult: Decodable {
        let result: [YahooQuote]?
    }
}

struct YahooQuote: Decodable {
    let symbol: String
    let regularMarketPrice: Double?
    let currency: String?
    let shortName: String?
    let regularMarketChangePercent: Double?
}

// MARK: - PriceService

actor PriceService {
    static let shared = PriceService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "Accept": "application/json"
        ]
        return URLSession(configuration: config)
    }()

    /// Fetches real-time quotes for the given Yahoo Finance symbols.
    /// Returns a dictionary keyed by symbol.
    func fetchQuotes(for symbols: [String]) async throws -> [String: YahooQuote] {
        let cleaned = symbols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [:] }

        let joined = cleaned.joined(separator: ",")
        let urlString = "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(joined)&fields=regularMarketPrice,currency,shortName,regularMarketChangePercent"
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(YahooFinanceResponse.self, from: data)
        var result: [String: YahooQuote] = [:]
        for quote in decoded.quoteResponse.result ?? [] {
            result[quote.symbol.uppercased()] = quote
        }
        return result
    }
}
