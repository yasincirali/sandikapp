import 'package:flutter/material.dart';

import '../models/asset_type.dart';
import '../models/varlik_monogrami.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';

/// Liste satırının başındaki tür noktası; bayrak `goz_alici` açıkken
/// sembolü olan varlıkta (hisse/fon/kripto) sembol rozeti.
///
/// ## Neden (göz alıcılık A+, yasin 2026-10-09)
/// Paket A rozeti Portföy ve hareket satırına koydu; takip listesi ve
/// arama sonuçları hâlâ 8pt tür noktasıyla açılıyordu — aynı ASELS bir
/// ekranda "ASE", ötekinde gri bir nokta. Rozet varlığın her listede aynı
/// yüzü olsun diye tek bileşen.
///
/// ## Kurallar
/// - Bayrak kapalı ya da sembol anlamsız (altın, emtia, endeks…) → birebir
///   eski tür noktası; satır yüksekliği ve hizası değişmez.
/// - Rozet daire, tür rengi zeminde (hareket satırı `_Avatar` ile aynı dil):
///   tür bilgisi renkte kalır, sembol harfte.
/// - Rozet ekran okuyucuya okunmaz: satırın etiketi zaten adı söylüyor.
/// - Varlık sayfası başlığına KONMAZ: orada sembolün tamamı büyük harfle
///   yazılı, "THY" rozeti "THYAO"nun yanında tekrar olurdu.
class VarlikRozeti extends StatelessWidget {
  const VarlikRozeti({super.key, required this.type, required this.ticker});

  final AssetType type;
  final String ticker;

  /// Rozet çapı. 28: Portföy satırı ikon kutusuyla aynı; 44pt satıra
  /// dikey dolgu eklemeden sığar.
  static const double cap = 28;

  @override
  Widget build(BuildContext context) {
    final sembol = RemoteConfigService.instance.gozAlici
        ? varlikMonogrami(type: type, ticker: ticker)
        : null;
    if (sembol == null) {
      return Container(
        width: SandikSpace.sm,
        height: SandikSpace.sm,
        decoration: BoxDecoration(color: type.color, shape: BoxShape.circle),
      );
    }
    return ExcludeSemantics(
      child: Container(
        width: cap,
        height: cap,
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
        child: Center(
          // Büyük yazıda kırpılmasın diye küçülür.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              sembol,
              maxLines: 1,
              style: context.t.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                height: 1,
                color: type.onSurface(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
