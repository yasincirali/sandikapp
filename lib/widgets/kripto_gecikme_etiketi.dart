import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/kripto_fiyat.dart';
import '../services/price_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Kripto fiyatı bayatsa "Gecikmeli · son güncelleme …" satırı; taze ya da
/// bilinmiyorsa HİÇBİR ŞEY çizmez.
///
/// Neden gerekli (2026-09-25, "tamamen Binance" kararı): yedek sağlayıcı
/// yok. Binance yanıt vermezse `kripto_fiyat` son değerde kalır; fiyat yine
/// ölçülmüş bir sayıdır ama 7/24 işleyen piyasada 10 dakikadan eski fiyatı
/// "şimdiki" gibi göstermek yanıltır. Eşik `KriptoFiyat.bayatlikEsigi`,
/// sunucudaki alarm eşiğiyle aynı (`KRIPTO_BAYATLIK_MS`).
class KriptoGecikmeEtiketi extends StatelessWidget {
  const KriptoGecikmeEtiketi({super.key, required this.sembol, this.simdi});

  final String sembol;

  /// Test için sabit saat.
  final DateTime? simdi;

  @override
  Widget build(BuildContext context) {
    final zaman = PriceService.instance.kriptoGuncellenme(sembol);
    if (zaman == null) return const SizedBox.shrink();
    final an = simdi ?? DateTime.now();
    if (an.difference(zaman) <= KriptoFiyat.bayatlikEsigi) {
      return const SizedBox.shrink();
    }
    final metin = fmtTarihSaat(zaman);
    return Semantics(
      label: context.l10n.priceDelayedSemantics(metin),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: context.c.amberText),
            const SizedBox(width: SandikSpace.xs),
            Expanded(
              child: Text(
                '${context.l10n.priceDelayed} · $metin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(color: context.c.amberText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
