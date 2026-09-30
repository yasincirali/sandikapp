import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/kap_baglanti_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'custom_loading_indicator.dart';

/// Hisse ekranında "KAP bildirimleri ↗" satırı (karar 7.2, 2026-09-30).
///
/// Uygulama KAP verisi göstermez (lisans, karar 7.1); şirketin KAP
/// sayfasını tarayıcıda açar. Adres `KapBaglantiService`'te çözülür —
/// yalnız BIST hissesinde çizilir; endeks (XU100) ve BIST dışı sembolde
/// yok (KAP'ta sayfası yoktur).
class KapBaglantisi extends StatefulWidget {
  const KapBaglantisi({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = EdgeInsets.zero,
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsets dis;

  /// Satır bu varlıkta çizilir mi — ekranın kendi koşulu da bu.
  static bool gosterilir(AssetType tur, String ticker) =>
      tur == AssetType.hisse &&
      ticker.toUpperCase().endsWith('.IS') &&
      !bistEndeksiMi(ticker);

  @override
  State<KapBaglantisi> createState() => _KapBaglantisiState();
}

class _KapBaglantisiState extends State<KapBaglantisi> {
  bool _aciliyor = false;

  Future<void> _ac() async {
    if (_aciliyor) return; // çift dokunuş iki sekme açmasın
    setState(() => _aciliyor = true);
    final uri = await KapBaglantiService.instance.sirketSayfasi(widget.ticker);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Tarayıcı yok / eklenti yanıt vermedi: aşağıdaki uyarı yeter;
      // kullanıcı eylemine bağlı, raporlanacak bir arıza değil.
      ok = false;
    }
    if (!mounted) return;
    setState(() => _aciliyor = false);
    if (!ok) {
      sandikSnack(context, context.l10n.kapLinkFailed,
          kind: SandikSnackKind.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!KapBaglantisi.gosterilir(widget.tur, widget.ticker)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    return Padding(
      padding: widget.dis,
      child: SandikCard(
        onTap: _aciliyor ? null : _ac,
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.md, vertical: SandikSpace.smd),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined, size: 20, color: c.text58),
            const SizedBox(width: SandikSpace.smd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.kapLinkLabel,
                      style: context.t.bodyLarge?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w600)),
                  const SizedBox(height: SandikSpace.xs2),
                  Text(context.l10n.kapLinkHint,
                      style: context.t.bodySmall?.copyWith(color: c.text58)),
                ],
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            if (_aciliyor)
              const CustomLoadingIndicator(size: 18)
            else
              Icon(Icons.open_in_new_rounded, size: 18, color: c.amberText),
          ],
        ),
      ),
    );
  }
}
