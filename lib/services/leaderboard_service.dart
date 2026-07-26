import '../models/asset.dart';
import '../models/position.dart';
import 'history_service.dart';

/// Leaderboard için "dönem sonu değeri vs dönem başı değeri" bazlı basit
/// ROI hesabı. Kesin TWR değil — MVP için yeterli metrik.
///
/// Formül:
///   startValue = period başındaki portföy değeri (o günkü market price × o
///                gün elinde bulunan quantity)
///   endValue   = bugünkü portföy değeri
///   roi%       = (endValue - startValue - netCashFlow) / max(startValue, epsilon) × 100
///
/// netCashFlow: period içinde yapılan (buy TRY) - (sell TRY) — deposit
/// etkisini ROI'den çıkarır ki büyük yatırım yapan biri "daha iyi
/// performans göstermiş" gibi görünmesin.
class LeaderboardService {
  static final LeaderboardService instance = LeaderboardService._();
  LeaderboardService._();

  /// Bir kullanıcının portföy assets'ini alıp, verilen periyotta ROI%
  /// döner. Assets boşsa veya start değeri hesaplanamıyorsa null.
  Future<double?> computeROI({
    required List<Asset> assets,
    required int periodDays,
    required double currentValueTRY,
  }) async {
    if (assets.isEmpty) return null;

    // History → daily portfolio TRY value
    try {
      final history = await HistoryService.instance
          .getPortfolioHistory(assets, periodDays);
      if (history.isEmpty) return null;

      // Period başı — history'nin en eski noktası (en küçük ms epoch)
      final entries = history.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final startValue = entries.first.value;
      if (startValue <= 0) return null;

      // Bu period içinde net cash flow (buy − sell TRY)
      final startTs = entries.first.key;
      final now = DateTime.now();
      final periodStart =
          DateTime.fromMillisecondsSinceEpoch(startTs);
      double netCashFlow = 0;
      for (final a in assets) {
        if (a.addedDate.isBefore(periodStart)) continue;
        if (a.addedDate.isAfter(now)) continue;
        if (a.isBuy) netCashFlow += a.totalCostTRY;
        if (a.isSell) netCashFlow -= a.totalCostTRY;
      }

      // Deposit etkisini çıkararak "salt performans" ROI:
      final adjustedGain = currentValueTRY - startValue - netCashFlow;
      return (adjustedGain / startValue) * 100.0;
    } catch (_) {
      return null;
    }
  }

  /// Bir varlık listesinin canlı toplam TRY değeri (net pozisyondan hesaplı).
  /// portfolio_provider'daki aggregatePositions ile aynı mantık.
  double totalValueTRY(
      List<Asset> assets, double Function(double, String) toTRY) {
    return aggregatePositions(assets)
        .map((p) => p.asDisplayAsset())
        .fold<double>(0, (s, a) => s + toTRY(a.totalValue, a.currency));
  }
}
