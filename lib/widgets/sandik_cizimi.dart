import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Sandık çiziminin üzerinde durduğu zemin; renkler buna göre seçilir.
enum SandikZemini {
  /// Dolu amber blok (paywall başlığı). Gövde koyu, şeritler altın —
  /// #118'deki ilk çizimin renkleri birebir.
  amber,

  /// Uygulamanın olağan yüzeyi (`background`/`surface1`). Koyu gövde koyu
  /// zeminde kaybolurdu; gövde amber, şerit ve kilit koyu.
  yuzey,
}

/// sandık'ın kendi çizimi: kapaklı bir kasa, içinden dört çubuk yükselir.
///
/// ## Neden ortak bileşen (göz alıcılık C, yasin 2026-10-09)
/// Çizim yalnız paywall'daydı (#118, yasin'in en sevdiği ekran). Boş
/// ekranlar düz bir ikon, kilometre taşı sayfası düz bir rozet gösteriyordu;
/// uygulamanın adı "sandık" ama sandığın kendisi görünmüyordu. Tek çizim,
/// her yerde aynı karakter.
///
/// ## Kurallar
/// - [acik] `false` → kapalı kasa, çubuk yok (boş durum: "henüz bir şey
///   yok"). `true` → ilk çizimde kapak bir kez açılır, çubuklar yükselir
///   (paywall, kilometre taşı: "kasana bir şey eklendi").
/// - [dokunulabilir] → dokununca açılır/kapanır (paywall'daki oyuncak).
/// - Süslemedir: ekran okuyucuya görünmez; anlam yanındaki metindedir.
/// - "Hareketi azalt" açıkken son hâli doğrudan çizilir.
/// - Zamanlayıcı yok: gecikme [Interval] ile (testte bekleyen Timer kalmaz).
/// - Boyut [olcek] ile; çizim 130×140 tasarım kutusunda tanımlıdır.
class SandikCizimi extends StatefulWidget {
  const SandikCizimi({
    super.key,
    this.zemin = SandikZemini.amber,
    this.acik = true,
    this.dokunulabilir = true,
    this.olcek = 1,
  });

  final SandikZemini zemin;
  final bool acik;
  final bool dokunulabilir;
  final double olcek;

  /// Tasarım kutusu (pt, [olcek] 1'de).
  static const Size tasarimBoyutu = Size(130, 140);

  @override
  State<SandikCizimi> createState() => _SandikCizimiState();
}

class _SandikCizimiState extends State<SandikCizimi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: SandikMotion.flow + SandikMotion.modal);
  bool _basladi = false;

  static const _yukseklikler = [30.0, 52.0, 40.0, 70.0];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (!widget.acik) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _dokun() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = _c.value > 0.5 ? 0 : 1;
    } else if (_c.value > 0.5) {
      _c.reverse();
    } else {
      _c.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color govde;
    final Color serit;
    final Color kapak;
    final Color cubukA;
    final Color cubukB;
    switch (widget.zemin) {
      case SandikZemini.amber:
        const d = SandikPalette.dark;
        const a = SandikPalette.light;
        govde = context.c.onAmber;
        serit = d.gold;
        kapak = d.surface2;
        cubukA = a.background;
        cubukB = a.surface2;
      case SandikZemini.yuzey:
        govde = context.c.amberFill;
        serit = context.c.onAmber.withValues(alpha: 0.35);
        kapak = context.c.amberText;
        cubukA = context.c.gold;
        cubukB = context.c.text58;
    }
    final kapakEgri = CurvedAnimation(
        parent: _c, curve: const Interval(0.36, 1, curve: SandikMotion.spring));
    final cizim = SizedBox(
      width: SandikCizimi.tasarimBoyutu.width,
      height: SandikCizimi.tasarimBoyutu.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            // Çubuklar sandığın ağzından yükselir.
            Positioned(
              left: 27,
              bottom: 58,
              width: 76,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 13,
                      height: _yukseklikler[i] *
                          Interval(0.45 + i * 0.09, 1,
                                  curve: SandikMotion.spring)
                              .transform(_c.value)
                              .clamp(0.0, 1.2),
                      decoration: BoxDecoration(
                        color: i.isEven ? cubukA : cubukB,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(SandikSpace.xs)),
                      ),
                    ),
                ],
              ),
            ),
            // Gövde: iki şerit ve kilit.
            Positioned(
              left: 4,
              bottom: 0,
              width: 122,
              height: 62,
              child: Container(
                decoration: BoxDecoration(
                  color: govde,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(SandikSpace.xs),
                      bottom: Radius.circular(SandikSpace.md2)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                        left: 22,
                        top: 0,
                        bottom: 0,
                        width: 10,
                        child: ColoredBox(color: serit)),
                    Positioned(
                        right: 22,
                        top: 0,
                        bottom: 0,
                        width: 10,
                        child: ColoredBox(color: serit)),
                    Positioned(
                      left: 49,
                      top: 11,
                      width: 24,
                      height: 28,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: serit,
                          borderRadius:
                              BorderRadius.circular(SandikSpace.xs2 + 1),
                        ),
                        child: Container(
                          width: 6,
                          height: 11,
                          decoration: BoxDecoration(
                            color: govde,
                            borderRadius:
                                BorderRadius.circular(SandikSpace.xxs + 1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Kapak: sol alt köşesinden geriye yatar.
            Positioned(
              left: 0,
              bottom: 58,
              width: 130,
              height: 28,
              child: Transform.rotate(
                alignment: Alignment.bottomLeft,
                angle: -26 * math.pi / 180 * kapakEgri.value,
                child: Container(
                  decoration: BoxDecoration(
                    color: kapak,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(SandikSpace.md2),
                        bottom: Radius.circular(SandikSpace.xs)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                          left: 22,
                          top: 0,
                          bottom: 0,
                          width: 10,
                          child: ColoredBox(color: serit)),
                      Positioned(
                          right: 22,
                          top: 0,
                          bottom: 0,
                          width: 10,
                          child: ColoredBox(color: serit)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final olcekli = widget.olcek == 1
        ? cizim
        : SizedBox(
            width: SandikCizimi.tasarimBoyutu.width * widget.olcek,
            height: SandikCizimi.tasarimBoyutu.height * widget.olcek,
            child: FittedBox(child: cizim),
          );
    return ExcludeSemantics(
      child: widget.dokunulabilir
          ? GestureDetector(onTap: _dokun, child: olcekli)
          : olcekli,
    );
  }
}
