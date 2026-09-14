import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Grafik kartının köşesindeki "tam ekran" ikon çipi.
///
/// Performans ve tekil varlık ekranlarında birer kopyası vardı
/// (`_PortfolioFullscreenChip` / `_FullscreenChip`); tek fark kenarlık
/// rengiydi ve o da bilinçli bir ayrım değil, kopyanın sürüklenmesiydi.
/// Tek widget: `hairline` kenarlık (daha yeni olan sürüm).
class ChartFullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const ChartFullscreenChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
          child: Icon(
            Icons.fullscreen_rounded,
            size: 16,
            color: context.c.text58,
          ),
        ),
      ),
    );
  }
}
