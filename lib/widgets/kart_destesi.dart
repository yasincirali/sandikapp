import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/sandik.dart';

/// Sonsuz kart destesi (paywall yeniden tasarımı, yasin 2026-10-08).
///
/// Davranış prototipten birebir (https://claude.ai/artifact/Fwm1QWqhox792DBk32HEPJ):
/// sola da sağa da kaydırınca öndeki kart o yana çıkar, destenin ARKASINA
/// dolanır ve sıradaki öne gelir; geri oku en dipteki kartı aynı yoldan öne
/// getirir. "Destenin sonunu alıyor gibi" — iki yön de ileri sayar, çünkü
/// deste sonsuzdur.
///
/// Akıcılık kuralları (yasin: "kesinlikle kasmaması gerekiyor"):
///  - Kart içerikleri bir kez kurulur ve [RepaintBoundary] içinde kalır;
///    her karede yalnız dönüşüm, opaklık ve karartma katmanı değişir.
///  - Karartma ayrı bir katmanın rengidir (filtre yok; prototipte filtre
///    telefonda kasıyordu).
///  - Yeni dokunuş süren animasyonu beklemez: anında son karesine alınır.
///  - Hareketi azalt açıkken geçiş animasyonsuz atlar; sürükleme parmağı
///    izlemeye devam eder (kullanıcının kendi hareketi).
class KartDestesi extends StatefulWidget {
  const KartDestesi({
    super.key,
    required this.kartlar,
    required this.oncekiEtiketi,
    required this.sonrakiEtiketi,
    required this.ipucu,
    this.kartYuksekligi = 300,
  });

  final List<DesteKarti> kartlar;

  /// Okların ipucu / ekran okuyucu etiketi.
  final String oncekiEtiketi;
  final String sonrakiEtiketi;

  /// Destenin ekran okuyucu ipucu ("kaydırarak geç").
  final String ipucu;

  final double kartYuksekligi;

  @override
  State<KartDestesi> createState() => KartDestesiState();
}

/// Destedeki bir kart: zemin rengi, içerik ve ekran okuyucu metni.
class DesteKarti {
  const DesteKarti({
    required this.zemin,
    required this.child,
    required this.semantik,
  });

  final Color zemin;
  final Widget child;
  final String semantik;
}

/// Bir kartın destedeki görünümü. Saf veri; [desteKonumu] ve geçiş
/// kareleri bunu üretir, widget yalnız uygular.
@immutable
class DestePozu {
  const DestePozu({
    this.x = 0,
    this.y = 0,
    this.olcek = 1,
    this.aci = 0,
    this.opaklik = 1,
    this.karartma = 0,
  });

  final double x;
  final double y;
  final double olcek;

  /// Radyan.
  final double aci;
  final double opaklik;

  /// Üstteki koyu katmanın opaklığı (arkadaki kart sönük görünür).
  final double karartma;

  static DestePozu lerp(DestePozu a, DestePozu b, double t) => DestePozu(
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
        olcek: a.olcek + (b.olcek - a.olcek) * t,
        aci: a.aci + (b.aci - a.aci) * t,
        opaklik: a.opaklik + (b.opaklik - a.opaklik) * t,
        karartma: a.karartma + (b.karartma - a.karartma) * t,
      );
}

/// Saf: öndeki karta [p] uzaklıktaki kartın duruşu. 0 ön, 1–2 arkada
/// görünen, 3 ve ötesi dipte (görünmez). Kesirli [p] sürüklemede ara
/// duruşu verir; 2→3 arası kart solar.
DestePozu desteKonumu(double p) {
  final g = p.clamp(0.0, 3.0);
  return DestePozu(
    y: g * 13,
    olcek: 1 - g * 0.045,
    opaklik: p <= 2 ? 1 : (3 - p).clamp(0.0, 1.0),
    karartma: g * 0.16,
  );
}

const double _derece = math.pi / 180;

/// Saf: sürüklenen öndeki kartın duruşu (parmağı birebir izler).
DestePozu surukluPoz(double dx) =>
    DestePozu(x: dx, y: -dx.abs() * 0.03, aci: dx / 20 * _derece);

/// Saf: öndeki kartın destenin altına dolanması, [o] ∈ [0, 1].
///
/// Kart [taraf] yönüne açılır (±0,66 genişlik, hafif yukarı ve eğik), o
/// noktada destenin ALTINA geçer ([alttaGidenUstte] false olur), sonra
/// ikinci kademenin hemen altından dipteki yerine solar. Destenin yanında
/// geçtiği için katman değişimi göze sıçrama olarak görünmez.
DestePozu alttaGidenPoz(
  double o, {
  required double genislik,
  required int taraf,
  required int kartSayisi,
  DestePozu bas = const DestePozu(),
}) {
  final yan = taraf * genislik * 0.66;
  final ikinci = desteKonumu(math.min(2, kartSayisi - 1).toDouble());
  return _kare(o, const [
    0,
    0.42,
    0.82,
    1
  ], [
    bas,
    DestePozu(x: yan, y: -12, olcek: 0.97, aci: taraf * 8 * _derece),
    DestePozu(
        y: ikinci.y + 8, olcek: ikinci.olcek - 0.02, karartma: ikinci.karartma),
    desteKonumu((kartSayisi - 1).toDouble()),
  ], const [
    SandikMotion.enter,
    SandikMotion.move,
    Curves.easeIn,
  ]);
}

/// Dolanan kart [o] anında destenin üstünde mi.
bool alttaGidenUstte(double o) => o < 0.425;

/// Saf: dipteki kartın ters yoldan öne gelmesi (geri oku), [o] ∈ [0, 1].
/// Dipten belirir, sola açılırken destenin arkasında kalır, açılmanın
/// tepesinde üste geçer ve öne oturur.
DestePozu ustteGelenPoz(
  double o, {
  required double genislik,
  required int kartSayisi,
}) {
  final yan = -genislik * 0.66;
  final ikinci = desteKonumu(math.min(2, kartSayisi - 1).toDouble());
  return _kare(o, const [
    0,
    0.18,
    0.58,
    1
  ], [
    desteKonumu((kartSayisi - 1).toDouble()),
    DestePozu(
        y: ikinci.y + 8, olcek: ikinci.olcek - 0.02, karartma: ikinci.karartma),
    DestePozu(x: yan, y: -12, olcek: 0.97, aci: -8 * _derece),
    const DestePozu(),
  ], const [
    Curves.easeOut,
    SandikMotion.move,
    SandikMotion.enter,
  ]);
}

/// Gelen kart [o] anında destenin üstünde mi.
bool ustteGelenUstte(double o) => o >= 0.575;

DestePozu _kare(
    double o, List<double> anlar, List<DestePozu> pozlar, List<Curve> egriler) {
  for (var i = 0; i < anlar.length - 1; i++) {
    if (o <= anlar[i + 1] || i == anlar.length - 2) {
      final u = ((o - anlar[i]) / (anlar[i + 1] - anlar[i])).clamp(0.0, 1.0);
      return DestePozu.lerp(pozlar[i], pozlar[i + 1], egriler[i].transform(u));
    }
  }
  return pozlar.last;
}

/// Saf: bırakılan sürükleme kartı geçirir mi. Genişliğin %26'sı ya da kısa
/// ama hızlı bir fiske (≥ 500 px/sn ve en az 24 px).
bool suruklemeGecer(double dx, double hiz, double genislik) =>
    dx.abs() > genislik * 0.26 || (hiz.abs() > 500 && dx.abs() > 24);

enum _Gecis { yok, alta, ustte }

class KartDestesiState extends State<KartDestesi>
    with TickerProviderStateMixin {
  int _on = 0;
  double _dx = 0;
  double _genislik = 1;

  _Gecis _tur = _Gecis.yok;
  int _hareketli = -1;
  DestePozu _bas = const DestePozu();

  /// Geçiş başladığında arka kartların sürüklemeyle aldığı yol (0–1);
  /// geçiş oradan devam eder, kartlar geri sıçramaz.
  double _t0 = 0;

  late final AnimationController _gecis =
      AnimationController(vsync: this, duration: SandikMotion.flow)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            setState(() {
              _tur = _Gecis.yok;
              _hareketli = -1;
            });
          }
        });

  late final AnimationController _yay =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() => _dx = _yay.value));

  late List<Widget> _kabuklar = _kabuklariKur();

  /// Öndeki kartın sırası (0'dan).
  int get onIndeks => _on;

  int get _n => widget.kartlar.length;

  @override
  void didUpdateWidget(KartDestesi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.kartlar, widget.kartlar)) {
      _kabuklar = _kabuklariKur();
      if (_on >= _n) _on = 0;
    }
  }

  List<Widget> _kabuklariKur() => [
        for (final k in widget.kartlar)
          RepaintBoundary(child: _KartKabugu(kart: k)),
      ];

  @override
  void dispose() {
    _gecis.dispose();
    _yay.dispose();
    super.dispose();
  }

  bool get _hareketAz => MediaQuery.disableAnimationsOf(context);

  /// Süren geçişi ve yaylanmayı anında bitirir.
  void _bitir() {
    _yay.stop();
    if (_gecis.isAnimating) _gecis.stop();
    _tur = _Gecis.yok;
    _hareketli = -1;
  }

  /// Öndeki kartı destenin altına gönderir; sıradaki öne gelir.
  void ileri() => _alta(-1);

  /// Dipteki kartı öne getirir.
  void geri() {
    if (_n < 2) return;
    setState(() {
      _bitir();
      _dx = 0;
      _on = (_on - 1 + _n) % _n;
      _hareketli = _on;
      _t0 = 0;
      _tur = _hareketAz ? _Gecis.yok : _Gecis.ustte;
    });
    if (_tur != _Gecis.yok) _gecis.forward(from: 0);
  }

  void _alta(int taraf) {
    if (_n < 2) return;
    _yay.stop();
    final dx = _dx;
    setState(() {
      _bitir();
      _bas = surukluPoz(dx);
      _t0 = math.min(1.0, dx.abs() / (_genislik * 0.55));
      _taraf = taraf;
      _dx = 0;
      _hareketli = _on;
      _on = (_on + 1) % _n;
      _tur = _hareketAz ? _Gecis.yok : _Gecis.alta;
    });
    if (_tur != _Gecis.yok) _gecis.forward(from: 0);
  }

  int _taraf = -1;

  void _basla(DragStartDetails _) {
    setState(() {
      _bitir();
      _dx = 0;
    });
  }

  void _surukle(DragUpdateDetails d) {
    if (_n < 2) return;
    setState(() => _dx += d.primaryDelta ?? d.delta.dx);
  }

  void _birak(DragEndDetails d) {
    final hiz = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (suruklemeGecer(_dx, hiz, _genislik)) {
      _alta((_dx.abs() > 4 ? _dx : hiz) < 0 ? -1 : 1);
      return;
    }
    _geriYaylan(hiz);
  }

  void _geriYaylan(double hiz) {
    if (_hareketAz || _dx == 0) {
      setState(() => _dx = 0);
      return;
    }
    _yay.animateWith(SpringSimulation(SandikMotion.yayGeri, _dx, 0, hiz));
  }

  int _uzaklik(int i) => (i - _on + _n) % _n;

  /// Her kartın bu karedeki duruşu ve üstte mi çizileceği.
  (DestePozu, bool) _poz(int i, double o) {
    if (i == _hareketli && _tur == _Gecis.alta) {
      return (
        alttaGidenPoz(o,
            genislik: _genislik, taraf: _taraf, kartSayisi: _n, bas: _bas),
        alttaGidenUstte(o),
      );
    }
    if (i == _hareketli && _tur == _Gecis.ustte) {
      return (
        ustteGelenPoz(o, genislik: _genislik, kartSayisi: _n),
        ustteGelenUstte(o),
      );
    }
    final p = _uzaklik(i).toDouble();
    switch (_tur) {
      case _Gecis.alta:
        // Yeni sırada p; geçiş başında bir kademe gerideydi (eksi
        // sürüklemenin aldığı yol).
        final ilerleme = _t0 + (1 - _t0) * SandikMotion.move.transform(o);
        return (desteKonumu(p + 1 - ilerleme), false);
      case _Gecis.ustte:
        return (desteKonumu(p - 1 + SandikMotion.move.transform(o)), false);
      case _Gecis.yok:
        if (p == 0) return (surukluPoz(_dx), true);
        final t = math.min(1.0, _dx.abs() / (_genislik * 0.55));
        return (desteKonumu(p - t), false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final yukseklik = widget.kartYuksekligi;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          label: _n == 0
              ? null
              : '${widget.kartlar[_on].semantik}, ${_on + 1} / $_n',
          hint: widget.ipucu,
          liveRegion: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _basla,
            onHorizontalDragUpdate: _surukle,
            onHorizontalDragEnd: _birak,
            onHorizontalDragCancel: () => _geriYaylan(0),
            child: LayoutBuilder(builder: (context, k) {
              _genislik =
                  k.maxWidth.isFinite && k.maxWidth > 0 ? k.maxWidth : 1;
              return SizedBox(
                height: yukseklik + 2 * 13 + SandikSpace.sm,
                child: AnimatedBuilder(
                  animation: _gecis,
                  builder: (context, _) => _yigin(yukseklik),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        Row(
          children: [
            IconButton(
              tooltip: widget.oncekiEtiketi,
              onPressed: _n < 2 ? null : geri,
              style: IconButton.styleFrom(
                side: BorderSide(color: c.hairline),
              ),
              icon: Icon(Icons.chevron_left_rounded, color: c.text90),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _n; i++)
                      AnimatedContainer(
                        duration: SandikMotion.stateOf(context),
                        curve: SandikMotion.enter,
                        margin: const EdgeInsets.symmetric(
                            horizontal: SandikSpace.xxs),
                        width: i == _on ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _on ? c.amberFill : c.text20,
                          borderRadius: BorderRadius.circular(SandikSpace.xs),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: widget.sonrakiEtiketi,
              onPressed: _n < 2 ? null : ileri,
              style: IconButton.styleFrom(backgroundColor: c.overlay),
              icon: Icon(Icons.chevron_right_rounded, color: c.text90),
            ),
          ],
        ),
      ],
    );
  }

  Widget _yigin(double yukseklik) {
    final o = _gecis.value;
    final c = context.c;
    final altlar = <(int, DestePozu, double)>[];
    final ustler = <(int, DestePozu, double)>[];
    for (var i = 0; i < _n; i++) {
      final (poz, ustte) = _poz(i, o);
      if (poz.opaklik <= 0.001) continue;
      // Çizim sırası: uzaktaki önce. Dolanan kart altta ise en dipte.
      final derinlik =
          i == _hareketli ? (ustte ? -1.0 : 99.0) : _derinlik(i, o);
      (ustte && i == _hareketli ? ustler : altlar).add((i, poz, derinlik));
    }
    altlar.sort((a, b) => b.$3.compareTo(a.$3));
    final sira = [...altlar, ...ustler];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (i, poz, _) in sira)
          Positioned(
            key: ValueKey(i),
            left: 0,
            right: 0,
            top: 0,
            height: yukseklik,
            child: ExcludeSemantics(
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.translationValues(poz.x, poz.y, 0)
                  ..multiply(Matrix4.rotationZ(poz.aci))
                  ..multiply(Matrix4.diagonal3Values(poz.olcek, poz.olcek, 1)),
                child: Opacity(
                  opacity: poz.opaklik.clamp(0.0, 1.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _kabuklar[i],
                      if (poz.karartma > 0.001)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.golge.withValues(
                                  alpha: poz.karartma.clamp(0.0, 1.0)),
                              borderRadius: _kartKosesi,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _derinlik(int i, double o) {
    final p = _uzaklik(i).toDouble();
    return switch (_tur) {
      _Gecis.alta => p + 1 - (_t0 + (1 - _t0) * o),
      _Gecis.ustte => p - 1 + o,
      _Gecis.yok => p,
    };
  }
}

final BorderRadius _kartKosesi = BorderRadius.circular(SandikSpace.lg);

/// Kartın kabuğu: zemin, köşe, gölge ve iç boşluk. Bir kez kurulur.
class _KartKabugu extends StatelessWidget {
  const _KartKabugu({required this.kart});

  final DesteKarti kart;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kart.zemin,
        borderRadius: _kartKosesi,
        boxShadow: [
          BoxShadow(
            color: context.c.golge.withValues(alpha: 0.30),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(SandikSpace.lgs),
        child: kart.child,
      ),
    );
  }
}
