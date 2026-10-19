import 'package:flutter/material.dart';

import '../models/asset_type.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Bir portföyün fon DIŞI bir türündeki kırılımı: hangi hisse/kripto/altın,
/// portföyün yüzde kaçı (0158; yasin 2026-10-19: "detaylı varlıkların
/// yüzdelerini anonim ve miktardan bağımsız oransal olarak göstermek").
///
/// Fonların eşi `ZirveFonListesi`; ayrı çünkü fonun adı TEFAS kataloğundan
/// okunur, burada sembolün kendisi addır (`ZirveKiyas.varlikAdi`).
///
/// ## Kilitli satır (vitrin)
/// Premium olmayan kullanıcıya sunucu en büyük tek kalemi açık, gerisini
/// `?1`, `?2`… olarak gönderir (sembol cihaza hiç gelmez). Satır yine
/// çizilir — oran ve çubuk açık, ad yerine "••••" ve kilit — çünkü merakı
/// uyandıran tam da bu: "zirvedeki portföyün %12'si ne?" Dokununca
/// [onKilitli] (paywall). Renk tek başına anlam taşımaz: kilit simgesi ve
/// ekran okuyucu etiketi "Premium'da görünür" der.
class ZirveVarlikListesi extends StatelessWidget {
  const ZirveVarlikListesi({
    super.key,
    required this.tur,
    required this.detay,
    this.onKilitli,
  });

  /// `AssetType.name` (hisse, kripto, altin…).
  final String tur;

  /// {sembol: toplam portföyün %'si}; "DIGER" toplu, `?n` kilitli.
  final Map<String, double> detay;
  final VoidCallback? onKilitli;

  @override
  Widget build(BuildContext context) {
    final satirlar = ZirveKiyas.fonSirali(detay);
    if (satirlar.isEmpty) return const SizedBox.shrink();
    final turToplami = satirlar.fold<double>(0, (s, e) => s + e.pay);
    final renk = AssetType.values
            .where((t) => t.name == tur)
            .firstOrNull
            ?.color ??
        context.c.text36;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in satirlar) ...[
          _satir(context, f.kod, f.pay, turToplami, renk),
          const SizedBox(height: SandikSpace.sm),
        ],
      ],
    );
  }

  Widget _satir(BuildContext context, String kod, double pay,
      double turToplami, Color renk) {
    final diger = kod == ZirveKiyas.fonDiger;
    final kilitli = ZirveKiyas.kilitliMi(kod);
    final yuzde = '%${fmtNum(pay, digits: pay < 10 ? 1 : 0)}';
    final satir = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: SandikSpace.xs2),
              decoration: BoxDecoration(
                color: renk.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: Text(
                diger
                    ? 'DİĞER'
                    : kilitli
                        ? ZirveKiyas.kilitliYer
                        : ZirveKiyas.varlikAdi(kod),
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: context.c.text90,
                ),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: diger
                  ? Text(
                      'Diğerleri (her biri %1 altı ya da sembolsüz)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: context.c.text58,
                      ),
                    )
                  : kilitli
                      ? Row(
                          children: [
                            Icon(Icons.lock_rounded,
                                size: 14, color: context.c.amberText),
                            const SizedBox(width: SandikSpace.xs),
                            Flexible(
                              child: Text(
                                "Premium'da görünür",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.t.labelMedium?.copyWith(
                                  letterSpacing: 0,
                                  color: context.c.amberText,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
            ),
            const SizedBox(width: SandikSpace.sm),
            Text(
              yuzde,
              style: context.t.numSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.text90,
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: Container(
            height: SandikSpace.xs2,
            color: context.c.overlay,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor:
                  turToplami <= 0 ? 0 : (pay / turToplami).clamp(0.0, 1.0),
              child: Container(color: renk),
            ),
          ),
        ),
      ],
    );
    if (!kilitli) {
      return Semantics(
        label: diger
            ? 'Diğerleri $yuzde'
            : '${ZirveKiyas.varlikAdi(kod)} $yuzde',
        excludeSemantics: true,
        child: satir,
      );
    }
    return Semantics(
      button: onKilitli != null,
      label: "Kilitli varlık $yuzde. Premium'da görünür.",
      excludeSemantics: true,
      child: InkWell(
        onTap: onKilitli,
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        child: ConstrainedBox(
          // Dokunma alanı ≥44 pt (HIG); satırın kendisi daha alçak.
          constraints: const BoxConstraints(minHeight: 44),
          child: satir,
        ),
      ),
    );
  }
}
