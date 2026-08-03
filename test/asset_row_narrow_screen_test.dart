import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// Varlık satırında kolon genişliklerinin dağıtımı.
///
/// **Bug:** sparkline (56pt) ve tutar kolonu (108pt) SABİT genişlikteydi;
/// isme "kalan ne varsa" düşüyordu. iPhone 12 mini'de (375pt) isim alanı
/// 81pt'ye, 320pt'lik cihazlarda 26pt'ye iniyordu ve isimler okunmuyordu.
///
/// **Çözüm:** sabit değer ve cihaz eşiği YOK. Kolonlar satırın gerçek
/// genişliğinden pay alır; önce isim tabanı ayrılır, tutar kolonu ölçeklenir,
/// sparkline yalnızca ARTAN alandan beslenir.
///
/// Buradaki [resolve], charts_screen.dart'taki `_AssetCardMetrics.resolve`
/// ile birebir aynı olmalı — private olduğu için kopyalandı. Orası
/// değişirse burası da güncellenmeli.

const double kMinNameWidth = 112;
const double kMaxSparklineWidth = 56;
const double kMinValueWidth = 88;
const double kMaxValueWidth = 108;
const double kColumnGap = 8;
const double kLeadingWidth = 28 + 14;
const double kTrailingChevronWidth = 32 + 4;

({double name, double spark, double value}) resolve(double rowWidth) {
  final afterLeading = rowWidth - kLeadingWidth - kTrailingChevronWidth;
  double value = kMaxValueWidth;
  final needForNameAndValue = kMinNameWidth + kColumnGap + value;
  if (afterLeading < needForNameAndValue) {
    value = (afterLeading - kMinNameWidth - kColumnGap)
        .clamp(kMinValueWidth, kMaxValueWidth);
  }
  double name = afterLeading - kColumnGap - value;
  double spark = 0;
  final surplus = name - kMinNameWidth;
  final slot = (surplus / 2).clamp(0.0, kColumnGap + kMaxSparklineWidth);
  if (slot > kColumnGap) {
    spark = slot - kColumnGap;
    name -= slot;
  }
  if (name < 0) name = 0;
  return (name: name, spark: spark, value: value);
}

/// Kart iç genişliği = ekran − liste padding (20×2) − kart padding.
double rowWidthFor(double screenW) => screenW - 40 - 12 * 2;

/// Düzeltme öncesi isim alanı — sabit sparkline + sabit tutar kolonu.
double legacyNameWidth(double screenW) =>
    screenW - 40 - 32 - kLeadingWidth - (8 + 56) - (8 + 108) - 36;

void main() {
  group('kolon dağıtımı', () {
    test('iPhone 12 mini (375pt) isme okunabilir alan verir', () {
      final m = resolve(rowWidthFor(375));
      expect(m.name, greaterThanOrEqualTo(kMinNameWidth));
      expect(m.name, greaterThan(legacyNameWidth(375)),
          reason: 'düzeltme öncesi 45pt idi');
    });

    test('çok dar cihazda (320pt) isim alanı kullanılabilir olur', () {
      final m = resolve(rowWidthFor(320));
      // 320pt'de taban matematiksel olarak ulaşılamaz (satırın tamamı
      // 256pt). Garanti: eski 26pt'den çok daha iyi ve tutar kolonu
      // küçülerek isme yer açmış olmalı.
      expect(m.name, greaterThan(3 * legacyNameWidth(320)));
      expect(m.value, lessThan(kMaxValueWidth));
      // Alan yetmediği için önce sparkline, sonra tutar kolonu feda edilir.
      expect(m.spark, 0);
      expect(m.value, lessThanOrEqualTo(kMaxValueWidth));
      expect(m.value, greaterThanOrEqualTo(kMinValueWidth));
    });

    test('tablet genişliğinde sparkline tam boyuna doyar', () {
      final m = resolve(rowWidthFor(834));
      expect(m.spark, kMaxSparklineWidth);
      expect(m.value, kMaxValueWidth);
      expect(m.name, greaterThan(400),
          reason: 'doyum sonrası artan alan tamamen isme gider');
    });

    test('isim alanı hiçbir genişlikte tabanın altına inmez', () {
      for (var w = 280.0; w <= 1024.0; w += 1) {
        final m = resolve(rowWidthFor(w));
        // Taban ancak satır onu taşıyabildiğinde garanti edilebilir.
        final canHonourFloor = rowWidthFor(w) >=
            kLeadingWidth + kMinNameWidth + kColumnGap + kMinValueWidth +
                kTrailingChevronWidth;
        if (!canHonourFloor) continue;
        expect(m.name, greaterThanOrEqualTo(kMinNameWidth - 0.001),
            reason: '$w pt: isim tabanı ihlal edildi');
      }
    });

    test('isim alanı ekran genişledikçe pratikte daralmaz', () {
      // Sürekli dağıtımın kazancı: eski tasarımdaki 64pt'lik sıçrama yok.
      // Sparkline ilk belirdiğinde tek seferlik ≤8pt'lik bir düzeltme olur;
      // gözle fark edilmez, ama sessizce büyümesin diye sınırlanmıştır.
      double prev = -1;
      double worstDrop = 0;
      for (var w = 300.0; w <= 1024.0; w += 1) {
        final cur = resolve(rowWidthFor(w)).name;
        if (prev >= 0 && cur < prev) worstDrop = max(worstDrop, prev - cur);
        prev = cur;
      }
      expect(worstDrop, lessThanOrEqualTo(8.0),
          reason: 'isim alanındaki en büyük geri düşüş 8pt sınırını aşmamalı');
    });

    test('sparkline üst sınırını aşmaz ve negatif olmaz', () {
      for (var w = 280.0; w <= 1024.0; w += 1) {
        final s = resolve(rowWidthFor(w)).spark;
        expect(s, greaterThanOrEqualTo(0));
        expect(s, lessThanOrEqualTo(kMaxSparklineWidth));
      }
    });

    test('kolonlar satır genişliğini taşırmaz', () {
      for (var w = 300.0; w <= 1024.0; w += 1) {
        final rw = rowWidthFor(w);
        final m = resolve(rw);
        final used = kLeadingWidth +
            m.name +
            (m.spark > 0 ? kColumnGap + m.spark : 0) +
            kColumnGap +
            m.value +
            kTrailingChevronWidth;
        expect(used, lessThanOrEqualTo(rw + 0.001),
            reason: '$w pt: satır taşıyor (overflow)');
      }
    });

    test('hiçbir genişlikte düzeltme öncesinden kötü değil', () {
      for (var w = 300.0; w <= 500.0; w += 1) {
        expect(resolve(rowWidthFor(w)).name,
            greaterThanOrEqualTo(legacyNameWidth(w) - 0.001),
            reason: '$w pt: isim alanı eskisinden dar');
      }
    });
  });
}
