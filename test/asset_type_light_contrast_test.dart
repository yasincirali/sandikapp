import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Kategori renkleri light zeminde ikon/metin olarak OKUNMALI.
///
/// 2026-08-09 ölçümü: kategori renklerinin hepsi light `surface1` üstünde
/// AA altındaydı (altın 1,52:1). Dolgu olarak sorun değil (arkada %12-15
/// alfa), ama çıplak ikon ve tür etiketi metni olarak kullanıldıkları yerde
/// `AssetType.onSurface` koyulaştırılmış tonu verir. Bu test o tonu 4,5:1'e
/// (AA, küçük metin) bağlar ve koyu temada HAM rengin aynen kaldığını
/// doğrular — marka dark-first, oradaki renk değişmez.
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const light = SandikPalette.light;
  const dark = SandikPalette.dark;

  group('AssetType.onLightSurface', () {
    for (final t in AssetType.values) {
      test('${t.name}: light surface1 ve background üstünde ≥ 4,5:1', () {
        for (final zemin in [light.surface1, light.background]) {
          final cr = _contrast(t.onLightSurface, zemin);
          expect(cr, greaterThanOrEqualTo(4.5),
              reason: '${t.name}: ${cr.toStringAsFixed(2)}:1');
        }
      });

      test('${t.name}: ton korunur, yalnızca açıklık kısılır', () {
        // "Amber = hisse, mavi = fon" kimliği light modda da okunmalı;
        // yalnızca lightness düşer, hue aynı kalır.
        final ham = HSLColor.fromColor(t.color);
        final koyu = HSLColor.fromColor(t.onLightSurface);
        expect((ham.hue - koyu.hue).abs(), lessThan(2.0));
        expect(koyu.lightness, lessThanOrEqualTo(ham.lightness));
      });
    }
  });

  group('onSurface temaya göre seçer', () {
    Future<BuildContext> ctxWith(WidgetTester tester, ThemeData theme) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      return ctx;
    }

    testWidgets('koyu temada ham renk', (tester) async {
      final ctx = await ctxWith(tester, ThemeData.dark());
      for (final t in AssetType.values) {
        expect(t.onSurface(ctx), t.color, reason: t.name);
        // Koyu zeminde ham rengin kendisi okunur olmalı (mevcut sözleşme).
        expect(_contrast(t.color, dark.surface1), greaterThanOrEqualTo(3.0),
            reason: '${t.name} dark');
      }
    });

    testWidgets('açık temada koyulaştırılmış ton', (tester) async {
      final ctx = await ctxWith(tester, ThemeData.light());
      for (final t in AssetType.values) {
        expect(t.onSurface(ctx), t.onLightSurface, reason: t.name);
      }
    });
  });
}
