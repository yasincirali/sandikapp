import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../providers/portfoy_provider.dart';
import '../screens/paywall_screen.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';
import 'sandik_segment.dart';

/// "Ne kadarı aktarılsın?" — pozisyon taşımanın miktar adımı (0136).
///
/// ## Neden ayrı adım, neden "Tamamı" varsayılan
/// Taşı bugün pozisyonun tamamını geçmişiyle taşıyor ve Premium değil;
/// kısmi aktarım Premium (yasin 2026-10-10). Varsayılan "Tamamı" olunca
/// ücretsiz kullanıcı için akış eskisiyle aynı kalır (bir dokunuş fazlası),
/// Premium kullanıcı "Bir kısmı"na geçip miktar yazar. Kilitliyken
/// "Bir kısmı" paywall'ı açar, seçim değişmez.
///
/// Kısmi aktarım "klon" değildir: aynı varlık iki portföyde birden SAYILMAZ,
/// toplam değişmez (klon toplamı iki kez sayardı — kullanıcıya bu yüzden
/// önerilmedi).
///
/// [aktar] miktarı alır (tamamı = [toplam]); hata yönetimi çağıranda.
/// Düğme `SandikAsyncButton`: istek bitene kadar sayfa açık kalır.
Future<void> showKismiAktarimSayfasi(
  BuildContext context, {
  required Asset gorunum,
  required double toplam,
  required String hedefAdi,
  required Future<bool> Function(double miktar) aktar,
}) =>
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (_) => KismiAktarimIcerik(
        gorunum: gorunum,
        toplam: toplam,
        hedefAdi: hedefAdi,
        aktar: aktar,
      ),
    );

/// Sayfanın gövdesi — açık sınıf: görsel önizleme testi sayfasız çizer.
class KismiAktarimIcerik extends ConsumerStatefulWidget {
  const KismiAktarimIcerik({
    super.key,
    required this.gorunum,
    required this.toplam,
    required this.hedefAdi,
    required this.aktar,
    this.ilkKismi = false,
  });

  final Asset gorunum;
  final double toplam;
  final String hedefAdi;
  final Future<bool> Function(double miktar) aktar;

  /// Önizleme için "Bir kısmı" açık başlat.
  final bool ilkKismi;

  @override
  ConsumerState<KismiAktarimIcerik> createState() => _KismiAktarimIcerikState();
}

class _KismiAktarimIcerikState extends ConsumerState<KismiAktarimIcerik> {
  late bool _kismi = widget.ilkKismi;
  final _ctrl = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _miktar(double v) =>
      widget.gorunum.miktarMetni(v, (d, n) => fmtNum(d, digits: n));

  /// Kullanıcının yazdığı miktar; geçersizse `null` ve hata yazısı.
  double? _okunan() {
    final v = parseTrNumber(_ctrl.text);
    if (v == null || v <= 0 || v > widget.toplam) {
      setState(() =>
          _hata = context.l10n.portfoyAktarGecersiz(_miktar(widget.toplam)));
      return null;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final kilitli = ref.watch(portfoyPremiumKilitliProvider);
    final hp = SandikSpace.screenH(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp,
            SandikSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(
              l.portfoyAktarBaslik,
              style: context.t.titleLarge?.copyWith(
                  color: context.c.text90, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              l.portfoyAktarAciklama(widget.hedefAdi, _miktar(widget.toplam)),
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            SandikSegment(
              key: const ValueKey('kismi-aktarim-segment'),
              adet: 2,
              secili: _kismi ? 1 : 0,
              onSec: (i) {
                if (i == 1 && kilitli) {
                  PaywallScreen.show(context, source: 'portfoy_kismi_aktar');
                  return;
                }
                setState(() {
                  _kismi = i == 1;
                  _hata = null;
                });
              },
              semantik: (i) => i == 0
                  ? l.portfoyAktarTamami
                  : kilitli
                      ? '${l.portfoyAktarBirKismi}, ${l.portfoyAktarPremium}'
                      : l.portfoyAktarBirKismi,
              oge: (_, i, __) => i == 0
                  ? Text(l.portfoyAktarTamami)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (kilitli) ...[
                          Icon(Icons.lock_outline_rounded,
                              size: 14, color: context.c.text36),
                          const SizedBox(width: SandikSpace.xs),
                        ],
                        Text(l.portfoyAktarBirKismi),
                      ],
                    ),
            ),
            const SizedBox(height: SandikSpace.md),
            if (_kismi) ...[
              TextField(
                key: const ValueKey('kismi-aktarim-miktar'),
                controller: _ctrl,
                autofocus: !widget.ilkKismi,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: context.c.text90),
                onChanged: (_) {
                  if (_hata != null) setState(() => _hata = null);
                },
                decoration: InputDecoration(
                  labelText: l.portfoyAktarMiktar,
                  hintText: _miktar(widget.toplam / 2),
                  errorText: _hata,
                  // Dolgu/çerçeve temadan (`inputDecorationTheme`).
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
              Text(
                l.portfoyAktarNot,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ] else if (kilitli)
              Text(
                l.portfoyAktarPremium,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            const SizedBox(height: SandikSpace.md),
            SandikAsyncButton(
              key: const ValueKey('kismi-aktarim-dugme'),
              onPressed: () async {
                final miktar = _kismi ? _okunan() : widget.toplam;
                if (miktar == null) return;
                final tamam = await widget.aktar(miktar);
                if (tamam && context.mounted) Navigator.pop(context);
              },
              child: Text(l.portfoyAktarDugme),
            ),
          ],
        ),
      ),
    );
  }
}
