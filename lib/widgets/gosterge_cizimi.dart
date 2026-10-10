import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/gosterge_betigi/betik.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'grafik_stili.dart';

/// Kullanıcı göstergelerinin (betik) çizimi — varlık grafiği, ayrı panel ve
/// düzenleyici önizlemesi AYNI renk ve çizgi kuralını buradan alır.
///
/// ## Renk
/// Betik ham renk yazamaz; dilin renk adı token'a çevrilir (tasarım sistemi:
/// renk yalnız `context.c.*`). Renk verilmeyen çizgiler sırayla mavi, amber,
/// altın, gri alır — kazanç/kayıp yeşili ve kırmızısı varsayılan değildir
/// (TASARIM_DILI §1.6: o renkler para yönü içindir; kullanıcı açıkça
/// `color.green` yazarsa kendi seçimi). Renk anlamı tek başına taşımaz:
/// her çizginin adı göstergeler satırında yazılı (HIG renk körlüğü).
Color betikRengi(BuildContext context, String? ad, int sira) {
  final c = context.c;
  switch (ad) {
    case 'yesil':
      return c.gain;
    case 'kirmizi':
      return c.loss;
    case 'mavi' || 'mor':
      return c.info;
    case 'turuncu':
      return c.amberText;
    case 'sari':
      return c.gold;
    case 'gri':
      return c.text58;
  }
  final sirali = [c.info, c.amberText, c.gold, c.text58];
  return sirali[sira % sirali.length];
}

/// Bir sonucun bütün fl_chart çubukları ve dolguları.
///
/// Dizin sözleşmesi: `bars[i]` = `sonuc.cizgiler[i]` (gizli çizgi saydam bir
/// çubuk olarak yine yer tutar — `fill` ona bağlanabilsin). Histogramın eksi
/// tarafı ve işaretler bunlardan SONRA gelir. [dolgular] dizinleri bu listeye
/// görelidir; listeyi başka çubuklarla birleştiren [ofset] verir.
({List<LineChartBarData> bars, List<BetweenBarsData> dolgular}) betikCizimleri(
  BuildContext context,
  BetikSonucu sonuc, {
  double Function(double)? toY,
  List<double>? fiyatY,
  int ofset = 0,
}) {
  final x = sonuc.x;
  final ana = <LineChartBarData>[];
  final ek = <LineChartBarData>[];
  for (final (i, c) in sonuc.cizgiler.indexed) {
    final cubuklar = _cizgiCubuklari(context, c, x, i, toY);
    ana.add(cubuklar.first);
    ek.addAll(cubuklar.skip(1));
  }
  if (fiyatY != null && sonuc.fiyatUstunde) {
    for (final m in sonuc.isaretler) {
      ek.add(betikIsaretCubugu(context, m, x, fiyatY));
    }
  }
  final dolgular = <BetweenBarsData>[
    for (final d in sonuc.dolgular)
      if (d.a != null && d.b != null)
        BetweenBarsData(
          fromIndex: ofset + d.a!,
          toIndex: ofset + d.b!,
          color: betikRengi(context, d.renk ?? sonuc.cizgiler[d.a!].renk,
                  d.a!)
              .withValues(alpha: 0.12),
        ),
  ];
  return (bars: [...ana, ...ek], dolgular: dolgular);
}

/// Bir `plot`un çubukları; ilki her zaman "ana" çubuk (dolgu dizini).
List<LineChartBarData> _cizgiCubuklari(BuildContext context, BetikCizgi c,
    List<double> x, int sira, double Function(double)? toY) {
  double y(double v) => toY == null ? v : toY(v);
  final renk = betikRengi(context, c.renk, sira);
  if (c.gizli) {
    return [
      LineChartBarData(
        spots: [
          for (var i = 0; i < x.length; i++)
            if (c.degerler[i].isFinite) FlSpot(x[i], y(c.degerler[i])),
        ],
        barWidth: 0,
        color: renk.withValues(alpha: 0),
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ),
    ];
  }
  switch (c.stil) {
    case BetikCizgiStili.histogram:
      // Sütunlar: her çubuk sıfırdan değere dikey bir parça; parçalar
      // `nullSpot` ile ayrılır. Artı ve eksi taraf ayrı renk (MACD).
      final eksi = betikRengi(context, c.eksiRenk ?? c.renk, sira);
      final sifir = y(0);
      List<FlSpot> parcalar(bool arti) => [
            for (var i = 0; i < x.length; i++)
              if (c.degerler[i].isFinite && (c.degerler[i] >= 0) == arti) ...[
                FlSpot(x[i], sifir),
                FlSpot(x[i], y(c.degerler[i])),
                FlSpot.nullSpot,
              ],
          ];
      LineChartBarData sutun(List<FlSpot> sp, Color r) => LineChartBarData(
            spots: sp,
            isCurved: false,
            color: r.withValues(alpha: 0.8),
            barWidth: c.kalinlik + 0.6,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          );
      return [sutun(parcalar(true), renk), sutun(parcalar(false), eksi)];
    case BetikCizgiStili.nokta:
      return [
        LineChartBarData(
          spots: [
            for (var i = 0; i < x.length; i++)
              if (c.degerler[i].isFinite) FlSpot(x[i], y(c.degerler[i])),
          ],
          barWidth: 0,
          color: renk.withValues(alpha: 0),
          belowBarData: BarAreaData(show: false),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: c.kalinlik,
              color: renk,
              strokeWidth: 0,
              strokeColor: renk,
            ),
          ),
        ),
      ];
    case BetikCizgiStili.cizgi || BetikCizgiStili.alan:
      final alan = c.stil == BetikCizgiStili.alan;
      return [
        LineChartBarData(
          // Pine `na` çizgiyi böler (plot.style_linebr ve Supertrend gibi
          // iki çizgili göstergeler): boşluk nullSpot.
          spots: _bolunmus(c.degerler, x, y),
          isCurved: false,
          color: renk,
          barWidth: c.kalinlik,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: alan,
            color: renk.withValues(alpha: 0.14),
            cutOffY: y(0),
            applyCutOffY: alan,
          ),
        ),
      ];
  }
}

/// NaN aralıkları `nullSpot` ile böler; baştaki ve sondaki boşluk atılır.
List<FlSpot> _bolunmus(
    List<double> d, List<double> x, double Function(double) y) {
  final out = <FlSpot>[];
  var bosluk = false;
  for (var i = 0; i < x.length; i++) {
    if (!d[i].isFinite) {
      bosluk = out.isNotEmpty;
      continue;
    }
    if (bosluk) {
      out.add(FlSpot.nullSpot);
      bosluk = false;
    }
    out.add(FlSpot(x[i], y(d[i])));
  }
  return out;
}

/// `plotshape` işaretleri: koşulun doğru olduğu çubukta, FİYATIN üstünde
/// küçük daire. Çizgi yok (kalınlık 0 + saydam renk; işlem işaretleriyle
/// aynı kalıp).
LineChartBarData betikIsaretCubugu(
  BuildContext context,
  BetikIsaret isaret,
  List<double> x,
  List<double> fiyatY,
) {
  final renk = betikRengi(context, isaret.renk, 1);
  return LineChartBarData(
    spots: [
      for (final i in isaret.indeksler)
        if (fiyatY[i].isFinite) FlSpot(x[i], fiyatY[i]),
    ],
    isCurved: false,
    barWidth: 0,
    color: renk.withValues(alpha: 0),
    belowBarData: BarAreaData(show: false),
    dotData: FlDotData(
      show: true,
      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
        radius: 4,
        color: renk,
        strokeColor: context.c.surface1,
        strokeWidth: 1.5,
      ),
    ),
  );
}

/// Bir göstergenin çizgi adları ve (görünür penceredeki) son değerleri —
/// grafiğin altındaki tek satır. Renk noktası + AD birlikte: renk tek başına
/// anlam taşımaz.
class BetikLejandi extends StatelessWidget {
  const BetikLejandi({
    super.key,
    required this.baslik,
    required this.sonuc,
    this.sonX,
  });

  final String baslik;
  final BetikSonucu sonuc;

  /// Bu X'e kadarki son değer yazılır (yakınlaştırılmış pencerenin sağı);
  /// null → serinin sonu.
  final double? sonX;

  @override
  Widget build(BuildContext context) {
    final stil = context.t.labelSmall?.copyWith(color: context.c.text58);
    double? son(BetikCizgi c) {
      for (var i = sonuc.x.length - 1; i >= 0; i--) {
        if (sonX != null && sonuc.x[i] > sonX!) continue;
        if (c.degerler[i].isFinite) return c.degerler[i];
      }
      return null;
    }

    return Wrap(
      spacing: SandikSpace.md,
      runSpacing: SandikSpace.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(baslik,
            style: context.t.labelSmall?.copyWith(
                color: context.c.text90, fontWeight: FontWeight.w700)),
        for (final (i, c) in sonuc.cizgiler.indexed)
          if (!c.gizli)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: betikRengi(context, c.renk, i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: SandikSpace.xs),
              Text(
                son(c) == null ? c.ad : '${c.ad} ${fmtNumFlex(son(c)!, maxDigits: 2)}',
                style: stil,
              ),
            ],
          ),
      ],
    );
  }
}

/// Ayrı panel (overlay=false): grafiğin altında, ana grafikle AYNI X
/// penceresi ([minX]/[maxX]) ve aynı sağ eksen bandı — dikey hizada aynı
/// çubuk aynı yerde durur (TradingView'deki alt panel).
class BetikPaneli extends StatelessWidget {
  const BetikPaneli({
    super.key,
    required this.baslik,
    required this.sonuc,
    required this.minX,
    required this.maxX,
    this.yukseklik = 96,
  });

  final String baslik;
  final BetikSonucu sonuc;
  final double minX;
  final double maxX;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    final bant = betikYBandi(sonuc, minX, maxX);
    return Semantics(
      label: context.l10n.ozgPanelSemantik(baslik),
      child: Container(
        decoration: GrafikStili.kart(context),
        padding: GrafikStili.kartDolgusu.copyWith(top: SandikSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BetikLejandi(baslik: baslik, sonuc: sonuc, sonX: maxX),
            const SizedBox(height: SandikSpace.xs),
            SizedBox(
              height: yukseklik,
              child: ExcludeSemantics(
                child: LineChart(
                  _panelVerisi(context, sonuc, minX, maxX, bant),
                  duration: Duration.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panelin Y bandı: görünür penceredeki değerler + yatay seviyeler, %8 pay.
({double min, double max}) betikYBandi(
    BetikSonucu s, double minX, double maxX) {
  var lo = double.infinity;
  var hi = -double.infinity;
  for (final c in s.cizgiler) {
    for (var i = 0; i < s.x.length; i++) {
      final v = c.degerler[i];
      if (!v.isFinite || s.x[i] < minX || s.x[i] > maxX) continue;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
  }
  for (final y in s.yataylar) {
    lo = math.min(lo, y.deger);
    hi = math.max(hi, y.deger);
  }
  if (!lo.isFinite || !hi.isFinite) return (min: 0, max: 1);
  if (hi - lo < 1e-9) {
    final p = lo.abs() * 0.05 + 1;
    return (min: lo - p, max: hi + p);
  }
  final pay = (hi - lo) * 0.08;
  return (min: lo - pay, max: hi + pay);
}

LineChartData _panelVerisi(BuildContext context, BetikSonucu s, double minX,
    double maxX, ({double min, double max}) bant) {
  final eksen = GrafikStili.eksenYazisi(context);
  final cizim = betikCizimleri(context, s);
  return LineChartData(
    minX: minX,
    maxX: maxX,
    minY: bant.min,
    maxY: bant.max,
    clipData: const FlClipData.all(),
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: (bant.max - bant.min) / 2,
      getDrawingHorizontalLine: (_) => GrafikStili.izgara(context),
    ),
    borderData: GrafikStili.eksenAyraci(context),
    titlesData: FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: GrafikStili.yEkseniGenisligi,
          interval: (bant.max - bant.min) / 2,
          // Seviye çizgisi varsa (RSI 70/30) eksen onların değerini yazar:
          // okunacak sayı odur; ara değerler gürültü.
          getTitlesWidget: (v, meta) {
            if (s.yataylar.isNotEmpty || v == meta.min || v == meta.max) {
              return const SizedBox();
            }
            return GrafikStili.yEtiketi(fmtNumFlex(v, maxDigits: 2),
                stil: eksen);
          },
        ),
      ),
    ),
    extraLinesData: ExtraLinesData(horizontalLines: [
      for (final y in s.yataylar)
        HorizontalLine(
          y: y.deger,
          color: betikRengi(context, y.renk, 3).withValues(alpha: 0.7),
          strokeWidth: 1,
          dashArray: const [4, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(left: SandikSpace.sm),
            style: eksen,
            labelResolver: (_) => fmtNumFlex(y.deger, maxDigits: 2),
          ),
        ),
    ]),
    // fill(hline1, hline2): RSI'nin 30-70 bandı gibi.
    rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
      for (final d in s.dolgular)
        if (d.yatayA != null && d.yatayB != null)
          HorizontalRangeAnnotation(
            y1: math.min(d.yatayA!, d.yatayB!),
            y2: math.max(d.yatayA!, d.yatayB!),
            color: betikRengi(context, d.renk, 0).withValues(alpha: 0.08),
          ),
    ]),
    lineTouchData: const LineTouchData(enabled: false),
    lineBarsData: cizim.bars,
    betweenBarsData: cizim.dolgular,
  );
}

/// Düzenleyicinin önizlemesi: fiyatın üstündeki gösterge fiyat çizgisiyle,
/// ayrı panel göstergesi kendi ölçeğinde. Etkileşim yok (yalnız bakış).
class BetikOnizleme extends StatelessWidget {
  const BetikOnizleme({
    super.key,
    required this.sonuc,
    required this.veri,
    this.yukseklik = 168,
  });

  final BetikSonucu sonuc;
  final BetikVerisi veri;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    if (sonuc.x.isEmpty) return SizedBox(height: yukseklik);
    final minX = sonuc.x.first;
    final maxX = sonuc.x.last;
    if (!sonuc.fiyatUstunde) {
      return SizedBox(
        height: yukseklik,
        child: ExcludeSemantics(
          child: LineChart(
            _panelVerisi(
                context, sonuc, minX, maxX, betikYBandi(sonuc, minX, maxX)),
            duration: Duration.zero,
          ),
        ),
      );
    }
    // Fiyat çizgisi sonucun X'leriyle hizalı: betik girdinin son
    // [kBetikAzamiCubuk] çubuğunda çalışır.
    final kayma = veri.uzunluk - sonuc.x.length;
    final fiyat = veri.kapanis.sublist(kayma);
    var lo = double.infinity, hi = -double.infinity;
    void kat(double v) {
      if (!v.isFinite) return;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }

    fiyat.forEach(kat);
    for (final c in sonuc.cizgiler) {
      c.degerler.forEach(kat);
    }
    if (!lo.isFinite) return SizedBox(height: yukseklik);
    final pay = math.max((hi - lo) * 0.08, hi.abs() * 0.005 + 1e-9);
    final eksen = GrafikStili.eksenYazisi(context);
    // Fiyat çizgisi listede ilk; göstergenin dolgu dizinleri 1 kayar.
    final cizim = betikCizimleri(context, sonuc, fiyatY: fiyat, ofset: 1);
    return SizedBox(
      height: yukseklik,
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: lo - pay,
            maxY: hi + pay,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => GrafikStili.izgara(context),
            ),
            borderData: GrafikStili.eksenAyraci(context),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: GrafikStili.yEkseniGenisligi,
                  getTitlesWidget: (v, meta) {
                    if (v == meta.min || v == meta.max) {
                      return const SizedBox();
                    }
                    return GrafikStili.yEtiketi(fmtNumFlex(v, maxDigits: 2),
                        stil: eksen);
                  },
                ),
              ),
            ),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < fiyat.length; i++)
                    if (fiyat[i].isFinite) FlSpot(sonuc.x[i], fiyat[i]),
                ],
                isCurved: false,
                color: context.c.text36,
                barWidth: 1.4,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
              ...cizim.bars,
            ],
            betweenBarsData: cizim.dolgular,
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}
