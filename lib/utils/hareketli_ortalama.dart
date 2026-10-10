/// Fiyat grafiği katmanları: EMA50/EMA200 ve mum (varlık detayı, 2026-10-10).
///
/// Kullanıcı isteği (yasin, 2026-10-10): *"EMA50 ve EMA200 hareketli
/// ortalamaları koyalım, biri yeşil biri kırmızı; mum grafik ekle, o da
/// logaritmik olsun."* Hesap ekranın `build()`'inde değil burada (CLAUDE.md
/// "Katmanlama"); fonksiyonlar saf, testleri `hareketli_ortalama_test.dart`.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

import '../services/history_service.dart' show ResolutionTier;
import '../services/technical_analysis_service.dart';
import 'mum_turetici.dart';

/// Grafikteki uzun ortalamalar. MA20 ayrı (kesikli, nötr renk) kalır.
const int kEmaKisa = 50;
const int kEmaUzun = 200;

/// EMA'nın ısınması için dönem başından ÖNCE kaç takvim günü istenir.
///
/// ## Neden geri bakış
/// EMA, seçili dönemin çubukları üzerinden hesaplanır (TradingView'de grafiğin
/// zaman dilimi neyse ortalama da onun çubuklarıdır). Ama 1A'da ~22 günlük
/// nokta var: yalnız dönem içinden hesaplansa EMA50 hiç, EMA200 neredeyse hiçbir
/// dönemde çizilmezdi. Aynı motor ve AYNI çözünürlükten dönemden önceki
/// [periyot] çubuk istenir; böylece çizgi dönemin ilk noktasından başlar ve
/// ölçeği grafikle birebir aynıdır (fiyat kaynağı sözleşmesi madde 2).
///
/// Çubuk başına takvim günü: haftalık 7; günlük 7/5 (hafta sonu yok); saatlik
/// BIST seansı ~8 saat/gün → 1/8 işlem günü. +%15 ve sabit pay tatiller için.
/// Gün içi (5 dk) için geri bakış YOK (0): gün tek seanstır, önceki günün
/// 5 dakikalıkları başka bir motordan gelir.
int emaGeriBakisGunu(ResolutionTier katman, int periyot) {
  final double gunPerCubuk = switch (katman) {
    ResolutionTier.weekly => 7,
    ResolutionTier.daily => 7 / 5,
    ResolutionTier.hourly => (1 / 8) * 7 / 5,
    _ => 0,
  };
  if (gunPerCubuk == 0) return 0;
  return (periyot * gunPerCubuk * 1.15).ceil() + 7;
}

/// [seri] (grafiğin çizdiği nokta dizisi, X artan) üzerine EMA noktaları.
///
/// [onSeri] dönem öncesi ısınma noktalarıdır (aynı X uzayında; X'i
/// `seri.first.x`'ten küçük olanlar kullanılır, gerisi atlanır — örtüşen kısım
/// grafiğin KENDİ noktalarından gelir ki EMA'nın ucu çizginin ucuyla aynı
/// sayıyla bitsin). Dönen noktalar yalnız [seri]'nin X aralığındadır; yeterli
/// nokta yoksa boş liste (uydurma yok — CLAUDE.md "Fiyat kaynağı" madde 3).
List<FlSpot> emaNoktalari(
  List<FlSpot> seri, {
  required int periyot,
  List<FlSpot> onSeri = const [],
}) {
  if (seri.isEmpty) return const [];
  final ilkX = seri.first.x;
  final birlesik = <FlSpot>[
    for (final s in onSeri)
      if (s.x < ilkX && s.y.isFinite && s.y > 0) s,
    for (final s in seri)
      if (s.y.isFinite) s,
  ]..sort((a, b) => a.x.compareTo(b.x));
  final ema = TechnicalAnalysisService.emaSeries(
      [for (final s in birlesik) s.y], periyot);
  return [
    for (var i = 0; i < birlesik.length; i++)
      if (!ema[i].isNaN && birlesik[i].x >= ilkX) FlSpot(birlesik[i].x, ema[i]),
  ];
}

/// Ham fiyat mumlarını grafiğin Y uzayına taşır (LOG açıkken log10).
///
/// Dönüşüm monoton olduğu için mumun yönü ve en yüksek/en düşük sırası
/// değişmez; yalnızca konumlar log ölçeğe geçer — "mum da logaritmik olsun".
List<Mum> mumlariDonustur(List<Mum> mumlar, double Function(double) toY) => [
      for (final m in mumlar)
        Mum(
          x: m.x,
          kovaMs: m.kovaMs,
          acilis: toY(m.acilis),
          enYuksek: toY(m.enYuksek),
          enDusuk: toY(m.enDusuk),
          kapanis: toY(m.kapanis),
          noktaSayisi: m.noktaSayisi,
        ),
    ];

/// Log ölçek dönüşümü — varlık detayındaki `toY` ile aynı taban (log10) ve
/// aynı alt sınır (sıfır/negatif fiyat log'da tanımsız).
double log10Fiyat(double y) => math.log(y < 1e-6 ? 1e-6 : y) / math.ln10;
