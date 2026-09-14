@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Çubuk grafiğinin GÖRSEL önizlemesi — PNG üretir.
///
/// ## Neden var
///
/// Bu makinedeki emülatörler Flutter'ı render EDEMİYOR (ekran görüntüsü
/// tamamen siyah; süreç yaşıyor, FATAL yok — CLAUDE.md'de belgelenmiş,
/// 2026-08-09 ve 2026-09-14'te iki kez doğrulandı; `-gpu swiftshader_indirect`
/// de çözmüyor). Yani "doğru görünüyor mu" sorusu cihazda yanıtlanamıyor.
///
/// Flutter'ın test motoru kendi yazılımsal rasterizer'ıyla çiziyor ve
/// emülatörün GPU'suna ihtiyaç duymuyor — grafiği burada çizip PNG'ye
/// döküyoruz. Üretilen dosyalar `build/gorsel/` altına düşer.
///
/// Koşmak için:  flutter test test/cubuk_gorsel_onizleme_test.dart
///
/// Bu bir GOLDEN test DEĞİL: hiçbir şeyi assert etmiyor, sadece bakılacak
/// bir resim üretiyor. CI'da koşmasın diye `gorsel` etiketi taşıyor.
void main() {
  /// Senaryo: kullanıcının 2026-09-14 ekran görüntüsündeki gün.
  /// Portföy ₺2,51M'den ₺2,49M'ye düşüyor — bandın genişliği değerin
  /// yalnızca ~%0,8'i. Bar grafiğini kıran tam olarak bu dar bant.
  List<FlSpot> gunIciSeri() {
    final rnd = math.Random(42);
    final spots = <FlSpot>[];
    var deger = 2510000.0;
    // 10:00–18:00 arası, 5 dakikada bir → 96 nokta.
    for (var dk = 600; dk <= 1080; dk += 5) {
      // Sabah yatay, öğleden sonra düşüş (ekran görüntüsündeki desen).
      final egim = dk < 780 ? 0.0 : -95.0;
      deger += egim + (rnd.nextDouble() - 0.5) * 900;
      spots.add(FlSpot(dk.toDouble(), deger));
    }
    return spots;
  }

  /// ESKİ davranış: taban = görünür pencerenin dibi, kalınlık sabit 2.0,
  /// seyreltme segment başına 60.
  List<LineChartBarData> eskiCubuklar(List<FlSpot> spots, double viewMinY) {
    const maksCubuk = 60;
    final adim = (spots.length / maksCubuk).ceil().clamp(1, 1 << 30);
    final out = <LineChartBarData>[];
    for (var i = 0; i < spots.length; i += adim) {
      final s = spots[i];
      out.add(LineChartBarData(
        spots: [FlSpot(s.x, viewMinY), FlSpot(s.x, s.y)],
        isCurved: false,
        color: const Color(0xFF8B6F3A),
        barWidth: 2.0,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    return out;
  }

  /// YENİ davranış: taban = dönem başı, kalınlık yoğunluktan, renk yönden.
  /// `_cubukSegmentleri`'nin aynı cebri (private olduğu için burada tekrar).
  List<LineChartBarData> yeniCubuklar(
    List<FlSpot> spots,
    double tabanY,
    double genislik,
  ) {
    const minAralikPx = 6.0;
    const maksAralikPx = 22.0;
    final maksCubuk = (genislik / minAralikPx).floor().clamp(8, 240);
    final adim = (spots.length / maksCubuk).ceil().clamp(1, 1 << 30);
    final cizilecek = (spots.length / adim).ceil().clamp(1, maksCubuk);
    final aralikPx = (genislik / cizilecek).clamp(minAralikPx, maksAralikPx);
    final kalinlik = (aralikPx * 0.65).clamp(2.0, 14.0);

    final out = <LineChartBarData>[];
    for (var i = 0; i < spots.length; i += adim) {
      final s = spots[i];
      out.add(LineChartBarData(
        spots: [FlSpot(s.x, tabanY), FlSpot(s.x, s.y)],
        isCurved: false,
        color: s.y >= tabanY
            ? const Color(0xFF2E7D57) // gain
            : const Color(0xFFB3261E), // loss
        barWidth: kalinlik,
        isStrokeCapRound: kalinlik >= 5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    return out;
  }

  Widget kart(String baslik, List<LineChartBarData> bars, double minY,
      double maxY, List<FlSpot> spots) {
    return Container(
      color: const Color(0xFFFAF7F2),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(baslik,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          const Text('Bugünkü birikim değişimi  −₺12.794  (%0,51)',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: spots.first.x,
                maxX: spots.last.x,
                minY: minY,
                maxY: maxY,
                lineBarsData: bars,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.black12, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  testWidgets('çubuk grafiği önizlemesi — eski vs yeni', (tester) async {
    const genislik = 420.0;
    const yukseklik = 620.0;
    tester.view.physicalSize = const ui.Size(genislik * 2, yukseklik * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final spots = gunIciSeri();
    final taban = spots.first.y;
    var minY = double.infinity, maxY = -double.infinity;
    for (final s in spots) {
      minY = math.min(minY, s.y);
      maxY = math.max(maxY, s.y);
    }
    // Yeni davranış tabanı Y aralığına katıyor.
    final yeniMinY = math.min(minY, taban) - 2000;
    final yeniMaxY = math.max(maxY, taban) + 2000;
    final eskiMinY = minY - 2000;
    final eskiMaxY = maxY + 2000;

    final dizin = Directory('build/gorsel')..createSync(recursive: true);

    Future<void> ciz(String ad, Widget w) async {
      // Anahtar her çağrıda YENİ: aynı GlobalKey'i ikinci bir pumpWidget'a
      // vermek ağacı yeniden kullanmaya çalışıp çizimi asıyordu.
      final anahtar = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: ui.Size(genislik, yukseklik)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              // RepaintBoundary şart: kök render view `toImage` sunmuyor,
              // yakalanabilen tek katman kendi sınırımız.
              child: RepaintBoundary(
                key: anahtar,
                child:
                    SizedBox(width: genislik, height: yukseklik, child: w),
              ),
            ),
          ),
        ),
      );
      // `pumpAndSettle` KULLANILMAZ: fl_chart'ın giriş animasyonu test
      // saatinde sürekli tick atıyor ve settle hiç gerçekleşmiyor (ikinci
      // kart çiziminde süresiz asılı kaldı). Sabit sayıda kare yeterli —
      // animasyon zaten 250ms'de bitiyor.
      await tester.pump(const Duration(milliseconds: 600));

      final boundary = anahtar.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dizin.path}/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());

      // Ağacı boşalt: fl_chart'ın animasyon ticker'ı sonraki pumpWidget'a
      // taşınırsa çizim asılı kalıyor.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    }

    // İki kart TEK karede: ayrı `pumpWidget` çağrılarında fl_chart'ın
    // ticker'ı ikinci çizimi süresiz asıyordu (üç deneme). Tek ağaç hem
    // sorunu çözüyor hem karşılaştırmayı doğrudan yan yana koyuyor.
    await ciz(
      'cubuk_karsilastirma',
      Column(
        children: [
          Expanded(
            child: kart('ESKİ — taban pencere dibi, sabit 2px',
                eskiCubuklar(spots, eskiMinY), eskiMinY, eskiMaxY, spots),
          ),
          Expanded(
            child: kart(
                'YENİ — taban dönem başı, kalınlık yoğunluktan',
                yeniCubuklar(spots, taban, genislik - 32),
                yeniMinY,
                yeniMaxY,
                spots),
          ),
        ],
      ),
    );

    // ignore: avoid_print
    print('PNG üretildi: ${dizin.absolute.path}');
  });
}
