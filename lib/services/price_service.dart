import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tefas_service.dart';

class YahooQuote {
  final String symbol;
  final double? regularMarketPrice;
  final String? currency;
  final double? regularMarketChangePercent;
  final String? shortName;
  final String? longName;

  const YahooQuote({
    required this.symbol,
    this.regularMarketPrice,
    this.currency,
    this.regularMarketChangePercent,
    this.shortName,
    this.longName,
  });

  factory YahooQuote.fromJson(Map<String, dynamic> j) => YahooQuote(
        symbol: j['symbol'] as String,
        regularMarketPrice: (j['regularMarketPrice'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        regularMarketChangePercent:
            (j['regularMarketChangePercent'] as num?)?.toDouble(),
        shortName: j['shortName'] as String?,
        longName: j['longName'] as String?,
      );

  String get companyName => shortName ?? longName ?? symbol;
}

class PriceService {
  static final PriceService instance = PriceService._();
  PriceService._();

  final _client = http.Client();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  // FX pairs handled by open.er-api.com (fallback)
  static const _fxSymbols = {'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};

  // Turkish gold symbols → finans.truncgil.com key names
  static const _truncgilGoldKeys = <String, String>{
    'ALTIN_GRAM': 'Gram Altın',
    'ALTIN_CEYREK': 'Çeyrek Altın',
    'ALTIN_YARIM': 'Yarım Altın',
    'ALTIN_CUMHURIYET': 'Cumhuriyet Altını',
    'ALTIN_ATA': 'Ata Altını',
    'ALTIN_RESAT': 'Reşat Altını',
  };

  // Fallback gold weights in 22K grams (used with Yahoo GC=F if truncgil fails)
  static const _goldWeights = <String, double>{
    'ALTIN_GRAM': 1.0,
    'ALTIN_CEYREK': 1.75,
    'ALTIN_YARIM': 3.5,
    'ALTIN_CUMHURIYET': 7.216,
    'ALTIN_ATA': 7.216,
    'ALTIN_RESAT': 7.216,
  };

  static const _tefasPrefix = 'TEFAS:';

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<Map<String, YahooQuote>> fetchQuotes(List<String> symbols) async {
    final cleaned = symbols
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return {};

    final fxList = cleaned.where((s) => _fxSymbols.contains(s)).toList();
    final goldList =
        cleaned.where((s) => _truncgilGoldKeys.containsKey(s)).toList();
    final tefasList =
        cleaned.where((s) => s.startsWith(_tefasPrefix)).toList();
    final yahooList = cleaned
        .where((s) =>
            !_fxSymbols.contains(s) &&
            !_truncgilGoldKeys.containsKey(s) &&
            !s.startsWith(_tefasPrefix))
        .toList();

    final results = <String, YahooQuote>{};

    // ── Step 1: Fetch truncgil ONCE for both FX and gold ───────────────────
    if (fxList.isNotEmpty || goldList.isNotEmpty) {
      Map<String, dynamic>? truncgilData;
      try {
        truncgilData = await _fetchTruncgilData();
      } catch (_) {}

      // FX from truncgil
      if (fxList.isNotEmpty && truncgilData != null) {
        try {
          results.addAll(_extractFx(truncgilData));
        } catch (_) {}
      }

      // FX fallback: open.er-api.com
      if (fxList.isNotEmpty && !results.containsKey('USDTRY=X')) {
        try {
          results.addAll(await _fetchFxErApi());
        } catch (_) {}
      }

      // Gold from truncgil
      if (goldList.isNotEmpty && truncgilData != null) {
        try {
          results.addAll(_extractGold(goldList, truncgilData));
        } catch (_) {}
      }

      // Gold fallback: Yahoo GC=F + USD/TRY calculation
      final missingGold =
          goldList.where((s) => !results.containsKey(s)).toList();
      if (missingGold.isNotEmpty) {
        final usdTry = results['USDTRY=X']?.regularMarketPrice ?? 0;
        if (usdTry > 0) {
          try {
            results.addAll(await _fetchGoldFallback(missingGold, usdTry));
          } catch (_) {}
        }
      }
    }

    // ── Step 2: TEFAS + Yahoo in parallel ─────────────────────────────────
    await Future.wait([
      if (tefasList.isNotEmpty)
        _fetchTefas(tefasList).then(results.addAll).catchError((_) {}),
      if (yahooList.isNotEmpty)
        _fetchYahoo(yahooList).then(results.addAll).catchError((_) {}),
    ]);

    return results;
  }

  // ── finans.truncgil.com — primary source for Turkish gold + FX ───────────

  Future<Map<String, dynamic>> _fetchTruncgilData() async {
    final res = await _client
        .get(
          Uri.parse('https://finans.truncgil.com/v4/today.json'),
          headers: {'Accept': 'application/json', 'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Truncgil HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  double _parseTruncgilValue(dynamic entry) {
    if (entry is! Map) return 0;
    final raw =
        (entry['Alış'] ?? entry['Satış'] ?? '').toString();
    return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }

  Map<String, YahooQuote> _extractFx(Map<String, dynamic> data) {
    final usdTry = _parseTruncgilValue(data['USD']);
    final eurTry = _parseTruncgilValue(data['EUR']);
    final gbpTry = _parseTruncgilValue(data['GBP']);
    if (usdTry <= 0) throw Exception('USD rate missing from Truncgil');
    return {
      'USDTRY=X': _fxQ('USDTRY=X', usdTry),
      'EURTRY=X': _fxQ('EURTRY=X', eurTry > 0 ? eurTry : usdTry * 1.1),
      'GBPTRY=X': _fxQ('GBPTRY=X', gbpTry > 0 ? gbpTry : usdTry * 1.28),
    };
  }

  Map<String, YahooQuote> _extractGold(
      List<String> goldSymbols, Map<String, dynamic> data) {
    final result = <String, YahooQuote>{};
    for (final sym in goldSymbols) {
      final key = _truncgilGoldKeys[sym];
      if (key == null) continue;
      final price = _parseTruncgilValue(data[key]);
      if (price > 0) {
        result[sym] = YahooQuote(
          symbol: sym,
          regularMarketPrice: price,
          currency: 'TRY',
          shortName: _goldLabel(sym),
        );
      }
    }
    return result;
  }

  // ── FX fallback — open.er-api.com ─────────────────────────────────────────

  Future<Map<String, YahooQuote>> _fetchFxErApi() async {
    final res = await _client
        .get(Uri.parse('https://open.er-api.com/v6/latest/USD'),
            headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('FX HTTP ${res.statusCode}');
    final rates = (jsonDecode(res.body) as Map<String, dynamic>)['rates']
        as Map<String, dynamic>;
    final usdTry = (rates['TRY'] as num?)?.toDouble() ?? 0;
    final usdEur = (rates['EUR'] as num?)?.toDouble() ?? 1;
    final usdGbp = (rates['GBP'] as num?)?.toDouble() ?? 1;
    if (usdTry == 0) throw Exception('TRY rate missing');
    return {
      'USDTRY=X': _fxQ('USDTRY=X', usdTry),
      'EURTRY=X': _fxQ('EURTRY=X', usdTry / usdEur),
      'GBPTRY=X': _fxQ('GBPTRY=X', usdTry / usdGbp),
    };
  }

  YahooQuote _fxQ(String symbol, double price) =>
      YahooQuote(symbol: symbol, regularMarketPrice: price, currency: 'TRY');

  // ── Gold fallback — Yahoo GC=F + USD/TRY ─────────────────────────────────

  Future<Map<String, YahooQuote>> _fetchGoldFallback(
      List<String> goldSymbols, double usdTry) async {
    final q = await _fetchOneChart('GC=F');
    final xauUsd = q?.regularMarketPrice;
    if (xauUsd == null || xauUsd <= 500) {
      throw Exception('GC=F unavailable');
    }
    final xauTry = xauUsd * usdTry;
    final gram22k = xauTry / 31.1035 * (22 / 24);
    return {
      for (final sym in goldSymbols)
        sym: YahooQuote(
          symbol: sym,
          regularMarketPrice: gram22k * (_goldWeights[sym] ?? 1.0),
          currency: 'TRY',
          shortName: _goldLabel(sym),
        ),
    };
  }

  String _goldLabel(String sym) => switch (sym) {
        'ALTIN_GRAM' => 'Gram Altın (22K)',
        'ALTIN_CEYREK' => 'Çeyrek Altın',
        'ALTIN_YARIM' => 'Yarım Altın',
        'ALTIN_CUMHURIYET' => 'Cumhuriyet Altını',
        'ALTIN_ATA' => 'Ata Altını',
        'ALTIN_RESAT' => 'Reşat Altını',
        _ => sym,
      };

  // ── TEFAS funds ────────────────────────────────────────────────────────────

  Future<Map<String, YahooQuote>> _fetchTefas(List<String> tefasSymbols) async {
    final codes =
        tefasSymbols.map((s) => s.replaceFirst(_tefasPrefix, '')).toList();
    final prices = await TefasService.instance.fetchPrices(codes);
    return {
      for (final entry in prices.entries)
        '$_tefasPrefix${entry.key}': YahooQuote(
          symbol: '$_tefasPrefix${entry.key}',
          regularMarketPrice: entry.value,
          currency: 'TRY',
        ),
    };
  }

  // ── Yahoo Finance — stocks, crypto, commodities ────────────────────────────

  Future<Map<String, YahooQuote>> _fetchYahoo(List<String> symbols) async {
    try {
      final bulk = await _fetchBulk(symbols);
      if (bulk.isNotEmpty) return bulk;
    } catch (_) {}
    return _fetchChartAll(symbols);
  }

  Future<Map<String, YahooQuote>> _fetchBulk(List<String> symbols) async {
    final uri = Uri.https('query1.finance.yahoo.com', '/v7/finance/quote', {
      'symbols': symbols.join(','),
      'lang': 'en-US',
      'region': 'US',
      'corsDomain': 'finance.yahoo.com',
      'fields':
          'regularMarketPrice,currency,shortName,longName,regularMarketChangePercent',
    });

    final res = await _client
        .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) throw Exception('Bulk HTTP ${res.statusCode}');

    final parsed = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (parsed['quoteResponse']?['result'] as List?) ?? [];
    if (list.isEmpty) throw Exception('Empty bulk');

    return {
      for (final q in list.cast<Map<String, dynamic>>())
        (q['symbol'] as String).toUpperCase(): YahooQuote.fromJson(q),
    };
  }

  Future<Map<String, YahooQuote>> _fetchChartAll(List<String> symbols) async {
    final quotes = await Future.wait(symbols.map(_fetchOneChart));
    return {
      for (final q in quotes)
        if (q != null) q.symbol.toUpperCase(): q,
    };
  }

  Future<YahooQuote?> _fetchOneChart(String symbol) async {
    try {
      final uri = Uri.https(
          'query1.finance.yahoo.com',
          '/v8/finance/chart/$symbol',
          {'interval': '1d', 'range': '1d', 'includePrePost': 'false'});

      final res = await _client
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = (body['chart']?['result'] as List?)?.firstOrNull
          as Map<String, dynamic>?;
      if (result == null) return null;

      final m = result['meta'] as Map<String, dynamic>?;
      final price = (m?['regularMarketPrice'] as num?)?.toDouble();
      if (price == null) return null;

      return YahooQuote(
        symbol: symbol,
        regularMarketPrice: price,
        currency: m?['currency'] as String?,
        shortName: m?['shortName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Historical data for charts ─────────────────────────────────────────────

  Future<List<(int, double)>> fetchHistory(
      String symbol, String range) async {
    final interval = _intervalFor(range);

    final uri = Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/$symbol',
        {'interval': interval, 'range': range, 'includePrePost': 'false'});

    final res = await _client
        .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return [];

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result =
        (body['chart']?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
    if (result == null) return [];

    final timestamps = (result['timestamp'] as List?)?.cast<int>() ?? [];
    final closes = ((result['indicators']?['quote'] as List?)?.firstOrNull
            as Map<String, dynamic>?)?['close']
        ?.cast<dynamic>() ?? [];

    final points = <(int, double)>[];
    for (var i = 0; i < timestamps.length && i < closes.length; i++) {
      final price = (closes[i] as num?)?.toDouble();
      if (price != null && price > 0) {
        points.add((timestamps[i] * 1000, price));
      }
    }
    return points;
  }

  String _intervalFor(String range) => switch (range) {
        '1d' => '5m',
        '5d' => '30m',
        '1mo' => '1d',
        '3mo' => '1d',
        '6mo' => '1wk',
        '1y' => '1wk',
        _ => '1d',
      };
}
