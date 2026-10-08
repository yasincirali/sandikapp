// Sığan metin: aynı anlamın uzun → kısa yazımlarından yere sığan İLKİNİ
// tam yazar.
//
// Kullanıcı kuralı (2026-10-01, Bugün kartı): "Yazan her metin tam okunur
// olmalı; sığmıyorsa daha kısa yazılmalı." Üç nokta bir cevap değil —
// "Getiri, enflasyon, en iyi …" hiçbir şey söylemiyor. Çeviri de yere göre
// değişmeli: 320pt'te "Enflasyona göre · yıllık" sığmazsa "Enflasyona göre"
// yeter, anlam kaybolmaz.
//
// Sıra: kısa yazım > satıra kırma > üç nokta. Hiçbir aday [maxLines]
// satıra sığmıyorsa en kısası [sonCareSatir] satıra kırılır; o da yetmezse
// üç nokta — ama buraya düşen yer tasarım hatasıdır, aday listesi uzatılır.
//
// **Neden RenderBox, neden LayoutBuilder değil:** ilk sürüm LayoutBuilder
// ile yazılmıştı; `IntrinsicHeight` (ızgarada iki kutuyu eşit boya getiren)
// LayoutBuilder'dan intrinsic ölçü isteyemez ve çöker. Kendi RenderBox'ı
// intrinsic'leri adaylardan hesaplar: en kısa adayın genişliği (min), en
// uzununki (max), verilen genişlikte seçilen adayın boyu (yükseklik).
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SiganMetin extends LeafRenderObjectWidget {
  const SiganMetin(
    this.adaylar, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.sonCareSatir = 2,
    this.textAlign,
  });

  /// Uzundan kısaya yazımlar; ilk sığan seçilir.
  final List<String> adaylar;
  final TextStyle? style;

  /// Adayların sığması gereken satır sayısı.
  final int maxLines;

  /// Hiçbir aday [maxLines] satıra sığmazsa en kısası bu kadar satıra
  /// kırılır. [maxLines]'tan küçükse [maxLines] sayılır.
  final int sonCareSatir;
  final TextAlign? textAlign;

  /// [adaylar] içinden [genislik]'e [maxLines] satırda sığan ilk metin;
  /// hiçbiri sığmıyorsa `null`. Saf — `bugun_karti_sakin_pano_test` kilitler.
  static String? sigan(
    List<String> adaylar, {
    required double genislik,
    required TextStyle stil,
    required TextDirection yon,
    required TextScaler olcek,
    int maxLines = 1,
  }) {
    for (final a in adaylar) {
      final tp = TextPainter(
        text: TextSpan(text: a, style: stil),
        textDirection: yon,
        maxLines: maxLines,
        textScaler: olcek,
      )..layout(maxWidth: genislik);
      // +0.5: alt piksel yuvarlaması tam sığan metni elemesin.
      final sigar = !tp.didExceedMaxLines && tp.width <= genislik + 0.5;
      tp.dispose();
      if (sigar) return a;
    }
    return null;
  }

  TextStyle _stil(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(style);

  @override
  RenderObject createRenderObject(BuildContext context) => SiganMetinRender(
        adaylar: adaylar,
        stil: _stil(context),
        yon: Directionality.of(context),
        olcek: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        sonCareSatir: sonCareSatir,
        hiza: textAlign ?? TextAlign.start,
      );

  @override
  void updateRenderObject(BuildContext context, SiganMetinRender renderObject) {
    renderObject
      ..adaylar = adaylar
      ..stil = _stil(context)
      ..yon = Directionality.of(context)
      ..olcek = MediaQuery.textScalerOf(context)
      ..maxLines = maxLines
      ..sonCareSatir = sonCareSatir
      ..hiza = textAlign ?? TextAlign.start;
  }
}

/// [SiganMetin]'in kutusu; dışarıya yalnızca [secilen] için açık.
class SiganMetinRender extends RenderBox {
  SiganMetinRender({
    required List<String> adaylar,
    required TextStyle stil,
    required TextDirection yon,
    required TextScaler olcek,
    required int maxLines,
    required int sonCareSatir,
    required TextAlign hiza,
  })  : _adaylar = adaylar,
        _stil = stil,
        _yon = yon,
        _olcek = olcek,
        _maxLines = maxLines,
        _sonCareSatir = sonCareSatir,
        _hiza = hiza;

  List<String> _adaylar;
  TextStyle _stil;
  TextDirection _yon;
  TextScaler _olcek;
  int _maxLines;
  int _sonCareSatir;
  TextAlign _hiza;

  set adaylar(List<String> v) {
    if (identical(v, _adaylar) || listEquals(v, _adaylar)) return;
    _adaylar = v;
    markNeedsLayout();
  }

  set stil(TextStyle v) {
    if (v == _stil) return;
    _stil = v;
    markNeedsLayout();
  }

  set yon(TextDirection v) {
    if (v == _yon) return;
    _yon = v;
    markNeedsLayout();
  }

  set olcek(TextScaler v) {
    if (v == _olcek) return;
    _olcek = v;
    markNeedsLayout();
  }

  set maxLines(int v) {
    if (v == _maxLines) return;
    _maxLines = v;
    markNeedsLayout();
  }

  set sonCareSatir(int v) {
    if (v == _sonCareSatir) return;
    _sonCareSatir = v;
    markNeedsLayout();
  }

  set hiza(TextAlign v) {
    if (v == _hiza) return;
    _hiza = v;
    markNeedsLayout();
  }

  /// Çizilen metnin boyacısı; [performLayout]'ta kurulur.
  TextPainter? _tp;
  String _secilen = '';

  /// Son yerleşimde seçilen yazım — `find.text` bu kutuyu görmez, testler
  /// buradan okur.
  @visibleForTesting
  String get secilen => _secilen;

  /// [genislik]'e göre adayı seçer ve o metin için boyacı kurar.
  /// Intrinsic sorguları canlı boyacıyı bozmasın diye her çağrı YENİ
  /// boyacı döndürür; çağıran dispose eder.
  TextPainter _kur(double minW, double maxW) {
    final secilen = SiganMetin.sigan(
      _adaylar,
      genislik: maxW,
      stil: _stil,
      yon: _yon,
      olcek: _olcek,
      maxLines: _maxLines,
    );
    final satir = secilen == null
        ? (_sonCareSatir > _maxLines ? _sonCareSatir : _maxLines)
        : _maxLines;
    _secilen = secilen ?? (_adaylar.isEmpty ? '' : _adaylar.last);
    return TextPainter(
      text: TextSpan(text: _secilen, style: _stil),
      textDirection: _yon,
      textScaler: _olcek,
      maxLines: satir,
      ellipsis: '…',
      textAlign: _hiza,
    )..layout(minWidth: minW, maxWidth: maxW);
  }

  double _genislik(String metin) {
    final tp = TextPainter(
      text: TextSpan(text: metin, style: _stil),
      textDirection: _yon,
      textScaler: _olcek,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _adaylar.isEmpty ? 0 : _genislik(_adaylar.last);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _adaylar.isEmpty ? 0 : _genislik(_adaylar.first);

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final tp = _kur(0, width);
    final h = tp.height;
    tp.dispose();
    return h;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final tp = _kur(constraints.minWidth, constraints.maxWidth);
    final s = constraints.constrain(tp.size);
    tp.dispose();
    return s;
  }

  @override
  void performLayout() {
    _tp?.dispose();
    _tp = _kur(constraints.minWidth, constraints.maxWidth);
    size = constraints.constrain(_tp!.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _tp?.paint(context.canvas, offset);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _secilen
      ..textDirection = _yon;
  }

  @override
  void dispose() {
    _tp?.dispose();
    _tp = null;
    super.dispose();
  }
}
