import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ekrandaki her metnin, ARKASINDAKİ gerçek zemine karşı kontrastını ölçer.
///
/// Neden var (2026-10-08): varsayılan tema `ThemeMode.system` oldu; grafik,
/// yarış, auth ve mevduat ekranları açık temada hiç gözle görülmemişti
/// (TECHNICAL_DEBT "Light mode"). `light_mode_contrast_test` paletin
/// DEĞERLERİNİ doğrular, ama hata çoğu zaman token *seçiminde* ya da sabit
/// bir zeminin üstüne temadan gelen metin yazılmasındadır (ör. her iki
/// modda koyu kalan tooltip üstüne açık temanın koyu `gain`'i). Bu yardımcı
/// pompalanmış ağacı tarar: her `RenderParagraph`'ın rengi, element
/// atalarındaki ilk opak zemine (ara yarı saydam katmanlar harmanlanarak)
/// karşı ölçülür.
///
/// Bilinçli sınırlar — yanlış alarm yerine sessizlik seçildi:
/// * Gradyan zeminli metin atlanır (tek bir zemin rengi yok).
/// * Ata zincirinde opaklığı < 1 olan (`Opacity`, `FadeTransition`) metin
///   atlanır: bu bilinçli soluklaştırmadır (pasif/eski dönem) ya da geçiş
///   anıdır, okunacak son durum değildir.
/// * `Stack` kardeşi olarak çizilen zemin görülmez; o durumda bir üst atanın
///   zemini kullanılır. Bulgu çıkarsa elle doğrula.
class KontrastBulgusu {
  KontrastBulgusu(this.metin, this.renk, this.zemin, this.oran, this.esik);
  final String metin;
  final Color renk;
  final Color zemin;
  final double oran;
  final double esik;

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  String toString() => '"$metin" ${_hex(renk)} / ${_hex(zemin)} = '
      '${oran.toStringAsFixed(2)}:1 (eşik $esik)';
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 2.1 kontrast oranı — iki opak renk için.
double kontrastOrani(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Bir atanın zemine katkısı. `null` = katkı yok; [_Belirsiz] = ölçülemez.
Object? _zeminKatkisi(Widget w) {
  Decoration? d;
  if (w is ColoredBox) return w.color;
  if (w is DecoratedBox && w.position == DecorationPosition.background) {
    d = w.decoration;
  } else if (w is Ink) {
    d = w.decoration;
  } else if (w is PhysicalModel) {
    return w.color;
  } else if (w is PhysicalShape) {
    return w.color;
  } else if (w is Opacity) {
    return w.opacity < 0.99 ? const _Belirsiz() : null;
  } else if (w is FadeTransition) {
    return w.opacity.value < 0.99 ? const _Belirsiz() : null;
  }
  if (d is BoxDecoration) {
    if (d.gradient != null || d.image != null) return const _Belirsiz();
    return d.color;
  }
  if (d is ShapeDecoration) {
    if (d.gradient != null || d.image != null) return const _Belirsiz();
    return d.color;
  }
  return null;
}

class _Belirsiz {
  const _Belirsiz();
}

/// [element]'in arkasındaki etkin zemin; ölçülemiyorsa `null`.
Color? _zemin(Element element, Color varsayilan) {
  final katmanlar = <Color>[];
  var belirsiz = false;
  element.visitAncestorElements((a) {
    final k = _zeminKatkisi(a.widget);
    if (k is _Belirsiz) {
      belirsiz = true;
      return false;
    }
    if (k is Color && k.a > 0) {
      katmanlar.add(k);
      if (k.a >= 0.999) return false;
    }
    return true;
  });
  if (belirsiz) return null;
  var zemin = varsayilan;
  for (final k in katmanlar.reversed) {
    zemin = Color.alphaBlend(k, zemin);
  }
  return zemin;
}

/// Span ağacındaki her metin parçasının (metin, etkin renk) çifti.
void _parcalar(InlineSpan span, Color? miras, List<(String, Color)> out) {
  final renk = span.style?.color ?? miras;
  if (span is TextSpan) {
    final t = span.text?.trim() ?? '';
    if (t.isNotEmpty && renk != null) out.add((t, renk));
    for (final c in span.children ?? const <InlineSpan>[]) {
      _parcalar(c, renk, out);
    }
  }
}

/// Ağaçtaki metinleri tarar; eşiği geçemeyenleri döner.
///
/// Eşik WCAG AA: 4,5:1; büyük metin (≥ 24 px ya da ≥ 18,66 px kalın) ve
/// ikon glifi 3:1.
/// [haric] metni bu alt dizeyi içeren parçalar atlanır (bilinçli istisna —
/// çağıran gerekçesini yazmalı).
List<KontrastBulgusu> kontrastDenetle(
  WidgetTester tester, {
  required Color varsayilanZemin,
  Set<String> haric = const {},
}) {
  final bulgular = <KontrastBulgusu>[];
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    if (ro.size.isEmpty) continue;
    final creator = ro.debugCreator;
    if (creator is! DebugCreator) continue;
    final element = creator.element;
    final parcalar = <(String, Color)>[];
    _parcalar(ro.text, null, parcalar);
    if (parcalar.isEmpty) continue;
    final zemin = _zemin(element, varsayilanZemin);
    if (zemin == null) continue;
    final stil = ro.text.style;
    final boy = stil?.fontSize ?? 14;
    final kalin = (stil?.fontWeight?.value ?? 400) >= 700;
    final buyuk = boy >= 24 || (boy >= 18.66 && kalin);
    // İkon glifleri (`Icon` da `RichText` çizer) metin değil anlamlı
    // grafiktir: WCAG 1.4.11 → 3:1.
    final aile = stil?.fontFamily ?? '';
    final ikon = aile.contains('MaterialIcons') || aile.contains('Cupertino');
    final esik = buyuk || ikon ? 3.0 : 4.5;
    for (final (metin, renk) in parcalar) {
      if (renk.a == 0) continue;
      if (haric.any(metin.contains)) continue;
      final etkin = Color.alphaBlend(renk, zemin);
      final oran = kontrastOrani(etkin, zemin);
      if (oran < esik) {
        bulgular.add(KontrastBulgusu(metin, renk, zemin, oran, esik));
      }
    }
  }
  return bulgular;
}

/// Ağaçta ölçülen metin parçası sayısı — denetimin boş geçmediğini kanıtlar.
int olculenMetinSayisi(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderParagraph>()
    .where((r) => r.attached && r.hasSize && !r.size.isEmpty)
    .length;
