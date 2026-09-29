import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Metin tonlarının HİYERARŞİSİ iki temada da doğru sırada:
/// text90 (ana) > text58 (ikincil) > text36 (üçüncül), hepsi AA (4.5:1).
///
/// ## Yakaladığı hata (hareket/UX denetimi 2026-09-29)
/// Koyu temada text36'nın AA düzeltmesi (0x59 → 0x94) onu text58'in
/// (0x8C) ÜSTÜNE çıkarmıştı: tarihler ve dipnotlar ikincil etiketlerden
/// parlak görünüyordu. Her iki ton da tek başına AA'yı geçtiği için
/// kontrast testleri bunu görmüyordu — sıra ayrıca kilitlenmeli.
///
/// Saydam tonlar zemine düzleştirilerek ölçülür (koyu temanın metin
/// tonları beyazın opaklığıdır; alfa yok sayılırsa hepsi "beyaz" ölçülür).
double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

Color _duzlestir(Color fg, Color bg) {
  final a = fg.a;
  double k(double f, double b) => f * a + b * (1 - a);
  return Color.from(
      alpha: 1, red: k(fg.r, bg.r), green: k(fg.g, bg.g), blue: k(fg.b, bg.b));
}

double _kontrast(Color fg, Color bg) {
  final la = _luminance(_duzlestir(fg, bg));
  final lb = _luminance(bg);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (ad, p) in [
    ('açık', SandikPalette.light),
    ('koyu', SandikPalette.dark),
  ]) {
    for (final (zeminAd, zemin) in [
      ('surface1', p.surface1),
      ('background', p.background),
    ]) {
      test('$ad tema / $zeminAd: 90 > 58 > 36 ve hepsi AA', () {
        final k90 = _kontrast(p.text90, zemin);
        final k58 = _kontrast(p.text58, zemin);
        final k36 = _kontrast(p.text36, zemin);
        final ozet = '90=${k90.toStringAsFixed(2)} '
            '58=${k58.toStringAsFixed(2)} 36=${k36.toStringAsFixed(2)}';
        expect(k90, greaterThan(k58), reason: 'ana ≤ ikincil ($ozet)');
        expect(k58, greaterThan(k36), reason: 'ikincil ≤ üçüncül ($ozet)');
        expect(k36, greaterThanOrEqualTo(4.5), reason: 'üçüncül AA altı ($ozet)');
      });
    }
  }

  test('Sandik sabitleri koyu paletle aynı (iki tanım ayrışmasın)', () {
    expect(Sandik.text58, SandikPalette.dark.text58);
    expect(Sandik.text36, SandikPalette.dark.text36);
    expect(Sandik.text90, SandikPalette.dark.text90);
  });
}
