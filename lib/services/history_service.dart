import '../models/asset.dart';
import '../models/asset_type.dart';
import 'price_service.dart';

class HistoryService {
  static final HistoryService instance = HistoryService._();
  HistoryService._();

  static final Map<String, List<(int, double)>> _cache = {};

  /// Verilen varlıkların ilgili periyot için (örn. 365 gün) geçmiş fiyatlarını
  /// gün-den-güne hesaplar. Dönen map: { UNIX_MILLIS: TOPLAM_PORTFOY_DEGERI_TRY }
  Future<Map<int, double>> getPortfolioHistory(
      List<Asset> assets, int periodDays) async {
    // Haftalık için de günlük çözünürlük kullan — saatlik veri (Yahoo 1h)
    // bazı hisse/emtia sembollerinde çok az nokta döndürüp grafiği bozuyor.
    // Trading uygulamaları da 1H sekmesinde günlük 7 nokta gösterir.
    final range = periodDays > 100
        ? '1y'
        : periodDays > 60
            ? '3mo'
            : periodDays > 20
                ? '1mo'
                : '1mo';

    // Tüm timestamp'leri gece yarısına (00:00:00) normalize eden yardımcı fonskiyon
    int normalizeTs(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
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
      if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, range);
        if (pts.isNotEmpty) _cache[cacheKey] = pts;
        return pts;
      } catch (e) {
        return [];
      }
    }

    // -- Ağ çağrıları --
    if (needsUsd) {
      final usdPoints = await getHistorySafe('USDTRY=X');
      for (final p in usdPoints) {
        usdTryHistory[normalizeTs(p.$1)] = p.$2;
      }
    }

    if (needsGold) {
      final xauPoints = await getHistorySafe('GC=F');
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
        final gram22k = xauTry / 31.1035 * (22 / 24);
        goldHistory[dTs] = gram22k;
      }
    }

    // Hisse, Emtia, Döviz ve TEFAS Fon API Verileri
    for (final a in assets) {
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (fetchable && !tickerNormalizedDaily.containsKey(a.ticker)) {
        final rawPts = await getHistorySafe(a.ticker);
        final map = <int, double>{};
        for (final p in rawPts) {
          map[normalizeTs(p.$1)] = p.$2;
        }
        tickerNormalizedDaily[a.ticker] = map;
      }
    }

    // -- Toparlama ve Hizalama (Her gün için) --
    final startMs = now.subtract(Duration(days: periodDays)).millisecondsSinceEpoch;
    for (int i = periodDays; i >= 0; i--) {
      final dayDate = now.subtract(Duration(days: i));
      final dayTs = normalizeTs(dayDate.millisecondsSinceEpoch);
      if (dayTs < normalizeTs(startMs)) continue;

      double dayTotalValue = 0.0;

      for (final a in assets) {
        try {
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
              assetDayVal = price * factor * a.quantity;
            } else {
              assetDayVal = _flatFallback(a);
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
              assetDayVal = price * a.quantity;
            } else {
              assetDayVal = _flatFallback(a);
            }
          } else {
            assetDayVal = _flatFallback(a);
          }

          dayTotalValue += assetDayVal;
        } catch (e) {
          dayTotalValue += _flatFallback(a);
        }
      }

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
        liveTotal += tryPrice * a.quantity;
      }
      if (!skipOverwrite && liveTotal > 0) {
        // Geçmiş seriye göre >%30 sapma varsa (ölçek uyumsuzluğu şüphesi)
        // suni sıçrama yaratmamak için overwrite'ı atla.
        final prevDayTs = normalizeTs(
            now.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
        final prev = groupedPoints[prevDayTs];
        if (prev != null && prev > 0) {
          final dev = ((liveTotal - prev) / prev).abs();
          if (dev < 0.30) {
            groupedPoints[todayTs] = liveTotal;
          }
        } else {
          groupedPoints[todayTs] = liveTotal;
        }
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
    if (map.containsKey(targetTs)) return map[targetTs]!;
    // Yoksa en yakın geçmiş tarihi (haftasonu durumu vs) bul
    List<int> sortedKeys = map.keys.toList()..sort();
    final pastKeys = sortedKeys.where((k) => k <= targetTs).toList();
    if (pastKeys.isNotEmpty) return map[pastKeys.last]!;
    // Geçmişte yoksa gelecekteki en yakın ilk günü dön
    if (sortedKeys.isNotEmpty) return map[sortedKeys.first]!;
    return fallbackValue ?? 0.0;
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

    final now = DateTime.now();
    final Map<String, Map<int, double>> tickerSlots = {};
    Map<int, double> usdTrySlots = {};

    Future<List<(int, double)>> getHistorySafe(String sym) async {
      final cacheKey = '${sym}_$range';
      if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, range);
        if (pts.isNotEmpty) _cache[cacheKey] = pts;
        return pts;
      } catch (_) {
        return [];
      }
    }

    bool needsUsd = assets
        .any((a) => a.currency == 'USD' || a.type == AssetType.altin);

    if (needsUsd) {
      final usd = await getHistorySafe('USDTRY=X');
      for (final p in usd) {
        usdTrySlots[normalizeSlot(p.$1)] = p.$2;
      }
    }

    for (final a in assets) {
      if (a.quantity <= 0) continue;
      if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty)) {
        if (!tickerSlots.containsKey(a.ticker)) {
          final raw = await getHistorySafe(a.ticker);
          final map = <int, double>{};
          for (final p in raw) {
            map[normalizeSlot(p.$1)] = p.$2;
          }
          tickerSlots[a.ticker] = map;
        }
      }
    }

    final groupedPoints = <int, double>{};

    // Bugünün 00:00'ından başlayarak 5 dakikalık grid üret.
    final dayStart = DateTime(now.year, now.month, now.day);
    final slotCount = hours * (60 ~/ slotMinutes); // 24h → 288 slot

    for (int i = 0; i <= slotCount; i++) {
      final hourDate = dayStart.add(Duration(minutes: i * slotMinutes));
      final hourTs = normalizeSlot(hourDate.millisecondsSinceEpoch);

      double total = 0.0;
      for (final a in assets) {
        try {
          double v = 0.0;
          if (a.type == AssetType.altin) {
            // Saatlik altın verisi yok — currentPrice sabit
            v = a.currentPrice * a.quantity;
          } else if (a.type == AssetType.fon) {
            v = a.currentPrice * a.quantity;
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.doviz) {
            final map = tickerSlots[a.ticker] ?? {};
            if (map.isNotEmpty) {
              double price = _getClosestPrice(map, hourTs, null);
              if (a.currency == 'USD') {
                double usdRate = usdTrySlots.isNotEmpty
                    ? _getClosestPrice(usdTrySlots, hourTs, 35.0)
                    : 35.0;
                price *= usdRate;
              }
              v = price * a.quantity;
            } else {
              v = a.currentPrice * a.quantity *
                  (a.currency == 'USD' ? 35.0 : 1.0);
            }
          } else {
            v = a.currentPrice * a.quantity;
          }
          total += v;
        } catch (_) {
          total += a.currentPrice * a.quantity;
        }
      }
      groupedPoints[hourTs] = total;
    }

    return groupedPoints;
  }
}
