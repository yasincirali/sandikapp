import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TefasFund {
  final String code;
  final String name;
  final double price;
  final String fundType;       // YAT, EMK, BYF
  final String managerName;    // Portföy yönetim şirketi (fonUnvan'dan parse)
  final double? return1m;      // 1 aylık getiri
  final double? return3m;
  final double? return6m;
  final double? return1y;
  final double? returnYtd;
  final int? riskLevel;        // 1-7

  const TefasFund({
    required this.code,
    required this.name,
    required this.price,
    required this.fundType,
    required this.managerName,
    this.return1m,
    this.return3m,
    this.return6m,
    this.return1y,
    this.returnYtd,
    this.riskLevel,
  });
}

class TefasService {
  static final TefasService instance = TefasService._();
  TefasService._();

  final _client = http.Client();

  List<TefasFund>? _cachedFunds;
  DateTime? _cacheTime;

  static const _baseUrl = 'https://www.tefas.gov.tr';
  static const _listEndpoint  = '/api/funds/fonGetiriBazliBilgiGetir';
  static const _priceEndpoint = '/api/funds/fonFiyatBilgiGetir';

  static const _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36',
  };

  // 1 saatlik cache — fiyatlar gün içinde çok değişmez
  bool get _cacheValid =>
      _cachedFunds != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < const Duration(hours: 1);

  // ── Tüm fonları çek ───────────────────────────────────────────────────────

  /// 1007+ TEFAS fonunu portföy yönetim şirketi ve performans verileriyle döner.
  /// İlk çağrıda cache boşsa ağdan çeker; sonrasında cache'ten döner.
  Future<List<TefasFund>> fetchAllFunds({bool forceRefresh = false}) async {
    if (!forceRefresh && _cacheValid) return _cachedFunds!;

    try {
      final funds = await _fetchFundList('YAT');
      if (funds.isNotEmpty) {
        _cachedFunds = funds;
        _cacheTime = DateTime.now();
        return funds;
      }
    } catch (e) {
      _log('fetchAllFunds error: $e');
    }

    // Cache varsa eski veriyle devam et
    if (_cachedFunds != null) return _cachedFunds!;
    return [];
  }

  /// Belirli fon kodları için güncel NAV fiyatlarını çeker.
  /// [codes] listesindeki her kod için ayrı istek atmak yerine
  /// önce cache'teki fiyatları kullanır; cache'te yoksa tek tek çeker.
  Future<Map<String, double>> fetchPrices(List<String> codes) async {
    if (codes.isEmpty) return {};

    // Önce cache'ten doldur
    final result = <String, double>{};
    final missing = <String>[];

    if (_cacheValid) {
      final map = {for (final f in _cachedFunds!) f.code: f.price};
      for (final c in codes) {
        if (map.containsKey(c) && (map[c] ?? 0) > 0) {
          result[c] = map[c]!;
        } else {
          missing.add(c);
        }
      }
    } else {
      missing.addAll(codes);
    }

    // Cache'te olmayan / eski cache için fon listesini yenile
    if (missing.isNotEmpty) {
      try {
        final fresh = await fetchAllFunds(forceRefresh: !_cacheValid);
        final map = {for (final f in fresh) f.code: f.price};
        for (final c in missing) {
          if (map.containsKey(c)) result[c] = map[c]!;
        }

        // Hâlâ bulunamayanlar veya fiyatı 0 olanlar için bireysel fiyat endpoint'ini dene
        final stillMissing = missing.where((c) => !result.containsKey(c) || (result[c] ?? 0) <= 0).toList();
        for (final c in stillMissing) {
          final price = await _fetchSinglePrice(c);
          if (price != null) result[c] = price;
        }
      } catch (e) {
        _log('fetchPrices error: $e');
      }
    }

    return result;
  }

  /// Tek fon için güncel fiyatı `fonFiyatBilgiGetir` endpoint'inden çeker.
  Future<double?> _fetchSinglePrice(String code) async {
    try {
      final body = jsonEncode({'fonKodu': code, 'dil': 'TR', 'periyod': 1});
      final res = await _client
          .post(Uri.parse('$_baseUrl$_priceEndpoint'),
              headers: _headers, body: body)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final items = (data['resultList'] as List?) ?? [];
      if (items.isEmpty) return null;

      // Son (en güncel) kaydı al
      final latest = items.last as Map<String, dynamic>;
      final raw = latest['fiyat'];
      return raw != null ? double.tryParse(raw.toString()) : null;
    } catch (_) {
      return null;
    }
  }

  /// Tarihsel NAV verisi — performans grafikleri için.
  /// [periyod]: 1, 3, 6, 12, 36, 60 (ay)
  Future<List<(int, double)>> fetchHistory(
    String code, {
    int periyod = 3,
  }) async {
    try {
      final body = jsonEncode({'fonKodu': code, 'dil': 'TR', 'periyod': periyod});
      final res = await _client
          .post(Uri.parse('$_baseUrl$_priceEndpoint'),
              headers: _headers, body: body)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final items = (data['resultList'] as List?) ?? [];

      final points = <(int, double)>[];
      for (final row in items.cast<Map<String, dynamic>>()) {
        final dateStr = row['tarih'] as String? ?? '';
        final price = double.tryParse(row['fiyat']?.toString() ?? '');
        if (price == null || price <= 0) continue;
        final dt = DateTime.tryParse(dateStr);
        if (dt != null) points.add((dt.millisecondsSinceEpoch, price));
      }

      points.sort((a, b) => a.$1.compareTo(b.$1));
      return points;
    } catch (e) {
      _log('fetchHistory error: $e');
      return [];
    }
  }

  // ── Aracı kuruluş kırılımı ────────────────────────────────────────────────

  /// Fonları portföy yönetim şirketine göre grupla.
  /// Key: şirket adı, Value: o şirkete ait fonlar.
  Future<Map<String, List<TefasFund>>> fetchByManager() async {
    final funds = await fetchAllFunds();
    final grouped = <String, List<TefasFund>>{};
    for (final f in funds) {
      grouped.putIfAbsent(f.managerName, () => []).add(f);
    }
    // Her grup içini fon adına göre sırala
    for (final list in grouped.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  void invalidateCache() {
    _cachedFunds = null;
    _cacheTime = null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<List<TefasFund>> _fetchFundList(String fonTipi) async {
    final payload = {
      'dil': 'TR',
      'fonTipi': fonTipi,
      'kurucuKodu': null,
      'sfonTurKod': null,
      'fonTurAciklama': null,
      'islem': 1,
      'fonTurKod': null,
      'fonGrubu': null,
      'donemGetiri1a': '1',
      'donemGetiri3a': '1',
      'donemGetiri6a': '1',
      'donemGetiri1y': '1',
      'donemGetiriyb': '1',
      'donemGetiri3y': '1',
      'donemGetiri5y': '1',
      'basTarih': null,
      'bitTarih': null,
      'calismaTipi': 2,
      'getiriOrani': '1',
    };

    final res = await _client
        .post(
          Uri.parse('$_baseUrl$_listEndpoint'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('TEFAS list HTTP ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = (data['resultList'] as List?) ?? [];

    if (items.isEmpty) {
      throw Exception('TEFAS returned empty resultList');
    }

    return items
        .cast<Map<String, dynamic>>()
        .map((d) => TefasFund(
              code: (d['fonKodu'] as String? ?? '').trim(),
              name: _fixEncoding(d['fonUnvan'] as String? ?? '').trim(),
              price: 0.0, // fon listesi endpoint'i fiyat vermiyor
              fundType: fonTipi,
              managerName: _parseManagerName(
                  _fixEncoding(d['fonUnvan'] as String? ?? '')),
              return1m: _toDouble(d['getiri1a']),
              return3m: _toDouble(d['getiri3a']),
              return6m: _toDouble(d['getiri6a']),
              return1y: _toDouble(d['getiri1y']),
              returnYtd: _toDouble(d['getiriyb']),
              riskLevel: int.tryParse(d['riskDegeri']?.toString() ?? ''),
            ))
        .where((f) => f.code.isNotEmpty && f.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// fonUnvan'dan portföy yönetim şirketini çıkar.
  /// "GARANTI PORTFÖY ... FONU" → "GARANTİ PORTFÖY"
  static String _parseManagerName(String unvan) {
    final keywords = ['PORTFÖY', 'VARLIK', 'YATIRIM', 'MENKUL'];
    final parts = unvan.split(RegExp(r'\s+'));
    for (int i = 0; i < parts.length; i++) {
      if (keywords.contains(parts[i].toUpperCase())) {
        return parts.sublist(0, i + 1).join(' ').trim();
      }
    }
    // Keyword bulunamadıysa ilk 2 kelimeyi kullan
    return parts.take(2).join(' ').trim();
  }

  /// TEFAS bazen Latin-1 encoding ile yanıt veriyor,
  /// utf8.decode yeterli olmayabilir — ham bytes'ı kontrol et.
  static String _fixEncoding(String s) {
    // Eğer bozuk karakter yoksa olduğu gibi dön
    if (!s.contains('?') && !s.contains('\u00ef')) return s;
    try {
      return utf8.decode(latin1.encode(s), allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  void _log(String msg) {
    assert(() {
      // ignore: avoid_print
      print('[TefasService] $msg');
      return true;
    }());
  }
}
