import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/tefas_nav_gozlem.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'fiyat_kaynagi.dart';
import 'price_service.dart';
import 'supabase_service.dart';
import '../utils/tr_format.dart';

// Fiyat kaynağı sözleşmesi (`fiyat_kaynagi.dart`) bu kütüphaneden de
// görünür: altın merdiveni ve ölçek kalibrasyonu buradan TAŞINDI, çağıran
// ekranların ve testlerin import'u değişmesin diye yeniden yayımlanıyor.
// Yeni kod doğrudan `fiyat_kaynagi.dart`'ı import etmelidir.
export 'fiyat_kaynagi.dart';

/// Grafik çözünürlük seviyeleri. Zoom yaptıkça daha ince tier'a düşer.
///
/// **Bu enum YALNIZCA ÇİZİM çözünürlüğüdür.** Sinyal üretimi buradan
/// beslenmez ve beslenmemelidir: `TechnicalAnalysisService` bar SAYISI ile
/// çalışır (`RSI(14)` = son 14 bar) ve barın ne kadar sürdüğünü BİLMEZ.
/// Aynı motoru 5 dakikalık seriye verirsen `RSI(14)` "son 70 dakika"
/// anlamına gelir, ama eşikler (`overbought = 70`) GÜNLÜK bar için kalibre
/// edilmiştir; intraday'de RSI uçlara çok daha sık değer ve motor kalibresiz
/// biçimde AL/SAT üretir. Sinyal yolu `getSymbolHistory(periodDays: 180)`
/// ile günlük bara sabittir — `test/sinyal_gunluk_bar_kilidi_test.dart`
/// bunu kilitler.
///
/// Üye listesi sektör standardıyla hizalı (TradingView/Yahoo/Investing ortak
/// çekirdeği): 1dk · 5dk · 15dk · 1sa · 1G · 1H. Adımlar kabaca 3-4×
/// logaritmik ilerler — iki komşu seçenek arasındaki fark kullanıcıya
/// GÖRÜNÜR olmalı. 10dk/20dk bilinçli olarak YOK: 5dk ile 15dk arasına
/// sıkışıyorlar, seçim yükü ekleyip bilgi eklemiyorlar (ayrıca Yahoo bu
/// interval'leri hiç vermiyor; 5dk'dan bucket'lamak gerekirdi).
enum ResolutionTier {
  oneMin, // 1 dakikalık — yalnızca bugün; Yahoo 8 GÜN geriye veriyor
  fiveMin, // 5 dakikalık — sadece bugün için (1d range)
  fifteenMin, // 15 dakikalık — son günler; Yahoo 1mo'ya kadar
  hourly, // 1 saatlik — son 5-7 gün (5d range)
  daily, // günlük close — son 30-180 gün
  weekly, // haftalık close — 1 yıl+ (uzun dönem)
}

extension ResolutionTierMeta on ResolutionTier {
  /// Yahoo API range parametresi.
  ///
  /// **Range'ler ÖLÇÜLDÜ (2026-09-13, THYAO.IS).** Yahoo dakikalık veride
  /// sert duvarlar koyuyor ve aşıldığında `Unprocessable Entity` döner:
  ///   · `1m` + `1mo` → "Only 8 days worth of 1m granularity data allowed"
  ///   · `5m` + `3mo` → reddedildi (`1mo` çalışıyor: 2342 nokta)
  ///   · `15m` + `3mo` → reddedildi (`1mo` çalışıyor: 782 nokta)
  ///   · `1h` + `2y` → çalışıyor (4582 nokta)
  /// `oneMin` için bu yüzden `5d` seçildi: Yahoo'da `8d` range'i yok, `1mo`
  /// ise duvarı aşıyor. Range dönemden GENİŞ olabilir ([clipToPeriod] kırpar),
  /// DAR olması veri kaybıdır — ama duvarı aşmak veriyi TAMAMEN kaybettirir.
  String get yahooRange => switch (this) {
        ResolutionTier.oneMin => '5d',
        ResolutionTier.fiveMin => '1d',
        ResolutionTier.fifteenMin => '1mo',
        // 1H periyot 7 gün ister — Yahoo 5d döner ve sol tarafta boşluk kalır.
        // 1mo döndür (Yahoo 1h intervalinde 1mo'ya kadar destekler).
        ResolutionTier.hourly => '1mo',
        ResolutionTier.daily => '1y',
        ResolutionTier.weekly => '5y',
      };

  /// Yahoo API interval parametresi (PriceService._intervalFor ile uyumlu)
  String get yahooInterval => switch (this) {
        ResolutionTier.oneMin => '1m',
        ResolutionTier.fiveMin => '5m',
        ResolutionTier.fifteenMin => '15m',
        ResolutionTier.hourly => '1h',
        ResolutionTier.daily => '1d',
        ResolutionTier.weekly => '1wk',
      };

  /// Seçicide görünen kısa etiket.
  String get etiket => switch (this) {
        ResolutionTier.oneMin => '1dk',
        ResolutionTier.fiveMin => '5dk',
        ResolutionTier.fifteenMin => '15dk',
        ResolutionTier.hourly => '1sa',
        ResolutionTier.daily => '1G',
        ResolutionTier.weekly => '1H',
      };

  /// Bir barın kapsadığı süre — seri önbelleğinin TTL'i buradan türer.
  ///
  /// **Kural: `ttl == bar süresi`.** Bardan daha sık tazelemek AYNI barı
  /// tekrar çekmektir: ağ harcar, ekranda hiçbir şey değişmez. Bu içgörü
  /// zaten `_intradayCacheTtl` yorumunda keşfedilmişti ("Slot çözünürlüğüyle
  /// aynı: 5 dakika"); burada tüm tier'lara genelleniyor.
  Duration get barSuresi => switch (this) {
        ResolutionTier.oneMin => const Duration(minutes: 1),
        ResolutionTier.fiveMin => const Duration(minutes: 5),
        ResolutionTier.fifteenMin => const Duration(minutes: 15),
        ResolutionTier.hourly => const Duration(hours: 1),
        ResolutionTier.daily => const Duration(days: 1),
        ResolutionTier.weekly => const Duration(days: 7),
      };

  /// Bu tier'da ts'yi hangi ölçekte normalize edelim (aynı bucket'a düşen
  /// noktalar tek değer olur).
  int normalizeTs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    switch (this) {
      case ResolutionTier.oneMin:
        return DateTime(d.year, d.month, d.day, d.hour, d.minute)
            .millisecondsSinceEpoch;
      case ResolutionTier.fiveMin:
        final snappedMin = (d.minute ~/ 5) * 5;
        return DateTime(d.year, d.month, d.day, d.hour, snappedMin)
            .millisecondsSinceEpoch;
      case ResolutionTier.fifteenMin:
        final snappedMin = (d.minute ~/ 15) * 15;
        return DateTime(d.year, d.month, d.day, d.hour, snappedMin)
            .millisecondsSinceEpoch;
      case ResolutionTier.hourly:
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      case ResolutionTier.daily:
        return dayKey(d).millisecondsSinceEpoch;
      case ResolutionTier.weekly:
        // Haftanın pazartesi 00:00'ına snap
        final wd = d.weekday; // 1..7
        final monday =
            dayKey(d).subtract(Duration(days: wd - 1));
        return monday.millisecondsSinceEpoch;
    }
  }

  /// Görünen aralığın gün cinsinden genişliğine göre optimal tier seçimi.
  /// Trading uygulamalarındaki gibi ~30-300 nokta hedefler.
  static ResolutionTier pickForSpan(double viewportDays) {
    if (viewportDays < 5) return ResolutionTier.fiveMin;
    if (viewportDays < 30) return ResolutionTier.hourly;
    if (viewportDays < 180) return ResolutionTier.daily;
    return ResolutionTier.weekly;
  }
}

/// Portföy değer serisi + aynı serinin tür ve pozisyon bazında dağılımı.
///
/// **Değişmez (iki seviyeli):** her `ts` için
///   `total[ts] == Σ byType[t]![ts]` ve
///   `byType[t]![ts] == Σ byPosition[k]![ts]` (k, türü `t` olan pozisyonlar).
/// Kayan nokta toplama hatası payı dışında birebir. Üç alan da AYNI döngüde
/// üretilir; bu yüzden tür dökümü portföy toplamını, ürün dökümü de tür
/// toplamını her zaman tutar.
/// Bkz. [HistoryService.getPortfolioHistoryBreakdownAtResolution].
class PortfolioHistoryBreakdown {
  /// ts → toplam portföy değeri (TRY).
  final Map<int, double> total;

  /// tür → (ts → o türün o slot'taki değeri, TRY).
  /// Yalnızca o slot'ta fiilen değeri olan türler bulunur.
  final Map<AssetType, Map<int, double>> byType;

  /// `positionKey` → (ts → o pozisyonun o slot'taki değeri, TRY).
  ///
  /// Anahtar `positionKey`'dir, ticker DEĞİL: altın türleri (Gram/Çeyrek/
  /// Yarım/Reşat) aynı `GC=F` serisinden türetilir ama farklı ağırlık
  /// katsayısı taşır — ticker ile gruplansaydı hepsi tek satırda toplanır ve
  /// "çeyrek mi gram mı kazandırdı" sorusu cevapsız kalırdı.
  final Map<String, Map<int, double>> byPosition;

  /// `positionKey` → o pozisyonun ait olduğu tür. Ürün satırlarını doğru
  /// başlığın altına yerleştirmek için.
  final Map<String, AssetType> positionType;

  /// Gün içi seride ÇİZİLEN günün 00:00'ı. Diğer periyotlarda `null`.
  ///
  /// Neden var: "GÜNLÜK" sekmesi her zaman BUGÜNÜ çizmez. Piyasa kapalıyken
  /// (hafta sonu, tatil, Pazartesi 10:00'dan önce) Yahoo'nun `range=1d`
  /// yanıtı SON SEANSA aittir; ızgara bugüne kurulsaydı o noktalar bugünün
  /// slotlarına yayılır ve grafik 00:00'dan şu ana kadar DÜMDÜZ bir çizgi
  /// olurdu (hafta sonu → tek fiyat, 288 slot).
  /// Bu alan, çizilen günü ekrana bildirir: X ekseni, saat etiketleri ve
  /// "şimdi" işareti o güne göre kurulur.
  final DateTime? seansGunu;

  /// Piyasanın KAPALI olduğu slotların başlangıcı (UNIX millis).
  ///
  /// Gün içi seri son seansın kapanışında bitmiyor; kapanış fiyatı BUGÜNE
  /// kadar sabit bir kuyruk olarak uzatılıyor. Böylece Pazar günü eksende
  /// Cuma–Cumartesi–Pazar görünür ve kullanıcı "grafik dünde kalmış"
  /// demez (kullanıcı isteği 2026-09-12).
  ///
  /// Bu damgadan SONRAKİ noktalar gerçek işlem değildir: son kapanışın
  /// taşınmasıdır. Ekran onları GRİ ve kesikli çizer, "piyasa kapalı"
  /// ibaresi gösterir — yoksa düz çizgi "fiyat hiç oynamadı" diye
  /// okunurdu, oysa borsa kapalıydı.
  ///
  /// `null` ise seri tümüyle canlı seanstır (hafta içi, piyasa açık).
  final int? piyasaKapaliBaslangicTs;

  /// Gün içi seride TEK BİR gerçek fiyat noktası bile alınamayan türler.
  ///
  /// Bu türlerin değeri gün boyu son bilinen fiyatla (seed) sabit çizilir —
  /// yani grafikteki düzlük piyasanın durgunluğu değil, VERİ YOKLUĞUDUR.
  /// Ayrım kullanıcıya gösterilmeden ikisi birbirinden ayırt edilemiyordu:
  /// "altın değeri mi alınamıyor acaba" sorusunun uygulamada cevabı yoktu
  /// (kullanıcı bildirimi 2026-09-07).
  ///
  /// Gün içi fiyatı OLMAYAN türler (fon → TEFAS gün içi NAV yayınlamaz,
  /// vadeli mevduat, diğer) buraya HİÇ girmez: onların sabit çizilmesi
  /// beklenen davranıştır, uyarı üretmek gürültü olurdu.
  final Set<AssetType> gunIciVerisiYokTurler;

  const PortfolioHistoryBreakdown({
    required this.total,
    required this.byType,
    required this.byPosition,
    required this.positionType,
    this.seansGunu,
    this.piyasaKapaliBaslangicTs,
    this.gunIciVerisiYokTurler = const {},
  });

  const PortfolioHistoryBreakdown.empty()
      : total = const {},
        byType = const {},
        byPosition = const {},
        positionType = const {},
        seansGunu = null,
        piyasaKapaliBaslangicTs = null,
        gunIciVerisiYokTurler = const {};
}

class HistoryService {
  /// Grafik veri çekiminin üst sınırı.
  ///
  /// Alt katmanda (`PriceService`) 15 saniyelik bir timeout var ama o
  /// SAYFA AÇILIŞINI değil tek bir HTTP çağrısını koruyor. Kullanıcı
  /// grafiği beklerken 15 saniye çok uzun: bildirim (2026-09-13) "uzun
  /// süre bekleyince geldi, kimse bu kadar uzun beklemez."
  ///
  /// 8 saniye bilinçli bir takas: normal ağda tüm çekimler 1-2 saniyede
  /// biter, yavaş ağda ise grafik boş beklemek yerine elde olanla
  /// (yedek kaynak / `currentPrice` seed'i) çizilir.
  static const _grafikCekimSuresi = Duration(seconds: 8);

  static final HistoryService instance = HistoryService._();
  HistoryService._();

  // ── TEFAS NAV gözlemi kaynağı ─────────────────────────────────────────────
  //
  // Gün içi fon basamağının çapası (bkz. `fonBasamakAni`). Statik ve
  // değiştirilebilir: testler sunucuya gitmeden sahte gözlem verir. Varsayılan
  // `SupabaseService` — tablo yoksa (0063 koşmadıysa) ya da istek düşerse boş
  // harita döner ve basamak sabit saate (`tefasNavYayinSaati`) düşer. Hata
  // yutulmaz, Crashlytics'e non-fatal gider.
  static Future<Map<String, TefasNavGozlem>> Function(
    Set<String> fonKodlari,
    DateTime gun,
  ) tefasNavGozlemKaynagi = _sunucuGozlemleri;

  static Future<Map<String, TefasNavGozlem>> _sunucuGozlemleri(
    Set<String> fonKodlari,
    DateTime gun,
  ) async {
    try {
      return await SupabaseService.instance
          .tefasNavGozlemleri(fonKodlari, gun: gun);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HistoryService.tefasNavGozlemleri');
      return const {};
    }
  }

  // Gözlem 5 dk önbellekte: gün içi seri 30 sn'de bir yeniden kuruluyor,
  // gözlem ise günde bir kez değişir. Anahtar kod kümesi — portföye fon
  // eklenince yeniden sorulur.
  Map<String, TefasNavGozlem>? _gozlemCache;
  String _gozlemCacheKey = '';
  DateTime? _gozlemCacheAt;
  static const _gozlemCacheTtl = Duration(minutes: 5);

  Future<Map<String, TefasNavGozlem>> _gozlemleriGetir(
      Set<String> fonKodlari, DateTime gun) async {
    if (fonKodlari.isEmpty) return const {};
    final key = (fonKodlari.toList()..sort()).join(',');
    final at = _gozlemCacheAt;
    if (_gozlemCache != null &&
        key == _gozlemCacheKey &&
        at != null &&
        DateTime.now().difference(at) < _gozlemCacheTtl) {
      return _gozlemCache!;
    }
    final sonuc = await tefasNavGozlemKaynagi(fonKodlari, gun);
    _gozlemCache = sonuc;
    _gozlemCacheKey = key;
    _gozlemCacheAt = DateTime.now();
    return sonuc;
  }

  /// Ticker başına fiyat serisi önbelleği.
  ///
  /// LRU + TTL: `static` olduğu için süreç ömrü boyunca yaşar. Sınırsız
  /// bırakılırsa her ticker'ın 365 günlük serisi bellekte birikir; periyotlar
  /// arasında gezinen, çok varlıklı bir portföyde onlarca MB'a çıkar.
  /// `LinkedHashMap` ekleme sırasını korur → en eski giriş ilk atılır.
  static final Map<String, List<(int, double)>> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};

  /// Aynı oturumda tekrar tekrar çekmeyi önlemeye yetecek kadar uzun,
  /// gün içi fiyat hareketini kaçırmayacak kadar kısa.
  static const _cacheTtl = Duration(minutes: 15);

  /// GÜN İÇİ (`1d`) serilerin TTL'i — daha kısa.
  ///
  /// Gün içi seri 5 dakikalık slotlardan oluşur ve ekran 30 saniyede bir
  /// tick atıp yeniden istiyor. 15 dakikalık ortak TTL bu isteklerin
  /// üçte ikisini aynı listeye bağlıyor: grafiğin GÖVDESİ çeyrek saat
  /// boyunca hiç hareket etmiyor, yalnızca son nokta canlı toplamla
  /// güncelleniyordu. "Gün içi grafik dümdüz" hissinin bir kısmı
  /// buradandı. Slot çözünürlüğüyle aynı: 5 dakika.
  static const _intradayCacheTtl = Duration(minutes: 5);
  static const _cacheMaxEntries = 50;

  /// [ttl] verilmezse [_cacheTtl] geçerlidir.
  ///
  /// Gün içi çağıranlar [_intradayCacheTtl] geçer. TTL'i anahtarın
  /// biçiminden ÇIKARMAYA çalışma: iki farklı anahtar şeması var
  /// (`SEMBOL_range` ve `SEMBOL_range_interval`) ve `THYAO.IS_1mo_1d` gibi
  /// bir GÜNLÜK anahtarı da `_1d` ile bitiyor — sonek kontrolü onu yanlışlıkla
  /// gün içi sayardı.
  static List<(int, double)>? _cacheGet(String key, {Duration? ttl}) {
    final at = _cacheAt[key];
    if (at == null) return null;
    if (DateTime.now().difference(at) > (ttl ?? _cacheTtl)) {
      _cache.remove(key);
      _cacheAt.remove(key);
      return null;
    }
    return _cache[key];
  }

  static void _cachePut(String key, List<(int, double)> value) {
    // Yeniden ekleme sırayı tazeler (LRU davranışı).
    _cache.remove(key);
    _cacheAt.remove(key);
    _cache[key] = value;
    _cacheAt[key] = DateTime.now();
    while (_cache.length > _cacheMaxEntries) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _cacheAt.remove(oldest);
    }
  }

  /// Bellek baskısında veya oturum kapanışında çağrılabilir.
  static void clearCache() {
    _cache.clear();
    _cacheAt.clear();
  }

  /// Verilen varlıkların ilgili periyot için (örn. 365 gün) geçmiş fiyatlarını
  /// gün-den-güne hesaplar. Dönen map: { UNIX_MILLIS: TOPLAM_PORTFOY_DEGERI_TRY }
  ///
  /// [simulate] true iken: her lot'un `addedDate`'i ve alım/satış geçmişi
  /// yok sayılır — tüm dönem boyunca bugünkü net miktar sabit tutulur.
  /// "Şu anki portföyüm o zaman elimde olsaydı ne olurdu?" senaryosunu
  /// çizer. Bu modda arayan `assets` olarak aggregate edilmiş (net)
  /// display-asset listesini verir; buy/sell ayrımı olmaz.
  ///
  /// DİKKAT — simülasyon "hiç satmasaydım" DEĞİLDİR. Gelen liste zaten net
  /// pozisyondur: 100 alıp 40 sattıysan simülasyon 60 adet üzerinden çizer,
  /// satılan 40 hiç var olmamış sayılır. Senaryo "bu portföyü daha erken
  /// kursaydım"dır. Bu bilinçli bir ürün kararıdır (kullanıcı onayı
  /// 2026-08-10); davranış `test/simulation_semantics_test.dart` içinde
  /// sabitlenmiştir — değiştirmeden önce o testi ve sahibini kontrol et.
  Future<Map<int, double>> getPortfolioHistory(
      List<Asset> assets, int periodDays,
      {bool simulate = false}) async {
    // Haftalık (7 gün) → saatlik veri: `5d` range + `1h` interval.
    // Diğer dönemler günlük veya haftalık.
    final bool hourly = periodDays <= 7;

    // Range dönemi KAPSAMAK zorunda: dar bir range portföy çizgisini sessizce
    // kırpar ve grafik, seçilen dönemin yalnızca sağ dilimini gösterir.
    // Eski merdivende iki delik vardı — 91-180 gün `'3mo'`e (90 gün) düşüyor,
    // 365 günün üstü de `'1y'`de kalıyordu. `getSymbolHistory` ile aynı
    // aileden hata; ikisi de kapatıldı.
    //
    // **Merdiven artık [rangeForPeriod] ile ORTAK.** Burada ayrı bir kopya
    // duruyordu ve `getSymbolHistory`'ninkiyle ayrışmıştı: GÜNLÜK'te sembol
    // `'1d'` çekerken portföy `'5d'`, 1H'de sembol `'1mo'` çekerken portföy
    // yine `'5d'` çekiyordu. Aynı grafikte iki seri iki farklı pencereden
    // geliyordu (ölçüldü: GÜNLÜK'te 96 saatlik kayma). İki kopya tutmak bu
    // projede tekrar eden hata sınıfı; tek kaynağa indirildi.
    final range = rangeForPeriod(periodDays);
    // Testler bu değeri ağa çıkmadan denetler — `range` yerel bir değişken
    // olduğu sürece merdivenin yeniden ayrışması hiçbir testle yakalanamıyordu
    // (sabotaj denendi, tüm testler geçti).
    debugSonKullanilanRange = range;

    // Haftalık'ta saat başına, diğerlerinde gece yarısına normalize.
    int normalizeTs(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (hourly) {
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      }
      return dayKey(d).millisecondsSinceEpoch;
    }

    final groupedPoints = <int, double>{};
    final now = DateTime.now();

    // Her bir varlık için günlük fiyat eşleşmesi tutalım donmuş/gerçek fiyatlar
    final Map<String, Map<int, double>> tickerNormalizedDaily = {};

    final Map<int, double> usdTryHistory = {};
    final Map<int, double> goldHistory = {};

    final bool needsGold = assets.any((a) => a.type == AssetType.altin);
    final bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    Future<List<(int, double)>> getHistorySafe(String sym) async {
      final cacheKey = '${sym}_$range';
      final cached = _cacheGet(cacheKey);
      if (cached != null) return cached;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, range);
        if (pts.isNotEmpty) _cachePut(cacheKey, pts);
        return pts;
      } catch (e) {
        return [];
      }
    }

    // -- Ağ çağrıları --
    //
    // Tüm semboller TEK SEFERDE başlatılır. Eskiden USD → altın → her ticker
    // sırayla `await` ediliyordu: 15 varlıklı bir portföyde 15 gidiş-dönüş
    // ardışık toplanıyor ve grafik ekranı saniyelerce spinner gösteriyordu.
    // İstekler birbirinden bağımsız olduğu için paralel başlatılabilir;
    // toplam süre en yavaş tek isteğe iner. (`getHistorySafe` zaten kendi
    // içinde hata yutar, bu yüzden `Future.wait` bir sembol patlasa da
    // diğerlerini düşürmez.)
    //
    // Not: altın hesabı USD serisine bağımlı — ikisi paralel ÇEKİLİR ama
    // dönüşüm her ikisi de geldikten sonra yapılır (sıra korunur).
    final usdFuture = needsUsd
        ? getHistorySafe(FiyatKaynagi.usdTry)
        : Future.value(const <(int, double)>[]);
    // Altın: spot (`XAUTRY=X`) ÖNCE, vadeli (`GC=F`) yedek — merdiven
    // `altinGramSerisi`'nde. İkisi de burada PARALEL başlar; eskiden bu yol
    // yalnızca `GC=F` çekiyordu, yani gün içi tabı spot ölçeğindeyken 1H/1A/
    // 6A/1Y tabları kalıcı olarak vadeli (primli) ölçekteydi.
    final goldTryFuture = needsGold
        ? getHistorySafe(FiyatKaynagi.xauTry)
        : Future.value(const <(int, double)>[]);
    final goldFuture = needsGold
        ? getHistorySafe(FiyatKaynagi.xauUsd)
        : Future.value(const <(int, double)>[]);

    // Çekilecek benzersiz ticker'ları önce topla — aynı ticker'ın birden çok
    // lot'u varsa tek istek yapılsın.
    final tickerFutures = <String, Future<List<(int, double)>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (!fetchable) continue;
      tickerFutures.putIfAbsent(a.ticker, () => getHistorySafe(a.ticker));
    }

    if (needsUsd) {
      final usdPoints = await usdFuture;
      for (final p in usdPoints) {
        usdTryHistory[normalizeTs(p.$1)] = p.$2;
      }
      // Kur serisi CANLI kura hizalanır — tek kur gerçeği
      // (bkz. `kurSerisiniHizala`).
      final hizali = kurSerisiniHizala(usdTryHistory, canliKur());
      if (!identical(hizali, usdTryHistory)) {
        usdTryHistory
          ..clear()
          ..addAll(hizali);
      }
    }

    if (needsGold) {
      final xauTryPoints = await goldTryFuture;
      final xauUsdPoints = await goldFuture;
      final sonuc = altinGramSerisi(
        xauTry: {for (final p in xauTryPoints) normalizeTs(p.$1): p.$2},
        xauUsd: {for (final p in xauUsdPoints) normalizeTs(p.$1): p.$2},
        usdTry: usdTryHistory,
        // Burada eskiden `usdRate = 35.0` varsayılanı vardı: kur serisi boş
        // dönünce (Yahoo düşer/429 verir) TÜM altın günleri uydurma bir kurla
        // fiyatlanıyor ve seri sessizce ~%17 aşağı kayıyordu. Artık kuru
        // bulunamayan nokta seriye hiç girmez.
        kurBul: (kur, ts) => _closestOrNull(kur, ts),
      );
      goldHistory.addAll(sonuc.seri);
      debugSonAltinKaynagi = sonuc.kaynak;
    }

    // Altın serisi CANLI ölçeğe kalibre edilir — gerekçe `altinKalibrasyonu`
    // dokümantasyonunda. Bu yolda da son nokta `liveTotal` ile eziliyor,
    // yani kalibrasyon olmadan sağ uçta aynı yapay basamak oluşur.
    final altinKalibre =
        altinKalibrasyonHaritasi(assets: assets, gramSerisi: goldHistory);

    // Hisse, Emtia, Döviz ve TEFAS Fon API Verileri.
    // Fiyat serileri yukarıda zaten paralel başlatıldı (sadece BUY lot'ları,
    // ticker başına tek istek) — burada yalnızca sonuçlar toplanır.
    for (final entry in tickerFutures.entries) {
      final rawPts = await entry.value;
      final map = <int, double>{};
      for (final p in rawPts) {
        map[normalizeTs(p.$1)] = p.$2;
      }
      tickerNormalizedDaily[entry.key] = map;
    }

    // Her lot için "o gün geçerli miktar":
    // - simulate=true: addedDate yok sayılır, quantity tüm dönem boyunca
    //   sabit → "şu anki portföyümü geçmişte tutsaydım" senaryosu.
    // - simulate=false (gerçek):
    //   * Buy lot: addedDate <= dayTs ise +quantity, aksi 0.
    //   * Sell lot: addedDate <= dayTs ise -quantity.
    //   * deleteLog: skip.
    double signedQtyOnDay(Asset a, int dayTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      // Simülasyonda arayan NET (aggregate) liste verir, yani sell lot
      // beklenmez. Yine de işaret korunur: kardeş fonksiyon
      // `getPortfolioHistoryAtResolution.signedQtyOnSlot` bunu zaten
      // yapıyordu ve iki kopyanın ayrışması bu projede yaşanmış bir hata
      // sınıfıdır. Ham lot listesi yanlışlıkla verilirse satılan miktar
      // burada EKLENİR ve portföy olduğundan büyük görünürdü.
      if (simulate) return a.isSell ? -a.quantity : a.quantity;
      final addedTs = normalizeTs(a.addedDate.millisecondsSinceEpoch);
      if (addedTs > dayTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // -- Toparlama ve Hizalama --
    // Haftalık'ta saat başına, diğerlerinde gün başına grid oluştur.
    //
    // **Grid `now`'a değil son İŞ GÜNÜNE çapalanır.** Saatlik grid hafta sonu
    // slotlarını atlar (aşağıdaki `weekday` kontrolü); pencere `now`'dan
    // geriye sayınca Pazar günü "GÜNLÜK" seçildiğinde 24 slotun tamamı Cts/Paz
    // oluyor ve portföy çizgisi TAMAMEN kayboluyordu (ölçüldü: Pazar → 0 slot,
    // Cumartesi → 9 slot). Aynı anda takip varlıkları Cuma seansını
    // gösteriyordu, çünkü `clipToPeriod` son VERİ noktasına çapalanır.
    // İki seri aynı grafikte farklı pencerelerden geliyordu.
    //
    // Çapayı son iş gününe almak `clipToPeriod`'un hafta sonu kuralıyla aynı
    // anlamı verir: "son bir günlük hareket" = son seans.
    for (final dayTs in gridSlotlari(
      now: now,
      periodDays: periodDays,
      hourly: hourly,
    )) {
      double dayTotalValue = 0.0;

      for (final a in assets) {
        try {
          final qty = signedQtyOnDay(a, dayTs);
          if (qty == 0) continue;

          double assetDayVal = 0.0;

          if (a.type == AssetType.altin) {
            if (goldHistory.isNotEmpty) {
              // Ağırlık tablosu `PriceService`'te tutulur. Burada duran yerel
              // kopya ALTIN_RESAT'ı ATLIYORDU (tabloda 7.216 ile var ama
              // koşul zincirinde yoktu) ve `?? 1.0` sessizce gram altına
              // düşürüyordu. Kardeş iki yol (`...HourlyBreakdown`,
              // `...BreakdownAtResolution`) aynı hatadan ötürü zaten ortak
              // tabloya taşınmıştı; ÜÇÜNCÜ kopya olan burası geride kalmıştı.
              //
              // Sonucu ölçülmüş iki belirtiydi (kullanıcı bildirimi
              // 2026-09-12, "altının datası grafiği çizilmiyor ancak
              // kar/zararda 0 da farklı"): Reşat için geçmiş seri 7.216 kat
              // küçük çiziliyor (birim ~6.200 ₺), son nokta ise canlı fiyatla
              // (~34.000 ₺) EZİLDİĞİ için grafik dümdüz bir taban + tek dikey
              // sıçrama oluyordu — ölçülen oran 5,17 kat. Kâr/zarar `Asset.
              // currentPrice` üzerinden hesaplandığı için doğru kalıyor;
              // "grafik yok ama kâr/zarar var" ayrışması tam olarak buradan.
              final double factor = PriceService.goldWeightFactor(a.ticker);
              final double price = _getClosestPrice(goldHistory, dayTs, null);
              final double kal = altinKalibre[a.ticker] ?? 1.0;
              assetDayVal = price * factor * kal * qty;
            } else {
              // Ölçülemeyen varlık o günü DÜŞÜRMEZ, yalnızca kendisi
              // toplama girmez (uydurma fiyat üretmekten iyidir).
              final f = _flatFallback(a);
              if (f == null) continue;
              assetDayVal = f * (qty / a.quantity);
            }
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.fon ||
              a.type == AssetType.doviz) {
            final map = tickerNormalizedDaily[a.ticker] ?? {};
            if (map.isNotEmpty) {
              double price = _getClosestPrice(map, dayTs, null);
              // Kur: serinin kendi kuru → yoksa canlı kur → yoksa ÖLÇÜM YOK.
              // Sabit 35.0 varsayılanı buradaydı ve kur serisi boş döndüğü
              // her turda portföyü sessizce yanlış gösteriyordu.
              double? usdRate;
              if (a.currency == 'USD') {
                usdRate = usdTryHistory.isNotEmpty
                    ? _getClosestPrice(usdTryHistory, dayTs, null)
                    : canliKur();
                if (usdRate == null || usdRate <= 0) continue;
                price *= usdRate;
              }
              assetDayVal = price * qty;
            } else {
              final f = _flatFallback(a);
              if (f == null) continue;
              assetDayVal = f * (qty / a.quantity);
            }
          } else {
            final f = _flatFallback(a);
            if (f == null) continue;
            assetDayVal = f * (qty / a.quantity);
          }

          dayTotalValue += assetDayVal;
        } catch (e) {
          // Bir lot'un günü hesaplanamazsa, sadece o günkü işaretli
          // katkıyı fallback ile ekle — yine de negatif olamaz. Fallback de
          // ölçülemiyorsa (kur yok) o lot bu güne HİÇ girmez.
          dayTotalValue += _flatFallback(a) ?? 0.0;
        }
      }

      // Geçmişte satılan miktarlar buy'lardan büyük olsa (edge case)
      // negatif toplam çıkmasın.
      if (dayTotalValue < 0) dayTotalValue = 0;
      groupedPoints[dayTs] = dayTotalValue;
    }

    // Bugünün noktasını anlık portföy değerine sabitle (Yahoo API'sindeki
    // son gün datası bazen geç güncellenir; ana ekranla tutarlılık için).
    //
    // NOT: Altın için `currentPrice` adet fiyatı (Cumhuriyet ~40k gibi) iken
    // geçmiş serisi gram22k × factor × qty üzerinden hesaplanır.
    //
    // ⚠️ Burada eskiden "ölçekler aynı" yazıyordu; DEĞİLDİ. Geçmiş seri
    // uluslararası spot'tan (`XAUTRY=X` / `GC=F`), canlı fiyat ise yurt içi
    // kotasyondan (truncgil) geliyor ve aralarında kalıcı bir makas var.
    // Bu satırın varsayımı yüzünden altın grafiklerinin SAĞ UCUNDA fiyat
    // hareketi olmayan dik bir basamak oluşuyordu. Seri artık yukarıda
    // `altinKalibre` ile canlı ölçeğe taşınıyor; aşağıdaki hizalama da o
    // sayede süreklilik bozmadan çalışıyor.
    final todayTs = normalizeTs(now.millisecondsSinceEpoch);
    if (groupedPoints.containsKey(todayTs)) {
      double liveTotal = 0.0;
      bool skipOverwrite = false;
      for (final a in assets) {
        if (a.isDeleteLog) continue;
        final qty = signedQtyOnDay(a, todayTs);
        if (qty == 0) continue;
        final price = a.currentPrice > 0 ? a.currentPrice : 0.0;
        if (price <= 0) {
          skipOverwrite = true;
          break;
        }
        // Canlı toplam, ekrandaki kurla AYNI kurdan hesaplanır; seri kuru
        // yalnızca canlı kur hiç bilinmiyorsa devreye girer. Eskiden burada
        // `40.0` sabiti vardı ve grafiğin son noktası ile kâr/zarar çipi
        // farklı kurlardan iki ayrı sayı üretiyordu.
        double? liveUsd = canliKur();
        if (liveUsd == null && usdTryHistory.isNotEmpty) {
          liveUsd = usdTryHistory.values.last;
        }
        if (a.currency == 'USD' && (liveUsd == null || liveUsd <= 0)) {
          skipOverwrite = true;
          break;
        }
        final tryPrice = a.currency == 'USD' ? price * liveUsd! : price;
        liveTotal += tryPrice * qty;
      }
      if (liveTotal < 0) liveTotal = 0;
      // TradingView tarzı: son bar canlı fiyattır — tarihsel bar'lara asla
      // dokunma, sapma eşiği kullanma. %30 kural, gerçek büyük hareketlerde
      // (yeni alım, döviz sıçraması) canlı toplamı bastırıp grafiği yanıltıyor.
      if (!skipOverwrite && liveTotal > 0) {
        groupedPoints[todayTs] = liveTotal;
      }
    }

    // Outlier smoothing: bir gün önceki ve sonraki noktaya göre >%1.5 sapan ama
    // önceki-sonraki arası fark %1'den az olan tek-gün spike'ları temizle. Bu,
    // Yahoo'nun bazı sembollerdeki tek-gün eksik/geç verisinden gelen V-dip
    // artefaktlarını (gerçek trend olmadan) yumuşatır.
    smoothSpikes(groupedPoints, deviation: 0.015, neighborGap: 0.01);

    // Takip/karşılaştırma serileriyle AYNI kırpma. Grid zaten `periodDays`
    // adım üretiyor, ama kırpma iki şeyi garanti eder:
    //   · pencere sembol serileriyle bire bir aynı kuralla kapanır
    //     (`clipToPeriod` son veri noktasına çapalanır),
    //   · yüzde tabanı dönem içinde kalır. Kırpma yokken GÜNLÜK'te portföy
    //     çizgisi dönem başına göre değil BEŞ GÜN öncesine göre normalize
    //     oluyordu; ölçülen hata %1,00 yerine %10,02 (9 puan) idi ve aynı
    //     yanlış rakam açıklama satırına da yazılıyordu.
    return clipToPeriod(groupedPoints, periodDays);
  }

  double _getClosestPrice(
      Map<int, double> map, int targetTs, double? fallbackValue) {
    final exact = map[targetTs];
    if (exact != null) return exact;
    // Yoksa en yakın geçmiş tarihi (haftasonu durumu vs) bul.
    // Intraday'de slot × varlık başına çağrılır — sıralı indeks + ikili
    // arama şart (bkz. _sortedKeys). Eskiden her çağrıda sort + where
    // yapıyordu.
    if (map.isEmpty) return fallbackValue ?? 0.0;
    final sortedKeys = _sortedKeys(map);
    final idx = _floorIndex(sortedKeys, targetTs);
    if (idx >= 0) return map[sortedKeys[idx]]!;
    // Geçmişte yoksa gelecekteki en yakın ilk günü dön
    return map[sortedKeys.first]!;
  }

  /// [getPortfolioHistory]'nin son çağrıda kullandığı Yahoo range'i.
  ///
  /// Yalnızca test gözlemi içindir; üretimde okunmaz. Var olma sebebi:
  /// `range` yerel bir değişken olduğu için portföy merdiveninin sembol
  /// merdiveninden yeniden ayrışması ağa çıkmayan hiçbir testle
  /// yakalanamıyordu (sabotaj denendi, tüm testler geçti).
  @visibleForTesting
  static String? debugSonKullanilanRange;

  /// Altın serisinin son çağrıda hangi kaynaktan kurulduğu.
  ///
  /// Aynı gerekçe: kaynak seçimi yerel bir karardı ve ARALIKLI bir arızanın
  /// (spot ↔ vadeli geçişi, bkz. [altinGramSerisi]) hangi tarafta olduğu
  /// dışarıdan görülemiyordu. Kullanıcı "bazen oluyor" dediğinde bakılacak
  /// yer burası.
  @visibleForTesting
  static AltinSeriKaynagi? debugSonAltinKaynagi;

  /// Portföy serisinin zaman ızgarası — `{ normalize edilmiş UNIX_MILLIS }`,
  /// eskiden yeniye sıralı.
  ///
  /// Saf fonksiyon ([now] dışarıdan verilir) olmasının SEBEBİ var: hafta sonu
  /// davranışı yalnızca Cumartesi/Pazar günü ortaya çıkıyor. Izgara
  /// `getPortfolioHistory`'nin içinde `DateTime.now()` ile kurulduğu sürece
  /// o dal hafta içi koşan bir testte HİÇ çalışmaz — nitekim ilk yazılan
  /// koruma testi, çapa sabote edildiğinde de geçiyordu (Cuma günü koşuldu).
  /// Izgarayı ayırmak "Pazar günü ne olur" sorusunu doğrudan sorulabilir yapar.
  ///
  /// ## Kurallar
  /// · Saatlik ızgara (dönem ≤ 7 gün) hafta sonu slotlarını ATLAR — Cts/Paz
  ///   platosu trading uygulamalarında gösterilmez.
  /// · Bu yüzden pencere de hafta sonundan BAŞLAYAMAZ: [_sonIsGunu] ile son
  ///   iş gününe çapalanır. Aksi halde Pazar günü "GÜNLÜK" seçildiğinde
  ///   24 slotun tamamı elenir ve seri boş döner (ölçüldü: Pazar → 0 slot).
  /// · Günlük ızgara (dönem > 7 gün) hafta sonunu ELEMEZ; haftada 5 nokta ile
  ///   7 nokta arasındaki fark uzun dönemde önemsiz.
  @visibleForTesting
  static List<int> gridSlotlari({
    required DateTime now,
    required int periodDays,
    required bool hourly,
  }) {
    int normalizeTs(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (hourly) {
        return DateTime(d.year, d.month, d.day, d.hour).millisecondsSinceEpoch;
      }
      return dayKey(d).millisecondsSinceEpoch;
    }

    // ## Hafta sonu YALNIZCA tek günlük pencerede elenir
    //
    // Eleme, 24 saatlik pencerenin hafta sonunda tümüyle boşalmasını
    // önlemek için konmuştu: "son 24 saat" yerine "son 24 SEANS SAATİ"
    // çizilir ve çizgi kaybolmaz.
    //
    // Ama kural ÇOK GÜNLÜ pencerelerde (1H = 7 gün, saatlik) zararlıydı:
    // Cumartesi bakıldığında 12 Eylül ızgarada HİÇ üretilmiyor, grafik
    // 11 Eylül'de bitiyordu. Kullanıcı bildirimi 2026-09-12: "1H'de
    // 12 Eylül datasını göremiyorum."
    //
    // Çok günlü pencerede boşalma riski zaten yok (hafta sonu en fazla
    // iki günü kaplar, geriye beş seans günü kalır). Kapalı günler
    // ızgarada DURUR ve `_getClosestPrice` son kapanışı taşır — yani düz
    // çizgi olarak görünürler, kullanıcının istediği davranış.
    final tekGunlukPencere = periodDays <= 1;
    final gridNow = (hourly && tekGunlukPencere) ? _sonIsGunu(now) : now;
    final stepMinutes = hourly ? 60 : 24 * 60;
    final totalSteps = hourly ? periodDays * 24 : periodDays;

    final out = <int>[];
    for (var i = totalSteps; i >= 0; i--) {
      final slotDate = gridNow.subtract(Duration(minutes: i * stepMinutes));
      if (hourly && tekGunlukPencere) {
        final wd = slotDate.weekday; // 6=Cts, 7=Paz
        if (wd == DateTime.saturday || wd == DateTime.sunday) continue;
      }
      out.add(normalizeTs(slotDate.millisecondsSinceEpoch));
    }

    // **Hafta sonu elenince pencere KISALIR — geriye doğru tamamlanır.**
    //
    // `_sonIsGunu` yalnızca `now`'un kendisi hafta sonundaysa çapayı çeker;
    // pencerenin hafta sonuna UZANMASINI karşılamaz. Pazartesi 00:10'da
    // ölçüldü: 24 saatlik pencerenin tamamı Pazar'a düşüyor, hepsi eleniyor
    // ve geriye TEK slot kalıyordu — `normalizeSeries` iki noktanın altında
    // null döner, yani portföy çizgisi yine kayboluyordu. Cuma akşamı
    // koşulduğunda görünmeyen, Pazartesi sabahı ortaya çıkan bir hata.
    //
    // Çözüm: hedef slot sayısına ulaşana kadar iş günlerinde geriye yürü.
    // Böylece "son 24 saat" değil "son 24 SEANS SAATİ" çizilir — grafiğin
    // sorusu zaten piyasanın açık olduğu zamanla ilgili.
    // Yalnızca eleme YAPILDIYSA anlamlı: çok günlü pencerede hafta sonu
    // artık elenmiyor, ızgara zaten tam uzunlukta.
    if (hourly && tekGunlukPencere && out.length < totalSteps + 1) {
      var slotDate = gridNow.subtract(Duration(minutes: totalSteps * stepMinutes));
      // Üst sınır: sonsuz döngüye karşı güvenlik ağı (tatil zinciri olsa
      // bile iki haftada hedefe ulaşılır).
      final sinir = totalSteps * 3 + 14;
      var adim = 0;
      while (out.length < totalSteps + 1 && adim < sinir) {
        slotDate = slotDate.subtract(Duration(minutes: stepMinutes));
        adim++;
        final wd = slotDate.weekday;
        if (wd == DateTime.saturday || wd == DateTime.sunday) continue;
        out.add(normalizeTs(slotDate.millisecondsSinceEpoch));
      }
      out.sort();
    }
    return out;
  }

  /// [d] hafta sonuna düşüyorsa bir önceki Cuma'ya (aynı saatte) çeker.
  ///
  /// Saatlik grid hafta sonu slotlarını atladığı için pencerenin kendisi de
  /// hafta sonundan başlamamalı — yoksa pencere boşa düşer ve çizgi kaybolur.
  /// Borsa tatilleri KAPSANMAZ: tatil takvimi yok, ve tatilde pencere bir
  /// seans dar kalır ama boşalmaz (Cuma verisi hâlâ pencerede).
  @visibleForTesting
  static DateTime sonIsGunu(DateTime d) => _sonIsGunu(d);

  /// Gün içi grafiğin ÇİZECEĞİ günün 00:00'ı — HER ZAMAN bugün.
  ///
  /// [enSonVeriTs] çekilen gün içi serilerdeki EN YENİ zaman damgası
  /// (hiç veri yoksa `null`). Artık yalnızca geriye dönük uyumluluk için
  /// duruyor: dönüş değeri ona BAĞLI DEĞİL.
  ///
  /// ## Neden eskiden bugün olmayabiliyordu
  /// Piyasa kapalıyken Yahoo'nun `range=1d` yanıtı SON SEANSA aittir.
  /// Izgara bugüne kurulunca `pastOrNull` o seansın kapanışını bugünün
  /// 288 slotunun tamamına yayıyor ve grafik DÜMDÜZ bir çizgi oluyordu
  /// ("data alınamıyor olabilir mi, dümdüz çizgi sebebi nedir" —
  /// kullanıcı bildirimi 2026-09-07). Çözüm veriyi ait olduğu güne
  /// çizmekti.
  ///
  /// ## Neden DEĞİŞTİ (kullanıcı kararı 2026-09-13)
  /// "Ayın 13'ünde günlük tabında 12 Eylül verisini görmemeliyim."
  ///
  /// O çözüm iki yeni sorun doğurmuştu:
  ///   1. Sekme adı yalan söylüyordu — "GÜNLÜK" başka bir günü gösteriyordu.
  ///   2. Seri son seansın son damgasında (Cuma 20:55) bitiyor, ekran ise
  ///      ucuna CANLI toplamı ekliyordu. Aradaki saatlerde nokta yok:
  ///      grafik düz gidip "şimdi"ye ATLIYORDU.
  ///
  /// Düz çizgi artık kabul edilebilir çünkü ekranda onu AÇIKLAYAN bir
  /// rozet var (`piyasa_kapali_etiketi.dart` — "BORSA KAPALI" / "SON
  /// VERİ"). 2026-09-07'de o rozet YOKTU; düz çizgi sessizdi ve bu yüzden
  /// korkutucuydu. Dürüst ve açıklanmış bir düz çizgi, yanlış güne
  /// çizilmiş bir seriden iyidir.
  ///
  /// ## Neden saf fonksiyon (ve neden imza korunuyor)
  /// Karar `DateTime.now()` ile verilseydi hafta içi koşan hiçbir test
  /// hafta sonu dalını çalıştıramazdı. [enSonVeriTs] parametresi, çağıran
  /// tarafı ve testleri kırmamak için duruyor; kaldırmak bu dosyanın
  /// dışındaki dört çağrı noktasını da değiştirmeyi gerektirirdi ve
  /// kazancı yok.
  @visibleForTesting
  static DateTime seansGunu({
    required DateTime now,
    required int? enSonVeriTs,
  }) =>
      dayKey(now);

  /// Gün içi serinin SAĞ UCU ve kapalı bölgenin başlangıcı.
  ///
  /// ## Neden kapanışta durmuyoruz (kullanıcı isteği 2026-09-12)
  /// Geçmiş bir seans çizilirken seri, o seansın kapanışında kesiliyordu.
  /// Doğru veriydi ama Pazar günü eksende yalnızca Cuma görünüyordu ve
  /// kullanıcı "grafik dünde kalmış" diye okudu.
  ///
  /// Artık kapanış fiyatı BUGÜNE kadar sabit bir kuyruk olarak uzatılıyor:
  /// Pazar günü eksen Cuma–Cumartesi–Pazar'ı kapsar. Kuyruk gerçek işlem
  /// DEĞİLDİR; [piyasaKapali] damgasından sonrası ekranda gri ve kesikli
  /// çizilir.
  ///
  /// ## Neden saf fonksiyon
  /// Hafta sonu dalı yalnızca Cumartesi/Pazar ortaya çıkar. Karar
  /// `DateTime.now()` ile verildiği sürece hafta içi koşan hiçbir test o
  /// dalı çalıştıramaz — `gridSlotlari` ve `seansGunu` da aynı sebeple
  /// ayrılmıştı.
  ///
  /// [seansSonuTs] geçmiş seans çiziliyorsa o seansın son veri damgası,
  /// bugün çiziliyorsa `null`.
  @visibleForTesting
  static ({int sagUc, int? piyasaKapali}) gunIciSagUc({
    required DateTime now,
    required int? seansSonuTs,
    required int Function(int) normalizeSlot,
  }) {
    final simdi = normalizeSlot(now.millisecondsSinceEpoch);
    // Bugünün seansı çiziliyor: kuyruk yok, seri "şimdi"de biter.
    if (seansSonuTs == null) return (sagUc: simdi, piyasaKapali: null);

    final kapanis = normalizeSlot(seansSonuTs);
    // Savunma: veri damgası ileri tarihliyse (saat dilimi kayması)
    // kuyruk NEGATİF uzunlukta olurdu.
    if (kapanis >= simdi) return (sagUc: kapanis, piyasaKapali: null);

    return (sagUc: simdi, piyasaKapali: kapanis);
  }

  static DateTime _sonIsGunu(DateTime d) {
    var out = d;
    while (out.weekday == DateTime.saturday || out.weekday == DateTime.sunday) {
      out = out.subtract(const Duration(days: 1));
    }
    return out;
  }

  /// Gerçek geçmiş veri yoksa currentPrice'ı sabit kullan (simülasyon yok).
  ///
  /// **Ölçülemiyorsa `null`.** Eskiden USD kote varlık için sabit `40.0`
  /// kuru uyduruluyordu; o sayı gerçek kurdan saptıkça portföyü sessizce
  /// yanlış gösteriyordu. Artık sıra: canlı kur (oturumda görülen son
  /// gerçek değer) → yoksa ölçüm YOK ve varlık o noktada toplama girmez.
  double? _flatFallback(Asset asset) {
    final price = asset.currentPrice > 0 ? asset.currentPrice : 0.0;
    if (price <= 0) return null;
    if (asset.currency != 'USD') return price * asset.quantity;
    final kur = canliKur();
    if (kur == null) return null;
    return price * kur * asset.quantity;
  }

  /// Uygulamanın CANLI kur gerçeği — ekrandaki TL karşılığıyla AYNI kaynak.
  ///
  /// `PortfolioState.toTRY` de `fetchQuotes('USDTRY=X')` sonucunu kullanır;
  /// grafik yollarının ayrı bir kur gerçeği olmamalı (bkz.
  /// `fiyat_kaynagi.dart` sözleşmesi).
  @visibleForTesting
  static double? Function() canliKur =
      () => PriceService.instance.sonBilinenFiyat(FiyatKaynagi.usdTry);

  /// Intraday (gün-içi) çözünürlükte portföy değeri.
  /// Yahoo `1d/5m` interval'i kullanılır → 5 dakikalık noktalar. Bugünün 00:00
  /// ile 23:59 arasındaki her 5 dakikalık slot için toplam TRY değeri döner.
  /// Anahtar: UNIX_MILLIS (5 dakikalık slota normalize).
  ///
  /// [hours] parametresi yalnızca X ekseni birim ölçeği (saat) için tutulur;
  /// gerçek çözünürlük 5 dakikadır (12x saatlik). Veri kaynağı borsa saatleri
  /// dışı slotlar için son bilinen fiyatı yayar (`_getClosestPrice`).
  Future<Map<int, double>> getPortfolioHistoryHourly(
          List<Asset> assets, int hours) async =>
      (await getPortfolioHistoryHourlyBreakdown(assets, hours)).total;

  /// [getPortfolioHistoryHourly] ile AYNI hesap — ek olarak tür/pozisyon
  /// dağılımını da döndürür.
  ///
  /// Gün içi ("GÜNLÜK") sekmesinde tür dökümü kartı bunu kullanır. Kart bu
  /// sekmede eskiden HİÇ görünmüyordu: diğer periyotlar
  /// `getPortfolioHistoryBreakdownAtResolution`'dan dağılım alıyordu, gün içi
  /// yolu ise ayrı olan bu servise gidiyor ve dağılım taşımıyordu.
  ///
  /// Değişmez diğer yolla aynı ve aynı gerekçeyle: toplam ve dağılım TEK
  /// döngüde birikir, ayrı geçişte hesaplanırsa toplamlar ayrışır.
  /// Bkz. [PortfolioHistoryBreakdown].
  Future<PortfolioHistoryBreakdown> getPortfolioHistoryHourlyBreakdown(
      List<Asset> assets, int hours) async {
    const range = '1d';
    const slotMinutes = 5;

    int normalizeSlot(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final snappedMinute = (d.minute ~/ slotMinutes) * slotMinutes;
      return DateTime(d.year, d.month, d.day, d.hour, snappedMinute)
          .millisecondsSinceEpoch;
    }

    // Intraday'e özel "geçmişe yakın olan" price lookup. Standart
    // `_getClosestPrice` past yoksa gelecekteki en yakın slotu döndürüyor —
    // bu intraday grafiğinde borsa açılmadan önceki tüm slotlara açılış
    // fiyatını yayıyor ve grafiği düz gösteriyor. Burada past yoksa null
    // döndürüp o slotu atlıyoruz (grafik ilk gerçek veriden başlasın).
    double? pastOrNull(Map<int, double> map, int targetTs) {
      if (map.isEmpty) return null;
      final exact = map[targetTs];
      if (exact != null) return exact;
      // Sıralı indeks + ikili arama (bkz. _sortedKeys) — bu closure her
      // 5dk slot × varlık için çağrılıyor.
      final keys = _sortedKeys(map);
      final idx = _floorIndex(keys, targetTs);
      return idx < 0 ? null : map[keys[idx]];
    }

    // pastOrNull başarısızsa "en yakın nokta" ile fallback yap.
    // 40.0 gibi sabit sayı kullanmak eski/yeni tarihlerde büyük sapma yaratır.
    // Bu helper hiç değilse serinin en yakın gerçek değerini kullanır.
    double? closestOrNull(Map<int, double> map, int targetTs) {
      final past = pastOrNull(map, targetTs);
      if (past != null) return past;
      if (map.isEmpty) return null;
      // Geçmişte yok → ileride en yakın
      return map[_sortedKeys(map).first];
    }

    final now = DateTime.now();
    final Map<String, Map<int, double>> tickerSlots = {};
    final Map<int, double> usdTrySlots = {};
    final Map<int, double> goldSlots = {}; // TRY / gram22k

    Future<List<(int, double)>> getHistorySafeFor(String sym, String r) async {
      final cacheKey = '${sym}_$r';
      // Gün içi seriler daha çabuk eskir (bkz. `_intradayCacheTtl`).
      final cached =
          _cacheGet(cacheKey, ttl: r == '1d' ? _intradayCacheTtl : null);
      if (cached != null) return cached;
      try {
        final pts = await PriceService.instance.fetchHistory(sym, r);
        if (pts.isNotEmpty) _cachePut(cacheKey, pts);
        return pts;
      } catch (_) {
        return [];
      }
    }

    Future<List<(int, double)>> getHistorySafe(String sym) =>
        getHistorySafeFor(sym, range);

    final bool needsGold = assets.any((a) => a.type == AssetType.altin);
    final bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    // Tüm semboller tek seferde başlatılır — gerekçe için `getPortfolioHistory`
    // içindeki aynı bloğun açıklamasına bak.
    final usdFuture = needsUsd
        ? getHistorySafe(FiyatKaynagi.usdTry)
        : Future.value(const <(int, double)>[]);
    // Altının gün içi serisi ÖNCE `XAUTRY=X` ile denenir.
    //
    // Eskiden tek kaynak `GC=F` idi ve bu TEK ARIZA NOKTASIYDI: Yahoo o
    // vadeli sözleşme için 5 dakikalık veriyi vermediğinde altının hiçbir
    // slotu fiyatlanamıyor, her slot `assetSeedTRY` ile son bilinen fiyata
    // düşüyor ve altın ağırlıklı bir portföyün grafiği gün boyu DÜMDÜZ
    // çiziliyordu. Üstelik bu bir hata gibi de görünmüyordu: seed slotu
    // "kapsanmış" sayıyor, eksik kapsam elemesine takılmıyor.
    //
    // `fetchHistoricalClose` bu sıralamayı zaten kullanıyordu (önce
    // XAUTRY=X, olmazsa GC=F × USDTRY); gün içi yolu o dersin dışında
    // kalmıştı. XAUTRY=X doğrudan TRY/ons verir — USD serisine bağımlılık
    // da kalkar, yani iki kaynak birden düşmedikçe altın düz çizgiye
    // inmez.
    final goldTryFuture = needsGold
        ? getHistorySafe(FiyatKaynagi.xauTry)
        : Future.value(const <(int, double)>[]);

    // Yedek altın kaynağı ŞİMDİ başlar — birincinin sonucu beklenmeden.
    //
    // Eskiden `if (goldSlots.isEmpty)` dalında çağrılıyordu, yani ikinci
    // istek ancak birincisi TAMAMLANDIKTAN sonra başlıyordu. Altın böylece
    // tek başına iki isteği SIRALI yapan tür oluyordu: en kötü durumda
    // 15 sn + 15 sn = 30 saniye. Diğer türler tek istekle en kötü 15 sn.
    //
    // Kullanıcı bildirimi (2026-09-13): "uzun süre bekleyince geldi, kimse
    // bu kadar uzun beklemez." Paralel başlatmak en kötü durumu yarıya
    // indiriyor; birincisi doluysa ikincinin sonucu zaten kullanılmıyor
    // (fazladan bir istek, ölçülebilir bir gecikme değil).
    final goldUsdFuture = needsGold
        ? getHistorySafe(FiyatKaynagi.xauUsd)
        : Future.value(const <(int, double)>[]);

    final tickerFutures = <String, Future<List<(int, double)>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty)) {
        tickerFutures.putIfAbsent(a.ticker, () => getHistorySafe(a.ticker));
      }
    }

    // ── Fon (TEFAS) NAV serisi ──────────────────────────────────────────────
    //
    // TEFAS gün içi NAV yayınlamaz: bir fonun fiyatı günde BİR kez değişir.
    // Fon gün boyu `currentPrice` ile sabit çizildiğinde gün içi seride
    // değişimi SIFIR görünüyordu — oysa iki NAV arasında gerçek bir fark
    // var ve kullanıcı onu görmek istiyor ("günlükte fon seçilince de
    // değişim yok gözüküyor ancak aslında var", 2026-09-10).
    //
    // Çözüm: fonun ÖNCEKİ NAV'ını da çek. Gün, önceki NAV ile açılır;
    // seansın ilk gerçek verisinden sonra güncel NAV'a geçer (aşağıdaki
    // `fonOncekiNav` kullanımına bak). Böylece gün içi seri fonun
    // günlük değişimini bir BASAMAK olarak taşır — ara noktalar
    // uydurulmaz, çünkü fonun gün içinde ara değeri yoktur.
    final fonNavFutures = <String, Future<List<(int, double)>>>{};
    for (final a in assets) {
      if (!a.isBuy || a.quantity <= 0) continue;
      if (a.type != AssetType.fon) continue;
      // NAV yalnızca TEFAS kodlu fonlarda var; elle fiyatlanan fonun
      // yayımlanmış bir serisi yok.
      if (!a.ticker.startsWith('TEFAS:')) continue;
      if (a.isManualPrice) continue;
      // `5d` aralığı TEFAS tarafında 1 aylık GÜNLÜK NAV serisine eşlenir
      // (bkz. `PriceService._tefasPeriyodFor`) — son iki nokta yeter.
      //
      // Bilerek `1d` DEĞİL: `1d` anahtarları gün içi TTL'ine (5 dk) tabi
      // ve 30 saniyelik ekran tick'i onları sürekli tazeler. Fon NAV'ı
      // günde bir kez değişir; onu beş dakikada bir yeniden çekmek boşuna
      // TEFAS trafiğidir.
      fonNavFutures.putIfAbsent(
          a.ticker, () => getHistorySafeFor(a.ticker, '5d'));
    }
    // Sunucudaki yayın anı gözlemleri — NAV serileriyle PARALEL başlar.
    // Çizilecek gün (`dayStart`) henüz bilinmiyor; son üç gün istenir,
    // eşleştirme aşağıda `fonBasamakAni` içinde güne göre yapılır.
    final fonGozlemFuture = _gozlemleriGetir(
      fonNavFutures.keys.map(tefasKodu).toSet(),
      dayKey(now).subtract(const Duration(days: 3)),
    );

    if (needsUsd) {
      final usd = await usdFuture;
      for (final p in usd) {
        usdTrySlots[normalizeSlot(p.$1)] = p.$2;
      }
      final hizali = kurSerisiniHizala(usdTrySlots, canliKur());
      if (!identical(hizali, usdTrySlots)) {
        usdTrySlots
          ..clear()
          ..addAll(hizali);
      }
    }

    if (needsGold) {
      // Merdiven (spot → vadeli) `altinGramSerisi`'nde; iki kaynak da
      // yukarıda PARALEL başlatıldı, burada yalnızca sonuçları alıyoruz.
      final xauTryPts = await goldTryFuture;
      final xauUsdPts = await goldUsdFuture;
      final sonuc = altinGramSerisi(
        xauTry: {
          for (final p in xauTryPts) normalizeSlot(p.$1): p.$2,
        },
        xauUsd: {
          for (final p in xauUsdPts) normalizeSlot(p.$1): p.$2,
        },
        usdTry: usdTrySlots,
        kurBul: (kur, ts) => closestOrNull(kur, ts),
      );
      goldSlots.addAll(sonuc.seri);
      debugSonAltinKaynagi = sonuc.kaynak;
    }

    // Fiyat serileri yukarıda paralel başlatıldı — burada sonuçlar toplanır.
    for (final entry in tickerFutures.entries) {
      final raw = await entry.value;
      final map = <int, double>{};
      for (final p in raw) {
        map[normalizeSlot(p.$1)] = p.$2;
      }
      tickerSlots[entry.key] = map;
    }

    // Fon NAV'ları: sembol → (önceki NAV, güncel NAV).
    //
    // "Önceki" = son yayımlanandan bir ÖNCEKİ gün. İkisi eşitse ya da
    // seri tek noktalıysa fonun günlük değişimi yok demektir; o durumda
    // `oncekiNav` null bırakılır ve fon eskisi gibi sabit çizilir.
    final fonOncekiNav = <String, double>{};
    // Son NAV'ın YAYIN TARİHİ — basamağın çizilip çizilmeyeceğini belirler.
    final fonSonNavGunu = <String, DateTime>{};
    for (final entry in fonNavFutures.entries) {
      final pts = await entry.value; // (ts, nav) — artan sırada
      if (pts.length < 2) continue;
      final onceki = pts[pts.length - 2].$2;
      final son = pts.last.$2;
      if (onceki <= 0 || son <= 0) continue;
      final sonGun = DateTime.fromMillisecondsSinceEpoch(pts.last.$1);
      fonSonNavGunu[entry.key] =
          dayKey(sonGun);
      if ((son - onceki).abs() < 1e-9) continue;
      fonOncekiNav[entry.key] = onceki;
    }

    // ── Çizilecek SEANS günü ────────────────────────────────────────────────
    //
    // "GÜNLÜK" sekmesi her zaman bugünü çizemez. Piyasa kapalıyken (hafta
    // sonu, resmî tatil, ve gün başında açılıştan önce) Yahoo'nun
    // `range=1d` yanıtı SON SEANSA aittir. Izgara bugüne kurulursa
    // `pastOrNull` o son seansın kapanışını bugünün 288 slotunun tamamına
    // yayar → grafik dümdüz bir çizgi olur. Pazartesi 10:00'dan önce de
    // aynı durum geçerlidir: o saatte son seans hâlâ Cuma'dır.
    //
    // Doğrusu: veri hangi güne aitse O GÜNÜ çiz. Böylece hafta sonunda
    // Cuma seansının gerçek gün içi hareketi görünür — trading
    // uygulamalarının standart davranışı.
    final bugun = dayKey(now);
    int? enSonVeriTs;
    void enSonuIzle(Map<int, double> m) {
      if (m.isEmpty) return;
      final k = m.keys.reduce((x, y) => x > y ? x : y);
      if (enSonVeriTs == null || k > enSonVeriTs!) enSonVeriTs = k;
    }

    for (final m in tickerSlots.values) {
      enSonuIzle(m);
    }
    enSonuIzle(goldSlots);
    enSonuIzle(usdTrySlots);

    final dayStart = seansGunu(now: now, enSonVeriTs: enSonVeriTs);
    // Bugün dışında bir seans çiziliyor mu?
    final gecmisSeans = dayStart.isBefore(bugun);
    final seansSonuTs = gecmisSeans ? normalizeSlot(enSonVeriTs!) : null;

    // Slot-bazlı işaretli miktar. Bugünkü zaman dilimlerinde:
    // buy addedDate <= slot ise +qty, sell addedDate <= slot ise -qty.
    double signedQtyOnSlot(Asset a, int slotTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      // GEÇMİŞ seans çizilirken tarih kapısı UYGULANMAZ: elde ŞU ANKİ
      // pozisyon vardır ve soru "elimdeki portföy son seansta ne yaptı".
      // Kapı uygulansaydı hafta sonu yapılan bir alım Cuma seansına hiç
      // girmez, grafiğin son noktası ana ekrandaki toplamla tutmazdı.
      if (!gecmisSeans) {
        final addedTs = normalizeSlot(a.addedDate.millisecondsSinceEpoch);
        if (addedTs > slotTs) return 0.0;
      }
      return a.isSell ? -a.quantity : a.quantity;
    }

    // Altın türü katsayısı (gram22k referansına göre).
    // Ağırlık tablosu `PriceService`'te tutulur; buradaki yerel kopya
    // ALTIN_RESAT'ı ATLIYORDU (tabloda 7.216 ile var ama switch'te yoktu),
    // yani Reşat altını grafikte gram altın gibi çiziliyor ve pozisyon
    // 7.216 kat düşük görünüyordu.
    double goldFactor(String ticker) => PriceService.goldWeightFactor(ticker);

    // Altın serisi CANLI ölçeğe kalibre edilir (bkz. `altinKalibrasyonu`).
    // Yapılmazsa seri uluslararası spot ölçeğinde ilerler, son slot ise
    // aşağıdaki `liveTotal` hizalamasıyla yurt içi kotasyona iner: aradaki
    // kalıcı makas "ŞİMDİ" imlecine yapışık dik bir uçurum olarak görünür
    // (kullanıcı bildirimi 2026-09-17).
    final altinKalibre =
        altinKalibrasyonHaritasi(assets: assets, gramSerisi: goldSlots);
    double goldKal(String ticker) => altinKalibre[ticker] ?? 1.0;

    final groupedPoints = <int, double>{};
    // Tür/pozisyon dağılımı — `groupedPoints` ile AYNI döngüde birikir.
    final byType = <AssetType, Map<int, double>>{};
    final byPosition = <String, Map<int, double>>{};
    final positionType = <String, AssetType>{};
    // Gerçek gün içi fiyatın göründüğü İLK slot (seans açılışı).
    //
    // Fonun NAV basamağı buraya göre konumlanır: seansın ilk gerçek
    // noktasına kadar önceki NAV, sonrasında güncel NAV (bkz. fon dalı).
    // Slot döngüsünün SONUNDA yazılır — döngü gövdesinde okunduğunda
    // "önceki slotlarda gerçek veri gördük mü" sorusunu yanıtlar.
    int? ilkGercekTs;
    // Gün içi fiyatı OLMASI GEREKEN türler ve fiilen ALINABİLEN türler.
    // Farkı, kullanıcıya "bu türün düzlüğü veri yokluğundandır" diye
    // gösterilir (bkz. `gunIciVerisiYokTurler`). Fon/mevduat/diğer bu
    // sayıma hiç girmez: onların gün içi fiyatı zaten yok.
    final gunIciBeklenenTurler = <AssetType>{};
    final gunIciGercekTurler = <AssetType>{};

    // Serinin sağ ucu ve "piyasa kapalı" bölgesinin başlangıcı.
    //
    // Geçmiş seans çizilirken seri kapanışta KESİLMİYOR: kapanış fiyatı
    // bugüne kadar sabit kuyruk olarak uzatılıyor ki eksen Pazar günü
    // Cuma–Cmt–Pazar'ı kapsasın. Kuyruk gerçek işlem değildir; ekran onu
    // gri/kesikli çizer (bkz. `gunIciSagUc`).
    // ## Kapalı kuyruk KALDIRILDI (kullanıcı kararı 2026-09-12)
    //
    // Kuyruk, son seansın kapanışını bugüne kadar düz taşıyordu. İki
    // sorun çıktı:
    //
    //   1. "Son seans" güvenilir değil: `enSonVeriTs` TÜM sembollerin en
    //      yenisi ve döviz 7/24'e yakın işliyor. BIST 18:10'da kapanmışken
    //      damga 20:40 çıkabiliyor — kullanıcı bunu fark etti.
    //   2. Kuyruk boyunca hiçbir varlık hesaplanmadığı için mevduat faizi
    //      ve açık spot piyasalar görünmüyordu; "piyasa kapalı" demek de
    //      yanlış bilgiydi.
    //
    // Kullanıcı isteği: "piyasa kapalı ve çizikli alanları iptal edelim
    // önceki gibi, güncel değer ne ise o şekilde göstersin."
    //
    // Seri yine son seansın gününü çiziyor (`seansGunu`) ve serinin ucu
    // CANLI toplama sabitleniyor (ekran tarafı) — yani rakam her zaman
    // güncel.
    final nowTs = seansSonuTs ?? normalizeSlot(now.millisecondsSinceEpoch);
    const int? piyasaKapaliTs = null;

    // Izgara `dayStart`'tan başlar ve SAĞ UCA kadar uzar.
    //
    // Sabit 288 slot (24 saat) yetmiyor: kapalı kuyruk çizilirken seri
    // Cuma 00:00'dan Pazar'a kadar uzanabilir (Pazar günü ~3 gün = 864
    // slot). Sabit sayıyla döngü Cuma gecesinde biter ve kuyruk hiç
    // çizilmezdi — eksende yine tek gün görünürdü.
    const slotMs = slotMinutes * 60 * 1000;
    final hedefSlot =
        ((nowTs - dayStart.millisecondsSinceEpoch) / slotMs).ceil();
    // Alt sınır: istenen pencere (24s → 288). Üst sınır: güvenlik ağı —
    // bozuk/çok eski bir veri damgası ızgarayı sonsuza yaymasın
    // (7 gün = 2016 slot, en uzun tatil zinciri için fazlasıyla yeterli).
    final slotCount = hedefSlot.clamp(
      hours * (60 ~/ slotMinutes),
      7 * 24 * (60 ~/ slotMinutes),
    );

    // ── Fonun NAV basamağının yeri ──────────────────────────────────────────
    //
    // Fonun günlük NAV değişimi gün içinde TEK bir anda olur. O anın nerede
    // çizileceği SABİT olmak zorunda: kayan bir basamak, kullanıcıya "az önce
    // bir şey oldu" der ve her bakışta başka bir yerde durur.
    //
    // Çapa neden `tefasNavYayinSaati`: TEFAS yanıtı NAV'ın TARİHİNİ taşıyor,
    // yayımlandığı ANI değil — elimizde gerçek yayın damgası yok. Piyasa
    // açılışı (10:00) uygulamanın başka yerlerinde de kullandığı, günden güne
    // değişmeyen bir referans. Yaklaşıklığı `TECHNICAL_DEBT.md`'de yazılı.
    //
    // Çizilen gün henüz o saate ULAŞMADIYSA basamak YOKTUR (`null`): fon gün
    // boyu güncel NAV ile çizilir. Bu, son slotu canlı toplamla ezen
    // hizalamanın fon için no-op kalmasını garanti eder — yani imlece yapışan
    // dik uçurum hiçbir saatte oluşamaz.
    final fonBasamakAdayi = dayStart
        .add(const Duration(hours: tefasNavYayinSaati))
        .millisecondsSinceEpoch;
    final int? fonBasamakTs =
        nowTs >= normalizeSlot(fonBasamakAdayi) ? normalizeSlot(fonBasamakAdayi) : null;
    // Gözlem varsa fon bazında bu varsayılanın yerine geçer (`fonBasamakAni`).
    final fonGozlemler = await fonGozlemFuture;

    // Her varlık için "seed" fiyatı — intraday veri henüz gelmediği
    // slotlarda kullanılır (dünkü kapanış proxy'si). Böylece bir varlığın
    // borsa açılışı gecikse bile grafik ilk slot'tan itibaren varlığı sayar
    // ve borsa açıldığında dik sıçrama olmaz, sadece intraday hareket
    // görünür.
    //
    // Seed önceliği:
    //   1. Yahoo intraday map'inin en erken (bugüne ait ilk) noktası —
    //      dünkü kapanışa en yakın değer.
    //   2. Yoksa currentPrice (canlı — genelde intraday map ile aynı
    //      mertebede).
    double? assetSeedTRY(Asset a) {
      double? unitTRY;
      if (a.type == AssetType.altin) {
        final firstTs = goldSlots.keys.isEmpty
            ? null
            : goldSlots.keys.reduce((x, y) => x < y ? x : y);
        if (firstTs != null) {
          // Seed de KALİBRE edilir: else dalındaki `currentPrice` canlı
          // ölçektedir, ikisi ayrışırsa seans öncesi plato ile ilk gerçek
          // slot arasında yapay bir basamak kalırdı.
          unitTRY =
              goldSlots[firstTs]! * goldFactor(a.ticker) * goldKal(a.ticker);
        } else if (a.currentPrice > 0) {
          unitTRY = a.currentPrice;
        }
      } else if (a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          a.type == AssetType.doviz) {
        final map = tickerSlots[a.ticker] ?? {};
        double? unitLocal;
        if (map.isNotEmpty) {
          final firstTs = map.keys.reduce((x, y) => x < y ? x : y);
          unitLocal = map[firstTs];
        } else if (a.currentPrice > 0) {
          unitLocal = a.currentPrice;
        }
        if (unitLocal != null) {
          if (a.currency == 'USD') {
            // Sabit 40.0 yerine: günün ilk kuru → yoksa canlı kur → yoksa
            // seed YOK (varlık ölçülemez sayılır, uydurma fiyat üretilmez).
            final usdSeed = usdTrySlots.isNotEmpty
                ? usdTrySlots[usdTrySlots.keys.reduce((x, y) => x < y ? x : y)]!
                : canliKur();
            unitTRY = usdSeed == null ? null : unitLocal * usdSeed;
          } else {
            unitTRY = unitLocal;
          }
        }
      } else if (a.type == AssetType.fon && a.currentPrice > 0) {
        unitTRY = a.currentPrice;
      } else if (a.currentPrice > 0) {
        unitTRY = a.currentPrice;
      }
      return unitTRY;
    }

    // ── HİÇ fiyatlanamayan varlıklar seriden tamamen çıkarılır ─────────────
    //
    // `assetSeedTRY` null döndüren bir varlık (fiyatı hiç çekilemeyen
    // kurucu-only fon, kaldırılmış sembol, `currentPrice = 0` ile
    // kaydedilmiş bir kayıt) hiçbir slotta değer üretemez.
    //
    // Aşağıdaki "eksik kapsam" elemesi böyle bir varlığı gördüğünde
    // `covered < expected` olur ve slot seriye ALINMAZ. Tek bir
    // fiyatlanamayan varlık, bu yüzden HER slotu düşürüyor ve gün içi
    // grafiği bütünüyle boşaltıyordu — kullanıcı sebebini göremeden
    // "grafik yok / düz" görüyordu.
    //
    // Doğrusu, kapsam sayımının "ölçülebilir portföy" üzerinden yapılması:
    // fiyatlanamayan varlık ne toplama ne de `expected`'a girer. Böylece
    // eleme asıl işini yapmaya devam eder (bir ticker kapanışa doğru veri
    // vermeyi kesince o slot düşer) ama ölçülemeyen bir varlık tüm günü
    // götürmez.
    final olculebilir = <Asset>[
      for (final a in assets)
        if (a.isQuantityNeutral || a.isDeleted || assetSeedTRY(a) != null) a,
    ];

    for (int i = 0; i <= slotCount; i++) {
      final hourDate = dayStart.add(Duration(minutes: i * slotMinutes));
      final hourTs = normalizeSlot(hourDate.millisecondsSinceEpoch);
      // Gelecek slotları çizme — grafik "ŞİMDİ" marker'ında bitsin.
      if (hourTs > nowTs) break;

      double total = 0.0;
      // En az bir varlık için fiyat hesaplanabildiyse slot'u çiz. Bir
      // varlığın hiç fiyatı yoksa (kurucu-only fon, silinmiş sembol vs.)
      // O ASSET'İ yok say — tüm portföyü boşaltma.
      bool anyCovered = false;

      // Bu slotta kaç pozisyon fiyatlanabildi / kaç pozisyon bekleniyor.
      //
      // Slotlar ancak AYNI pozisyon kümesini içeriyorsa karşılaştırılabilir.
      // Kapanışa yakın bazı ticker'lar veri vermeyi keserken diğerleri
      // devam ediyor; o slotta toplam daha AZ pozisyondan oluşuyor ve seri
      // aşağı sıçrayıp bir sonraki slotta geri çıkıyordu (grafikte "W").
      // Bu bir fiyat hareketi değil, EKSİK PORTFÖY.
      var covered = 0;
      var expected = 0;

      // Bu slot'un tür/pozisyon kırılımı. `total`a giren her `v` buraya da
      // girer; slot seriye alınmazsa dağılıma da yazılmaz (aşağıdaki
      // `continue` dalları) — böylece toplamlar ayrışamaz.
      final slotByType = <AssetType, double>{};
      final slotByPosition = <String, double>{};

      // Bu slotta EN AZ BİR varlık gerçek gün içi fiyatla değerlendi mi?
      // Seed (dünkü kapanış proxy'si) gerçek veri sayılmaz — seans
      // açılmadan önceki slotların hepsi seed'dir ve aynı değeri taşır.
      var slotGercekVeri = false;

      // O anda defterde kayıt var mıydı — net miktar sıfır olsa bile.
      // Uzun dönem yolundaki `anyLedger` ile aynı gerekçe: aynı gün alınıp
      // satılan bir pozisyonda her varlık `qty == 0` verir, `anyCovered`
      // hiç true olmaz ve GÜNLÜK grafiği tamamen boş kalırdı.
      bool anyLedger = false;

      // Ölçülemeyen varlıklar burada YOK (bkz. `olculebilir`).
      for (final a in olculebilir) {
        try {
          if (!a.isDeleted &&
              !a.isQuantityNeutral &&
              a.addedDate.millisecondsSinceEpoch <= hourTs) {
            anyLedger = true;
          }
          final qty = signedQtyOnSlot(a, hourTs);
          if (qty == 0) continue;
          expected++;
          double? v;

          if (a.type == AssetType.altin) {
            gunIciBeklenenTurler.add(a.type);
            final gram = pastOrNull(goldSlots, hourTs);
            if (gram != null) {
              v = gram * goldFactor(a.ticker) * goldKal(a.ticker) * qty;
              slotGercekVeri = true;
              gunIciGercekTurler.add(a.type);
            }
          } else if (a.type == AssetType.hisse ||
              a.type == AssetType.emtia ||
              a.type == AssetType.doviz) {
            gunIciBeklenenTurler.add(a.type);
            final map = tickerSlots[a.ticker] ?? {};
            final price = pastOrNull(map, hourTs);
            if (price != null) {
              double p = price;
              var kurVar = true;
              if (a.currency == 'USD') {
                final usdRate = closestOrNull(usdTrySlots, hourTs) ?? canliKur();
                // Kur yoksa slot ATLANIR — altın dalındaki kuralın aynısı.
                if (usdRate == null || usdRate <= 0) {
                  kurVar = false;
                } else {
                  p *= usdRate;
                }
              }
              v = kurVar ? p * qty : null;
              slotGercekVeri = true;
              gunIciGercekTurler.add(a.type);
            }
          }
          // Fon (TEFAS) intraday NAV yayınlamıyor: fiyat günde bir kez
          // değişir. Gün boyu `currentPrice` ile sabit çizmek, fonun
          // GERÇEK günlük değişimini grafikten ve tür dökümünden siliyordu
          // (kullanıcı bildirimi 2026-09-10).
          //
          // Doğrusu bir BASAMAK: gün önceki NAV ile açılır, yayın anında
          // güncel NAV'a atlar. Ara nokta uydurulmaz — fonun gün içinde ara
          // değeri yoktur, olan tek şey bir yayın anıdır.
          //
          // Basamağın yeri `fonBasamakTs` — SABİT bir saat (bkz. o alanın
          // hesabı). Bir önceki sürümde seansın ilk gerçek verisine
          // (`ilkGercekTs`) çapalıydı ve bu, portföyde fondan başka varlık
          // yoksa HİÇ gerçekleşmiyordu: "Fon" türü filtresinde gün boyu
          // önceki NAV çiziliyor, sonra son slotu canlı toplamla ezen
          // hizalama tek noktalık dik bir uçurum bırakıyordu. Uçurum
          // "ŞİMDİ" imlecine yapışık duruyor ve dakikalar geçtikçe onunla
          // birlikte sağa kayıyordu (kullanıcı ekran görüntüsü, 2026-09-10).
          //
          // ## Basamak YALNIZCA o günün NAV'ı yayınlandıysa
          // TEFAS hafta sonu ve tatilde NAV yayınlamıyor. Basamak yine de
          // çizilirse, elde olan SON değişim (örn. Perşembe→Cuma) bugünün
          // hareketiymiş gibi görünüyordu: Pazar günü grafik ve tür dökümü
          // fonlarda −%2,12 gösteriyordu, oysa o Cuma'nın hareketiydi
          // (kullanıcı bildirimi 2026-09-13; TEFAS'tan ölçüldü — AFT son
          // iki NAV 10 Eyl 1,022627 → 11 Eyl 1,000902 = −%2,12, ekrandaki
          // rakamla birebir).
          //
          // Üstelik aynı ekranda "altın için gün içi veri alınamadı, sabit
          // çizildi" uyarısı duruyordu: iki ifade çelişiyordu.
          //
          // Yayın günü çizilen günle uyuşmuyorsa fon SABİT çizilir ve tür
          // dökümünde "—" görünür — piyasa kapalıyken doğru olan budur.
          //
          // ## İKİNCİ koşul: çizilen seans BUGÜN olmalı
          // Yalnızca yayın gününe bakmak YETMEDİ (kullanıcı bildirimi
          // 2026-09-13, ikinci kez). Sebep: `dayStart` bugün değil, SON
          // SEANS. Pazar günü `seansGunu` Cuma'yı döndürüyor ve TEFAS'ın
          // son NAV'ı da Cuma; iki tarih uyuşuyor, kapı açılıyor ve
          // basamak `dayStart + 10:00` = Cuma 10:00'a düşüyordu. Eksen
          // Cuma'dan Pazar'a uzandığı için bu, grafiğin SOL UCUNDA dik bir
          // uçurum olarak görünüyordu.
          //
          // Cuma'nın NAV hareketi Cuma'ya aittir — yanlış olan hareketin
          // kendisi değil, KAPANMIŞ bir seansın içine bugünün canlı ucunu
          // bağlayan melez seri. Geçmiş seans çizilirken fon sabit çizilir;
          // basamak yalnızca seans bugünse "şu an itibarıyla" diye okunur.
          final navGunu = fonSonNavGunu[a.ticker];
          final navBugunMu = !gecmisSeans &&
              navGunu != null &&
              navGunu.year == dayStart.year &&
              navGunu.month == dayStart.month &&
              navGunu.day == dayStart.day;
          if (v == null && a.type == AssetType.fon && a.currentPrice > 0) {
            v = gunIciFonBirimFiyati(
                  guncelNav: a.currentPrice,
                  // NAV bugüne ait değilse basamak YOK: `oncekiNav` null
                  // verilince fonksiyon sabit çiziyor.
                  oncekiNav: navBugunMu ? fonOncekiNav[a.ticker] : null,
                  slotTs: hourTs,
                  basamakTs: fonBasamakAni(
                    dayStart: dayStart,
                    nowTs: nowTs,
                    varsayilanTs: fonBasamakTs,
                    gozlem: fonGozlemler[tefasKodu(a.ticker)],
                    normalizeSlot: normalizeSlot,
                  ),
                ) *
                qty;
          }
          // Intraday verisi henüz gelmemiş varlıklar için seed fiyatı
          // kullan — grafik dik sıçramasın.
          if (v == null) {
            final seed = assetSeedTRY(a);
            if (seed != null) {
              v = seed * qty;
            }
          }

          if (v != null) {
            total += v;
            slotByType[a.type] = (slotByType[a.type] ?? 0) + v;
            final pk = positionKey(a);
            slotByPosition[pk] = (slotByPosition[pk] ?? 0) + v;
            positionType[pk] = a.type;
            anyCovered = true;
            covered++;
          }
        } catch (_) {
          // Bu asset hesaplanamadı, diğerlerine devam et.
        }
      }

      // Sıfır da bir ölçümdür: portföy o an VARDI ve değeri sıfırdı.
      if (!anyCovered && !anyLedger) continue;
      // Negatif toplam kırpılırsa dağılım da düşer — aksi halde
      // `Σ byType != total` olur (aynı kural günlük seride de var).
      if (total < 0) {
        total = 0;
        slotByType.clear();
        slotByPosition.clear();
      }

      // EKSİK KAPSAMLI slot seriye GİRMEZ.
      //
      // Portföyün bir kısmı fiyatlanamadıysa bu slot diğerleriyle aynı
      // şeyi ölçmüyor demektir; grafiğe koymak "portföyüm düştü" yalanını
      // söyler. Slotu atlamak doğru davranıştır: çizgi bir önceki gerçek
      // noktadan bir sonrakine gider ve gün içi hareketi olduğu gibi
      // anlatır.
      //
      // `expected` sıfırsa (o an hiç pozisyon yok) bölme yapılmaz.
      if (expected > 0 && covered < expected) continue;

      if (slotGercekVeri) ilkGercekTs ??= hourTs;

      groupedPoints[hourTs] = total;
      for (final e in slotByType.entries) {
        (byType[e.key] ??= <int, double>{})[hourTs] = e.value;
      }
      for (final e in slotByPosition.entries) {
        (byPosition[e.key] ??= <int, double>{})[hourTs] = e.value;
      }
    }

    // ── Seri GÜNÜN 00:00'ından başlar ───────────────────────────────────────
    //
    // Borsa 10:00'da açılır; 00:00–10:00 arasındaki slotlar seed fiyatıyla
    // (bugünkü ilk gerçek fiyatın proxy'si) doldurulur ve aynı değeri
    // taşır — yani seans öncesi düz bir platodur.
    //
    // Bu plato bir ara SİLİNİYORDU ("gerçek hareket sağa sıkışıyor"
    // gerekçesiyle). Sonuç kullanıcı tarafında daha kötüydü: X ekseni
    // 00:00'da başlıyor ama çizgi grafiğin ortasından, ~%42'sinden
    // başlıyordu; solda kocaman boş bir alan kalıyordu. Kullanıcının
    // isteği açık: "GÜNLÜK seçildiğinde 00:00'dan başlayarak gözükmeli"
    // (2026-09-10).
    //
    // Platonun "her şeyi düz gösterme" riski BAŞKA bir yerde çözüldü:
    // gün içi Y ekseninin asgari bandı %8'den %0,5'e indi
    // (`gunIciAsgariBantOrani`), yani seans hareketi plato yanında da
    // okunaklı kalıyor. Kalan düzlük gerçekten veri yokluğuysa bunu
    // `gunIciVerisiYokTurler` notu söylüyor.
    //
    // `ilkGercekTs` artık yalnızca fonun NAV basamağını konumlandırmak
    // için kullanılıyor (bkz. yukarıdaki fon dalı).

    // Son slotu anlık portföy toplamı ile hizala — grafiğin bitiş noktası
    // her zaman ana ekrandaki toplamla eşleşsin. currentPrice=0 olan
    // varlıklar (kurucu-fon vs.) hesap dışı, diğerleri toplama girer.
    if (groupedPoints.isNotEmpty) {
      // Canlı toplam TÜR VE POZİSYON BAZINDA hesaplanır — tek bir toplam
      // çarpanı YETMEZ.
      //
      // Önce toplam ezilip dağılım `liveTotal / before` oranıyla ölçekleniyordu.
      // Bu, bir türdeki hareketi TÜM türlere yayıyordu: altın %2 düşünce
      // fiyatı hiç değişmemiş fon da ekranda düşmüş görünüyordu
      // (ölçüldü: fon 25.000 → 16.716, oysa fon fiyatı sabitti).
      // Kullanıcının gördüğü "alttaki satırlar üsttekiyle senkron değil"
      // şikâyetinin kaynağı buydu — toplam tutuyordu ama satırlar yalandı.
      //
      // Doğrusu: her varlığın canlı değerini kendi türüne/pozisyonuna yazmak.
      // Toplam yine `Σ tür` olur, ama her tür KENDİ gerçek değerini taşır.
      double liveTotal = 0.0;
      final liveByType = <AssetType, double>{};
      final liveByPosition = <String, double>{};
      for (final a in assets) {
        if (a.isDeleteLog) continue;
        final qty = signedQtyOnSlot(a, nowTs);
        if (qty == 0) continue;
        if (a.currentPrice <= 0) continue;
        // Ekrandaki TL karşılığıyla AYNI kur (bkz. `canliKur`).
        final liveUsd = canliKur() ??
            (usdTrySlots.isNotEmpty ? usdTrySlots.values.last : null);
        if (a.currency == 'USD' && (liveUsd == null || liveUsd <= 0)) continue;
        final tryPrice =
            a.currency == 'USD' ? a.currentPrice * liveUsd! : a.currentPrice;
        final v = tryPrice * qty;
        liveTotal += v;
        liveByType[a.type] = (liveByType[a.type] ?? 0) + v;
        final pk = positionKey(a);
        liveByPosition[pk] = (liveByPosition[pk] ?? 0) + v;
        positionType[pk] = a.type;
      }
      if (liveTotal > 0) {
        final lastKey = groupedPoints.keys.reduce((a, b) => a > b ? a : b);
        groupedPoints[lastKey] = liveTotal;
        // Son slotta dağılımı canlı değerlerle DEĞİŞTİR (ölçekleme değil).
        // `liveTotal == Σ liveByType` olduğu için değişmez korunur.
        for (final e in liveByType.entries) {
          (byType[e.key] ??= <int, double>{})[lastKey] = e.value;
        }
        for (final e in liveByPosition.entries) {
          (byPosition[e.key] ??= <int, double>{})[lastKey] = e.value;
        }
        // Canlı hesapta yer almayan (currentPrice<=0) tür/pozisyon son
        // slotta ARTIK YOK — eski ham değeri bırakmak toplamı şişirirdi.
        for (final e in byType.entries) {
          if (!liveByType.containsKey(e.key)) e.value.remove(lastKey);
        }
        for (final e in byPosition.entries) {
          if (!liveByPosition.containsKey(e.key)) e.value.remove(lastKey);
        }
      }
    }

    // Outlier smoothing — GÜNLÜK seride olanın gün içi karşılığı
    // (bkz. `getPortfolioHistory` sonundaki aynı blok).
    //
    // Yahoo bazı sembollerde tek bir 5 dakikalık slotu eksik/geç
    // döndürüyor. `pastOrNull` o slot için bir önceki fiyatı taşıyamadığında
    // pozisyon anlık olarak eksik hesaplanıyor ve seri tek noktalık bir
    // "V" çiziyor: aşağı iner, hemen geri çıkar. Gerçek bir fiyat hareketi
    // değil, veri artefaktı.
    //
    // Günlük seri bunu zaten temizliyordu; gün içi seri temizlemiyordu ve
    // artefakt widget grafiğinde dikey bir sıçrama olarak görünüyordu
    // (uygulamanın GÜNLÜK sekmesinde görünmeyen bir sıçrama).
    //
    // Eşikler gün içi ölçeğe göre DARALTILDI: günlük seride %1,5 sapma
    // anlamlıyken 5 dakikalık bir slotta portföyün %0,3'ü bile büyük bir
    // harekettir. Komşular arası fark %0,2'den azsa (yani gerçek bir trend
    // yoksa) ortadaki nokta iki komşunun ortalamasına çekilir.
    final smoothed = <int, double>{};
    smoothSpikes(groupedPoints,
        deviation: 0.003, neighborGap: 0.002, changed: smoothed);
    // Düzeltilen slot'larda dağılımı da aynı oranda ölçekle (bkz. `changed`).
    for (final ts in smoothed.keys) {
      final before = smoothed[ts]!;
      if (before <= 0) continue;
      final factor = groupedPoints[ts]! / before;
      for (final series in byType.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
      for (final series in byPosition.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
    }

    return PortfolioHistoryBreakdown(
      total: groupedPoints,
      byType: byType,
      byPosition: byPosition,
      positionType: positionType,
      // Ekran X eksenini bu güne göre kurar; bugün olmak ZORUNDA değil
      // (hafta sonu/tatil → son seans günü).
      seansGunu: dayStart,
      // Kapanıştan sonraki kuyruk: gerçek işlem değil, son fiyatın
      // taşınması. Ekran bu damgadan sonrasını gri/kesikli çizer.
      piyasaKapaliBaslangicTs: piyasaKapaliTs,
      // Gün içi fiyatı beklenen ama HİÇ alınamayan türler. Grafikte bu
      // türler sabit çizilir; kullanıcı "piyasa mı durgun, veri mi yok"
      // sorusunu ancak bu bilgi yüzeye çıkarsa yanıtlayabilir.
      gunIciVerisiYokTurler:
          gunIciBeklenenTurler.difference(gunIciGercekTurler),
    );
  }

  // ── Tier-bazlı çözünürlük (zoom-aware) ────────────────────────────────────
  //
  // Cache: (tier, sembol) → ts→price map. Aynı tier+sembol tekrar istenirse
  // ağa çıkılmaz. Farklı tier'da aynı sembol için ayrı istek (Yahoo interval
  // farklı olduğundan).
  final Map<String, Map<int, double>> _tierCache = {};
  final Map<String, DateTime> _tierCacheAt = {};

  /// Tier önbelleğinde tutulacak azami giriş sayısı.
  ///
  /// Tier sayısı 4'ten 6'ya çıktı (1dk/15dk eklendi) ve her tier aynı sembol
  /// için AYRI bir giriş tutuyor — üst sınır olmadan gezinen kullanıcıda
  /// sembol × 6 seri birikir. `_cache`in (`_cacheMaxEntries = 50`) zaten
  /// uyguladığı disiplinin aynısı.
  static const _tierCacheMaxEntries = 60;

  String _tierCacheKey(ResolutionTier tier, String symbol) =>
      '${tier.name}::$symbol';

  /// Önbellek girişi hâlâ taze mi?
  ///
  /// **TTL = bar süresi.** Bardan daha sık tazelemek AYNI barı yeniden
  /// çekmektir: ağ harcar, ekranda hiçbir şey değişmez. Tersi de bozuk —
  /// 1 dakikalık bar 15 dakika önbellekte tutulursa grafiğin GÖVDESİ donar
  /// ve yalnızca canlı uç kıpırdar ("gün içi grafik dümdüz" hissi,
  /// `_intradayCacheTtl` yorumunda kayıtlı).
  ///
  /// Günlük/haftalık barlarda tavan 15 dakika: kapanış verisi gün içinde
  /// değişmez, bir günlük TTL ise fiyat düzeltmelerini kaçırırdı.
  bool _tierCacheTaze(String key, ResolutionTier tier) {
    final at = _tierCacheAt[key];
    if (at == null) return false;
    final ttl = tier.barSuresi < const Duration(minutes: 15)
        ? tier.barSuresi
        : const Duration(minutes: 15);
    return DateTime.now().difference(at) < ttl;
  }

  Future<Map<int, double>> _fetchTickerAtTier(
      String ticker, ResolutionTier tier) async {
    final key = _tierCacheKey(tier, ticker);
    final cached = _tierCache[key];
    if (cached != null && _tierCacheTaze(key, tier)) return cached;
    try {
      final pts = await PriceService.instance
          .fetchHistoryAtInterval(ticker, tier.yahooRange, tier.yahooInterval);
      final map = <int, double>{};
      for (final p in pts) {
        map[tier.normalizeTs(p.$1)] = p.$2;
      }
      // Yeniden ekle: `Map` ekleme sırasını korur, bu yüzden var olan
      // anahtarı önce SİLMEZSEK LRU sırası güncellenmez ve sık kullanılan
      // bir giriş en eski sayılıp atılabilir.
      _tierCache.remove(key);
      _tierCacheAt.remove(key);
      _tierCache[key] = map;
      _tierCacheAt[key] = DateTime.now();
      while (_tierCache.length > _tierCacheMaxEntries) {
        final enEski = _tierCache.keys.first;
        _tierCache.remove(enEski);
        _tierCacheAt.remove(enEski);
      }
      return map;
    } catch (_) {
      // Bayat da olsa elde bir seri varsa onu döndür: boş grafik, eski
      // grafikten kötüdür (ağ hatası geçicidir).
      return cached ?? {};
    }
  }

  /// Verilen tarih aralığında ve tier'da portföy toplam değeri (TRY) döner.
  /// Zoom yaptıkça viewport daralır → tier ince olur → daha detaylı nokta.
  /// [assets] tüm buy/sell lot'ları içerir (deleteLog hariç filtrelenir).
  Future<Map<int, double>> getPortfolioHistoryAtResolution({
    required List<Asset> assets,
    required DateTime from,
    required DateTime to,
    required ResolutionTier tier,
    bool simulate = false,
  }) async =>
      (await getPortfolioHistoryBreakdownAtResolution(
        assets: assets,
        from: from,
        to: to,
        tier: tier,
        simulate: simulate,
      ))
          .total;

  /// [getPortfolioHistoryAtResolution] ile AYNI hesap — ek olarak her slot'un
  /// tür bazında dağılımını da döndürür.
  ///
  /// ## Neden tek fonksiyon
  /// Tür dökümü eskiden ayrı bir `getPortfolioHistory` çağrısıyla, tür başına
  /// bağımsız hesaplanıyordu. İki hesap farklı pencere, farklı tier ve farklı
  /// "kapsanan slot" kümesi ürettiği için **türlerin toplamı üst kartın
  /// toplamını tutmuyordu** (kullanıcı yakaladı, 2026-09-01).
  ///
  /// Burada dağılım, toplamı üreten döngünün İÇİNDE biriktirilir:
  /// `total[ts] == Σ byType[t]![ts]` her slot için **yapısal olarak** doğrudur
  /// — iki ayrı kod yolunun tesadüfen aynı sonucu vermesine bel bağlanmaz.
  /// Bir slot toplama giriyorsa dağılımına da girer; girmiyorsa ikisinde de
  /// yoktur.
  Future<PortfolioHistoryBreakdown> getPortfolioHistoryBreakdownAtResolution({
    required List<Asset> assets,
    required DateTime from,
    required DateTime to,
    required ResolutionTier tier,
    bool simulate = false,
  }) async {
    if (assets.isEmpty) return const PortfolioHistoryBreakdown.empty();

    final normalizedFrom = tier.normalizeTs(from.millisecondsSinceEpoch);
    final normalizedTo = tier.normalizeTs(to.millisecondsSinceEpoch);
    final nowTs = tier.normalizeTs(DateTime.now().millisecondsSinceEpoch);

    // Gerekli sembolleri tespit et.
    final bool needsGold = assets.any((a) => a.type == AssetType.altin);
    final bool needsUsd = assets.any((a) => a.currency == 'USD') || needsGold;

    final tickerFutures = <String, Future<Map<int, double>>>{};
    for (final a in assets) {
      if (!a.isBuy) continue;
      if (a.quantity <= 0) continue;
      final fetchable = a.type == AssetType.hisse ||
          a.type == AssetType.emtia ||
          (a.type == AssetType.doviz && a.ticker.isNotEmpty) ||
          (a.type == AssetType.fon && a.ticker.isNotEmpty);
      if (!fetchable) continue;
      tickerFutures.putIfAbsent(
          a.ticker, () => _fetchTickerAtTier(a.ticker, tier));
    }
    Future<Map<int, double>>? usdFuture;
    Future<Map<int, double>>? goldFuture;
    Future<Map<int, double>>? goldTryFuture;
    if (needsUsd) usdFuture = _fetchTickerAtTier(FiyatKaynagi.usdTry, tier);
    if (needsGold) goldFuture = _fetchTickerAtTier(FiyatKaynagi.xauUsd, tier);
    // Spot altın ÖNCE denenir (bkz. `altinGramSerisi`); bu yol eskiden
    // yalnızca vadeliyi (`GC=F`) tanıyordu.
    if (needsGold) goldTryFuture = _fetchTickerAtTier(FiyatKaynagi.xauTry, tier);

    // Paralel bekle.
    await Future.wait([
      ...tickerFutures.values,
      if (usdFuture != null) usdFuture,
      if (goldFuture != null) goldFuture,
      if (goldTryFuture != null) goldTryFuture,
    ]);

    final tickerMaps = <String, Map<int, double>>{};
    for (final entry in tickerFutures.entries) {
      tickerMaps[entry.key] = await entry.value;
    }
    final usdMap = kurSerisiniHizala(
        usdFuture != null ? await usdFuture : <int, double>{}, canliKur());
    final xauMap = goldFuture != null ? await goldFuture : <int, double>{};
    final xauTryMap =
        goldTryFuture != null ? await goldTryFuture : <int, double>{};

    // XAU → gram22k TRY seri. Merdiven ve kur kuralı `altinGramSerisi`'nde:
    // burada duran `?? 40.0` varsayılanı, kur serisi boş döndüğünde altını
    // gerçek kurdan sapan uydurma bir fiyata oturtuyordu.
    final altinSonuc = altinGramSerisi(
      xauTry: xauTryMap,
      xauUsd: xauMap,
      usdTry: usdMap,
      kurBul: (kur, ts) => _closestOrNull(kur, ts),
    );
    final goldMap = altinSonuc.seri;
    debugSonAltinKaynagi = altinSonuc.kaynak;

    // Ağırlık tablosu `PriceService`'te tutulur; buradaki yerel kopya
    // ALTIN_RESAT'ı ATLIYORDU (tabloda 7.216 ile var ama switch'te yoktu),
    // yani Reşat altını grafikte gram altın gibi çiziliyor ve pozisyon
    // 7.216 kat düşük görünüyordu.
    double goldFactor(String ticker) => PriceService.goldWeightFactor(ticker);

    // Altın serisi CANLI ölçeğe kalibre edilir — gerekçe `altinKalibrasyonu`
    // dokümantasyonunda. Bu yolun serisini performans ekranı çiziyor ve son
    // noktayı `currentTotalOverride` ile canlı toplama sabitliyor; kalibrasyon
    // olmadan altın ağırlıklı portföyde sağ uçta yapay bir basamak kalırdı.
    final altinKalibre =
        altinKalibrasyonHaritasi(assets: assets, gramSerisi: goldMap);
    double goldKal(String ticker) => altinKalibre[ticker] ?? 1.0;

    // Signed quantity per slot
    double signedQtyOnSlot(Asset a, int slotTs) {
      // Temettü nakit hareketidir, miktara girmez. deleteLog da mezar taşı.
      // Bu satır olmadan aşağıdaki `isSell ? -q : +q` temettüyü alım sayardı.
      if (a.isQuantityNeutral) return 0.0;
      // Yumuşak silinmiş lot grafiğe girmez: silinen varlık "hiç olmamış"
      // sayılır. Kayıt ledger'da durur (hareket geçmişi için) ama miktarı
      // hiçbir günde sayılmaz.
      if (a.isDeleted) return 0.0;
      if (simulate) return a.isSell ? -a.quantity : a.quantity;
      // slotTs tier bucket başlangıcı. Bir varlığın o slot'ta olabilmesi
      // için addedDate <= slotTs olmalı — böylece slot başlangıcından SONRA
      // alınan varlık (örn. çarşamba alım vs pazartesi slot) o slot'a
      // dahil edilmez, bir sonraki bucket'a girer. Yanlış "erken katılım"
      // grafiği geçmişte yapay yükseltirdi.
      final addedMs = a.addedDate.millisecondsSinceEpoch;
      if (addedMs > slotTs) return 0.0;
      return a.isSell ? -a.quantity : a.quantity;
    }

    // Grid: from..to arası tier step'inde tüm slot'lar
    final result = <int, double>{};
    // Tür ve pozisyon dağılımı — `result` ile AYNI döngüde birikir
    // (bkz. sınıf notu). Ayrı bir geçişte hesaplanırsa toplamlar ayrışır.
    final byType = <AssetType, Map<int, double>>{};
    final byPosition = <String, Map<int, double>>{};
    final positionType = <String, AssetType>{};
    final stepMs = _tierStepMs(tier);
    int cursor = normalizedFrom;
    while (cursor <= normalizedTo) {
      // Gelecek slotları atla
      if (cursor > nowTs) break;
      // Haftalık intraday'de hafta sonu atla (Cts/Paz)
      if (tier == ResolutionTier.hourly) {
        final wd = DateTime.fromMillisecondsSinceEpoch(cursor).weekday;
        if (wd == DateTime.saturday || wd == DateTime.sunday) {
          cursor += stepMs;
          continue;
        }
      }

      double total = 0.0;
      bool anyCovered = false;
      // Bu slot'ta portföyde HİÇ kayıt var mıydı? (net miktar sıfır olsa
      // bile). `anyCovered`'dan farkı: o "fiyatlanabilir pozisyon bulundu"
      // der, bu "o tarihte bir portföy vardı" der.
      //
      // **Neden gerekli (kullanıcı bildirimi, 2026-09-16):** portföyün
      // tamamı satıldığında her varlık için `qty == 0` oluyor, hiçbiri
      // `anyCovered`'ı true yapmıyor ve SLOT SERİYE HİÇ GİRMİYORDU. Grafik
      // satış gününden önce bitiyor, son değerde asılı kalıyordu — ölçüldü:
      // seri 14.09'da ₺330.804'te bitmiş, satışın yapıldığı 16.09 slotu
      // yok. Kullanıcı "varlığımın 0'a indiğini görmüyorum" dedi; haklıydı,
      // düşüş çizilmiyordu çünkü o gün seride yoktu.
      bool anyLedger = false;
      // Bu slot'un tür ve pozisyon kırılımı. `total`a giren her `v` ikisine
      // de girer — tek yerden beslendikleri için toplamları ayrışamaz.
      final slotByType = <AssetType, double>{};
      final slotByPosition = <String, double>{};
      for (final a in assets) {
        // Defterde o tarihte kayıt var mı — miktarı sıfırlanmış olsa bile.
        // Silinmiş ve miktar-nötr (temettü/mezar taşı) satırlar sayılmaz:
        // ilki "hiç olmamış", ikincisi zaten miktar taşımıyor.
        if (!a.isDeleted &&
            !a.isQuantityNeutral &&
            a.addedDate.millisecondsSinceEpoch <= cursor) {
          anyLedger = true;
        }
        final qty = signedQtyOnSlot(a, cursor);
        if (qty == 0) continue;
        double? v;
        if (a.type == AssetType.altin) {
          // Altın için _pastOrNull yerine _closestOrNull — cursor'dan önce
          // veri yoksa serinin en yakın gelecek noktasına düş. Böylece yeni
          // eklenmiş bir altın için düz plato + dik sıçrama olmaz.
          final gram = _closestOrNull(goldMap, cursor);
          if (gram != null) {
            v = gram * goldFactor(a.ticker) * goldKal(a.ticker) * qty;
          }
        } else if (a.type == AssetType.hisse ||
            a.type == AssetType.emtia ||
            a.type == AssetType.doviz ||
            a.type == AssetType.fon) {
          final map = tickerMaps[a.ticker] ?? {};
          final price = _closestOrNull(map, cursor);
          if (price != null) {
            double p = price;
            var kurVar = true;
            if (a.currency == 'USD') {
              final usdRate = _closestOrNull(usdMap, cursor) ?? canliKur();
              if (usdRate == null || usdRate <= 0) {
                kurVar = false;
              } else {
                p *= usdRate;
              }
            }
            v = kurVar ? p * qty : null;
          }
        }
        // Son çare: canlı fiyat (Yahoo serisi tamamen boşsa). Bunun yerine
        // artık nadiren buraya düşülür çünkü _closestOrNull mevcut serideki
        // herhangi bir noktayı bulur.
        if (v == null && a.currentPrice > 0) {
          // Sabit 40.0 kaldırıldı: USD kote varlık ancak gerçek bir kur
          // varken seed'lenir, yoksa o slotta ölçülemez sayılır.
          final kur = a.currency == 'USD' ? canliKur() : null;
          if (a.currency != 'USD') {
            v = a.currentPrice * qty;
          } else if (kur != null && kur > 0) {
            v = a.currentPrice * kur * qty;
          }
        }
        // Bir asset için hiç fiyat yoksa (kurucu-fon YLB(0.00) gibi) O
        // ASSET'İ o slot'ta yok say — diğer varlıklar toplama girmeye devam
        // etsin. Aksi halde tek eksik varlık için tüm grafik boş kalır.
        if (v == null) continue;
        total += v;
        slotByType[a.type] = (slotByType[a.type] ?? 0) + v;
        // Aynı ürünün farklı lot'ları tek satırda toplanır (ekrandaki
        // pozisyon kavramıyla aynı), ama SAHİP ayrımı korunur: `positionKey`
        // sahip taşımadığı için burada ortakların aynı hissesi tek satıra
        // düşer — bu kart zaten sekme başına ayrı çizilir, sekme içinde
        // birleşmeleri doğrudur.
        final pk = positionKey(a);
        slotByPosition[pk] = (slotByPosition[pk] ?? 0) + v;
        positionType[pk] = a.type;
        anyCovered = true;
      }
      // `anyLedger` tek başına da yeter: o tarihte portföy VARDI ve net
      // değeri sıfırdı. Sıfır bir ölçümdür, ölçüm yokluğu değil — grafik
      // düşüşü çizebilmeli.
      if (anyCovered || anyLedger) {
        // Negatif toplam kırpılırsa dağılım da AYNI ORANDA kırpılmalı;
        // aksi halde `Σ byType != total` olur ve tür dökümü üst kartı
        // tutmaz. Pratikte buraya nadiren düşülür (satış lot'ları alımı
        // aşarsa), ama değişmez koşulsuz korunmalı.
        if (total < 0) {
          total = 0;
          slotByType.clear();
          slotByPosition.clear();
        }
        result[cursor] = total;
        for (final e in slotByType.entries) {
          (byType[e.key] ??= <int, double>{})[cursor] = e.value;
        }
        for (final e in slotByPosition.entries) {
          (byPosition[e.key] ??= <int, double>{})[cursor] = e.value;
        }
      }
      cursor += stepMs;
    }

    // Outlier smoothing: tek nokta V-dip artefaktları (Yahoo veri gecikmesi
    // veya eksik slot) yumuşat. Komşu iki nokta birbirine yakınken ortadaki
    // >%1.5 sapıyorsa yerine ortalama koy.
    //
    // Düzeltilen slot'lar geri bildirilir: smoothing YALNIZCA `result`u
    // değiştirir, dağılıma dokunmazsa `Σ byType != total` olur ve tür dökümü
    // üst kartı tutmaz. Aşağıda dağılım aynı oranda ölçeklenir.
    final smoothed = _smoothOutliers(result);
    for (final ts in smoothed.keys) {
      final before = smoothed[ts]!;
      final after = result[ts]!;
      // Sıfırdan ölçeklenemez; o slot'ta dağılım zaten anlamsızdır.
      if (before <= 0) continue;
      final factor = after / before;
      for (final series in byType.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
      for (final series in byPosition.values) {
        final v = series[ts];
        if (v != null) series[ts] = v * factor;
      }
    }

    return PortfolioHistoryBreakdown(
      total: result,
      byType: byType,
      byPosition: byPosition,
      positionType: positionType,
    );
  }

  /// In-place outlier smoothing — tek nokta V-dip / N-tepe artefaktlarını
  /// komşuların ortalamasıyla değiştirir. Gerçek trendleri (komşular arası
  /// da büyük fark) korur.
  /// Değiştirilen slot'ları `ts → ÖNCEKİ değer` olarak döndürür. Çağıran bu
  /// bilgiyle tür dağılımını aynı oranda ölçekler; aksi halde toplam düzeltilip
  /// dağılım ham kalır ve `Σ byType != total` olur.
  Map<int, double> _smoothOutliers(Map<int, double> points) {
    final changed = <int, double>{};
    if (points.length < 3) return changed;
    final keys = points.keys.toList()..sort();
    for (int i = 1; i < keys.length - 1; i++) {
      final prev = points[keys[i - 1]]!;
      final cur = points[keys[i]]!;
      final next = points[keys[i + 1]]!;
      if (prev <= 0 || next <= 0) continue;
      final devPrev = ((cur - prev) / prev).abs();
      final devNext = ((cur - next) / next).abs();
      final prevNextGap = ((next - prev) / prev).abs();
      if (devPrev > 0.015 && devNext > 0.015 && prevNextGap < 0.01) {
        changed[keys[i]] = cur;
        points[keys[i]] = (prev + next) / 2;
      }
    }
    return changed;
  }

  /// Tier'ın bar adımı (ms).
  ///
  /// [ResolutionTierMeta.barSuresi]'ye DELEGE eder. Eskiden burada ikinci bir
  /// merdiven vardı ve yeni bir tier eklendiğinde sessizce eksik kalırdı —
  /// "iki merdiven tutmak" bu projede tekrar eden hata sınıfı.
  int _tierStepMs(ResolutionTier tier) => tier.barSuresi.inMilliseconds;

  /// Sıralı anahtar indeksi (identity-keyed).
  ///
  /// `_pastOrNull` slot × varlık kombinasyonu başına bir kez çağrılır —
  /// 1 yıllık haftalık grafikte 20 varlıkla binlerce çağrı eder. Eskiden her
  /// çağrı `map.keys.toList()..sort()` yapıyordu: O(n log n) sıralama +
  /// O(n) doğrusal tarama, hep AYNI değişmeyen map üstünde. Grafiğin
  /// "ağ beklemiyorken bile" saniyelerce takılmasının sebebi buydu.
  ///
  /// Fiyat serisi map'leri `_tierCache` içinde immutable tutulur, bu yüzden
  /// sıralı anahtar listesi map nesnesi başına bir kez üretilip
  /// önbelleğe alınabilir. `Expando` kullanıyoruz: map çöp toplandığında
  /// indeks de gider, elle invalidasyon gerekmez.
  static final Expando<List<int>> _sortedKeysCache = Expando<List<int>>();

  static List<int> _sortedKeys(Map<int, double> map) {
    final cached = _sortedKeysCache[map];
    if (cached != null) return cached;
    final keys = map.keys.toList()..sort();
    _sortedKeysCache[map] = keys;
    return keys;
  }

  /// [keys] içinde `<= targetTs` olan EN BÜYÜK indeksi bulur; yoksa -1.
  /// Doğrusal tarama yerine ikili arama — O(log n).
  @visibleForTesting
  static int floorIndexForTest(List<int> keys, int targetTs) =>
      _floorIndex(keys, targetTs);

  static int _floorIndex(List<int> keys, int targetTs) {
    int lo = 0, hi = keys.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (keys[mid] <= targetTs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  double? _pastOrNull(Map<int, double> map, int targetTs) {
    if (map.isEmpty) return null;
    final exact = map[targetTs];
    if (exact != null) return exact;
    final keys = _sortedKeys(map);
    final idx = _floorIndex(keys, targetTs);
    return idx < 0 ? null : map[keys[idx]];
  }

  /// pastOrNull null döndüyse "en yakın ileri nokta" ile fallback. Böylece
  /// eski tarihlere sabit 40.0 kur atamak yerine serinin en yakın gerçek
  /// değerini kullanırız → grafik ani sıçrama üretmez.
  double? _closestOrNull(Map<int, double> map, int targetTs) {
    final past = _pastOrNull(map, targetTs);
    if (past != null) return past;
    if (map.isEmpty) return null;
    return map[_sortedKeys(map).first];
  }

  /// Bir kısmi tier'ın cache'ini temizle (invalidate). Debug için.
  void clearTierCache() {
    _tierCache.clear();
  }

  // ── Tek varlık geçmişi (karşılaştırma altyapısı) ──────────────────────────
  //
  // Buradan aşağısı PORTFÖYDEN BAĞIMSIZDIR: kullanıcının sahip olmadığı bir
  // varlığın geçmişini de çeker. "THYAO alsaydım ne olurdu?" sorusunu
  // yanıtlayan karşılaştırma ekranının veri katmanı.
  //
  // `getPortfolioHistory` ile arasındaki fark özet olarak:
  //   portföy  → miktar × fiyat, lot geçmişi, TL toplam
  //   buradaki → yalnızca FİYAT serisi, miktar kavramı yok
  //
  // Bu ayrım bilinçli: karşılaştırmada "ne kadarım vardı" sorusu anlamsızdır
  // (kullanıcı o varlığa hiç sahip olmamış olabilir), sorulan şey saf getiri.

  /// Tek bir sembolün TRY cinsinden fiyat serisini döner.
  ///
  /// Dönen map: `{ UNIX_MILLIS: TRY_FIYAT }` — boş map "veri yok" demektir
  /// (ağ hatası ya da tanınmayan sembol); çağıran taraf bunu grafik çizmeme
  /// kararına çevirmelidir.
  ///
  /// **Para birimi:** USD kote semboller (ör. `AAPL`) o günün USD/TRY kuruyla
  /// çevrilir — sabit bugünkü kur değil. Aksi halde geçmiş getiri, kurdaki
  /// hareketi hisseye mal ederdi.
  ///
  /// **Altın:** `ALTIN_*` sembolleri XAU/USD serisinden 22 ayar gram TRY'ye
  /// çevrilir ve ürün ağırlığıyla (çeyrek, yarım...) ölçeklenir.
  Future<Map<int, double>> getSymbolHistory(
    String symbol, {
    required int periodDays,
  }) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return {};

    final tier = tierForPeriod(periodDays);
    final range = rangeForPeriod(periodDays);

    // Interval'i KATMAN belirler, range değil. Eskiden interval
    // `PriceService._intervalFor(range)`'dan türüyordu ve katmanla
    // çelişebiliyordu: `days<=2` beş dakikalık bucket isterken ağdan saatlik
    // veri geliyordu. Tek karar noktası olsun diye interval açıkça geçilir.
    Future<Map<int, double>> series(String s) async =>
        _normalized(await _fetchSafe(s, range, tier.yahooInterval), tier);

    // Altın: spot (`XAUTRY=X`) → yoksa vadeli (`GC=F` × `USDTRY=X`) →
    // 22 ayar gram → ürün ağırlığı. Merdiven `altinGramSerisi`'nde: bu yol da
    // yalnızca vadeliyi tanıyordu, yani takip listesi ile portföy grafiği
    // aynı altını iki ayrı ölçekte gösterebiliyordu.
    if (sym.startsWith('ALTIN_')) {
      final results = await Future.wait([
        series(FiyatKaynagi.xauTry),
        series(FiyatKaynagi.xauUsd),
        series(FiyatKaynagi.usdTry).then((m) => kurSerisiniHizala(m, canliKur())),
      ]);
      final weight = PriceService.goldWeightFactor(sym);
      final sonuc = altinGramSerisi(
        xauTry: results[0],
        xauUsd: results[1],
        usdTry: results[2],
        kurBul: (kur, ts) => _closestOrNull(kur, ts),
      );
      debugSonAltinKaynagi = sonuc.kaynak;
      final out = <int, double>{
        for (final e in sonuc.seri.entries) e.key: e.value * weight,
      };
      // Kırpma ÇEVRİMDEN SONRA yapılır: önce kırpsaydık USD/TRY serisinde
      // eşleşecek komşu nokta kalmayabilir ve `_closestOrNull` kenardaki
      // noktaları düşürürdü.
      return clipToPeriod(out, periodDays);
    }

    final raw = await series(sym);
    if (raw.isEmpty) return {};

    // TRY kote olanlar (BIST `.IS`, TEFAS fonları, `*TRY=X` pariteleri)
    // doğrudan döner; kalanlar USD kabul edilip çevrilir.
    if (_isTryQuoted(sym)) return clipToPeriod(raw, periodDays);

    final usd = kurSerisiniHizala(await series(FiyatKaynagi.usdTry), canliKur());
    if (usd.isEmpty) return {};
    final out = <int, double>{};
    for (final e in raw.entries) {
      final rate = _closestOrNull(usd, e.key);
      if (rate == null) continue;
      out[e.key] = e.value * rate;
    }
    return clipToPeriod(out, periodDays);
  }

  /// Sembol TRY cinsinden mi kote?
  ///
  /// BIST sembolleri `.IS` ile biter, TEFAS fonları `TEFAS:` önekli, TRY
  /// pariteleri `TRY=X` ile biter. Kalan her şey (ABD hisseleri, emtia,
  /// kripto) USD kabul edilir — Yahoo'nun varsayılanı budur.
  static bool _isTryQuoted(String sym) =>
      sym.endsWith('.IS') ||
      sym.startsWith('TEFAS:') ||
      sym.endsWith('TRY=X') ||
      sym.startsWith('ALTIN_');

  /// Periyoda uygun Yahoo range.
  ///
  /// **Merdiven eksiksiz olmak ZORUNDA.** Eskiden `'1d'` ve `'6mo'` hiç
  /// üretilmiyordu; `days<=7` doğrudan `'5d'`e, `days<=365` doğrudan `'1y'`e
  /// düşüyordu. Sonuç ölçülmüş iki hataydı:
  ///   · "GÜNLÜK" (1 gün) beş günlük değişimi gösteriyordu,
  ///   · "6A" (180 gün) ile "1Y" (365 gün) aynı range'e düştüğü için —
  ///     önbellek anahtarı da `'${sym}_$range'` olduğundan — BİREBİR aynı
  ///     seriyi döndürüyordu. İki sekme arasında hiçbir rakam değişmiyordu.
  ///
  /// Yahoo'da `7d` diye bir range yok; 1 haftalık dönem `'1mo'` çekip
  /// [clipToPeriod] ile kırpılarak elde edilir. Range'in dönemden GENİŞ
  /// olması sorun değil, DAR olması veri kaybıdır.
  @visibleForTesting
  static String rangeForPeriod(int days) {
    if (days <= 1) return '1d';
    if (days <= 5) return '5d';
    if (days <= 30) return '1mo';
    if (days <= 90) return '3mo';
    if (days <= 180) return '6mo';
    if (days <= 365) return '1y';
    return '5y';
  }

  /// Periyoda uygun çözünürlük katmanı.
  ///
  /// Katman, [rangeForPeriod]'un seçtiği range'in Yahoo'dan GERÇEKTE hangi
  /// interval'le geldiğiyle uyumlu olmalı (`PriceService._intervalFor`).
  /// Eskiden `days<=2` beş dakikalık bucket'a çekiyordu ama range `'5d'`
  /// olduğu için gelen veri saatlikti — bucket'lama boşa çalışıyordu.
  ///
  /// **Karar [ResolutionTierMeta.pickForSpan]'e devredildi.** Burada ayrı bir
  /// merdiven duruyordu ve performans ekranının kullandığıyla ayrışmıştı:
  /// 6A ve 1Y'de performans ekranı HAFTALIK çizerken takip listesi GÜNLÜK
  /// çiziyordu. Aynı portföyün aynı dönemi iki ekranda iki farklı sıklıkta
  /// görünüyordu (kullanıcı bulgusu: "tüm zaman aralıklarında performans
  /// ekranındaki sıklıklarda gösterilmeli"). İki merdiven tutmak bu projede
  /// tekrar eden hata sınıfı; tek kaynağa indirildi.
  ///
  /// `pickForSpan` hedefi ~30-300 nokta: 1Y'de günlük 365 nokta fazla
  /// yoğun, haftalık 52 nokta doğru ölçek. 6A haftalıkta 26 noktaya iner —
  /// hedefin biraz altında ama iki ekranın AYNI şeyi göstermesi bundan daha
  /// önemli; ayrıca zoom yapıldığında viewport daralınca `pickForSpan`
  /// otomatik olarak daha ince katmana geçer.
  @visibleForTesting
  static ResolutionTier tierForPeriod(int days) =>
      ResolutionTierMeta.pickForSpan(days.toDouble());

  /// Seriyi seçili döneme kırpar.
  ///
  /// **Neden gerekli:** range her zaman dönemden geniştir (Yahoo yalnızca
  /// belirli range'leri kabul eder). Kırpılmazsa etiket ile veri ayrışır —
  /// "GÜNLÜK" yazıp beş günü, "1H" yazıp bir ayı gösterirdik. Dönem başı
  /// yüzdesi serinin İLK noktasından hesaplandığı için bu, çağıran her
  /// yüzeyde doğrudan yanlış bir rakam demekti.
  ///
  /// **`days == 1` TAKVİM GÜNÜ, diğerleri kayan penceredir.** Ayrım aşağıda
  /// gerekçelendirildi; kısacası "bugün ne oldu" sorusunun tabanı bugünün
  /// açılışıdır, 24 saat öncesi değil.
  ///
  /// **Pencere `now`'a değil SON VERİ NOKTASINA çapalanır.** Borsa hafta
  /// sonu ve tatilde kapalıdır; `now`'dan geriye saymak Pazar günü "GÜNLÜK"
  /// seçildiğinde Cuma seansının tamamını pencerenin dışında bırakır ve
  /// grafik boşalırdı.
  ///
  /// Kırpma yine de iki noktanın altına düşürüyorsa **son iki nokta** döner,
  /// ham serinin tamamı değil: günde tek fiyat açıklayan TEFAS fonlarında
  /// pencereye tek fiyat düşer ve `normalizeSeries` iki noktanın altında
  /// `null` verip varlığı grafikten sessizce siler. Ham seriye dönmek ise
  /// "GÜNLÜK" etiketiyle bir aylık değişim göstermek olurdu — kaçındığımız
  /// hatanın tam kendisi.
  @visibleForTesting
  static Map<int, double> clipToPeriod(Map<int, double> series, int days) {
    if (series.length < 2) return series;

    final keys = series.keys.toList()..sort();

    // **"GÜNLÜK" bir TAKVİM GÜNÜDÜR, kayan 24 saat değil.**
    //
    // Kayan pencere döviz gibi 7/24 işlem gören sembollerde dünün öğleden
    // sonrasını da içine alıyordu: eksen "15:37 · 21:18 · 02:59 · 08:41"
    // okunuyor ve dönem başı %0 referansı DÜNE düşüyordu. Kullanıcının
    // sorduğu soru "bugün ne oldu"; cevabın tabanı da bugünün açılışı olmalı.
    //
    // Bu, uygulamanın geri kalanının zaten kullandığı tanım:
    // `getPortfolioHistoryHourlyBreakdown` gün içi grid'ini bugünün
    // 00:00'ından kurar ve `DailySummary` gece yarısını geçen bir önbelleği
    // koşulsuz düşürür — tam da "bugünkü değişim aslında dünden bugüne farkı
    // gösterir" durumuna düşmemek için. Takip listesi bu konvansiyonun
    // dışında kalmıştı.
    //
    // Çapa `now` değil SON NOKTANIN GÜNÜ: borsa hafta sonu ve tatilde
    // kapalıdır, `now`'dan saymak Pazar günü boş bir grafik verirdi. Son
    // noktanın günü işlem gününde zaten bugündür (00:00 → şimdi); kapalı
    // günlerde son seansın tamamını gösterir.
    final int cutoff;
    if (days <= 1) {
      final sonGun = DateTime.fromMillisecondsSinceEpoch(keys.last);
      cutoff =
          dayKey(sonGun).millisecondsSinceEpoch;
    } else {
      cutoff = keys.last - Duration(days: days).inMilliseconds;
    }

    final out = <int, double>{
      for (final e in series.entries)
        if (e.key >= cutoff) e.key: e.value,
    };
    if (out.length >= 2) return out;

    final son = keys.sublist(keys.length - 2);
    return {for (final k in son) k: series[k]!};
  }

  /// Ham noktaları tier'a göre bucket'lara indirger.
  static Map<int, double> _normalized(
      List<(int, double)> pts, ResolutionTier tier) {
    final out = <int, double>{};
    for (final p in pts) {
      // Aynı bucket'a düşen sonraki nokta öncekini ezer → bucket'ın
      // KAPANIŞ değeri kalır. Grafiklerde beklenen davranış budur.
      out[tier.normalizeTs(p.$1)] = p.$2;
    }
    return out;
  }

  /// Önbellekli, hata yutan tek sembol çekimi.
  ///
  /// Anahtara interval de girer: aynı range farklı çözünürlükle istenebilir
  /// ve iki çekim birbirini ezmemelidir.
  Future<List<(int, double)>> _fetchSafe(
      String sym, String range, String interval) async {
    final key = '${sym}_${range}_$interval';
    final cached = _cacheGet(key);
    if (cached != null) return cached;
    final sure = Stopwatch()..start();
    try {
      final pts = await PriceService.instance
          .fetchHistoryAtInterval(sym, range, interval)
          .timeout(_grafikCekimSuresi);
      _cekimSuresiniKaydet(sym, sure.elapsedMilliseconds, pts.length,
          timedOut: false);
      if (pts.isNotEmpty) _cachePut(key, pts);
      return pts;
    } on TimeoutException {
      // Zaman aşımı HATA DEĞİL, bir karar: grafik o kaynak olmadan
      // çizilir (altında yedek kaynak ya da `currentPrice` seed'i var).
      _cekimSuresiniKaydet(sym, sure.elapsedMilliseconds, 0, timedOut: true);
      return const [];
    } catch (e) {
      if (kDebugMode) debugPrint('getSymbolHistory($sym) failed: $e');
      return const [];
    }
  }

  /// Bu sürenin üstündeki çekimler analytics'e düşer.
  static const _yavasCekimEsigi = Duration(seconds: 3);

  /// Çekim süresi teşhisi.
  ///
  /// Altın grafiğinin gecikmesi 2026-09-13'te yapısal olarak düzeltildi (iki
  /// istek paralel, timeout, boş seri "veri yok") ama gerçek ağda hiç
  /// ölçülmedi — test ortamında ağ yok, emülatörde oturum yok. Bu kayıt o
  /// boşluğu kapatır: debug'da her sembolün süresi konsola yazılır; eşiği
  /// aşanlar ve zaman aşımları Firebase'e `slow_history_fetch` olarak gider.
  ///
  /// Neden hepsi değil: bir grafik açılışı 2-3 sembol çeker; hepsini
  /// loglamak olay hacmini boşuna şişirirdi. Soru "hâlâ yavaş mı, hangi
  /// sembolde" — yalnızca yavaşlar cevaplar.
  void _cekimSuresiniKaydet(String sym, int ms, int nokta,
      {required bool timedOut}) {
    if (kDebugMode) {
      debugPrint('getSymbolHistory($sym) ${ms}ms, $nokta nokta'
          '${timedOut ? ' — ZAMAN AŞIMI' : ''}');
    }
    if (!timedOut && ms < _yavasCekimEsigi.inMilliseconds) return;
    unawaited(AnalyticsService.instance.logSlowHistoryFetch(
      symbol: sym,
      ms: ms,
      points: nokta,
      timedOut: timedOut,
    ));
  }
}

/// Bir serinin dönem başına göre normalize edilmiş getirisi.
///
/// Karşılaştırmanın temel taşı: farklı fiyat ölçeklerindeki varlıklar
/// (₺12 bir hisse ile ₺4.800 bir altın) ancak yüzde cinsinden aynı
/// grafikte anlamlı görünür.
typedef NormalizedSeries = ({
  /// `{ UNIX_MILLIS: YUZDE_DEGISIM }` — dönem başı `0.0`.
  Map<int, double> points,

  /// Dönem boyunca toplam getiri yüzdesi (son nokta).
  double totalReturnPct,

  /// Dönemdeki ilk ve son ham fiyat — "₺X → ₺Y" göstermek için.
  double firstPrice,
  double lastPrice,
});

/// Ham fiyat serisini dönem başı `%0` olacak şekilde normalize eder.
///
/// **Neden yüzde:** kullanıcının sahip OLMADIĞI bir varlık için alım fiyatı
/// yoktur; "ne kadar kazandın" sorusu tanımsızdır. Tanımlı olan tek şey
/// dönem boyunca fiyatın yüzde kaç değiştiğidir. Bu yüzden karşılaştırma
/// her zaman dönem başını sıfır kabul eder.
///
/// İlk fiyat sıfır veya negatifse (bozuk veri) `null` döner — sıfıra bölme
/// sonsuz yüzde üretir ve grafiği okunamaz hale getirirdi.
NormalizedSeries? normalizeSeries(Map<int, double> raw) {
  if (raw.length < 2) return null;
  final keys = raw.keys.toList()..sort();
  final first = raw[keys.first]!;
  if (first <= 0) return null;

  final points = <int, double>{};
  for (final k in keys) {
    points[k] = (raw[k]! - first) / first * 100.0;
  }
  final last = raw[keys.last]!;
  return (
    points: points,
    totalReturnPct: (last - first) / first * 100.0,
    firstPrice: first,
    lastPrice: last,
  );
}

/// TEFAS'ın günlük NAV'ının gün içi grafikte çizileceği VARSAYILAN saat
/// (yerel) — sunucu gözlemi yoksa.
///
/// TEFAS yanıtı NAV'ın TARİHİNİ taşır, yayımlandığı ANI değil. 2026-09-14'e
/// kadar tek çapa buydu: piyasa açılışı (10:00), günden güne değişmeyen bir
/// an; yaklaşık ama KARARLI. Kararlılık burada doğruluktan daha çok iş
/// görüyor: kayan bir basamak kullanıcıya olmayan bir olay anlatır.
///
/// Artık asıl çapa sunucunun GÖZLEMİ (`fonBasamakAni`, `tefas_nav_gozlem`,
/// 0063): NAV tarihinin sunucuda ilk görüldüğü an. Bu sabit yalnızca gözlem
/// olmadığında (tablo yok, hafta sonu, TEFAS o tur yanıt vermedi) devreye
/// girer. Geçmişi `TECHNICAL_DEBT.md`'de.
const int tefasNavYayinSaati = 10;

/// `TEFAS:AFT` → `AFT`. Sunucu gözlemi öneksiz kodla anahtarlı.
String tefasKodu(String ticker) {
  final t = ticker.trim().toUpperCase();
  return t.startsWith('TEFAS:') ? t.substring('TEFAS:'.length) : t;
}

/// Bir fonun gün içi basamağının çizileceği slot.
///
/// Öncelik sunucu gözleminde ([gozlem], bkz. `TefasNavGozlem`): NAV tarihi
/// çizilen gün ([dayStart]) İSE ve ilk görülme de o güne düşüyorsa basamak
/// ilk görülmenin slotuna konur — TEFAS'ın verdiği damga değil, bizim
/// ölçtüğümüz "en geç bu saatte yayımlanmıştı" anı (cron sıklığı kadar,
/// 30 dk, kaba).
///
/// Aksi hâlde [varsayilanTs] (sabit `tefasNavYayinSaati`, gün o saate
/// gelmediyse `null`). Yani gözlem yokken davranış ESKİSİYLE AYNI; gözlem
/// varken yalnızca basamağın yeri değişir, basamağın kendisi (`oncekiNav` /
/// `guncelNav`) aynı kalır.
///
/// İki koruma:
///   * Gözlem [dayStart]'tan önceye düşerse (saat dilimi/bozuk damga)
///     varsayılana dönülür — grafiğin sol ucunda uçurum açılmasın.
///   * Gözlem ŞİMDİDEN ilerideyse (cihaz saati geri) basamak henüz yok
///     (`null`) — hizalama fon için no-op kalır, imlece yapışık uçurum
///     oluşmaz (2026-09-10 dersi).
@visibleForTesting
int? fonBasamakAni({
  required DateTime dayStart,
  required int nowTs,
  required int? varsayilanTs,
  required TefasNavGozlem? gozlem,
  required int Function(int) normalizeSlot,
}) {
  if (gozlem == null) return varsayilanTs;
  bool ayniGun(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (!ayniGun(gozlem.navTarihi, dayStart)) return varsayilanTs;
  if (!ayniGun(gozlem.ilkGorulme, dayStart)) return varsayilanTs;
  final slot = normalizeSlot(gozlem.ilkGorulme.millisecondsSinceEpoch);
  if (slot < dayStart.millisecondsSinceEpoch) return varsayilanTs;
  if (nowTs < slot) return null;
  return slot;
}

/// Bir fonun gün içi seride kullanacağı BİRİM fiyat.
///
/// TEFAS gün içi NAV yayınlamaz — bir fonun fiyatı günde bir kez değişir.
/// Fon gün boyu `currentPrice` ile sabit çizildiğinde gün içi seride
/// değişimi SIFIR görünüyordu; oysa iki NAV arasındaki fark gerçek ve
/// kullanıcı onu görmek istiyor ("günlükte fon seçilince de değişim yok
/// gözüküyor ancak aslında var", 2026-09-10).
///
/// Kural bir BASAMAK: gün, önceki NAV ile açılır ve [basamakTs] anında
/// güncel NAV'a atlar. Ara değer UYDURULMAZ (doğrusal rampa çizmek, fonun
/// olmayan bir gün içi hareketini icat etmek olurdu).
///
/// [oncekiNav] bilinmiyorsa (seri tek noktalı, iki NAV eşit, fon elle
/// fiyatlanıyor) davranış eskisi gibi kalır: gün boyu sabit `guncelNav`.
///
/// [basamakTs] `null` ise çizilen gün henüz yayın saatine ulaşmamıştır ve
/// basamak YOKTUR — fon gün boyu `guncelNav` ile çizilir.
///
/// ## Çapa neden SABİT bir saat
/// İlk sürümde basamak, seansın ilk gerçek fiyat verisine çapalıydı. O veri
/// yalnızca hisse/altın/emtia/döviz dallarında üretiliyor; portföyde (ya da
/// tür filtresinde) fondan başka varlık yoksa çapa HİÇ oluşmuyor, fon gün
/// boyu önceki NAV'da kalıyor ve son slotu canlı toplamla ezen hizalama tek
/// noktalık dik bir uçurum bırakıyordu — üstelik "ŞİMDİ" imlecine yapışık,
/// dakikalar geçtikçe sağa kayan bir uçurum.
///
/// Sabit saat hem bu kaymayı bitirir hem de aynı fonun basamağını "Tümü" ve
/// "Fon" görünümlerinde AYNI yere koyar.
@visibleForTesting
double gunIciFonBirimFiyati({
  required double guncelNav,
  required double? oncekiNav,
  required int slotTs,
  required int? basamakTs,
}) {
  if (oncekiNav == null || oncekiNav <= 0) return guncelNav;
  if (basamakTs == null) return guncelNav;
  return slotTs < basamakTs ? oncekiNav : guncelNav;
}

/// Tek noktalık "V" artefaktlarını temizler.
///
/// Yahoo bazı sembollerde tek bir slotu eksik/geç döndürüyor; o slotta
/// pozisyon eksik hesaplanıyor ve seri aşağı inip hemen geri çıkıyor.
/// Gerçek bir fiyat hareketi değil, veri artefaktı.
///
/// Bir nokta ancak ÜÇ koşulu birden sağlarsa düzeltilir:
///   * iki komşusundan da [deviation] oranından fazla sapıyorsa,
///   * komşuları birbirine [neighborGap] oranından yakınsa (yani gerçek
///     bir trend YOKSA — trend varsa ortadaki nokta meşrudur).
///
/// Eşikler ölçeğe göre verilir: günlük seride %1,5 sapma anlamlıyken
/// 5 dakikalık bir slotta portföyün %0,3'ü bile büyük bir haraket sayılır.
///
/// Uçlar (ilk ve son) DOKUNULMAZ: komşusu olmayan bir noktanın artefakt
/// olup olmadığı bilinemez ve son nokta zaten canlı toplama sabitlenir.
@visibleForTesting
Map<int, double> smoothSpikes(
  Map<int, double> points, {
  required double deviation,
  required double neighborGap,

  /// Düzeltilen slot'ların ÖNCEKİ değerleri buraya yazılır (ts → eski değer).
  /// Çağıran bununla tür/pozisyon dağılımını aynı oranda ölçekler; aksi halde
  /// toplam düzeltilip dağılım ham kalır ve `Σ byType != total` olur.
  Map<int, double>? changed,
}) {
  final keys = points.keys.toList()..sort();
  for (int i = 1; i < keys.length - 1; i++) {
    final prev = points[keys[i - 1]]!;
    final cur = points[keys[i]]!;
    final next = points[keys[i + 1]]!;
    if (prev <= 0 || next <= 0) continue;
    final devPrev = ((cur - prev) / prev).abs();
    final devNext = ((cur - next) / next).abs();
    final prevNextGap = ((next - prev) / prev).abs();
    if (devPrev > deviation &&
        devNext > deviation &&
        prevNextGap < neighborGap) {
      changed?[keys[i]] = cur;
      points[keys[i]] = (prev + next) / 2;
    }
  }
  return points;
}
