import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/bes_sozlesme_pozisyonu.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// BES sözleşmesindeki bir fonun satırı: kod (+ kısa ad), sözleşme içindeki
/// payı, tutarı ve getirisi.
///
/// Tek bileşen iki yerde (2026-10-29): Portföy'deki sözleşme satırının
/// açılır paneli ve varlık sayfasındaki sözleşme kartının "Fon dağılımı"
/// bölümü. İkisi ayrı yazılsaydı biri getiri yüzdesini, öbürü payı farklı
/// yuvarlardı.
///
/// [tutar] biçimlenmiş gelir: Portföy gösterim para birimiyle (`BazPara`),
/// kart TL ile yazar. Getiri yönü metinde de var (`fmtPctIsaretli`), yalnız
/// renkle verilmez.
class BesFonSatiriGorunumu extends StatelessWidget {
  const BesFonSatiriGorunumu({
    super.key,
    required this.satir,
    required this.tutar,
    this.kisaAd,
    this.onTap,
  });

  final BesFonSatiri satir;
  final String tutar;

  /// Fon unvanının kısa hâli ("Altın Katılım"); bilinmiyorsa yalnız kod.
  final String? kisaAd;

  /// Verilirse satır dokunulabilir (Portföy: fonun varlık sayfası).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final getiri = satir.getiriYuzde;
    final pay = fmtPct(satir.oran, digits: 0);
    final altMetin = [
      if (satir.devlet) l10n.pensionGov,
      if (kisaAd != null && kisaAd!.isNotEmpty) kisaAd!,
    ].join(' · ');
    final getiriRengi = getiri == null || getiri.abs() < 0.005
        ? context.c.text58
        : (getiri > 0 ? context.c.gain : context.c.loss);

    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    satir.kod,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AssetType.bes.onSurface(context)),
                  ),
                  if (altMetin.isNotEmpty)
                    Text(
                      altMetin,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tutar,
                    textAlign: TextAlign.end,
                    style: context.t.numSmall.copyWith(
                        fontWeight: FontWeight.w700, color: context.c.text90),
                  ),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: pay,
                          style: TextStyle(color: context.c.text58)),
                      if (getiri != null) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(
                            text: fmtPctIsaretli(getiri, digits: 1),
                            style: TextStyle(color: getiriRengi)),
                      ],
                    ]),
                    textAlign: TextAlign.end,
                    style: context.t.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600, color: context.c.text58),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: SandikSpace.xs),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: context.c.text36),
            ],
          ],
        ),
      ),
    );

    // Ekran okuyucu tek cümle duyar: "AH5, sözleşmenin %60 kadarı, ₺12.000"
    // + getiri; parçalar ayrı ayrı okunmaz.
    final etiket = [
      l10n.pensionFundRowSemantics(satir.kod, pay, tutar),
      if (altMetin.isNotEmpty) altMetin,
      if (getiri != null) fmtPctIsaretli(getiri, digits: 1),
    ].join(', ');
    if (onTap == null) {
      return Semantics(
          label: etiket, excludeSemantics: true, child: govde);
    }
    return SandikTappable(
      onTap: onTap,
      semanticLabel: etiket,
      child: ExcludeSemantics(child: govde),
    );
  }
}
