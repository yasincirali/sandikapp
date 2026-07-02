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
    final range = periodDays > 100
        ? '1y'
        : periodDays > 60
            ? '3mo'
            : periodDays > 20
                ? '1mo'
                : periodDays > 6
                    ? '5d'
                    : '1d';

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
        // USD fallback find
        double usdRate = 35.0;
        if (usdTryHistory.containsKey(dTs)) {
          usdRate = usdTryHistory[dTs]!;
        } else if (usdTryHistory.isNotEmpty) {
          // En son bilineni al (Aynı gün yoksa)
          final closest = usdTryHistory.entries.lastWhere((e) => e.key <= dTs,
              orElse: () => usdTryHistory.entries.first);
          usdRate = closest.value;
        }

        final xauTry = xauUsd * usdRate;
        final gram22k = xauTry / 31.1035 * (22 / 24);
        goldHistory[dTs] = gram22k;
      }
    }

    // Hisse ve Emtia API Verileri
    for (final a in assets) {
      if (a.quantity <= 0) continue;
      if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker == 'USDTRY=X')) {
        if (!tickerNormalizedDaily.containsKey(a.ticker)) {
          final rawPts = await getHistorySafe(a.ticker);
          final map = <int, double>{};
          for (final p in rawPts) {
            map[normalizeTs(p.$1)] = p.$2;
          }
          tickerNormalizedDaily[a.ticker] = map;
        }
      }
    }

    // -- Toparlama ve Hizalama (Her gün için) --
    // Geçmiş periyot boyunca tam 'periodDays' adet gün (gece yarısı ms) üretelim
    for (int i = periodDays; i >= 0; i--) {
      final dayDate = now.subtract(Duration(days: i));
      final dayTs = normalizeTs(dayDate.millisecondsSinceEpoch);

      double dayTotalValue = 0.0;

      for (final a in assets) {
        try {
          double assetDayVal = 0.0;
          double fallbackReturn = (a.type == AssetType.fon) ? 0.60 : 0.40;

          // Fiyat arayışı
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
              assetDayVal = _getSimFallback(a, i, fallbackReturn);
            }
          } else if (a.type == AssetType.doviz && a.ticker == 'USDTRY=X') {
            if (usdTryHistory.isNotEmpty) {
              double price = _getClosestPrice(usdTryHistory, dayTs, null);
              assetDayVal = price * a.quantity;
            } else {
              assetDayVal = _getSimFallback(a, i, fallbackReturn);
            }
          } else if (a.type == AssetType.hisse || a.type == AssetType.emtia) {
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
              assetDayVal = _getSimFallback(a, i, fallbackReturn);
            }
          } else {
            assetDayVal = _getSimFallback(a, i, fallbackReturn);
          }

          dayTotalValue += assetDayVal;
        } catch (e) {
          dayTotalValue += _getSimFallback(a, i, 0.40);
        }
      }

      groupedPoints[dayTs] = dayTotalValue;
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

  double _getSimFallback(Asset asset, int diffDays, double yearlyReturn) {
    final endPrice = asset.currentPrice > 0 ? asset.currentPrice : 100.0 * 35.0;
    double simulated = endPrice / (1.0 + (yearlyReturn * (diffDays / 365.0)));
    double TRYsim = asset.currency == 'USD' ? simulated * 35.0 : simulated;
    return TRYsim * asset.quantity;
  }
}
