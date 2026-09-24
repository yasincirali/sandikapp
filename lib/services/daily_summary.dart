import 'dart:async';
import 'tazelik_ritmi.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import '../utils/chart_axis.dart' show gunIciAsgariBantOrani;
import 'history_service.dart';
import 'price_service.dart';
import '../utils/tr_format.dart';
import 'bist_calendar.dart';

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
    this.inflowTRY = 0,
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

  /// [changeTRY]'den düşülen gün içi net nakit akışı (TRY) — [gunIciKatki].
  ///
  /// Performans › Özet GÜNLÜK köprüsü ("başlangıç + katkı + piyasa = son")
  /// bu sayıyı kullanır; ayrı bir akış hesabı yapsaydı köprü, düşülen
  /// akışla tutmazdı (2026-09-24).
  final double inflowTRY;

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
    double minSpanRatio = gunIciAsgariBantOrani,
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

  /// Sparkline çizimi için 0…1 aralığına normalize edilmiş seri.
  ///
  /// ORTAK katmanda durur çünkü iki yüzey de aynı eğriyi çizmek zorunda:
  /// kilit ekranı (Live Activity) ve iOS ana ekran widget'ı. Ayrı ayrı
  /// normalize edilseydi aynı portföy iki yerde farklı görünürdü.
  static List<double> normalizeForSparkline(List<double> values) {
    if (values.length < 2) return const [];

    // Düz çizgi: ortada yatay çiz. Sıfıra bölmeyi de önler.
    //
    // Eşik GÖRELİDİR — mutlak `1e-9` büyük portföyde işe yaramıyordu.
    // Gerçek vaka: ₺2.489.186,40 → ₺2.489.186,35 (5 kuruş). Eşiği aştığı
    // için "hareket" sayılıyor ve bu 5 kuruş 0…1 aralığının TAMAMINA
    // yayılıyordu: düz bir günde grafiğin ucu tepeden dibe iniyordu.
    if (isVisuallyFlat(values)) {
      return List.filled(values.length.clamp(2, 40), 0.5);
    }

    // Normalize aralığı EKSENLE aynı olmalı.
    //
    // Etiketler `_axisBounds` üzerinden `niceAxisBounds`
    // kullanıyor; çizgi başka bir aralığa göre normalize edilirse ikisi
    // ayrışır: kullanıcı "₺2,48M–₺2,50M" yazan bir eksende tuvali baştan
    // başa dolduran bir çizgi görür. Aynı fonksiyondan okunur.
    final bounds = niceAxisBounds(values);
    final lo = bounds.min;
    final axisSpan = bounds.max - bounds.min;

    // Örnekleme: 40 noktadan fazlasını seyrelt.
    const maxPoints = 40;
    final step = values.length <= maxPoints
        ? 1
        : (values.length / maxPoints).ceil();

    final out = <double>[];
    for (var i = 0; i < values.length; i += step) {
      out.add((values[i] - lo) / axisSpan);
    }
    // Son nokta her zaman dahil — grafiğin ucu güncel değeri göstermeli.
    final lastNorm = (values.last - lo) / axisSpan;
    if (out.isEmpty || (out.last - lastNorm).abs() > 1e-9) out.add(lastNorm);
    return out;
  }

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
  /// Resmî tatiller [BistTakvimi]'nden gelir: sabit tarihli ulusal
  /// tatiller her yıl, dinî bayramlar yalnızca ilan edilmiş yıllar için
  /// (kapsanmayan yılda o günler AÇIK sayılır — yanlış liste listesizlikten
  /// kötüdür). Arife ve 28 Ekim yarım gün: 12:30'da kapanır.
  static bool isMarketOpen(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    if (BistTakvimi.tatilMi(now)) return false;
    final mins = now.hour * 60 + now.minute;
    final kapanis = BistTakvimi.yarimGunMu(now)
        ? BistTakvimi.yarimGunKapanisDk
        : 18 * 60 + 10;
    return mins >= 10 * 60 && mins < kapanis;
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
  /// tek pozisyona düşerdi. Kilit ekranı ve widget yalnızca kullanıcının
  /// KENDİ portföyünü gösterir; ama Bugün kartı 2026-09-21'den beri
  /// Birlikte görünümünde BİRLEŞİK defterle de çağırır. Defter sahibe göre
  /// bölünür (`lotlarSahibeGore`): tek sahipli defterde tek grup, hesap
  /// aynı; birleşik defterde sahiplik sınırı korunur.
  static double liveTotalTRY(PortfolioState state) =>
      kapsamToplami(state, state.assets);

  /// [kapsam] lot'larının CANLI toplamı — [liveTotalTRY] ile aynı yol.
  ///
  /// Dönem özetinin ("Şimdi") sağ ucu da bunu kullanır (2026-09-24): seri
  /// son slotunu `normalizeTs(now)` damgasına kurar (günlük katmanda bugün
  /// 00:00, haftalıkta pazartesi) ve o damgadan sonra alınan lot o slotta
  /// YOKTUR; katkı ise onu sayar. Uç canlı toplama bağlanmazsa piyasa
  /// etkisi bu lot'ların değeri kadar eksik çıkıyordu (ölçüldü: 1H'de
  /// Grafik +₺306, Özet −₺5.069; fark bugünkü alımların değeri).
  static double kapsamToplami(PortfolioState state, List<Asset> kapsam) =>
      ownerScopedTotalValue(lotlarSahibeGore(kapsam),
          toTRY: state.toTRY, sonFiyat: PriceService.instance.sonBilinenFiyat);

  /// [kapsamToplami]'nın türe göre dağılımı — aynı yol, tür başına bir
  /// kez. Dönem özetinin "dönem sonu" dağılımı rakamla aynı uca baksın
  /// diye (2026-09-24). Değeri olmayan tür haritaya girmez.
  static Map<AssetType, double> kapsamDagilimi(
      PortfolioState state, List<Asset> kapsam) {
    final turLotlari = <AssetType, List<Asset>>{};
    for (final a in kapsam) {
      turLotlari.putIfAbsent(a.type, () => []).add(a);
    }
    final out = <AssetType, double>{};
    turLotlari.forEach((tur, lotlar) {
      final v = kapsamToplami(state, lotlar);
      if (v > 0) out[tur] = v;
    });
    return out;
  }

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
  ///   3. Serinin ucu canlı toplama sabitlenir — ama YALNIZCA çizilen gün
  ///      BUGÜNSE (bkz. [seansGunu] parametresi).
  ///
  /// [seansGunu] çizilen seansın 00:00'ı. `null` verilirse SERİNİN KENDİ
  /// son damgasından türetilir — bugün VARSAYILMAZ.
  ///
  /// **Neden bugün varsayılmıyor:** varsayım yanlış olduğunda sessizce
  /// zarar veriyor. Hafta sonu seri Cuma'nındır; "bugün" varsayan bir
  /// dal, kapanmış Cuma seansının ucuna Pazar'ın canlı toplamını ekler ve
  /// olmamış bir hareket çizer (ölçüldü: Cuma'nın gerçek ₺9.800'lük
  /// hareketi +₺99.000 / %9,89 olarak görünüyordu). Seriden türetmek
  /// `seansGunu` taşınmadığı her yolda da doğru davranışı verir.
  static List<double> dayValues(
    Map<int, double> series,
    DateTime now,
    double currentTotal, {
    DateTime? seansGunu,
    bool acikPozisyonYok = false,
  }) {
    if (series.isEmpty) return const [];
    final nowMs = now.millisecondsSinceEpoch;
    final keys = series.keys.toList()..sort();

    // BAŞTAKİ sıfırlar atlanır, SONRAKİLER ölçümdür — grafiğin gün içi
    // dalıyla aynı kural (`seriler.dart`, 2026-09-16: "varlığımın 0'a
    // indiğini görmüyorum"). Bu liste o düzeltmeyi almamıştı: gün içinde
    // HER ŞEYİ satan kullanıcıda satış sonrası sıfırlar düşüyor, son değer
    // satış öncesi kalıyor ve satış geliri akıştan düşülünce değişim
    // satış tutarı kadar ŞİŞİYORDU (2026-09-24 kod incelemesi).
    final values = <double>[];
    var lastTs = 0;
    for (final k in keys) {
      if (k > nowMs) break;
      final v = series[k]!;
      if (v <= 0 && values.isEmpty) continue;
      values.add(v < 0 ? 0 : v);
      lastTs = k;
    }
    if (values.isEmpty) return const [];

    // Grafiğin ucunu canlı toplama sabitle — uygulamanın günlük
    // grafiğiyle BİREBİR aynı iki dallı kural
    // (`portfolio_performance_screen._convertHistoryToSegments`, intraday
    // dalı):
    //
    //   * Serinin ucu TAZEYSE (< 5 dk) son nokta EZİLİR — aynı ana iki
    //     nokta koymak grafiğin ucunda dik bir çentik bırakırdı.
    //   * Ucu BAYATSA canlı değer AYRI bir nokta olarak EKLENİR. Seri 5
    //     dakika önbelleklenir ([IntradaySeriesCache]) ve o arada fiyatlar
    //     tazelenir; ekleme, eğrinin ucunu yanındaki rakamla aynı yere
    //     getiren şeydir.
    //
    // **Neden eskiden eklenmiyordu:** bu liste X ekseni taşımıyor, o yüzden
    // "canlı değeri kendi zaman konumuna ekle" dalının karşılığı yok
    // sayılmıştı ve uç olduğu gibi bırakılıyordu. Sonuç: yüzeyin yazdığı
    // rakam ile hemen altındaki eğrinin bittiği yer farklı oluyordu
    // (ölçüldü: rakam ₺1.040.000, eğrinin ucu ₺1.009.800). Sparkline
    // eşit aralıklı çizildiği için son noktayı sona eklemek doğru
    // karşılıktır — tek kayıp, o noktanın X'inin bir slot ileride
    // olması; eğrinin ŞEKLİ ve bittiği DEĞER artık uyuşuyor.
    //
    // **Neden yalnızca BUGÜN çizilirken:** geçmiş seans çizilirken (hafta
    // sonu → Cuma) "şimdi" o günün ekseninde YOKTUR. Kapanmış bir seansın
    // ucuna bugünün canlı değerini yazmak, olmamış bir hareketi grafiğe
    // basar. Uygulamanın `bugunMu` kapısı da tam olarak bunu yapıyor.
    final cizilenGun = seansGunu ?? cizilenGunFromSeries(series);
    final bugunMu = cizilenGun != null &&
        cizilenGun.year == now.year &&
        cizilenGun.month == now.month &&
        cizilenGun.day == now.day;

    // Canlı toplam 0 iki şey olabilir: fiyat bilinmiyor (uç EZİLMEZ) ya da
    // elde hiç pozisyon kalmadı (0 bir ölçümdür, uç sıfıra iner).
    if (bugunMu && (currentTotal > 0 || acikPozisyonYok)) {
      if (nowMs - lastTs <= _liveTailMaxLag.inMilliseconds) {
        values[values.length - 1] = currentTotal;
      } else {
        values.add(currentTotal);
      }
    }

    return values;
  }

  /// Serinin AİT OLDUĞU günü (00:00) damgalarından türetir.
  ///
  /// `HistoryService` ızgarayı tek bir seans gününe kurar, bu yüzden son
  /// damganın günü çizilen gündür. Geleceğe düşen damgalar (saat dilimi
  /// kayması) yok sayılır — aksi halde "yarın" çizildiği sanılırdı.
  static DateTime? cizilenGunFromSeries(Map<int, double> series) {
    if (series.isEmpty) return null;
    final sonTs = series.keys.reduce((a, b) => a > b ? a : b);
    final d = DateTime.fromMillisecondsSinceEpoch(sonTs);
    return dayKey(d);
  }

  /// Serinin ucu bu süreden eskiyse canlı değer son noktayı EZMEZ, ayrı
  /// bir nokta olarak eklenir.
  ///
  /// 5 dakika, hem veri çözünürlüğüyle (5 dk slot) hem de uygulamanın
  /// kendi grafiğindeki eşikle aynıdır.
  static const _liveTailMaxLag = TazelikRitmi.canliUcAzamiGecikme;

  /// Çizilen SEANS GÜNÜNDE portföye giren net nakit (TRY) — alım (+),
  /// satış (−).
  ///
  /// **Neden gerekli:** ham uçtan uca fark "portföyüm ne kazandı?"
  /// sorusunun cevabı DEĞİLDİR; içine o gün yatırdığınız para da girer.
  /// 170.000 TL'lik bir alım, hiçbir fiyat hareketi olmasa bile yüzeyi
  /// "+%6,19 kâr" gösterirdi.
  ///
  /// **Neden "bugün" DEĞİL, çizilen gün:** seri her zaman bugüne ait
  /// değildir. Piyasa kapalıyken (hafta sonu, tatil, Pazartesi 10:00
  /// öncesi) `HistoryService` SON SEANSI döndürür — Pazar günü çizilen
  /// eğri Cuma'nındır (bkz. `PortfolioHistoryBreakdown.seansGunu`).
  /// Akış bugüne göre hesaplanırsa, seansTAN SONRA yapılmış bir alım o
  /// seansın hareketinden düşülür: ölçülen vakada Cuma'nın gerçek
  /// hareketi ₺9.800 iken Pazar günü girilen ₺1.000'lik alım yüzünden
  /// yüzeyler ₺8.800 gösteriyordu. O alım Cuma seansında henüz yoktu.
  ///
  /// `portfolio_performance_screen._buildPeriodChangeCard` ve bu sınıf
  /// GÜNLÜK akışı artık aynı fonksiyondan alır: [gunIciKatki] (2026-09-24).
  /// Bu fonksiyon yalnızca pencereyi açıkça veren ham yardımcıdır.
  ///
  /// `portfolio_performance_screen._flowOf` ile BİREBİR aynı işaret
  /// kuralı:
  ///   * alım para GİRİŞİ (+), satışta ele geçen tutar ÇIKIŞ (−);
  ///   * satışta maliyet değil `sellProceedsTRY` kullanılır — kârla
  ///     satılan pozisyonda ikisi farklıdır ve fark yanlışlıkla "piyasa
  ///     etkisi" sayılırdı;
  ///   * temettü ve silinen lot akışa girmez (`isActive` ikisini de eler).
  static double todayInflow(List<Asset> assets, DateTime now) {
    final dayStart = dayKey(now);
    final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return inflowOnDay(assets, dayStart, dayEnd);
  }

  /// [todayInflow]'un gün penceresini AÇIKÇA alan hâli.
  ///
  /// Çizilen seans günü bugün olmayabilir; pencereyi çağıran taraf verir.
  static double inflowOnDay(
    List<Asset> assets,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
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

  /// Gün içi motorun lot kapısının slot genişliği —
  /// `HistoryService.getPortfolioHistoryHourlyBreakdown` `slotMinutes`.
  static const gunIciSlot = Duration(minutes: 5);

  /// GÜNLÜK dönemin nakit akışı: gün içi serinin AÇILIŞ ölçümünde
  /// ([acilisMs]) henüz OLMAYAN lot'lar.
  ///
  /// Grafik kartı, tür dökümü ve bu sınıf (ana sayfa, widget, kilit
  /// ekranı, Özet GÜNLÜK) aynı fonksiyonu çağırır — "piyasa etkisi" diğer
  /// dönemlerdeki `PeriodSummaryService.piyasaEtkisi` ile aynı ilkeye
  /// oturur: bir lot ya tabandadır ya katkıdadır, ikisinde birden olamaz.
  ///
  /// ## Neden gün başından saymak yanlıştı (2026-09-24 kod incelemesi)
  ///   * Motor lot'u 5 dk'lık kovaya AŞAĞI yuvarlayarak slota koyar
  ///     (14:32'lik alım 14:30 slotunda var). Açılış ölçümü ilk DOLU
  ///     slottur (BIST'te 10:00); açılıştan önce girilen alım (ör. tarih
  ///     seçiciyle 00:00, ya da 09:30) açılış değerinin İÇİNDE ve akışta da
  ///     sayılıyordu: günlük değişim alım tutarı kadar eksiye düşüyordu.
  ///   * GEÇMİŞ seans çizilirken (hafta sonu → Cuma) motor tarih kapısı
  ///     UYGULAMAZ: eldeki pozisyon seansın her slotundadır. O seansın
  ///     günü yapılan alım yine de akıştan düşülüyordu. Geçmiş seansta
  ///     akış yoktur.
  static double gunIciKatki(
    List<Asset> lotlar, {
    required int acilisMs,
    required DateTime seansGunu,
    required DateTime now,
  }) {
    if (dayKey(seansGunu).isBefore(dayKey(now))) return 0;
    // `normalizeSlot(ms) > acilisMs` ⇔ `ms >= acilisMs + slot`
    // (açılış damgası slot hizalı).
    final esik = DateTime.fromMillisecondsSinceEpoch(
        acilisMs + gunIciSlot.inMilliseconds);
    return inflowOnDay(lotlar, esik,
        DateTime(seansGunu.year, seansGunu.month, seansGunu.day, 23, 59, 59));
  }

  /// Gün içi serinin açılış ölçümünün damgası — [dayValues]'un ilk
  /// noktası (şimdiye kadarki ilk DOLU slot).
  static int? acilisDamgasi(Map<int, double> series, DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    int? ilk;
    for (final e in series.entries) {
      if (e.key > nowMs || e.value <= 0) continue;
      if (ilk == null || e.key < ilk) ilk = e.key;
    }
    return ilk;
  }

  /// Kapsamda açık pozisyon kalmadı mı? Canlı toplam 0 iken "fiyat yok"
  /// ile "her şey satıldı"yı ayırır. Sahipler ayrı toplanır
  /// (`lotlarSahibeGore`) — [kapsamToplami] ile aynı sınır.
  static bool acikPozisyonYok(List<Asset> kapsam) {
    for (final l in lotlarSahibeGore(kapsam)) {
      if (aktifLotlar(l).isNotEmpty) return false;
    }
    return true;
  }

  /// Gün içi seriden ve portföy durumundan tam özeti kurar.
  ///
  /// [series] boş ya da tek noktalıysa değişim `null` döner — grafik de
  /// çizilmez. Tek noktalı bir "çizgi" yanıltıcı olurdu.
  ///
  /// [seansGunu] ÇİZİLEN seansın 00:00'ı — bugün olmak zorunda değil
  /// (hafta sonu/tatilde son seans). Hem canlı uç kuralı hem de nakit
  /// akışı penceresi buna göre kurulur; `null` verilirse bugün varsayılır.
  ///
  /// [kapsamLotlari] verildiğinde canlı toplam ve nakit akışı YALNIZCA o
  /// lot'lardan okunur — [state] geriye yalnızca kur çevirici olarak kalır.
  ///
  /// **Neden gerekli (kullanıcı bildirimi, 2026-09-22).** Performans →
  /// Özet sekmesi bir KAPSAM taşır (Ben / bir ortak / Birlikte) ve
  /// `series` o kapsama göre çekilir. Buradaki canlı uç ise `state.assets`
  /// üzerinden tüm defteri topluyordu: ortak sekmesinde ortağın gün içi
  /// eğrisinin ucuna HERKESİN toplamı yazılıyor, gün başı ile uç farklı
  /// kümeleri ölçtüğü için kâr/zarar ve birikim saçmalıyordu. Aynı kayma
  /// nakit akışında da vardı — başka bir sahibin o gün yaptığı alım,
  /// görüntülenen kapsamın hareketinden düşülüyordu.
  ///
  /// Kapsam listesi ham lot defteridir (alım + satış + temettü); sahiplik
  /// sınırı `lotlarSahibeGore` ile yeniden kurulur, yani Birlikte
  /// kapsamında ortakların lot'ları tek havuzda toplanmaz
  /// (bkz. `aggregatePositionsByOwner`).
  static DailySummary from({
    required PortfolioState state,
    required Map<int, double> series,
    required DateTime now,
    DateTime? seansGunu,
    List<Asset>? kapsamLotlari,
  }) {
    final kapsam = kapsamLotlari ?? state.assets;
    // `sonFiyat` ŞART — [liveTotalTRY] ile aynı yol olmalı (2026-09-22).
    // Ayrıştığında ana ekranın toplamı (oradan) ile Bugün kartının günlük
    // kâr/zararı (buradan) farklı kümeleri ölçüyordu: toplam ortağı
    // sayıyor, kâr/zarar saymıyordu. Kullanıcı bildirimi: "anasayfa
    // toplamlar veriyor ancak günlük kartında kâr zarar toplamları
    // tutmuyor."
    final total = kapsamToplami(state, kapsam);
    final values = dayValues(series, now, total,
        seansGunu: seansGunu, acikPozisyonYok: acikPozisyonYok(kapsam));

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
    //
    // Pencere ÇİZİLEN seans günüdür, bugün değil: hafta sonu Cuma'nın
    // eğrisi çizilirken Cumartesi/Pazar girilen bir alım o seansın
    // hareketinden düşülemez (bkz. [todayInflow]). Sınır açılış ölçümüdür,
    // gün başı değil — bkz. [gunIciKatki] (2026-09-24).
    final cizilenGun = seansGunu ??
        cizilenGunFromSeries(series) ??
        dayKey(now);
    final acilis = acilisDamgasi(series, now);
    final inflow = acilis == null
        ? 0.0
        : gunIciKatki(kapsam,
            acilisMs: acilis, seansGunu: cizilenGun, now: now);
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
      inflowTRY: inflow,
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
  static const minInterval = TazelikRitmi.gunIciSeriOmru;

  Map<int, double>? _series;
  DateTime? _fetchedAt;
  DateTime? _seansGunu;

  /// Süren fetch — aynı anda iki yüzey isterse İKİNCİSİ aynı future'ı
  /// bekler, ikinci bir ağ turu atılmaz.
  ///
  /// Üç yüzey bu önbelleği paylaşıyor (Bugün kartı, ana ekran widget'ı,
  /// Live Activity) ve açılışta hepsi birden isteyebiliyor. Tekilleştirme
  /// olmadan iki istek yarışıyor ve GEÇ dönen erken döneni eziyordu —
  /// rakamın "saçmalayıp düzelmesi"nin ikinci kaynağı buydu
  /// (kullanıcı bildirimi 2026-09-22).
  Future<Map<int, double>>? _surenFetch;

  /// Serinin ait olduğu defterin sahibi (`PortfolioState.ownerId`).
  ///
  /// Önbellek süreç ömrüne bağlı, kullanıcıya değil (2026-09-21). Çıkışta
  /// `clear()` çağrılıyor ama kullanıcı değişiminde önceki defter bir kare
  /// daha yayınlanabiliyor ve önbelleği yeniden dolduruyordu: yeni
  /// kullanıcı 5 dakika boyunca ÖNCEKİ kullanıcının gün içi serisiyle
  /// kendi toplamını kıyaslıyor, kilit ekranı ve widget öncekinin
  /// kâr/zararını gösteriyordu. Sahip damgası uyuşmazsa seri koşulsuz düşer.
  String _ownerId = '';

  /// Son başarıyla çekilen seri — hiç çekilmediyse boş.
  Map<int, double> get series => _series ?? const {};

  /// Son çekilen serinin ait olduğu SEANS günü (00:00) — bugün olmak
  /// zorunda değil.
  ///
  /// Piyasa kapalıyken `HistoryService` son seansı döndürür; yüzeylerin
  /// hem canlı uç kuralı hem nakit akışı penceresi buna dayanır. Bu alan
  /// taşınmadığında iki yüzey de "bugün" varsayıyor ve hafta sonu Cuma'nın
  /// eğrisine bugünün akışını uyguluyordu.
  DateTime? get seansGunu => _seansGunu;

  /// Seriyi gerekiyorsa tazeler ve döner.
  ///
  /// Sessizce başarısız olur: ağ hatasında son bilinen seri korunur ve
  /// çağıran taraf yine bir şey gösterebilir.
  /// [azamiYas] verilirse önbellek bundan eskiyse TAZELENİR.
  ///
  /// ## Neden (kullanıcı bildirimi, 2026-09-22)
  /// "ana sayfa günlük ben tabıyla performans tabındaki günlük ben kâr
  /// zarar tutarsız."
  ///
  /// İki yüzey aynı hesabı yapıyor ama FARKLI YAŞTA serilere bakıyordu:
  ///   * Bugün kartı → bu önbellek, [minInterval] = 5 dk
  ///   * Performans  → kendi tick'i, 30 sn (`_startIntradayTickIfNeeded`)
  ///
  /// Gün başı (`open`) serinin ilk noktasından gelir; iki seri farklı
  /// anlarda çekildiğinde o nokta da farklı olabiliyor ve aynı kapsamda
  /// iki farklı kâr/zarar çıkıyordu.
  ///
  /// TTL'yi topluca düşürmek YANLIŞ olurdu: bu önbelleği ana ekran
  /// widget'ı ve Live Activity de kullanıyor ve onlar 5 dk'lık push
  /// döngüsüyle hizalı — daha sık çekmek boşuna ağ trafiği olurdu
  /// ([minInterval] gerekçesi). Bu yüzden tazelik KULLANICININ BAKTIĞI
  /// yüzeyde istenir, varsayılan korunur.
  Future<Map<int, double>> get(
    PortfolioState state, {
    DateTime? now,
    Duration? azamiYas,
  }) async {
    final ts = now ?? DateTime.now();

    // Ekranda duran yüzey daha taze isteyebilir.
    //
    // **Veri SİLİNMEZ, yalnızca "tazele" denir (2026-09-22, ikinci tur).**
    // İlk sürümde burada `_series = null` yapılıyordu ve bu, kullanıcının
    // gördüğü "datalar biraz saçmalayıp düzeliyor" arızasını DOĞURDU:
    //
    //   * Önbellek boşaltılıyor, fetch başlıyor.
    //   * O arada aynı önbelleği çağıran başka bir yüzey (ana ekran
    //     widget'ı, Live Activity) BOŞ seri alıyor.
    //   * Fetch başarısız olursa `_series` null kalıyor ve kart gün başı
    //     olmadan hesap yapıyor.
    //
    // Belirti "Ben" kapsamında görülüyordu çünkü `azamiYas`'ı yalnızca o
    // yol kullanıyor; ortak/Birlikte önbelleğe hiç uğramaz.
    //
    // Doğrusu: eski seri fetch BİTENE KADAR elde kalsın. Aşağıdaki
    // `minInterval` kısa devresi atlanır, yani yeni veri çekilir; ama
    // çekilene kadar gösterilecek bir şey vardır ve hata hâlinde de
    // kaybolmaz.
    final tazeleZorla = azamiYas != null &&
        _fetchedAt != null &&
        ts.difference(_fetchedAt!) > azamiYas;

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

    // Sahip değiştiyse de düşer: başka bir kullanıcının serisi bu deftere
    // ait değildir (bkz. `_ownerId`). Sahibi bilinmeyen state (`''`) eski
    // yolları ve testleri kırmasın diye damgayı olduğu gibi bırakır.
    final sameOwner = state.ownerId.isEmpty || state.ownerId == _ownerId;

    if (!sameDay || !sameOwner) {
      // Dünün (ya da başkasının) serisi DERHAL düşer — fetch başarısız olsa
      // bile bayat baseline'la rakam üretilmemeli.
      _series = null;
      _seansGunu = null;
      _fetchedAt = null;
    } else if (!tazeleZorla && ts.difference(_fetchedAt!) < minInterval) {
      return _series ?? const {};
    }

    // Süren bir fetch varsa ona katıl — ikinci ağ turu atma.
    final suren = _surenFetch;
    if (suren != null) return suren;

    final tamamlayici = Completer<Map<int, double>>();
    _surenFetch = tamamlayici.future;
    try {
      // Breakdown çağrılır, `getPortfolioHistoryHourly` DEĞİL: ikincisi
      // yalnızca `.total` döndürür ve `seansGunu`'nu düşürür. O alan
      // düştüğünde yüzeyler çizilen günü bugün sanıyordu.
      // Eleme Performans ekranıyla AYNI kuraldan (`FiyatKaynagi.seriyeGirer`).
      // Bu önbellek "Ben" kapsamını besliyor ve eleme YOKTU: aynı defterden
      // Performans'tan farklı bir seri üretiyor, iki yüzey farklı kâr/zarar
      // gösteriyordu (kullanıcı bildirimi 2026-09-22).
      final fresh = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown(
              state.activeAssets.where(FiyatKaynagi.seriyeGirer).toList(), 24);
      _series = fresh.total;
      _seansGunu = fresh.seansGunu;
      // Damga yalnızca fetch BAŞARILI olduğunda atılır. Await'ten önce
      // atmak, ağ hatası alan çağrının da pencereyi yakmasına yol açardı:
      // hata sürekliyse seri saatlerce tazelenmez ve yüzeyler sabahki
      // değerde donar — üstelik "Canlı" etiketiyle.
      _fetchedAt = ts;
      _ownerId = state.ownerId;
    } catch (e) {
      if (kDebugMode) debugPrint('Gün içi seri çekilemedi: $e');
    } finally {
      _surenFetch = null;
    }

    final sonuc = _series ?? const <int, double>{};
    tamamlayici.complete(sonuc);
    return sonuc;
  }

  /// Oturum kapanışında çağrılır — bir sonraki kullanıcı öncekinin
  /// grafiğini görmemeli.
  void clear() {
    _series = null;
    _fetchedAt = null;
    _seansGunu = null;
    _ownerId = '';
  }

  /// Önbelleği elle doldurur — sahip/gün kurallarının testi için.
  @visibleForTesting
  void seedForTest({
    required Map<int, double> series,
    required DateTime fetchedAt,
    String ownerId = '',
    DateTime? seansGunu,
  }) {
    _series = series;
    _fetchedAt = fetchedAt;
    _seansGunu = seansGunu;
    _ownerId = ownerId;
  }

  /// Önbellekteki serinin sahibi — test için.
  @visibleForTesting
  String get ownerIdForTest => _ownerId;
}
