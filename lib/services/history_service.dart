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
    // Haftalık periyot için saatlik çözünürlük (~80 nokta)
    if (periodDays <= 7) {
      return _getPortfolioHistoryHourly7d(assets);
    }

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

    return groupedPoints;
  }

  /// Haftalık görünüm için saatlik çözünürlük. Yahoo `5d/1h` → ~80 nokta.
  /// Altın ve USD dönüşümü günlük yaklaşımla yapılır (intraday kur verisi yok).
  Future<Map<int, double>> _getPortfolioHistoryHourly7d(
      List<Asset> assets) async {
    const range = '5d';
    const hourlyRange = '5d_1h';

    int normalizeHour(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
    }

    int normalizeDay(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }

    Future<List<(int, double)>> getHistorySafe(String sym,
        {String? cacheKey, String? overrideRange}) async {
      final key = cacheKey ?? '${sym}_$range';
      if (_cache.containsKey(key)) return _cache[key]!;
      try {
        final pts = await PriceService.instance
            .fetchHistory(sym, overrideRange ?? range);
        if (pts.isNotEmpty) _cache[key] = pts;
        return pts;
      } catch (e) {
        return [];
      }
    }

    bool needsGold = assets.any((a) => a.type == AssetType.altin);
    bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    // USD/TRY ve altın günlük (5d/1d) — intraday kur verisi güvenilmez
    Map<int, double> usdTryDaily = {};
    Map<int, double> goldDaily = {};

    if (needsUsd) {
      final pts = await getHistorySafe('USDTRY=X');
      for (final p in pts) {
        usdTryDaily[normalizeDay(p.$1)] = p.$2;
      }
    }

    if (needsGold) {
      final xauPts = await getHistorySafe('GC=F');
      for (final p in xauPts) {
        final dTs = normalizeDay(p.$1);
        double usdRate = usdTryDaily[dTs] ??
            (usdTryDaily.isNotEmpty
                ? _getClosestPrice(usdTryDaily, dTs, 35.0)
                : 35.0);
        final gram22k = p.$2 * usdRate / 31.1035 * (22 / 24);
        goldDaily[dTs] = gram22k;
      }
    }

    // Saatlik fiyat haritası: ticker → { saatlik_ts: fiyat }
    final Map<String, Map<int, double>> tickerHourly = {};

    for (final a in assets) {
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (!fetchable || tickerHourly.containsKey(a.ticker)) continue;

      // TEFAS fonları için günlük veri kullan (saatlik desteklenmiyor)
      final isTefas = a.ticker.startsWith('TEFAS_');
      final pts = isTefas
          ? await getHistorySafe(a.ticker)
          : await getHistorySafe(a.ticker,
              cacheKey: '${a.ticker}_$hourlyRange',
              overrideRange: '5d_1h');

      final map = <int, double>{};
      for (final p in pts) {
        final ts = isTefas ? normalizeDay(p.$1) : normalizeHour(p.$1);
        map[ts] = p.$2;
      }
      tickerHourly[a.ticker] = map;
    }

    // Ham saatlik timestamp'leri topla (tüm tickerlardan)
    final allHourTs = <int>{};
    for (final map in tickerHourly.values) {
      allHourTs.addAll(map.keys);
    }

    // Altın/nakit gibi tickerHourly'e girmeyen varlıklar varsa
    // goldDaily veya usdTryDaily'den saatlik grid üret (her gün 8 slot: 09-17)
    if (allHourTs.isEmpty) {
      final baseDays = goldDaily.isNotEmpty
          ? goldDaily.keys
          : usdTryDaily.isNotEmpty
              ? usdTryDaily.keys
              : <int>[];
      for (final dayTs in baseDays) {
        for (int h = 9; h <= 17; h++) {
          allHourTs.add(dayTs + h * 3600 * 1000);
        }
      }
    }

    // Hâlâ boşsa günlük fallback
    if (allHourTs.isEmpty) {
      return getPortfolioHistory(assets, 7);
    }

    final cutoff =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final sortedTs =
        allHourTs.where((t) => t >= cutoff).toList()..sort();

    final result = <int, double>{};
    for (final ts in sortedTs) {
      final dayTs = normalizeDay(ts);
      double total = 0.0;

      for (final a in assets) {
        try {
          double val = 0.0;
          if (a.type == AssetType.altin) {
            double factor = (a.ticker == 'ALTIN_CEYREK')
                ? 1.75
                : (a.ticker == 'ALTIN_YARIM')
                    ? 3.5
                    : (a.ticker == 'ALTIN_CUMHURIYET' ||
                            a.ticker == 'ALTIN_ATA')
                        ? 7.216
                        : 1.0;
            val = _getClosestPrice(goldDaily, dayTs, null) * factor * a.quantity;
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.fon ||
              a.type == AssetType.doviz) {
            final map = tickerHourly[a.ticker] ?? {};
            if (map.isNotEmpty) {
              double price = _getClosestPrice(map, ts, null);
              if (a.currency == 'USD') {
                double usdRate = _getClosestPrice(usdTryDaily, dayTs, 35.0);
                price *= usdRate;
              }
              val = price * a.quantity;
            } else {
              val = _flatFallback(a);
            }
          } else {
            val = _flatFallback(a);
          }
          total += val;
        } catch (_) {
          total += _flatFallback(a);
        }
      }

      result[ts] = total;
    }

    return result;
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
    final tryPrice = asset.currency == 'USD' ? price * 35.0 : price;
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
