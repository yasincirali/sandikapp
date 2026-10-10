import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/portfoy.dart';
import '../providers/base_currency_provider.dart';
import '../providers/portfoy_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../widgets/portfoy_secici.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_async_button.dart';

/// Portföy yönetimi (çoklu portföy, 0133): oluştur, yeniden adlandır,
/// sırala, sil.
///
/// "Ana" bir satır değildir (`portfoy_id IS NULL`); listenin başında sabit
/// durur, adı ve yeri değişmez, silinemez — silinen her portföyün lotları
/// oraya döner. Silme lotları SİLMEZ (FK `on delete set null`), onay
/// sayfası kaç kaydın Ana'ya döneceğini söyler. Değerler
/// `portfoyOzetleriProvider`'dan (hesap build'de değil).
class PortfoyYonetimiScreen extends ConsumerWidget {
  const PortfoyYonetimiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
    final ozet = ref.watch(portfoyOzetleriProvider);
    final baz = ref.watch(gosterimBazParaProvider);
    final hp = SandikSpace.screenH(context);

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(title: l.portfoyYonetimiBaslik),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, 0),
              child: Text(
                l.portfoyYonetimiAciklama,
                style: context.t.bodyMedium?.copyWith(color: context.c.text58),
              ),
            ),
            const SizedBox(height: SandikSpace.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: _Satir(
                key: const ValueKey('portfoy-satir-ana'),
                ad: l.portfoyAnaUzun,
                alt: l.portfoyAnaAciklama,
                deger: baz.fmt(ozet[null]?.deger ?? 0),
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
            if (liste.length > 1)
              Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.xs),
                child: Text(
                  l.portfoySiralaIpucu,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.lg),
                itemCount: liste.length,
                // Sürükleme tutamacı satırın kendisi (uzun basış): ayrı bir
                // tutamaç ikonu dar ekranda adı kısaltırdı.
                buildDefaultDragHandles: true,
                onReorderItem: (eski, yeni) {
                  final ids = [for (final p in liste) p.id];
                  ids.insert(yeni, ids.removeAt(eski));
                  CrashReporter.arkaPlan(
                    ref
                        .read(portfoylerProvider.notifier)
                        .sirala(ids)
                        .catchError((Object e) {
                      if (context.mounted) {
                        sandikSnackError(context, e,
                            prefix: l.portfoyKaydedilemedi);
                      }
                    }),
                    reason: 'portfoyYonetimi.sirala',
                  );
                },
                itemBuilder: (context, i) {
                  final p = liste[i];
                  return Padding(
                    key: ValueKey('portfoy-satir-${p.id}'),
                    padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                    child: _Satir(
                      ad: p.ad,
                      deger: baz.fmt(ozet[p.id]?.deger ?? 0),
                      onYenidenAdlandir: () => showPortfoyAdiSayfasi(
                        context,
                        baslik: l.portfoyYenidenAdlandir,
                        dugme: l.save,
                        baslangic: p.ad,
                        kaydet: (ad) => ref
                            .read(portfoylerProvider.notifier)
                            .yenidenAdlandir(p.id, ad),
                      ),
                      onSil: () =>
                          _silOnayi(context, ref, p, ozet[p.id]?.kayit ?? 0),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.md),
              child: FilledButton.icon(
                key: const ValueKey('portfoy-yeni-dugmesi'),
                onPressed: () => CrashReporter.arkaPlan(
                    yeniPortfoyAkisi(context, ref, sec: false),
                    reason: 'portfoyYonetimi.yeni'),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.portfoyYeni),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Silme onayı alt sayfada (`showSandikSheet`): sonucu (lotlar Ana'ya
  /// döner, toplam değişmez) okuyup karar verilsin. Silme düğmenin İÇİNDE
  /// koşar; hata sayfanın üstünde söylenir.
  Future<void> _silOnayi(
    BuildContext context,
    WidgetRef ref,
    Portfoy p,
    int kayit,
  ) async {
    final l = context.l10n;
    final silindi = await showSandikSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(ctx), SandikSpace.md,
              SandikSpace.screenH(ctx), SandikSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SandikTutamac()),
              const SizedBox(height: SandikSpace.md),
              Text(
                l.portfoySilBaslik(p.ad),
                style: ctx.t.titleLarge?.copyWith(
                    color: ctx.c.text90, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SandikSpace.sm),
              Text(
                l.portfoySilAciklama(kayit),
                style: ctx.t.bodyMedium?.copyWith(color: ctx.c.text58),
              ),
              const SizedBox(height: SandikSpace.lg),
              SandikAsyncButton.kompakt(
                key: const ValueKey('portfoy-sil-onay'),
                style: FilledButton.styleFrom(
                  backgroundColor: ctx.c.danger,
                  foregroundColor: ctx.c.onStatus,
                ),
                onPressed: () async {
                  try {
                    await ref.read(portfoylerProvider.notifier).sil(p.id);
                  } catch (e, st) {
                    CrashReporter.report(e, st, reason: 'portfoyYonetimi.sil');
                    if (ctx.mounted) {
                      sandikSnackError(ctx, e, prefix: l.portfoySilinemedi);
                    }
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(l.portfoySil,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel),
              ),
            ],
          ),
        ),
      ),
    );
    if (silindi == true && context.mounted) {
      sandikSnack(context, l.portfoySilindi(p.ad),
          kind: SandikSnackKind.success);
    }
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    super.key,
    required this.ad,
    required this.deger,
    this.alt,
    this.onYenidenAdlandir,
    this.onSil,
  });

  final String ad;
  final String deger;
  final String? alt;
  final VoidCallback? onYenidenAdlandir;
  final VoidCallback? onSil;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SandikCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad,
                  style: context.t.titleSmall?.copyWith(
                      color: context.c.text90, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  deger,
                  style:
                      context.t.bodyMedium?.copyWith(color: context.c.text58),
                ),
                if (alt != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    alt!,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ],
              ],
            ),
          ),
          if (onYenidenAdlandir != null)
            IconButton(
              tooltip: l.portfoyYenidenAdlandir,
              constraints: const BoxConstraints(
                  minWidth: SandikTouch.min, minHeight: SandikTouch.min),
              onPressed: onYenidenAdlandir,
              icon: Icon(Icons.edit_outlined, color: context.c.text58),
            ),
          if (onSil != null)
            IconButton(
              tooltip: l.portfoySil,
              constraints: const BoxConstraints(
                  minWidth: SandikTouch.min, minHeight: SandikTouch.min),
              onPressed: onSil,
              icon: Icon(Icons.delete_outline_rounded, color: context.c.danger),
            ),
        ],
      ),
    );
  }
}
