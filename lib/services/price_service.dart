import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'crash_reporter.dart';
import 'fiyat_kaynagi.dart';
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
  //
  // ⚠️ 2026-09-15: truncgil v4 anahtarları DEĞİŞTİ — boşluklu Türkçe adlar
  // ('Gram Altın') yerine boşluksuz ASCII. Eski adların hiçbiri yanıtta
  // artık YOK, yani `data[key]` her sembolde null dönüyor ve altın
  // fiyatları Yahoo GC=F + ons/gram çevrimi olan YEDEĞE düşüyordu
  // (`_goldWeights`). Yedek çalıştığı için belirti sessizdi: fiyat geliyor
  // ama kaynak yanlış, sayı tutarsız.
  //
  // ⚠️⚠️ `ALTIN_GRAM` → `YIA`, **`GRA` DEĞİL** (ikinci tur düzeltmesi).
  // `GRA`'nın adı `GRAMALTIN` ama içeriği 24 ayar HAS altındır (`HAS` ile
  // %0,5 fark). Buradaki `ALTIN_GRAM` ise 22 ayardır — `asset_categories`
  // onu '22 Ayar Gram Altın' diye adlandırır ve aşağıdaki `_goldWeights`
  // ağırlıkları da 22 ayar cinsindendir. Yanlış eşleme kullanıcıya %8 yüksek
  // fiyat gösterir ve alarmları erken tetikler (2026-09-15, kullanıcı
  // bildirimi). Çapraz doğrulama: çeyrek/yarım/tam altının gram eşdeğeri
  // `YIA` ile %1 içinde uyumlu, `GRA` ile %8 sapıyor.
  //
  // Sunucu tarafındaki eşi: `supabase/functions/_shared/live_prices.ts`
  // → `GOLD_KEYS`. İKİSİ BİREBİR AYNI KALMALI — alarm, uygulamada GÖRÜNEN
  // sayı üzerinden tetiklenmeli.
  static const _truncgilGoldKeys = <String, String>{
    // 22AYARBILEZIK — '22 Ayar Gram Altın' ile aynı ayar.
    'ALTIN_GRAM': 'YIA',
    'ALTIN_CEYREK': 'CEYREKALTIN',
    'ALTIN_YARIM': 'YARIMALTIN',
    'ALTIN_CUMHURIYET': 'CUMHURIYETALTINI',
    'ALTIN_ATA': 'ATAALTIN',
    'ALTIN_RESAT': 'RESATALTIN',
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

  /// Bir troy ons kaç gram — altın çevriminin sabiti.
  static const _gramsPerTroyOunce = 31.1035;

  /// Türkiye'de "gram altın" 22 ayar üzerinden fiyatlanır; XAU ise 24 ayar
  /// saflıktadır. Bu oran saf ons fiyatını yerel gram fiyatına indirir.
  static const _goldPurityFactor = 22 / 24;

  /// Ons cinsinden XAU/TRY fiyatını **22 ayar gram** fiyatına çevirir.
  ///
  /// **Neden tek yerde:** bu formül geçmişte beş ayrı yere kopyalanmıştı
  /// (iki `price_service`, üç `history_service`). Ayar oranı ya da ons
  /// sabiti değişirse beşini birden düzeltmek gerekiyordu ve biri
  /// kaçarsa canlı fiyat ile grafik sessizce ayrışırdı — kullanıcı aynı
  /// altını iki ekranda iki farklı değerde görürdü.
  ///
  /// [xauTry] ons başına TRY fiyatı (yani XAU/USD × USD/TRY).
  static double gram22kFromXauTry(double xauTry) =>
      xauTry / _gramsPerTroyOunce * _goldPurityFactor;

  /// Altın ürününün gram cinsinden ağırlık çarpanı (çeyrek, yarım, ata...).
  /// Bilinmeyen sembolde 1.0 → gram altın gibi davranır.
  static double goldWeightFactor(String symbol) => _goldWeights[symbol] ?? 1.0;

  static const _tefasPrefix = 'TEFAS:';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Sembol başına kısa ömürlü fiyat önbelleği.
  ///
  /// `refreshPrices` her ekran açılışında ve her pull-to-refresh'te
  /// çağrılıyor; önbelleksiz her seferinde tüm semboller yeniden çekiliyordu.
  /// TTL bilinçli olarak kısa: kullanıcı "yenile" dediğinde bayat veri
  /// görmemeli, ama ekranlar arası gidip gelme yeni istek doğurmamalı.
  /// (Sunucu tarafında `price_history_cache` zaten var; bu onun istemci
  /// karşılığı.)
  static const _quoteTtl = Duration(seconds: 45);
  final Map<String, ({YahooQuote quote, DateTime at})> _quoteCache = {};

  /// Kullanıcı açıkça yenileme istediğinde (pull-to-refresh) çağrılır —
  /// önbellek atlanır ve fiyatlar kaynaktan tazelenir.
  void invalidateQuoteCache() => _quoteCache.clear();

  /// Bu oturumda GÖRÜLMÜŞ son canlı fiyatlar (sembol → TL/kotasyon).
  ///
  /// [_quoteCache]'ten farkı: TTL ile düşmez. Amacı "şu an taze mi" değil,
  /// **"en son ölçülen gerçek değer neydi"**.
  ///
  /// ## Neden var
  /// Grafik yolları kur bulunamadığında `35.0` / `40.0` gibi SABİTLER
  /// kullanıyordu. Bu sayılar ölçüm değil; gerçek kurdan saptıkça portföyü
  /// sessizce yanlış gösteriyorlardı (ölçülen en kötü hâl ~%17). Doğrusu
  /// sırayla: (1) serinin kendi kuru, (2) bu oturumda görülen son canlı kur,
  /// (3) hiçbiri yoksa noktayı ATLA.
  ///
  /// Ayrıca ekranın gösterdiği TL karşılığı (`PortfolioState.toTRY`) de bu
  /// kurdan hesaplanır — seri buna hizalanınca (`kurSerisiniHizala`) grafiğin
  /// son noktası ile kâr/zarar çipi aynı sayıyı verir.
  final Map<String, double> _sonBilinenFiyat = {};

  /// Sembolün SON fiyatını hangi kaynak verdi.
  ///
  /// Teşhis için: "fiyat zıplıyor" bildirimi geldiğinde ilk soru kaynağın
  /// değişip değişmediğidir ve bu, dışarıdan görülemiyordu.
  final Map<String, FiyatKaynagiEtiketi> _sonKaynak = {};

  /// Sembolün son fiyatını veren kaynak — yoksa `null`.
  FiyatKaynagiEtiketi? sonKaynak(String symbol) =>
      _sonKaynak[symbol.trim().toUpperCase()];

  /// Bu oturumda görülmüş son canlı fiyat — yoksa `null` (uydurma YOK).
  double? sonBilinenFiyat(String symbol) =>
      _sonBilinenFiyat[symbol.trim().toUpperCase()];

  /// Testler için: oturum belleğini sıfırlar (disk değil).
  @visibleForTesting
  void sonBilinenFiyatlariTemizle() {
    _sonBilinenFiyat.clear();
    _sonKaynak.clear();
    _birincilYukleme = null;
  }

  // ── Birincil kaynağın son fiyatı: KALICI bellek ─────────────────────────
  //
  // `OlcekHafizasi` oranı ilk yedek geçişinde "bu oturumda görülmüş son
  // birincil fiyat"tan öğreniyor (bkz. `_fetchGoldFallback`). Soğuk açılışta
  // o fiyat yoktu → oran öğrenilemiyor → yedek HAM ölçekte kalıyordu.
  // Kullanıcının "bazen doğru, bazen zıplıyor" dediği artığın ikinci ayağı.
  //
  // Bu yüzden truncgil'in verdiği son fiyatlar diske yazılır ve ilk
  // `fetchQuotes`'ta geri okunur. TTL 6 saat: oran öğrenirken aradan geçen
  // hareket de orana karışır; birkaç saatlik hareket %0,5'in altındadır ve
  // ilk grafik çizimi oranı zaten tazeler, ama dünkü fiyattan öğrenilen
  // oran bir günlük hareketi kalıcılaştırırdı.
  static const _prefsBirincilKey = 'son_birincil_fiyat_v1';
  static const _birincilTtl = Duration(hours: 6);
  Future<void>? _birincilYukleme;

  /// Diskteki son birincil fiyatları bir kez yükler (bu oturumda görülmüş
  /// değerlere DOKUNMAZ). `fetchQuotes` her çağrıda bekler; ilk çağrıdan
  /// sonra ücretsizdir.
  @visibleForTesting
  Future<void> birincilHafizayiYukle() => _birincilYukleme ??= _birincilYukle();

  Future<void> _birincilYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ham = prefs.getString(_prefsBirincilKey);
      if (ham == null) return;
      final map = jsonDecode(ham) as Map<String, dynamic>;
      final now = DateTime.now();
      for (final e in map.entries) {
        final v = e.value as Map<String, dynamic>;
        final p = (v['p'] as num?)?.toDouble();
        final ts = v['ts'] as int?;
        if (p == null || p <= 0 || !p.isFinite || ts == null) continue;
        if (now.difference(DateTime.fromMillisecondsSinceEpoch(ts)) >
            _birincilTtl) {
          continue;
        }
        // Bu oturumda zaten bir fiyat görüldüyse o kazanır.
        if (_sonBilinenFiyat.containsKey(e.key)) continue;
        _sonBilinenFiyat[e.key] = p;
        _sonKaynak[e.key] = FiyatKaynagiEtiketi.yurtIci;
      }
    } catch (_) {
      // Bozuk kayıt — yok say; bir sonraki başarılı çekim üstüne yazar.
    }
  }

  /// Yalnızca BİRİNCİL kaynaktan gelmiş fiyatlar yazılır: yedeğin sayısını
  /// "birincil" diye saklamak ölçek hafızasını yanlış oranla zehirlerdi.
  Future<void> _birincilHafizayiKaydet() async {
    final map = <String, Map<String, dynamic>>{};
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (final e in _sonBilinenFiyat.entries) {
      if (_sonKaynak[e.key] != FiyatKaynagiEtiketi.yurtIci) continue;
      map[e.key] = {'p': e.value, 'ts': ts};
    }
    if (map.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsBirincilKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<Map<String, YahooQuote>> fetchQuotes(
    List<String> symbols, {
    bool forceRefresh = false,
  }) async {
    final cleaned = symbols
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return {};

    // Soğuk açılışta yedek yol hiçbir oran/birincil fiyat bilmeden
    // koşmasın — iki kalıcı bellek de ağa çıkmadan ÖNCE hazır olmalı.
    await Future.wait([
      birincilHafizayiYukle(),
      OlcekHafizasi.instance.yukle(),
    ]);

    // Taze önbellek girişlerini ayır; yalnızca eksikler için ağa çık.
    final cachedHits = <String, YahooQuote>{};
    final now = DateTime.now();
    if (!forceRefresh) {
      cleaned.removeWhere((s) {
        final e = _quoteCache[s];
        if (e == null) return false;
        if (now.difference(e.at) > _quoteTtl) {
          _quoteCache.remove(s);
          return false;
        }
        cachedHits[s] = e.quote;
        return true;
      });
      if (cleaned.isEmpty) return cachedHits;
    }

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

    // ── Tüm kaynakları paralel başlat ─────────────────────────────────────
    final needTruncgil = fxList.isNotEmpty || goldList.isNotEmpty;

    final truncgilFuture = needTruncgil
        ? _fetchTruncgilData().catchError((_) => <String, dynamic>{})
        : Future<Map<String, dynamic>>.value({});

    final tefasFuture = tefasList.isNotEmpty
        ? _fetchTefas(tefasList, forceRefresh: forceRefresh)
            .catchError((_) => <String, YahooQuote>{})
        : Future<Map<String, YahooQuote>>.value({});

    final yahooFuture = yahooList.isNotEmpty
        ? _fetchYahoo(yahooList).catchError((_) => <String, YahooQuote>{})
        : Future<Map<String, YahooQuote>>.value({});

    final parallel = await Future.wait([truncgilFuture, tefasFuture, yahooFuture]);

    final truncgilData = parallel[0];
    final tefasResult  = parallel[1] as Map<String, YahooQuote>;
    final yahooResult  = parallel[2] as Map<String, YahooQuote>;

    // ── FX from truncgil ──────────────────────────────────────────────────
    if (fxList.isNotEmpty && truncgilData.isNotEmpty) {
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

    // ── Gold from truncgil ────────────────────────────────────────────────
    if (goldList.isNotEmpty && truncgilData.isNotEmpty) {
      try {
        results.addAll(_extractGold(goldList, truncgilData));
      } catch (_) {}
    }

    // Gold fallback: XAU/TRY doğrudan, olmazsa GC=F × USD/TRY.
    //
    // **Buradaki `usdTry > 0` kapısı KALDIRILDI ve sebebi önemli.**
    // `USDTRY=X` yalnızca kullanıcının portföyünde bir DÖVİZ varlığı varsa
    // çekiliyor (`fxList` boşsa truncgil'den FX bile istenmiyor). Yani
    // altını olup dövizi olmayan bir kullanıcıda `results['USDTRY=X']`
    // hiçbir zaman dolmuyordu → kur 0 → truncgil düştüğü an altın için
    // yedek yol HİÇ ÇALIŞMIYOR ve altın fiyatsız kalıyordu. Belirtisi:
    // "bugün altın fiyatları çekilmiyor" (kullanıcı bildirimi 2026-09-07).
    //
    // Yedek yolun kendi kurunu bulabilmesi gerekir; portföyün bileşimine
    // bağlı olmamalıdır.
    final missingGold = goldList.where((s) => !results.containsKey(s)).toList();
    if (missingGold.isNotEmpty) {
      try {
        results.addAll(await _fetchGoldFallback(
          missingGold,
          results['USDTRY=X']?.regularMarketPrice ?? 0,
        ));
      } catch (_) {}
    }

    // ── TEFAS + Yahoo (zaten tamamlandı) ──────────────────────────────────
    results.addAll(tefasResult);
    results.addAll(yahooResult);

    // Yalnızca gerçekten fiyat dönen sembolleri önbelleğe al: 0/eksik değer
    // önbelleklenirse TTL boyunca hatalı fiyat gösterilir.
    final cachedAt = DateTime.now();
    for (final e in results.entries) {
      final p = e.value.regularMarketPrice ?? 0;
      if (p > 0) {
        _quoteCache[e.key] = (quote: e.value, at: cachedAt);
        // TTL'siz oturum belleği: grafik yolları kur/fiyat bulamadığında
        // sabit uydurmak yerine buraya bakar (bkz. `sonBilinenFiyat`).
        _sonBilinenFiyat[e.key] = p;
      }
    }
    // Birincil kaynaktan bir şey geldiyse kalıcı belleği tazele.
    if (results.keys
        .any((k) => _sonKaynak[k] == FiyatKaynagiEtiketi.yurtIci)) {
      CrashReporter.arkaPlan(_birincilHafizayiKaydet(), reason: 'price_service._birincilHafizayiKaydet');
    }

    results.addAll(cachedHits);
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
    return parseTruncgilBody(res.body);
  }

  /// truncgil gövdesini ayrıştırır; KESİK gövdeden tam girişleri kurtarır.
  ///
  /// ## Neden düz `jsonDecode` yetmiyor (2026-09-17, ölçüldü)
  /// truncgil `v4/today.json`'u sunucu tarafında 6.805 baytta KESİK
  /// gönderiyor (`Content-Length` de 6805; gövde `"Chang` ile bitiyor, gzip
  /// istenince bağlantı kopuyor; üç ardışık istekte aynı). `jsonDecode`
  /// bunu `FormatException` ile reddediyor ve birincil kaynak o turda
  /// "düşmüş" sayılıyordu — yani yedek yol (Yahoo paritesi, ~%1,8 farklı
  /// ölçek) devreye giriyordu. `OlcekHafizasi` o farkı örtüyor ama oranı
  /// öğrenmek için en az bir birincil gözlem ister; kaynak kalıcı kesikse
  /// hiç öğrenemez. Gövdeyi kurtarmak sorunu kaynağında kapatır: birincil
  /// fiyat gerçekten elde olduğu sürece yedeğe hiç inilmez.
  ///
  /// Gövde DÜZ bir sözlüktür (`{"USD":{...},"EUR":{...},...}`, iç içe nesne
  /// yok); kesik olsa da kesim noktasına kadarki girişler bütündür. USD ve
  /// tüm altın anahtarları ilk ~6.400 baytta geliyor, yalnızca sondaki
  /// (paladyum vb.) kayıp. Bu yüzden tam `"KEY":{...}` çiftleri tek tek
  /// kurtarılır; yalnızca hiçbiri kurtarılamazsa ayrıştırma başarısız sayılır.
  ///
  /// Gövde `{` ile başlamıyorsa (HTML hata sayfası, boş yanıt) kurtarma
  /// DENENMEZ — çöp sayfadan tesadüfen eşleşen bir çift fiyat üretmemeli.
  /// Sunucu eşi: `_shared/live_prices.ts` → `parseTruncgilBody`.
  @visibleForTesting
  static Map<String, dynamic> parseTruncgilBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('truncgil: kök nesne değil');
    } on FormatException {
      if (!body.trimLeft().startsWith('{')) rethrow;
      final out = <String, dynamic>{};
      for (final m in _truncgilGirisDeseni.allMatches(body)) {
        try {
          final v = jsonDecode(m.group(2)!);
          if (v is Map<String, dynamic>) out[m.group(1)!] = v;
        } on FormatException {
          // Girişin kendisi bozuksa atla; komşuları hâlâ kurtarılabilir.
        }
      }
      if (out.isEmpty) rethrow;
      return out;
    }
  }

  /// `"KEY":{ ...düz alanlar... }` — iç içe süslü parantez YOK, o yüzden
  /// `[^{}]*` bir girişi tam sınırlarıyla yakalar.
  static final _truncgilGirisDeseni =
      RegExp(r'"([A-Za-z0-9_]+)"\s*:\s*(\{[^{}]*\})');

  /// truncgil kaydından fiyat.
  ///
  /// İKİ biçim de desteklenir ve bu bilinçli:
  ///   · **num** (v4, 2026-09 sonrası): `6710.67` — API artık JSON sayısı
  ///     döndürüyor ve alan adları İngilizce (`Buying`/`Selling`).
  ///   · **String** (eski biçim): `"5.412,37"` — binlik NOKTA, ondalık
  ///     VİRGÜL. Ham `double.tryParse` bunu 5.412 okur, yani BİN KATI
  ///     hatalı fiyat.
  ///
  /// Eski dallar KORUNUYOR: API biçimi bir kez değiştiyse geri de dönebilir.
  double _parseTruncgilValue(dynamic entry) {
    if (entry is! Map) return 0;
    final raw = entry['Alış'] ??
        entry['Buying'] ??
        entry['Satış'] ??
        entry['Selling'];
    if (raw == null) return 0;
    // v4: gerçek sayı — string ayrıştırması uygulanmamalı.
    if (raw is num) {
      final v = raw.toDouble();
      return v.isFinite && v > 0 ? v : 0;
    }
    final metin = raw.toString();
    return double.tryParse(metin.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }

  Map<String, YahooQuote> _extractFx(Map<String, dynamic> data) {
    final usdTry = _parseTruncgilValue(data['USD']);
    final eurTry = _parseTruncgilValue(data['EUR']);
    final gbpTry = _parseTruncgilValue(data['GBP']);
    if (usdTry <= 0) throw Exception('USD rate missing from Truncgil');
    _sonKaynak[FiyatKaynagi.usdTry] = FiyatKaynagiEtiketi.yurtIci;
    // EUR/GBP yoksa UYDURULMAZ (eskiden `usdTry × 1,1` / `× 1,28`): sabit
    // çapraz kur gerçek paritenin %5-10 dışında kalabilir ve kaynak bir
    // sonraki turda dönünce EUR varlıkları zıplardı. Anahtar verilmez;
    // provider son bilinen kuru korur (`?? current.eurTry`).
    if (eurTry > 0) _sonKaynak['EURTRY=X'] = FiyatKaynagiEtiketi.yurtIci;
    if (gbpTry > 0) _sonKaynak['GBPTRY=X'] = FiyatKaynagiEtiketi.yurtIci;
    return {
      'USDTRY=X': _fxQ('USDTRY=X', usdTry, _truncgilChange(data['USD'])),
      if (eurTry > 0)
        'EURTRY=X': _fxQ('EURTRY=X', eurTry, _truncgilChange(data['EUR'])),
      if (gbpTry > 0)
        'GBPTRY=X': _fxQ('GBPTRY=X', gbpTry, _truncgilChange(data['GBP'])),
    };
  }

  /// truncgil günlük değişim yüzdesi (`Change: 0.08` = %0,08).
  ///
  /// Piyasa şeridi için (2026-09-20): kur/altının günlük yönü, fiyatla
  /// AYNI kaynaktan gelmeli — Yahoo'nun dünkü kapanışından türetmek iki
  /// ölçeği karıştırırdı (sözleşme kural 2). Alan yoksa null: uydurma yok.
  static double? _truncgilChange(dynamic entry) {
    if (entry is! Map) return null;
    final raw = entry['Change'];
    // Yalnızca sayı (v4). Eski string biçiminde ("-0,30" / "-0.30") ondalık
    // ayırıcı belirsiz — tahmin etmektense değişim yazılmaz.
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    return null;
  }

  Map<String, YahooQuote> _extractGold(
      List<String> goldSymbols, Map<String, dynamic> data) {
    final result = <String, YahooQuote>{};
    for (final sym in goldSymbols) {
      final key = _truncgilGoldKeys[sym];
      if (key == null) continue;
      final price = _parseTruncgilValue(data[key]);
      if (price > 0) {
        _sonKaynak[sym] = FiyatKaynagiEtiketi.yurtIci;
        result[sym] = YahooQuote(
          symbol: sym,
          regularMarketPrice: price,
          currency: 'TRY',
          shortName: _goldLabel(sym),
          regularMarketChangePercent: _truncgilChange(data[key]),
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
    // Kur yedeği de başka bir ölçektedir (er-api mid, truncgil `Alış`).
    // Altınla aynı gerekçe: kaynak değişince kullanıcının USD kote
    // varlıkları zıplamamalı.
    double hizala(String sembol, double ham) {
      // Altındaki ile aynı kural: oran yoksa bu oturumda birincil kaynaktan
      // görülmüş son kurdan öğren.
      if (OlcekHafizasi.instance.oran(sembol, FiyatKaynagiEtiketi.erApi) ==
              null &&
          _sonKaynak[sembol] == FiyatKaynagiEtiketi.yurtIci) {
        final sonBirincil = _sonBilinenFiyat[sembol];
        if (sonBirincil != null && sonBirincil > 0 && ham > 0) {
          OlcekHafizasi.instance.ogren(sembol, FiyatKaynagiEtiketi.erApi,
              birincil: sonBirincil, yedek: ham);
        }
      }
      _sonKaynak[sembol] = FiyatKaynagiEtiketi.erApi;
      return OlcekHafizasi.instance
          .hizala(sembol, FiyatKaynagiEtiketi.erApi, ham);
    }

    return {
      FiyatKaynagi.usdTry: _fxQ(FiyatKaynagi.usdTry, hizala(FiyatKaynagi.usdTry, usdTry)),
      'EURTRY=X': _fxQ('EURTRY=X', hizala('EURTRY=X', usdTry / usdEur)),
      'GBPTRY=X': _fxQ('GBPTRY=X', hizala('GBPTRY=X', usdTry / usdGbp)),
    };
  }

  YahooQuote _fxQ(String symbol, double price, [double? change]) => YahooQuote(
        symbol: symbol,
        regularMarketPrice: price,
        currency: 'TRY',
        regularMarketChangePercent: change,
      );

  // ── Gold fallback — XAU/TRY doğrudan, olmazsa GC=F × USD/TRY ─────────────

  /// Altın için USD/TRY kuru — portföyün bileşiminden BAĞIMSIZ.
  ///
  /// `results['USDTRY=X']` yalnızca kullanıcının döviz varlığı varsa dolar
  /// (bkz. `fxList`). Altın yedeği o değere bağlı kalırsa, dövizi olmayan
  /// kullanıcıda kur hiç bulunamaz ve altın fiyatsız kalır. Bu yüzden yedek
  /// yol kendi kurunu ARAR: önce Yahoo, sonra er-api.
  Future<double> _resolveUsdTry() async {
    try {
      final p = (await _fetchOneChart('USDTRY=X'))?.regularMarketPrice;
      if (p != null && p > 0) return p;
    } catch (_) {}
    try {
      final fx = await _fetchFxErApi();
      final p = fx['USDTRY=X']?.regularMarketPrice;
      if (p != null && p > 0) return p;
    } catch (_) {}
    return 0;
  }

  /// [usdTryHint] çağıran tarafta zaten çekilmiş kur (0 = bilinmiyor).
  Future<Map<String, YahooQuote>> _fetchGoldFallback(
      List<String> goldSymbols, double usdTryHint) async {
    // 1) XAU/TRY doğrudan — kur çevrimi GEREKTİRMEZ, dolayısıyla USD
    //    serisi hiç bulunamasa bile altın fiyatlanır. `history_service`
    //    gün içi altın serisinde de aynı sıralama kullanılıyor; iki yüzey
    //    aynı kaynağı aynı öncelikle denemeli.
    //    Eşik ons başına TRY için düşük ama anlamlı bir taban: gerçek değer
    //    yüz binler mertebesinde, 1000 yalnızca çöp/placeholder'ı eler.
    double? xauTry;
    // Hangi yedek yol kullanıldı — ölçek hafızasının anahtarı buna bağlı:
    // spot ile vadeli AYNI ölçekte değil, tek bir "yedek" etiketi ikisini
    // karıştırır ve yanlış oranla düzeltme yapardı.
    var xauTrySpotMuydu = true;
    try {
      final direct =
          (await _fetchOneChart(FiyatKaynagi.xauTry))?.regularMarketPrice;
      if (direct != null && direct > 1000) xauTry = direct;
    } catch (_) {}

    // 2) Eski yol: GC=F (ons/USD) × USD/TRY.
    if (xauTry == null) {
      xauTrySpotMuydu = false;
      final q = await _fetchOneChart(FiyatKaynagi.xauUsd);
      final xauUsd = q?.regularMarketPrice;
      if (xauUsd == null || xauUsd <= 500) {
        throw Exception('GC=F unavailable');
      }
      final usdTry = usdTryHint > 0 ? usdTryHint : await _resolveUsdTry();
      if (usdTry <= 0) throw Exception('USDTRY unavailable');
      xauTry = xauUsd * usdTry;
    }

    final gram22k = gram22kFromXauTry(xauTry);
    // ── Yedek kaynak BAŞKA BİR ÖLÇEKTEDİR ────────────────────────────────
    //
    // Birincil kaynak truncgil'dir: yurt içi kotasyon. Buradaki sayı ise
    // uluslararası spot (ya da vadeli) çevrimidir ve aralarında kalıcı bir
    // makas vardır (~%1-2). Ham dönerse, truncgil'in bir tur cevap
    // vermediği her seferde kullanıcının fiyatı zıplar ve bir sonraki turda
    // geri döner: portföy toplamı, grafiğin son noktası ve Live Activity'nin
    // "bugünkü değişim"i aynı anda işaret değiştirir (kullanıcı bildirimi,
    // TestFlight 2026-09-17). Hareket değil, ÖLÇEK değişimi.
    //
    // Bu yüzden değer, öğrenilmiş oranla birincilin ölçeğine taşınır. Oran
    // grafik yollarında zaten hesaplanıyor (`altinKalibrasyonHaritasi`),
    // ek ağ maliyeti yok. Oran bilinmiyorsa ham kullanılır — uydurma
    // çarpan yok — ve durum teşhise açık kalır (`sonKaynak`).
    final etiket = xauTrySpotMuydu
        ? FiyatKaynagiEtiketi.spot
        : FiyatKaynagiEtiketi.vadeli;
    final out = <String, YahooQuote>{};
    for (final sym in goldSymbols) {
      final ham = gram22k * (_goldWeights[sym] ?? 1.0);
      // Oran henüz öğrenilmemişse (grafik hiç çizilmediyse) BU GEÇİŞTE
      // öğren: bu oturumda birincil kaynaktan görülmüş son fiyat elimizde.
      // Aradan geçen sürede gerçekleşmiş küçük bir hareketi ölçeğe
      // katmak, %1-2'lik bir ölçek sıçramasını kullanıcıya göstermekten
      // iyidir — ve bir sonraki grafik çizimi oranı zaten tazeleyecek.
      if (OlcekHafizasi.instance.oran(sym, etiket) == null &&
          _sonKaynak[sym] == FiyatKaynagiEtiketi.yurtIci) {
        final sonBirincil = _sonBilinenFiyat[sym];
        if (sonBirincil != null && sonBirincil > 0 && ham > 0) {
          OlcekHafizasi.instance
              .ogren(sym, etiket, birincil: sonBirincil, yedek: ham);
        }
      }
      final hizali = OlcekHafizasi.instance.hizala(sym, etiket, ham);
      _sonKaynak[sym] = etiket;
      out[sym] = YahooQuote(
        symbol: sym,
        regularMarketPrice: hizali,
        currency: 'TRY',
        shortName: _goldLabel(sym),
      );
    }
    CrashReporter.report(
      'altın yedek kaynak devrede: ${etiket.name} '
      '(ölçek hafızası: ${OlcekHafizasi.instance.oran(goldSymbols.first, etiket) == null ? "YOK" : "var"})',
      StackTrace.current,
      reason: 'fiyat_yedek_kaynak',
    );
    return out;
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

  Future<Map<String, YahooQuote>> _fetchTefas(
    List<String> tefasSymbols, {
    bool forceRefresh = false,
  }) async {
    final codes =
        tefasSymbols.map((s) => s.replaceFirst(_tefasPrefix, '')).toList();
    // `forceRefresh` TEFAS'a da geçer. Geçmediğinde kendi 30 dakikalık
    // TTL'i devrede kalıyor ve kullanıcının pull-to-refresh'i fonlar için
    // hiçbir şey yapmıyordu — hisse tazeleniyor, fon bayat kalıyordu.
    final prices = await TefasService.instance
        .fetchPrices(codes, forceRefresh: forceRefresh);
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

  // ── Historical FX rate for a specific date ────────────────────────────────

  /// Verilen tarih için günlük kapanış FX kurunu döndürür.
  /// Bulunamazsa null döner — çağıran 1.0 fallback kullanır.
  /// Yahoo Finance sembolü (hisse, ETF, emtia, FX) için verilen [date] tarihine
  /// en yakın işlem gününün kapanış fiyatını döndürür. Aralık: hedef tarihten
  /// 10 gün önce - 10 gün sonra (hafta sonu, tatil, veri gecikmesi toleransı).
  /// Bulamazsa null.
  ///
  /// TEFAS sembolleri (`TEFAS:XYZ`) için TefasService.fetchHistory kullanılır.
  Future<double?> fetchHistoricalClose(String symbol, DateTime date) async {
    if (symbol.trim().isEmpty) return null;

    // Altın iç sembolleri: önce XAUTRY=X dene; Yahoo bu sembolü 404 döner-
    // se GC=F (ons USD) × USDTRY=X ile hesapla — spot fallback'in birebir
    // tarihli versiyonu.
    if (_goldWeights.containsKey(symbol)) {
      if (kDebugMode) debugPrint('[PriceService] historicalGold: sym=$symbol date=$date');
      double? xauTry = await fetchHistoricalClose('XAUTRY=X', date);
      if (xauTry == null || xauTry <= 0) {
        // Fallback: GC=F × USDTRY
        final xauUsd = await fetchHistoricalClose('GC=F', date);
        final usdTry = await fetchHistoricalClose('USDTRY=X', date);
        if (kDebugMode) debugPrint('[PriceService] historicalGold fallback: xauUsd=$xauUsd usdTry=$usdTry');
        if (xauUsd != null && xauUsd > 0 && usdTry != null && usdTry > 0) {
          xauTry = xauUsd * usdTry;
        }
      }
      if (kDebugMode) debugPrint('[PriceService] historicalGold: xauTry=$xauTry');
      if (xauTry == null || xauTry <= 0) return null;
      final gram22k = gram22kFromXauTry(xauTry);
      final result = gram22k * goldWeightFactor(symbol);
      if (kDebugMode) debugPrint('[PriceService] historicalGold: result=$result');
      return result;
    }

    if (symbol.startsWith('TEFAS:')) {
      final code = symbol.replaceFirst('TEFAS:', '');
      final points = await TefasService.instance
          .fetchHistory(code, periyod: 12);
      if (points.isEmpty) return null;
      // "Son geçerli kapanış" kuralı: hedef tarihe eşit veya öncesindeki
      // en yeni noktayı seç. Hafta sonu/tatil için doğal olarak bir önceki
      // işlem günü gelir. İleri günü asla seçme.
      final target =
          DateTime(date.year, date.month, date.day, 23, 59, 59)
              .millisecondsSinceEpoch;
      double? best;
      int bestTs = -1;
      for (final p in points) {
        if (p.$1 > target) continue;
        if (p.$1 > bestTs) {
          bestTs = p.$1;
          best = p.$2;
        }
      }
      // Hiç ≤ hedef nokta yoksa (kullanıcı fonun kuruluş tarihinden önce
      // seçmiş) fallback: en eski noktayı ver.
      if (best == null && points.isNotEmpty) {
        points.sort((a, b) => a.$1.compareTo(b.$1));
        best = points.first.$2;
      }
      return best;
    }

    // Yahoo Finance: "son geçerli kapanış" kuralı — hedef tarihte veya
    // öncesindeki en yeni işlem günü kapanışını al. Hafta sonu/tatil için
    // otomatik olarak Cuma'ya (ya da son işlem gününe) düşer. Pencere: 15
    // gün geriye (uzun tatilleri kapsasın diye), 1 gün ileri (Yahoo'nun UTC
    // dilim farkını tolere etmek için — kullanıcının seçtiği tarihin gün
    // sonuna kadar).
    final windowStart =
        DateTime.utc(date.year, date.month, date.day)
            .subtract(const Duration(days: 15));
    final windowEnd =
        DateTime.utc(date.year, date.month, date.day, 23, 59, 59)
            .add(const Duration(days: 1));
    final p1 = (windowStart.millisecondsSinceEpoch / 1000).round();
    final p2 = (windowEnd.millisecondsSinceEpoch / 1000).round();
    final targetEnd =
        DateTime.utc(date.year, date.month, date.day, 23, 59, 59)
            .millisecondsSinceEpoch;

    try {
      final uri = Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/$symbol',
        {'interval': '1d', 'period1': '$p1', 'period2': '$p2'},
      );
      if (kDebugMode) debugPrint('[PriceService] histClose GET $uri');
      final res = await _client
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) debugPrint('[PriceService] histClose status=${res.statusCode} bodyLen=${res.body.length}');
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = (body['chart']?['result'] as List?)?.firstOrNull
          as Map<String, dynamic>?;
      if (result == null) {
        if (kDebugMode) debugPrint('[PriceService] histClose: null result');
        return null;
      }

      final timestamps = (result['timestamp'] as List?)?.cast<dynamic>();
      final closes = (((result['indicators']?['quote'] as List?)?.firstOrNull
              as Map<String, dynamic>?)?['close'] as List?)
          ?.cast<dynamic>();
      if (timestamps == null ||
          closes == null ||
          timestamps.isEmpty ||
          closes.isEmpty) {
        if (kDebugMode) debugPrint('[PriceService] histClose: empty timestamps/closes');
        return null;
      }

      // ≤ hedef en yeni kapanış (hafta sonu → Cuma, tatil → önceki iş günü).
      double? best;
      int bestTs = -1;
      double? earliest;
      int earliestTs = 1 << 62;
      for (var i = 0; i < timestamps.length && i < closes.length; i++) {
        final ts = (timestamps[i] as num?)?.toInt();
        final v = (closes[i] as num?)?.toDouble();
        if (ts == null || v == null || v <= 0) continue;
        final tsMs = ts * 1000;
        if (tsMs <= targetEnd && tsMs > bestTs) {
          bestTs = tsMs;
          best = v;
        }
        if (tsMs < earliestTs) {
          earliestTs = tsMs;
          earliest = v;
        }
      }
      // Hedef tarihten önce hiç veri yoksa (kullanıcı çok eski tarih seçmiş)
      // pencerede bulunan en eski veriyi ver — hiç dönmemekten iyidir.
      final picked = best ?? earliest;
      if (kDebugMode) debugPrint('[PriceService] histClose picked=$picked bestTs=$bestTs');
      return picked;
    } catch (e) {
      if (kDebugMode) debugPrint('[PriceService] histClose EXC: $e');
      return null;
    }
  }

  Future<double?> fetchHistoricalFxRate(String fxSymbol, DateTime date) async {
    // Yahoo Finance UNIX timestamp: gün başı ve gün sonu (UTC)
    final dayStart = DateTime.utc(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 3)); // hafta sonu toleransı
    final p1 = (dayStart.millisecondsSinceEpoch / 1000).round();
    final p2 = (dayEnd.millisecondsSinceEpoch / 1000).round();

    try {
      final uri = Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/$fxSymbol',
        {'interval': '1d', 'period1': '$p1', 'period2': '$p2'},
      );
      final res = await _client
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = (body['chart']?['result'] as List?)?.firstOrNull
          as Map<String, dynamic>?;
      if (result == null) return null;

      final closes = (((result['indicators']?['quote'] as List?)?.firstOrNull
              as Map<String, dynamic>?)?['close'] as List?)
          ?.cast<dynamic>();
      if (closes == null || closes.isEmpty) return null;

      // İlk geçerli kapanış fiyatını al
      for (final c in closes) {
        final v = (c as num?)?.toDouble();
        if (v != null && v > 0) return v;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Historical data for charts ─────────────────────────────────────────────

  Future<List<(int, double)>> fetchHistory(
      String symbol, String range) async {
    return fetchHistoryAtInterval(symbol, range, _intervalFor(range));
  }

  /// Aynı fetchHistory ama interval'i çağıran belirler. Zoom-aware
  /// çözünürlük için (HistoryService.getPortfolioHistoryAtResolution).
  Future<List<(int, double)>> fetchHistoryAtInterval(
      String symbol, String range, String interval) async {
    // TEFAS fonları için TEFAS history endpoint'i (interval yok, periyod ay).
    if (symbol.startsWith(_tefasPrefix)) {
      final code = symbol.replaceFirst(_tefasPrefix, '');
      final periyod = _tefasPeriyodFor(range);
      return TefasService.instance.fetchHistory(code, periyod: periyod);
    }

    final yahooRange = range;

    final uri = Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/$symbol',
        {'interval': interval, 'range': yahooRange, 'includePrePost': 'false'});

    final res = await _client
        .get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return [];

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result =
        (body['chart']?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
    if (result == null) return [];

    final timestamps = (result['timestamp'] as List?)?.cast<int>() ?? [];
    final closes = (((result['indicators']?['quote'] as List?)?.firstOrNull
            as Map<String, dynamic>?)?['close'] as List?)
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

  /// Range'e uygun varsayılan interval.
  ///
  /// `6mo` eskiden `1wk` idi: altı ay için haftalık çözünürlük fazla kabaydı
  /// ve `1y` ile aynı adımı verdiği için iki dönem birbirinden ayırt
  /// edilemiyordu. Günlük adım altı ayda ~125 nokta üretir — grafik için
  /// uygun, ağ için ucuz.
  ///
  /// Not: çağıran interval'i kendisi belirleyebilir
  /// ([fetchHistoryAtInterval]); `HistoryService.getSymbolHistory` bunu
  /// çözünürlük katmanından türetir ve bu eşlemeye hiç uğramaz.
  String _intervalFor(String range) => switch (range) {
        '1d' => '5m',
        '5d' => '1h',
        '1mo' => '1d',
        '3mo' => '1d',
        '6mo' => '1d',
        '1y' => '1wk',
        _ => '1d',
      };

  // Yahoo range → TEFAS periyod (ay cinsinden: 1,3,6,12,36,60)
  int _tefasPeriyodFor(String range) => switch (range) {
        '1d' || '5d' || '1mo' => 1,
        '3mo' => 3,
        '6mo' => 6,
        '1y'  => 12,
        '3y'  => 36,
        '5y'  => 60,
        _     => 3,
      };
}
