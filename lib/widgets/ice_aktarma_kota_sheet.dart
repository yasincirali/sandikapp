import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Toplu kayıt öncesi kota seçimi (paywall incelemesi, 2026-10-20).
enum IceAktarmaKotaSecimi { premium, siganlar, vazgec }

/// "N kalem var, M'si sığıyor" — kayıt başlamadan sorulur ki ekstre yarıda
/// kesilip rastgele bir alt küme yazılmasın (gerekçe
/// `iceAktarmaKotaPlani`). Üç yol: Premium'a geçip hepsini ekle (birincil),
/// sığanları kaydet, vazgeç. Kapatma = vazgeç.
class IceAktarmaKotaSheet extends StatelessWidget {
  const IceAktarmaKotaSheet(
      {super.key, required this.bulunan, required this.sigan});

  final int bulunan;
  final int sigan;

  static Future<IceAktarmaKotaSecimi> sor(BuildContext context,
          {required int bulunan, required int sigan}) async =>
      await showSandikSheet<IceAktarmaKotaSecimi>(
        context: context,
        backgroundColor: context.c.surface2,
        shape:
            const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
        builder: (_) => IceAktarmaKotaSheet(bulunan: bulunan, sigan: sigan),
      ) ??
      IceAktarmaKotaSecimi.vazgec;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.md, SandikSpace.screenH(context), SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.lg),
            Icon(Icons.inventory_2_outlined,
                color: c.amberText, size: SandikSpace.xxl),
            const SizedBox(height: SandikSpace.md),
            Text(l.iktKotaBaslik,
                textAlign: TextAlign.center,
                style: t.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(l.iktKotaGovde(bulunan, sigan),
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(SandikTouch.min),
                backgroundColor: c.amberFill,
                foregroundColor: c.onAmber,
              ),
              onPressed: () =>
                  Navigator.of(context).pop(IceAktarmaKotaSecimi.premium),
              child: Text(l.iktKotaPremium),
            ),
            if (sigan > 0) ...[
              const SizedBox(height: SandikSpace.xs),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(SandikTouch.min)),
                onPressed: () =>
                    Navigator.of(context).pop(IceAktarmaKotaSecimi.siganlar),
                child: Text(l.iktKotaSiganlar(sigan)),
              ),
            ],
            const SizedBox(height: SandikSpace.xs),
            TextButton(
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(SandikTouch.min)),
              onPressed: () =>
                  Navigator.of(context).pop(IceAktarmaKotaSecimi.vazgec),
              child: Text(l.iktKotaVazgec),
            ),
          ],
        ),
      ),
    );
  }
}
