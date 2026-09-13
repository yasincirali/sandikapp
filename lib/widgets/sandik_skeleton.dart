import 'package:flutter/material.dart';
import '../theme/sandik.dart';

/// İçerik biçimli yükleme yer tutucusu (iskelet).
///
/// 2026-09 denetimi: uygulamada sıfır skeleton, 23 spinner sitesi vardı.
/// Finans panosunda ortada dönen bir halka "bozuk" okunur; içeriğin
/// geleceği yerde soluk bloklar ise "geliyor" der ve yerleşim zıplamaz.
///
/// Hareket: opaklık 0,45 ↔ 0,9 arasında yumuşak nabız. Sistem "hareketi
/// azalt" açıksa nabız YOK — sabit blok (`MediaQuery.disableAnimationsOf`).
/// Shimmer (kayan parlama) bilerek seçilmedi: bir paket daha ve koyu yeşil
/// zeminde amber parlama gürültü yapıyordu.
class SandikSkeleton extends StatefulWidget {
  const SandikSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = SandikRadius.sm,
  });

  /// Tam genişlik için `null`.
  final double? width;
  final double height;
  final double radius;

  @override
  State<SandikSkeleton> createState() => _SandikSkeletonState();
}

class _SandikSkeletonState extends State<SandikSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _alpha =
      Tween<double>(begin: 0.45, end: 0.9).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.5;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.c.hairline;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _alpha,
        builder: (context, _) => Opacity(
          opacity: _alpha.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              // hairline zaten yarı saydam; iki kat üst üste bloğu belirginleştirir.
              color: Color.alphaBlend(color, color.withValues(alpha: 1)),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      ),
    );
  }
}

/// Satır listesi iskeleti — sol ikon, iki satır metin, sağda tutar.
class SandikSkeletonList extends StatelessWidget {
  const SandikSkeletonList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });

  final int rows;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Yükleniyor',
      liveRegion: true,
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: SandikSpace.sm),
        itemBuilder: (_, __) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SandikSpace.md),
      decoration: context.surfaceCard(),
      child: const Row(
        children: [
          SandikSkeleton(width: 40, height: 40, radius: SandikRadius.md),
          SizedBox(width: SandikSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SandikSkeleton(width: 120, height: 14),
                SizedBox(height: SandikSpace.xs),
                SandikSkeleton(width: 72, height: 11),
              ],
            ),
          ),
          SizedBox(width: SandikSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SandikSkeleton(width: 84, height: 14),
              SizedBox(height: SandikSpace.xs),
              SandikSkeleton(width: 48, height: 11),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grafik alanı iskeleti — başlık satırı + gövde + eksen etiketleri.
class SandikSkeletonChart extends StatelessWidget {
  const SandikSkeletonChart({super.key, this.height = 260});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Grafik yükleniyor',
      liveRegion: true,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SandikSkeleton(width: 140, height: 16),
            const SizedBox(height: SandikSpace.sm),
            const Expanded(
              child: SandikSkeleton(height: double.infinity, radius: SandikRadius.md),
            ),
            const SizedBox(height: SandikSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                5,
                (_) => const SandikSkeleton(width: 36, height: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
