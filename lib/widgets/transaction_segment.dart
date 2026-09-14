import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Değer grafiğinin tek parça çizgisi — Portföy/Performans ve tekil varlık
/// ekranlarının ORTAK modeli (Faz 3.9'un ilk adımı, 2026-09-14).
///
/// İki ekran bu sınıfı ayrı ayrı tanımlıyordu; alanlar aynıydı, tek fark
/// bayrağın adıydı (`dashed` / `piyasaKapali`) ve tekil varlık ekranında
/// bayrak artık hiç `true` olmuyordu (alış öncesi pasif segment kaldırıldı).
/// Aynı görsel dil tek yerde: kapalı piyasa kuyruğu GRİ ve KESİKLİ çizilir,
/// altı doldurulmaz.
class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;

  /// Bu segment piyasa KAPALIYKEN taşınan son fiyat mı?
  ///
  /// Hafta sonu gün içi grafiği Cuma kapanışını bugüne kadar uzatıyor
  /// (bkz. `HistoryService.gunIciSagUc`). O kuyruk gerçek işlem değildir:
  /// tek bir fiyatın yayılmasıdır. Düz çizgi olarak çizilirse "fiyat hiç
  /// oynamadı" diye okunur — oysa borsa kapalıydı.
  ///
  /// `true` olduğunda çizgi GRİ ve KESİKLİ çizilir, altındaki alan
  /// doldurulmaz. Kullanıcı isteği (2026-09-12): "cmt ve pazar günü için
  /// piyasa kapalı ibaresi olup gri şekilde çizilecek."
  final bool piyasaKapali;

  TransactionSegment({
    required this.spots,
    required this.lineColor,
    required this.areaGradientStart,
    required this.areaGradientEnd,
    required this.thickness,
    this.piyasaKapali = false,
  });
}
