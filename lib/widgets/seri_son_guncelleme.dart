import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// "Son güncelleme: …" satırı — grafik eski seriyle KALDIĞINDA.
///
/// ## Neden (Ar-Ge raporu 2026-10-24 §1)
/// Önce-eski-seri yolunda (`HistoryService.eldekiSeriyle`) grafik diskteki
/// son ölçülmüş seriyle soluk açılır, taze seri gelince netleşir. Taze çekim
/// düşerse eski seri ekranda kalır; ama sonsuza dek soluk durursa kullanıcı
/// neden soluk olduğunu bilemez, net çizilip sessiz kalırsa da eski veriyi
/// bugünkü sanır. Bu satır ikisinin arası: seri net çizilir, altında ne
/// zaman ölçüldüğü YAZIYLA söylenir (yalnız renk ya da opaklıkla değil —
/// HIG renk körlüğü maddesi).
///
/// Varlık sayfası ve varlık detay grafiği aynı satırı kullanır.
class SeriSonGuncelleme extends StatelessWidget {
  const SeriSonGuncelleme({super.key, required this.zaman});

  /// Gösterilen serinin ölçüldüğü an.
  final DateTime zaman;

  @override
  Widget build(BuildContext context) {
    final renk = context.c.text58;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.history_rounded, size: 14, color: renk),
          ),
          const SizedBox(width: SandikSpace.xs),
          Flexible(
            child: Text(
              context.l10n.chartLastUpdated(fmtTarihSaat(zaman)),
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: renk),
            ),
          ),
        ],
      ),
    );
  }
}
