import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'crash_reporter.dart';

/// Adı devlet katkısı fonu mu?
///
/// TEFAS'taki gerçek adlar "… KATKI EMEKLİLİK YATIRIM FONU" ve "… KATILIM
/// KATKI EMEKLİLİK YATIRIM FONU"dur — "DEVLET" kelimesi GEÇMEZ. İlk sürüm
/// yalnız "DEVLET KATKI" arıyordu; seçici hiçbir fonu tanımıyor, BES
/// formunda devlet katkısı girilemiyordu (2026-10-01 emülatör testi).
/// `toUpperCase` Türkçe değildir (i → I), eski küçük harfli önbellek kaydı
/// için İ/I ikisi de kabul edilir.
bool devletKatkisiAdiMi(String ad) =>
    _devletKatkisiAdi.hasMatch(ad.toUpperCase());
final RegExp _devletKatkisiAdi =
    RegExp(r'KATKI EMEKL[İI]L[İI]K|DEVLET KATKI');

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

  /// TEFAS'ın `fonTurAciklama` alanı — "Hisse Senedi Şemsiye Fonu",
  /// "Para Piyasası Şemsiye Fonu"… Fon karnesi (F4, 2026-09-29) bir fonu
  /// yalnızca AYNI kategorideki fonlarla kıyaslar; farklı kategorideki
  /// fonlarla getiri sırası anlamsızdır (hisse fonu ile para piyasası fonu
  /// aynı yarışta koşmaz).
  ///
  /// Nullable: v1 disk önbelleğinde bu alan yoktu. Eski kayıt okunursa
  /// `null` kalır ve karne hiç çizilmez — kategori TAHMİN edilmez (uydurma
  /// sayı yasağının metin karşılığı).
  final String? kategori;

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
    this.kategori,
  });

  Map<String, dynamic> toJson() => {
        'c': code,
        'n': name,
        'p': price,
        't': fundType,
        'm': managerName,
        'r1m': return1m,
        'r3m': return3m,
        'r6m': return6m,
        'r1y': return1y,
        'ryd': returnYtd,
        'rl': riskLevel,
        'k': kategori,
      };

  static TefasFund? fromJson(Map<String, dynamic> j) {
    final c = j['c'] as String?;
    final n = j['n'] as String?;
    if (c == null || n == null) return null;
    return TefasFund(
      code: c,
      name: n,
      price: (j['p'] as num?)?.toDouble() ?? 0.0,
      fundType: (j['t'] as String?) ?? 'YAT',
      managerName: (j['m'] as String?) ?? '',
      return1m: (j['r1m'] as num?)?.toDouble(),
      return3m: (j['r3m'] as num?)?.toDouble(),
      return6m: (j['r6m'] as num?)?.toDouble(),
      return1y: (j['r1y'] as num?)?.toDouble(),
      returnYtd: (j['ryd'] as num?)?.toDouble(),
      // `as num?` — JSON'dan tamsayı bazen `double` olarak döner
      // (ör. 3.0); `as int?` o durumda fırlatır ve TÜM katalog okuması
      // "bozuk önbellek" sayılıp ağa düşerdi.
      riskLevel: (j['rl'] as num?)?.toInt(),
      // Eski (v1) kayıtta anahtar yok → null. Boş metin de "bilinmiyor".
      kategori: _bosIseNull(j['k'] as String?),
    );
  }

  static String? _bosIseNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

class TefasService {
  static final TefasService instance = TefasService._();
  TefasService._();

  final _client = http.Client();

  List<TefasFund>? _cachedFunds;
  DateTime? _cacheTime;
  bool _diskLoaded = false;

  // Kod → (price, timestamp). refreshPrices sırasında yazılır, TTL bitene
  // kadar hem RAM hem disk'ten servis eder. Portföyde 20 fon varsa 20
  // ayrı HTTP isteği yerine cache'ten anında geliyor.
  final Map<String, ({double price, DateTime ts})> _priceCache = {};
  bool _priceDiskLoaded = false;

  static const _baseUrl = 'https://www.tefas.gov.tr';
  static const _listEndpoint  = '/api/funds/fonGetiriBazliBilgiGetir';
  static const _priceEndpoint = '/api/funds/fonFiyatBilgiGetir';

  // Fon kataloğu DOSYADA, SharedPreferences'ta DEĞİL (2026-09-28).
  //
  // Eskiden `tefas_funds_cache_v1` anahtarıydı ve tek başına 497 KB'tı
  // (tercih dosyası 610 KB). Android SharedPreferences dosyanın TAMAMINI ilk
  // erişimde okuyup ayrıştırıyor: `initPreferencesCache` açılışta ~450 ms
  // bekliyordu (profile build, ölçüldü) — yalnız fon aramasında gereken bir
  // liste için HER açılışta. Dosya yalnız katalog istendiğinde okunur.
  // Şema değişirse dosya adının sürümünü artır → eski dosya yok sayılır.
  //
  // v2 (2026-09-29, F4 fon karnesi): kayda `k` (kategori, `fonTurAciklama`)
  // eklendi. v1 dosyası 24 saat daha "taze" sayılıp kategorisiz katalog
  // döndürürdü → karne bir güne kadar hiç görünmezdi. Ad değişince eski
  // dosya okunmaz, katalog bir kez ağdan yeniden çekilir (ilk fon araması
  // ya da karne açılışında — normal 24 saatlik yenilemeyle aynı istek).
  // `fromJson` eksik alanı yine `null` sayar: sürüm artırmak yalnız hızlı
  // geçiş içindir, okuma tarafı eski biçime karşı ZATEN dayanıklıdır.
  static const _dosyaAdi = 'tefas_funds_cache_v2.json';
  // Önceki sürüm dosyaları — yalnız SİLMEK için (~500 KB diskte kalmasın).
  static const _eskiDosyaAdlari = ['tefas_funds_cache_v1.json'];
  // Eski yerdeki anahtarlar — yalnız SİLMEK için (tercih dosyası küçülsün).
  static const _eskiPrefsCacheKey = 'tefas_funds_cache_v1';
  static const _eskiPrefsCacheTsKey = 'tefas_funds_cache_ts_v1';
  // Fon fiyatları ayrı cache — liste cache'i (fon meta) 24 saat yaşar ama
  // fiyatlar çok daha çabuk eskir. Kod→{price, ts} formatında saklanır.
  static const _prefsPricesKey = 'tefas_prices_cache_v1';
  static const _pricesCacheTtl = Duration(minutes: 30);

  static const _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36',
  };

  // Disk cache 24 saat, RAM cache 1 saat — RAM eskiyse ve disk hâlâ tazeyse
  // diski RAM'e yükleyip ondan devam et; hem sürat hem daha az ağ isteği.
  static const _diskCacheTtl = Duration(hours: 24);
  static const _ramCacheTtl = Duration(hours: 1);

  bool get _cacheValid =>
      _cachedFunds != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _ramCacheTtl;

  Future<File?> _katalogDosyasi() async {
    try {
      final klasor = await getApplicationSupportDirectory();
      return File('${klasor.path}/$_dosyaAdi');
    } catch (_) {
      return null; // test ortamı / eklenti yok → yalnız RAM önbelleği
    }
  }

  /// Eski tercih anahtarlarını bir kez sil — içerik taşınmaz (24 saatlik
  /// önbellek, ağdan yeniden gelir); amaç tercih dosyasını küçültmek.
  Future<void> eskiOnbellegiTemizle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_eskiPrefsCacheKey)) {
        await prefs.remove(_eskiPrefsCacheKey);
        await prefs.remove(_eskiPrefsCacheTsKey);
      }
    } catch (_) {}
    try {
      final klasor = await getApplicationSupportDirectory();
      for (final ad in _eskiDosyaAdlari) {
        final eski = File('${klasor.path}/$ad');
        if (await eski.exists()) await eski.delete();
      }
    } catch (_) {} // test ortamı / eklenti yok / dosya kilitli — önemsiz
  }

  Future<void> _loadFromDisk() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    CrashReporter.arkaPlan(eskiOnbellegiTemizle(), reason: 'tefas_service.eskiOnbellegiTemizle');
    try {
      final dosya = await _katalogDosyasi();
      if (dosya == null || !await dosya.exists()) return;
      final kayit = jsonDecode(await dosya.readAsString()) as Map<String, dynamic>;
      final ts = kayit['ts'] as int?;
      if (ts == null) return;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts));
      if (age > _diskCacheTtl) return; // eski, ağdan çekilsin
      final list = kayit['funds'] as List;
      final funds = <TefasFund>[];
      for (final e in list) {
        final f = TefasFund.fromJson(e as Map<String, dynamic>);
        if (f != null) funds.add(f);
      }
      if (funds.isNotEmpty) {
        _cachedFunds = funds;
        _cacheTime = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    } catch (_) {
      // Bozuk cache — sessizce yok say, ağdan çekilir.
    }
  }

  Future<void> _saveToDisk() async {
    if (_cachedFunds == null || _cachedFunds!.isEmpty) return;
    try {
      final dosya = await _katalogDosyasi();
      if (dosya == null) return;
      await dosya.writeAsString(jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'funds': _cachedFunds!.map((f) => f.toJson()).toList(),
      }));
    } catch (_) {
      // Disk yazımı başarısız olsa da RAM cache çalışır.
    }
  }

  Future<void> _loadPricesFromDisk() async {
    if (_priceDiskLoaded) return;
    _priceDiskLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsPricesKey);
      if (jsonStr == null) return;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final now = DateTime.now();
      for (final entry in map.entries) {
        final v = entry.value as Map<String, dynamic>;
        final p = (v['p'] as num?)?.toDouble();
        final ts = v['ts'] as int?;
        if (p == null || p <= 0 || ts == null) continue;
        final t = DateTime.fromMillisecondsSinceEpoch(ts);
        // TTL geçmişse ignore et — eski fiyat kullanma.
        if (now.difference(t) > _pricesCacheTtl) continue;
        _priceCache[entry.key] = (price: p, ts: t);
      }
    } catch (_) {
      // Bozuk cache — sessizce yok say.
    }
  }

  Future<void> _savePricesToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, Map<String, dynamic>>{};
      for (final entry in _priceCache.entries) {
        map[entry.key] = {
          'p': entry.value.price,
          'ts': entry.value.ts.millisecondsSinceEpoch,
        };
      }
      await prefs.setString(_prefsPricesKey, jsonEncode(map));
    } catch (_) {}
  }

  bool _priceFresh(String code) {
    final entry = _priceCache[code];
    if (entry == null) return false;
    return DateTime.now().difference(entry.ts) < _pricesCacheTtl;
  }

  // ── Tüm fonları çek ───────────────────────────────────────────────────────

  /// 1007+ TEFAS fonunu portföy yönetim şirketi ve performans verileriyle döner.
  /// İlk çağrıda cache boşsa ağdan çeker; sonrasında cache'ten döner.
  /// Devlet katkısı fonları — doğrudan TEFAS `islem: 0` listesinden.
  ///
  /// Katalog (`fetchAllFunds`) üzerinden süzmek yetmedi: emülatör testinde
  /// (2026-10-01) diskteki katalogda 24 katkı fonu varken seçici boş geldi;
  /// katalog RAM'de başka yollarla (tek fon fiyatı) yeniden kuruluyor ve
  /// birleştirmedeki ağ hatası sessizce boş listeye düşüyor. Burada hata
  /// FIRLATILIR — seçici "eşleşen fon yok" yerine hatayı gösterir.
  Future<List<TefasFund>> fetchDevletKatkisiFonlari() async {
    final onbellek = _dkFonlari;
    if (onbellek != null && onbellek.isNotEmpty) return onbellek;
    final l = [
      for (final f in await _fetchFundList('EMK', islem: 0))
        if (devletKatkisiAdiMi(f.name)) f,
    ]..sort((a, b) => a.name.compareTo(b.name));
    _dkFonlari = l;
    return l;
  }

  List<TefasFund>? _dkFonlari;

  Future<List<TefasFund>> fetchAllFunds({bool forceRefresh = false}) async {
    // RAM cache taze → direkt döndür.
    if (!forceRefresh && _cacheValid) return _cachedFunds!;

    // RAM yok / eski ise disk'i dene (24 saatlik cache). Buradan doldurursa
    // uygulama açılışı anında ağa hiç çıkılmaz.
    if (!forceRefresh) {
      await _loadFromDisk();
      if (_cacheValid) return _cachedFunds!;
    }

    try {
      // TEFAS'ın 3 fon tipini çek: YAT (yatırım), EMK (emeklilik),
      // BYF (borsa yatırım fonu / ETF). Aynı kod farklı tiplerde
      // tekrar edebilir — dedupe için code→fund map'e yaz.
      final results = await Future.wait([
        _fetchFundList('YAT').catchError((_) => <TefasFund>[]),
        _fetchFundList('EMK').catchError((_) => <TefasFund>[]),
        _fetchFundList('BYF').catchError((_) => <TefasFund>[]),
        // Devlet katkısı fonları TEFAS'ta İŞLEM GÖRMEZ: `islem: 1` listesinde
        // yoklar, yalnız `islem: 0`'da (2026-10-01: 24 katkı fonu). Fiyatları
        // `fonFiyatBilgiGetir`'den normal gelir. Listenin geri kalanı (işlem
        // görmeyen OKS/grup fonları) fon aramasına karışmasın diye alınmaz.
        _fetchFundList('EMK', islem: 0)
            .then((l) => [
                  for (final f in l)
                    if (devletKatkisiAdiMi(f.name)) f,
                ])
            .catchError((_) => <TefasFund>[]),
      ]);
      final byCode = <String, TefasFund>{};
      for (final list in results) {
        for (final f in list) {
          byCode.putIfAbsent(f.code, () => f);
        }
      }
      final funds = byCode.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (funds.isNotEmpty) {
        _cachedFunds = funds;
        _cacheTime = DateTime.now();
        // Diske asenkron yaz — çağıranı bekletme.
        CrashReporter.arkaPlan(_saveToDisk(), reason: 'tefas_service._saveToDisk');
        return funds;
      }
    } catch (e) {
      _log('fetchAllFunds error: $e');
    }

    // Cache varsa (RAM veya disk'ten yüklenmiş) eski veriyle devam et
    if (_cachedFunds != null) return _cachedFunds!;
    return [];
  }

  /// Belirli fon kodları için güncel NAV fiyatlarını çeker.
  /// Fiyat cache mimarisi (30 dk TTL):
  ///   1. RAM `_priceCache` taze → direkt kullan
  ///   2. Uygulama açılışında disk'ten yükle (bir kereye mahsus)
  ///   3. Cache'te olmayan / eskimiş kodlar için `fonFiyatBilgiGetir`
  ///      endpoint'ine tek tek istek gönder — cevabı cache'e yaz.
  ///
  /// NOT: `fetchAllFunds` liste endpoint'i fiyat döndürmüyor (hep 0). Bu
  /// yüzden liste cache'ini fiyat kaynağı olarak kullanmıyoruz; fiyatlar
  /// yalnızca `fonFiyatBilgiGetir` üzerinden gelir.
  ///
  /// [forceRefresh] kullanıcı açıkça yenileme istediğinde (pull-to-refresh)
  /// 30 dakikalık TTL'i atlar — bayat NAV görmemeli.
  Future<Map<String, double>> fetchPrices(
    List<String> codes, {
    bool forceRefresh = false,
  }) async {
    if (codes.isEmpty) return {};

    await _loadPricesFromDisk();

    final result = <String, double>{};
    final missing = <String>[];

    for (final c in codes) {
      if (!forceRefresh && _priceFresh(c)) {
        result[c] = _priceCache[c]!.price;
      } else {
        missing.add(c);
      }
    }

    if (missing.isEmpty) return result;

    // Eksik olanlar için tek tek fiyat endpoint'ini çağır. Paralel istekler
    // (Future.wait) — TEFAS aynı anda ~10 isteği kabul ediyor.
    try {
      final futures = missing.map((code) async {
        final price = await _fetchSinglePrice(code);
        return MapEntry(code, price);
      }).toList();
      final results = await Future.wait(futures);
      final now = DateTime.now();
      var dirty = false;
      for (final entry in results) {
        final p = entry.value;
        if (p != null && p > 0) {
          result[entry.key] = p;
          _priceCache[entry.key] = (price: p, ts: now);
          dirty = true;
        }
      }
      if (dirty) CrashReporter.arkaPlan(_savePricesToDisk(), reason: 'tefas_service._savePricesToDisk');
    } catch (e) {
      _log('fetchPrices error: $e');
    }

    return result;
  }

  /// Tek fon için güncel fiyatı `fonFiyatBilgiGetir` endpoint'inden çeker.
  ///
  /// ## ⚠️ Fon listesi cache'ine ASLA düşmez
  ///
  /// Bu metot eskiden `lookupFund`'a delege ediyordu. `lookupFund` ise ÖNCE
  /// `_cachedFunds` listesine bakıp bulduğunu döndürüyor — ve o listedeki
  /// her fonun fiyatı **0'dır** (`_fetchFundList` fiyat alanını
  /// döndürmüyor, `price: 0.0` yazıyor). Sonuç iki katmanlı bir sessiz
  /// arıza oluyordu:
  ///
  ///   1. Kullanıcı bir kez fon listesini açar → `_cachedFunds` fiyatsız
  ///      1000+ fonla dolar ve **24 saat** diskte yaşar.
  ///   2. Ondan sonra `fetchPrices` her çağrıldığında `lookupFund` o
  ///      fiyatsız kaydı bulur, `price > 0` kapısına takılır ve `null`
  ///      döner. Yani fon fiyatı ağdan HİÇ çekilmez; portföyde varlığın
  ///      en son kaydedilen `currentPrice`'ı kalır.
  ///
  /// Belirtisi (kullanıcı bildirimi 2026-09-10): "Fonların günlük değerleri
  /// güncel çekilmiyor… fonları açınca bir süre sonra data geliyor."
  /// Gecikmeli gelen veri, listenin cache'i düştükten sonraki ilk
  /// `lookupFund` ağ çağrısıydı.
  ///
  /// Doğrusu: fiyat sorusu HER ZAMAN fiyat endpoint'ine sorulur. Liste
  /// cache'i yalnızca fonun ADI/ÜNVANI için bir kaynaktır.
  Future<double?> _fetchSinglePrice(String code) async {
    final fetched = await _fetchPriceRow(code);
    return fetched?.price;
  }

  /// TEFAS liste endpoint'inde (`fonGetiriBazliBilgiGetir`) görünmeyen ama
  /// fiyat endpoint'inde (`fonFiyatBilgiGetir`) yer alan fonlar için lookup.
  /// Kurucu-only fonlar (ALE, YLB gibi) TEFAS liste API'sinde yok ama
  /// fiyat API'sinde fiyat + ünvan döndürüyor. Kullanıcı bir kod yazdığında
  /// ve normal listede bulunmadığında bu metod çağrılır; bulunursa cache'e
  /// eklenir ve normal fon gibi davranır.
  ///
  /// Cache'ten dönen kayıt FİYATSIZ olabilir (liste endpoint'i fiyat
  /// vermiyor). O durumda fiyat için yine ağa çıkılır — çağıranların
  /// çoğu (arama, ekleme ekranı) fiyatı da bekliyor.
  Future<TefasFund?> lookupFund(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    // Cache'te fiyatıyla birlikte varsa döndür. Fiyatsız kayıt (liste
    // endpoint'inden gelen) yeterli DEĞİLDİR — aşağıda fiyatla tamamlanır.
    TefasFund? cached;
    if (_cachedFunds != null) {
      for (final f in _cachedFunds!) {
        if (f.code == normalized) {
          cached = f;
          break;
        }
      }
    }
    if (cached != null && cached.price > 0) return cached;
    // Taze fiyat cache'i varsa ağa çıkmadan tamamla.
    if (cached != null && _priceFresh(normalized)) {
      return _withPrice(cached, _priceCache[normalized]!.price);
    }

    final fetched = await _fetchPriceRow(normalized);
    if (fetched == null) return cached; // ağ düştü → elde ne varsa o

    // Ad/ünvan bilgisi liste kaydında daha zengin olabilir; onu koru.
    final fund = cached != null
        ? _withPrice(cached, fetched.price)
        : TefasFund(
            code: normalized,
            name: fetched.unvan.isEmpty ? normalized : fetched.unvan,
            price: fetched.price,
            // Liste endpoint'inde olmayan fonların tipini bilmiyoruz — YAT
            // olarak varsay (kullanıcının göreceği kategori "fon").
            fundType: 'YAT',
            managerName: _parseManagerName(fetched.unvan),
          );

    // Cache'e ekle/güncelle — bir daha aynı kod için fetchAllFunds arasa
    // bulur ve bu sefer FİYATLI bulur.
    //
    // Katalog henüz yüklenmediyse ÖNCE diskten yüklenir (2026-10-01):
    // açılıştaki fiyat turu portföydeki fonları burada ararken RAM boştu;
    // boş listeye tek fon eklenip `_saveToDisk` ile yazılınca 24 saatlik
    // katalog o birkaç fonla eziliyordu.
    if (_cachedFunds == null) await _loadFromDisk();
    final liste = <TefasFund>[...(_cachedFunds ?? const <TefasFund>[])];
    final idx = liste.indexWhere((f) => f.code == normalized);
    if (idx >= 0) {
      liste[idx] = fund;
    } else {
      liste.add(fund);
    }
    _cachedFunds = liste;
    // Kurucu-only fonlar da kalıcı olsun — kullanıcı bir kez eklediğinde
    // sonraki açılışlarda yeniden lookup gerektirmesin. Yalnız elde TAM
    // katalog varken (`_cacheTime` dolu): eksik liste diske yazılmaz.
    if (_cacheTime != null) {
      CrashReporter.arkaPlan(_saveToDisk(),
          reason: 'tefas_service._saveToDisk');
    }
    return fund;
  }

  /// Aynı fonun fiyatı güncellenmiş kopyası.
  static TefasFund _withPrice(TefasFund f, double price) => TefasFund(
        code: f.code,
        name: f.name,
        price: price,
        fundType: f.fundType,
        managerName: f.managerName,
        return1m: f.return1m,
        return3m: f.return3m,
        return6m: f.return6m,
        return1y: f.return1y,
        returnYtd: f.returnYtd,
        riskLevel: f.riskLevel,
        // Kopyada kategori düşerse fon, fiyatı bir kez sorulduktan sonra
        // karne sıralamasından sessizce çıkardı (kategori sayısı da bir
        // eksik yazılırdı).
        kategori: f.kategori,
      );

  /// `fonFiyatBilgiGetir` çağrısının HAM sonucu — fiyat + ünvan.
  ///
  /// Fiyat cache'ini burada yazar: her çağıran (fiyat yenileme, arama,
  /// kurucu-only lookup) aynı taze değeri paylaşsın.
  Future<({double price, String unvan})?> _fetchPriceRow(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    try {
      final body =
          jsonEncode({'fonKodu': normalized, 'dil': 'TR', 'periyod': 1});
      final res = await _client
          .post(Uri.parse('$_baseUrl$_priceEndpoint'),
              headers: _headers, body: body)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final items = (data['resultList'] as List?) ?? [];
      if (items.isEmpty) return null;

      // En güncel kaydı al — liste tarih sıralı, son eleman en yeni
      Map<String, dynamic>? latest;
      double? price;
      for (int i = items.length - 1; i >= 0; i--) {
        final row = items[i] as Map<String, dynamic>;
        final raw = row['fiyat'] ?? row['birimPayDegeri'];
        final p = raw != null ? double.tryParse(raw.toString()) : null;
        if (p != null && p > 0) {
          latest = row;
          price = p;
          break;
        }
      }
      if (latest == null || price == null) return null;

      _priceCache[normalized] = (price: price, ts: DateTime.now());
      CrashReporter.arkaPlan(_savePricesToDisk(), reason: 'tefas_service._savePricesToDisk');

      return (
        price: price,
        unvan: _fixEncoding(latest['fonUnvan'] as String? ?? '').trim(),
      );
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
    _diskLoaded = false;
    _priceCache.clear();
    _priceDiskLoaded = false;
    CrashReporter.arkaPlan(_clearDiskCache(), reason: 'tefas_service._clearDiskCache');
  }

  Future<void> _clearDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_eskiPrefsCacheKey);
      await prefs.remove(_eskiPrefsCacheTsKey);
      await prefs.remove(_prefsPricesKey);
      final dosya = await _katalogDosyasi();
      if (dosya != null && await dosya.exists()) await dosya.delete();
    } catch (_) {}
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<List<TefasFund>> _fetchFundList(String fonTipi, {int islem = 1}) async {
    final payload = {
      'dil': 'TR',
      'fonTipi': fonTipi,
      'kurucuKodu': null,
      'sfonTurKod': null,
      'fonTurAciklama': null,
      // 1 = TEFAS'ta işlem gören fonlar; 0 = görmeyenler (katkı fonları).
      'islem': islem,
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
              kategori: TefasFund._bosIseNull(
                  _fixEncoding(d['fonTurAciklama'] as String? ?? '')),
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
