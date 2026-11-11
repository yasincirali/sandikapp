import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';

/// Sıra değişince satırların eski yerinden yenisine kayması (FLIP).
///
/// Neden (2026-11-11): Portföy ve Takip listesi sıralama düğmesiyle ya da
/// fiyat turunda yeniden dizilince satırlar anında yer değiştiriyordu; göz
/// hangi satırın nereye gittiğini kaybediyordu. Satır eski konumundan yeni
/// konumuna [SandikMotion.surface] (~240 ms) ve [SandikMotion.move] ile
/// kayar; hareketi azalt açıkken anlık.
///
/// Kararlar:
/// - **Yalnız sıra.** [sira] aynı anahtar kümesinin farklı dizilişini
///   görürse anlık konumları alır; ekleme/çıkarma/süzgeç (küme değişti)
///   eski davranışta kalır — Takip'in çıkış animasyonu ve yeni satır
///   parlaması kendi işini yapar.
/// - **Yeniden kurulum yok.** Kayma [_SiraKaydirmaRender]'ın boyamasında
///   ötelemedir; satırın alt ağacı (Portföy `_ImzaliSatir` önbelleği)
///   kurulmaz, her karede yalnız boyama tazelenir.
/// - **Konum içerik ekseninde.** Viewport'a göre konum + kaydırma ofseti:
///   kaydırma kayma sayılmaz, sliver türü (Takip'in grup sliver'ı,
///   sürüklenebilir liste ↔ düz liste değişimi) fark etmez. Eleman yeniden
///   doğsa bile anahtarla eşleşir.
/// - **Yalnız görünenler.** Kurulu (görünen + önbellek payı) satırlar
///   ölçülür; ekran dışından gelen satır yerinde belirir.
/// - **Parmak değerken kapalı.** [dinle] listedeki işaretçileri sayar:
///   kaydırırken, Slidable panelini çekerken ya da Takip'te sürüklerken
///   sıra değişirse anında uygulanır, satır parmağın altından kaymaz.
class SiraKaydirmaDenetcisi {
  final Map<Object, _SiraKaydirmaRender> _satirlar = {};
  List<Object>? _onceki;
  Map<Object, double> _anlik = const {};
  int _no = 0;
  int _basili = 0;

  /// Liste her kurulduğunda ekrandaki sırayla çağrılır. [etkin] `false`
  /// ise (ör. Takip'te sürükleyerek yeniden sıralama) yalnız sıra
  /// kaydedilir.
  void sira(List<Object> anahtarlar, {bool etkin = true}) {
    final once = _onceki;
    _onceki = List.of(anahtarlar);
    if (!etkin || _basili > 0 || once == null) return;
    if (once.length != anahtarlar.length || listEquals(once, anahtarlar)) {
      return;
    }
    if (!setEquals(once.toSet(), anahtarlar.toSet())) return;
    // Henüz yeni yerleşim yapılmadı: ölçülen konumlar ESKİ sıranınki.
    final anlik = <Object, double>{};
    for (final MapEntry(:key, :value) in _satirlar.entries) {
      final y = value._gorselY();
      if (y != null) anlik[key] = y;
    }
    if (anlik.isEmpty) return;
    _anlik = anlik;
    _no++;
    // Yalnız yeri değişen satır, katmanı (RepaintBoundary) yeniden
    // kullanıldığı için boyanmaz; yeni konumunu görebilsin diye.
    for (final r in _satirlar.values) {
      r.markNeedsPaint();
    }
    // Anlık konumlar yalnız bu kare için: sonra kurulan satır (kaydırınca
    // ekrana giren) eski bir ölçüme bakıp boşuna kaymasın.
    SchedulerBinding.instance.addPostFrameCallback((_) => _anlik = const {});
  }

  /// Listeyi sarar; parmak değdiği sürece [sira] kayma başlatmaz.
  Widget dinle({required Widget child}) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _basili++,
        onPointerUp: (_) => _basili = math.max(0, _basili - 1),
        onPointerCancel: (_) => _basili = math.max(0, _basili - 1),
        child: child,
      );
}

/// Bir liste satırı. Anahtar ([key]) listedeki satır anahtarıyla aynı
/// olmalı (sliver eleman eşlemesi en dıştaki anahtara bakar); [anahtar]
/// denetçideki kimliktir.
class SiraKaydirmaSatiri extends StatefulWidget {
  const SiraKaydirmaSatiri({
    super.key,
    required this.denetci,
    required this.anahtar,
    required this.child,
  });

  final SiraKaydirmaDenetcisi denetci;
  final Object anahtar;
  final Widget child;

  @override
  State<SiraKaydirmaSatiri> createState() => _SiraKaydirmaSatiriState();
}

class _SiraKaydirmaSatiriState extends State<SiraKaydirmaSatiri>
    with SingleTickerProviderStateMixin {
  /// İlk kaymada kurulur: listedeki onlarca satır boşuna ticker taşımasın.
  AnimationController? _c;

  void _basla() {
    if (!mounted) return;
    final yeni = _c == null;
    final c = _c ??=
        AnimationController(vsync: this, duration: SandikMotion.surface);
    c.forward(from: 0);
    if (yeni) setState(() {});
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SiraKaydirmaKutusu(
        denetci: widget.denetci,
        anahtar: widget.anahtar,
        etkin: !MediaQuery.disableAnimationsOf(context),
        konum: Scrollable.maybeOf(context)?.position,
        animasyon: _c,
        onBasla: _basla,
        child: widget.child,
      );
}

class _SiraKaydirmaKutusu extends SingleChildRenderObjectWidget {
  const _SiraKaydirmaKutusu({
    required this.denetci,
    required this.anahtar,
    required this.etkin,
    required this.konum,
    required this.animasyon,
    required this.onBasla,
    super.child,
  });

  final SiraKaydirmaDenetcisi denetci;
  final Object anahtar;
  final bool etkin;
  final ScrollPosition? konum;
  final AnimationController? animasyon;
  final VoidCallback onBasla;

  @override
  _SiraKaydirmaRender createRenderObject(BuildContext context) =>
      _SiraKaydirmaRender(denetci, anahtar)
        ..etkin = etkin
        ..konum = konum
        ..animasyon = animasyon
        ..onBasla = onBasla;

  @override
  void updateRenderObject(
          BuildContext context, _SiraKaydirmaRender renderObject) =>
      renderObject
        ..yeniden(denetci, anahtar)
        ..etkin = etkin
        ..konum = konum
        ..animasyon = animasyon
        ..onBasla = onBasla;
}

class _SiraKaydirmaRender extends RenderProxyBox {
  _SiraKaydirmaRender(this._denetci, this._anahtar);

  SiraKaydirmaDenetcisi _denetci;
  Object _anahtar;
  bool etkin = true;
  ScrollPosition? konum;
  VoidCallback? onBasla;

  /// Son ölçülen ve uygulanan anlık konum turu.
  int _no = -1;

  /// Kaymanın başladığı öteleme (eski − yeni).
  double _bas = 0;

  /// Kayma bu karede başladı, denetleyici bir sonraki karede koşacak:
  /// arada satır ESKİ yerinde boyanır (tek karelik sıçrama yok).
  bool _bekliyor = false;

  AnimationController? _animasyon;
  set animasyon(AnimationController? a) {
    if (identical(a, _animasyon)) return;
    if (attached) _animasyon?.removeListener(_tik);
    _animasyon = a;
    if (attached) a?.addListener(_tik);
    if (a != null && a.isAnimating) _bekliyor = false;
    markNeedsPaint();
  }

  void _tik() {
    _bekliyor = false;
    markNeedsPaint();
  }

  void yeniden(SiraKaydirmaDenetcisi d, Object anahtar) {
    if (identical(d, _denetci) && anahtar == _anahtar) return;
    _kaydiSil();
    _denetci = d;
    _anahtar = anahtar;
    if (attached) _denetci._satirlar[_anahtar] = this;
  }

  void _kaydiSil() {
    if (identical(_denetci._satirlar[_anahtar], this)) {
      _denetci._satirlar.remove(_anahtar);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _denetci._satirlar[_anahtar] = this;
    _animasyon?.addListener(_tik);
  }

  @override
  void detach() {
    _kaydiSil();
    _animasyon?.removeListener(_tik);
    super.detach();
  }

  double get _kayma {
    if (_bekliyor) return _bas;
    final a = _animasyon;
    if (a == null || !a.isAnimating) return 0;
    return _bas * (1 - SandikMotion.move.transform(a.value));
  }

  /// İçerik eksenindeki konum (kaydırmadan bağımsız), ötelemesiz.
  double? _dogalY() {
    final k = konum;
    if (!attached || !hasSize || k == null || !k.hasPixels) return null;
    final vp = RenderAbstractViewport.maybeOf(this);
    if (vp == null) return null;
    return localToGlobal(Offset.zero, ancestor: vp).dy + k.pixels;
  }

  /// Gözün gördüğü konum: yarıda kesilen kayma oradan devam eder.
  double? _gorselY() {
    final y = _dogalY();
    return y == null ? null : y + _kayma;
  }

  void _anlikKontrol() {
    if (_no == _denetci._no) return;
    _no = _denetci._no;
    final eski = _denetci._anlik[_anahtar];
    if (eski == null || !etkin) return;
    final yeni = _dogalY();
    if (yeni == null) return;
    final fark = eski - yeni;
    if (fark.abs() < 0.5) return;
    _bas = fark;
    _bekliyor = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => onBasla?.call());
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _anlikKontrol();
    final k = _kayma;
    if (k == 0 || child == null) {
      super.paint(context, offset);
    } else {
      context.paintChild(child!, offset.translate(0, k));
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final k = _kayma;
    if (k != 0) transform.translateByDouble(0.0, k, 0.0, 1.0);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final k = _kayma;
    if (k == 0) return super.hitTestChildren(result, position: position);
    return result.addWithPaintOffset(
      offset: Offset(0, k),
      position: position,
      hitTest: (r, p) => child?.hitTest(r, position: p) ?? false,
    );
  }
}
