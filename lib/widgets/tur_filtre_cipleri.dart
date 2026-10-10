import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/tur_filtre_ozeti.dart';
import '../theme/sandik.dart';

/// Performans › Filtre alt sayfasının kategori seçimi (bayrak `goz_alici`).
///
/// ## Karar (kullanıcı, 2026-10-10 — tasarım tuvalinde "D · Sade çipler")
/// Önceki turlar: sayılı/paylı döşemeler, halka, renkli kartlar ve 3×3
/// ikonlu kare ızgara (PR #140). Kullanıcı: "fazla detay ve karmaşıklığı
/// artırdı; filtre mantığının üstüne çıkmamalı ama fonksiyonel ve anlaşılır,
/// net olmalı." Seçilen hâl:
///   · Yalnız ad: sayı, yüzde, tutar, ikon YOK — filtre ne süzdüğünü söyler,
///     portföyü anlatmaz (o iş Portföy sekmesinin halkasında).
///   · Elde OLAN türler en önde (Tümü'den sonra), değeri büyükten küçüğe;
///     kullanıcının seçeceği şey ilk satırda.
///   · Elde OLMAYAN türler listenin SONUNDA, PASİF: soluk, dokunulmaz
///     ("portföyde olmayanlar pasif şekilde çip listenin sonunda yer
///     alsın"). Boş grafiğe giden seçim baştan kapalı.
///   · Seçili çip amber dolgu + onay işareti; renk tek başına bilgi taşımaz.
///
/// İstisna: seçili tür elde değilse (eski seçim, satılmış pozisyon) çip
/// pasif DEĞİL ve seçili görünür — görünmeyen ya da kaldırılamayan bir
/// filtre olmasın.
class TurFiltreCipleri extends StatelessWidget {
  const TurFiltreCipleri({
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

  /// Çip sırası: elde olanlar değeri büyükten küçüğe (eşitse adet, sonra
  /// enum sırası), ardından elde olmayanlar enum sırasıyla. Saf — test eder.
  static ({List<AssetType> eldeki, List<AssetType> olmayan}) sirala(
      List<AssetType> turlar, TurFiltreOzeti ozet) {
    final eldeki = [
      for (final t in turlar)
        if ((ozet.adet[t] ?? 0) > 0) t,
    ]..sort((a, b) {
        final d = (ozet.deger[b] ?? 0).compareTo(ozet.deger[a] ?? 0);
        if (d != 0) return d;
        final n = (ozet.adet[b] ?? 0).compareTo(ozet.adet[a] ?? 0);
        if (n != 0) return n;
        return a.index.compareTo(b.index);
      });
    final olmayan = [
      for (final t in turlar)
        if ((ozet.adet[t] ?? 0) == 0) t,
    ];
    return (eldeki: eldeki, olmayan: olmayan);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = sirala(turlar, ozet);
    return Wrap(
      spacing: SandikSpace.sm,
      runSpacing: SandikSpace.sm,
      children: [
        _Cip(
          ad: l.allTypes,
          secili: secili == null,
          onTap: () => onSec(null),
        ),
        for (final t in s.eldeki)
          _Cip(
            ad: t.labelOf(l),
            secili: secili == t,
            onTap: () => onSec(t),
          ),
        for (final t in s.olmayan)
          _Cip(
            ad: t.labelOf(l),
            secili: secili == t,
            // Pasif — seçiliyse kaldırılabilsin diye etkin kalır.
            onTap: secili == t ? () => onSec(t) : null,
            pasifEtiket: secili == t ? null : l.s2FiltreYok,
          ),
      ],
    );
  }
}

class _Cip extends StatelessWidget {
  const _Cip({
    required this.ad,
    required this.secili,
    required this.onTap,
    this.pasifEtiket,
  });

  final String ad;
  final bool secili;
  final VoidCallback? onTap;

  /// Doluysa çip pasif (portföyde yok); ekran okuyucuya "Fon, yok" denir.
  final String? pasifEtiket;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pasif = pasifEtiket != null;
    final yazi = secili
        ? c.onAmber
        : pasif
            ? c.text36
            : c.text90;
    final cip = AnimatedContainer(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.enter,
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
      decoration: BoxDecoration(
        // Pasif çip dolgusuz: yalnız çerçeve, zemin sayfanın kendisi.
        color: secili
            ? c.amberFill
            : pasif
                ? null
                : c.surface2,
        borderRadius: BorderRadius.circular(SandikTouch.min / 2),
        border: Border.all(color: secili ? c.amberFill : c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secili) ...[
            Icon(Icons.check_rounded, size: 16, color: yazi),
            const SizedBox(width: SandikSpace.xs2),
          ],
          Text(
            ad,
            style: context.t.titleSmall?.copyWith(
              fontWeight: secili
                  ? FontWeight.w700
                  : pasif
                      ? FontWeight.w500
                      : FontWeight.w600,
              color: yazi,
            ),
          ),
        ],
      ),
    );
    if (pasif) {
      return Semantics(
        label: '$ad, $pasifEtiket',
        button: true,
        enabled: false,
        excludeSemantics: true,
        child: cip,
      );
    }
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: ad,
      child: cip,
    );
  }
}
