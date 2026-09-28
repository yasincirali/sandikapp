import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'sandik_skeleton.dart';

/// Varlık ekranlarının açılış iskeleti — güncel fiyat, grafik, dönem
/// çipleri ve istatistik kartlarının yerini tutar.
///
/// Varlık detayı ile varlık sayfası AYNI iskeleti gösterir (A tasarımı,
/// 2026-09-28: iki ekran aynı düzen). Bloklar gerçek içeriğin ölçüsünde:
/// veri gelince yerleşim zıplamaz, yalnızca dolar
/// (bkz. `utils/acilis_kapisi.dart`).
class VarlikIskeleti extends StatelessWidget {
  const VarlikIskeleti({super.key, this.grafikYuksekligi = 400});

  final double grafikYuksekligi;

  @override
  Widget build(BuildContext context) {
    Widget kart() => Expanded(
          child: Container(
            padding: const EdgeInsets.all(SandikSpace.smd),
            decoration: context.surfaceCard(),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SandikSkeleton(width: 72, height: 10),
                SizedBox(height: SandikSpace.xs),
                SandikSkeleton(width: 56, height: 16),
              ],
            ),
          ),
        );
    return Semantics(
      label: context.l10n.loadingEllipsis,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SandikSkeleton(width: 84, height: 10),
          const SizedBox(height: SandikSpace.xs),
          const SandikSkeleton(width: 168, height: 30),
          const SizedBox(height: SandikSpace.xs),
          const SandikSkeleton(width: 140, height: 12),
          const SizedBox(height: SandikSpace.md),
          SandikSkeleton(height: grafikYuksekligi, radius: SandikRadius.md),
          const SizedBox(height: SandikSpace.sm),
          Row(children: [
            for (var i = 0; i < 6; i++)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
                  child: SandikSkeleton(
                      height: SandikTouch.min, radius: SandikRadius.sm),
                ),
              ),
          ]),
          const SizedBox(height: SandikSpace.md),
          Row(children: [
            kart(),
            const SizedBox(width: SandikSpace.sm),
            kart()
          ]),
          const SizedBox(height: SandikSpace.sm),
          Row(children: [
            kart(),
            const SizedBox(width: SandikSpace.sm),
            kart()
          ]),
        ],
      ),
    );
  }
}
