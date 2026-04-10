import 'dart:convert';
import 'package:http/http.dart' as http;

class YahooQuote {
  final String symbol;
  final double? regularMarketPrice;
  final String? currency;
  final double? regularMarketChangePercent;

  const YahooQuote({
    required this.symbol,
    this.regularMarketPrice,
    this.currency,
    this.regularMarketChangePercent,
  });

  factory YahooQuote.fromJson(Map<String, dynamic> j) => YahooQuote(
        symbol: j['symbol'] as String,
        regularMarketPrice: (j['regularMarketPrice'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        regularMarketChangePercent:
            (j['regularMarketChangePercent'] as num?)?.toDouble(),
      );
}

class PriceService {
  static final PriceService instance = PriceService._();
  PriceService._();

  final _client = http.Client();

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    'Accept': 'application/json',
  };

  Future<Map<String, YahooQuote>> fetchQuotes(List<String> symbols) async {
    final cleaned =
        symbols.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (cleaned.isEmpty) return {};

    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v7/finance/quote'
      '?symbols=${cleaned.join(",")}'
      '&fields=regularMarketPrice,currency,shortName,regularMarketChangePercent',
    );

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results =
        (body['quoteResponse']?['result'] as List?) ?? [];

    return {
      for (final q in results.cast<Map<String, dynamic>>())
        (q['symbol'] as String).toUpperCase(): YahooQuote.fromJson(q),
    };
  }
}
