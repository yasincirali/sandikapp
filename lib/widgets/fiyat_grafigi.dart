import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
import '../utils/chart_line_width.dart';
import '../utils/spot_lookup.dart';
import '../utils/tr_format.dart';
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
    required this.renk,
    required this.semanticLabel,
    this.height = 220,
  });

  /// `epoch ms → fiyat`.
  final Map<int, double> seri;

  /// Seçili dönem — X ekseninin penceresini ve adımını belirler (veriden
  /// çıkarılamaz, bkz. [PercentComparisonChart.periodDays]).
  final int periodDays;

  /// Fiyat biçimi — sayfadaki büyük fiyatla AYNI biçimleyici; crosshair ile
  /// başlık aynı sayıyı iki farklı ondalıkla yazmasın.
  final NumberFormat bicim;

  /// Çizgi rengi — dönem yönünden gelir (başlıktaki yüzdeyle aynı kaynak).
  final Color renk;

  final String semanticLabel;
  final double height;

  /// `rightTitles.reservedSize` ile AYNI — crosshair etiket bandına girmez.
  static const _yEkseniGenisligi = 56.0;
  static const _altEksenYuksekligi = 26.0;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (final k in (seri.keys.toList()..sort()))
        FlSpot(k.toDouble(), seri[k]!),
    ];
    if (spots.length < 2) return SizedBox(height: height);

    final eksenX = zamanEkseni(
      ilkMs: spots.first.x,
      sonMs: spots.last.x,
      periodDays: periodDays,
    );
    final ilk = spots.first.y;

    return ZoomableChart(
      semanticLabel: semanticLabel,
      height: height,
      fullMinX: eksenX.min,
      fullMaxX: eksenX.max,
      bottomAxisHeight: _altEksenYuksekligi,
      plotPaddingRight: _yEkseniGenisligi,
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
            fmtPct(pct, digits: 2, showSign: true),
            pct.abs() < 0.005 ? context.c.text58 : context.signColor(pct),
          ),
        ];
      },
      builder: (minX, maxX) =>
          _data(context, spots, eksenX, minX, maxX),
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
    final p = context.c;
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
    final ondalik = bant.interval < 1
        ? 2
        : bant.interval < 10
            ? 1
            : 0;
    final eksenBicimi = tryFormatter(digits: ondalik, symbol: '');
    final span = maxX - minX;

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
          color: renk,
          // Kalınlık döneme bağlı — performans ekranıyla aynı merdiven.
          barWidth: donemCizgiKalinligi(periodDays),
          // Eğri interpolasyon veride olmayan tepe ve dip uydurur.
          isCurved: false,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                renk.withValues(alpha: 0.18),
                renk.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
      // Dönem başı çizgisi: yüzdenin neye göre okunacağını gösterir.
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: tam.first.y,
            color: p.text36.withValues(alpha: 0.4),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ],
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: eksenX.gunIci,
        verticalInterval: eksenX.interval,
        getDrawingVerticalLine: (_) => FlLine(color: p.hairline, strokeWidth: 1),
        horizontalInterval: bant.interval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: p.hairline, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
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
              return Padding(
                padding: const EdgeInsets.only(left: SandikSpace.xs2),
                child: Text(
                  eksenBicimi.format(value).trim(),
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(color: p.text58),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: _altEksenYuksekligi,
            interval: eksenX.interval,
            getTitlesWidget: (value, meta) {
              if (eksenKenarinda(value, meta.min, meta.max)) {
                return const SizedBox.shrink();
              }
              final t = DateTime.fromMillisecondsSinceEpoch(value.round());
              return Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xs2),
                child: Text(
                  zamanEtiketi(t,
                      spanGun: span / const Duration(days: 1).inMilliseconds,
                      gunIci: eksenX.gunIci),
                  maxLines: 1,
                  style: context.t.labelSmall?.copyWith(color: p.text36),
                ),
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
