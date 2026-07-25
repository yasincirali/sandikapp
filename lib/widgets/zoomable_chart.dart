import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';

/// fl_chart [LineChart] üzerine pinch (iki parmak) zoom ve pan hareketi ekler.
///
/// Yaklaşım: LineChart'ın **üzerinde** her zaman aktif bir GestureDetector
/// katmanı var. `HitTestBehavior.translucent` ile aynı jesti alta da (LineChart
/// tooltip'ine) geçirir. Scale recognizer 2+ parmakta arena'yı kazanır ve
/// zoom uygulanır; tek parmak dokunma tooltip'e gider.
class ZoomableChart extends StatefulWidget {
  final double fullMinX;
  final double fullMaxX;
  final LineChartData Function(double minX, double maxX) builder;
  final double height;
  /// Viewport her değiştiğinde çağrılır (pan/pinch/reset). ZoomDataController
  /// bunu dinleyip uygun çözünürlükte yeni veri yükleyebilir.
  final void Function(double minX, double maxX)? onViewportChanged;

  const ZoomableChart({
    super.key,
    required this.fullMinX,
    required this.fullMaxX,
    required this.builder,
    this.height = 360,
    this.onViewportChanged,
  });

  @override
  State<ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<ZoomableChart> {
  late double _minX;
  late double _maxX;

  double _startMinX = 0;
  double _startMaxX = 0;
  double _startFocalRel = 0.5;
  double _chartWidth = 1.0;

  @override
  void initState() {
    super.initState();
    _minX = widget.fullMinX;
    _maxX = widget.fullMaxX;
  }

  @override
  void didUpdateWidget(covariant ZoomableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullMinX != widget.fullMinX ||
        oldWidget.fullMaxX != widget.fullMaxX) {
      _minX = widget.fullMinX;
      _maxX = widget.fullMaxX;
    }
  }

  bool get _isZoomed =>
      (_minX - widget.fullMinX).abs() > 0.001 ||
      (_maxX - widget.fullMaxX).abs() > 0.001;

  void _reset() {
    setState(() {
      _minX = widget.fullMinX;
      _maxX = widget.fullMaxX;
    });
    widget.onViewportChanged?.call(_minX, _maxX);
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

    setState(() {
      _minX = newMin;
      _maxX = newMax;
    });
    widget.onViewportChanged?.call(_minX, _maxX);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _chartWidth = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
      return SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // Alt: LineChart (tooltip'i için touch handler kendi içinde çalışır)
            Positioned.fill(child: LineChart(widget.builder(_minX, _maxX))),

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
                },
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
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
