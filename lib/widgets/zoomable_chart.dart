import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';

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

  const ZoomableChart({
    super.key,
    required this.fullMinX,
    required this.fullMaxX,
    required this.builder,
    this.height = 360,
    this.onViewportChanged,
    this.crosshairLabelBuilder,
    this.viewportController,
    this.enableTimeScaleDrag = true,
    this.bottomAxisHeight = 32,
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
    _startMinX = _minX;
    _startMaxX = _maxX;
    _startFocalRel =
        (details.localFocalPoint.dx / _chartWidth).clamp(0.0, 1.0);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Sadece iki+ parmak (gerçek pinch) veya zoom'luyken tek parmak pan.
    if (details.pointerCount < 2 && !_isZoomed) return;

    final width = _startMaxX - _startMinX;
    if (width <= 0) return;

    double newWidth = width / details.scale;
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    final minWidth = fullWidth * 0.02;
    if (newWidth < minWidth) newWidth = minWidth;
    if (newWidth > fullWidth) newWidth = fullWidth;

    final focalX = _startMinX + width * _startFocalRel;
    double newMin = focalX - newWidth * _startFocalRel;
    double newMax = newMin + newWidth;

    final panPx = details.focalPointDelta.dx;
    final panData = -panPx / _chartWidth * newWidth;
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

  void _updateCrosshair(double localDx) {
    final clamped = localDx.clamp(0.0, _chartWidth);
    final rel = _chartWidth <= 0 ? 0.0 : clamped / _chartWidth;
    final xData = _minX + (_maxX - _minX) * rel;
    setState(() {
      _crosshairPx = clamped;
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
    _timeDragStartWidth = _maxX - _minX;
  }

  void _onTimeDragUpdate(DragUpdateDetails d) {
    if (_chartWidth <= 0 || _timeDragStartWidth <= 0) return;
    // Delta piksel → viewport genişlik oranı. Sağa 100px drag genişliğin
    // yaklaşık %25'i kadar daraltsın (~4x sensitivity).
    final delta = d.primaryDelta ?? 0;
    if (delta == 0) return;
    final factor = 1 - (delta / _chartWidth) * 2.5;
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
          clipBehavior: Clip.none,
          children: [
            // Alt: LineChart (tooltip'i için touch handler kendi içinde çalışır)
            Positioned.fill(child: LineChart(widget.builder(_minX, _maxX))),

            // Crosshair overlay
            if (_crosshairEnabled && _crosshairPx != null)
              _CrosshairOverlay(
                px: _crosshairPx!,
                pill: widget.crosshairLabelBuilder!(_crosshairX!),
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
                        ..onUpdate = _onScaleUpdate;
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
                    borderRadius: BorderRadius.circular(20),
                    onTap: _reset,
                    onDoubleTap: _reset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_out_map_rounded,
                              size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('Sıfırla',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white70)),
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
  /// Sıfırla chip'i sağ üstteyse pill onun soluna kayar.
  final bool reserveTopRight;

  const _CrosshairOverlay({
    required this.px,
    required this.pill,
    this.reserveTopRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Dikey dashed çizgi — dokunulan X'te
              Positioned(
                left: px - 0.5,
                top: 0,
                bottom: 0,
                child: CustomPaint(
                  size: const Size(1, double.infinity),
                  painter: _DashedLinePainter(
                    color: Colors.white.withValues(alpha: 0.55),
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
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          pill!.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pill!.$2,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
