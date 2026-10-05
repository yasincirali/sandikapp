import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/premium_provider.dart';
import '../theme/sandik.dart';

/// Erken kullanıcı hediyesi (S13-A, 2026-10-05) — bir kez açılan sayfa.
///
/// Hediye sunucuda verilir (0116 `erken_kullanici_hediyesi_ver`, paywall
/// açılırken bir kez elle çalıştırılır). Kullanıcı bunu SÖYLENMEDEN
/// görürse "neden birden Premium oldum, ne zaman para kesilecek" diye
/// sorar; sayfa üç şeyi tek cümlede cevaplar: kaç gün, ne zaman biter,
/// bitince ne olur (hiçbir veri silinmez) — ve kart istenmediğini.
class PremiumHediyeSayfasi extends StatelessWidget {
  const PremiumHediyeSayfasi(
      {super.key, required this.hak, required this.simdi});

  final PremiumHakki hak;
  final DateTime simdi;

  static Future<void> goster(BuildContext context, PremiumHakki hak) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.c.surface2,
        isScrollControlled: true,
        shape:
            const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
        builder: (_) => PremiumHediyeSayfasi(hak: hak, simdi: DateTime.now()),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final bitis = hak.bitis!.toLocal();
    // Kalan gün yukarı yuvarlanır: bugün biten hediye "0 gün" demesin.
    final gun = (bitis.difference(simdi).inHours / 24).ceil().clamp(1, 9999);
    final tarih =
        DateFormat('d MMMM y', Localizations.localeOf(context).toString())
            .format(bitis);
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
            Icon(Icons.card_giftcard_rounded,
                color: c.amberText, size: SandikSpace.xxl),
            const SizedBox(height: SandikSpace.md),
            Text(l10n.prmHediyeBaslik,
                textAlign: TextAlign.center,
                style: t.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(l10n.prmHediyeGovde('$gun', tarih),
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(SandikTouch.min),
                backgroundColor: c.amberFill,
                foregroundColor: c.onAmber,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.prmTesekkurler),
            ),
          ],
        ),
      ),
    );
  }
}
