import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/asset.dart';
import '../models/position.dart';

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

/// Leaderboard sıralaması: **ortalama maliyet üzerinden kâr/zarar yüzdesi.**
///
/// ```
///   kâr/zarar% = (güncel değer − toplam maliyet) / toplam maliyet × 100
/// ```
///
/// Toplam maliyet, `aggregatePositions` ile hesaplanan AĞIRLIKLI ORTALAMA
/// maliyettir: komisyonlar dahil, her lot'un alım anındaki kuruyla. Yani
/// kullanıcının portföy ekranında gördüğü sayının aynısı
/// (`PortfolioState.gainLossPercentage`).
///
/// ## Neden dönem bazlı ROI değil (2026-09-02'de değiştirildi)
/// Önceki hesap iki farklı formül kullanıyordu ve hangisinin çalıştığı
/// KİŞİYE GÖRE değişiyordu:
///   · dönem başında portföyü OLAN → `(değer − dönemBaşı − nakitAkışı) / dönemBaşı`
///   · dönem başında portföyü OLMAYAN → maliyet bazlı fallback
///
/// Ölçüldü: aynı işlemi yapan iki kullanıcı (ikisi de 100'den alıp 120'ye
/// çıkmış, yani %20 kâr) **%380,67** ve **%20,00** olarak sıralanıyordu.
/// Aynı yarışta iki farklı metrik, dolayısıyla sıralama anlamsızdı.
///
/// Tek formül bu sorunu YAPISAL olarak çözer: dallanma yoksa kişiye göre
/// değişen bir sonuç da olamaz. Herkes aynı soruya cevap verir —
/// "yatırdığın paraya göre ne kadar kazandın?"
///
/// ## Kabul edilen sınır
/// Bu bir ZAMAN AĞIRLIKLI getiri (TWR) DEĞİLDİR; dönem seçimi sonucu
/// etkilemez. 3 yılda %50 kazanan ile 3 ayda %50 kazanan aynı görünür.
/// TWR doğru cevap olurdu ama her lot için tarihsel nakit akışı gerektirir;
/// mevcut veri modeli bunu taşımıyor. Basit ve HERKES İÇİN AYNI olan bir
/// metrik, karmaşık ama kişiye göre değişen bir metrikten iyidir.
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

  /// Bir kullanıcının kâr/zarar yüzdesi — **ortalama maliyet üzerinden.**
  ///
  /// ```
  ///   (güncel değer − toplam maliyet) / toplam maliyet × 100
  /// ```
  ///
  /// [periodDays] artık hesabı ETKİLEMEZ; yalnızca önbellek anahtarı ve
  /// sunucudaki snapshot'ın dönem etiketi için taşınır. Sıralama, herkesin
  /// tüm varlıklarının ağırlıklı ortalama maliyetine göre yapılır — kim ne
  /// zaman almış olursa olsun aynı soruya cevap verir.
  ///
  /// Maliyeti bilinmeyen (0) portföy için `null` döner: bölme tanımsızdır ve
  /// 0 göstermek "başabaş" yanılgısı yaratırdı.
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
    final result = maliyetBazliKarZararPct(assets, currentValueTRY, toTRY);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[LeaderboardService.computeROI] user=${cacheKey ?? "?"} '
          'current=${currentValueTRY.toStringAsFixed(0)} '
          'cost=${toplamMaliyetTRY(assets, toTRY).toStringAsFixed(0)} '
          '=> ${result?.toStringAsFixed(2) ?? "null"}%');
    }

    if (ck != null) {
      _roiCache[ck] = (at: DateTime.now(), roi: result);
    }
    // Tek formül var; "tahmini" diye ayrı bir hâl yok.
    return RoiResult(roi: result, usedFallback: false);
  }

  /// Net pozisyonların ağırlıklı ortalama maliyeti (TRY).
  ///
  /// `aggregatePositions` kullanılır: sell lot'ları buy miktarından düşer,
  /// silinmiş kayıtlar elenir. Her pozisyonun maliyeti kendi alım kuruyla
  /// TRY'ye çevrilir (bankacılık standardı — bugünkü kurla değil).
  double toplamMaliyetTRY(
    List<Asset> assets,
    double Function(double, String) toTRY,
  ) =>
      aggregatePositions(assets)
          .map((p) => p.asDisplayAsset())
          .fold<double>(0, (s, a) => s + toTRY(a.totalCost, a.currency));

  /// Ortalama maliyet üzerinden kâr/zarar yüzdesi.
  ///
  /// Saf fonksiyon — leaderboard'un TEK metriği. Portföy ekranındaki
  /// `PortfolioState.gainLossPercentage` ile aynı soruyu yanıtlar, yani
  /// kullanıcı yarışta gördüğü sayıyı kendi portföyünde de görür.
  ///
  /// Maliyet 0 veya negatifse `null` — bölme tanımsız.
  double? maliyetBazliKarZararPct(
    List<Asset> assets,
    double currentValueTRY,
    double Function(double, String) toTRY,
  ) {
    final maliyet = toplamMaliyetTRY(assets, toTRY);
    if (maliyet <= 0) return null;
    return ((currentValueTRY - maliyet) / maliyet) * 100.0;
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
