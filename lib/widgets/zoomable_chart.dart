import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/sandik.dart';

/// Birden fazla grafik (ana + volume subchart) aynı X viewport'unu paylaşsın
/// diye kullanılan ChangeNotifier. Ana grafikte pinch/pan olur, viewport
/// güncellenir, alt grafik de dinleyip aynı X aralığını çizer.
class ChartViewport extends ChangeNotifier {
  ChartViewport({required this.fullMinX, required this.fullMaxX})
      : _minX = fullMinX,
        _maxX = fullMaxX;

  double fullMinX;
  double fullMaxX;
  double _minX;
  double _maxX;

  double get minX => _minX;
  double get maxX => _maxX;
  bool get isZoomed =>
      (_minX - fullMinX).abs() > 0.001 || (_maxX - fullMaxX).abs() > 0.001;

  void set(double minX, double maxX) {
    if (_minX == minX && _maxX == maxX) return;
    _minX = minX;
    _maxX = maxX;
    notifyListeners();
  }

  void updateFullRange(double newMin, double newMax) {
    if (fullMinX == newMin && fullMaxX == newMax) return;
    fullMinX = newMin;
    fullMaxX = newMax;
    _minX = newMin;
    _maxX = newMax;
    notifyListeners();
  }

  void reset() {
    set(fullMinX, fullMaxX);
  }
}

/// fl_chart [LineChart] üzerine pinch (iki parmak) zoom, pan ve isteğe bağlı
/// crosshair (uzun basınca dikey rehber çizgi + fiyat/tarih pill'i) ekler.
///
/// Yaklaşım: LineChart'ın **üzerinde** her zaman aktif bir GestureDetector
/// katmanı var. `HitTestBehavior.translucent` ile aynı jesti alta da (LineChart
/// tooltip'ine) geçirir. Scale recognizer 2+ parmakta arena'yı kazanır ve
/// zoom uygulanır; tek parmak dokunma tooltip'e gider.
///
/// Crosshair, [crosshairLabelBuilder] verildiğinde aktif olur. Long-press
/// başlatır, pan devam ettirir, pointer kalkınca kaybolur.
class ZoomableChart extends StatefulWidget {
  final double fullMinX;
  final double fullMaxX;
  final LineChartData Function(double minX, double maxX) builder;
  final double height;

  /// Viewport her değiştiğinde çağrılır (pan/pinch/reset). ZoomDataController
  /// bunu dinleyip uygun çözünürlükte yeni veri yükleyebilir.
  final void Function(double minX, double maxX)? onViewportChanged;

  /// Crosshair aktif için gerekli. `x` chart data cinsinden (builder'a giden
  /// aynı X uzayı), dönüş pill'de gösterilecek 2 satır: `(title, subtitle)`.
  /// Örn: (`'₺1.234'`, `'14 Mar 15:30'`). `null` dönerse pill gösterilmez ama
  /// dikey çizgi hâlâ çizilir.
  final (String, String)? Function(double x)? crosshairLabelBuilder;

  /// Opsiyonel — verilirse pill'de fiyat/tarih altında ek detay satırları
  /// gösterilir (getiri, alım/satım vs.). Her satır: (metin, renk).
  final List<(String, Color)> Function(double x)? crosshairDetailsBuilder;

  /// Opsiyonel: crosshair X'ini en yakın data noktasına snap eder. Verilirse
  /// hem dikey çizgi hem pill label snap edilmiş X'te gösterilir — böylece
  /// fl_chart'ın built-in tooltip'i ile crosshair birebir aynı noktaya
  /// oturur, kullanıcı "çizgi ile veri tutmuyor" hissi almaz.
  final double Function(double x)? crosshairSnapX;

  /// Verilirse widget kendi viewport state'ini tutmaz — controller üstünden
  /// paylaşılır. Volume subchart gibi 2. panelin aynı X aralığına oturması
  /// için kullanılır.
  final ChartViewport? viewportController;

  /// Grafik altındaki X-axis label alanında horizontal drag = zaman ölçeği
  /// sıkıştır/genişlet. Sağ kenar pivot — son nokta sabit kalır.
  final bool enableTimeScaleDrag;

  /// Bottom axis alanı yüksekliği (px). enableTimeScaleDrag için sadece
  /// bu alan drag'i yakalar; üstteki chart alanı pinch/tap için serbest.
  final double bottomAxisHeight;

  /// Sağdaki Y-ekseni rezerv alanı (px). Chart plot area sağdan bu kadar
  /// içeride biter — crosshair/touch bu alana **girmez**. fl_chart'ın
  /// `rightTitles.reservedSize` değeriyle aynı olmalı.
  final double plotPaddingRight;

  /// Soldaki Y-ekseni rezerv alanı (px). fl_chart `leftTitles.reservedSize`
  /// ile aynı olmalı. Sağ Y kullanılıyorsa 0.
  final double plotPaddingLeft;

  /// Veri (periyot/filtre) değişiminde grafiğin eski şekilden yenisine
  /// morf süresi. Jest sırasında yok sayılır — bkz. build().
  final Duration swapDuration;

  /// Morf eğrisi. `ease-out` hızlı başlar: değişim hemen algılanır.
  final Curve swapCurve;

  const ZoomableChart({
    super.key,
    required this.fullMinX,
    required this.fullMaxX,
    required this.builder,
    this.height = 360,
    this.onViewportChanged,
    this.crosshairLabelBuilder,
    this.crosshairDetailsBuilder,
    this.crosshairSnapX,
    this.viewportController,
    this.enableTimeScaleDrag = true,
    this.bottomAxisHeight = 32,
    this.plotPaddingRight = 0,
    this.plotPaddingLeft = 0,
    this.swapDuration = SandikMotion.state,
    this.swapCurve = SandikMotion.enter,
  });

  @override
  State<ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<ZoomableChart> {
  // Controller yoksa iç state — verildiyse controller kaynak.
  double _localMinX = 0;
  double _localMaxX = 0;

  double get _minX =>
      widget.viewportController?.minX ?? _localMinX;
  double get _maxX =>
      widget.viewportController?.maxX ?? _localMaxX;

  double _startMinX = 0;
  double _startMaxX = 0;
  double _startFocalRel = 0.5;
  double _chartWidth = 1.0;

  // Crosshair state — null = kapalı. `_crosshairPx` widget'ın soldan
  // piksel offset'i; `_crosshairX` chart data cinsinden değer.
  double? _crosshairPx;
  double? _crosshairX;

  // Kullanıcı şu an pinch/pan/time-scale drag yapıyor mu? Doğruysa
  // LineChart'ın implicit animasyonu kapatılır: viewport her karede
  // değişirken lerp etmek parmağın arkasında kalan "lastikli" bir his
  // yaratıyor. Jest bitince tekrar açılır ki periyot/filtre değişimleri
  // yumuşak morf'lansın.
  bool _interacting = false;

  void _setInteracting(bool v) {
    if (_interacting == v) return;
    // Jest sırasında setState zaten viewport değişimiyle tetikleniyor;
    // burada yalnızca bayrağı güncelliyoruz (build bir sonraki karede
    // doğru süreyi okur).
    _interacting = v;
  }

  @override
  void initState() {
    super.initState();
    _localMinX = widget.fullMinX;
    _localMaxX = widget.fullMaxX;
    widget.viewportController?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ZoomableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportController != widget.viewportController) {
      oldWidget.viewportController?.removeListener(_onControllerChanged);
      widget.viewportController?.addListener(_onControllerChanged);
    }
    if (oldWidget.fullMinX != widget.fullMinX ||
        oldWidget.fullMaxX != widget.fullMaxX) {
      _localMinX = widget.fullMinX;
      _localMaxX = widget.fullMaxX;
      // Controller varsa full range'i de güncelle
      widget.viewportController
          ?.updateFullRange(widget.fullMinX, widget.fullMaxX);
    }
  }

  @override
  void dispose() {
    widget.viewportController?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _setViewport(double newMin, double newMax) {
    final c = widget.viewportController;
    if (c != null) {
      c.set(newMin, newMax);
    } else {
      setState(() {
        _localMinX = newMin;
        _localMaxX = newMax;
      });
    }
  }

  bool get _isZoomed =>
      (_minX - widget.fullMinX).abs() > 0.001 ||
      (_maxX - widget.fullMaxX).abs() > 0.001;

  bool get _crosshairEnabled => widget.crosshairLabelBuilder != null;

  void _reset() {
    _setViewport(widget.fullMinX, widget.fullMaxX);
    widget.onViewportChanged?.call(widget.fullMinX, widget.fullMaxX);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _setInteracting(true);
    _startMinX = _minX;
    _startMaxX = _maxX;
    // Focal point plot area sınırlarına clamp — Y ekseni bandına gelirse
    // %100 olarak alma.
    final localInPlot =
        (details.localFocalPoint.dx - _plotLeft).clamp(0.0, _plotWidth);
    _startFocalRel = (localInPlot / _plotWidth).clamp(0.0, 1.0);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Sadece iki+ parmak (gerçek pinch) veya zoom'luyken tek parmak pan.
    if (details.pointerCount < 2 && !_isZoomed) return;

    final width = _startMaxX - _startMinX;
    if (width <= 0) return;

    // Pinch her açıda tetiklenmeli — yatay, dikey ya da çapraz. `details.scale`
    // geometric mean, dikey pinch'te ~1.0 kalıp chart'ı zoom etmiyor. Yatay ve
    // dikey ölçekten "1'den daha uzak olanı" seç → dikey pinch de X zoom yapar.
    final hs = details.horizontalScale;
    final vs = details.verticalScale;
    final effectiveScale = ((hs - 1).abs() >= (vs - 1).abs()) ? hs : vs;
    double newWidth = width / effectiveScale;
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    final minWidth = fullWidth * 0.02;
    if (newWidth < minWidth) newWidth = minWidth;
    if (newWidth > fullWidth) newWidth = fullWidth;

    final focalX = _startMinX + width * _startFocalRel;
    double newMin = focalX - newWidth * _startFocalRel;
    double newMax = newMin + newWidth;

    final panPx = details.focalPointDelta.dx;
    final panData = -panPx / _plotWidth * newWidth;
    newMin += panData;
    newMax += panData;

    if (newMin < widget.fullMinX) {
      final overflow = widget.fullMinX - newMin;
      newMin += overflow;
      newMax += overflow;
    }
    if (newMax > widget.fullMaxX) {
      final overflow = newMax - widget.fullMaxX;
      newMin -= overflow;
      newMax -= overflow;
    }

    _setViewport(newMin, newMax);
    widget.onViewportChanged?.call(newMin, newMax);
  }

  /// Chart plot area'nın genişliği = toplam - sağ Y rezervi - sol Y rezervi.
  /// Kullanıcı touch'ı bu alana konumlanır; Y ekseni bandına düşen dokunuşlar
  /// clamp'lenir. TradingView'de dikey crosshair Y-ekseni bantına asla girmez.
  double get _plotWidth {
    final w = _chartWidth - widget.plotPaddingRight - widget.plotPaddingLeft;
    return w <= 0 ? 1.0 : w;
  }

  double get _plotLeft => widget.plotPaddingLeft;
  double get _plotRight => _chartWidth - widget.plotPaddingRight;

  void _updateCrosshair(double localDx) {
    // Touch X'i plot area sınırlarına clamp — Y ekseni bandında dokunulsa
    // bile crosshair plot içinde kalır.
    final clamped = localDx.clamp(_plotLeft, _plotRight);
    final relInPlot = (clamped - _plotLeft) / _plotWidth;
    var xData = _minX + (_maxX - _minX) * relInPlot;
    var px = clamped;
    // En yakın data noktasına snap: hem çizgi hem label aynı X'te olsun.
    if (widget.crosshairSnapX != null) {
      final snappedX = widget.crosshairSnapX!(xData);
      xData = snappedX;
      final span = _maxX - _minX;
      if (span > 0) {
        px = (_plotLeft +
                (snappedX - _minX) / span * _plotWidth)
            .clamp(_plotLeft, _plotRight);
      }
    }
    setState(() {
      _crosshairPx = px;
      _crosshairX = xData;
    });
  }

  void _clearCrosshair() {
    if (_crosshairPx == null) return;
    setState(() {
      _crosshairPx = null;
      _crosshairX = null;
    });
  }

  // ── Time scale drag ────────────────────────────────────────────────────
  // Bottom axis alanında horizontal drag: sağa = daralt (zoom in), sola =
  // genişlet (zoom out). Sağ kenar pivot — son nokta sabit kalır.
  double _timeDragStartWidth = 0;

  void _onTimeDragStart(DragStartDetails _) {
    _setInteracting(true);
    _timeDragStartWidth = _maxX - _minX;
  }

  void _onTimeDragEnd(DragEndDetails _) {
    if (!mounted) return;
    setState(() => _interacting = false);
  }

  void _onTimeDragUpdate(DragUpdateDetails d) {
    if (_chartWidth <= 0 || _timeDragStartWidth <= 0) return;
    // Delta piksel → viewport genişlik oranı. Sağa 100px drag genişliğin
    // yaklaşık %25'i kadar daraltsın (~4x sensitivity).
    final delta = d.primaryDelta ?? 0;
    if (delta == 0) return;
    final factor = 1 - (delta / _plotWidth) * 2.5;
    double newWidth = (_maxX - _minX) * factor;
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    final minWidth = fullWidth * 0.02;
    if (newWidth < minWidth) newWidth = minWidth;
    if (newWidth > fullWidth) newWidth = fullWidth;
    // Sağ kenar sabit: newMax = eski maxX, newMin = newMax - newWidth
    double newMin = _maxX - newWidth;
    double newMax = _maxX;
    if (newMin < widget.fullMinX) {
      newMin = widget.fullMinX;
      newMax = newMin + newWidth;
      if (newMax > widget.fullMaxX) newMax = widget.fullMaxX;
    }
    _setViewport(newMin, newMax);
    widget.onViewportChanged?.call(newMin, newMax);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _chartWidth = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
      return SizedBox(
        height: widget.height,
        child: Stack(
          // **Çizim kendi kutusunun DIŞINA taşamaz.**
          //
          // `Clip.none` gerekçesizdi ve pinch sırasında görünür bir hataya
          // yol açıyordu: `LineChart` bir ImplicitlyAnimatedWidget, jest
          // boyunca eski `LineChartData` ile yenisi arasında lerp'liyor ve
          // ara karelerde min/max sınırları anlık olarak hedefin dışına
          // çıkabiliyor. Clip yokken o karelerdeki çizgi kartın dışına,
          // başlığın ve dönem seçicinin üstüne basıyordu (kullanıcı
          // ekran görüntüsü, GÜNLÜK sekmesi).
          //
          // Stack'in Flutter varsayılanı zaten `Clip.hardEdge`; burada
          // taşmadan yararlanan bir çocuk YOK — crosshair çizgisi, pill ve
          // Sıfırla çipi hepsi kutunun içinde konumlanıyor.
          clipBehavior: Clip.hardEdge,
          children: [
            // Alt: LineChart (tooltip'i için touch handler kendi içinde çalışır)
            //
            // `LineChart` bir ImplicitlyAnimatedWidget: yeni LineChartData
            // gelince eskisinden yenisine kendi lerp'ler. Periyot/filtre
            // değişiminde grafiğin "0'dan yeniden çizilmesi" yerine akıcı
            // şekilde şekil değiştirmesini sağlayan mekanizma budur —
            // ANCAK widget ağaçta kalmalı, aksi halde State ve tween sıfırlanır.
            //
            // Süre iki moda ayrılır:
            //  • Jest sırasında (pinch/pan) animasyon KAPALI (Duration.zero).
            //    Aksi halde her kare bir önceki hedefe doğru lerp'lerken yeni
            //    hedef gelir; parmak takip etmesi gecikmeli/lastikli hissedilir.
            //  • Veri/periyot değişiminde `swapDuration` ile yumuşak morf.
            Positioned.fill(
              child: LineChart(
                widget.builder(_minX, _maxX),
                duration: _interacting ? Duration.zero : widget.swapDuration,
                curve: widget.swapCurve,
              ),
            ),

            // Crosshair overlay
            if (_crosshairEnabled && _crosshairPx != null)
              _CrosshairOverlay(
                px: _crosshairPx!,
                pill: widget.crosshairLabelBuilder!(_crosshairX!),
                details: widget.crosshairDetailsBuilder
                    ?.call(_crosshairX!),
                reserveTopRight: _isZoomed,
              ),

            // Üst: her zaman aktif gesture layer.
            // trackpad + touch scale recognizer'ı arena'da 2+ parmakla kazanır.
            // Trackpad'de (masaüstü) da scale çalışsın diye supportedDevices.
            Positioned.fill(
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: <Type, GestureRecognizerFactory>{
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    (instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate
                        // Jest bitti → implicit animasyon tekrar açılsın.
                        // setState şart: son kare doğru süreyle çizilmeli.
                        ..onEnd = (_) {
                          if (!mounted) return;
                          setState(() => _interacting = false);
                        };
                    },
                  ),
                  if (_crosshairEnabled)
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer>(
                      () => LongPressGestureRecognizer(
                        duration: const Duration(milliseconds: 220),
                      ),
                      (instance) {
                        instance.onLongPressStart =
                            (d) => _updateCrosshair(d.localPosition.dx);
                        instance.onLongPressMoveUpdate =
                            (d) => _updateCrosshair(d.localPosition.dx);
                        instance.onLongPressEnd = (_) => _clearCrosshair();
                        instance.onLongPressCancel = _clearCrosshair;
                      },
                    ),
                },
              ),
            ),

            // Time scale drag zone — bottom axis label alanı üstünde.
            // Sadece bu ince şerit horizontal drag'i yakalar; üstteki pinch
            // ve tap zonları etkilenmez.
            if (widget.enableTimeScaleDrag)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: widget.bottomAxisHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _onTimeDragStart,
                  onHorizontalDragUpdate: _onTimeDragUpdate,
                  onHorizontalDragEnd: _onTimeDragEnd,
                  onHorizontalDragCancel: () => _onTimeDragEnd(DragEndDetails()),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: SizedBox.expand(),
                  ),
                ),
              ),

            // Reset chip'i sadece zoom'luyken üstte
            if (_isZoomed)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(SandikRadius.lg),
                    onTap: _reset,
                    onDoubleTap: _reset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(SandikRadius.lg),
                        border: Border.all(
                            color: context.c.text36),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_out_map_rounded,
                              size: 14, color: context.c.text58),
                          const SizedBox(width: 4),
                          Text('Sıfırla',
                              style: TextStyle(
                                  fontSize: 11, color: context.c.text58)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Dikey dashed çizgi (dokunulan X'te) + üstte sabit pozisyonda fiyat/tarih
/// pill'i. Pill sabit tutulur ki grafik içindeki ŞİMDİ/BAŞLANGIÇ etiketleriyle
/// çakışmasın — kullanıcı çizgiyle X'i, pill'le değeri ayrı ayrı okur.
class _CrosshairOverlay extends StatelessWidget {
  final double px;
  final (String, String)? pill;
  final List<(String, Color)>? details;
  /// Sıfırla chip'i sağ üstteyse pill onun soluna kayar.
  final bool reserveTopRight;

  const _CrosshairOverlay({
    required this.px,
    required this.pill,
    this.details,
    this.reserveTopRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            // Crosshair katmanı da kırpılır — dikey çizgi ve pill kutunun
            // içinde konumlanıyor, taşmaya ihtiyaç duyan çocuk yok. Üstteki
            // Stack ile aynı gerekçe.
            clipBehavior: Clip.hardEdge,
            children: [
              // Dikey dashed çizgi — dokunulan X'te
              Positioned(
                left: px - 0.5,
                top: 0,
                bottom: 0,
                child: CustomPaint(
                  size: const Size(1, double.infinity),
                  painter: _DashedLinePainter(
                    color: context.c.text58,
                  ),
                ),
              ),
              // Pill — sabit sağ üst (Sıfırla varsa onun soluna kaç)
              if (pill != null)
                Positioned(
                  top: 6,
                  right: reserveTopRight ? 96 : 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    // Tooltip grafiğin ÜSTÜNDE durur; zemini her iki modda
                    // koyu kalır (açık zeminde de grafik çizgileri arasında
                    // okunması gerekir). Bu yüzden metni text90 DEĞİL —
                    // light modda text90 koyudur ve koyu zemine koyu yazı
                    // olurdu. Tooltip kendi kontrast dünyasını taşır.
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1E15).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          pill!.$1,
                          style: const TextStyle(
                            color: Color(0xE1FFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pill!.$2,
                          style: const TextStyle(
                            color: Color(0x8CFFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (details != null && details!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 40,
                            color: context.c.overlay,
                          ),
                          const SizedBox(height: 4),
                          for (final line in details!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: Text(
                                line.$1,
                                style: TextStyle(
                                  color: line.$2,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashHeight = 4.0;
    const dashSpace = 4.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashHeight), paint);
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

/// Ana [ZoomableChart]'ın altına yerleştirilen ve aynı [ChartViewport]
/// controller'ını dinleyen bar chart. Kendi gesture'ı yok — üstteki chart
/// pinch/pan'da viewport değişince otomatik yeniden çizer.
class ZoomableBarChart extends StatefulWidget {
  final ChartViewport viewportController;
  final BarChartData Function(double minX, double maxX) builder;
  final double height;

  const ZoomableBarChart({
    super.key,
    required this.viewportController,
    required this.builder,
    this.height = 80,
  });

  @override
  State<ZoomableBarChart> createState() => _ZoomableBarChartState();
}

class _ZoomableBarChartState extends State<ZoomableBarChart> {
  @override
  void initState() {
    super.initState();
    widget.viewportController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant ZoomableBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportController != widget.viewportController) {
      oldWidget.viewportController.removeListener(_onChanged);
      widget.viewportController.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.viewportController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.viewportController;
    return SizedBox(
      height: widget.height,
      child: BarChart(widget.builder(c.minX, c.maxX)),
    );
  }
}
