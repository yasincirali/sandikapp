import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/bekleyen_fon_alimi_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/tr_format.dart';
import 'sandik_async_button.dart';

/// "Fiyat yarın kesinleşir" — tutarla bugün alınan fonun adedi dünkü
/// fiyatla hesaplandı, alım gününün TEFAS fiyatı henüz yok (Ar-Ge 7 Kas
/// 14:30 #1). `FonFiyatGunuEtiketi`'nin yanında; bekleyen alım yoksa yer
/// kaplamaz. Renk gri (bilgi, uyarı değil); anlam metinde.
class BekleyenFonAlimiEtiketi extends ConsumerWidget {
  const BekleyenFonAlimiEtiketi({
    super.key,
    required this.lotIdleri,
    this.onEk = '· ',
    this.stil,
  });

  /// Pozisyonun lot kimlikleri.
  final Iterable<String> lotIdleri;

  /// Etiket bir başka etiketin yanındaysa ayraç; kendi satırındaysa ''.
  final String onEk;
  final TextStyle? stil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = pozisyonFonAlimDurumu(
        ref.watch(fonAlimDurumlariProvider), lotIdleri);
    if (d is! FonAlimBekliyor) return const SizedBox.shrink();
    final metin = context.l10n.fonFiyatYarinKesinlesir;
    return Text(
      '$onEk$metin',
      key: const ValueKey('fonFiyatYarinKesinlesir'),
      maxLines: 2,
      semanticsLabel: metin,
      style: stil ??
          context.t.labelSmall?.copyWith(color: context.c.text36),
    );
  }
}

/// Alım gününün fiyatı geldi: "Yeni fiyatla adet 1.234,56 olur · Güncelle".
///
/// Tek dokunuş, sessiz düzeltme yok. Güncelle mevcut lot güncelleme yolunu
/// kullanır (adet = tutar ÷ yeni fiyat, birim maliyet yeni fiyat, toplam
/// tutar aynı); "Yok say" işareti siler. Büyük yazıda `Wrap` ile alt satıra
/// sarar, kırpılmaz.
class FonAlimOneriSatiri extends ConsumerWidget {
  const FonAlimOneriSatiri({super.key, required this.lotIdleri});

  final Iterable<String> lotIdleri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = pozisyonFonAlimDurumu(
        ref.watch(fonAlimDurumlariProvider), lotIdleri);
    if (d is! FonAlimOnerisi) return const SizedBox.shrink();
    final l = context.l10n;
    final adet = qtyFormatter(maxDigits: 4).format(d.adet);
    final notifier = ref.read(bekleyenFonAlimlariProvider.notifier);
    return Padding(
      key: const ValueKey('fonAlimOnerisi'),
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SandikSpace.xs,
        children: [
          ExcludeSemantics(
            child: Text(
              l.fonAlimOneri(adet),
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
          Semantics(
            label: l.fonAlimOneriSemantik(adet),
            button: true,
            excludeSemantics: true,
            child: SandikAsyncButton.kompakt(
              tur: SandikAsyncTur.metin,
              onPressed: () async {
                try {
                  await notifier.uygula(d.lotId);
                } catch (e, st) {
                  CrashReporter.report(e, st,
                      reason: 'FonAlimOneriSatiri.uygula');
                  if (context.mounted) showAppError(context, e);
                }
              },
              child: Text(l.update),
            ),
          ),
          IconButton(
            tooltip: l.fonAlimYokSay,
            constraints: const BoxConstraints(
                minWidth: SandikTouch.min, minHeight: SandikTouch.min),
            icon: Icon(Icons.close_rounded,
                size: 18, color: context.c.text36),
            onPressed: () => notifier.kaldir(d.lotId),
          ),
        ],
      ),
    );
  }
}
