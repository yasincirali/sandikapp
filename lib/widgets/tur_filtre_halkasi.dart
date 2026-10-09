import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/tur_filtre_ozeti.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Performans › Filtre alt sayfasının kategori seçimi (bayrak `goz_alici`).
///
/// Tasarım kararı (kullanıcı, 2026-10-09): dört yön arasından "Halka" —
/// ilk deneme (sayılı döşeme ızgarası) "sevmedim, daha tasarım öğesi
/// barındıran seçenekler" ile geri çevrildi. Halka seçildi çünkü Portföy
/// ekranındaki tür halkasıyla AYNI dil: kullanıcı onu zaten tanıyor, tür
/// renkleri iki yüzeyde aynı şeyi söylüyor.
///
/// Üç parça:
///   · Halka: elde olan türlerin değer payı. Dilime dokununca o tür seçilir;
///     seçili dilim kalınlaşır, ötekiler söner. Ortada seçili türün payı ve
///     varlık sayısı (seçim yoksa toplam varlık sayısı).
///   · Lejant satırları: Tümü + elde olan türler, sayı ve yüzdeyle. Küçük
///     dilimlere parmakla isabet zor; satır her türe 44pt hedef verir.
///   · "Elinde yok" çipleri: elde olmayan türler de SEÇİLEBİLİR kalır (işlev
///     kaybı yok; eski seçim ya da derin bağlantı yine görünür).
///
/// Fiyatı bilinmeyen portföyde (toplam değer 0) halka çizilmez — uydurma
/// oran yok; satırlar yüzdesiz kalır.
/// Satır sırası enum sırasıdır, paya göre SIRALANMAZ: kişi değişince
/// satırlar yer değiştirseydi parmak yanlış yere giderdi.
class TurFiltreHalkasi extends StatelessWidget {
  const TurFiltreHalkasi({
    super.key,
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onSec,
  });

  final AssetType? secili;
  final TurFiltreOzeti ozet;

  /// Gösterilecek türler (bayrakla kapalı tür çağıranda elenir).
  final List<AssetType> turlar;
  final ValueChanged<AssetType?> onSec;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final eldekiler = [for (final t in turlar) if ((ozet.adet[t] ?? 0) > 0) t];
    final olmayanlar = [for (final t in turlar) if ((ozet.adet[t] ?? 0) == 0) t];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ozet.payVar) ...[
          _Halka(secili: secili, ozet: ozet, turlar: eldekiler, onSec: onSec),
          const SizedBox(height: SandikSpace.sm),
        ],
        _Satir(
          secili: secili == null,
          renk: context.c.amberText,
          ikon: Icons.dashboard_rounded,
          ad: l.allTypes,
          alt: l.s2FiltreVarlikSayisi(ozet.toplamAdet),
          onTap: () => onSec(null),
        ),
        for (final t in eldekiler)
          _Satir(
            secili: secili == t,
            renk: t.onSurface(context),
            nokta: t.color,
            ad: t.labelOf(l),
            alt: l.s2FiltreVarlikSayisi(ozet.adet[t] ?? 0),
            yuzde: ozet.payVar ? fmtPct(ozet.pay(t) * 100, digits: 1) : null,
            onTap: () => onSec(t),
          ),
        if (olmayanlar.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.xs2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.s2FiltreElindeYok,
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text36)),
              for (final t in olmayanlar)
                _YokCipi(
                  tur: t,
                  secili: secili == t,
                  onTap: () => onSec(t),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Halka extends StatelessWidget {
  const _Halka({
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onSec,
  });

  final AssetType? secili;
  final TurFiltreOzeti ozet;
  final List<AssetType> turlar;
  final ValueChanged<AssetType?> onSec;

  static const double _cap = 150;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dilimler = [for (final t in turlar) if (ozet.pay(t) > 0) t];
    final sec = secili;
    final secAdet = sec == null ? 0 : (ozet.adet[sec] ?? 0);
    return SizedBox(
      height: _cap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            swapAnimationDuration: SandikMotion.stateOf(context),
            swapAnimationCurve: SandikMotion.enter,
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              pieTouchData: PieTouchData(
                touchCallback: (event, cevap) {
                  if (event is! FlTapUpEvent) return;
                  final i = cevap?.touchedSection?.touchedSectionIndex;
                  if (i == null || i < 0 || i >= dilimler.length) return;
                  // Seçili dilime ikinci dokunuş Tümü'ne döner — Portföy
                  // halkasıyla aynı davranış.
                  onSec(dilimler[i] == secili ? null : dilimler[i]);
                },
              ),
              sections: [
                for (final t in dilimler)
                  PieChartSectionData(
                    value: ozet.pay(t),
                    color: secili == null || secili == t
                        ? t.color
                        : t.color.withValues(alpha: 0.22),
                    radius: secili == t ? 28 : 22,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          // Ortadaki özet ekran okuyucuya ayrıca okunmaz: aynı bilgi seçili
          // satırın etiketinde var.
          ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: SandikMotion.stateOf(context),
              child: Column(
                key: ValueKey(sec),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sec == null
                        ? '${ozet.toplamAdet}'
                        : fmtPct(ozet.pay(sec) * 100, digits: 1),
                    style: context.t.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: sec == null
                          ? context.c.text90
                          : sec.onSurface(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    sec == null
                        ? l.s2FiltreTumTurler
                        : l.s2FiltreVarlikSayisi(secAdet),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.secili,
    required this.renk,
    required this.ad,
    required this.alt,
    required this.onTap,
    this.nokta,
    this.ikon,
    this.yuzde,
  });

  final bool secili;
  final Color renk;
  final Color? nokta;
  final IconData? ikon;
  final String ad;
  final String alt;
  final String? yuzde;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: [ad, alt, if (yuzde != null) yuzde!].join(', '),
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        height: SandikTouch.min,
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm2),
        decoration: BoxDecoration(
          color: secili ? context.c.overlay : context.c.surface1.withValues(alpha: 0),
          borderRadius: SandikRadius.mdAll,
        ),
        child: Row(
          children: [
            SizedBox(
              width: SandikSpace.md,
              child: Center(
                child: ikon != null
                    ? Icon(ikon, size: 16, color: renk)
                    : Container(
                        width: SandikSpace.sm2,
                        height: SandikSpace.sm2,
                        decoration:
                            BoxDecoration(color: nokta, shape: BoxShape.circle),
                      ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm2),
            Expanded(
              child: Text(ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: secili ? FontWeight.w700 : FontWeight.w600,
                      color: context.c.text90)),
            ),
            Text(alt,
                style: context.t.bodySmall?.copyWith(color: context.c.text58)),
            SizedBox(
              width: SandikSpace.xxl + SandikSpace.sm,
              child: Text(
                yuzde ?? '',
                textAlign: TextAlign.end,
                style: context.t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: renk,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YokCipi extends StatelessWidget {
  const _YokCipi({required this.tur, required this.secili, required this.onTap});
  final AssetType tur;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ad = tur.labelOf(context.l10n);
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: '$ad, ${context.l10n.s2FiltreYok}',
      // Görsel kabuk küçük, dokunma hedefi 44pt (HIG): şeffaf dolgu.
      child: SizedBox(
        height: SandikTouch.min,
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
            decoration: BoxDecoration(
              color: secili ? tur.color.withValues(alpha: 0.14) : null,
              borderRadius: SandikRadius.smAll,
              border: Border.all(
                  color: secili ? tur.color : context.c.hairline),
            ),
            child: Text(ad,
                style: context.t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: secili ? tur.onSurface(context) : context.c.text58)),
          ),
        ),
      ),
    );
  }
}

/// "Bugünkü portföyle" anahtarının küçük çizimi (Filtre sayfası,
/// `goz_alici`): kesik çizgi gerçek geçmiş, düz çizgi bugünkü portföyle
/// çizilen eğri. Açıkken düz çizgi amber.
class BugunkuPortfoyCizimi extends StatelessWidget {
  const BugunkuPortfoyCizimi({super.key, required this.acik});
  final bool acik;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: SandikSpace.xl + SandikSpace.sm2,
        height: SandikSpace.lg,
        child: CustomPaint(
          painter: _CizimRessami(
            kesik: context.c.text36,
            duz: acik ? context.c.amberText : context.c.text58,
          ),
        ),
      );
}

class _CizimRessami extends CustomPainter {
  _CizimRessami({required this.kesik, required this.duz});
  final Color kesik;
  final Color duz;

  @override
  void paint(Canvas canvas, Size s) {
    Offset p(double x, double y) => Offset(x * s.width, y * s.height);
    final gercek = [p(0, .8), p(.28, .6), p(.48, .72), p(.72, .3), p(1, .42)];
    final bugun = [p(0, .62), p(.28, .46), p(.48, .5), p(.72, .18), p(1, .12)];
    final k = Paint()
      ..color = kesik
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < gercek.length - 1; i++) {
      final a = gercek[i], b = gercek[i + 1];
      const adim = 6;
      final n = ((b - a).distance / adim).floor();
      for (var j = 0; j < n; j += 2) {
        canvas.drawLine(Offset.lerp(a, b, j / n)!,
            Offset.lerp(a, b, ((j + 1) / n).clamp(0, 1))!, k);
      }
    }
    final d = Paint()
      ..color = duz
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon(bugun, false), d);
  }

  @override
  bool shouldRepaint(_CizimRessami o) => o.kesik != kesik || o.duz != duz;
}
