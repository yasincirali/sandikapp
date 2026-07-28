import 'package:supabase_flutter/supabase_flutter.dart';
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

  // In-memory ROI cache — key: (userId, periodDays). Session boyunca kalır.
  // Ekran her açılışta cache'i placeholder olarak gösterir (stale ok),
  // arka planda hemen yeniden hesaplar. Kullanıcı bekletilmez, veri her
  // zaman güncel.
  final Map<String, ({DateTime at, double? roi})> _roiCache = {};

  void clearCache() => _roiCache.clear();

  /// Önceki hesaptan cache'te kalan ROI değeri (varsa). Ekran açılırken
  /// spinner yerine placeholder olarak gösterilir; asıl `computeROI`
  /// arka planda çağrılır ve gelen sonuç bunun üstüne yazılır.
  double? staleROI({required String userId, required int periodDays}) {
    return _roiCache['$userId|$periodDays']?.roi;
  }

  /// Bir kullanıcının portföy assets'ini alıp verilen periyotta ROI% döner.
  /// History fetch başarısızsa unrealized PnL%'ye fallback yapar. Her
  /// çağrıda gerçek hesap yapılır; [cacheKey] verilirse sonuç cache'e
  /// yazılır — sonraki açılışta [staleROI] anında okuyabilir.
  Future<double?> computeROI({
    required List<Asset> assets,
    required int periodDays,
    required double currentValueTRY,
    required double Function(double, String) toTRY,
    String? cacheKey,
  }) async {
    if (assets.isEmpty) return null;

    final ck = cacheKey == null ? null : '$cacheKey|$periodDays';

    // Fallback: net pozisyonun toplam maliyeti — her zaman hesaplanabilir.
    final totalCostTRY = aggregatePositions(assets)
        .map((p) => p.asDisplayAsset())
        .fold<double>(0, (s, a) => s + toTRY(a.totalCost, a.currency));
    double? fallbackPnlPct() {
      if (totalCostTRY <= 0) return null;
      return ((currentValueTRY - totalCostTRY) / totalCostTRY) * 100.0;
    }

    double? result;
    try {
      final history = await HistoryService.instance
          .getPortfolioHistory(assets, periodDays);
      if (history.isEmpty) {
        result = fallbackPnlPct();
      } else {
        final entries = history.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final startValue = entries.first.value;
        if (startValue <= 0) {
          result = fallbackPnlPct();
        } else {
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
          final adjustedGain = currentValueTRY - startValue - netCashFlow;
          result = (adjustedGain / startValue) * 100.0;
        }
      }
    } catch (_) {
      result = fallbackPnlPct();
    }

    if (ck != null) {
      _roiCache[ck] = (at: DateTime.now(), roi: result);
    }
    return result;
  }

  /// Bir varlık listesinin canlı toplam TRY değeri (net pozisyondan hesaplı).
  /// portfolio_provider'daki aggregatePositions ile aynı mantık.
  double totalValueTRY(
      List<Asset> assets, double Function(double, String) toTRY) {
    return aggregatePositions(assets)
        .map((p) => p.asDisplayAsset())
        .fold<double>(0, (s, a) => s + toTRY(a.totalValue, a.currency));
  }

  // ─── Global percentile ─────────────────────────────────────────────────

  /// Sunucuda bu kullanıcı için daha önce bir ROI snapshot atıldı mı?
  /// True ise kullanıcı bir cihazda opt-in yapmış demektir — uygulama
  /// yeniden kurulsa bile lokal bayrağı buradan hydrate ederiz.
  Future<bool> hasServerSideOptIn(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('user_roi_snapshots')
          .select('user_id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Client'ın hesapladığı ROI değerini snapshot tablosuna yazar. Opt-in
  /// kontrolü çağıran yerin sorumluluğu. Hata sessizce yutulur — bu ikincil
  /// bir operasyon, ana leaderboard'un düşmesine izin vermez.
  Future<void> uploadRoiSnapshot({
    required String userId,
    required int periodDays,
    required double roiPct,
  }) async {
    try {
      await Supabase.instance.client.from('user_roi_snapshots').insert({
        'user_id': userId,
        'period_days': periodDays,
        'roi_pct': roiPct,
      });
    } catch (_) {
      // Sessizce yut — global percentile "yakında" hâli, kullanıcıyı bozmasın.
    }
  }

  /// Caller'ın son 24 saatteki anonim genel sıralamasını döndürür.
  /// k-anonymity (min 20 katılımcı) altında null döner — bu durumda UI
  /// "Yakında" placeholder gösterir.
  ///
  /// Dönen: (percentile 1-100, totalParticipants) veya null.
  Future<({int percentile, int total})?> fetchPercentile(
      int periodDays) async {
    try {
      final result = await Supabase.instance.client
          .rpc('get_percentile_bucket', params: {
        'p_period_days': periodDays,
      });
      if (result == null) return null;
      final rows = result as List<dynamic>;
      if (rows.isEmpty) return null;
      final row = rows.first as Map<String, dynamic>;
      final pct = (row['percentile'] as num?)?.toInt();
      final total = (row['total_participants'] as num?)?.toInt();
      if (pct == null || total == null) return null;
      return (percentile: pct, total: total);
    } catch (_) {
      return null;
    }
  }
}
