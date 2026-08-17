import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import 'history_service.dart';

/// Uygulama DIŞI yüzeylerin ortak günlük özet hesabı.
///
/// İki yüzey besler ve ikisi de BİREBİR aynı rakamı göstermek zorundadır:
///   * [LiveActivityService] — iOS kilit ekranı / Dynamic Island,
///   * [HomeWidgetService]   — Android & iOS ana ekran widget'ı.
///
/// ## Neden ayrı bir dosya
/// Bu mantık önce yalnızca `LiveActivityService` içinde, private olarak
/// yaşıyordu. Ana ekran widget'ı ise kendi hesabını yapıyordu ve üç yerde
/// ayrışmıştı: ömürlük getiriyi "günlük" diye gösteriyor, satış lot'larını
/// toplama geri ekliyor, grafiği sıfır slotlarla düzleştiriyordu.
///
/// Kopyalayarak düzeltmek aynı sınıf hatayı üretirdi — bu projede ons→gram
/// formülünün beş kopyası tam olarak böyle ayrışmıştı. Bu yüzden hesap TEK
/// yerde toplanır ve iki servis de buradan okur.
///
/// ## Değişmezler
/// Aşağıdaki kuralların hepsi uygulamanın kendi "Bugünkü değişim" kartıyla
/// (`portfolio_performance_screen`) aynı olmak ZORUNDADIR. Kullanıcı aynı
/// anda üç yüzeyde farklı rakam görürse hangisine güveneceğini bilemez.
@immutable
class DailySummary {
  const DailySummary({
    required this.totalTRY,
    required this.changeTRY,
    required this.changePct,
    required this.sparkline,
  });

  /// Portföyün ŞU ANKİ toplam değeri (TRY) — sahip kapsamlı aggregate'ten.
  final double totalTRY;

  /// Bugünün net kâr/zararı (TRY) — nakit akışından arındırılmış.
  ///
  /// Hesaplanamadıysa `null`: seri çekilemediğinde uydurma bir sıfır
  /// yerine "veri yok" taşınır. Sıfır bir ÖLÇÜMDÜR ("bugün değişmedi") ve
  /// ölçüm yokken sıfır basmak kullanıcıyı yanıltır.
  final double? changeTRY;

  /// Bugünün değişim yüzdesi. [changeTRY] ile birlikte `null` olur.
  final double? changePct;

  /// Gün içi HAM (TRY) seri — grafik çizimi için.
  ///
  /// Normalize edilmemiştir; gizlilik gerektiren yüzey (kilit ekranı)
  /// normalize etmeyi kendi üstlenir. Ana ekran widget'ı PNG'yi ham
  /// değerlerden çizer, dolayısıyla ikisi ortak ham seriden beslenir.
  final List<double> sparkline;

  /// Değişim gerçekten ölçülebildi mi?
  bool get hasChange => changeTRY != null && changePct != null;

  /// Seri görsel olarak DÜZ mü? (grafik ölçeklemesi için)
  ///
  /// **Neden göreli eşik:** mutlak bir eşik (`< 1e-9`) portföy
  /// büyüklüğünden bağımsızdır ve büyük portföyde işe yaramaz. Gerçek
  /// vaka: ₺2.489.186,40 → ₺2.489.186,35, yani **5 kuruşluk** fark.
  /// `1e-9` eşiğini aştığı için "gerçek hareket" sayılıyor, normalize
  /// aralık 0,05'e oturuyor ve bu 5 kuruş tuvalin TAMAMINA yayılıyordu:
  /// düz bir günde grafiğin ucu tepeden dibe iniyordu.
  ///
  /// Ölçeğin milyonda biri (1e-6) eşik alınır — 2,5 milyonluk portföyde
  /// ~2,5 TL. Bunun altındaki fark yuvarlama gürültüsüdür, hareket değil.
  static bool isVisuallyFlat(List<double> values) {
    if (values.length < 2) return true;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs();
    final scale = maxV.abs();
    // Sıfır ölçekte mutlak eşiğe düş — sıfıra bölme olmasın.
    if (scale < 1e-9) return span < 1e-9;
    return span / scale < 1e-6;
  }

  /// Ölçüldü ama SIFIR mı? (yuvarlanmış tutar ve yüzde ikisi de sıfır)
  ///
  /// Uygulamanın "Bugünkü değişim" kartındaki `isFlat` ile aynı kural.
  /// Ayrı tutulmasının sebebi sunum: sıfır bir YÖN taşımaz. `-₺0` ya da
  /// yeşil bir `+₺0` yazmak, olmayan bir hareketi varmış gibi gösterir —
  /// kullanıcı kırmızı gördüğünde "bugün kaybettim" diye okur.
  bool get isFlat =>
      hasChange && changeTRY!.abs().round() == 0 && changePct!.abs() < 0.005;

  /// Grafiğin tutar ekseni sınırları — OKUNABİLİR (yuvarlak) değerlerde.
  ///
  /// **Neden ham min/max yetmiyor:** sınırlar doğrudan veriden alınınca
  /// `₺2,4893M` / `₺2,4880M` gibi keyfi rakamlar çıkıyor. Kullanıcı bu
  /// sayılardan bir şey çıkaramaz; eksen "hangi bandın içindeyim"
  /// sorusunu ancak tahmin edilebilir basamaklarda yanıtlar.
  ///
  /// Yöntem "nice numbers" (Heckbert): aralık 1·10ⁿ, 2·10ⁿ, 2,5·10ⁿ ya da
  /// 5·10ⁿ adımlarından birine yuvarlanır ve sınırlar o adımın katlarına
  /// oturtulur. Grafik kütüphanelerinin (fl_chart, d3, matplotlib) hepsi
  /// bu aileden bir kural kullanır.
  ///
  /// Sınırlar veriyi HER ZAMAN kapsar: alt sınır `min`'in altına, üst
  /// sınır `max`'ın üstüne yuvarlanır — aksi halde çizgi eksenin dışına
  /// taşar ve kırpılmış görünür.
  ///
  /// [minSpanRatio] eksen bandının en dar hâlini belirler (varsayılan
  /// portföyün %0,5'i). Yalnızca veriye göre ölçeklenen bir eksen, yatay
  /// giden portföydeki minicik dalgalanmayı tuvalin tamamına yayıyor ve
  /// rakamla çelişen bir "çöküş" gösteriyordu.
  static ({double min, double max}) niceAxisBounds(
    List<double> values, {
    double minSpanRatio = 0.005,
  }) {
    if (values.isEmpty) return (min: 0, max: 1);

    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final scale = rawMax.abs();

    // Ham aralık + asgari bant + nefes payı (%25).
    var span = (rawMax - rawMin).abs();
    final minSpan = scale * minSpanRatio;
    if (span < minSpan) span = minSpan;
    if (span <= 0) span = scale > 0 ? scale * minSpanRatio : 1;
    final padded = span * 1.25;

    // Bandı verinin ortasına al, sonra yuvarlak adıma oturt.
    //
    // Adım bandın YARISI değil, `_tickCount`'a bölünmüş hâli üzerinden
    // seçilir. Yarıyı vermek adımı gereğinden büyük yuvarlıyordu:
    // ₺2.300'lük gerçek hareket ₺30.000'lik bir banda oturuyor ve çizgi
    // düz görünüyordu — eksen okunabilir oluyor ama grafik bilgi
    // taşımıyordu. Bant her zaman veriyi kapsar, sadece gereksiz yere
    // genişlemez.
    final mid = (rawMax + rawMin) / 2;
    final step = _niceStep(padded / _tickCount);

    // Alt sınır AŞAĞI, üst sınır YUKARI yuvarlanır — veri her zaman
    // eksenin içinde kalmalı.
    var lo = (( mid - padded / 2) / step).floor() * step;
    var hi = ((mid + padded / 2) / step).ceil() * step;

    // Yuvarlama sonrası veri yine de dışarıda kaldıysa bir adım genişlet.
    // (Kayan nokta hatası ya da uç değerlerde olabilir.)
    while (lo > rawMin) {
      lo -= step;
    }
    while (hi < rawMax) {
      hi += step;
    }
    // Dejenere durum: adım sıfıra düşerse bant kapanır ve sıfıra bölme
    // riski doğar.
    if (hi - lo < 1e-9) return (min: lo - 1, max: lo + 1);

    return (min: lo, max: hi);
  }

  /// Eksende hedeflenen bölme sayısı.
  ///
  /// Yüzey iki kılavuz çizgisi (alt + üst) gösteriyor ama adım hesabı
  /// daha ince bir ızgara varsayar: 4 bölme, bandı veriye yakın tutarken
  /// sınırların yuvarlak kalmasını sağlar. Daha az bölme adımı büyütüp
  /// bandı şişirir, daha çok bölme sınırları kesirli yapar.
  static const _tickCount = 4;

  /// Verilen büyüklüğe en yakın "okunabilir" adım — 1, 2, 2,5 ya da 5'in
  /// 10 kuvvetiyle çarpımı.
  ///
  /// Kullanıcı bu basamakları zihninde kolayca ikiye/beşe bölebilir;
  /// 3'lük ya da 7'lik adımlar okunmaz.
  static double _niceStep(double rough) {
    if (rough <= 0) return 1;
    final exp = (math.log(rough) / math.ln10).floor();
    final pow10 = math.pow(10, exp).toDouble();
    final frac = rough / pow10; // 1 ≤ frac < 10

    final double niceFrac;
    if (frac <= 1) {
      niceFrac = 1;
    } else if (frac <= 2) {
      niceFrac = 2;
    } else if (frac <= 2.5) {
      niceFrac = 2.5;
    } else if (frac <= 5) {
      niceFrac = 5;
    } else {
      niceFrac = 10;
    }
    return niceFrac * pow10;
  }

  /// BIST işlem saatleri içinde miyiz? Fiyatların gerçekten hareket
  /// ettiği aralık (hafta içi 10:00–18:10).
  ///
  /// **Neden ortak katmanda:** iki yüzey de "Canlı" / "Piyasa kapalı"
  /// etiketini bu kurala göre gösterir. Ayrışırlarsa kilit ekranı "Canlı"
  /// derken ana ekran "Piyasa kapalı" diyebilir — aynı anda, yan yana.
  ///
  /// Kullanıcının seçtiği GÖSTERİM penceresinden ayrıdır: 7/24 gösterim
  /// seçilse bile gece fiyat hareket etmez.
  ///
  /// Resmî tatiller burada bilinmez — takvim gerektirir ve yanlış bir
  /// tatil listesi listesizlikten kötüdür (bkz. TECHNICAL_DEBT.md).
  static bool isMarketOpen(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final mins = now.hour * 60 + now.minute;
    return mins >= 10 * 60 && mins < 18 * 60 + 10;
  }

  /// Portföyün canlı toplam değeri (TRY).
  ///
  /// **Neden `state.totalValue` DEĞİL:** o alan ham lot listesi üzerinden
  /// toplar ve `Asset.totalValue` (= `quantity * currentPrice`)
  /// İŞARETSİZDİR. Satış lot'unun miktarı da pozitiftir, dolayısıyla ham
  /// toplam satılan miktarı düşmek yerine GERİ EKLER — kullanıcı ne kadar
  /// çok satış yaptıysa rakam o kadar şişer.
  ///
  /// Gün içi serinin geldiği `HistoryService` ise satışı `signedQtyOnSlot`
  /// ile doğru şekilde `-quantity` sayar. İki uç zıt işaret kuralı
  /// kullandığında `last - open` farkı anlamsızlaşır.
  ///
  /// `aggregatePositionsByOwner` ortak lot'ları tek havuzda toplamaz:
  /// `positionKey` sahip taşımaz ve havuzlanan iki ortağın aynı hissesi
  /// tek pozisyona düşerdi. Uygulama dışı yüzeyler yalnızca kullanıcının
  /// KENDİ portföyünü gösterir, bu yüzden kapsam tek sahiplidir.
  static double liveTotalTRY(PortfolioState state) =>
      ownerScopedTotalValue([state.assets], toTRY: state.toTRY);

  /// Gün içi seriyi uygulamanın GÜNLÜK grafiğiyle birebir aynı kurallarla
  /// ham (TRY) değer listesine indirger.
  ///
  /// Kurallar `portfolio_performance_screen._convertHistoryToSegments`
  /// (intraday dalı) ile aynıdır:
  ///   1. Gelecekteki slotlar atılır (`ts > now`). Kaynak 24 saatlik grid
  ///      üretir; günün geri kalanı henüz olmamıştır.
  ///   2. `y <= 0` slotlar atlanır — borsa açılmadan önceki boş slotlar.
  ///      Bunlar bırakılırsa çizilen aralık 0'dan başlar ve gerçek gün içi
  ///      hareket düz bir çizgiye ezilir.
  ///   3. Son nokta canlı toplama sabitlenir — ama YALNIZCA seri güncelse
  ///      (bkz. [_liveTailMaxLag]).
  static List<double> dayValues(
    Map<int, double> series,
    DateTime now,
    double currentTotal,
  ) {
    if (series.isEmpty) return const [];
    final nowMs = now.millisecondsSinceEpoch;
    final keys = series.keys.toList()..sort();

    final values = <double>[];
    var lastTs = 0;
    for (final k in keys) {
      if (k > nowMs) break;
      final v = series[k]!;
      if (v <= 0) continue;
      values.add(v);
      lastTs = k;
    }
    if (values.isEmpty) return const [];

    // Grafiğin ucunu canlı toplama sabitle — AMA yalnızca serinin son
    // noktası taze ise.
    //
    // **Neden koşullu:** `HistoryService` serinin son slotunu zaten canlı
    // toplama sabitliyor, ama seri 5 dakika ÖNBELLEKLENİYOR
    // ([IntradaySeriesCache]). Bu arada fiyatlar tazelenirse buradaki
    // `currentTotal` önbellekteki uçtan farklı olur.
    //
    // Piyasa AÇIKKEN bu farkı uca yazmak doğrudur: aradaki hareket
    // gerçektir ve grafiğin ucu güncel değeri göstermelidir. Ama piyasa
    // KAPALIYKEN seri kapanışta donmuştur; saatler önceki bir slota akşam
    // fiyatını yazmak, olmayan bir hareketi grafiğe basar.
    //
    // Uygulamanın kendi günlük grafiği de aynı eşiği kullanıyor
    // (`portfolio_performance_screen._convertHistoryToSegments`, intraday
    // dalı): fark 5 dakikadan azsa son nokta EZİLİR. Orada değilse canlı
    // değer kendi zaman konumuna AYRI bir nokta olarak eklenir; burada
    // seri ham bir değer listesi olduğu (X ekseni taşımadığı) için o
    // karşılık yoktur, uç değiştirilmeden bırakılır.
    //
    // Rakam (`totalTRY`) zaten canlı değeri gösteriyor; grafik gün içi
    // hareketi anlatır ve kapanıştan sonra düz kalması DOĞRUDUR.
    if (currentTotal > 0 && nowMs - lastTs <= _liveTailMaxLag.inMilliseconds) {
      values[values.length - 1] = currentTotal;
    }

    return values;
  }

  /// Serinin ucu bu süreden eskiyse canlı değerle EZİLMEZ.
  ///
  /// 5 dakika, hem veri çözünürlüğüyle (5 dk slot) hem de uygulamanın
  /// kendi grafiğindeki eşikle aynıdır.
  static const _liveTailMaxLag = Duration(minutes: 5);

  /// Bugün portföye giren net nakit (TRY) — alım (+), satış (−).
  ///
  /// **Neden gerekli:** ham uçtan uca fark "portföyüm ne kazandı?"
  /// sorusunun cevabı DEĞİLDİR; içine bugün yatırdığınız para da girer.
  /// 170.000 TL'lik bir alım, hiçbir fiyat hareketi olmasa bile yüzeyi
  /// "+%6,19 kâr" gösterirdi.
  ///
  /// `portfolio_performance_screen._flowOf` ile BİREBİR aynı kural:
  ///   * alım para GİRİŞİ (+), satışta ele geçen tutar ÇIKIŞ (−);
  ///   * satışta maliyet değil `sellProceedsTRY` kullanılır — kârla
  ///     satılan pozisyonda ikisi farklıdır ve fark yanlışlıkla "piyasa
  ///     etkisi" sayılırdı;
  ///   * temettü ve silinen lot akışa girmez (`isActive` ikisini de eler).
  static double todayInflow(List<Asset> assets, DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    var total = 0.0;
    for (final a in assets) {
      if (!a.isActive) continue;
      if (a.addedDate.isBefore(dayStart) || a.addedDate.isAfter(dayEnd)) {
        continue;
      }
      if (a.isBuy) {
        total += a.totalCostTRY;
      } else if (a.isSell) {
        total -= a.sellProceedsTRY;
      }
    }
    return total;
  }

  /// Gün içi seriden ve portföy durumundan tam özeti kurar.
  ///
  /// [series] boş ya da tek noktalıysa değişim `null` döner — grafik de
  /// çizilmez. Tek noktalı bir "çizgi" yanıltıcı olurdu.
  static DailySummary from({
    required PortfolioState state,
    required Map<int, double> series,
    required DateTime now,
  }) {
    final total = liveTotalTRY(state);
    final values = dayValues(series, now, total);

    if (values.length < 2) {
      return DailySummary(
        totalTRY: total,
        changeTRY: null,
        changePct: null,
        sparkline: values,
      );
    }

    final open = values.first;
    final last = values.last;
    if (open <= 0) {
      return DailySummary(
        totalTRY: total,
        changeTRY: null,
        changePct: null,
        sparkline: values,
      );
    }

    // Nakit akışından ARINDIR — uygulamanın kartıyla birebir aynı formül.
    final inflow = todayInflow(state.assets, now);
    final amount = (last - open) - inflow;

    // Yüzde tabanı: gün başı değer + bugün yatırılan para. Yalnızca `open`
    // kullanmak, gün içinde portföyünü büyüten kullanıcıda yüzdeyi
    // şişirirdi. (Kartla aynı taban.)
    final base = open + (inflow > 0 ? inflow : 0);
    if (base <= 0) {
      return DailySummary(
        totalTRY: total,
        changeTRY: null,
        changePct: null,
        sparkline: values,
      );
    }

    return DailySummary(
      totalTRY: total,
      changeTRY: amount,
      changePct: amount / base * 100,
      sparkline: values,
    );
  }
}

/// Gün içi serinin ORTAK önbelleği — iki yüzey de buradan okur.
///
/// **Neden paylaşımlı:** `getPortfolioHistoryHourly` onlarca fiyat serisi
/// çeken pahalı bir çağrı. İki servis ayrı ayrı önbelleklerse aynı veri
/// için iki ağ turu atılır ve — daha kötüsü — iki yüzey farklı anlarda
/// tazelenip aynı anda FARKLI rakam gösterir. Kullanıcı kilit ekranıyla
/// ana ekranı yan yana gördüğünde bu doğrudan "uygulama bozuk" demektir.
class IntradaySeriesCache {
  IntradaySeriesCache._();
  static final instance = IntradaySeriesCache._();

  /// En sık tazeleme aralığı.
  ///
  /// 5 dakika, hem veri çözünürlüğüyle (5 dk slot) hem de Live Activity
  /// push döngüsünün periyoduyla (`0033_live_activity_cron.sql`) hizalı:
  /// daha sık çekmek push'a yansımayacağı için boşuna olur.
  static const minInterval = Duration(minutes: 5);

  Map<int, double>? _series;
  DateTime? _fetchedAt;

  /// Son başarıyla çekilen seri — hiç çekilmediyse boş.
  Map<int, double> get series => _series ?? const {};

  /// Seriyi gerekiyorsa tazeler ve döner.
  ///
  /// Sessizce başarısız olur: ağ hatasında son bilinen seri korunur ve
  /// çağıran taraf yine bir şey gösterebilir.
  Future<Map<int, double>> get(PortfolioState state, {DateTime? now}) async {
    final ts = now ?? DateTime.now();

    // Gün DEĞİŞTİYSE önbellek koşulsuz düşer.
    //
    // Bu yüzeyler saatlerce açık kalır ve gece yarısını geçebilir. Yalnızca
    // "N dakika geçti mi" diye soran bir tazelik testi 23:58'de çekilen
    // seriyi 00:01'de hâlâ taze sayar: gün başı değeri DÜNÜN açılışı olarak
    // kalır ve "bugünkü" değişim aslında dünden bugüne farkı gösterir.
    final sameDay = _fetchedAt != null &&
        _fetchedAt!.year == ts.year &&
        _fetchedAt!.month == ts.month &&
        _fetchedAt!.day == ts.day;

    if (!sameDay) {
      // Dünün serisi DERHAL düşer — fetch başarısız olsa bile bayat
      // baseline'la rakam üretilmemeli.
      _series = null;
    } else if (ts.difference(_fetchedAt!) < minInterval) {
      return _series ?? const {};
    }

    try {
      final fresh = await HistoryService.instance
          .getPortfolioHistoryHourly(state.activeAssets, 24);
      _series = fresh;
      // Damga yalnızca fetch BAŞARILI olduğunda atılır. Await'ten önce
      // atmak, ağ hatası alan çağrının da pencereyi yakmasına yol açardı:
      // hata sürekliyse seri saatlerce tazelenmez ve yüzeyler sabahki
      // değerde donar — üstelik "Canlı" etiketiyle.
      _fetchedAt = ts;
    } catch (e) {
      if (kDebugMode) debugPrint('Gün içi seri çekilemedi: $e');
    }

    return _series ?? const {};
  }

  /// Oturum kapanışında çağrılır — bir sonraki kullanıcı öncekinin
  /// grafiğini görmemeli.
  void clear() {
    _series = null;
    _fetchedAt = null;
  }
}
