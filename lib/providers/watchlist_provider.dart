import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/watchlist_item.dart';
import '../services/history_service.dart';
import '../services/supabase_service.dart';
import '../widgets/watchlist_chart.dart' show WatchlistChart;
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';

/// Free tier takip limiti aşıldı.
///
/// Ayrı bir tip: çağıran taraf bunu ağ hatasından AYIRT edebilmeli. Genel bir
/// `Exception` fırlatmak, ekleme ekranında "bağlantını kontrol et" gibi yanlış
/// bir mesaj gösterilmesine yol açardı.
class WatchlistLimitException implements Exception {
  final int limit;
  const WatchlistLimitException(this.limit);

  @override
  String toString() =>
      'Ücretsiz planda en fazla $limit varlık takip edilebilir.';
}

/// Güvenlik ağı: seride kalan baştaki sıfırları atar.
///
/// Kıyas çizgisi `simulate: true` ile üretilir (bkz. `watchlistChartProvider`),
/// yani `addedDate` yok sayılır ve sıfır slot BEKLENMEZ. Yine de bir sembolün
/// fiyat geçmişi hiç gelmezse `_flatFallback` 0 üretebiliyor; o durumda seri
/// yüzdeye çevrilirken bozulur:
///   · dönem başı 0 ise `normalizeSeries` **null** döner → çizgi hiç çizilmez,
///   · aradaki 0 seriyi **−%100'e** çakıp geri çıkarır → dikey uçurum.
///
/// **Yalnızca BAŞTAKİ sıfırlar atılır.** Ortadaki bir sıfır gerçek bir olay
/// olabilir (tüm varlıklar satıldı); onu atmak grafiği yalan söyletirdi.
Map<int, double> portfoyunVarOlduguSlotlar(Map<int, double> raw) {
  if (raw.isEmpty) return raw;
  final ts = raw.keys.toList()..sort();

  // Sıfırdan büyük İLK slotu bul.
  var basla = -1;
  for (var i = 0; i < ts.length; i++) {
    if (raw[ts[i]]! > 0) {
      basla = i;
      break;
    }
  }
  // Hiç pozitif değer yok — çizilecek bir şey yok.
  if (basla < 0) return const {};

  return {
    for (var i = basla; i < ts.length; i++) ts[i]: raw[ts[i]]!,
  };
}

/// Grafikteki TÜM serileri ORTAK bir zaman penceresine hizalar.
///
/// ## Neden gerekli
/// `clipToPeriod` her seriyi kendi SON veri noktasına çapalar. Bu tek bir
/// seri için doğru (hafta sonu son seansı korur) ama aynı grafikteki farklı
/// varlıklar için pencereleri AYIRIR:
///   · USDTRY=X 7/24 tikler → penceresi "şimdi"de biter,
///   · bir BIST hissesi seans kapanışında durur → penceresi 18:00'de biter,
///   · portföy ızgarası son iş gününe çapalanır.
///
/// Ölçüldü: GÜNLÜK sekmesinde üç seri birleşince eksen **54 saate** çıkıyor
/// ve BIST hissesi grafiğin solundan **12 saat sonra** başlıyordu — kullanıcı
/// ekran görüntüsündeki "başlangıç ve bitiş alanları sorunlu" bulgusu buydu.
/// Karşılaştır ekranında sorun görünmüyor çünkü orada dönemler ≥ 1 hafta ve
/// tek günlük çapa farkı 30 günlük bir eksende göze çarpmıyor.
///
/// ## Kural
/// Pencerenin SONU, serilerin son noktalarının **en ERKENİ**dir; başı
/// `son − periodDays`. Her seri bu pencereye kırpılır.
///
/// **Neden en geç değil (ölçüldü):** hafta sonu USDTRY=X tiklemeye devam
/// ederken BIST hissesi Cuma 18:00'de durur. Pencere en GEÇ noktaya
/// çapalanırsa 24 saatlik pencere Cumartesi'ye kayar ve hisse ile portföy
/// serisi pencereye HİÇ düşmez — grafikte tek çizgi kalırdı. Seri kaybetmek,
/// düzeltmeye çalıştığımız hizasızlıktan daha kötü.
///
/// En erken sona çapalamak en fazla bir seansın en güncel ucunu kırpar ama
/// TÜM serileri aynı pencerede, kesintisiz tutar — grafiğin sorusu zaten
/// "aynı pencerede kim ne yaptı".
///
/// **Seriler kırpılmadan ÖNCE normalize edilmemeli**: yüzde tabanı serinin
/// ilk noktasıdır, o nokta pencere dışındaysa taban da yanlış olur.
///
/// Saf fonksiyon — provider olmadan doğrudan test edilir.
Map<String, Map<int, double>> ortakPencereyeHizala(
  Map<String, Map<int, double>> seriler,
  int periodDays,
) {
  final doluOlanlar = {
    for (final e in seriler.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
  if (doluOlanlar.isEmpty) return const {};

  int sonNoktasi(Map<int, double> s) => s.keys.reduce((a, b) => a > b ? a : b);

  // En ERKEN son nokta — gerekçe yukarıda.
  var son = sonNoktasi(doluOlanlar.values.first);
  for (final s in doluOlanlar.values) {
    final k = sonNoktasi(s);
    if (k < son) son = k;
  }
  final bas = son - Duration(days: periodDays).inMilliseconds;

  final out = <String, Map<int, double>>{};
  for (final e in doluOlanlar.entries) {
    // Pencerenin İKİ ucu da kapatılır. Yalnızca başı kırpmak yetmez: daha
    // uzun tiklemeye devam eden bir seri ekseni sağa doğru genişletir ve
    // hizasızlık öteki uçta geri gelirdi.
    final kirpili = <int, double>{
      for (final p in e.value.entries)
        if (p.key >= bas && p.key <= son) p.key: p.value,
    };
    // İki noktadan azı çizilemez (`normalizeSeries` null döner); pencereye
    // hiç düşmeyen seriyi de taşımanın anlamı yok.
    if (kirpili.length >= 2) out[e.key] = kirpili;
  }
  return out;
}

/// Kıyas çizgisine hangi varlıklar girer?
///
/// `ModernTabSelector` sözleşmesi:
///   · `''`   → yalnızca ben
///   · uuid   → yalnızca o ortak
///   · `null` → Birlikte (ben + tüm aktif ortaklar)
///
/// **Pasif ortaklık dışlanır.** `partnerAssets` haritasında pasifleşmiş bir
/// ortağın verisi hâlâ duruyor olabilir; kıyasa yalnızca [activePartnerIds]
/// içindekiler girer.
///
/// "Birlikte" bir POZİSYON aggregate'i DEĞİLDİR: burada üretilen şey tek bir
/// toplam-değer zaman serisidir. `aggregatePositions`'ın sahiplik sınırı
/// kuralı (iki kişinin aynı hissesi tek havuzda toplanmaz) pozisyon bazlı
/// kâr/zarar içindir; "birlikte toplamda ne oldu" sorusunun cevabı lot'ların
/// toplamıdır.
///
/// Saf fonksiyon — provider olmadan doğrudan test edilir.
List<Asset> kiyasVarliklari({
  required String? view,
  required List<Asset> myAssets,
  required Map<String, List<Asset>> partnerAssets,
  required Set<String> activePartnerIds,
}) {
  List<Asset> aktif(String id) => activePartnerIds.contains(id)
      ? (partnerAssets[id] ?? const [])
      : const [];

  if (view == '') return myAssets;
  if (view != null) return aktif(view);
  return <Asset>[
    ...myAssets,
    for (final id in activePartnerIds) ...aktif(id),
  ];
}

/// Bu ekleme limite takılır mı?
///
/// Saf fonksiyon — provider/ağ/state olmadan doğrudan test edilir. Kararın
/// kendisi buradadır; `add` yalnızca uygular. Kuralı kaynak metninden değil
/// DAVRANIŞINDAN doğrulayabilmek için ayrıldı.
///
/// Kurallar:
///  · `limit` pratik sonsuzsa (paywall kapalı / premium) asla engelleme,
///  · zaten takipteki varlığı yeniden eklemek kotayı ARTIRMAZ — sunucudaki
///    unique index onu zaten reddeder, kotadan da saymamak gerekir,
///  · aksi halde mevcut sayı limite ulaştıysa engelle.
bool watchlistLimitiAsiliyorMu({
  required int mevcutSayi,
  required bool zatenTakipte,
  required int limit,
}) {
  if (limit >= (1 << 30)) return false;
  if (zatenTakipte) return false;
  return mevcutSayi >= limit;
}

/// Takip listesi dönem seçenekleri.
///
/// `portfolio_performance_screen.dart`'taki `_periods` ile AYNI küme —
/// kullanıcı iki ekranda farklı periyotlar öğrenmesin. Oradaki `intraday`
/// bayrağı burada `days: 1`'e karşılık gelir: takip listesi gün içi 5 dakikalık
/// grid çizmez, yalnızca "bugün ne oldu" yüzdesini gösterir.
const watchlistPeriods = <({String label, int days})>[
  (label: 'GÜNLÜK', days: 1),
  (label: '1H', days: 7),
  (label: '1A', days: 30),
  (label: '6A', days: 180),
  (label: '1Y', days: 365),
];

/// Seçili dönem indeksi. Varsayılan 1A — ne çok gürültülü ne çok durgun.
final watchlistPeriodProvider = StateProvider<int>((ref) => 2);

/// Grafikteki portföy çizgisinin KİMİ gösterdiği.
///
/// Uygulamanın geri kalanıyla AYNI sözleşme (`_view`, `ModernTabSelector`):
///   · `null` → Birlikte (ben + tüm aktif ortaklar)
///   · `''`   → yalnızca ben
///   · uuid   → yalnızca o ortak
///
/// Varsayılan `''` (Ben): kullanıcının ilk merak ettiği kıyas kendi
/// portföyüdür. "Birlikte" bilinçli bir seçim olmalı, varsayılan değil —
/// aksi halde tek başına yatırım yapan bir kullanıcı, ortağının verisini
/// istemeden kıyas çizgisi sanırdı.
final watchlistCompareViewProvider = StateProvider<String?>((ref) => '');

/// Grafikte odaklanılan serinin anahtarı — `null` ise odak yok.
///
/// Odak bir FİLTRE DEĞİLDİR: diğer seriler grafikten kaldırılmaz, soluklaşır.
/// Kaldırmak kıyası yok ederdi; "bu varlık iyi mi gidiyor" sorusunun cevabı
/// ancak diğerleri görünürken vardır.
final watchlistFocusProvider = StateProvider<String?>((ref) => null);

/// Takip listesi.
///
/// **Değişmez:** Bu provider'ın döndürdüğü hiçbir şey portföy toplamına,
/// kâr/zarara, tür dökümüne veya grafik serisine girmez. `watchlist` tablosu
/// `assets`'ten ayrıdır (bkz. `0043_watchlist.sql`) ve portföy tarafındaki
/// hiçbir provider bunu okumaz.
class WatchlistNotifier extends AsyncNotifier<List<WatchlistItem>> {
  @override
  Future<List<WatchlistItem>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];

    // Dönem değişince fiyatlar yeniden hesaplanmalı — provider'ı izliyoruz.
    final periodIdx = ref.watch(watchlistPeriodProvider);

    try {
      final items =
          await SupabaseService.instance.fetchWatchlist(userId: user.id);
      if (items.isEmpty) return const [];
      // `await` ZORUNLU: await olmadan döndürülen future'ın hatası aşağıdaki
      // `catch`'e DÜŞMEZ. O durumda provider hata durumuna geçer ve takip
      // listesi, boş liste yerine hata ekranı gösterirdi — koruma yazıldığı
      // gibi çalışmıyordu.
      return await _withPrices(items, watchlistPeriods[periodIdx].days);
    } catch (_) {
      return const [];
    }
  }

  /// Her varlık için güncel fiyat + seçili dönemin değişimi.
  ///
  /// Tek kaynak: `getSymbolHistory`. Serinin SON noktası güncel fiyat, İLK
  /// noktası dönem başı — ayrı bir "canlı fiyat" çağrısı yapılmaz. İki ayrı
  /// kaynak kullanmak bu projede tekrar eden bir hata sınıfıdır (üst kart ile
  /// tür dökümünün ayrışması); aynı tuzağa burada düşülmüyor.
  Future<List<WatchlistItem>> _withPrices(
      List<WatchlistItem> items, int periodDays) async {
    // Semboller paralel çekilir; `HistoryService` zaten sembol başına
    // önbelleklidir, yani aynı sembolü izleyen iki satır tek istek eder.
    final futures = items.map((item) async {
      try {
        final map = await HistoryService.instance
            .getSymbolHistory(item.ticker, periodDays: periodDays);
        if (map.length < 2) return item;
        final ts = map.keys.toList()..sort();
        final first = map[ts.first]!;
        final last = map[ts.last]!;
        return item.copyWith(
          currentPrice: last,
          // (son − ilk) / ilk — ekranın geri kalanıyla aynı formül.
          periodChangePct: first > 0 ? ((last - first) / first) * 100 : null,
        );
      } catch (_) {
        // Fiyatı çekilemeyen varlık listeden DÜŞMEZ; fiyatsız görünür.
        // Silmek kullanıcının eklediği kaydı kaybetmek olurdu.
        return item;
      }
    });
    final withPrices = await Future.wait(futures);

    // Seçili dönemin değişimine göre azalan. Fiyatsızlar dibe iner.
    withPrices.sort((a, b) =>
        (b.periodChangePct ?? -999).compareTo(a.periodChangePct ?? -999));
    return withPrices;
  }

  /// Takibe alır. Zaten takiptaki varlık için hata fırlatır (sunucudaki
  /// unique index) — çağıran bunu kullanıcıya gösterir.
  ///
  /// İyimser güncelleme YAPILMAZ: eklenen satırın `id`'si sunucuda üretiliyor
  /// ve fiyatı henüz bilinmiyor. Sunucu yanıtından sonra listeyi tazelemek
  /// hem daha basit hem de yanlış veri göstermiyor.
  Future<void> add(WatchlistItem item) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    // Limit UI'da DEĞİL burada uygulanır: ekleme ekranı tek giriş noktası
    // olmayabilir (ileride derin bağlantı, "portföyden takibe al" akışı).
    // Kural tek yerde durursa baypas edilemez — `portfolio_provider`'daki
    // varlık limiti de aynı gerekçeyle notifier içinde.
    final limit = ref.read(watchlistLimitProvider);
    final mevcut = state.valueOrNull ?? const [];
    if (watchlistLimitiAsiliyorMu(
      mevcutSayi: mevcut.length,
      zatenTakipte: mevcut.any((w) => w.key == item.key),
      limit: limit,
    )) {
      throw WatchlistLimitException(limit);
    }

    await SupabaseService.instance.addToWatchlist(item);
    ref.invalidateSelf();
    await future;
  }

  /// Takipten çıkarır — iyimser güncelleme + başarısızlıkta geri alma.
  ///
  /// Bildirim silme tarafındaki sözleşmenin aynısı: satır önce ekrandan düşer,
  /// sunucu reddederse GERİ GELİR ve hata fırlatılır. Sessiz başarısızlık
  /// kullanıcıya sildiğini sandırır (bkz. `SignalNotifier.dismiss`).
  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? const [];
    state = AsyncData(current.where((w) => w.id != id).toList());
    try {
      await SupabaseService.instance.removeFromWatchlist(id);
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Bu varlık zaten takipte mi? Ekleme ekranında çift kayıt önlemek için.
  bool contains(String key) =>
      (state.valueOrNull ?? const []).any((w) => w.key == key);
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistNotifier, List<WatchlistItem>>(
  WatchlistNotifier.new,
);

/// Takip listesindeki varlık sayısı — Portföy ekranındaki
/// `Varlıklarım | Takip Listesi` sekmesinin rozeti için.
///
/// Sekme, altındaki içerik görünmezken ne olduğunu söylemeli: boş bir
/// listeyle dolu bir liste arasındaki fark, dokunmaya değip değmeyeceğini
/// söyler.
final watchlistCountProvider = Provider<int>((ref) {
  return (ref.watch(watchlistProvider).valueOrNull ?? const []).length;
});

/// Grafiğin serileri: her takip varlığı + kullanıcının portföyü.
///
/// ## Yön tek taraflıdır
/// Bu provider portföy varlıklarını OKUR ama takip listesini portföye
/// YAZMAZ. Ürettiği şey yalnızca çizim verisidir (`{etiket: yüzde serisi}`);
/// hiçbir toplama, kâr/zarara veya tür dökümüne girmez. Değişmez korunuyor:
/// takip edilen varlık portföy hesabına girmez — burada portföy, takip
/// listesinin YANINDA bir kıyas çizgisi olarak duruyor.
///
/// ## Neden yüzde
/// `comparison_screen` ile aynı motor (`normalizeSeries`): dönem başı %0.
/// Farklı fiyat ölçekleri ancak böyle aynı eksende anlamlı görünür.
final watchlistChartProvider =
    FutureProvider<Map<String, NormalizedSeries>>((ref) async {
  final items = ref.watch(watchlistProvider).valueOrNull ?? const [];
  final periodIdx = ref.watch(watchlistPeriodProvider);
  final days = watchlistPeriods[periodIdx].days;

  // HAM seriler önce toplanır, normalize SONRA yapılır: yüzde tabanı serinin
  // ilk noktasıdır ve ortak pencereye kırpma o noktayı değiştirir. Önce
  // normalize etmek her seriyi kendi penceresinin başına göre ölçerdi.
  final ham = <String, Map<int, double>>{};

  // ── Takip edilen varlıklar ────────────────────────────────────────────────
  // Paralel çekilir; `HistoryService` sembol başına önbelleklidir.
  final futures = items.map((item) async {
    try {
      final raw = await HistoryService.instance
          .getSymbolHistory(item.ticker, periodDays: days);
      return (label: item.chartLabel, raw: raw);
    } catch (_) {
      // Tek bir sembolün düşmesi grafiğin tamamını götürmemeli.
      return (label: item.chartLabel, raw: const <int, double>{});
    }
  });
  for (final r in await Future.wait(futures)) {
    if (r.raw.isNotEmpty) ham[r.label] = r.raw;
  }

  // ── Portföy (kendi + ortaklar) ────────────────────────────────────────────
  // Kıyas noktası: "izlediklerim benim portföyümden iyi mi gidiyor?"
  //
  // Ortakların lot'ları kendi listelerinde AYRI durur ama buradaki soru
  // "birlikte ne kadar kazandık" olduğu için hepsi tek seriye girer. Bu bir
  // AGGREGATE DEĞİL, tek bir zaman serisidir — `aggregatePositions`'ın
  // sahiplik sınırı kuralı (ortak lot'ları havuzlanmaz) pozisyon bazlı
  // kâr/zarar için geçerlidir; toplam portföy değeri eğrisi için değil.
  try {
    final all = kiyasVarliklari(
      view: ref.watch(watchlistCompareViewProvider),
      myAssets:
          ref.watch(portfolioProvider).valueOrNull?.activeAssets ?? const [],
      partnerAssets:
          ref.watch(allPartnerAssetsProvider).valueOrNull ?? const {},
      activePartnerIds:
          ref.watch(activePartnersProvider).map((p) => p.id).toSet(),
    );

    if (all.isNotEmpty) {
      // `simulate: true` — alım tarihleri YOK SAYILIR: bugünkü net pozisyon
      // dönemin tamamı boyunca elde tutulmuş kabul edilir. Performans
      // ekranındaki "simülasyon" sekmesiyle AYNI bayrak, aynı anlam.
      //
      // ## Neden gerçek geçmiş değil
      // Gerçek modda `addedDate`'ten önceki slotlara 0 yazılır ve kıyas
      // çizgisi bozulur: dönem başı 0 ise seri çizilemez, aradaki 0 ise
      // −%100'e çakılır (ölçüldü: 30 günlük dönem + 10 gün önce alınan
      // varlık → 31 noktanın 20'si sıfır).
      //
      // Daha önemlisi: KIYAS ADALETİ. İzlenen varlıklar dönemin tamamı
      // boyunca çiziliyor. Portföyü yalnızca sahip olunan günlerde çizmek
      // iki tarafı farklı pencerelerde ölçmek olurdu — "izlediklerim
      // portföyümden iyi mi gidiyor" sorusu ancak aynı pencerede anlamlı.
      //
      // Bunun bir yorumu var ve kullanıcıya AÇIKÇA söylenmeli (grafik
      // altındaki not): bu çizgi "bu varlıkları dönem başından beri
      // tutsaydım" senaryosudur, gerçekleşmiş getirin değildir.
      final raw = await HistoryService.instance
          .getPortfolioHistory(all, days, simulate: true);
      final temiz = portfoyunVarOlduguSlotlar(raw);
      if (temiz.isNotEmpty) ham[WatchlistChart.portfolioSeriesKey] = temiz;
    }
  } catch (e) {
    // Portföy serisi çizilemezse grafik takip varlıklarıyla DEVAM eder —
    // kıyas çizgisinin düşmesi listeyi kullanılmaz yapmamalı. Sebep yine de
    // yutulmaz: sessiz başarısızlık bu projede tekrar eden tuzak.
    if (kDebugMode) debugPrint('[watchlist-chart] portföy serisi yok: $e');
  }

  // Tüm seriler ORTAK pencereye hizalanır, normalize SONRA yapılır. Sıra
  // önemli: her seri kendi penceresinde normalize edilseydi yüzde tabanları
  // farklı anlara denk gelir ve kıyas anlamsızlaşırdı.
  final out = <String, NormalizedSeries>{};
  for (final e in ortakPencereyeHizala(ham, days).entries) {
    final norm = normalizeSeries(e.value);
    if (norm != null) out[e.key] = norm;
  }
  return out;
});

/// Grafikte ve açıklamada kullanılan kısa etiket.
///
/// `TEFAS:AFO` → `AFO`, `AGHOL.IS` → `AGHOL` — kaynak önekleri kullanıcıya
/// hiçbir şey ifade etmez. `watchlist_screen`'deki `displayLabel` ile aynı
/// kural; grafik ile liste aynı adı göstermeli.
extension WatchlistChartLabel on WatchlistItem {
  String get chartLabel {
    final t = ticker.trim();
    if (t.isNotEmpty) {
      final sade =
          t.contains(':') ? t.split(':').last : t.replaceAll('.IS', '');
      if (sade.length >= 2) return sade;
    }
    final sub = subCategory?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    return name;
  }
}
