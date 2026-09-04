import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
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
        final monday =
            DateTime(d.year, d.month, d.day).subtract(Duration(days: wd - 1));
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

/// Portföy değer serisi + aynı serinin tür ve pozisyon bazında dağılımı.
///
/// **Değişmez (iki seviyeli):** her `ts` için
///   `total[ts] == Σ byType[t]![ts]` ve
///   `byType[t]![ts] == Σ byPosition[k]![ts]` (k, türü `t` olan pozisyonlar).
/// Kayan nokta toplama hatası payı dışında birebir. Üç alan da AYNI döngüde
/// üretilir; bu yüzden tür dökümü portföy toplamını, ürün dökümü de tür
/// toplamını her zaman tutar.
/// Bkz. [HistoryService.getPortfolioHistoryBreakdownAtResolution].
class PortfolioHistoryBreakdown {
  /// ts → toplam portföy değeri (TRY).
  final Map<int, double> total;

  /// tür → (ts → o türün o slot'taki değeri, TRY).
  /// Yalnızca o slot'ta fiilen değeri olan türler bulunur.
  final Map<AssetType, Map<int, double>> byType;

  /// `positionKey` → (ts → o pozisyonun o slot'taki değeri, TRY).
  ///
  /// Anahtar `positionKey`'dir, ticker DEĞİL: altın türleri (Gram/Çeyrek/
  /// Yarım/Reşat) aynı `GC=F` serisinden türetilir ama farklı ağırlık
  /// katsayısı taşır — ticker ile gruplansaydı hepsi tek satırda toplanır ve
  /// "çeyrek mi gram mı kazandırdı" sorusu cevapsız kalırdı.
  final Map<String, Map<int, double>> byPosition;

  /// `positionKey` → o pozisyonun ait olduğu tür. Ürün satırlarını doğru
  /// başlığın altına yerleştirmek için.
  final Map<String, AssetType> positionType;

  const PortfolioHistoryBreakdown({
    required this.total,
    required this.byType,
    required this.byPosition,
    required this.positionType,
  });

  const PortfolioHistoryBreakdown.empty()
      : total = const {},
        byType = const {},
        byPosition = const {},
        positionType = const {};
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

    // Range dönemi KAPSAMAK zorunda: dar bir range portföy çizgisini sessizce
    // kırpar ve grafik, seçilen dönemin yalnızca sağ dilimini gösterir.
    // Eski merdivende iki delik vardı — 91-180 gün `'3mo'`e (90 gün) düşüyor,
    // 365 günün üstü de `'1y'`de kalıyordu. `getSymbolHistory` ile aynı
    // aileden hata; ikisi de kapatıldı.
    //
    // **Merdiven artık [rangeForPeriod] ile ORTAK.** Burada ayrı bir kopya
    // duruyordu ve `getSymbolHistory`'ninkiyle ayrışmıştı: GÜNLÜK'te sembol
    // `'1d'` çekerken portföy `'5d'`, 1H'de sembol `'1mo'` çekerken portföy
    // yine `'5d'` çekiyordu. Aynı grafikte iki seri iki farklı pencereden
    // geliyordu (ölçüldü: GÜNLÜK'te 96 saatlik kayma). İki kopya tutmak bu
    // projede tekrar eden hata sınıfı; tek kaynağa indirildi.
    final range = rangeForPeriod(periodDays);
    // Testler bu değeri ağa çıkmadan denetler — `range` yerel bir değişken
    // olduğu sürece merdivenin yeniden ayrışması hiçbir testle yakalanamıyordu
    // (sabotaj denendi, tüm testler geçti).
    debugSonKullanilanRange = range;

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
    final usdFuture = needsUsd
        ? getHistorySafe('USDTRY=X')
        : Future.value(const <(int, double)>[]);
    final goldFuture = needsGold
        ? getHistorySafe('GC=F')
        : Future.value(const <(int, double)>[]);

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
      // Simülasyonda arayan NET (aggregate) liste verir, yani sell lot
      // beklenmez. Yine de işaret korunur: kardeş fonksiyon
      // `getPortfolioHistoryAtResolution.signedQtyOnSlot` bunu zaten
      // yapıyordu ve iki kopyanın ayrışması bu projede yaşanmış bir hata
      // sınıfıdır. Ham lot listesi yanlışlıkla verilirse satılan miktar
      // burada EKLENİR ve portföy olduğundan büyük görünürdü.
      if (simulate) return a.isSell ? -a.quantity : a.quantity;
      final addedTs = normalizeTs(a.addedDate.millisecondsSinceEpoch);
      if (addedTs > dayTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // -- Toparlama ve Hizalama --
    // Haftalık'ta saat başına, diğerlerinde gün başına grid oluştur.
    //
    // **Grid `now`'a değil son İŞ GÜNÜNE çapalanır.** Saatlik grid hafta sonu
    // slotlarını atlar (aşağıdaki `weekday` kontrolü); pencere `now`'dan
    // geriye sayınca Pazar günü "GÜNLÜK" seçildiğinde 24 slotun tamamı Cts/Paz
    // oluyor ve portföy çizgisi TAMAMEN kayboluyordu (ölçüldü: Pazar → 0 slot,
    // Cumartesi → 9 slot). Aynı anda takip varlıkları Cuma seansını
    // gösteriyordu, çünkü `clipToPeriod` son VERİ noktasına çapalanır.
    // İki seri aynı grafikte farklı pencerelerden geliyordu.
    //
    // Çapayı son iş gününe almak `clipToPeriod`'un hafta sonu kuralıyla aynı
    // anlamı verir: "son bir günlük hareket" = son seans.
    for (final dayTs in gridSlotlari(
      now: now,
      periodDays: periodDays,
      hourly: hourly,
    )) {
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
    smoothSpikes(groupedPoints, deviation: 0.015, neighborGap: 0.01);

    // Takip/karşılaştırma serileriyle AYNI kırpma. Grid zaten `periodDays`
    // adım üretiyor, ama kırpma iki şeyi garanti eder:
    //   · pencere sembol serileriyle bire bir aynı kuralla kapanır
    //     (`clipToPeriod` son veri noktasına çapalanır),
    //   · yüzde tabanı dönem içinde kalır. Kırpma yokken GÜNLÜK'te portföy
    //     çizgisi dönem başına göre değil BEŞ GÜN öncesine göre normalize
    //     oluyordu; ölçülen hata %1,00 yerine %10,02 (9 puan) idi ve aynı
    //     yanlış rakam açıklama satırına da yazılıyordu.
    return clipToPeriod(groupedPoints, periodDays);
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

  /// [getPortfolioHistory]'nin son çağrıda kullandığı Yahoo range'i.
  ///
  /// Yalnızca test gözlemi içindir; üretimde okunmaz. Var olma sebebi:
  /// `range` yerel bir değişken olduğu için portföy merdiveninin sembol
  /// merdiveninden yeniden ayrışması ağa çıkmayan hiçbir testle
  /// yakalanamıyordu (sabotaj denendi, tüm testler geçti).
  @visibleForTesting
  static String? debugSonKullanilanRange;

  /// Portföy serisinin zaman ızgarası — `{ normalize edilmiş UNIX_MILLIS }`,
  /// eskiden yeniye sıralı.
  ///
  /// Saf fonksiyon ([now] dışarıdan verilir) olmasının SEBEBİ var: hafta sonu
  /// davranışı yalnızca Cumartesi/Pazar günü ortaya çıkıyor. Izgara
  /// `getPortfolioHistory`'nin içinde `DateTime.now()` ile kurulduğu sürece
  /// o dal hafta içi koşan bir testte HİÇ çalışmaz — nitekim ilk yazılan
  /// koruma testi, çapa sabote edildiğinde de geçiyordu (Cuma günü koşuldu).
  /// Izgarayı ayırmak "Pazar günü ne olur" sorusunu doğrudan sorulabilir yapar.
  ///
  /// ## Kurallar
  /// · Saatlik ızgara (dönem ≤ 7 gün) hafta sonu slotlarını ATLAR — Cts/Paz
  ///   platosu trading uygulamalarında gösterilmez.
  /// · Bu yüzden pencere de hafta sonundan BAŞLAYAMAZ: [_sonIsGunu] ile son
  ///   iş gününe çapalanır. Aksi halde Pazar günü "GÜNLÜK" seçildiğinde
  ///   24 slotun tamamı elenir ve seri boş döner (ölçüldü: Pazar → 0 slot).
  /// · Günlük ızgara (dönem > 7 gün) hafta sonunu ELEMEZ; haftada 5 nokta ile
  ///   7 nokta arasındaki fark uzun dönemde önemsiz.
  @visibleForTesting
  static List<int> gridSlotlari({
    required DateTime now,
    required int periodDays,
    required bool hourly,
  }) {
    int normalizeTs(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (hourly) {
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      }
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }

    final gridNow = hourly ? _sonIsGunu(now) : now;
    final startMs =
        gridNow.subtract(Duration(days: periodDays)).millisecondsSinceEpoch;
    final stepMinutes = hourly ? 60 : 24 * 60;
    final totalSteps = hourly ? periodDays * 24 : periodDays;

    final out = <int>[];
    for (var i = totalSteps; i >= 0; i--) {
      final slotDate = gridNow.subtract(Duration(minutes: i * stepMinutes));
      final dayTs = normalizeTs(slotDate.millisecondsSinceEpoch);
      if (dayTs < normalizeTs(startMs)) continue;
      if (hourly) {
        final wd = slotDate.weekday; // 6=Cts, 7=Paz
        if (wd == DateTime.saturday || wd == DateTime.sunday) continue;
      }
      out.add(dayTs);
    }
    return out;
  }

  /// [d] hafta sonuna düşüyorsa bir önceki Cuma'ya (aynı saatte) çeker.
  ///
  /// Saatlik grid hafta sonu slotlarını atladığı için pencerenin kendisi de
  /// hafta sonundan başlamamalı — yoksa pencere boşa düşer ve çizgi kaybolur.
  /// Borsa tatilleri KAPSANMAZ: tatil takvimi yok, ve tatilde pencere bir
  /// seans dar kalır ama boşalmaz (Cuma verisi hâlâ pencerede).
  @visibleForTesting
  static DateTime sonIsGunu(DateTime d) => _sonIsGunu(d);

  static DateTime _sonIsGunu(DateTime d) {
    var out = d;
    while (out.weekday == DateTime.saturday || out.weekday == DateTime.sunday) {
      out = out.subtract(const Duration(days: 1));
    }
    return out;
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
          List<Asset> assets, int hours) async =>
      (await getPortfolioHistoryHourlyBreakdown(assets, hours)).total;

  /// [getPortfolioHistoryHourly] ile AYNI hesap — ek olarak tür/pozisyon
  /// dağılımını da döndürür.
  ///
  /// Gün içi ("GÜNLÜK") sekmesinde tür dökümü kartı bunu kullanır. Kart bu
  /// sekmede eskiden HİÇ görünmüyordu: diğer periyotlar
  /// `getPortfolioHistoryBreakdownAtResolution`'dan dağılım alıyordu, gün içi
  /// yolu ise ayrı olan bu servise gidiyor ve dağılım taşımıyordu.
  ///
  /// Değişmez diğer yolla aynı ve aynı gerekçeyle: toplam ve dağılım TEK
  /// döngüde birikir, ayrı geçişte hesaplanırsa toplamlar ayrışır.
  /// Bkz. [PortfolioHistoryBreakdown].
  Future<PortfolioHistoryBreakdown> getPortfolioHistoryHourlyBreakdown(
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
    final usdFuture = needsUsd
        ? getHistorySafe('USDTRY=X')
        : Future.value(const <(int, double)>[]);
    final goldFuture = needsGold
        ? getHistorySafe('GC=F')
        : Future.value(const <(int, double)>[]);

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
    // Tür/pozisyon dağılımı — `groupedPoints` ile AYNI döngüde birikir.
    final byType = <AssetType, Map<int, double>>{};
    final byPosition = <String, Map<int, double>>{};
    final positionType = <String, AssetType>{};

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
                ? usdTrySlots[usdTrySlots.keys.reduce((x, y) => x < y ? x : y)]!
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

      // Bu slotta kaç pozisyon fiyatlanabildi / kaç pozisyon bekleniyor.
      //
      // Slotlar ancak AYNI pozisyon kümesini içeriyorsa karşılaştırılabilir.
      // Kapanışa yakın bazı ticker'lar veri vermeyi keserken diğerleri
      // devam ediyor; o slotta toplam daha AZ pozisyondan oluşuyor ve seri
      // aşağı sıçrayıp bir sonraki slotta geri çıkıyordu (grafikte "W").
      // Bu bir fiyat hareketi değil, EKSİK PORTFÖY.
      var covered = 0;
      var expected = 0;

      // Bu slot'un tür/pozisyon kırılımı. `total`a giren her `v` buraya da
      // girer; slot seriye alınmazsa dağılıma da yazılmaz (aşağıdaki
      // `continue` dalları) — böylece toplamlar ayrışamaz.
      final slotByType = <AssetType, double>{};
      final slotByPosition = <String, double>{};

      for (final a in assets) {
        try {
          final qty = signedQtyOnSlot(a, hourTs);
          if (qty == 0) continue;
          expected++;
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
            slotByType[a.type] = (slotByType[a.type] ?? 0) + v;
            final pk = positionKey(a);
            slotByPosition[pk] = (slotByPosition[pk] ?? 0) + v;
            positionType[pk] = a.type;
            anyCovered = true;
            covered++;
          }
        } catch (_) {
          // Bu asset hesaplanamadı, diğerlerine devam et.
        }
      }

      if (!anyCovered) continue;
      // Negatif toplam kırpılırsa dağılım da düşer — aksi halde
      // `Σ byType != total` olur (aynı kural günlük seride de var).
      if (total < 0) {
        total = 0;
        slotByType.clear();
        slotByPosition.clear();
      }

      // EKSİK KAPSAMLI slot seriye GİRMEZ.
      //
      // Portföyün bir kısmı fiyatlanamadıysa bu slot diğerleriyle aynı
      // şeyi ölçmüyor demektir; grafiğe koymak "portföyüm düştü" yalanını
      // söyler. Slotu atlamak doğru davranıştır: çizgi bir önceki gerçek
      // noktadan bir sonrakine gider ve gün içi hareketi olduğu gibi
      // anlatır.
      //
      // `expected` sıfırsa (o an hiç pozisyon yok) bölme yapılmaz.
      if (expected > 0 && covered < expected) continue;

      groupedPoints[hourTs] = total;
      for (final e in slotByType.entries) {
        (byType[e.key] ??= <int, double>{})[hourTs] = e.value;
      }
      for (final e in slotByPosition.entries) {
        (byPosition[e.key] ??= <int, double>{})[hourTs] = e.value;
      }
    }

    // Son slotu anlık portföy toplamı ile hizala — grafiğin bitiş noktası
    // her zaman ana ekrandaki toplamla eşleşsin. currentPrice=0 olan
    // varlıklar (kurucu-fon vs.) hesap dışı, diğerleri toplama girer.
    if (groupedPoints.isNotEmpty) {
      // Canlı toplam TÜR VE POZİSYON BAZINDA hesaplanır — tek bir toplam
      // çarpanı YETMEZ.
      //
      // Önce toplam ezilip dağılım `liveTotal / before` oranıyla ölçekleniyordu.
      // Bu, bir türdeki hareketi TÜM türlere yayıyordu: altın %2 düşünce
      // fiyatı hiç değişmemiş fon da ekranda düşmüş görünüyordu
      // (ölçüldü: fon 25.000 → 16.716, oysa fon fiyatı sabitti).
      // Kullanıcının gördüğü "alttaki satırlar üsttekiyle senkron değil"
      // şikâyetinin kaynağı buydu — toplam tutuyordu ama satırlar yalandı.
      //
      // Doğrusu: her varlığın canlı değerini kendi türüne/pozisyonuna yazmak.
      // Toplam yine `Σ tür` olur, ama her tür KENDİ gerçek değerini taşır.
      double liveTotal = 0.0;
      final liveByType = <AssetType, double>{};
      final liveByPosition = <String, double>{};
      for (final a in assets) {
        if (a.isDeleteLog) continue;
        final qty = signedQtyOnSlot(a, nowTs);
        if (qty == 0) continue;
        if (a.currentPrice <= 0) continue;
        final liveUsd = usdTrySlots.isNotEmpty ? usdTrySlots.values.last : 40.0;
        final tryPrice =
            a.currency == 'USD' ? a.currentPrice * liveUsd : a.currentPrice;
        final v = tryPrice * qty;
        liveTotal += v;
        liveByType[a.type] = (liveByType[a.type] ?? 0) + v;
        final pk = positionKey(a);
        liveByPosition[pk] = (liveByPosition[pk] ?? 0) + v;
        positionType[pk] = a.type;
      }
      if (liveTotal > 0) {
        final lastKey = groupedPoints.keys.reduce((a, b) => a > b ? a : b);
        groupedPoints[lastKey] = liveTotal;
        // Son slotta dağılımı canlı değerlerle DEĞİŞTİR (ölçekleme değil).
        // `liveTotal == Σ liveByType` olduğu için değişmez korunur.
        for (final e in liveByType.entries) {
          (byType[e.key] ??= <int, double>{})[lastKey] = e.value;
        }
        for (final e in liveByPosition.entries) {
          (byPosition[e.key] ??= <int, double>{})[lastKey] = e.value;
        }
        // Canlı hesapta yer almayan (currentPrice<=0) tür/pozisyon son
        // slotta ARTIK YOK — eski ham değeri bırakmak toplamı şişirirdi.
        for (final e in byType.entries) {
          if (!liveByType.containsKey(e.key)) e.value.remove(lastKey);
        }
        for (final e in byPosition.entries) {
          if (!liveByPosition.containsKey(e.key)) e.value.remove(lastKey);
        }
      }
    }

    // Outlier smoothing — GÜNLÜK seride olanın gün içi karşılığı
    // (bkz. `getPortfolioHistory` sonundaki aynı blok).
    //
    // Yahoo bazı sembollerde tek bir 5 dakikalık slotu eksik/geç
    // döndürüyor. `pastOrNull` o slot için bir önceki fiyatı taşıyamadığında
    // pozisyon anlık olarak eksik hesaplanıyor ve seri tek noktalık bir
    // "V" çiziyor: aşağı iner, hemen geri çıkar. Gerçek bir fiyat hareketi
    // değil, veri artefaktı.
    //
    // Günlük seri bunu zaten temizliyordu; gün içi seri temizlemiyordu ve
    // artefakt widget grafiğinde dikey bir sıçrama olarak görünüyordu
    // (uygulamanın GÜNLÜK sekmesinde görünmeyen bir sıçrama).
    //
    // Eşikler gün içi ölçeğe göre DARALTILDI: günlük seride %1,5 sapma
    // anlamlıyken 5 dakikalık bir slotta portföyün %0,3'ü bile büyük bir
    // harekettir. Komşular arası fark %0,2'den azsa (yani gerçek bir trend
    // yoksa) ortadaki nokta iki komşunun ortalamasına çekilir.
    final smoothed = <int, double>{};
    smoothSpikes(groupedPoints,
        deviation: 0.003, neighborGap: 0.002, changed: smoothed);
    // Düzeltilen slot'larda dağılımı da aynı oranda ölçekle (bkz. `changed`).
    for (final ts in smoothed.keys) {
      final before = smoothed[ts]!;
      if (before <= 0) continue;
      final factor = groupedPoints[ts]! / before;
      for (final series in byType.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
      for (final series in byPosition.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
    }

    return PortfolioHistoryBreakdown(
      total: groupedPoints,
      byType: byType,
      byPosition: byPosition,
      positionType: positionType,
    );
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
  }) async =>
      (await getPortfolioHistoryBreakdownAtResolution(
        assets: assets,
        from: from,
        to: to,
        tier: tier,
        simulate: simulate,
      ))
          .total;

  /// [getPortfolioHistoryAtResolution] ile AYNI hesap — ek olarak her slot'un
  /// tür bazında dağılımını da döndürür.
  ///
  /// ## Neden tek fonksiyon
  /// Tür dökümü eskiden ayrı bir `getPortfolioHistory` çağrısıyla, tür başına
  /// bağımsız hesaplanıyordu. İki hesap farklı pencere, farklı tier ve farklı
  /// "kapsanan slot" kümesi ürettiği için **türlerin toplamı üst kartın
  /// toplamını tutmuyordu** (kullanıcı yakaladı, 2026-09-01).
  ///
  /// Burada dağılım, toplamı üreten döngünün İÇİNDE biriktirilir:
  /// `total[ts] == Σ byType[t]![ts]` her slot için **yapısal olarak** doğrudur
  /// — iki ayrı kod yolunun tesadüfen aynı sonucu vermesine bel bağlanmaz.
  /// Bir slot toplama giriyorsa dağılımına da girer; girmiyorsa ikisinde de
  /// yoktur.
  Future<PortfolioHistoryBreakdown> getPortfolioHistoryBreakdownAtResolution({
    required List<Asset> assets,
    required DateTime from,
    required DateTime to,
    required ResolutionTier tier,
    bool simulate = false,
  }) async {
    if (assets.isEmpty) return const PortfolioHistoryBreakdown.empty();

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
    // Tür ve pozisyon dağılımı — `result` ile AYNI döngüde birikir
    // (bkz. sınıf notu). Ayrı bir geçişte hesaplanırsa toplamlar ayrışır.
    final byType = <AssetType, Map<int, double>>{};
    final byPosition = <String, Map<int, double>>{};
    final positionType = <String, AssetType>{};
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
      // Bu slot'un tür ve pozisyon kırılımı. `total`a giren her `v` ikisine
      // de girer — tek yerden beslendikleri için toplamları ayrışamaz.
      final slotByType = <AssetType, double>{};
      final slotByPosition = <String, double>{};
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
          final seedPrice =
              a.currency == 'USD' ? a.currentPrice * 40.0 : a.currentPrice;
          v = seedPrice * qty;
        }
        // Bir asset için hiç fiyat yoksa (kurucu-fon YLB(0.00) gibi) O
        // ASSET'İ o slot'ta yok say — diğer varlıklar toplama girmeye devam
        // etsin. Aksi halde tek eksik varlık için tüm grafik boş kalır.
        if (v == null) continue;
        total += v;
        slotByType[a.type] = (slotByType[a.type] ?? 0) + v;
        // Aynı ürünün farklı lot'ları tek satırda toplanır (ekrandaki
        // pozisyon kavramıyla aynı), ama SAHİP ayrımı korunur: `positionKey`
        // sahip taşımadığı için burada ortakların aynı hissesi tek satıra
        // düşer — bu kart zaten sekme başına ayrı çizilir, sekme içinde
        // birleşmeleri doğrudur.
        final pk = positionKey(a);
        slotByPosition[pk] = (slotByPosition[pk] ?? 0) + v;
        positionType[pk] = a.type;
        anyCovered = true;
      }
      if (anyCovered) {
        // Negatif toplam kırpılırsa dağılım da AYNI ORANDA kırpılmalı;
        // aksi halde `Σ byType != total` olur ve tür dökümü üst kartı
        // tutmaz. Pratikte buraya nadiren düşülür (satış lot'ları alımı
        // aşarsa), ama değişmez koşulsuz korunmalı.
        if (total < 0) {
          total = 0;
          slotByType.clear();
          slotByPosition.clear();
        }
        result[cursor] = total;
        for (final e in slotByType.entries) {
          (byType[e.key] ??= <int, double>{})[cursor] = e.value;
        }
        for (final e in slotByPosition.entries) {
          (byPosition[e.key] ??= <int, double>{})[cursor] = e.value;
        }
      }
      cursor += stepMs;
    }

    // Outlier smoothing: tek nokta V-dip artefaktları (Yahoo veri gecikmesi
    // veya eksik slot) yumuşat. Komşu iki nokta birbirine yakınken ortadaki
    // >%1.5 sapıyorsa yerine ortalama koy.
    //
    // Düzeltilen slot'lar geri bildirilir: smoothing YALNIZCA `result`u
    // değiştirir, dağılıma dokunmazsa `Σ byType != total` olur ve tür dökümü
    // üst kartı tutmaz. Aşağıda dağılım aynı oranda ölçeklenir.
    final smoothed = _smoothOutliers(result);
    for (final ts in smoothed.keys) {
      final before = smoothed[ts]!;
      final after = result[ts]!;
      // Sıfırdan ölçeklenemez; o slot'ta dağılım zaten anlamsızdır.
      if (before <= 0) continue;
      final factor = after / before;
      for (final series in byType.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
      for (final series in byPosition.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
    }

    return PortfolioHistoryBreakdown(
      total: result,
      byType: byType,
      byPosition: byPosition,
      positionType: positionType,
    );
  }

  /// In-place outlier smoothing — tek nokta V-dip / N-tepe artefaktlarını
  /// komşuların ortalamasıyla değiştirir. Gerçek trendleri (komşular arası
  /// da büyük fark) korur.
  /// Değiştirilen slot'ları `ts → ÖNCEKİ değer` olarak döndürür. Çağıran bu
  /// bilgiyle tür dağılımını aynı oranda ölçekler; aksi halde toplam düzeltilip
  /// dağılım ham kalır ve `Σ byType != total` olur.
  Map<int, double> _smoothOutliers(Map<int, double> points) {
    final changed = <int, double>{};
    if (points.length < 3) return changed;
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
        changed[keys[i]] = cur;
        points[keys[i]] = (prev + next) / 2;
      }
    }
    return changed;
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

    final tier = tierForPeriod(periodDays);
    final range = rangeForPeriod(periodDays);

    // Interval'i KATMAN belirler, range değil. Eskiden interval
    // `PriceService._intervalFor(range)`'dan türüyordu ve katmanla
    // çelişebiliyordu: `days<=2` beş dakikalık bucket isterken ağdan saatlik
    // veri geliyordu. Tek karar noktası olsun diye interval açıkça geçilir.
    Future<Map<int, double>> series(String s) async =>
        _normalized(await _fetchSafe(s, range, tier.yahooInterval), tier);

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
        out[e.key] = PriceService.gram22kFromXauTry(e.value * rate) * weight;
      }
      // Kırpma ÇEVRİMDEN SONRA yapılır: önce kırpsaydık USD/TRY serisinde
      // eşleşecek komşu nokta kalmayabilir ve `_closestOrNull` kenardaki
      // noktaları düşürürdü.
      return clipToPeriod(out, periodDays);
    }

    final raw = await series(sym);
    if (raw.isEmpty) return {};

    // TRY kote olanlar (BIST `.IS`, TEFAS fonları, `*TRY=X` pariteleri)
    // doğrudan döner; kalanlar USD kabul edilip çevrilir.
    if (_isTryQuoted(sym)) return clipToPeriod(raw, periodDays);

    final usd = await series('USDTRY=X');
    if (usd.isEmpty) return {};
    final out = <int, double>{};
    for (final e in raw.entries) {
      final rate = _closestOrNull(usd, e.key);
      if (rate == null) continue;
      out[e.key] = e.value * rate;
    }
    return clipToPeriod(out, periodDays);
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
  ///
  /// **Merdiven eksiksiz olmak ZORUNDA.** Eskiden `'1d'` ve `'6mo'` hiç
  /// üretilmiyordu; `days<=7` doğrudan `'5d'`e, `days<=365` doğrudan `'1y'`e
  /// düşüyordu. Sonuç ölçülmüş iki hataydı:
  ///   · "GÜNLÜK" (1 gün) beş günlük değişimi gösteriyordu,
  ///   · "6A" (180 gün) ile "1Y" (365 gün) aynı range'e düştüğü için —
  ///     önbellek anahtarı da `'${sym}_$range'` olduğundan — BİREBİR aynı
  ///     seriyi döndürüyordu. İki sekme arasında hiçbir rakam değişmiyordu.
  ///
  /// Yahoo'da `7d` diye bir range yok; 1 haftalık dönem `'1mo'` çekip
  /// [clipToPeriod] ile kırpılarak elde edilir. Range'in dönemden GENİŞ
  /// olması sorun değil, DAR olması veri kaybıdır.
  @visibleForTesting
  static String rangeForPeriod(int days) {
    if (days <= 1) return '1d';
    if (days <= 5) return '5d';
    if (days <= 30) return '1mo';
    if (days <= 90) return '3mo';
    if (days <= 180) return '6mo';
    if (days <= 365) return '1y';
    return '5y';
  }

  /// Periyoda uygun çözünürlük katmanı.
  ///
  /// Katman, [rangeForPeriod]'un seçtiği range'in Yahoo'dan GERÇEKTE hangi
  /// interval'le geldiğiyle uyumlu olmalı (`PriceService._intervalFor`).
  /// Eskiden `days<=2` beş dakikalık bucket'a çekiyordu ama range `'5d'`
  /// olduğu için gelen veri saatlikti — bucket'lama boşa çalışıyordu.
  ///
  /// **Karar [ResolutionTierMeta.pickForSpan]'e devredildi.** Burada ayrı bir
  /// merdiven duruyordu ve performans ekranının kullandığıyla ayrışmıştı:
  /// 6A ve 1Y'de performans ekranı HAFTALIK çizerken takip listesi GÜNLÜK
  /// çiziyordu. Aynı portföyün aynı dönemi iki ekranda iki farklı sıklıkta
  /// görünüyordu (kullanıcı bulgusu: "tüm zaman aralıklarında performans
  /// ekranındaki sıklıklarda gösterilmeli"). İki merdiven tutmak bu projede
  /// tekrar eden hata sınıfı; tek kaynağa indirildi.
  ///
  /// `pickForSpan` hedefi ~30-300 nokta: 1Y'de günlük 365 nokta fazla
  /// yoğun, haftalık 52 nokta doğru ölçek. 6A haftalıkta 26 noktaya iner —
  /// hedefin biraz altında ama iki ekranın AYNI şeyi göstermesi bundan daha
  /// önemli; ayrıca zoom yapıldığında viewport daralınca `pickForSpan`
  /// otomatik olarak daha ince katmana geçer.
  @visibleForTesting
  static ResolutionTier tierForPeriod(int days) =>
      ResolutionTierMeta.pickForSpan(days.toDouble());

  /// Seriyi seçili döneme kırpar.
  ///
  /// **Neden gerekli:** range her zaman dönemden geniştir (Yahoo yalnızca
  /// belirli range'leri kabul eder). Kırpılmazsa etiket ile veri ayrışır —
  /// "GÜNLÜK" yazıp beş günü, "1H" yazıp bir ayı gösterirdik. Dönem başı
  /// yüzdesi serinin İLK noktasından hesaplandığı için bu, çağıran her
  /// yüzeyde doğrudan yanlış bir rakam demekti.
  ///
  /// **`days == 1` TAKVİM GÜNÜ, diğerleri kayan penceredir.** Ayrım aşağıda
  /// gerekçelendirildi; kısacası "bugün ne oldu" sorusunun tabanı bugünün
  /// açılışıdır, 24 saat öncesi değil.
  ///
  /// **Pencere `now`'a değil SON VERİ NOKTASINA çapalanır.** Borsa hafta
  /// sonu ve tatilde kapalıdır; `now`'dan geriye saymak Pazar günü "GÜNLÜK"
  /// seçildiğinde Cuma seansının tamamını pencerenin dışında bırakır ve
  /// grafik boşalırdı.
  ///
  /// Kırpma yine de iki noktanın altına düşürüyorsa **son iki nokta** döner,
  /// ham serinin tamamı değil: günde tek fiyat açıklayan TEFAS fonlarında
  /// pencereye tek fiyat düşer ve `normalizeSeries` iki noktanın altında
  /// `null` verip varlığı grafikten sessizce siler. Ham seriye dönmek ise
  /// "GÜNLÜK" etiketiyle bir aylık değişim göstermek olurdu — kaçındığımız
  /// hatanın tam kendisi.
  @visibleForTesting
  static Map<int, double> clipToPeriod(Map<int, double> series, int days) {
    if (series.length < 2) return series;

    final keys = series.keys.toList()..sort();

    // **"GÜNLÜK" bir TAKVİM GÜNÜDÜR, kayan 24 saat değil.**
    //
    // Kayan pencere döviz gibi 7/24 işlem gören sembollerde dünün öğleden
    // sonrasını da içine alıyordu: eksen "15:37 · 21:18 · 02:59 · 08:41"
    // okunuyor ve dönem başı %0 referansı DÜNE düşüyordu. Kullanıcının
    // sorduğu soru "bugün ne oldu"; cevabın tabanı da bugünün açılışı olmalı.
    //
    // Bu, uygulamanın geri kalanının zaten kullandığı tanım:
    // `getPortfolioHistoryHourlyBreakdown` gün içi grid'ini bugünün
    // 00:00'ından kurar ve `DailySummary` gece yarısını geçen bir önbelleği
    // koşulsuz düşürür — tam da "bugünkü değişim aslında dünden bugüne farkı
    // gösterir" durumuna düşmemek için. Takip listesi bu konvansiyonun
    // dışında kalmıştı.
    //
    // Çapa `now` değil SON NOKTANIN GÜNÜ: borsa hafta sonu ve tatilde
    // kapalıdır, `now`'dan saymak Pazar günü boş bir grafik verirdi. Son
    // noktanın günü işlem gününde zaten bugündür (00:00 → şimdi); kapalı
    // günlerde son seansın tamamını gösterir.
    final int cutoff;
    if (days <= 1) {
      final sonGun = DateTime.fromMillisecondsSinceEpoch(keys.last);
      cutoff =
          DateTime(sonGun.year, sonGun.month, sonGun.day).millisecondsSinceEpoch;
    } else {
      cutoff = keys.last - Duration(days: days).inMilliseconds;
    }

    final out = <int, double>{
      for (final e in series.entries)
        if (e.key >= cutoff) e.key: e.value,
    };
    if (out.length >= 2) return out;

    final son = keys.sublist(keys.length - 2);
    return {for (final k in son) k: series[k]!};
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
  ///
  /// Anahtara interval de girer: aynı range farklı çözünürlükle istenebilir
  /// ve iki çekim birbirini ezmemelidir.
  Future<List<(int, double)>> _fetchSafe(
      String sym, String range, String interval) async {
    final key = '${sym}_${range}_$interval';
    final cached = _cacheGet(key);
    if (cached != null) return cached;
    try {
      final pts = await PriceService.instance
          .fetchHistoryAtInterval(sym, range, interval);
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

/// Tek noktalık "V" artefaktlarını temizler.
///
/// Yahoo bazı sembollerde tek bir slotu eksik/geç döndürüyor; o slotta
/// pozisyon eksik hesaplanıyor ve seri aşağı inip hemen geri çıkıyor.
/// Gerçek bir fiyat hareketi değil, veri artefaktı.
///
/// Bir nokta ancak ÜÇ koşulu birden sağlarsa düzeltilir:
///   * iki komşusundan da [deviation] oranından fazla sapıyorsa,
///   * komşuları birbirine [neighborGap] oranından yakınsa (yani gerçek
///     bir trend YOKSA — trend varsa ortadaki nokta meşrudur).
///
/// Eşikler ölçeğe göre verilir: günlük seride %1,5 sapma anlamlıyken
/// 5 dakikalık bir slotta portföyün %0,3'ü bile büyük bir haraket sayılır.
///
/// Uçlar (ilk ve son) DOKUNULMAZ: komşusu olmayan bir noktanın artefakt
/// olup olmadığı bilinemez ve son nokta zaten canlı toplama sabitlenir.
@visibleForTesting
Map<int, double> smoothSpikes(
  Map<int, double> points, {
  required double deviation,
  required double neighborGap,

  /// Düzeltilen slot'ların ÖNCEKİ değerleri buraya yazılır (ts → eski değer).
  /// Çağıran bununla tür/pozisyon dağılımını aynı oranda ölçekler; aksi halde
  /// toplam düzeltilip dağılım ham kalır ve `Σ byType != total` olur.
  Map<int, double>? changed,
}) {
  final keys = points.keys.toList()..sort();
  for (int i = 1; i < keys.length - 1; i++) {
    final prev = points[keys[i - 1]]!;
    final cur = points[keys[i]]!;
    final next = points[keys[i + 1]]!;
    if (prev <= 0 || next <= 0) continue;
    final devPrev = ((cur - prev) / prev).abs();
    final devNext = ((cur - next) / next).abs();
    final prevNextGap = ((next - prev) / prev).abs();
    if (devPrev > deviation &&
        devNext > deviation &&
        prevNextGap < neighborGap) {
      changed?[keys[i]] = cur;
      points[keys[i]] = (prev + next) / 2;
    }
  }
  return points;
}
