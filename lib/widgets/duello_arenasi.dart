import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../services/lider_seridi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import 'yaris_sahnesi.dart';

/// Yarış'ın "Düello arenası" — kullanıcı seçimi 2026-10-04 (artifact
/// seçeneği 2), bayrak `yaris_duello_arena`.
///
/// Kullanıcı: "profesyonel, ilgi çekici, göze hitap edecek, yüksek fps ile
/// animasyonu da tatmin edecek bir ekran… zaten ortakları görüyorsun
/// sadece." Yarışların çoğu iki kişilik (sen ve eşin); iki satırlık liste
/// bu durumda en zayıf biçim. Arena aynı bilgiyi karşılaşma olarak anlatır:
/// iki avatar karşı karşıya, getiriler sayaç gibi akar, fark halat çekme
/// çubuğunda okunur, taç öndekinin başındadır.
///
/// ## Zaman çizelgesi (onaylı prototip `Duello.dc.html` ile birebir)
/// Tek denetleyici, bütün parçalar onun ilerlemesinden [Interval]'la
/// türetilir — ayrı zamanlayıcı yok, kesilince her şey aynı yerden döner:
///   · getiriler  0 → 0,75   [SandikMotion.enter] (sayaç)
///   · halat      0,10 → 0,95 [SandikMotion.elastik]
///   · eski taç   0 → 0,30   küçülür (yalnız lider değiştiyse)
///   · yeni taç   0,62 → 0,87 [SandikMotion.spring] ile belirir, lider
///     değiştiyse yay çizerek zıplar, değişmediyse hafifçe iner
///   · kıvılcım   0,66 → 1    10 parçacık, yalnız giriş ve lider değişimi
///   · cümle      0,90'a kadar "Fark ölçülüyor…"
/// Süre: ilk açılış `flow × 4,6` (~2,6 sn), sonrası `flow × 3` (~1,7 sn).
///
/// ## Kesilebilirlik
/// Yeni değer (dönem değişimi ya da 15 sn'lik canlı yenileme) animasyonun
/// ortasında gelirse kaynak EKRANDAKİ değerdir, hedef değil: sayaç ve halat
/// sıçramadan yeni hedefe döner (Apple "fluid interfaces").
///
/// ## Nadir an
/// Taç gösterisi ve kıvılcım yalnız açılışta, dönem değişince ve lider
/// değişince. Canlı yenilemede lider aynıysa yalnız sayılar akar; ekran her
/// 15 saniyede bir kutlama yapmaz (Emil Kowalski'nin sıklık kuralı).
///
/// ## Kare maliyeti
/// Her karede yalnız dönüşüm/saydamlık ve sayaç metni değişir. Avatar,
/// zemin degradesi ve adlar bir kez kurulur; hareketli her parça kendi
/// `RepaintBoundary`'sinde, `AnimatedBuilder`'ların `child`'ı sabit. Parlama
/// `FadeTransition` (katman saydamlığı), kıvılcım `CustomPainter`
/// (`repaint:` denetleyici — yeniden kurulum yok). Animasyon bitince
/// ticker durur; boşta kare istenmez (`duello_arenasi_test` kanıtlar).
///
/// Hareketi azalt açıkken son hâl doğrudan çizilir, kıvılcım yok.
///
/// Saf widget: provider okumaz, veri parametre.
class DuelloArenasi extends StatefulWidget {
  const DuelloArenasi({
    super.key,
    required this.ben,
    required this.rakip,
    required this.donemGun,
  });

  final YarisKatilimci ben;
  final YarisKatilimci rakip;

  /// Seçili dönem (7 / 30 / 365). Halatın ölçeği buna bağlı; değişmesi
  /// "dönem değişimi" sayılır (taç gösterisi yeniden oynar).
  final int donemGun;

  @override
  State<DuelloArenasi> createState() => _DuelloArenasiState();
}

/// Halatın ölçeği (puan): bu kadar farkta ayrım uca dayanır. Yüzde 1'lik
/// fark haftada büyük, yılda küçüktür — tek ölçek ya haftayı uca yapıştırır
/// ya yılı ortada bırakırdı. Prototipteki değerler.
double arenaOlcegi(int gun) => gun <= 7
    ? 4
    : gun <= 31
        ? 8
        : 20;

/// Halat ayrımının yeri (0..1; 0,5 başa baş, >0,5 sen öndesin). Uçlara
/// yapışmaz (%8): fark pili her zaman iki rengin arasında görünür. Bir
/// tarafın getirisi yoksa ortada.
double arenaHalatOrani(double? ben, double? rakip, int gun) {
  if (ben == null || rakip == null) return 0.5;
  return 0.5 + ((ben - rakip) / (2 * arenaOlcegi(gun))).clamp(-0.42, 0.42);
}

/// Taç kimde: 0 sen, 1 ortak; biri ölçülmediyse kimse (kıyas yok).
int? arenaLideri(double? ben, double? rakip) {
  if (ben == null || rakip == null) return null;
  return ben >= rakip ? 0 : 1;
}

// Zaman çizelgesi (denetleyici ilerlemesinin kesirleri) — bkz. sınıf notu.
const _sayacSon = 0.75;
const _halatBas = 0.1;
const _halatSon = 0.95;
const _eskiTacSon = 0.3;
const _tacBas = 0.62;
const _tacSon = 0.87;
const _kivilcimBas = 0.66;
const _olcumSon = 0.9;

// Ölçüler (prototip, pt) — boşluk ölçeğinden.
const double _avatarCap = SandikSpace.xxl + SandikSpace.lg + SandikSpace.xs;
const double _tacGenislik = SandikSpace.lg + SandikSpace.xs;
const double _tacYukseklik = _tacGenislik * 0.66;
const double _tacZiplama = SandikSpace.lg + SandikSpace.xxs;
const double _kivilcimMenzil = SandikSpace.xxl + SandikSpace.sm;
const double _halatKalinlik = SandikSpace.md + SandikSpace.xxs;
const double _pilYukseklik = SandikSpace.xl + SandikSpace.xs;
const double _pilEnAz = SandikSpace.xl + SandikSpace.sm;
const double _kartKose = SandikRadius.lg + SandikSpace.xs;

class _Deger {
  const _Deger(this.ben, this.rakip, this.halat);
  final double ben;
  final double rakip;
  final double halat;
}

/// Denetleyiciden türetilmiş değer — `FadeTransition`'a tek bir saydamlık
/// akışı vermek için (her karede yeniden kurulum yok).
class _Turev extends Animation<double>
    with AnimationWithParentMixin<double> {
  _Turev(this.parent, this.f);
  @override
  final Animation<double> parent;
  final double Function(double p) f;
  @override
  double get value => f(parent.value);
}

class _DuelloArenasiState extends State<DuelloArenasi>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow * 3)
        ..addListener(_olcumuIzle);

  static const _sayacEgri =
      Interval(0, _sayacSon, curve: SandikMotion.enter);
  static const _halatEgri =
      Interval(_halatBas, _halatSon, curve: SandikMotion.elastik);
  static const _tacEgri = Interval(_tacBas, _tacSon);

  _Deger _kaynak = const _Deger(0, 0, 0.5);
  _Deger _hedef = const _Deger(0, 0, 0.5);

  int? _lider;
  int? _eskiLider;
  bool _degisti = false;

  /// Taç gösterisi bu oynatmada mı (açılış, dönem ya da lider değişimi).
  bool _tacOyna = true;

  /// Kıvılcım bu oynatmada mı (açılış ya da lider değişimi).
  bool _patlat = false;
  bool _basladi = false;

  /// "Fark ölçülüyor…" cümlesi — eşik geçişinde bir kez değişir; cümle her
  /// karede yeniden kurulmaz.
  final ValueNotifier<bool> _olcuyor = ValueNotifier(false);

  late final List<Animation<double>> _parlama = [
    _Turev(_c, (p) => _parlamaDegeri(0, p)),
    _Turev(_c, (p) => _parlamaDegeri(1, p)),
  ];

  _Deger _hedefi(DuelloArenasi w) => _Deger(
        w.ben.roi ?? 0,
        w.rakip.roi ?? 0,
        arenaHalatOrani(w.ben.roi, w.rakip.roi, w.donemGun),
      );

  /// EKRANDAKİ değerler — kesilen animasyon buradan devam eder.
  _Deger get _gorunen {
    final p = _c.value;
    final k = _sayacEgri.transform(p);
    final h = _halatEgri.transform(p);
    return _Deger(
      lerpDouble(_kaynak.ben, _hedef.ben, k)!,
      lerpDouble(_kaynak.rakip, _hedef.rakip, k)!,
      lerpDouble(_kaynak.halat, _hedef.halat, h)!,
    );
  }

  void _olcumuIzle() {
    final v = _tacOyna && _c.value < _olcumSon;
    if (_olcuyor.value != v) _olcuyor.value = v;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    _hedef = _hedefi(widget);
    _lider = arenaLideri(widget.ben.roi, widget.rakip.roi);
    _eskiLider = _lider;
    _degisti = false;
    _tacOyna = true;
    _patlat = _lider != null;
    _oynat(SandikMotion.flow * 4.6);
  }

  @override
  void didUpdateWidget(covariant DuelloArenasi old) {
    super.didUpdateWidget(old);
    final donemDegisti = old.donemGun != widget.donemGun;
    if (!donemDegisti &&
        old.ben.roi == widget.ben.roi &&
        old.rakip.roi == widget.rakip.roi) {
      return;
    }
    _kaynak = _gorunen;
    _hedef = _hedefi(widget);
    final yeni = arenaLideri(widget.ben.roi, widget.rakip.roi);
    _degisti = yeni != _lider;
    _eskiLider = _lider;
    _lider = yeni;
    _tacOyna = donemDegisti || _degisti;
    _patlat = _degisti && yeni != null;
    _oynat(SandikMotion.flow * 3);
  }

  void _oynat(Duration sure) {
    if (MediaQuery.disableAnimationsOf(context)) {
      // Son hâl doğrudan. 0 → 1 iki adımı dinleyicileri (parlama, taç)
      // yeni duruma uyandırır; değer zaten 1 olsa bile. Ticker çalışmaz.
      _patlat = false;
      _c.value = 0;
      _c.value = 1;
      _olcuyor.value = false;
      return;
    }
    _olcuyor.value = _tacOyna;
    _c.duration = sure;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    _olcuyor.dispose();
    super.dispose();
  }

  double _tacQ(double p) => _tacEgri.transform(p);

  /// Tacın ölçeği (0: yok). Lider değiştiyse eski lider küçülür, yenisi
  /// yay ile belirir; değişmediyse ve gösteri yoksa yerinde durur.
  double _tacOlcegi(int i, double p) {
    if (_lider == null) return 0;
    if (i == _lider) {
      return _tacOyna ? SandikMotion.spring.transform(_tacQ(p)) : 1;
    }
    if (_degisti && i == _eskiLider) {
      return 1 - (p / _eskiTacSon).clamp(0.0, 1.0);
    }
    return 0;
  }

  /// Tacın dikey kayması: lider değiştiyse yay (yukarı zıplayıp iner),
  /// değişmediyse hafifçe yukarıdan iner.
  double _tacKaymasi(int i, double p) {
    if (i != _lider || !_tacOyna) return 0;
    final q = _tacQ(p);
    return _degisti
        ? -math.sin(q * math.pi) * _tacZiplama
        : -(1 - q) * SandikSpace.sm;
  }

  /// Liderin avatar parıltısı (saydamlık). Prototipte gölge 8 → 30 pt
  /// büyüyordu; gölge yarıçapını her karede değiştirmek boyamayı
  /// tetikler — burada sabit gölgenin katman saydamlığı akar.
  double _parlamaDegeri(int i, double p) {
    if (_lider == null) return 0;
    if (i == _lider) return _tacOyna ? 0.27 + 0.73 * _tacQ(p) : 1;
    if (_degisti && i == _eskiLider) {
      return 1 - (p / _eskiTacSon).clamp(0.0, 1.0);
    }
    return 0;
  }

  String _cumle(BuildContext context) {
    final l = context.l10n;
    final a = widget.ben.roi, b = widget.rakip.roi;
    if (a == null || b == null) return l.arenaWaiting;
    final fark = a - b;
    if (fark.abs() < basaBasEsigi) return l.duelTied;
    final f = fmtNum(fark.abs(), digits: 1);
    final ad = widget.rakip.kisaAd;
    return fark > 0
        ? l.duelAhead(ad, trIyelik(ad), f)
        : l.arenaBehind(ad, f);
  }

  String _ozet(BuildContext context) {
    final l = context.l10n;
    String getiri(double? v) =>
        v == null ? l.arenaNoDataYet : fmtPctIsaretli(v, digits: 1);
    return '${l.raceYou} ${getiri(widget.ben.roi)} · '
        '${widget.rakip.kisaAd} ${getiri(widget.rakip.roi)}. '
        '${_cumle(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final benRenk = yarisciRengi(context, widget.ben);
    final rakipRenk = yarisciRengi(context, widget.rakip);
    final azalt = MediaQuery.disableAnimationsOf(context);
    // Avatar merkezine hizalı VS rozeti.
    const vsUst = _tacYukseklik +
        SandikSpace.sm +
        _avatarCap / 2 -
        SandikTouch.min / 2;

    return Semantics(
      container: true,
      label: _ozet(context),
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              SandikSpace.md + SandikSpace.xxs,
              SandikSpace.lgs + SandikSpace.xxs,
              SandikSpace.md + SandikSpace.xxs,
              SandikSpace.lgs,
            ),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                colors: [
                  c.surface2,
                  c.surface1,
                  Color.lerp(c.surface1, c.background, 0.5)!,
                ],
                stops: const [0, 0.6, 1],
              ),
              borderRadius: BorderRadius.circular(_kartKose),
              border: Border.all(color: c.hairline),
              boxShadow: c.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _taraf(context, 0, widget.ben,
                          context.l10n.raceYou, benRenk, azalt),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: vsUst),
                      child: _VsRozeti(),
                    ),
                    Expanded(
                      child: _taraf(context, 1, widget.rakip,
                          widget.rakip.kisaAd, rakipRenk, azalt),
                    ),
                  ],
                ),
                const SizedBox(height: SandikSpace.lgs + SandikSpace.xxs),
                _halat(context, rakipRenk),
                const SizedBox(height: SandikSpace.lgs + SandikSpace.xxs),
                ValueListenableBuilder<bool>(
                  valueListenable: _olcuyor,
                  builder: (context, olcuyor, _) {
                    final metin =
                        olcuyor ? context.l10n.arenaMeasuring : _cumle(context);
                    return AnimatedSwitcher(
                      duration: SandikMotion.stateOf(context),
                      switchInCurve: SandikMotion.enter,
                      switchOutCurve: SandikMotion.exit,
                      child: Text(
                        metin,
                        key: ValueKey(metin),
                        textAlign: TextAlign.center,
                        style: context.t.titleMedium?.copyWith(
                          color: c.text58,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _taraf(BuildContext context, int i, YarisKatilimci k, String ad,
      Color renk, bool azalt) {
    final c = context.c;
    final roi = k.roi;
    final sayiStili = context.t.numLarge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _tacYukseklik,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              child: const YarisTaci(genislik: _tacGenislik),
              builder: (_, child) {
                final p = _c.value;
                final s = _tacOlcegi(i, p);
                if (s <= 0) return const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(0, _tacKaymasi(i, p)),
                  child: Transform.scale(
                    scale: s,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        SizedBox.square(
          dimension: _avatarCap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: FadeTransition(
                    opacity: _parlama[i],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: renk.withValues(alpha: 0.55),
                            blurRadius: SandikSpace.xl - SandikSpace.xxs,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: renk, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      k.harf,
                      style: context.t.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: c.onAmber,
                      ),
                    ),
                  ),
                ),
              ),
              if (_patlat && !azalt && i == _lider)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _KivilcimBoyaci(anim: _c, renk: renk),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            ad,
            maxLines: 1,
            softWrap: false,
            style: context.t.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.text90,
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.xxs),
        if (roi == null)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.l10n.arenaNoDataYet,
              maxLines: 1,
              softWrap: false,
              style: context.t.bodyMedium?.copyWith(color: c.text36),
            ),
          )
        else
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final g = _gorunen;
                final v = i == 0 ? g.ben : g.rakip;
                // Renk HEDEFİN işaretinden: sayaç sıfırı geçerken renk
                // titremesin.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    fmtPctIsaretli(v, digits: 1),
                    maxLines: 1,
                    softWrap: false,
                    style: sayiStili.copyWith(
                      color: roi >= 0 ? c.gain : c.loss,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _halat(BuildContext context, Color rakipRenk) {
    final c = context.c;
    final ikisiVar = widget.ben.roi != null && widget.rakip.roi != null;
    return LayoutBuilder(builder: (context, kutu) {
      final w = kutu.maxWidth;
      return SizedBox(
        height: _pilYukseklik,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: (_pilYukseklik - _halatKalinlik) / 2,
              height: _halatKalinlik,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_halatKalinlik / 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: rakipRenk),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _c,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c.amberFill, Sandik.medalGold],
                            ),
                          ),
                        ),
                        builder: (_, child) => Transform(
                          alignment: Alignment.centerLeft,
                          transform: Matrix4.diagonal3Values(
                              math.max(0, _gorunen.halat), 1, 1),
                          child: child,
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 1,
                        color: c.background.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (ikisiVar)
              Positioned(
                left: 0,
                top: 0,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final g = _gorunen;
                      return Transform.translate(
                        offset: Offset((g.halat * w).clamp(0.0, w), 0),
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: _FarkPili(
                            metin: fmtNum((g.ben - g.rakip).abs(), digits: 1),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _VsRozeti extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: SandikTouch.min,
      height: SandikTouch.min,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.background,
        shape: BoxShape.circle,
        border: Border.all(color: c.text90.withValues(alpha: 0.15)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          context.l10n.raceVs,
          style: context.t.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: c.text58,
          ),
        ),
      ),
    );
  }
}

/// Halatın üstündeki fark pili. Zemin temayla TERS (koyuda açık, açıkta
/// koyu): iki rengin ayrım noktasında her temada seçilsin.
class _FarkPili extends StatelessWidget {
  const _FarkPili({required this.metin});
  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: _pilYukseklik,
      constraints: const BoxConstraints(minWidth: _pilEnAz),
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.text90,
        borderRadius: BorderRadius.circular(_pilYukseklik / 2),
        boxShadow: [
          BoxShadow(
            color: c.golge.withValues(alpha: 0.35),
            blurRadius: SandikSpace.md2,
            offset: const Offset(0, SandikSpace.xs),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          metin,
          maxLines: 1,
          style: context.t.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            color: c.background,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Liderin çevresinde 10 parçacıklık kıvılcım halkası. `repaint:`
/// denetleyiciye bağlı: kare başına yalnız bu katman boyanır.
class _KivilcimBoyaci extends CustomPainter {
  _KivilcimBoyaci({required this.anim, required this.renk})
      : super(repaint: anim);

  final Animation<double> anim;
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final t = ((anim.value - _kivilcimBas) / (1 - _kivilcimBas))
        .clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;
    final r = SandikMotion.enter.transform(t) * _kivilcimMenzil;
    final merkez = size.center(Offset.zero);
    final boya = Paint();
    for (var j = 0; j < 10; j++) {
      final a = j / 10 * 2 * math.pi;
      boya.color =
          (j.isOdd ? Sandik.medalGold : renk).withValues(alpha: 1 - t);
      canvas.drawCircle(
        merkez + Offset(math.cos(a) * r, math.sin(a) * r),
        SandikSpace.xs2 / 2,
        boya,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KivilcimBoyaci old) =>
      old.anim != anim || old.renk != renk;
}

// ── Lider şeridi ────────────────────────────────────────────────────────────

/// Dönemin her günü (yılda her ay) kimin önde olduğu — renkli dikey
/// çubuklar soldan sağa dalga gibi dolar, üstte "… kez yer değişti".
///
/// Veri `LiderSeridi` (servis katmanı, `lider_seridi.dart`): sıralamanın
/// kendi gün gün birikimi, iki kişi aynı anlarda. Ölçülmeyen gün sönük çizgi
/// — uydurulmaz. Dalga yalnız şerit ilk göründüğünde ve dönem değişince
/// oynar; canlı yenilemede çubuklar yerinde güncellenir.
class LiderSeridiKarti extends StatefulWidget {
  const LiderSeridiKarti({
    super.key,
    required this.serit,
    required this.benRengi,
    required this.rakipRengi,
  });

  final LiderSeridi serit;
  final Color benRengi;
  final Color rakipRengi;

  @override
  State<LiderSeridiKarti> createState() => _LiderSeridiKartiState();
}

class _LiderSeridiKartiState extends State<LiderSeridiKarti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow * 3);
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    _oynat();
  }

  @override
  void didUpdateWidget(covariant LiderSeridiKarti old) {
    super.didUpdateWidget(old);
    if (old.serit.donemGun != widget.serit.donemGun) _oynat();
  }

  void _oynat() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final s = widget.serit;
    final bas = DateFormat(s.aylik ? 'MMM y' : 'd MMM', context.tarihDili)
        .format(s.baslangic);
    final baslik = s.aylik ? l.arenaStripMonthly : l.arenaStripDaily;
    final degisim = l.arenaSwaps(s.yerDegisimi);
    final kucuk = context.t.titleSmall?.copyWith(color: c.text58);
    return Semantics(
      container: true,
      label: '$baslik · $degisim',
      child: ExcludeSemantics(
        child: SandikCard(
          radius: SandikRadius.md + SandikSpace.xs,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md, vertical: SandikSpace.md2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(baslik,
                        maxLines: 2, style: kucuk),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  Expanded(
                    child: Text(
                      degisim,
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      style: kucuk?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.sm2),
              SizedBox(
                height: SandikSpace.lgs + SandikSpace.xxs,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SeritBoyaci(
                      anim: _c,
                      cubuklar: s.cubuklar,
                      renkler: {
                        SeritLider.ben: widget.benRengi,
                        SeritLider.rakip: widget.rakipRengi,
                        SeritLider.berabere: c.text36,
                        SeritLider.bilinmiyor: c.text20,
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SandikSpace.xs2),
              // Uçlar: büyük yazıda kırpılmaz, küçülür (metin tam okunur).
              Row(
                children: [
                  for (final (metin, hiza) in [
                    (bas, Alignment.centerLeft),
                    (l.todayWord, Alignment.centerRight),
                  ])
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: hiza,
                        child: Text(
                          metin,
                          maxLines: 1,
                          softWrap: false,
                          style:
                              context.t.bodySmall?.copyWith(color: c.text36),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeritBoyaci extends CustomPainter {
  _SeritBoyaci({
    required this.anim,
    required this.cubuklar,
    required this.renkler,
  }) : super(repaint: anim);

  final Animation<double> anim;
  final List<SeritLider> cubuklar;
  final Map<SeritLider, Color> renkler;

  @override
  void paint(Canvas canvas, Size size) {
    final n = cubuklar.length;
    if (n == 0) return;
    const ara = SandikSpace.xxs;
    final w = (size.width - ara * (n - 1)) / n;
    if (w <= 0) return;
    final p = anim.value;
    final boya = Paint();
    for (var i = 0; i < n; i++) {
      // Dalga: her çubuk sırası gelince 0'dan dolar (prototip formülü).
      final q = ((p * 1.3 - i / n) * 4).clamp(0.0, 1.0);
      final olcek = 0.2 + 0.8 * SandikMotion.spring.transform(q);
      final h = size.height * olcek;
      final x = i * (w + ara);
      final renk = renkler[cubuklar[i]]!;
      boya.color = renk.withValues(alpha: renk.a * (0.25 + 0.75 * q));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          const Radius.circular(SandikSpace.xs - 1),
        ),
        boya,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeritBoyaci old) =>
      old.anim != anim ||
      !identical(old.cubuklar, cubuklar) ||
      old.renkler.length != renkler.length ||
      old.renkler.entries.any((e) => renkler[e.key] != e.value);
}
