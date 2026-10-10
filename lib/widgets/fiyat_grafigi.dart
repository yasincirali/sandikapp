import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
import '../utils/chart_line_width.dart';
import '../utils/spot_lookup.dart';
import '../utils/tr_format.dart';
import 'grafik_stili.dart';
import 'zoomable_chart.dart';

/// Tek varlığın FİYAT grafiği — varlık sayfasının (portföye eklemeden
/// inceleme) grafiği.
///
/// ## Neden yeni bir widget, neden aynı motor
/// Karşılaştır ve takip listesi yüzde çizer ([PercentComparisonChart]):
/// orada birden çok seri aynı eksene sığmalı. Varlık sayfasında tek seri var
/// ve kullanıcının sorusu "şu tarihte fiyatı neydi" — yüzde ekseni bu soruyu
/// cevaplamaz. Etkileşim ise birebir aynı olmalı ("grafikler click ve swipe
/// olaylarında birebir aynı çalışmalı"): pinch, pan, 220 ms basılı tutunca
/// crosshair, alt eksende zaman ölçeği sürüklemesi. Hepsi [ZoomableChart]'tan
/// gelir; bu dosya yalnızca veriyi ve eksenleri kurar.
///
/// Zaman ekseni [zamanEkseni]'nden, fiyat ekseni [gorunurYBandi]'ndan —
/// performans ekranı ve varlık detayıyla aynı kurallar. Değer okuması
/// [coveringSpotIndex]: gösterilen fiyat her zaman o ana kadar BİLİNEN son
/// fiyattır, gelecekteki bir nokta asla okunmaz.
class FiyatGrafigi extends StatelessWidget {
  const FiyatGrafigi({
    super.key,
    required this.seri,
    required this.periodDays,
    required this.bicim,
    required this.semanticLabel,
    this.height = GrafikStili.grafikYuksekligi,
    this.imlecEtiketi,
    this.ucTitresimi = false,
  });

  /// `epoch ms → fiyat`.
  final Map<int, double> seri;

  /// Seçili dönem — X ekseninin penceresini ve adımını belirler (veriden
  /// çıkarılamaz, bkz. [PercentComparisonChart.periodDays]).
  final int periodDays;

  /// Fiyat biçimi — sayfadaki büyük fiyatla AYNI biçimleyici; crosshair ile
  /// başlık aynı sayıyı iki farklı ondalıkla yazmasın.
  final NumberFormat bicim;

  final String semanticLabel;
  final double height;

  /// Bkz. [ZoomableChart.imlecEtiketi]. Varlık sayfası bayrak `goz_alici`
  /// açıkken verir: büyük fiyat parmağı izler.
  final ValueNotifier<(String, String)?>? imlecEtiketi;

  /// `true` → imleç dönemin zirvesine ve dibine oturunca hafif titreşim
  /// (bayrak `goz_alici`; bkz. [ZoomableChart.titresimNoktalari]).
  final bool ucTitresimi;

  /// Eksen bantları ortak grafik stilinden — `rightTitles.reservedSize`
  /// ile [ZoomableChart.plotPaddingRight] aynı (crosshair banda girmez).
  static const _yEkseniGenisligi = GrafikStili.yEkseniGenisligi;
  static const _altEksenYuksekligi = GrafikStili.altEksenYuksekligi;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (final k in (seri.keys.toList()..sort()))
        FlSpot(k.toDouble(), seri[k]!),
    ];
    if (spots.length < 2) {
      return SizedBox(
          height: height + GrafikStili.kartDolgusu.vertical);
    }

    final eksenX = zamanEkseni(
      ilkMs: spots.first.x,
      sonMs: spots.last.x,
      periodDays: periodDays,
    );
    final ilk = spots.first.y;

    // Kart, çizgi, dolgu, ızgara ve "şimdi" işareti ortak grafik stilinden
    // (Performans stili, kullanıcı kararı 2026-09-28). Eskiden bu grafik
    // çerçevesizdi ve çizgi dönemin yönüne göre kırmızı/yeşildi; yön artık
    // başlıktaki yüzdede ve çip getirilerinde, çizgi her ekranda amber.
    return Container(
      decoration: GrafikStili.kart(context),
      padding: GrafikStili.kartDolgusu,
      child: ZoomableChart(
      semanticLabel: semanticLabel,
      height: height,
      fullMinX: eksenX.min,
      // Sağda küçük pay: "şimdi" noktası (r=6) ve ŞİMDİ etiketi eksen
      // ayracına yapışıp kırpılmasın (varlık detayı aynı işi +%8 ile yapar).
      fullMaxX: eksenX.max + (eksenX.max - eksenX.min) * 0.04,
      bottomAxisHeight: _altEksenYuksekligi,
      plotPaddingRight: _yEkseniGenisligi,
      imlecEtiketi: imlecEtiketi,
      titresimNoktalari: ucTitresimi ? donemUclariX(spots) : const {},
      crosshairSnapX: (x) {
        // Clamp EKSENE, seriye değil — seans dışı saatler ölü bölge olmasın
        // (bkz. PercentComparisonChart.crosshairSnapX).
        final clamped = x.clamp(eksenX.min, eksenX.max);
        final i = coveringSpotIndex(spots, clamped);
        return i < 0 ? clamped : spots[i].x;
      },
      crosshairLabelBuilder: (x) {
        final i = coveringSpotIndex(spots, x);
        if (i < 0) return null;
        final s = spots[i];
        final t = DateTime.fromMillisecondsSinceEpoch(s.x.round());
        return (
          bicim.format(s.y),
          eksenX.gunIci
              ? DateFormat('d MMM HH:mm', 'tr_TR').format(t)
              : fmtTarihSaat(t),
        );
      },
      // Dönem başına göre değişim: "buradan bugüne ne oldu" değil, "dönem
      // başından bu ana ne oldu" — başlıktaki yüzdeyle aynı taban.
      crosshairDetailsBuilder: (x) {
        final i = coveringSpotIndex(spots, x);
        if (i < 0 || ilk <= 0) return const [];
        final pct = (spots[i].y - ilk) / ilk * 100;
        return [
          (
            fmtPctIsaretli(pct),
            pct.abs() < 0.005 ? context.c.text58 : context.signColor(pct),
          ),
        ];
      },
      builder: (minX, maxX) =>
          _data(context, spots, eksenX, minX, maxX),
      ),
    );
  }

  LineChartData _data(
    BuildContext context,
    List<FlSpot> tam,
    ({double min, double max, double interval, double baseline, bool gunIci})
        eksenX,
    double minX,
    double maxX,
  ) {
    final gorunur = _gorunur(tam, minX, maxX);

    var mn = gorunur.first.y, mx = gorunur.first.y, top = 0.0;
    for (final s in gorunur) {
      if (s.y < mn) mn = s.y;
      if (s.y > mx) mx = s.y;
      top += s.y;
    }
    final bant = gorunurYBandi(
      dataMinY: mn,
      dataMaxY: mx,
      avgY: top / gorunur.length,
      asgariBantOrani: eksenX.gunIci ? gunIciAsgariBantOrani : 0.02,
    );
    // Hane adımı TAM gösterir (0,25 → iki hane, 5 → hanesiz): eski merdiven
    // (<1 → 2, <10 → 1) 0,005'lik adımda komşu etiketleri aynı metne
    // düşürebiliyordu (2026-09-29 emülatör testi #7, "₺1 | ₺1").
    final ondalik = eksenOndaligi(bant.interval);
    // Eksende para simgesi var (₺320) — Performans ve varlık detayıyla aynı.
    final eksenBicimi =
        tryFormatter(digits: ondalik, symbol: bicim.currencySymbol);
    final span = maxX - minX;
    final spanGun = span / const Duration(days: 1).inMilliseconds;
    // Etiketler ekran genişliğine göre seyrelir (`xEtiketiAtlanir`).
    final xStil = GrafikStili.eksenYazisi(context);
    final etiketPx = GrafikStili.xEtiketAraligi(
      zamanEtiketiOrnegi(spanGun: spanGun, gunIci: eksenX.gunIci),
      stil: xStil,
      olcek: MediaQuery.textScalerOf(context),
    );

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: bant.minY,
      maxY: bant.maxY,
      // Pan/pinch lerp karelerinde çizgi eksen etiketlerinin üstüne taşmasın
      // — performans ekranları ve ortak yüzde grafiğiyle aynı bayrak.
      clipData: const FlClipData.all(),
      baselineX: eksenX.baseline,
      lineBarsData: [
        LineChartBarData(
          spots: gorunur,
          color: GrafikStili.cizgi(context),
          // Kalınlık döneme bağlı — performans ekranıyla aynı merdiven.
          barWidth: donemCizgiKalinligi(periodDays),
          // Eğri interpolasyon veride olmayan tepe ve dip uydurur.
          isCurved: false,
          // Yalnızca "şimdi" (serinin son) noktası — Performans stili.
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.x == tam.last.x,
            getDotPainter: (_, __, ___, ____) =>
                GrafikStili.simdiNoktasi(context),
          ),
          belowBarData: GrafikStili.dolgu(context),
        ),
      ],
      // Dönem başı çizgisi (tarih + değer etiketli) ve gün içi dışında
      // "ŞİMDİ" işareti — varlık detayı ve Performans ile aynı.
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          GrafikStili.donemBasi(
            context,
            tam.first.y,
            etiket: GrafikStili.donemBasiEtiketi(
              context,
              an: DateTime.fromMillisecondsSinceEpoch(tam.first.x.round()),
              deger: bicim.format(tam.first.y),
              gunIci: eksenX.gunIci,
            ),
          ),
        ],
        verticalLines: [
          if (!eksenX.gunIci) GrafikStili.simdiCizgisi(context, tam.last.x),
        ],
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: eksenX.gunIci,
        verticalInterval: eksenX.interval,
        getDrawingVerticalLine: (_) => GrafikStili.izgara(context),
        horizontalInterval: bant.interval,
        getDrawingHorizontalLine: (_) => GrafikStili.izgara(context),
      ),
      borderData: GrafikStili.eksenAyraci(context),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _yEkseniGenisligi,
            interval: bant.interval,
            getTitlesWidget: (value, meta) {
              if (value <= meta.min || value >= meta.max) {
                return const SizedBox.shrink();
              }
              return GrafikStili.yEtiketi(eksenBicimi.format(value).trim(),
                  stil: GrafikStili.eksenYazisi(context));
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _altEksenYuksekligi,
            interval: eksenX.interval,
            getTitlesWidget: (value, meta) {
              if (eksenKenarinda(value, meta.min, meta.max) ||
                  xEtiketiAtlanir(value,
                      aralik: meta.max - meta.min,
                      tickAraligi: meta.appliedInterval,
                      eksenPx: meta.parentAxisSize,
                      etiketPx: etiketPx,
                      taban: eksenX.baseline)) {
                return const SizedBox.shrink();
              }
              final t = DateTime.fromMillisecondsSinceEpoch(value.round());
              return GrafikStili.xEtiketi(
                zamanEtiketi(t, spanGun: spanGun, gunIci: eksenX.gunIci),
                stil: xStil,
              );
            },
          ),
        ),
      ),
      // Değer okuma crosshair'den gelir (ZoomableChart). fl_chart'ın kendi
      // dokunma katmanı kapalı — açık kalırsa iki ayrı tooltip çizilir.
      lineTouchData: const LineTouchData(
        enabled: false,
        handleBuiltInTouches: false,
      ),
    );
  }

  /// Viewport'a düşen noktalar, kenarların bir dışındaki dahil — seyreltme
  /// YOK (sıklık `ResolutionTierMeta.pickForSpan`'den gelir, bkz.
  /// `PercentComparisonChart._gorunurSpots`).
  static List<FlSpot> _gorunur(List<FlSpot> tam, double minX, double maxX) {
    var bas = 0;
    while (bas + 1 < tam.length && tam[bas + 1].x < minX) {
      bas++;
    }
    var son = tam.length - 1;
    while (son > bas && tam[son - 1].x > maxX) {
      son--;
    }
    return tam.sublist(bas, son + 1);
  }
}

/// Serinin en yüksek ve en düşük noktasının X'i (ilk rastlanan). Düz ya da
/// tek noktalı seride tek X döner; boş seride boş küme.
Set<double> donemUclariX(List<FlSpot> spots) {
  if (spots.isEmpty) return const {};
  var ust = spots.first;
  var alt = spots.first;
  for (final s in spots) {
    if (s.y > ust.y) ust = s;
    if (s.y < alt.y) alt = s;
  }
  return {ust.x, alt.x};
}
