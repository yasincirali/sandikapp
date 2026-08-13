import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/asset_categories.dart';

/// Arama sonucundaki tek bir sembol.
@immutable
class SymbolHit {
  /// Fiyat servislerine verilecek sembol — ör. `THYAO.IS`, `ALTIN_CEYREK`.
  final String ticker;

  /// Kullanıcıya gösterilen ad — ör. `Türk Hava Yolları`.
  final String name;

  /// Kısa köken etiketi — ör. `BIST`, `Altın`, `NASDAQ`.
  final String source;

  /// Yerleşik listelerden mi geldi (aksi halde Yahoo aramasından)?
  ///
  /// UI bunu rozet olarak gösterir: yerleşik semboller için fiyat/geçmiş
  /// desteği kanıtlıdır, Yahoo'dan gelen serbest sonuçlarda veri boş
  /// çıkabilir.
  final bool builtIn;

  const SymbolHit({
    required this.ticker,
    required this.name,
    required this.source,
    this.builtIn = true,
  });

  @override
  bool operator ==(Object other) =>
      other is SymbolHit && other.ticker == ticker;

  @override
  int get hashCode => ticker.hashCode;
}

/// Karşılaştırmaya eklenecek varlığı bulur.
///
/// İki katmanlı arar:
///   1. **Yerleşik listeler** (`asset_categories.dart`) — BIST 100, altın
///      ürünleri, emtia, döviz. Ticker formatları zaten doğru ve fiyat
///      desteği kanıtlı.
///   2. **Yahoo sembol araması** — yerleşikte yeterli sonuç yoksa devreye
///      girer; dünyadaki her şeyi (AAPL, BTC-USD, XU100.IS) bulur.
///
/// Sıralama bilinçlidir: yerleşik sonuçlar ÖNCE gelir. Yahoo'nun resmî
/// olmayan arama ucu bazen alakasız borsalardaki kopyaları öne atar
/// (ör. `THYAO.IS` ararken Meksika kotasyonu); yerel liste bunu bastırır.
class SymbolSearchService {
  SymbolSearchService._();
  static final instance = SymbolSearchService._();

  final _client = http.Client();

  /// Yahoo araması bu eşiğin altında yerleşik sonuç varsa tetiklenir.
  ///
  /// Amaç: "GARAN" yazan kullanıcıyı ağa çıkarmadan yanıtlamak, ama
  /// "AAPL" yazanı da boş bırakmamak.
  static const _builtInSatisfiedAt = 6;

  /// Yahoo yanıtı gecikirse arama tıkanmasın.
  static const _netTimeout = Duration(seconds: 4);

  static final _cache = <String, List<SymbolHit>>{};

  /// Yerleşik listelerin tek seferlik düzleştirilmiş hali.
  ///
  /// `static final` alan Dart'ta zaten tembel başlatılır: ilk erişimde
  /// kurulur, sonraki aramalar hazır listeyi kullanır. ~500 sembolü her
  /// tuş vuruşunda yeniden düzleştirmek gereksiz iş olurdu.
  static final List<SymbolHit> _builtIn = _buildBuiltInIndex();

  static List<SymbolHit> _buildBuiltInIndex() {
    final out = <SymbolHit>[];

    // BIST — `bist100StocksMap` kod→isim yönünde.
    bist100StocksMap.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'BIST'));
    });

    // Altın — `goldTickerMap` TERS yönde (isim→kod). Karıştırmak kolay;
    // bu yüzden burada açıkça çevriliyor.
    goldTickerMap.forEach((name, ticker) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Altın'));
    });

    // Döviz — karşılaştırmada sık istenen pariteler.
    const fx = {
      'USDTRY=X': 'Amerikan Doları',
      'EURTRY=X': 'Euro',
      'GBPTRY=X': 'İngiliz Sterlini',
    };
    fx.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Döviz'));
    });

    // Endeksler — "BIST'i yendim mi?" karşılaştırmasının referansı.
    // Yerleşik listede yoklar ama karşılaştırmanın en doğal kıyas
    // noktaları olduğu için elle ekleniyor.
    const indices = {
      'XU100.IS': 'BIST 100 Endeksi',
      'XU030.IS': 'BIST 30 Endeksi',
    };
    indices.forEach((ticker, name) {
      out.add(SymbolHit(ticker: ticker, name: name, source: 'Endeks'));
    });

    return out;
  }

  /// [query] için sembol arar. Boş sorguda popüler kıyas noktalarını döner.
  Future<List<SymbolHit>> search(String query) async {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return defaults;

    final cached = _cache[q];
    if (cached != null) return cached;

    final local = _searchBuiltIn(q);
    if (local.length >= _builtInSatisfiedAt) {
      _cache[q] = local;
      return local;
    }

    // Yerleşikte az sonuç var → Yahoo'ya sor, sonuçları BİRLEŞTİR.
    // Değiştirmek değil eklemek önemli: "ALTIN" araması yerel sonuçları
    // korurken Yahoo'dan gelenleri de gösterebilmeli.
    final remote = await _searchYahoo(q);
    final merged = <SymbolHit>[
      ...local,
      // `SymbolHit` eşitliği ticker üzerinden — yerel sonuç varsa Yahoo
      // kopyası elenir.
      ...remote.where((r) => !local.contains(r)),
    ];
    _cache[q] = merged;
    return merged;
  }

  /// Sorgu boşken gösterilen öneriler — kullanıcıya "ne arayabilirim"
  /// fikri verir.
  List<SymbolHit> get defaults => const [
        SymbolHit(ticker: 'XU100.IS', name: 'BIST 100 Endeksi', source: 'Endeks'),
        SymbolHit(ticker: 'ALTIN_GRAM', name: '22 Ayar Gram Altın', source: 'Altın'),
        SymbolHit(ticker: 'USDTRY=X', name: 'Amerikan Doları', source: 'Döviz'),
        SymbolHit(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST'),
        SymbolHit(ticker: 'GARAN.IS', name: 'Garanti BBVA', source: 'BIST'),
      ];

  /// Yerleşik listelerde ada VEYA ticker'a göre arar.
  static List<SymbolHit> _searchBuiltIn(String q) {
    final hits = _builtIn.where((h) {
      return h.ticker.contains(q) || h.name.toUpperCase().contains(q);
    }).toList();

    // Ticker'ı sorguyla BAŞLAYANLAR öne alınır: "AK" araması
    // `AKBNK`'ı, adında "ak" geçen rastgele bir şirketten önce göstermeli.
    hits.sort((a, b) {
      final aStarts = a.ticker.startsWith(q) ? 0 : 1;
      final bStarts = b.ticker.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts - bStarts;
      return a.ticker.compareTo(b.ticker);
    });
    return hits;
  }

  /// Yahoo'nun sembol arama ucu.
  ///
  /// **Resmî bir API değildir** — sözleşmesi habersiz değişebilir. Bu
  /// yüzden her hata yutulur ve boş liste döner: serbest arama bir bonus,
  /// yerleşik listeler asıl yoldur. Çökerse özellik çalışmaya devam eder,
  /// yalnızca kapsamı daralır.
  Future<List<SymbolHit>> _searchYahoo(String q) async {
    try {
      final uri = Uri.parse(
        'https://query2.finance.yahoo.com/v1/finance/search'
        '?q=${Uri.encodeQueryComponent(q)}&quotesCount=8&newsCount=0',
      );
      final res = await _client.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (compatible; SandikApp/1.0)',
      }).timeout(_netTimeout);

      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final quotes = (body['quotes'] as List?) ?? const [];

      final out = <SymbolHit>[];
      for (final raw in quotes) {
        final q = raw as Map<String, dynamic>;
        final sym = (q['symbol'] as String?)?.trim();
        if (sym == null || sym.isEmpty) continue;

        // Yalnızca fiyat serisi olan tipler; `quoteType` "OPTION" veya
        // "FUTURE" gelirse geçmiş çekimi anlamsız/boş olur.
        final type = (q['quoteType'] as String?)?.toUpperCase() ?? '';
        if (type != 'EQUITY' &&
            type != 'ETF' &&
            type != 'INDEX' &&
            type != 'CURRENCY' &&
            type != 'CRYPTOCURRENCY' &&
            type != 'MUTUALFUND') {
          continue;
        }

        out.add(SymbolHit(
          ticker: sym,
          name: (q['shortname'] ?? q['longname'] ?? sym) as String,
          source: (q['exchDisp'] as String?) ?? type,
          builtIn: false,
        ));
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('Yahoo sembol araması başarısız: $e');
      return const [];
    }
  }

  @visibleForTesting
  static void clearCacheForTest() => _cache.clear();
}
