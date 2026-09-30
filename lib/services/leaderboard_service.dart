import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';
import 'supabase_service.dart';
import '../models/asset.dart';
import '../models/position.dart';
import 'history_service.dart';
import 'zirve_kiyas.dart';

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

/// Top gainer satırı — anonim: rank + ROI + tür yüzdeleri + fon kırılımı.
class TopGainerAllocation {
  final int rank;
  final double roiPct;

  /// Tür bazlı yüzde, örn. {"hisse": 45.2, "doviz": 30.1, ...}. Sum ≈ 100.
  final Map<String, double> allocation;

  /// Fon türünün TEFAS kodu bazında kırılımı, TOPLAM portföyün yüzdesi
  /// (Σ ≈ allocation['fon']); "DIGER" toplu kalem (0084). Fon yoksa boş.
  final Map<String, double> fonDetay;

  /// Bu satır çağıranın kendi portföyü mü (0085, `auth.uid()`). Başkasına
  /// bir şey söylemez; ekran bu satırı "Sen" diye çizer, ikinci bir "Sen"
  /// işareti koymaz.
  final bool ben;
  const TopGainerAllocation({
    required this.rank,
    required this.roiPct,
    required this.allocation,
    this.fonDetay = const {},
    this.ben = false,
  });
}

/// Çağıranın zirve havuzundaki kendi değeri (0085 `zirve_benim`).
/// Havuzdaysa Zirve ekranı "Sen"i bununla çizer: zirveyle AYNI kaynak ve
/// saat, iki ayrı sayı yok.
typedef ZirveBenim = ({
  double roiPct,
  Map<String, double> allocation,
  Map<String, double> fonDetay,
});

/// `get_percentile_bucket` yanıtı.
///
/// [medianDiffPts] = benim ROI − havuz medyanı (yüzde PUANI). Pozitifse
/// medyandan öndeyim. Sunucu 0061 öncesiyse `null`.
typedef PercentileBucket = ({
  int percentile,
  int total,
  double? medianDiffPts,
});

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
/// ## Neden simülasyon — ölçtüğümüz şey SAF PİYASA HAREKETİ
/// Simülasyon, bugünkü net pozisyonu dönemin tamamına yayar. Bunun doğrudan
/// sonucu: **dönem içindeki alım/satımlar oranı ETKİLEMEZ.** Ölçüldü:
///
/// ```
///   A: 10 adet, hiç dokunmadı        → ilk 3238, son 3000 → −%7,34
///   B: 10 adet + 15 gün önce 10 daha → ilk 6475, son 6000 → −%7,34
///   C: 20 al, 10 sat (net 10)                             → −%7,34
///   D: 1 adet / 10.000 adet                               → −%7,34
/// ```
///
/// Para yatırmak, çekmek ya da portföyü büyütmek sıralamayı değiştirmez;
/// yalnızca piyasanın o varlıklara ne yaptığı ölçülür. Yarışın sorusu budur:
/// "kim daha çok para koydu" değil, "kimin portföyü daha çok değer kazandı".
///
/// Gerçek geçmiş modu bunu YAPAMAZDI: `addedDate`'ten önceki slotlara 0
/// yazıldığı için dönem içinde alım yapan herkes ya sıralamadan düşerdi
/// (dönem başı 0 → bölme tanımsız) ya da yeni para girişi getiri gibi
/// görünürdü. (Takip listesi grafiği de aynı gerekçeyle simülasyon kullanıyor.)
///
/// ## Kabul edilen sınır: varlık DEĞİŞTİRME
/// Simülasyon bugünkü kompozisyonu geçmişe yansıtır. Dönem içinde A'yı satıp
/// B aldıysan, sonuç "hep B tutsaydım" senaryosudur — gerçekleşen getirin
/// değil. Ölçüldü: 15 gün önce THYAO→GARAN geçen biri ile hep GARAN tutan
/// biri aynı çıkıyor (%127,62).
///
/// Bu bilinçli bir tercih: alternatifi zaman ağırlıklı getiri (TWR) olurdu
/// ve o da her lot için tarihsel nakit akışı ister; veri modeli taşımıyor.
/// Ayrıca TWR'de dönem içi işlem YİNE oranı etkilemezdi, sadece daha doğru
/// bir "ne zaman neye sahiptin" ağırlıklandırması yapardı.
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
  ///
  /// **Sahip sınırı korunur (denetim, 2026-09-22).** Eskiden düz
  /// `aggregatePositions` kullanıyordu; `positionKey` sahip TAŞIMAZ, yani
  /// karışık bir defterde (Performans › Özet "Birlikte" kapsamı) iki
  /// kişinin aynı hissesi tek pozisyona düşüyor ve birinin satışı
  /// diğerinin lot'unu düşürüyordu.
  ///
  /// Ölçüldü: ben 10 lot, ortak 4 al + 6 sat → havuz ₺960, doğrusu ₺1.200
  /// (ortağın pozisyonu kapalı, benimki tam). İkinci senaryoda fark ₺360.
  ///
  /// Yarış EKRANLARI bu hatadan etkilenmiyordu: orada her kişi kendi
  /// listesiyle ayrı çağrılıyor (`partnerAssets[p.id]`, `myAssets`).
  /// Ama `ozet_yan_veri` KARIŞIK defter geçiriyor — sunucuya gönderilen
  /// percentile ve XIRR'in tabanı oradan besleniyor.
  ///
  /// Tek sahipli listede davranış AYNI: `lotlarSahibeGore` tek grup döner.
  double totalValueTRY(
      List<Asset> assets, double Function(double, String) toTRY) {
    return ownerScopedTotalValue(lotlarSahibeGore(assets), toTRY: toTRY);
  }

  // ─── Global percentile ─────────────────────────────────────────────────

  /// Sunucuda bu kullanıcı için daha önce bir ROI snapshot atıldı mı?
  /// True ise kullanıcı bir cihazda opt-in yapmış demektir — uygulama
  /// yeniden kurulsa bile lokal bayrağı buradan hydrate ederiz.
  /// Opt-in tercihini sunucuya yansıtır (0081). Arka planda; hata
  /// non-fatal raporlanır, kullanıcı akışı beklemez. Çağıran taraf cihaz
  /// tercihini zaten yazdı; burası yalnızca sunucu bayrağı.
  void optInSunucuyaYaz(String? userId, bool acik) {
    if (userId == null || userId.isEmpty) return;
    CrashReporter.arkaPlan(
      SupabaseService.instance.yarisOptInYaz(userId, acik),
      reason: 'LeaderboardService.optInSunucuyaYaz',
    );
  }

  Future<bool> hasServerSideOptIn(String userId) async {
    // Önce sunucu bayrağı (0081); yoksa/okunamazsa eski kanıt: daha önce
    // atılmış bir snapshot satırı (sütun eklenmeden önceki cihazlar).
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('leaderboard_opt_in')
          .eq('id', userId)
          .maybeSingle();
      if (p != null && p['leaderboard_opt_in'] == true) return true;
    } catch (_) {}
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
      final res = await Supabase.instance.client.rpc<dynamic>(
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

  /// Fon türünün TEFAS kodu bazında kırılımı, toplam portföyün yüzdesi
  /// (Σ ≈ `computeAllocation()['fon']`). Kural sunucuyla aynı
  /// (`ZirveKiyas.fonAnahtari`, %1 eşiği) — Zirve ekranındaki "Sen" satırı
  /// zirveyle aynı ölçüyle okunsun. Yalnız cihazda kalır, gönderilmez.
  Map<String, double> computeFonDetay(
    List<Asset> assets,
    double Function(double, String) toTRY,
  ) {
    final kodDegeri = <String, double>{};
    var toplam = 0.0;
    for (final p in aggregatePositions(assets)) {
      final a = p.asDisplayAsset();
      final tl = toTRY(a.totalValue, a.currency);
      if (tl <= 0) continue;
      toplam += tl;
      if (a.type.name != 'fon') continue;
      final kod = ZirveKiyas.fonAnahtari(a.ticker);
      kodDegeri.update(kod, (v) => v + tl, ifAbsent: () => tl);
    }
    return ZirveKiyas.fonDetayiTopla(kodDegeri, toplam);
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
      // 0084: aynı havuz + fon kırılımı. Eski `get_top_gainers_allocation`
      // yayındaki eski sürümler için sunucuda duruyor.
      final res = await Supabase.instance.client.rpc<dynamic>(
        'zirve_portfoyleri',
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
        final fonRaw = row['fon_detay'];
        out.add(TopGainerAllocation(
          rank: rank,
          roiPct: roi,
          allocation: alloc,
          fonDetay: fonRaw is Map
              ? {
                  for (final e in fonRaw.entries)
                    e.key as String: (e.value as num).toDouble(),
                }
              : const {},
          ben: row['ben'] == true,
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
  /// Dönen: (percentile 1-100, totalParticipants, medyan farkı) veya null.
  /// `medianDiffPts` sunucu 0061'den eskiyse `null` — şerit medyansız
  /// çizilir, hata değil.
  Future<PercentileBucket?> fetchPercentile(int periodDays) async {
    try {
      final result =
          await Supabase.instance.client.rpc<dynamic>('get_percentile_bucket', params: {
        'p_period_days': periodDays,
      });
      if (result == null) return null;
      final rows = result as List<dynamic>;
      if (rows.isEmpty) return null;
      final row = rows.first as Map<String, dynamic>;
      final pct = (row['percentile'] as num?)?.toInt();
      final total = (row['total_participants'] as num?)?.toInt();
      if (pct == null || total == null) return null;
      // 0061: iki ek sütun. Fark SUNUCUNUN kendi sayılarından alınır —
      // istemcinin ayrıca hesapladığı ROI, yuvarlama/zamanlama yüzünden
      // sunucudaki snapshot'tan ayrışabilir.
      final medyan = (row['median_roi_pct'] as num?)?.toDouble();
      final benim = (row['my_roi_pct'] as num?)?.toDouble();
      return (
        percentile: pct,
        total: total,
        medianDiffPts: medyan == null || benim == null ? null : benim - medyan,
      );
    } catch (_) {
      return null;
    }
  }

  /// Zirve havuzunda kaç portföy var (0083 `zirve_havuz_boyutu`).
  ///
  /// Zirve havuzu beyana dayanmaz: portföyü 5 günden, hesabı 7 günden eski
  /// herkes anonim olarak içindedir. Yarış'ın [fetchPoolSize]'ından AYRI —
  /// o yalnız yarışa katılanları sayar ve Yarış ekranı onu kullanmaya
  /// devam eder. Hata → null; UI sayı yazmaz (uydurma sayı yok).
  Future<int?> fetchZirveHavuzBoyutu({int periodDays = 30}) async {
    try {
      final r = await Supabase.instance.client.rpc<dynamic>(
        'zirve_havuz_boyutu',
        params: {'p_period_days': periodDays},
      );
      return (r as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Çağıranın havuzdaki kendi getirisi/dağılımı; havuzda değilse (ya da
  /// hata) null — ekran istemci hesabına düşer.
  Future<ZirveBenim?> fetchZirveBenim({required int periodDays}) async {
    try {
      final res = await Supabase.instance.client.rpc<dynamic>(
        'zirve_benim',
        params: {'p_period_days': periodDays},
      );
      if (res is! List || res.isEmpty) return null;
      final row = res.first as Map<String, dynamic>;
      final roi = (row['roi_pct'] as num?)?.toDouble();
      final alloc = row['allocation_pct'];
      if (roi == null || alloc is! Map) return null;
      final fon = row['fon_detay'];
      return (
        roiPct: roi,
        allocation: {
          for (final e in alloc.entries)
            e.key as String: (e.value as num).toDouble(),
        },
        fonDetay: fon is Map
            ? {
                for (final e in fon.entries)
                  e.key as String: (e.value as num).toDouble(),
              }
            : const <String, double>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Zirvedeki Portföyler açık rıza metninin sürümü (0091). Metin
  /// (`ZirveRizaKarti`) anlamca değişirse bu da değişir; sunucu hangi
  /// sürüme rıza verildiğini saklar (ispat yükü veri sorumlusunda).
  static const zirveRizaMetniSurumu = '2026-10-01';

  /// Çağıranın geçerli zirve rızası var mı (0091 `zirve_rizalari`, RLS: yalnız
  /// kendi satırı)? Hata → null; ekran "bilinmiyor" der, rıza varsaymaz.
  Future<bool?> fetchZirveRizasi() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return null;
      final rows = await Supabase.instance.client
          .from('zirve_rizalari')
          .select('geri_cekildi_at')
          .eq('user_id', uid);
      if (rows.isEmpty) return false;
      return rows.first['geri_cekildi_at'] == null;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'zirve_rizasi_okunamadi');
      return null;
    }
  }

  /// Rıza ver ([ver] true) ya da geri çek. Geri çekme sunucuda ölçümleri
  /// aynı işlemde siler (0091 `zirve_rizasi_ayarla`). Hata çağırana
  /// fırlatılır — ekran `friendlyError` ile gösterir, durum değişmemiş sayılır.
  Future<void> setZirveRizasi(bool ver) async {
    await Supabase.instance.client.rpc<dynamic>(
      'zirve_rizasi_ayarla',
      params: {'p_ver': ver, 'p_metin_surumu': zirveRizaMetniSurumu},
    );
  }

  /// k-anonimlik eşiği — `get_percentile_bucket` / `get_top_gainers`
  /// (migration 0031, `k_min`). Sunucudaki sayı değişirse burası da.
  static const kMinKatilimci = 8;

  /// Yarış havuzunda kaç kişi var (son 24 saatte 30 günlük ROI yazan tekil
  /// kullanıcı; migration 0067 `leaderboard_pool_size`).
  ///
  /// Eşik dolmadan "Yakında" demek özelliği ölü gösteriyordu; sayı
  /// "3 kişi katıldı, 8'de açılır" diyebilmek için. Hata → null, UI sayı
  /// yazmaz (uydurma sayı yok).
  Future<int?> fetchPoolSize() async {
    try {
      final r = await Supabase.instance.client.rpc<dynamic>('leaderboard_pool_size');
      return (r as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }
}
