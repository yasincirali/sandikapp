import 'package:flutter/foundation.dart';
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
/// ROI hesabı sonucu — değer ve fallback bayrağı birlikte. usedFallback=true
/// ise UI "tahmini" işareti gösterebilir; hesap history yerine unrealized
/// PnL'den yapılmıştır.
class RoiResult {
  final double? roi;
  final bool usedFallback;
  const RoiResult({required this.roi, required this.usedFallback});
}

/// Top gainer satırı — anonim, sadece rank + ROI + tür yüzdeleri.
class TopGainerAllocation {
  final int rank;
  final double roiPct;
  /// Tür bazlı yüzde, örn. {"hisse": 45.2, "doviz": 30.1, ...}. Sum ≈ 100.
  final Map<String, double> allocation;
  const TopGainerAllocation({
    required this.rank,
    required this.roiPct,
    required this.allocation,
  });
}

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
  ///
  /// Formül:
  ///   ROI% = (currentValue - startValue - netCashFlow) / startValue × 100
  ///
  /// Nerede:
  ///   - startValue = dönem başındaki portföy değeri (TL, o günkü fiyatlarla)
  ///   - currentValue = bugünkü portföy değeri (TL)
  ///   - netCashFlow = dönem içinde eklenen yeni sermaye eksi çekim:
  ///        + isBuy: satın alım TL maliyeti (deposit)
  ///        - isSell: satış geliri (sellPrice × quantity × FX)  — DİKKAT:
  ///          maliyet DEĞİL, satış geliri kullanılır. Aksi halde kârlı
  ///          satış "çekilmiş sermaye" olarak eksik sayılır ve ROI düşük
  ///          hesaplanır.
  ///
  /// History fetch başarısız ya da dönem başı değer 0 ise unrealized PnL%'ye
  /// fallback yapar ([usedFallback] = true olarak dönerse UI "tahmini"
  /// göstergesi koyabilir).
  Future<RoiResult> computeROIDetailed({
    required List<Asset> assets,
    required int periodDays,
    required double currentValueTRY,
    required double Function(double, String) toTRY,
    String? cacheKey,
  }) async {
    if (assets.isEmpty) {
      return const RoiResult(roi: null, usedFallback: false);
    }

    final ck = cacheKey == null ? null : '$cacheKey|$periodDays';

    // Unrealized PnL fallback — net pozisyonun toplam maliyetine göre.
    final totalCostTRY = aggregatePositions(assets)
        .map((p) => p.asDisplayAsset())
        .fold<double>(0, (s, a) => s + toTRY(a.totalCost, a.currency));
    double? fallbackPnlPct() {
      if (totalCostTRY <= 0) return null;
      return ((currentValueTRY - totalCostTRY) / totalCostTRY) * 100.0;
    }

    double? result;
    bool usedFallback = false;
    String? diagnostic;

    try {
      final history = await HistoryService.instance
          .getPortfolioHistory(assets, periodDays);
      if (history.isEmpty) {
        result = fallbackPnlPct();
        usedFallback = true;
        diagnostic =
            'history=empty periodDays=$periodDays → unrealized PnL fallback';
      } else {
        final entries = history.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final startValue = entries.first.value;
        if (startValue <= 0) {
          result = fallbackPnlPct();
          usedFallback = true;
          diagnostic =
              'startValue=$startValue (dönem başında portföy boş) → fallback';
        } else {
          final startTs = entries.first.key;
          final now = DateTime.now();
          final periodStart =
              DateTime.fromMillisecondsSinceEpoch(startTs);
          double netCashFlow = 0;
          for (final a in assets) {
            // Yumuşak silinmiş kayıt nakit akışına girmez — silinen varlık
            // hiç alınmamış/satılmamış sayılır.
            if (!a.isActive) continue;
            if (a.addedDate.isBefore(periodStart)) continue;
            if (a.addedDate.isAfter(now)) continue;
            if (a.isBuy) {
              // Alım maliyeti — asset üzerindeki purchaseFxRate ile TL.
              netCashFlow += a.totalCostTRY;
            } else if (a.isSell) {
              // Satış geliri — sellPrice ile hesaplanır (maliyet DEĞİL).
              // sellPrice varsa onu, yoksa purchasePrice'a fallback.
              // TL'ye çevirme için bugünkü FX kullanılır (satış anındaki
              // tarihsel FX'i persist etmiyoruz; approximation).
              final unitPrice = a.sellPrice ?? a.purchasePrice;
              final saleProceedsTRY =
                  toTRY(unitPrice * a.quantity, a.currency);
              netCashFlow -= saleProceedsTRY;
            }
          }
          final adjustedGain = currentValueTRY - startValue - netCashFlow;
          result = (adjustedGain / startValue) * 100.0;
          diagnostic =
              'startValue=${startValue.toStringAsFixed(0)} '
              'current=${currentValueTRY.toStringAsFixed(0)} '
              'netCashFlow=${netCashFlow.toStringAsFixed(0)} '
              'periodDays=$periodDays historyPoints=${history.length}';
        }
      }
    } catch (e) {
      result = fallbackPnlPct();
      usedFallback = true;
      diagnostic = 'exception=$e → unrealized PnL fallback';
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[LeaderboardService.computeROI] '
          'user=${cacheKey ?? "?"} $diagnostic '
          '=> roi=${result?.toStringAsFixed(2) ?? "null"}%');
    }

    if (ck != null) {
      _roiCache[ck] = (at: DateTime.now(), roi: result);
    }
    return RoiResult(roi: result, usedFallback: usedFallback);
  }

  /// Backwards-compat: eski call site'lar sadece double? bekliyor.
  Future<double?> computeROI({
    required List<Asset> assets,
    required int periodDays,
    required double currentValueTRY,
    required double Function(double, String) toTRY,
    String? cacheKey,
  }) async {
    final r = await computeROIDetailed(
      assets: assets,
      periodDays: periodDays,
      currentValueTRY: currentValueTRY,
      toTRY: toTRY,
      cacheKey: cacheKey,
    );
    return r.roi;
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

  /// Aktif ortakların son ROI snapshot'larını Supabase'ten çeker.
  /// Her cihaz bu değeri okuyacak → iki cihaz aynı satırı görür (hesap
  /// tutarsızlığı biter). Snapshot atmayan partner map'te olmaz —
  /// caller onu "veri yok" olarak gösterir.
  ///
  /// Dönen map: partnerUserId → (roi%, snapshot'ın atıldığı zaman).
  Future<Map<String, ({double roi, DateTime updatedAt})>>
      fetchPartnerRois(int periodDays) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_partner_rois',
        params: {'p_period_days': periodDays},
      );
      if (res == null) return const {};
      final rows = res as List<dynamic>;
      final out = <String, ({double roi, DateTime updatedAt})>{};
      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final uid = row['user_id'] as String?;
        final roi = (row['roi_pct'] as num?)?.toDouble();
        final tsRaw = row['updated_at'];
        if (uid == null || roi == null) continue;
        final ts = tsRaw is String
            ? DateTime.tryParse(tsRaw) ?? DateTime.now()
            : DateTime.now();
        out[uid] = (roi: roi, updatedAt: ts);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Verilen aktif portföy asset'lerinden tür bazlı yüzdesel dağılım
  /// hesaplar. Net pozisyonlar (buy - sell) üzerinden, TL bazlı toplam
  /// değere göre. Sonuç `{tür: %}` map — sum ≈ 100 (yalnızca değeri > 0
  /// olan türler girer).
  ///
  /// Kullanım: computeAllocation'un çıktısı `uploadAllocationSnapshot`
  /// için doğrudan geçilebilir. Client-side hesap gerekiyor çünkü FX
  /// conversion ve net pozisyon mantığı server'da yok.
  Map<String, double> computeAllocation(
    List<Asset> assets,
    double Function(double, String) toTRY,
  ) {
    final byType = <String, double>{};
    for (final p in aggregatePositions(assets)) {
      final a = p.asDisplayAsset();
      final tl = toTRY(a.totalValue, a.currency);
      if (tl <= 0) continue;
      byType.update(a.type.name, (v) => v + tl, ifAbsent: () => tl);
    }
    final total = byType.values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return const {};
    return {
      for (final e in byType.entries) e.key: (e.value / total) * 100.0,
    };
  }

  /// Kullanıcının tür bazlı % dağılımını Supabase'e yazar. Miktar, TL,
  /// ticker göndermez — sadece {tür: %}. Aktif varlıklar (buy - sell)
  /// üzerinden TL bazlı hesaplanmış oranlar client tarafında hazırlanır.
  ///
  /// [allocation] map: {"hisse": 45.2, "doviz": 30.1, ...} — sum ≈ 100.
  /// [typeCount] map'teki tür sayısı; RPC anti-fingerprint filtresi için.
  Future<void> uploadAllocationSnapshot({
    required String userId,
    required Map<String, double> allocation,
    required int typeCount,
  }) async {
    try {
      await Supabase.instance.client.from('user_allocation_snapshots').insert({
        'user_id': userId,
        'allocation_pct': allocation,
        'type_count': typeCount,
      });
    } catch (_) {
      // Sessizce yut — ikincil özellik, ana leaderboard'u bozmasın.
    }
  }

  /// Top N gainer'ın anonim portföy dağılımını çeker. user_id/isim/
  /// ticker YOK; sadece rank + roi% + tür yüzdeleri.
  Future<List<TopGainerAllocation>> fetchTopGainersAllocation({
    required int periodDays,
    int topN = 3,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_top_gainers_allocation',
        params: {'p_period_days': periodDays, 'p_top_n': topN},
      );
      if (res == null) return const [];
      final rows = res as List<dynamic>;
      final out = <TopGainerAllocation>[];
      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final rank = (row['rank'] as num?)?.toInt();
        final roi = (row['roi_pct'] as num?)?.toDouble();
        final allocRaw = row['allocation_pct'];
        if (rank == null || roi == null || allocRaw is! Map) continue;
        final alloc = <String, double>{
          for (final e in allocRaw.entries)
            e.key as String: (e.value as num).toDouble(),
        };
        out.add(TopGainerAllocation(
          rank: rank,
          roiPct: roi,
          allocation: alloc,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Caller'ın son 24 saatteki anonim genel sıralamasını döndürür.
  /// k-anonymity (min 8 katılımcı, bkz. migration 0031) altında null
  /// döner — bu durumda UI "Yakında" placeholder gösterir.
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
