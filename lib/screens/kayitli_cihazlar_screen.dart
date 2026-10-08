import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/kayitli_cihaz.dart';
import '../providers/cihaz_provider.dart';
import '../services/cihaz_oturumu_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_error_view.dart';

/// Ayarlar › Hesap › Kayıtlı cihazlar (0098).
///
/// E-posta koduyla doğrulanmış cihazlar. Kaldırılan cihaz bir sonraki
/// girişte yeniden kod ister. "Bu cihaz" kaldırılamaz: sunucu da reddeder
/// (`aktif_cihaz_silinemez`) — kendini listeden atan cihaz kod sorulmadan
/// oturumunu sürdürürdü, kaldırmanın anlamı kalmazdı.
class KayitliCihazlarScreen extends ConsumerStatefulWidget {
  const KayitliCihazlarScreen({super.key});

  @override
  ConsumerState<KayitliCihazlarScreen> createState() =>
      _KayitliCihazlarScreenState();
}

class _KayitliCihazlarScreenState extends ConsumerState<KayitliCihazlarScreen> {
  // Eski `_silinen` bayrağı (hangi kart dönüyor + diğer kartları kilitle)
  // 2026-10-08'de kalktı: tek yükleniyor davranışı gereği "Kaldır" düğmesi
  // [SandikAsyncButton]; onay + istek tek Future, gösterge düğmenin içinde.
  // Farklı cihazları art arda kaldırmak zararsız, kartlar arası kilit yok.
  Future<void> _kaldir(KayitliCihaz c) async {
    final l = context.l10n;
    final onay = await showSandikConfirm(
      context: context,
      title: l.cihazKaldirBaslik,
      message: l.cihazKaldirMesaj(c.ad),
      confirmLabel: l.cihazKaldir,
      cancelLabel: l.cancel,
      destructive: true,
    );
    if (!onay || !mounted) return;
    try {
      await CihazOturumuService.instance.sil(c.cihazId);
      ref.invalidate(kayitliCihazlarProvider);
      if (mounted) sandikSnack(context, l.cihazKaldirildi);
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final veri = ref.watch(kayitliCihazlarProvider);
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: context.l10n.kayitliCihazlar),
      body: SafeArea(
        child: veri.when(
          loading: () => const Center(child: CustomLoadingIndicator()),
          error: (e, _) => SandikErrorView(
            error: e,
            onRetry: () => ref.invalidate(kayitliCihazlarProvider),
          ),
          data: (v) => RefreshIndicator.adaptive(
            onRefresh: () => ref.refresh(kayitliCihazlarProvider.future),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: SandikSpace.screenH(context),
                vertical: SandikSpace.md,
              ),
              children: [
                Text(
                  context.l10n.kayitliCihazlarAciklama,
                  style: context.t.bodyMedium?.copyWith(
                    color: context.c.text58,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: SandikSpace.lg),
                if (v.liste.isEmpty)
                  Text(
                    context.l10n.cihazListesiBos,
                    style: context.t.bodyMedium
                        ?.copyWith(color: context.c.text58),
                  ),
                for (final c in v.liste) ...[
                  _CihazKarti(
                    cihaz: c,
                    buCihaz: c.cihazId == v.buCihaz,
                    onKaldir: () => _kaldir(c),
                  ),
                  const SizedBox(height: SandikSpace.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CihazKarti extends StatelessWidget {
  final KayitliCihaz cihaz;
  final bool buCihaz;
  final Future<void> Function() onKaldir;

  const _CihazKarti({
    required this.cihaz,
    required this.buCihaz,
    required this.onKaldir,
  });

  @override
  Widget build(BuildContext context) {
    final tarih = DateFormat('d MMM y, HH:mm', context.tarihDili)
        .format(cihaz.sonGorulme);
    return SandikCard(
      child: Row(
        children: [
          Icon(
            cihaz.platform == 'ios'
                ? Icons.phone_iphone_rounded
                : Icons.phone_android_rounded,
            color: buCihaz ? context.c.amberText : context.c.text58,
          ),
          const SizedBox(width: SandikSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cihaz.ad,
                  style: context.t.titleMedium?.copyWith(
                    color: context.c.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(
                  buCihaz
                      ? context.l10n.buCihaz
                      : context.l10n.cihazSonKullanim(tarih),
                  style: context.t.bodySmall?.copyWith(
                    color: buCihaz ? context.c.amberText : context.c.text58,
                    fontWeight: buCihaz ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
          if (!buCihaz)
            SandikAsyncButton.kompakt(
              tur: SandikAsyncTur.metin,
              onPressed: onKaldir,
              style: TextButton.styleFrom(foregroundColor: context.c.loss),
              child: Text(context.l10n.cihazKaldir),
            ),
        ],
      ),
    );
  }
}
