import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../services/sparkline_service.dart';
import '../theme/sandik.dart';

/// Varlık satırındaki mini trend grafiği — son 1 ayın fiyat eğrisi.
///
/// Neden `fl_chart` değil: `LineChart` her örneğinde eksen/grid/touch
/// katmanlarını kurar ve `LayoutBuilder` + `Stack` ağacı üretir. 60×24pt'lik
/// dekoratif bir eğri için bu ağaç, listedeki her satırda tekrarlandığında
/// ölçülebilir bir maliyettir. [CustomPainter] tek `drawPath` çağrısıyla aynı
/// sonucu verir; `fl_chart` tam grafiklerde (performans/detay ekranları)
/// kullanılmaya devam eder.
///
/// Renk kasıtlı olarak [gain]/[loss]'a bağlanır ve satırdaki yüzde ile aynı
/// kaynaktan beslenir — grafiğin yeşil, yazının kırmızı olması gibi bir
/// çelişki oluşmasın.
class AssetSparkline extends StatefulWidget {
  const AssetSparkline({
    super.key,
    required this.asset,
    required this.isPositive,
    this.width = 56,
    this.height = 24,
  });

  final Asset asset;

  /// Satırdaki kâr/zarar yönü — eğrinin rengini belirler.
  final bool isPositive;

  final double width;
  final double height;

  @override
  State<AssetSparkline> createState() => _AssetSparklineState();
}

class _AssetSparklineState extends State<AssetSparkline> {
  List<double>? _series;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AssetSparkline old) {
    super.didUpdateWidget(old);
    // Aynı satır farklı bir varlığa yeniden kullanıldığında (liste
    // sıralaması değişince) seriyi tazele.
    if (old.asset.ticker != widget.asset.ticker ||
        old.asset.type != widget.asset.type) {
      _series = null;
      _load();
    }
  }

  Future<void> _load() async {
    final data = await SparklineService.instance.seriesFor(widget.asset);
    if (!mounted) return;
    setState(() => _series = data);
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;

    // Yükleniyor ya da veri yok: alanı KORU ama boş bırak.
    //
    // Placeholder yerine boşluk bırakmak bilinçli — spinner koymak 20
    // satırlık listede 20 dönen çark demek; yer ayırmamak ise veri gelince
    // tüm satırların yeniden hizalanmasına (layout shift) yol açar.
    if (series == null || series.length < 2) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final color = widget.isPositive ? Sandik.gain : Sandik.loss;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SparklinePainter(series: series, color: color),
          // Ekran okuyucular için: eğri dekoratiftir, satırdaki tutar ve
          // yüzde zaten sesli okunuyor. Tekrar duyurmak gürültü olur.
          isComplex: false,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.series, required this.color});

  /// 0..1 aralığında normalize edilmiş değerler (bkz. [SparklineService]).
  final List<double> series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;

    // Çizgi kalınlığının yarısı kadar içeri çek — aksi halde en yüksek ve
    // en düşük nokta kutunun kenarında kırpılır.
    const stroke = 1.6;
    const pad = stroke / 2;
    final h = size.height - stroke;
    final dx = size.width / (series.length - 1);

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      // Normalize değer 1 = en yüksek fiyat; ekran koordinatında y küçülür.
      final x = i * dx;
      final y = pad + (1 - series[i]) * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Eğrinin altını hafif doldur — yön algısını çizgiden daha hızlı verir.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !identical(old.series, series);
}
