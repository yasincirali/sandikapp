import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import 'price_service.dart';

/// Grafik çözünürlük seviyeleri. Zoom yaptıkça daha ince tier'a düşer.
enum ResolutionTier {
  fiveMin, // 5 dakikalık — sadece bugün için (1d range)
  hourly, // 1 saatlik — son 5-7 gün (5d range)
  daily, // günlük close — son 30-180 gün
  weekly, // haftalık close — 1 yıl+ (uzun dönem)
}

extension ResolutionTierMeta on ResolutionTier {
  /// Yahoo API range parametresi
  String get yahooRange => switch (this) {
        ResolutionTier.fiveMin => '1d',
        // 1H periyot 7 gün ister — Yahoo 5d döner ve sol tarafta boşluk kalır.
        // 1mo döndür (Yahoo 1h intervalinde 1mo'ya kadar destekler).
        ResolutionTier.hourly => '1mo',
        ResolutionTier.daily => '1y',
        ResolutionTier.weekly => '5y',
      };

  /// Yahoo API interval parametresi (PriceService._intervalFor ile uyumlu)
  String get yahooInterval => switch (this) {
        ResolutionTier.fiveMin => '5m',
        ResolutionTier.hourly => '1h',
        ResolutionTier.daily => '1d',
        ResolutionTier.weekly => '1wk',
      };

  /// Bu tier'da ts'yi hangi ölçekte normalize edelim (aynı bucket'a düşen
  /// noktalar tek değer olur).
  int normalizeTs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    switch (this) {
      case ResolutionTier.fiveMin:
        final snappedMin = (d.minute ~/ 5) * 5;
        return DateTime(d.year, d.month, d.day, d.hour, snappedMin)
            .millisecondsSinceEpoch;
      case ResolutionTier.hourly:
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      case ResolutionTier.daily:
        return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      case ResolutionTier.weekly:
        // Haftanın pazartesi 00:00'ına snap
        final wd = d.weekday; // 1..7
        final monday = DateTime(d.year, d.month, d.day)
            .subtract(Duration(days: wd - 1));
        return monday.millisecondsSinceEpoch;
      }
  }

  /// Görünen aralığın gün cinsinden genişliğine göre optimal tier seçimi.
  /// Trading uygulamalarındaki gibi ~30-300 nokta hedefler.
  static ResolutionTier pickForSpan(double viewportDays) {
    if (viewportDays < 5) return ResolutionTier.fiveMin;
    if (viewportDays < 30) return ResolutionTier.hourly;
    if (viewportDays < 180) return ResolutionTier.daily;
    return ResolutionTier.weekly;
  }
}

class HistoryService {
  static final HistoryService instance = HistoryService._();
  HistoryService._();

  /// Ticker başına fiyat serisi önbelleği.
  ///
  /// LRU + TTL: `static` olduğu için süreç ömrü boyunca yaşar. Sınırsız
  /// bırakılırsa her ticker'ın 365 günlük serisi bellekte birikir; periyotlar
  /// arasında gezinen, çok varlıklı bir portföyde onlarca MB'a çıkar.
  /// `LinkedHashMap` ekleme sırasını korur → en eski giriş ilk atılır.
  static final Map<String, List<(int, double)>> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};

  /// Aynı oturumda tekrar tekrar çekmeyi önlemeye yetecek kadar uzun,
  /// gün içi fiyat hareketini kaçırmayacak kadar kısa.
  static const _cacheTtl = Duration(minutes: 15);
  static const _cacheMaxEntries = 50;

  static List<(int, double)>? _cacheGet(String key) {
    final at = _cacheAt[key];
    if (at == null) return null;
    if (DateTime.now().difference(at) > _cacheTtl) {
      _cache.remove(key);
      _cacheAt.remove(key);
      return null;
    }
    return _cache[key];
  }

  static void _cachePut(String key, List<(int, double)> value) {
    // Yeniden ekleme sırayı tazeler (LRU davranışı).
    _cache.remove(key);
    _cacheAt.remove(key);
    _cache[key] = value;
    _cacheAt[key] = DateTime.now();
    while (_cache.length > _cacheMaxEntries) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _cacheAt.remove(oldest);
    }
  }

  /// Bellek baskısında veya oturum kapanışında çağrılabilir.
  static void clearCache() {
    _cache.clear();
    _cacheAt.clear();
  }

  /// Verilen varlıkların ilgili periyot için (örn. 365 gün) geçmiş fiyatlarını
  /// gün-den-güne hesaplar. Dönen map: { UNIX_MILLIS: TOPLAM_PORTFOY_DEGERI_TRY }
  ///
  /// [simulate] true iken: her lot'un `addedDate`'i ve alım/satış geçmişi
  /// yok sayılır — tüm dönem boyunca bugünkü net miktar sabit tutulur.
  /// "Şu anki portföyüm o zaman elimde olsaydı ne olurdu?" senaryosunu
  /// çizer. Bu modda arayan `assets` olarak aggregate edilmiş (net)
  /// display-asset listesini verir; buy/sell ayrımı olmaz.
  ///
  /// DİKKAT — simülasyon "hiç satmasaydım" DEĞİLDİR. Gelen liste zaten net
  /// pozisyondur: 100 alıp 40 sattıysan simülasyon 60 adet üzerinden çizer,
  /// satılan 40 hiç var olmamış sayılır. Senaryo "bu portföyü daha erken
  /// kursaydım"dır. Bu bilinçli bir ürün kararıdır (kullanıcı onayı
  /// 2026-08-10); davranış `test/simulation_semantics_test.dart` içinde
  /// sabitlenmiştir — değiştirmeden önce o testi ve sahibini kontrol et.
  Future<Map<int, double>> getPortfolioHistory(
      List<Asset> assets, int periodDays,
      {bool simulate = false}) async {
    // Haftalık (7 gün) → saatlik veri: `5d` range + `1h` interval.
    // Diğer dönemler günlük veya haftalık.
    final bool hourly = periodDays <= 7;
    final range = periodDays > 100
        ? '1y'
        : periodDays > 60
            ? '3mo'
            : periodDays > 20
                ? '1mo'
                : hourly
                    ? '5d'
                    : '1mo';

    // Haftalık'ta saat başına, diğerlerinde gece yarısına normalize.
    int normalizeTs(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (hourly) {
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      }
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }

    final groupedPoints = <int, double>{};
    final now = DateTime.now();

    // Her bir varlık için günlük fiyat eşleşmesi tutalım donmuş/gerçek fiyatlar
    final Map<String, Map<int, double>> tickerNormalizedDaily = {};

    Map<int, double> usdTryHistory = {};
    Map<int, double> goldHistory = {};

    bool needsGold = assets.any((a) => a.type == AssetType.altin);
    bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    Future<List<(int, double)>> getHistorySafe(String sym) async {
      final cacheKey = '${sym}_$range';
      final cached = _cacheGet(cacheKey);
      if (cached != null) return cached;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, range);
        if (pts.isNotEmpty) _cachePut(cacheKey, pts);
        return pts;
      } catch (e) {
        return [];
      }
    }

    // -- Ağ çağrıları --
    //
    // Tüm semboller TEK SEFERDE başlatılır. Eskiden USD → altın → her ticker
    // sırayla `await` ediliyordu: 15 varlıklı bir portföyde 15 gidiş-dönüş
    // ardışık toplanıyor ve grafik ekranı saniyelerce spinner gösteriyordu.
    // İstekler birbirinden bağımsız olduğu için paralel başlatılabilir;
    // toplam süre en yavaş tek isteğe iner. (`getHistorySafe` zaten kendi
    // içinde hata yutar, bu yüzden `Future.wait` bir sembol patlasa da
    // diğerlerini düşürmez.)
    //
    // Not: altın hesabı USD serisine bağımlı — ikisi paralel ÇEKİLİR ama
    // dönüşüm her ikisi de geldikten sonra yapılır (sıra korunur).
    final usdFuture =
        needsUsd ? getHistorySafe('USDTRY=X') : Future.value(const <(int, double)>[]);
    final goldFuture =
        needsGold ? getHistorySafe('GC=F') : Future.value(const <(int, double)>[]);

    // Çekilecek benzersiz ticker'ları önce topla — aynı ticker'ın birden çok
    // lot'u varsa tek istek yapılsın.
    final tickerFutures = <String, Future<List<(int, double)>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (!fetchable) continue;
      tickerFutures.putIfAbsent(a.ticker, () => getHistorySafe(a.ticker));
    }

    if (needsUsd) {
      final usdPoints = await usdFuture;
      for (final p in usdPoints) {
        usdTryHistory[normalizeTs(p.$1)] = p.$2;
      }
    }

    if (needsGold) {
      final xauPoints = await goldFuture;
      for (final p in xauPoints) {
        final dTs = normalizeTs(p.$1);
        final xauUsd = p.$2;
        double usdRate = 35.0;
        if (usdTryHistory.containsKey(dTs)) {
          usdRate = usdTryHistory[dTs]!;
        } else if (usdTryHistory.isNotEmpty) {
          final closest = usdTryHistory.entries.lastWhere((e) => e.key <= dTs,
              orElse: () => usdTryHistory.entries.first);
          usdRate = closest.value;
        }

        final xauTry = xauUsd * usdRate;
        final gram22k = PriceService.gram22kFromXauTry(xauTry);
        goldHistory[dTs] = gram22k;
      }
    }

    // Hisse, Emtia, Döviz ve TEFAS Fon API Verileri.
    // Fiyat serileri yukarıda zaten paralel başlatıldı (sadece BUY lot'ları,
    // ticker başına tek istek) — burada yalnızca sonuçlar toplanır.
    for (final entry in tickerFutures.entries) {
      final rawPts = await entry.value;
      final map = <int, double>{};
      for (final p in rawPts) {
        map[normalizeTs(p.$1)] = p.$2;
      }
      tickerNormalizedDaily[entry.key] = map;
    }

    // Her lot için "o gün geçerli miktar":
    // - simulate=true: addedDate yok sayılır, quantity tüm dönem boyunca
    //   sabit → "şu anki portföyümü geçmişte tutsaydım" senaryosu.
    // - simulate=false (gerçek):
    //   * Buy lot: addedDate <= dayTs ise +quantity, aksi 0.
    //   * Sell lot: addedDate <= dayTs ise -quantity.
    //   * deleteLog: skip.
    double signedQtyOnDay(Asset a, int dayTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      if (simulate) return a.quantity;
      final addedTs = normalizeTs(a.addedDate.millisecondsSinceEpoch);
      if (addedTs > dayTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // -- Toparlama ve Hizalama --
    // Haftalık'ta saat başına, diğerlerinde gün başına grid oluştur.
    final startMs =
        now.subtract(Duration(days: periodDays)).millisecondsSinceEpoch;
    final int stepMinutes = hourly ? 60 : 24 * 60;
    final int totalSteps = hourly ? periodDays * 24 : periodDays;
    for (int i = totalSteps; i >= 0; i--) {
      final slotDate =
          now.subtract(Duration(minutes: i * stepMinutes));
      final dayTs = normalizeTs(slotDate.millisecondsSinceEpoch);
      if (dayTs < normalizeTs(startMs)) continue;
      // Haftalık (saatlik) grid'de hafta sonlarını atla — trading apps'lerde
      // görüldüğü gibi Cts/Paz plato'sunu göstermeyelim. Diğer dönemlerde
      // (aylık, yıllık vs) gün grid'i kalır: haftada 5 nokta vs 7 çok
      // farklı değil.
      if (hourly) {
        final wd = slotDate.weekday; // 6=Cts, 7=Paz
        if (wd == DateTime.saturday || wd == DateTime.sunday) continue;
      }

      double dayTotalValue = 0.0;

      for (final a in assets) {
        try {
          final qty = signedQtyOnDay(a, dayTs);
          if (qty == 0) continue;

          double assetDayVal = 0.0;

          if (a.type == AssetType.altin) {
            if (goldHistory.isNotEmpty) {
              double factor = (a.ticker == 'ALTIN_CEYREK')
                  ? 1.75
                  : (a.ticker == 'ALTIN_YARIM')
                      ? 3.5
                      : (a.ticker == 'ALTIN_CUMHURIYET' ||
                              a.ticker == 'ALTIN_ATA')
                          ? 7.216
                          : 1.0;
              double price = _getClosestPrice(goldHistory, dayTs, null);
              assetDayVal = price * factor * qty;
            } else {
              assetDayVal = _flatFallback(a) * (qty / a.quantity);
            }
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.fon ||
              a.type == AssetType.doviz) {
            final map = tickerNormalizedDaily[a.ticker] ?? {};
            if (map.isNotEmpty) {
              double price = _getClosestPrice(map, dayTs, null);
              if (a.currency == 'USD') {
                double usdRate = usdTryHistory.isNotEmpty
                    ? _getClosestPrice(usdTryHistory, dayTs, 35.0)
                    : 35.0;
                price *= usdRate;
              }
              assetDayVal = price * qty;
            } else {
              assetDayVal = _flatFallback(a) * (qty / a.quantity);
            }
          } else {
            assetDayVal = _flatFallback(a) * (qty / a.quantity);
          }

          dayTotalValue += assetDayVal;
        } catch (e) {
          // Bir lot'un günü hesaplanamazsa, sadece o günkü işaretli
          // katkıyı fallback ile ekle — yine de negatif olamaz.
          dayTotalValue += _flatFallback(a);
        }
      }

      // Geçmişte satılan miktarlar buy'lardan büyük olsa (edge case)
      // negatif toplam çıkmasın.
      if (dayTotalValue < 0) dayTotalValue = 0;
      groupedPoints[dayTs] = dayTotalValue;
    }

    // Bugünün noktasını anlık portföy değerine sabitle (Yahoo API'sindeki
    // son gün datası bazen geç güncellenir; ana ekranla tutarlılık için).
    //
    // NOT: Altın için `currentPrice` adet fiyatı (Cumhuriyet ~40k gibi) iken
    // geçmiş serisi gram22k × factor × qty üzerinden hesaplanır — ölçekler
    // aynı olduğu için sadece live veri varsa altın için de kullan.
    final todayTs = normalizeTs(now.millisecondsSinceEpoch);
    if (groupedPoints.containsKey(todayTs)) {
      double liveTotal = 0.0;
      bool skipOverwrite = false;
      for (final a in assets) {
        if (a.isDeleteLog) continue;
        final qty = signedQtyOnDay(a, todayTs);
        if (qty == 0) continue;
        final price = a.currentPrice > 0 ? a.currentPrice : 0.0;
        if (price <= 0) {
          skipOverwrite = true;
          break;
        }
        double liveUsd = 40.0;
        if (usdTryHistory.isNotEmpty) {
          liveUsd = usdTryHistory.values.last;
        }
        final tryPrice = a.currency == 'USD' ? price * liveUsd : price;
        liveTotal += tryPrice * qty;
      }
      if (liveTotal < 0) liveTotal = 0;
      // TradingView tarzı: son bar canlı fiyattır — tarihsel bar'lara asla
      // dokunma, sapma eşiği kullanma. %30 kural, gerçek büyük hareketlerde
      // (yeni alım, döviz sıçraması) canlı toplamı bastırıp grafiği yanıltıyor.
      if (!skipOverwrite && liveTotal > 0) {
        groupedPoints[todayTs] = liveTotal;
      }
    }

    // Outlier smoothing: bir gün önceki ve sonraki noktaya göre >%1.5 sapan ama
    // önceki-sonraki arası fark %1'den az olan tek-gün spike'ları temizle. Bu,
    // Yahoo'nun bazı sembollerdeki tek-gün eksik/geç verisinden gelen V-dip
    // artefaktlarını (gerçek trend olmadan) yumuşatır.
    final sortedKeys = groupedPoints.keys.toList()..sort();
    for (int i = 1; i < sortedKeys.length - 1; i++) {
      final prev = groupedPoints[sortedKeys[i - 1]]!;
      final cur = groupedPoints[sortedKeys[i]]!;
      final next = groupedPoints[sortedKeys[i + 1]]!;
      if (prev <= 0 || next <= 0) continue;
      final devPrev = ((cur - prev) / prev).abs();
      final devNext = ((cur - next) / next).abs();
      final prevNextGap = ((next - prev) / prev).abs();
      if (devPrev > 0.015 && devNext > 0.015 && prevNextGap < 0.01) {
        groupedPoints[sortedKeys[i]] = (prev + next) / 2;
      }
    }

    return groupedPoints;
  }

  double _getClosestPrice(
      Map<int, double> map, int targetTs, double? fallbackValue) {
    final exact = map[targetTs];
    if (exact != null) return exact;
    // Yoksa en yakın geçmiş tarihi (haftasonu durumu vs) bul.
    // Intraday'de slot × varlık başına çağrılır — sıralı indeks + ikili
    // arama şart (bkz. _sortedKeys). Eskiden her çağrıda sort + where
    // yapıyordu.
    if (map.isEmpty) return fallbackValue ?? 0.0;
    final sortedKeys = _sortedKeys(map);
    final idx = _floorIndex(sortedKeys, targetTs);
    if (idx >= 0) return map[sortedKeys[idx]]!;
    // Geçmişte yoksa gelecekteki en yakın ilk günü dön
    return map[sortedKeys.first]!;
  }

  /// Gerçek geçmiş veri yoksa currentPrice'ı sabit kullan (simülasyon yok).
  double _flatFallback(Asset asset) {
    final price = asset.currentPrice > 0 ? asset.currentPrice : 0.0;
    // USD için sabit 35.0 yerine bir tahmin — history'de gerçek kur yoksa
    // en azından güncel kura yakın bir değer (~40) kullan; sabit 35 grafikte
    // %12 dip yaratıyordu.
    final tryPrice = asset.currency == 'USD' ? price * 40.0 : price;
    return tryPrice * asset.quantity;
  }

  /// Intraday (gün-içi) çözünürlükte portföy değeri.
  /// Yahoo `1d/5m` interval'i kullanılır → 5 dakikalık noktalar. Bugünün 00:00
  /// ile 23:59 arasındaki her 5 dakikalık slot için toplam TRY değeri döner.
  /// Anahtar: UNIX_MILLIS (5 dakikalık slota normalize).
  ///
  /// [hours] parametresi yalnızca X ekseni birim ölçeği (saat) için tutulur;
  /// gerçek çözünürlük 5 dakikadır (12x saatlik). Veri kaynağı borsa saatleri
  /// dışı slotlar için son bilinen fiyatı yayar (`_getClosestPrice`).
  Future<Map<int, double>> getPortfolioHistoryHourly(
      List<Asset> assets, int hours) async {
    const range = '1d';
    const slotMinutes = 5;

    int normalizeSlot(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final snappedMinute = (d.minute ~/ slotMinutes) * slotMinutes;
      return DateTime(d.year, d.month, d.day, d.hour, snappedMinute)
          .millisecondsSinceEpoch;
    }

    // Intraday'e özel "geçmişe yakın olan" price lookup. Standart
    // `_getClosestPrice` past yoksa gelecekteki en yakın slotu döndürüyor —
    // bu intraday grafiğinde borsa açılmadan önceki tüm slotlara açılış
    // fiyatını yayıyor ve grafiği düz gösteriyor. Burada past yoksa null
    // döndürüp o slotu atlıyoruz (grafik ilk gerçek veriden başlasın).
    double? pastOrNull(Map<int, double> map, int targetTs) {
      if (map.isEmpty) return null;
      final exact = map[targetTs];
      if (exact != null) return exact;
      // Sıralı indeks + ikili arama (bkz. _sortedKeys) — bu closure her
      // 5dk slot × varlık için çağrılıyor.
      final keys = _sortedKeys(map);
      final idx = _floorIndex(keys, targetTs);
      return idx < 0 ? null : map[keys[idx]];
    }

    // pastOrNull başarısızsa "en yakın nokta" ile fallback yap.
    // 40.0 gibi sabit sayı kullanmak eski/yeni tarihlerde büyük sapma yaratır.
    // Bu helper hiç değilse serinin en yakın gerçek değerini kullanır.
    double? closestOrNull(Map<int, double> map, int targetTs) {
      final past = pastOrNull(map, targetTs);
      if (past != null) return past;
      if (map.isEmpty) return null;
      // Geçmişte yok → ileride en yakın
      return map[_sortedKeys(map).first];
    }

    final now = DateTime.now();
    final Map<String, Map<int, double>> tickerSlots = {};
    Map<int, double> usdTrySlots = {};
    Map<int, double> goldSlots = {}; // TRY / gram22k

    Future<List<(int, double)>> getHistorySafe(String sym) async {
      final cacheKey = '${sym}_$range';
      final cached = _cacheGet(cacheKey);
      if (cached != null) return cached;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, range);
        if (pts.isNotEmpty) _cachePut(cacheKey, pts);
        return pts;
      } catch (_) {
        return [];
      }
    }

    bool needsGold = assets.any((a) => a.type == AssetType.altin);
    bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    // Tüm semboller tek seferde başlatılır — gerekçe için `getPortfolioHistory`
    // içindeki aynı bloğun açıklamasına bak.
    final usdFuture =
        needsUsd ? getHistorySafe('USDTRY=X') : Future.value(const <(int, double)>[]);
    final goldFuture =
        needsGold ? getHistorySafe('GC=F') : Future.value(const <(int, double)>[]);

    final tickerFutures = <String, Future<List<(int, double)>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty)) {
        tickerFutures.putIfAbsent(a.ticker, () => getHistorySafe(a.ticker));
      }
    }

    if (needsUsd) {
      final usd = await usdFuture;
      for (final p in usd) {
        usdTrySlots[normalizeSlot(p.$1)] = p.$2;
      }
    }

    if (needsGold) {
      // XAU/USD intraday (GC=F) + USDTRY intraday → gram22k TRY.
      final xau = await goldFuture;
      for (final p in xau) {
        final ts = normalizeSlot(p.$1);
        final xauUsd = p.$2;
        double usdRate = closestOrNull(usdTrySlots, ts) ?? 40.0;
        final xauTry = xauUsd * usdRate;
        final gram22k = PriceService.gram22kFromXauTry(xauTry);
        goldSlots[ts] = gram22k;
      }
    }

    // Fiyat serileri yukarıda paralel başlatıldı — burada sonuçlar toplanır.
    for (final entry in tickerFutures.entries) {
      final raw = await entry.value;
      final map = <int, double>{};
      for (final p in raw) {
        map[normalizeSlot(p.$1)] = p.$2;
      }
      tickerSlots[entry.key] = map;
    }

    // Slot-bazlı işaretli miktar. Bugünkü zaman dilimlerinde:
    // buy addedDate <= slot ise +qty, sell addedDate <= slot ise -qty.
    double signedQtyOnSlot(Asset a, int slotTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      final addedTs = normalizeSlot(a.addedDate.millisecondsSinceEpoch);
      if (addedTs > slotTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // Altın türü katsayısı (gram22k referansına göre).
    // Ağırlık tablosu `PriceService`'te tutulur; buradaki yerel kopya
    // ALTIN_RESAT'ı ATLIYORDU (tabloda 7.216 ile var ama switch'te yoktu),
    // yani Reşat altını grafikte gram altın gibi çiziliyor ve pozisyon
    // 7.216 kat düşük görünüyordu.
    double goldFactor(String ticker) => PriceService.goldWeightFactor(ticker);

    final groupedPoints = <int, double>{};

    // Bugünün 00:00'ından başlayarak 5 dakikalık grid üret.
    final dayStart = DateTime(now.year, now.month, now.day);
    final slotCount = hours * (60 ~/ slotMinutes); // 24h → 288 slot
    final nowTs = normalizeSlot(now.millisecondsSinceEpoch);

    // Her varlık için "seed" fiyatı — intraday veri henüz gelmediği
    // slotlarda kullanılır (dünkü kapanış proxy'si). Böylece bir varlığın
    // borsa açılışı gecikse bile grafik ilk slot'tan itibaren varlığı sayar
    // ve borsa açıldığında dik sıçrama olmaz, sadece intraday hareket
    // görünür.
    //
    // Seed önceliği:
    //   1. Yahoo intraday map'inin en erken (bugüne ait ilk) noktası —
    //      dünkü kapanışa en yakın değer.
    //   2. Yoksa currentPrice (canlı — genelde intraday map ile aynı
    //      mertebede).
    double? assetSeedTRY(Asset a) {
      double? unitTRY;
      if (a.type == AssetType.altin) {
        final firstTs = goldSlots.keys.isEmpty
            ? null
            : goldSlots.keys.reduce((x, y) => x < y ? x : y);
        if (firstTs != null) {
          unitTRY = goldSlots[firstTs]! * goldFactor(a.ticker);
        } else if (a.currentPrice > 0) {
          unitTRY = a.currentPrice;
        }
      } else if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          a.type == AssetType.doviz) {
        final map = tickerSlots[a.ticker] ?? {};
        double? unitLocal;
        if (map.isNotEmpty) {
          final firstTs = map.keys.reduce((x, y) => x < y ? x : y);
          unitLocal = map[firstTs];
        } else if (a.currentPrice > 0) {
          unitLocal = a.currentPrice;
        }
        if (unitLocal != null) {
          if (a.currency == 'USD') {
            final usdSeed = usdTrySlots.isNotEmpty
                ? usdTrySlots[
                    usdTrySlots.keys.reduce((x, y) => x < y ? x : y)]!
                : 40.0;
            unitTRY = unitLocal * usdSeed;
          } else {
            unitTRY = unitLocal;
          }
        }
      } else if (a.type == AssetType.fon && a.currentPrice > 0) {
        unitTRY = a.currentPrice;
      } else if (a.currentPrice > 0) {
        unitTRY = a.currentPrice;
      }
      return unitTRY;
    }

    for (int i = 0; i <= slotCount; i++) {
      final hourDate = dayStart.add(Duration(minutes: i * slotMinutes));
      final hourTs = normalizeSlot(hourDate.millisecondsSinceEpoch);
      // Gelecek slotları çizme — grafik "ŞİMDİ" marker'ında bitsin.
      if (hourTs > nowTs) break;

      double total = 0.0;
      // En az bir varlık için fiyat hesaplanabildiyse slot'u çiz. Bir
      // varlığın hiç fiyatı yoksa (kurucu-only fon, silinmiş sembol vs.)
      // O ASSET'İ yok say — tüm portföyü boşaltma.
      bool anyCovered = false;

      for (final a in assets) {
        try {
          final qty = signedQtyOnSlot(a, hourTs);
          if (qty == 0) continue;
          double? v;

          if (a.type == AssetType.altin) {
            final gram = pastOrNull(goldSlots, hourTs);
            if (gram != null) {
              v = gram * goldFactor(a.ticker) * qty;
            }
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.doviz) {
            final map = tickerSlots[a.ticker] ?? {};
            final price = pastOrNull(map, hourTs);
            if (price != null) {
              double p = price;
              if (a.currency == 'USD') {
                final usdRate = closestOrNull(usdTrySlots, hourTs) ?? 40.0;
                p *= usdRate;
              }
              v = p * qty;
            }
          }
          // Fon (TEFAS) intraday NAV yayınlamıyor — o gün için sabit
          // currentPrice kullanılır (alternatif yok).
          if (v == null && a.type == AssetType.fon && a.currentPrice > 0) {
            v = a.currentPrice * qty;
          }
          // Intraday verisi henüz gelmemiş varlıklar için seed fiyatı
          // kullan — grafik dik sıçramasın.
          if (v == null) {
            final seed = assetSeedTRY(a);
            if (seed != null) {
              v = seed * qty;
            }
          }

          if (v != null) {
            total += v;
            anyCovered = true;
          }
        } catch (_) {
          // Bu asset hesaplanamadı, diğerlerine devam et.
        }
      }

      if (!anyCovered) continue;
      if (total < 0) total = 0;
      groupedPoints[hourTs] = total;
    }

    // Son slotu anlık portföy toplamı ile hizala — grafiğin bitiş noktası
    // her zaman ana ekrandaki toplamla eşleşsin. currentPrice=0 olan
    // varlıklar (kurucu-fon vs.) hesap dışı, diğerleri toplama girer.
    if (groupedPoints.isNotEmpty) {
      double liveTotal = 0.0;
      for (final a in assets) {
        if (a.isDeleteLog) continue;
        final qty = signedQtyOnSlot(a, nowTs);
        if (qty == 0) continue;
        if (a.currentPrice <= 0) continue;
        final liveUsd = usdTrySlots.isNotEmpty
            ? usdTrySlots.values.last
            : 40.0;
        final tryPrice =
            a.currency == 'USD' ? a.currentPrice * liveUsd : a.currentPrice;
        liveTotal += tryPrice * qty;
      }
      if (liveTotal > 0) {
        final lastKey = groupedPoints.keys.reduce((a, b) => a > b ? a : b);
        groupedPoints[lastKey] = liveTotal;
      }
    }

    return groupedPoints;
  }

  // ── Tier-bazlı çözünürlük (zoom-aware) ────────────────────────────────────
  //
  // Cache: (tier, sembol) → ts→price map. Aynı tier+sembol tekrar istenirse
  // ağa çıkılmaz. Farklı tier'da aynı sembol için ayrı istek (Yahoo interval
  // farklı olduğundan).
  final Map<String, Map<int, double>> _tierCache = {};

  String _tierCacheKey(ResolutionTier tier, String symbol) =>
      '${tier.name}::$symbol';

  Future<Map<int, double>> _fetchTickerAtTier(
      String ticker, ResolutionTier tier) async {
    final key = _tierCacheKey(tier, ticker);
    final cached = _tierCache[key];
    if (cached != null) return cached;
    try {
      final pts = await PriceService.instance
          .fetchHistoryAtInterval(ticker, tier.yahooRange, tier.yahooInterval);
      final map = <int, double>{};
      for (final p in pts) {
        map[tier.normalizeTs(p.$1)] = p.$2;
      }
      _tierCache[key] = map;
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Verilen tarih aralığında ve tier'da portföy toplam değeri (TRY) döner.
  /// Zoom yaptıkça viewport daralır → tier ince olur → daha detaylı nokta.
  /// [assets] tüm buy/sell lot'ları içerir (deleteLog hariç filtrelenir).
  Future<Map<int, double>> getPortfolioHistoryAtResolution({
    required List<Asset> assets,
    required DateTime from,
    required DateTime to,
    required ResolutionTier tier,
    bool simulate = false,
  }) async {
    if (assets.isEmpty) return {};

    final normalizedFrom = tier.normalizeTs(from.millisecondsSinceEpoch);
    final normalizedTo = tier.normalizeTs(to.millisecondsSinceEpoch);
    final nowTs = tier.normalizeTs(DateTime.now().millisecondsSinceEpoch);

    // Gerekli sembolleri tespit et.
    bool needsGold = assets.any((a) => a.type == AssetType.altin);
    bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    final tickerFutures = <String, Future<Map<int, double>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (!fetchable) continue;
      tickerFutures.putIfAbsent(
          a.ticker, () => _fetchTickerAtTier(a.ticker, tier));
    }
    Future<Map<int, double>>? usdFuture;
    Future<Map<int, double>>? goldFuture;
    if (needsUsd) usdFuture = _fetchTickerAtTier('USDTRY=X', tier);
    if (needsGold) goldFuture = _fetchTickerAtTier('GC=F', tier);

    // Paralel bekle.
    await Future.wait([
      ...tickerFutures.values,
      if (usdFuture != null) usdFuture,
      if (goldFuture != null) goldFuture,
    ]);

    final tickerMaps = <String, Map<int, double>>{};
    for (final entry in tickerFutures.entries) {
      tickerMaps[entry.key] = await entry.value;
    }
    final usdMap = usdFuture != null ? await usdFuture : <int, double>{};
    final xauMap = goldFuture != null ? await goldFuture : <int, double>{};

    // XAU → gram22k TRY seri
    final goldMap = <int, double>{};
    for (final entry in xauMap.entries) {
      final ts = entry.key;
      final xauUsd = entry.value;
      final usdRate = _closestOrNull(usdMap, ts) ?? 40.0;
      final xauTry = xauUsd * usdRate;
      goldMap[ts] = PriceService.gram22kFromXauTry(xauTry);
    }

    // Ağırlık tablosu `PriceService`'te tutulur; buradaki yerel kopya
    // ALTIN_RESAT'ı ATLIYORDU (tabloda 7.216 ile var ama switch'te yoktu),
    // yani Reşat altını grafikte gram altın gibi çiziliyor ve pozisyon
    // 7.216 kat düşük görünüyordu.
    double goldFactor(String ticker) => PriceService.goldWeightFactor(ticker);

    // Signed quantity per slot
    double signedQtyOnSlot(Asset a, int slotTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      if (simulate) return a.isSell ? -a.quantity : a.quantity;
      // slotTs tier bucket başlangıcı. Bir varlığın o slot'ta olabilmesi
      // için addedDate <= slotTs olmalı — böylece slot başlangıcından SONRA
      // alınan varlık (örn. çarşamba alım vs pazartesi slot) o slot'a
      // dahil edilmez, bir sonraki bucket'a girer. Yanlış "erken katılım"
      // grafiği geçmişte yapay yükseltirdi.
      final addedMs = a.addedDate.millisecondsSinceEpoch;
      if (addedMs > slotTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // Grid: from..to arası tier step'inde tüm slot'lar
    final result = <int, double>{};
    final stepMs = _tierStepMs(tier);
    int cursor = normalizedFrom;
    while (cursor <= normalizedTo) {
      // Gelecek slotları atla
      if (cursor > nowTs) break;
      // Haftalık intraday'de hafta sonu atla (Cts/Paz)
      if (tier == ResolutionTier.hourly) {
        final wd = DateTime.fromMillisecondsSinceEpoch(cursor).weekday;
        if (wd == DateTime.saturday || wd == DateTime.sunday) {
          cursor += stepMs;
          continue;
        }
      }

      double total = 0.0;
      bool anyCovered = false;
      for (final a in assets) {
        final qty = signedQtyOnSlot(a, cursor);
        if (qty == 0) continue;
        double? v;
        if (a.type == AssetType.altin) {
          // Altın için _pastOrNull yerine _closestOrNull — cursor'dan önce
          // veri yoksa serinin en yakın gelecek noktasına düş. Böylece yeni
          // eklenmiş bir altın için düz plato + dik sıçrama olmaz.
          final gram = _closestOrNull(goldMap, cursor);
          if (gram != null) v = gram * goldFactor(a.ticker) * qty;
        } else if (a.type == AssetType.hisse ||
            a.type == AssetType.emtia ||
            a.type == AssetType.doviz ||
            a.type == AssetType.fon) {
          final map = tickerMaps[a.ticker] ?? {};
          final price = _closestOrNull(map, cursor);
          if (price != null) {
            double p = price;
            if (a.currency == 'USD') {
              final usdRate = _closestOrNull(usdMap, cursor) ?? 40.0;
              p *= usdRate;
            }
            v = p * qty;
          }
        }
        // Son çare: canlı fiyat (Yahoo serisi tamamen boşsa). Bunun yerine
        // artık nadiren buraya düşülür çünkü _closestOrNull mevcut serideki
        // herhangi bir noktayı bulur.
        if (v == null && a.currentPrice > 0) {
          final seedPrice = a.currency == 'USD'
              ? a.currentPrice * 40.0
              : a.currentPrice;
          v = seedPrice * qty;
        }
        // Bir asset için hiç fiyat yoksa (kurucu-fon YLB(0.00) gibi) O
        // ASSET'İ o slot'ta yok say — diğer varlıklar toplama girmeye devam
        // etsin. Aksi halde tek eksik varlık için tüm grafik boş kalır.
        if (v == null) continue;
        total += v;
        anyCovered = true;
      }
      if (anyCovered) {
        if (total < 0) total = 0;
        result[cursor] = total;
      }
      cursor += stepMs;
    }

    // Outlier smoothing: tek nokta V-dip artefaktları (Yahoo veri gecikmesi
    // veya eksik slot) yumuşat. Komşu iki nokta birbirine yakınken ortadaki
    // >%1.5 sapıyorsa yerine ortalama koy.
    _smoothOutliers(result);

    return result;
  }

  /// In-place outlier smoothing — tek nokta V-dip / N-tepe artefaktlarını
  /// komşuların ortalamasıyla değiştirir. Gerçek trendleri (komşular arası
  /// da büyük fark) korur.
  void _smoothOutliers(Map<int, double> points) {
    if (points.length < 3) return;
    final keys = points.keys.toList()..sort();
    for (int i = 1; i < keys.length - 1; i++) {
      final prev = points[keys[i - 1]]!;
      final cur = points[keys[i]]!;
      final next = points[keys[i + 1]]!;
      if (prev <= 0 || next <= 0) continue;
      final devPrev = ((cur - prev) / prev).abs();
      final devNext = ((cur - next) / next).abs();
      final prevNextGap = ((next - prev) / prev).abs();
      if (devPrev > 0.015 && devNext > 0.015 && prevNextGap < 0.01) {
        points[keys[i]] = (prev + next) / 2;
      }
    }
  }

  int _tierStepMs(ResolutionTier tier) => switch (tier) {
        ResolutionTier.fiveMin => 5 * 60 * 1000,
        ResolutionTier.hourly => 60 * 60 * 1000,
        ResolutionTier.daily => 24 * 60 * 60 * 1000,
        ResolutionTier.weekly => 7 * 24 * 60 * 60 * 1000,
      };

  /// Sıralı anahtar indeksi (identity-keyed).
  ///
  /// `_pastOrNull` slot × varlık kombinasyonu başına bir kez çağrılır —
  /// 1 yıllık haftalık grafikte 20 varlıkla binlerce çağrı eder. Eskiden her
  /// çağrı `map.keys.toList()..sort()` yapıyordu: O(n log n) sıralama +
  /// O(n) doğrusal tarama, hep AYNI değişmeyen map üstünde. Grafiğin
  /// "ağ beklemiyorken bile" saniyelerce takılmasının sebebi buydu.
  ///
  /// Fiyat serisi map'leri `_tierCache` içinde immutable tutulur, bu yüzden
  /// sıralı anahtar listesi map nesnesi başına bir kez üretilip
  /// önbelleğe alınabilir. `Expando` kullanıyoruz: map çöp toplandığında
  /// indeks de gider, elle invalidasyon gerekmez.
  static final Expando<List<int>> _sortedKeysCache = Expando<List<int>>();

  static List<int> _sortedKeys(Map<int, double> map) {
    final cached = _sortedKeysCache[map];
    if (cached != null) return cached;
    final keys = map.keys.toList()..sort();
    _sortedKeysCache[map] = keys;
    return keys;
  }

  /// [keys] içinde `<= targetTs` olan EN BÜYÜK indeksi bulur; yoksa -1.
  /// Doğrusal tarama yerine ikili arama — O(log n).
  @visibleForTesting
  static int floorIndexForTest(List<int> keys, int targetTs) =>
      _floorIndex(keys, targetTs);

  static int _floorIndex(List<int> keys, int targetTs) {
    int lo = 0, hi = keys.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (keys[mid] <= targetTs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  double? _pastOrNull(Map<int, double> map, int targetTs) {
    if (map.isEmpty) return null;
    final exact = map[targetTs];
    if (exact != null) return exact;
    final keys = _sortedKeys(map);
    final idx = _floorIndex(keys, targetTs);
    return idx < 0 ? null : map[keys[idx]];
  }

  /// pastOrNull null döndüyse "en yakın ileri nokta" ile fallback. Böylece
  /// eski tarihlere sabit 40.0 kur atamak yerine serinin en yakın gerçek
  /// değerini kullanırız → grafik ani sıçrama üretmez.
  double? _closestOrNull(Map<int, double> map, int targetTs) {
    final past = _pastOrNull(map, targetTs);
    if (past != null) return past;
    if (map.isEmpty) return null;
    return map[_sortedKeys(map).first];
  }

  /// Bir kısmi tier'ın cache'ini temizle (invalidate). Debug için.
  void clearTierCache() {
    _tierCache.clear();
  }

  // ── Tek varlık geçmişi (karşılaştırma altyapısı) ──────────────────────────
  //
  // Buradan aşağısı PORTFÖYDEN BAĞIMSIZDIR: kullanıcının sahip olmadığı bir
  // varlığın geçmişini de çeker. "THYAO alsaydım ne olurdu?" sorusunu
  // yanıtlayan karşılaştırma ekranının veri katmanı.
  //
  // `getPortfolioHistory` ile arasındaki fark özet olarak:
  //   portföy  → miktar × fiyat, lot geçmişi, TL toplam
  //   buradaki → yalnızca FİYAT serisi, miktar kavramı yok
  //
  // Bu ayrım bilinçli: karşılaştırmada "ne kadarım vardı" sorusu anlamsızdır
  // (kullanıcı o varlığa hiç sahip olmamış olabilir), sorulan şey saf getiri.

  /// Tek bir sembolün TRY cinsinden fiyat serisini döner.
  ///
  /// Dönen map: `{ UNIX_MILLIS: TRY_FIYAT }` — boş map "veri yok" demektir
  /// (ağ hatası ya da tanınmayan sembol); çağıran taraf bunu grafik çizmeme
  /// kararına çevirmelidir.
  ///
  /// **Para birimi:** USD kote semboller (ör. `AAPL`) o günün USD/TRY kuruyla
  /// çevrilir — sabit bugünkü kur değil. Aksi halde geçmiş getiri, kurdaki
  /// hareketi hisseye mal ederdi.
  ///
  /// **Altın:** `ALTIN_*` sembolleri XAU/USD serisinden 22 ayar gram TRY'ye
  /// çevrilir ve ürün ağırlığıyla (çeyrek, yarım...) ölçeklenir.
  Future<Map<int, double>> getSymbolHistory(
    String symbol, {
    required int periodDays,
  }) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return {};

    final tier = _tierForPeriod(periodDays);
    final range = _rangeForPeriod(periodDays);

    Future<Map<int, double>> series(String s) async =>
        _normalized(await _fetchSafe(s, range), tier);

    // Altın: XAU/USD × USD/TRY → 22 ayar gram → ürün ağırlığı.
    if (sym.startsWith('ALTIN_')) {
      final results = await Future.wait([series('GC=F'), series('USDTRY=X')]);
      final xau = results[0];
      final usd = results[1];
      final weight = PriceService.goldWeightFactor(sym);
      final out = <int, double>{};
      for (final e in xau.entries) {
        final rate = _closestOrNull(usd, e.key);
        // Kur bulunamazsa noktayı ATLA — sabit bir varsayılan kur (eski
        // kodda 40.0) geçmişte tamamen uydurma bir TL fiyatı üretirdi.
        if (rate == null) continue;
        out[e.key] =
            PriceService.gram22kFromXauTry(e.value * rate) * weight;
      }
      return out;
    }

    final raw = await series(sym);
    if (raw.isEmpty) return {};

    // TRY kote olanlar (BIST `.IS`, TEFAS fonları, `*TRY=X` pariteleri)
    // doğrudan döner; kalanlar USD kabul edilip çevrilir.
    if (_isTryQuoted(sym)) return raw;

    final usd = await series('USDTRY=X');
    if (usd.isEmpty) return {};
    final out = <int, double>{};
    for (final e in raw.entries) {
      final rate = _closestOrNull(usd, e.key);
      if (rate == null) continue;
      out[e.key] = e.value * rate;
    }
    return out;
  }

  /// Sembol TRY cinsinden mi kote?
  ///
  /// BIST sembolleri `.IS` ile biter, TEFAS fonları `TEFAS:` önekli, TRY
  /// pariteleri `TRY=X` ile biter. Kalan her şey (ABD hisseleri, emtia,
  /// kripto) USD kabul edilir — Yahoo'nun varsayılanı budur.
  static bool _isTryQuoted(String sym) =>
      sym.endsWith('.IS') ||
      sym.startsWith('TEFAS:') ||
      sym.endsWith('TRY=X') ||
      sym.startsWith('ALTIN_');

  /// Periyoda uygun Yahoo range.
  static String _rangeForPeriod(int days) {
    if (days <= 7) return '5d';
    if (days <= 30) return '1mo';
    if (days <= 90) return '3mo';
    if (days <= 365) return '1y';
    return '5y';
  }

  /// Periyoda uygun çözünürlük katmanı.
  static ResolutionTier _tierForPeriod(int days) {
    if (days <= 2) return ResolutionTier.fiveMin;
    if (days <= 30) return ResolutionTier.hourly;
    if (days <= 365) return ResolutionTier.daily;
    return ResolutionTier.weekly;
  }

  /// Ham noktaları tier'a göre bucket'lara indirger.
  static Map<int, double> _normalized(
      List<(int, double)> pts, ResolutionTier tier) {
    final out = <int, double>{};
    for (final p in pts) {
      // Aynı bucket'a düşen sonraki nokta öncekini ezer → bucket'ın
      // KAPANIŞ değeri kalır. Grafiklerde beklenen davranış budur.
      out[tier.normalizeTs(p.$1)] = p.$2;
    }
    return out;
  }

  /// Önbellekli, hata yutan tek sembol çekimi.
  Future<List<(int, double)>> _fetchSafe(String sym, String range) async {
    final key = '${sym}_$range';
    final cached = _cacheGet(key);
    if (cached != null) return cached;
    try {
      final pts = await PriceService.instance.fetchHistory(sym, range);
      if (pts.isNotEmpty) _cachePut(key, pts);
      return pts;
    } catch (e) {
      if (kDebugMode) debugPrint('getSymbolHistory($sym) failed: $e');
      return const [];
    }
  }
}

/// Bir serinin dönem başına göre normalize edilmiş getirisi.
///
/// Karşılaştırmanın temel taşı: farklı fiyat ölçeklerindeki varlıklar
/// (₺12 bir hisse ile ₺4.800 bir altın) ancak yüzde cinsinden aynı
/// grafikte anlamlı görünür.
typedef NormalizedSeries = ({
  /// `{ UNIX_MILLIS: YUZDE_DEGISIM }` — dönem başı `0.0`.
  Map<int, double> points,

  /// Dönem boyunca toplam getiri yüzdesi (son nokta).
  double totalReturnPct,

  /// Dönemdeki ilk ve son ham fiyat — "₺X → ₺Y" göstermek için.
  double firstPrice,
  double lastPrice,
});

/// Ham fiyat serisini dönem başı `%0` olacak şekilde normalize eder.
///
/// **Neden yüzde:** kullanıcının sahip OLMADIĞI bir varlık için alım fiyatı
/// yoktur; "ne kadar kazandın" sorusu tanımsızdır. Tanımlı olan tek şey
/// dönem boyunca fiyatın yüzde kaç değiştiğidir. Bu yüzden karşılaştırma
/// her zaman dönem başını sıfır kabul eder.
///
/// İlk fiyat sıfır veya negatifse (bozuk veri) `null` döner — sıfıra bölme
/// sonsuz yüzde üretir ve grafiği okunamaz hale getirirdi.
NormalizedSeries? normalizeSeries(Map<int, double> raw) {
  if (raw.length < 2) return null;
  final keys = raw.keys.toList()..sort();
  final first = raw[keys.first]!;
  if (first <= 0) return null;

  final points = <int, double>{};
  for (final k in keys) {
    points[k] = (raw[k]! - first) / first * 100.0;
  }
  final last = raw[keys.last]!;
  return (
    points: points,
    totalReturnPct: (last - first) / first * 100.0,
    firstPrice: first,
    lastPrice: last,
  );
}
