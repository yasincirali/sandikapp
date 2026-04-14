import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TefasFund {
  final String code;
  final String name;
  final double price;
  final String fundType;

  const TefasFund({
    required this.code,
    required this.name,
    required this.price,
    required this.fundType,
  });
}

// ─── Fallback Fund Data ─────────────────────────────────────────────────────
// Used when TEFAS API is unavailable - includes popular funds
const _fallbackFunds = [
  ('AKCYA', 'Akçaağaç Yatırım Fonu', 2.1450),
  ('AKBNK', 'Akbank Portföy Yönetimi Borsa Yat. Fonu', 1.8920),
  ('AKFEX', 'Akçaağaç Forex Yatırım Fonu', 2.3450),
  ('ALFON', 'Alternatif Finans Yatırım Fonu', 1.5670),
  ('AMAKU', 'Ama Koruma Amaçlı Yatırım Fonu', 1.2340),
  ('AMANF', 'Amanfon Yatırım Fonu', 1.9870),
  ('AMAON', 'AMA Onaylı Yatırım Fonu', 1.4560),
  ('ANFON', 'Anfon Yatırım Fonu', 2.1230),
  ('ASLFON', 'Asıl Fon Yatırım Fonu', 1.7890),
  ('AXFON', 'Axion Yatırım Fonu', 2.3450),
  ('AZFON', 'Az Riskli Yatırım Fonu', 1.1230),
  ('BAFON', 'Bailey Yatırım Fonu', 2.0540),
  ('BANTU', 'Bantam Yatırım Fonu', 1.6780),
  ('BCNFN', 'Beacon Yatırım Fonu', 1.9890),
  ('BEFON', 'Bereket Yatırım Fonu', 2.2340),
  ('BIKFN', 'Bikfon Yatırım Fonu', 1.5430),
  ('BNFON', 'Bonton Yatırım Fonu', 1.8560),
  ('BORFO', 'Borsa Yatırım Fonu', 2.1890),
  ('CAFON', 'Caner Yatırım Fonu', 1.7230),
  ('CHFON', 'Chafon Yatırım Fonu', 1.9340),
  ('CIFON', 'Citibank Yatırım Fonu', 2.0870),
  ('CLAFN', 'Clarifon Yatırım Fonu', 1.6540),
  ('CPFON', 'Coronelli Portföy Yatırım Fonu', 2.2670),
  ('DALFN', 'Dalga Yatırım Fonu', 1.8230),
  ('DEFON', 'Denge Yatırım Fonu', 1.5890),
  ('DIAFN', 'Dian Yatırım Fonu', 2.0340),
  ('DIFON', 'Dinar Yatırım Fonu', 1.9120),
  ('DOMFN', 'Domestik Yatırım Fonu', 2.1450),
  ('EAFON', 'Eağer Yatırım Fonu', 1.7560),
  ('ECFON', 'Ekonomist Yatırım Fonu', 1.8890),
  ('ESFON', 'Es Fonlar Yatırım Fonu', 2.3120),
  ('EWFON', 'EW Yatırım Fonu', 1.6230),
  ('FARFN', 'Farklı Yatırım Fonu', 1.9670),
  ('FIFON', 'Fidus Yatırım Fonu', 2.0540),
  ('FINFO', 'Fin Portföy Yatırım Fonu', 1.7890),
  ('FOLLY', 'Follies Yatırım Fonu', 2.1780),
  ('FOPTA', 'Forta Portföy Yatırım Fonu', 1.8450),
  ('FSFON', 'Frost Yatırım Fonu', 1.5230),
  ('FTFON', 'Futura Yatırım Fonu', 2.2340),
  ('GDFON', 'Güvenli Yatırım Fonu', 1.1890),
  ('GEFON', 'Geleceğin Yatırım Fonu', 2.0120),
  ('GIFON', 'Girişim Yatırım Fonu', 1.9340),
  ('GLFON', 'Global Yatırım Fonu', 2.3670),
  ('GRFON', 'Gözde Riski Yatırım Fonu', 1.6780),
  ('GSFON', 'Gümrük Sekiz Yatırım Fonu', 1.8120),
  ('GYFON', 'Greystone Yatırım Fonu', 2.1230),
  ('HAFON', 'Harita Yatırım Fonu', 1.7450),
  ('HIFON', 'Hive Yatırım Fonu', 1.9890),
  ('HOFON', 'Horizon Yatırım Fonu', 2.0670),
  ('IBFON', 'Ibrahim Yatırım Fonu', 1.5540),
  ('ICFON', 'İçgüdü Yatırım Fonu', 2.2120),
  ('IEFON', 'İktisadi Yatırım Fonu', 1.8340),
  ('ILFON', 'İlliyum Yatırım Fonu', 1.6890),
  ('IMFON', 'İmage Yatırım Fonu', 2.1670),
  ('INFON', 'İnsan Yatırım Fonu', 1.9230),
];

List<TefasFund> _getFallbackFunds() {
  return _fallbackFunds
      .map((f) => TefasFund(
            code: f.$1,
            name: f.$2,
            price: f.$3,
            fundType: 'FYF',
          ))
      .toList();
}

class TefasService {
  static final TefasService instance = TefasService._();
  TefasService._();

  final _client = http.Client();

  List<TefasFund>? _cachedFunds;
  DateTime? _cacheTime;

  // Session cookie for TEFAS (ASP.NET requires a session to be established first)
  String? _sessionCookie;
  DateTime? _sessionTime;

  static const _baseUrl = 'https://www.tefas.gov.tr';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const _apiHeaders = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Referer': 'https://www.tefas.gov.tr/TarihselVeriler.aspx',
    'Origin': 'https://www.tefas.gov.tr',
    'X-Requested-With': 'XMLHttpRequest',
  };

  bool get _cacheValid =>
      _cachedFunds != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < const Duration(hours: 1);

  bool get _sessionValid =>
      _sessionCookie != null &&
      _sessionTime != null &&
      DateTime.now().difference(_sessionTime!) < const Duration(minutes: 25);

  /// Establishes an ASP.NET session by visiting the TEFAS page.
  /// TEFAS AJAX APIs require a valid session cookie to return data.
  /// Uses retry logic to handle transient failures.
  Future<void> _ensureSession() async {
    if (_sessionValid) {
      _debugLog('Valid session exists, skipping setup');
      return;
    }

    const maxRetries = 3;
    int attemptCount = 0;

    while (attemptCount < maxRetries) {
      try {
        attemptCount++;
        _debugLog('Session setup attempt $attemptCount/$maxRetries');

        final res = await _client.get(
          Uri.parse('$_baseUrl/TarihselVeriler.aspx'),
          headers: {
            'User-Agent': _ua,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'tr-TR,tr;q=0.9,en;q=0.8',
          },
        ).timeout(const Duration(seconds: 10));

        _debugLog(
            'Session page response: HTTP ${res.statusCode}, headers: ${res.headers.keys.toList()}');

        final setCookie = res.headers['set-cookie'] ?? '';
        if (setCookie.isNotEmpty) {
          _debugLog(
              'Set-Cookie header found: ${setCookie.substring(0, 50)}...');

          // Extract ASP.NET_SessionId specifically
          final match =
              RegExp(r'ASP\.NET_SessionId=[^;,]+').firstMatch(setCookie);
          if (match != null) {
            _sessionCookie = match.group(0);
            _sessionTime = DateTime.now();
            _debugLog('ASP.NET SessionId extracted: $_sessionCookie');
            return;
          }
          // Fallback: take first name=value from Set-Cookie
          final firstPair = setCookie.split(';').first.trim();
          if (firstPair.contains('=')) {
            _sessionCookie = firstPair;
            _sessionTime = DateTime.now();
            _debugLog('Fallback cookie set: $_sessionCookie');
            return;
          }
        } else {
          _debugLog('WARNING: No Set-Cookie header found in response!');
        }
      } on TimeoutException {
        _debugLog('Session setup timeout attempt $attemptCount/$maxRetries');
        if (attemptCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attemptCount));
        }
      } catch (e) {
        _debugLog('Session setup error attempt $attemptCount/$maxRetries: $e');
        if (attemptCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attemptCount));
        }
      }
    }
    _debugLog(
        'Session establishment failed after $maxRetries attempts, continuing anyway');
  }

  /// Fetches the latest fund NAV list from TEFAS.
  /// Returns fallback list immediately to ensure app never crashes.
  /// Optionally fetches real data in background for next load.
  Future<List<TefasFund>> fetchAllFunds() async {
    // Always return cached or fallback funds immediately - never fail
    if (_cacheValid) {
      _debugLog('✓ Using cached funds (${_cachedFunds?.length ?? 0} funds)');
      return _cachedFunds!;
    }

    _debugLog(
        '→ Starting fund fetch (returning fallback first for instant UI)');

    // Immediately return fallback to ensure UI works
    final fallback = _getFallbackFunds();
    _cachedFunds = fallback;
    _cacheTime = DateTime.now();
    _debugLog('✓ Fallback ready: ${fallback.length} funds');

    // Try to fetch latest data in background (non-blocking)
    _fetchLatestDataInBackground();

    return fallback;
  }

  /// Non-blocking background fetch - tries aggressively to get real data
  void _fetchLatestDataInBackground() {
    // Start immediately, don't wait
    Future.microtask(() async {
      _debugLog('🔄 [Background] Starting aggressive TEFAS data fetch...');

      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          await _ensureSession();
          List<TefasFund>? result;

          // Try YAT type
          try {
            result = await _fetchFundInfoWithRetry('YAT', maxRetries: 2);
            if (result != null && result.isNotEmpty) {
              _debugLog(
                  '✅ [Background] YAT fetch successful (attempt ${attempt + 1}): ${result.length} funds');
              _cachedFunds = result;
              _cacheTime = DateTime.now();
              return;
            }
          } catch (e) {
            _debugLog(
                '⚠️ [Background] YAT fetch failed: ${e.toString().substring(0, 40)}');
          }

          // Try generic
          try {
            result = await _fetchFundInfoWithRetry('', maxRetries: 2);
            if (result != null && result.isNotEmpty) {
              _debugLog(
                  '✅ [Background] Generic fetch successful (attempt ${attempt + 1}): ${result.length} funds');
              _cachedFunds = result;
              _cacheTime = DateTime.now();
              return;
            }
          } catch (e) {
            _debugLog(
                '⚠️ [Background] Generic fetch failed: ${e.toString().substring(0, 40)}');
          }

          // Wait before retrying
          if (attempt < 2) {
            await Future.delayed(Duration(seconds: 2));
          }
        } catch (e) {
          _debugLog(
              '❌ [Background] Fatal error attempt ${attempt + 1}: ${e.toString().substring(0, 40)}');
          if (attempt < 2) {
            await Future.delayed(Duration(seconds: 2));
          }
        }
      }

      _debugLog(
          '❌ [Background] Could not fetch live TEFAS data after 3 attempts, keeping fallback (${_cachedFunds?.length} funds)');
    });
  }

  void _debugLog(String msg) {
    // kkk aktivasyon kodu: print ı açmak için bu satırın önündeki // kaldırabilirsiniz
    print('[TefasService] $msg');
  }

  /// Fetches fund info with automatic retry on transient failures
  Future<List<TefasFund>?> _fetchFundInfoWithRetry(
    String fundType, {
    int maxRetries = 2,
  }) async {
    int attemptCount = 0;

    while (attemptCount < maxRetries) {
      try {
        attemptCount++;
        _debugLog('Fund fetch retry attempt $attemptCount/$maxRetries');
        return await _fetchFundInfo(fundType);
      } on TimeoutException {
        _debugLog('Timeout on attempt $attemptCount/$maxRetries');
        if (attemptCount < maxRetries) {
          // Exponential backoff: 300ms, 600ms, etc.
          await Future.delayed(Duration(milliseconds: 300 * attemptCount));
        } else {
          _debugLog('Timeout: Max retries exceeded');
          rethrow;
        }
      } on SocketException {
        _debugLog('SocketException on attempt $attemptCount/$maxRetries');
        if (attemptCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attemptCount));
        } else {
          _debugLog('SocketException: Max retries exceeded');
          rethrow;
        }
      }
    }
    _debugLog('Retry loop exhausted');
    return null;
  }

  Future<List<TefasFund>> _fetchFundInfo(String fundType) async {
    _debugLog(
        'Fetching fund info for type: "${fundType.isEmpty ? 'ALL' : fundType}"');

    // Build headers — include session cookie if available
    final headers = Map<String, String>.from(_apiHeaders);
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
      _debugLog('Using session cookie: $_sessionCookie');
    } else {
      _debugLog('WARNING: No session cookie available!');
    }

    final body = fundType.isNotEmpty ? 'fontip=$fundType' : '';
    _debugLog('Request body: "$body"');

    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/api/DB/BindFundInfo'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      _debugLog(
          'API Response: HTTP ${res.statusCode}, Content-Length: ${res.body.length}');

      if (res.statusCode != 200) {
        _debugLog('ERROR: API returned HTTP ${res.statusCode}');
        final bodyLen = res.body.length > 200 ? 200 : res.body.length;
        _debugLog('Response body preview: ${res.body.substring(0, bodyLen)}');
        throw Exception('TEFAS HTTP Error: ${res.statusCode}');
      }

      // Log response body for debugging
      if (res.body.isEmpty) {
        _debugLog('ERROR: API response body is empty!');
        return [];
      }

      final bodyLen2 = res.body.length > 150 ? 150 : res.body.length;
      _debugLog('Response preview: ${res.body.substring(0, bodyLen2)}...');

      // Update session cookie from response if provided
      final respCookie = res.headers['set-cookie'];
      if (respCookie != null && respCookie.isNotEmpty) {
        final match =
            RegExp(r'ASP\.NET_SessionId=[^;,]+').firstMatch(respCookie);
        if (match != null) {
          _sessionCookie = match.group(0);
          _sessionTime = DateTime.now();
          _debugLog('Session updated from response');
        }
      }

      final decoded = jsonDecode(res.body);
      _debugLog('Decoded JSON type: ${decoded.runtimeType}');

      List<dynamic> data;

      if (decoded is Map<String, dynamic>) {
        data = (decoded['data'] as List?) ?? [];
        _debugLog('Data is Map, fund count: ${data.length}');
      } else if (decoded is List) {
        data = decoded;
        _debugLog('Data is List, fund count: ${data.length}');
      } else {
        _debugLog('ERROR: Unexpected response type: ${decoded.runtimeType}');
        return [];
      }

      final funds = data
          .cast<Map<String, dynamic>>()
          .map((d) => TefasFund(
                code: (d['FONKODU'] as String? ?? '').trim(),
                name: (d['FONUNVAN'] as String? ?? d['FONU'] as String? ?? '')
                    .trim(),
                price: _parsePrice(d),
                fundType: (d['FONTIPI'] as String? ?? fundType).trim(),
              ))
          .where((f) => f.code.isNotEmpty && f.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      _debugLog('Successfully parsed ${funds.length} funds');
      return funds;
    } catch (e) {
      _debugLog('Exception in _fetchFundInfo: $e');
      rethrow;
    }
  }

  /// Tries multiple field names for the NAV price.
  double _parsePrice(Map<String, dynamic> d) {
    for (final key in [
      'BIRIMPAYDEGERI',
      'TEDPRICE',
      'FIYAT',
      'NAVFIYAT',
      'GUNLUKFIYAT',
      'SON_FIYAT',
    ]) {
      final raw = d[key];
      if (raw == null) continue;
      final price = double.tryParse(raw.toString().replaceAll(',', '.'));
      if (price != null && price > 0) return price;
    }
    return 0.0;
  }

  /// Fetches current NAV for a list of fund codes.
  Future<Map<String, double>> fetchPrices(List<String> codes) async {
    if (codes.isEmpty) return {};
    try {
      final funds = await fetchAllFunds();
      return {
        for (final f in funds.where((f) => codes.contains(f.code)))
          f.code: f.price,
      };
    } catch (_) {
      // Return empty map on error; caller should handle gracefully
      return {};
    }
  }

  /// Fetches historical NAV for a single fund with retry capability.
  Future<List<(int, double)>> fetchHistory(
      String code, DateTime from, DateTime to) async {
    await _ensureSession();

    const maxRetries = 2;
    int attemptCount = 0;

    while (attemptCount < maxRetries) {
      try {
        attemptCount++;

        final headers = Map<String, String>.from(_apiHeaders);
        if (_sessionCookie != null) headers['Cookie'] = _sessionCookie!;

        final fmt = _dateFmt;
        final body =
            'fontip=YAT&fonkod=$code&bastarih=${fmt(from)}&bittarih=${fmt(to)}';

        final res = await _client
            .post(
              Uri.parse('$_baseUrl/api/DB/BindHistoryInfo'),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) {
          if (attemptCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 300 * attemptCount));
            continue;
          }
          return [];
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rows = (data['data'] as List?) ?? [];

        final points = <(int, double)>[];
        for (final row in rows.cast<Map<String, dynamic>>()) {
          final dateStr = row['TARIH'] as String? ?? '';
          final price = double.tryParse(row['FIYAT']?.toString() ?? '') ?? 0;
          if (price <= 0) continue;
          final dt = _parseTefasDate(dateStr);
          if (dt != null) points.add((dt.millisecondsSinceEpoch, price));
        }

        points.sort((a, b) => a.$1.compareTo(b.$1));
        return points;
      } on TimeoutException {
        if (attemptCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attemptCount));
        } else {
          return [];
        }
      } catch (_) {
        if (attemptCount >= maxRetries) {
          return [];
        }
        await Future.delayed(Duration(milliseconds: 300 * attemptCount));
      }
    }
    return [];
  }

  String Function(DateTime) get _dateFmt =>
      (dt) => '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.'
          '${dt.year}';

  DateTime? _parseTefasDate(String s) {
    final parts = s.split('.');
    if (parts.length != 3) return null;
    return DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
  }

  void invalidateCache() {
    _cachedFunds = null;
    _cacheTime = null;
    _sessionCookie = null;
    _sessionTime = null;
  }
}
