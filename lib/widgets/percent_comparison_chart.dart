import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
import '../utils/series_downsample.dart';
import '../utils/spot_lookup.dart';
import '../utils/tr_format.dart';
import 'zoomable_chart.dart';

/// Yüzde bazlı karşılaştırma grafiği — **Karşılaştır ve Takip ekranlarının
/// ORTAK motoru.**
///
/// ## Neden ortak
/// İki ekran aynı grafiği çiziyordu ama iki ayrı kopyayla, ve kopyalar
/// ayrışmıştı: takip grafiğinde çizgiye dokunmak seriye odaklanıyordu,
/// Karşılaştır'da beş seri çizilmesine rağmen `touchCallback` hiç yoktu;
/// takipte eksen adımı yuvarlanmışken Karşılaştır'da etiketler tekrar
/// ediyordu; ikisinde de zoom, pan ve crosshair yoktu — oysa performans
/// ekranları bunların üçünü de veriyordu. Kullanıcının "grafikler click ve
/// swipe olaylarında birebir aynı çalışmalı" bulgusunun kaynağı buydu.
///
/// Artık tek bir yüzey var: burada düzelen her şey iki ekranda birden düzelir.
///
/// ## Etkileşim sözleşmesi
/// Etkileşimin tamamı [ZoomableChart]'tan gelir — performans ekranlarıyla
/// **aynı** motor:
///   · pinch (her açıda) → zoom
///   · zoom'dayken tek parmak → pan
///   · alt eksen şeridinde yatay sürükleme → zaman ölçeğini sıkıştır/genişlet
///   · 220 ms basılı tutma → crosshair, parmakla gezdirilir
///   · çizgiye dokunma → o seriye odaklan, aynısına tekrar dokunma odağı kaldırır
///   · zoom'dayken sağ üstte "Sıfırla"
///
/// **Zoom'suzken tek parmak pan bilinçli olarak yok**: viewport zaten tüm
/// aralığı kaplar, kaydırılacak yer olmadığı için jest hiçbir şey yapmaz —
/// ama arena'da kazanıp sarmalayan listenin dikey kaydırmasını yutardı.
///
/// ## Neden yüzde
/// Dönem başı `%0` kabul edilir. Ham fiyatla çizmek anlamsız olurdu: ₺12'lik
/// bir hisse ile ₺4.800'lük altın aynı eksende görünmez. Yüzde ayrıca sahip
/// OLUNMAYAN varlığın doğasına uygun — "kazancı" tanımsızdır, tanımlı olan tek
/// şey fiyatın yüzde kaç değiştiğidir.
class PercentComparisonChart extends StatelessWidget {
  const PercentComparisonChart({
    super.key,
    required this.series,
    required this.order,
    required this.colorOf,
    required this.labelOf,
    required this.periodDays,
    this.emphasizedKey,
    this.focused,
    this.onFocusChanged,
    this.height = 210,
  });

  /// `anahtar → normalize edilmiş seri`.
  final Map<String, NormalizedSeries> series;

  /// Çizim SIRASI. fl_chart son barı en üste çizer; vurgulanan seri (portföy
  /// çizgisi) sona konursa diğerlerinin altında kalmaz.
  ///
  /// Sıra çağırana bırakıldı çünkü iki ekranın önceliği farklı: Takip
  /// listesinde portföy en üstte durmalı, Karşılaştır'da seçim sırası korunur.
  final List<String> order;

  /// Seri rengi. Odak solukluğu BURADA uygulanmaz — widget kendisi ekler.
  final Color Function(String key) colorOf;

  /// Tooltip ve crosshair'de görünen ad.
  final String Function(String key) labelOf;

  /// Seçili dönemin gün sayısı — X ekseninin penceresini ve adımını belirler.
  ///
  /// **Veriden ÇIKARILAMAZ.** GÜNLÜK ekseni son veri noktasının ötesine,
  /// günün sonuna kadar uzar (bkz. [gunIciEksenSonuDk]); serinin kapladığı
  /// aralığa bakarak "bu bir gün mü" diye tahmin etmek sabah 09:00'da
  /// 9 saatlik bir pencere üretirdi. Dönemi bilen taraf çağırandır.
  final int periodDays;

  /// Kalın çizilecek seri (portföy kıyas çizgisi). Kıyas noktası olduğu
  /// çizgi kalınlığından da okunmalı, yalnızca renkten değil.
  final String? emphasizedKey;

  /// Odaklanılan seri. Odak bir FİLTRE DEĞİL: diğerleri ekrandan kalkmaz,
  /// soluklaşır — kıyas ancak diğerleri görünürken anlamlıdır.
  final String? focused;

  /// Çizgiye dokunulduğunda çağrılır. `null` verilirse dokunma odak
  /// değiştirmez (yalnızca tooltip çalışır).
  final ValueChanged<String?>? onFocusChanged;

  final double height;

  /// Alt eksen etiket şeridinin yüksekliği. [ZoomableChart] yalnızca bu
  /// şeritte zaman ölçeği sürüklemesini yakalar, üstü pinch'e serbest kalır.
  static const _bottomAxisHeight = 26.0;

  static const _bosDurumYuksekligi = 200.0;

  @override
  Widget build(BuildContext context) {
    final p = context.c;

    final ciz = _hazirla();
    if (ciz == null) return _bosDurum(context);

    return LayoutBuilder(builder: (context, kisit) {
      // Seyreltme hedefi GERÇEK çizim genişliğinden hesaplanır; sabit bir
      // sayı dar telefonda çok yoğun, geniş ekranda gereksiz kaba olurdu.
      final hedefNokta = hedefNoktaSayisi(
        kisitGenisligi: kisit.maxWidth,
        periodDays: periodDays,
      );

      return ZoomableChart(
        height: height,
        fullMinX: ciz.minX,
        fullMaxX: ciz.maxX,
        bottomAxisHeight: _bottomAxisHeight,
        // Sol Y ekseni rezervi — crosshair'in etiket bandına girmemesi için
        // `leftTitles.reservedSize` ile AYNI olmak zorunda.
        plotPaddingLeft: _yEkseniGenisligi,
        crosshairSnapX: (x) {
          // En yoğun seriye snap: dikey çizgi gerçek bir veri noktasına otursun,
          // aradaki boşluğa değil.
          final spots = ciz.snapSpots;
          if (spots.isEmpty) return x;
          // **Clamp EKSENE, snap serisine DEĞİL.** Snap serisi ekseni tam
          // kaplamayabilir (BIST hissesi yalnızca seans saatlerini kapsar,
          // eksen ise geceyi de içerir). Seriye clamp'lemek ekseninin bir
          // bölümünü ÖLÜ BÖLGEYE çeviriyordu: kullanıcı sola dokunduğunda
          // crosshair 14 saat sağa zıplıyor ve grafiğin %64'ünde hiç
          // gezdirilemiyordu — "tüm grafiğin üzerinde gezdiremiyorum" bulgusu.
          final clamped = x.clamp(ciz.minX, ciz.maxX);
          // `_degerAt` ve `crosshairLabelBuilder` ile AYNI arama — üçü ayrışırsa
          // dikey çizgi bir noktayı, etiket başka bir noktayı gösterir.
          final i = coveringSpotIndex(spots, clamped);
          // Eksenin başı snap serisinden önceyse ham konumu koru: zıplatmak
          // yerine çizgi parmağın altında kalsın.
          return i < 0 ? clamped : spots[i].x;
        },
        crosshairLabelBuilder: (x) {
          final spots = ciz.snapSpots;
          if (spots.isEmpty) return null;
          // Değer ile TARİH aynı noktadan okunur. Eskiden yüzde en yakın
          // noktadan, tarih ise ham `x`'ten geliyordu; snap sonrası ikisi
          // birbirini tutuyordu ama snap noktası ile ham `x` arasındaki fark
          // kadar tarih kayabiliyordu. Tek kaynak = tutarlılık garantisi.
          final i = coveringSpotIndex(spots, x);
          // Snap serisi henüz başlamamışsa yüzde göstermek uydurma olurdu;
          // tarih yine de gösterilir — kullanıcı nereye baktığını bilmeli.
          if (i < 0) {
            final t = DateTime.fromMillisecondsSinceEpoch(x.round());
            final span = ciz.maxX - ciz.minX;
            final b = span < const Duration(days: 2).inMilliseconds
                ? DateFormat('d MMM HH:mm', 'tr_TR')
                : DateFormat('d MMM yyyy', 'tr_TR');
            return ('—', b.format(t));
          }
          final s = spots[i];
          final tarih = DateTime.fromMillisecondsSinceEpoch(s.x.round());
          // Gün içi seride tarih tek başına yetmez — saat de gösterilmeli,
          // yoksa "4 Eyl 2026" etiketi 288 noktanın hepsi için aynı görünür.
          final span = ciz.maxX - ciz.minX;
          final bicim = span < const Duration(days: 2).inMilliseconds
              ? DateFormat('d MMM HH:mm', 'tr_TR')
              : DateFormat('d MMM yyyy', 'tr_TR');
          return (
            fmtPct(s.y, digits: 1, showSign: true),
            bicim.format(tarih),
          );
        },
        // Crosshair açıkken her serinin o andaki değeri listelenir — kıyasın
        // asıl sorusu "şu tarihte kim neredeydi".
        crosshairDetailsBuilder: (x) => [
          for (var i = 0; i < ciz.cizilenler.length; i++)
            if (_degerAt(ciz.bars[i].spots, x) case final y?)
              (
                '${labelOf(ciz.cizilenler[i])}  '
                    '${fmtPct(y, digits: 1, showSign: true)}',
                colorOf(ciz.cizilenler[i])
              ),
        ],
        builder: (minX, maxX) => _data(p, ciz, minX, maxX, hedefNokta),
      );
    });
  }

  /// `leftTitles.reservedSize` ile aynı — ikisi ayrışırsa crosshair etiket
  /// bandının içine girer.
  static const _yEkseniGenisligi = 42.0;

  /// İki komşu nokta arasında bırakılacak asgari yatay mesafe (piksel).
  ///
  /// **Neden sabit bir nokta sayısı değil.** Önce sabit 160 nokta hedefi
  /// vardı; telefonun ~300px'lik çizim alanında bu, nokta başına 1,9px
  /// demekti — 5 dakikalık gün içi seride (288 nokta) neredeyse hiç
  /// seyreltme yapmıyor, çizgi kendi üstüne binerek karalamaya dönüşüyordu.
  /// Ölçüldü: GÜNLÜK sekmesinde 288 nokta → 160 nokta, yani %44 azalma;
  /// 3px kuralıyla aynı seri ~100 noktaya iner ve zikzak açılır.
  ///
  /// Hedef gerçek genişlikten hesaplandığı için tablet/yatay modda otomatik
  /// olarak daha çok detay gösterilir — sabit sayı orada tersine, gereksiz
  /// bilgi kaybı demekti.
  ///
  /// 3px: fl_chart çizgiyi 1,8–4px kalınlıkta çiziyor, yani bundan sık
  /// noktalar çizginin kendi kalınlığının içinde kalır.
  static const _pikselBasinaNokta = 3.0;

  /// GÜNLÜK için aynı kuralın seyreltilmiş hâli.
  ///
  /// **Neden gün içi AYRI:** diğer dönemler günlük/haftalık kapanış taşır ve
  /// 3px kuralıyla zaten okunur çıkıyor (kullanıcı: "diğerleri düzgün
  /// çalışıyor"). Gün içi seri 5 dakikalıktır ve taşıdığı dalgalanmanın
  /// büyük kısmı alım-satım gürültüsüdür; aynı kural orada ~100 zikzak
  /// üretiyor ve çizgi tarak gibi görünüyordu.
  ///
  /// **Seyreltme çizgiyi DÜZLEŞTİRMEZ.** `seyreltSpots` her kova için en
  /// düşük ve en yüksek noktayı korur — dış zarf birebir aynı kalır, yalnızca
  /// aradaki okunamayan salınım azalır. Kasıtlı: fiyat grafiğini yumuşatmak,
  /// veride gerçekten olan bir sıçramayı gizlemek demektir.
  ///
  /// 7px ~300px'lik telefon çizim alanında ~42 nokta demek; 5 dakikalık
  /// tam günde (288 nokta) her kova ~14 dakikayı temsil eder. Zoom
  /// yapıldıkça pencere daralır ve detay geri gelir.
  static const _gunIciPikselBasinaNokta = 7.0;

  /// Çizim alanı genişliği okunamadığında (sonsuz constraint) varsayılan.
  static const _varsayilanGenislik = 360.0;

  /// Viewport'a kaç nokta serpiştirileceği.
  ///
  /// `build` içine gömülü bir ifade olarak duruyordu ve o hâliyle hiçbir
  /// testle denetlenemiyordu: gün içi kuralının sessizce kaybolması ya da
  /// diğer dönemlerle eşitlenmesi fark edilmezdi. Saf fonksiyon olarak
  /// ayrılması kuralı doğrudan sorulabilir yapar.
  ///
  /// [kisitGenisligi] LayoutBuilder'ın verdiği ham genişliktir; Y ekseni
  /// rezervi burada düşülür.
  ///
  /// Alt sınır 20: dar bir telefonda gün içi kuralı 40'a kırpılsaydı kural
  /// pratikte devre dışı kalırdı (300px/7 ≈ 43, 200px/7 ≈ 29).
  /// `seyreltSpots` 4'ün altında zaten seyreltme yapmıyor.
  @visibleForTesting
  static int hedefNoktaSayisi({
    required double kisitGenisligi,
    required int periodDays,
  }) {
    final cizimGenisligi =
        (kisitGenisligi.isFinite ? kisitGenisligi : _varsayilanGenislik) -
            _yEkseniGenisligi;
    // Gün içi seri diğerlerinden çok daha sık örneklenir; aralık kuralı da
    // o yüzden döneme bağlı (bkz. [_gunIciPikselBasinaNokta]).
    final aralik =
        periodDays <= 1 ? _gunIciPikselBasinaNokta : _pikselBasinaNokta;
    return (cizimGenisligi / aralik).round().clamp(20, 400);
  }

  /// Viewport'a düşen noktalar, ekran yoğunluğuna indirgenmiş.
  ///
  /// Seyreltme HER VIEWPORT için yeniden yapılır: zoom yapıldıkça aynı
  /// pencereye daha az ham nokta düşer ve detay geri gelir — `ZoomableChart`
  /// ile `DotThinner`'ın zaten verdiği söz.
  ///
  /// Kenarların bir dışındaki nokta korunur; aksi halde çizgi grafiğin
  /// kenarına ulaşmadan biter.
  static List<FlSpot> _gorunurSpots(
      List<FlSpot> tam, double minX, double maxX, int hedefNokta) {
    if (tam.length < 2) return tam;

    var bas = 0;
    while (bas + 1 < tam.length && tam[bas + 1].x < minX) {
      bas++;
    }
    var son = tam.length - 1;
    while (son > bas && tam[son - 1].x > maxX) {
      son--;
    }

    return seyreltSpots(tam.sublist(bas, son + 1), hedefNokta);
  }

  Widget _bosDurum(BuildContext context) => SizedBox(
        height: _bosDurumYuksekligi,
        child: Center(
          child: Text(
            'Grafik için yeterli fiyat geçmişi yok.',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ),
      );

  /// Serinin [x] anındaki yüzdesi — [x]'i KAPSAYAN noktadan.
  ///
  /// **"En yakın" DEĞİL "kapsayan".** Seriler farklı yoğunlukta olabiliyor:
  /// USDTRY=X GÜNLÜK'te 5 dakikada bir tikler, bir TEFAS fonu günde bir fiyat
  /// açıklar. Crosshair en uzun seriye snap ettiği için, seyrek serilerde
  /// "en yakın" nokta İLERİDE olabiliyordu — kullanıcı 06:00'a basarken
  /// 12:00'nin değeri gösteriliyor, üstelik üstteki tarih göstergesi 06:00
  /// yazıyordu (ölçüldü: en kötü sapma 11 sa 55 dk).
  ///
  /// Kapsayan nokta (`spot.x <= x` olan son nokta) bu tutarsızlığı kaldırır:
  /// gösterilen değer her zaman o ana kadar BİLİNEN son değerdir — fiyat
  /// grafiklerinin standart okuması. İşlem noktalarında da aynı gerekçeyle
  /// `coveringSpotIndex` kullanılıyor.
  ///
  /// [x] serinin ilk noktasından önceyse `null` — o seri henüz başlamamıştır
  /// ve uydurma bir değer göstermek yanlış olurdu.
  double? _degerAt(List<FlSpot> spots, double x) {
    if (spots.isEmpty) return null;
    final i = coveringSpotIndex(spots, x);
    return i < 0 ? null : spots[i].y;
  }

  /// Bar'ları ve eksen sınırlarını tek geçişte hazırlar.
  ///
  /// `null` dönerse çizilecek seri yok (her seri iki noktadan kısa).
  _CizimVerisi? _hazirla() {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    final bars = <LineChartBarData>[];
    // `bars` ile AYNI SIRADA. Tooltip ve odak, barIndex'i buradan çözer.
    //
    // Bu liste ayrı tutuluyor çünkü Karşılaştır ekranında hata tam da burada
    // çıkmıştı: bar'lar yalnızca YÜKLENMİŞ serilerden kuruluyor, tooltip ise
    // barIndex'i seçim listesinde arıyordu. Bir sembol yüklenmemişse tooltip
    // yanlış ticker ve yanlış renk gösteriyordu.
    final cizilenler = <String>[];
    var snapSpots = const <FlSpot>[];

    for (final key in order) {
      final norm = series[key];
      if (norm == null) continue;

      final keys = norm.points.keys.toList()..sort();
      final spots = [
        for (final k in keys) FlSpot(k.toDouble(), norm.points[k]!),
      ];
      // Tek noktalı seri ÇİZİLMEZ; sınırları da genişletmemeli. Aksi halde
      // çizilmeyen bir veri, çizilenlerin eksenini kaydırırdı.
      if (spots.length < 2) continue;

      for (final s in spots) {
        if (s.x < minX) minX = s.x;
        if (s.x > maxX) maxX = s.x;
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }

      final vurgulu = key == emphasizedKey;
      final temelRenk = colorOf(key);
      final odakVar = focused != null;
      final buOdakta = focused == key;

      bars.add(LineChartBarData(
        spots: spots,
        color: odakVar && !buOdakta
            ? temelRenk.withValues(alpha: 0.18)
            : temelRenk,
        barWidth: buOdakta ? (vurgulu ? 4 : 3) : (vurgulu ? 3 : 1.8),
        // Tüm çizgi grafiklerde AYNI: eğri interpolasyon veride olmayan
        // tepe ve dip uydurur, fiyat grafiğinde bu yanıltıcıdır.
        isCurved: false,
        dotData: const FlDotData(show: false),
      ));
      cizilenler.add(key);
      // Crosshair en uzun seriye snap eder — en ince adımı o verir.
      if (spots.length > snapSpots.length) snapSpots = spots;
    }

    if (bars.isEmpty) return null;

    // Y ekseninde nefes payı; düz çizgide (minY == maxY) sıfıra bölme olmasın.
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);
    final pad = span * 0.12;

    return _CizimVerisi(
      bars: bars,
      cizilenler: cizilenler,
      snapSpots: snapSpots,
      // **Eksen veriden DEĞİL dönemden türetilir.** Veri aralığına oturtmak
      // GÜNLÜK sekmesinde ekseni gün ilerledikçe büyüyen bir pencereye
      // çeviriyordu (sabah 09:00'da 9 saat, akşam 18:00'de 18 saat) ve
      // performans ekranının sabit 00:00 → 24:00 ölçeğiyle ayrışıyordu.
      eksenX: zamanEkseni(
        ilkMs: minX,
        sonMs: maxX,
        periodDays: periodDays,
      ),
      eksen: yuzdeEkseni(minY - pad, maxY + pad),
    );
  }

  LineChartData _data(SandikPalette p, _CizimVerisi ciz, double minX,
      double maxX, int hedefNokta) {
    final eksen = ciz.eksen;
    final span = maxX - minX;

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: eksen.min,
      maxY: eksen.max,
      // Bar'lar TAM çözünürlükte tutulur (crosshair gerçek veriye snap etsin),
      // çizime giderken viewport'a kırpılıp seyreltilir.
      lineBarsData: [
        for (final b in ciz.bars)
          b.copyWith(spots: _gorunurSpots(b.spots, minX, maxX, hedefNokta)),
      ],
      // Sıfır çizgisi = dönem başı. Olmadan yüzdelerin neye göre okunacağı
      // belirsiz kalır.
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: 0,
            color: p.text36.withValues(alpha: 0.4),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ],
      ),
      // Tick'lerin nereye oturacağını belirler. fl_chart varsayılan olarak
      // 0'ı (1970-01-01 UTC) taban alıp adımın katlarını işaretler; epoch
      // milisaniye uzayında bu, UTC+3'te "03:00 · 07:00 · 11:00" gibi kayık
      // etiketler demekti. Taban gün başına alınınca tick'ler performans
      // ekranındaki gibi 00:00 · 04:00 · 08:00'a oturur.
      baselineX: ciz.eksenX.baseline,
      gridData: FlGridData(
        show: true,
        // Gün içi seride dikey ızgara VAR — performans ekranının GÜNLÜK
        // sekmesiyle aynı: saat dilimleri okunur bir referans verir. Uzun
        // dönemlerde çizgiler veriyi bastırdığı için kapalı kalır.
        drawVerticalLine: ciz.eksenX.gunIci,
        verticalInterval: ciz.eksenX.interval,
        getDrawingVerticalLine: (_) =>
            FlLine(color: p.hairline, strokeWidth: 1),
        // Izgara çizgileri etiketlerle AYNI adımda olmalı; ayrışırsa çizgiler
        // etiketsiz, etiketler çizgisiz kalır.
        horizontalInterval: eksen.interval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: p.hairline, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _bottomAxisHeight,
            // **Adım ham `span / 4` DEĞİL.** Ham bölme, eksenin başladığı
            // rastgele ana kilitleniyordu: GÜNLÜK sekmesinde etiketler
            // "14:30 · 20:30 · 02:30 · 08:30" okunuyordu. Performans ekranı
            // aynı günü 4 saatlik yuvarlak adımlarla çiziyor; kural artık
            // ortak (`zamanEkseni`).
            interval: ciz.eksenX.interval,
            getTitlesWidget: (value, meta) {
              // Kenar payı performans ekranıyla aynı (%6). Salt
              // `value <= meta.min` kontrolü zoom'da yetmiyordu: adım artık
              // sınırlara denk gelmediği için kenara bir tık uzak bir tick
              // etiketi çizim alanının dışına taşıyordu.
              if (eksenKenarinda(value, meta.min, meta.max)) {
                return const SizedBox.shrink();
              }
              final t = DateTime.fromMillisecondsSinceEpoch(value.round());
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  zamanEtiketi(t,
                      spanGun: span / const Duration(days: 1).inMilliseconds,
                      gunIci: ciz.eksenX.gunIci),
                  style: TextStyle(fontSize: 9, color: p.text36),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _yEkseniGenisligi,
            // Adım AÇIKÇA verilir — verilmezse fl_chart kendi seçer ve dar
            // bantlarda etiketler tekrar eder ("+0%, +0%, +1%").
            interval: eksen.interval,
            getTitlesWidget: (value, meta) {
              // Kenar etiketleri kırpılır ve komşusuyla üst üste biner.
              if (value <= meta.min || value >= meta.max) {
                return const SizedBox.shrink();
              }
              // Kayan nokta hatası: 15.000000000000002 gibi değerler ondalık
              // gösterimde "15,0" yerine gürültü üretir.
              final v = (value / eksen.interval).round() * eksen.interval;
              return Text(
                '${v >= 0 ? '+' : ''}'
                '${v.toStringAsFixed(eksen.ondalik).replaceAll('.', ',')}%',
                style: TextStyle(fontSize: 10, color: p.text58),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        // Çizgiye dokunmak o seriye ODAKLANIR; aynısına tekrar dokunmak odağı
        // kaldırır. `charts_screen`'deki donut `touchCallback` deseninin
        // aynısı — kullanıcı her grafikte aynı davranışı görsün.
        touchCallback: (event, response) {
          if (onFocusChanged == null) return;
          // Yalnızca TAP: sürükleme tooltip gezdirmek içindir, her hareket
          // odağı değiştirseydi grafik okunamaz hale gelirdi.
          if (event is! FlTapUpEvent) return;
          final spots = response?.lineBarSpots;
          if (spots == null || spots.isEmpty) {
            // Boşluğa dokunma odağı temizler — çıkış yolu her zaman açık.
            onFocusChanged!(null);
            return;
          }
          final i = spots.first.barIndex;
          if (i < 0 || i >= ciz.cizilenler.length) return;
          onFocusChanged!(
              yeniOdak(mevcut: focused, dokunulan: ciz.cizilenler[i]));
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => p.surface2,
          getTooltipItems: (spots) => spots.map((s) {
            // barIndex her zaman ÇİZİLEN seriler üzerinde çözülür — seçim
            // listesi üzerinde değil. Yüklenememiş bir sembol varken bu ikisi
            // ayrışıyor ve tooltip yanlış varlığı gösteriyordu.
            final key = s.barIndex < ciz.cizilenler.length
                ? ciz.cizilenler[s.barIndex]
                : null;
            return LineTooltipItem(
              '${key == null ? '' : labelOf(key)}  '
              '${fmtPct(s.y, digits: 1, showSign: true)}',
              TextStyle(
                color: key == null ? p.text90 : colorOf(key),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Tek geçişte hesaplanan çizim girdileri.
class _CizimVerisi {
  const _CizimVerisi({
    required this.bars,
    required this.cizilenler,
    required this.snapSpots,
    required this.eksenX,
    required this.eksen,
  });

  final List<LineChartBarData> bars;

  /// `bars` ile aynı sıradaki seri anahtarları.
  final List<String> cizilenler;

  /// Crosshair'in snap edeceği referans seri.
  final List<FlSpot> snapSpots;

  /// Zaman ekseni — pencere, adım ve tick hizası. Veri aralığından DEĞİL,
  /// dönemden türetilir (bkz. [zamanEkseni]).
  final ({
    double min,
    double max,
    double interval,
    double baseline,
    bool gunIci
  }) eksenX;

  double get minX => eksenX.min;
  double get maxX => eksenX.max;

  final ({double min, double max, double interval, int ondalik}) eksen;
}
