import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
import '../utils/tr_format.dart';
import 'percent_comparison_chart.dart';

// `yuzdeEkseni` ve `yeniOdak` bu dosyadan çıkarıldı ama buradan import
// eden çağıranlar (ve testler) kırılmasın diye yeniden dışa verilir.
export '../utils/chart_axis.dart' show yuzdeEkseni, yeniOdak;

/// Takip listesinin üstündeki karşılaştırma grafiği.
///
/// ## Neden yüzde (ham fiyat değil)
/// `comparison_screen.dart` ile AYNI mantık ve AYNI motor
/// ([normalizeSeries]): dönem başı `%0` kabul edilir, her seri oradan
/// itibaren yüzde olarak çizilir. Ham fiyatla çizmek anlamsız olurdu — ₺12'lik
/// bir hisse ile ₺4.800'lük altın aynı eksende görünmez, biri düz çizgiye
/// yapışırdı.
///
/// Yüzde ayrıca takip listesinin doğasına uyuyor: sahip olmadığın varlığın
/// "kazancı" tanımsızdır, tanımlı olan tek şey fiyatın yüzde kaç değiştiğidir.
/// (Bu gerekçe `normalizeSeries` dokümanında da yazılı.)
///
/// ## Portföy çizgisi
/// Kullanıcının kendi portföyü (ortaklar dahil) da bir seri olarak çizilir ve
/// **kalın + amber** gösterilir. Kıyas noktası budur: "izlediklerim benim
/// portföyümden iyi mi gidiyor?" Diğer serilerle aynı normalize işleminden
/// geçer, yani karşılaştırma adildir.
class WatchlistChart extends StatelessWidget {
  const WatchlistChart({
    super.key,
    required this.series,
    required this.portfolioLabel,
    this.focused,
    this.onFocusChanged,
    this.portfolioKey = _portfolioKey,
  });

  /// Odaklanılan serinin anahtarı. `null` ise hepsi eşit ağırlıkta çizilir.
  ///
  /// Odak bir FİLTRE DEĞİL: diğer seriler ekrandan kaldırılmaz, soluklaşır.
  /// Kaldırmak kıyası yok ederdi — "bu varlık iyi mi gidiyor" sorusunun
  /// cevabı ancak diğerleri görünürken vardır.
  final String? focused;

  /// Bir çizgiye dokunulduğunda çağrılır. Aynı çizgiye tekrar dokunmak odağı
  /// kaldırır (donut grafikteki `_touchedIndex` deseninin aynısı).
  final ValueChanged<String?>? onFocusChanged;

  /// `etiket → normalize edilmiş seri`. Portföy serisi [portfolioKey]
  /// anahtarıyla gelir.
  final Map<String, NormalizedSeries> series;

  /// Kıyas çizgisinin adı — seçime göre değişir ("Portföyüm", "Birlikte",
  /// ortağın adı). Sabit "Portföyüm" yazmak, bir ortak seçiliyken YANLIŞ
  /// bilgi olurdu.
  final String portfolioLabel;

  final String portfolioKey;

  /// Portföy serisinin sabit anahtarı — çağıran taraf da bunu kullanır.
  static const _portfolioKey = '__portfoy__';
  static const portfolioSeriesKey = _portfolioKey;

  /// Takip serileri için renk paleti. Portföy bu paletten renk ALMAZ; o her
  /// zaman amber ve daha kalın çizilir, yani gözle anında ayrılır.
  static List<Color> _palette(SandikPalette p) => [
        p.info,
        p.gain,
        p.loss,
        p.text58,
        p.gold,
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.c;

    // Takip serileri önce, portföy EN SON — fl_chart son barı en üste çizer,
    // yani kıyas çizgisi diğerlerinin altında kalmaz.
    final watchKeys = series.keys.where((k) => k != portfolioKey).toList()
      ..sort();
    final order = [
      ...watchKeys,
      if (series.containsKey(portfolioKey)) portfolioKey,
    ];

    final palette = _palette(p);

    return PercentComparisonChart(
      series: series,
      order: order,
      emphasizedKey: portfolioKey,
      focused: focused,
      onFocusChanged: onFocusChanged,
      colorOf: (key) => key == portfolioKey
          ? p.amberText
          : palette[watchKeys.indexOf(key) % palette.length],
      labelOf: (key) => key == portfolioKey ? portfolioLabel : key,
    );
  }
}

/// Grafiğin altındaki renk açıklaması.
///
/// Renk tek başına yeterli değil (erişilebilirlik: "Don't convey information
/// by color alone") — her seri adıyla birlikte yazılır ve dönem getirisi
/// sayı olarak da gösterilir.
class WatchlistChartLegend extends StatelessWidget {
  const WatchlistChartLegend({
    super.key,
    required this.series,
    required this.colors,
    required this.portfolioLabel,
    this.focused,
    this.onFocusChanged,
  });

  final Map<String, NormalizedSeries> series;
  final Map<String, Color> colors;

  /// Grafikteki kıyas çizgisiyle AYNI ad — ikisi ayrışırsa açıklama yanlış
  /// çizgiyi işaret eder.
  final String portfolioLabel;

  final String? focused;

  /// Açıklama satırları da odak değiştirir.
  ///
  /// İnce bir çizgiye nişan almak zordur; 44pt'lik bir etiket çok daha kolay
  /// hedeftir. Aynı işi iki yoldan yapabilmek dokunma isabetini artırır.
  final ValueChanged<String?>? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final entries = series.entries.toList()
      // En iyi performans üstte — kullanıcının aradığı sıralama bu.
      ..sort(
          (a, b) => b.value.totalReturnPct.compareTo(a.value.totalReturnPct));

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final e in entries)
          _LegendChip(
            label: e.key == WatchlistChart.portfolioSeriesKey
                ? portfolioLabel
                : e.key,
            pct: e.value.totalReturnPct,
            color: colors[e.key] ?? context.c.text58,
            isPortfolio: e.key == WatchlistChart.portfolioSeriesKey,
            dimmed: focused != null && focused != e.key,
            onTap: onFocusChanged == null
                ? null
                : () => onFocusChanged!(
                    yeniOdak(mevcut: focused, dokunulan: e.key)),
          ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.pct,
    required this.color,
    required this.isPortfolio,
    this.dimmed = false,
    this.onTap,
  });

  final String label;
  final double pct;
  final Color color;
  final bool isPortfolio;

  /// Başka bir seri odaktayken bu satır soluklaşır — grafikteki çizgisiyle
  /// aynı görsel durumda kalsın.
  final bool dimmed;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFlat = pct.abs() < 0.005;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: isPortfolio ? 4 : 2.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.t.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: isPortfolio ? FontWeight.w700 : FontWeight.w500,
            color: isPortfolio ? context.c.amberText : context.c.text58,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          isFlat
              ? '—'
              : '${pct >= 0 ? '+' : '−'}${fmtPct(pct.abs(), digits: 1)}',
          style: context.t.numSmall.copyWith(
            fontSize: 11,
            color: isFlat
                ? context.c.text36
                : (pct >= 0 ? context.c.gain : context.c.loss),
          ),
        ),
      ],
    );

    // Soluklaşma yalnızca opaklıkla: metin renklerini ayrı ayrı hesaplamak
    // kazanç/kayıp renk kuralını bozardı.
    final content = AnimatedOpacity(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.enter,
      opacity: dimmed ? 0.32 : 1.0,
      child: row,
    );

    if (onTap == null) return content;

    return SandikTappable(
      onTap: onTap!,
      semanticLabel: '$label serisine odaklan',
      // 44pt dokunma hedefi — satırın kendisi ~14pt yüksekliğinde.
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        child: content,
      ),
    );
  }
}
