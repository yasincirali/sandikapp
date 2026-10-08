import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../screens/hafta_ozeti_screen.dart';
import '../theme/sandik.dart';

/// Ana ekran, Bugün kartının altında tek satırlık radar şeridi (S7-A,
/// 2026-10-05): "N varlığında bu hafta olağandışı hareket var ›".
///
/// ## Neden şerit, neden kart değil
/// Ana ekranın sorusu "bugün ne oldu"; radar haftalık bir sinyal. Kart
/// ana ekranı uzatır ve her gün aynı şeyi söylerdi. Şerit yalnız SÖYLENECEK
/// bir şey varken çıkar (olağandışı hareket ≥ 1), dokununca Haftanın özeti.
/// Sayı `haftaOlagandisiSayisiProvider`'dan: özet ekranının başlığıyla
/// aynı sayı.
///
/// Bayrak (`balina_radari_acik`) kapalıyken provider sorgu atmaz, 0 döner
/// → şerit hiç yer kaplamaz; ana ekran eski hâliyle birebir.
class RadarSeridi extends ConsumerWidget {
  const RadarSeridi({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sayi = ref.watch(haftaOlagandisiSayisiProvider);
    if (sayi <= 0) return const SizedBox.shrink();
    final c = context.c;
    final t = context.t;
    return Padding(
      padding: padding,
      child: SandikCard(
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.smd),
        onTap: () => pushGuarded(
          context,
          adaptiveRoute<void>(builder: (_) => const HaftaOzetiScreen()),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: SandikTouch.min - 2 * SandikSpace.smd),
          child: Row(
            children: [
              Icon(Icons.radar_rounded,
                  color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Text(
                  context.l10n.rdrSeritSayi('$sayi'),
                  style: t.bodyMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.text36),
            ],
          ),
        ),
      ),
    );
  }
}
