import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/kap_baglanti_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';

/// Hisse ekranında "KAP bildirimleri ↗" satırı (karar 7.2, 2026-09-30).
///
/// Uygulama KAP verisi göstermez (lisans, karar 7.1); dokununca varlığın
/// KAP'taki şirket sayfası tarayıcıda açılır.
///
/// ## Neden adres ekran açılırken çözülür (kullanıcı kararı, ikinci tur)
/// "KAP bilgisi olabilecek olanlarda gözükmeli": satır yalnız KAP'ta
/// şirketi KESİN bulunan varlıkta çizilir. Türe bakmak yetmiyor — borsa
/// yatırım fonu (GLDTR) de BIST'te hisse gibi işlem görür ama KAP'ta şirket
/// sayfası yoktur. Bu yüzden ekran açılınca adres bir kez sorulur (oturum
/// önbelleği; ikinci açılışta ilk karede çizilir) ve bulunamazsa satır hiç
/// yer kaplamaz. Altın, döviz, kripto, fon ve endekste sorgu hiç atılmaz.
class KapBaglantisi extends StatefulWidget {
  const KapBaglantisi({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = EdgeInsets.zero,
    this.servis,
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsets dis;

  /// Test için; verilmezse paylaşılan örnek.
  final KapBaglantiService? servis;

  /// KAP'ta sayfası OLABİLECEK varlık mı — sorgu yalnız bunlarda atılır.
  static bool gosterilir(AssetType tur, String ticker) =>
      tur == AssetType.hisse &&
      ticker.toUpperCase().endsWith('.IS') &&
      !bistEndeksiMi(ticker);

  @override
  State<KapBaglantisi> createState() => _KapBaglantisiState();
}

class _KapBaglantisiState extends State<KapBaglantisi> {
  Uri? _adres;

  KapBaglantiService get _servis =>
      widget.servis ?? KapBaglantiService.instance;

  @override
  void initState() {
    super.initState();
    if (!KapBaglantisi.gosterilir(widget.tur, widget.ticker)) return;
    if (_servis.biliniyor(widget.ticker)) {
      _adres = _servis.onbellekte(widget.ticker);
      return;
    }
    _servis.sirketSayfasi(widget.ticker).then((u) {
      if (mounted && u != null) setState(() => _adres = u);
    });
  }

  Future<void> _ac() async {
    final uri = _adres;
    if (uri == null) return;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Tarayıcı yok / eklenti yanıt vermedi: aşağıdaki uyarı yeter;
      // kullanıcı eylemine bağlı, raporlanacak bir arıza değil.
      ok = false;
    }
    if (!ok && mounted) {
      sandikSnack(context, context.l10n.kapLinkFailed,
          kind: SandikSnackKind.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_adres == null) return const SizedBox.shrink();
    final c = context.c;
    return Padding(
      padding: widget.dis,
      child: SandikCard(
        onTap: _ac,
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
            Icon(Icons.open_in_new_rounded, size: 18, color: c.amberText),
          ],
        ),
      ),
    );
  }
}
