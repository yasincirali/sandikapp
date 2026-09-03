import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/chart_axis.dart';
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

    return ZoomableChart(
      height: height,
      fullMinX: ciz.minX,
      fullMaxX: ciz.maxX,
      bottomAxisHeight: _bottomAxisHeight,
      // Sol Y ekseni rezervi — crosshair'in etiket bandına girmemesi için
      // `leftTitles.reservedSize` ile AYNI olmak zorunda.
      plotPaddingLeft: _yEkseniGenisligi,
      crosshairSnapX: (x) {
        // Odaktaki seri varsa ona, yoksa ilk seriye snap et: crosshair
        // dikey çizgisi ile tooltip aynı noktaya otursun.
        final spots = ciz.snapSpots;
        if (spots.isEmpty) return x;
        final clamped = x.clamp(spots.first.x, spots.last.x);
        return spots[nearestSpotIndex(spots, clamped)].x;
      },
      crosshairLabelBuilder: (x) {
        final spots = ciz.snapSpots;
        if (spots.isEmpty) return null;
        final s = spots[nearestSpotIndex(spots, x)];
        final tarih = DateTime.fromMillisecondsSinceEpoch(x.round());
        return (
          fmtPct(s.y, digits: 1, showSign: true),
          DateFormat('d MMM yyyy', 'tr_TR').format(tarih),
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
      builder: (minX, maxX) => _data(p, ciz, minX, maxX),
    );
  }

  /// `leftTitles.reservedSize` ile aynı — ikisi ayrışırsa crosshair etiket
  /// bandının içine girer.
  static const _yEkseniGenisligi = 42.0;

  Widget _bosDurum(BuildContext context) => SizedBox(
        height: _bosDurumYuksekligi,
        child: Center(
          child: Text(
            'Grafik için yeterli fiyat geçmişi yok.',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ),
      );

  /// Serinin [x] anındaki (en yakın noktadaki) yüzdesi.
  ///
  /// Noktalar zaten X'e göre sıralı olduğu için ikili arama kullanılır —
  /// crosshair parmak her kaydığında ve HER seri için çağrılıyor; doğrusal
  /// tarama beş seri × iki yüz noktada kare başına gözle görülür bir maliyet
  /// olurdu.
  double? _degerAt(List<FlSpot> spots, double x) {
    if (spots.isEmpty) return null;
    return spots[nearestSpotIndex(spots, x)].y;
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
      minX: minX,
      maxX: maxX,
      eksen: yuzdeEkseni(minY - pad, maxY + pad),
    );
  }

  LineChartData _data(
      SandikPalette p, _CizimVerisi ciz, double minX, double maxX) {
    final eksen = ciz.eksen;
    final span = maxX - minX;

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: eksen.min,
      maxY: eksen.max,
      lineBarsData: ciz.bars,
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
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
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
            // Dört etiket: daha fazlası dar ekranda üst üste biniyor.
            interval: span <= 0 ? null : span / 4,
            getTitlesWidget: (value, meta) {
              if (value <= meta.min || value >= meta.max) {
                return const SizedBox.shrink();
              }
              final t = DateTime.fromMillisecondsSinceEpoch(value.round());
              // Bir günden kısa aralıkta tarih tekrar eder; saat göster.
              final bicim = span < const Duration(days: 2).inMilliseconds
                  ? DateFormat('HH:mm', 'tr_TR')
                  : DateFormat('d MMM', 'tr_TR');
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  bicim.format(t),
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
    required this.minX,
    required this.maxX,
    required this.eksen,
  });

  final List<LineChartBarData> bars;

  /// `bars` ile aynı sıradaki seri anahtarları.
  final List<String> cizilenler;

  /// Crosshair'in snap edeceği referans seri.
  final List<FlSpot> snapSpots;

  final double minX;
  final double maxX;
  final ({double min, double max, double interval, int ondalik}) eksen;
}
