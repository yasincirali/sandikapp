import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/asset.dart';
import '../models/position.dart';
import 'history_service.dart';

/// Kâr/zarar hesabı sonucu.
///
/// [usedFallback] her zaman `false` — tek formül var, ikinci bir yol yok.
/// Alan çağrı yerlerini kırmamak için duruyor; yeni kod buna BAKMAMALI.
/// (Eskiden UI "tahmini" rozeti için kullanılacaktı ama hiç bağlanmadı.)
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

/// Leaderboard sıralaması: **seçili dönemin getirisi.**
///
/// ```
///   getiri% = (dönem sonu değeri − dönem başı değeri) / dönem başı değeri × 100
/// ```
///
/// Takip listesi grafiğindeki `normalizeSeries` ile AYNI soru — "bu dönemde
/// yüzde kaç değişti?" Seri `getPortfolioHistory(..., simulate: true)` ile
/// üretilir: bugünkü net pozisyon dönemin tamamına yayılır.
///
/// ## Neden simülasyon
/// Gerçek geçmiş modunda bir lot'un `addedDate`'inden önceki slotlara 0
/// yazılır. Dönem başı 0 olunca bölme tanımsız kalır ve dönem içinde alım
/// yapan HERKES sıralamadan düşerdi. Simülasyon herkesi aynı pencerede
/// ölçer. (Takip listesi grafiği de aynı gerekçeyle simülasyon kullanıyor.)
///
/// ## Neden tek formül (2026-09-02'de düzeltildi)
/// Önceki hesap İKİ ayrı formül kullanıyordu ve hangisinin çalıştığı KİŞİYE
/// GÖRE değişiyordu:
///   · dönem başında portföyü OLAN → dönemsel ROI + nakit akışı düzeltmesi
///   · dönem başında portföyü OLMAYAN → maliyet bazlı fallback
///
/// Ölçüldü: aynı işlemi yapan iki kullanıcı **%380,67** ve **%20,00** olarak
/// sıralanıyordu. Aynı yarışta iki farklı metrik → sıralama anlamsız.
/// Dallanma kaldırıldı; artık herkes tek yoldan geçiyor.
///
/// ## Herkes bu cihazda hesaplanır
/// Ortağın lot'ları `allPartnerAssetsProvider` ile zaten burada. Sunucu
/// snapshot'ını beklemek, ortak uygulamayı açmadıysa onu yarıştan
/// düşürüyordu — bkz. [donemGetirisiPct].
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

  /// Bir kullanıcının SEÇİLİ DÖNEMDEKİ getirisi.
  ///
  /// ```
  ///   (dönem sonu değeri − dönem başı değeri) / dönem başı değeri × 100
  /// ```
  ///
  /// [currentValueTRY] ve [toTRY] artık KULLANILMIYOR (imza geriye dönük
  /// uyumluluk için duruyor): değer de dönem başı da aynı fiyat serisinden
  /// gelir, yani iki ayrı kaynak yok. Bu projede iki kaynak kullanmak tekrar
  /// eden bir hata sınıfı.
  ///
  /// Herkes — ben ve ortaklar — [donemGetirisiPct] üzerinden geçer.
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
    final result = await donemGetirisiPct(assets, periodDays);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[LeaderboardService.computeROI] user=${cacheKey ?? "?"} '
          'periodDays=$periodDays => ${result?.toStringAsFixed(2) ?? "null"}%');
    }

    if (ck != null) {
      _roiCache[ck] = (at: DateTime.now(), roi: result);
    }
    // Tek formül var; "tahmini" diye ayrı bir hâl yok.
    return RoiResult(roi: result, usedFallback: false);
  }

  /// Bir varlık listesinin SEÇİLİ DÖNEMDEKİ getirisi.
  ///
  /// ```
  ///   (dönem sonu değeri − dönem başı değeri) / dönem başı değeri × 100
  /// ```
  ///
  /// Takip listesi grafiğindeki `normalizeSeries` ile AYNI soru: "bu dönemde
  /// yüzde kaç değişti?" Seri `getPortfolioHistory(..., simulate: true)` ile
  /// üretilir — bugünkü net pozisyon dönemin tamamına yayılır.
  ///
  /// ## Neden `simulate: true`
  /// Gerçek geçmiş modunda bir lot'un `addedDate`'inden önceki slotlara 0
  /// yazılır; dönem başı 0 olunca bölme tanımsız kalır ve dönem içinde alım
  /// yapan herkes sıralamadan düşerdi. Simülasyon, herkesi aynı pencerede
  /// ölçer — "bu varlıkları dönem başından beri tutsaydım" senaryosu.
  /// (Takip listesi grafiği de aynı gerekçeyle simülasyon kullanıyor.)
  ///
  /// ## Ortaklar için de aynı yol
  /// Ortağın lot'ları `allPartnerAssetsProvider` üzerinden bu cihazda ZATEN
  /// var ve `refreshPrices` `currentPrice`'ı canlı kotasyonla güncelliyor
  /// (RLS DB'ye yazmayı engellese de bellekte günceller). Sunucu snapshot'ı
  /// beklemek üç soruna yol açıyordu:
  ///   · ortak uygulamayı hiç açmadıysa → yarışta değeri YOK,
  ///   · eski sürümde açtıysa → eski formülle yazılmış BAYAT değer,
  ///   · bugün açmadıysa → dünkü fiyatlarla hesaplanmış değer.
  ///
  /// Dönem başı ≤ 0 ise `null` — bölme tanımsız.
  Future<double?> donemGetirisiPct(
    List<Asset> assets,
    int periodDays,
  ) async {
    if (assets.isEmpty) return null;
    try {
      final seri = await HistoryService.instance
          .getPortfolioHistory(assets, periodDays, simulate: true);
      if (seri.length < 2) return null;
      final ts = seri.keys.toList()..sort();
      final ilk = seri[ts.first]!;
      final son = seri[ts.last]!;
      if (ilk <= 0) return null;
      return ((son - ilk) / ilk) * 100.0;
    } catch (_) {
      // Fiyat geçmişi alınamadı — "veri yok" olarak göster. Uydurma bir
      // sayı basmak sıralamayı sessizce bozardı.
      return null;
    }
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
  ///
  /// **ŞU AN KULLANILMIYOR** (2026-09-02). Yarış ekranı ortakların kâr/zararını
  /// artık YERELDE hesaplıyor (`karZararPctFor`), çünkü ortağın lot'ları
  /// `allPartnerAssetsProvider` üzerinden zaten cihazda ve canlı fiyatlarla
  /// güncel. Snapshot'a bağlı kalmak üç soruna yol açıyordu:
  ///   · ortak uygulamayı hiç açmadıysa → yarışta değeri YOK,
  ///   · eski sürümde açtıysa → eski formülle yazılmış bayat değer,
  ///   · bugün açmadıysa → dünkü fiyatlarla hesaplanmış değer.
  ///
  /// Silinmedi: RPC sunucuda duruyor ve ortak sayısı cihazda tutulamayacak
  /// kadar büyürse (ya da ortak lot'ları gizlenirse) sunucu tarafı sıralamaya
  /// dönmek gerekebilir.
  ///
  /// Dönen map: partnerUserId → (roi%, snapshot'ın atıldığı zaman).
  Future<Map<String, ({double roi, DateTime updatedAt})>> fetchPartnerRois(
      int periodDays) async {
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
  Future<({int percentile, int total})?> fetchPercentile(int periodDays) async {
    try {
      final result =
          await Supabase.instance.client.rpc('get_percentile_bucket', params: {
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
