import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/varlik_kimligi.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'sandik_async_button.dart';

/// Takibe al / takipten çıkar — varlık sayfasıyla portföy varlık detayının
/// ORTAK eylemi.
///
/// Başarı mesajı YOK (kullanıcı kararı, 2026-09-16): düğmenin durumu
/// değişir, onay orada. Takipten çıkarma geri alınabilir ("Geri al"),
/// limit ve ağ hataları mesaj verir — orada geri bildirim tek kanal.
///
/// Varlık sayfasındaydı; detay ekranı da aynı eylemi taşıyınca (2026-09-28
/// A tasarımı) iki kopya "zaten takipte" ve geri alma davranışını
/// ayrıştırırdı. Tek yer burası.
Future<void> takipDegistir(
  BuildContext context,
  WidgetRef ref,
  VarlikKimligi k, {
  required bool takipte,
}) async {
  if (DemoModu.yazmaKapisi('takip')) return; // Demo: takip bir yazma (F1).
  final notifier = ref.read(watchlistProvider.notifier);
  try {
    if (takipte) {
      final kayit = (ref.read(watchlistProvider).valueOrNull ?? const [])
          .where((w) => w.key == k.key)
          .firstOrNull;
      if (kayit == null) return;
      await notifier.remove(kayit.id);
      if (!context.mounted) return;
      sandikSnack(
        context,
        context.l10n.vsRemovedFromWatchlist(k.kisaEtiket),
        onUndo: () => CrashReporter.arkaPlan(
            _takibeAl(context, ref, notifier, k),
            reason: 'takipDegistir.geriAl'),
      );
    } else {
      await _takibeAl(context, ref, notifier, k);
    }
  } catch (e) {
    if (!context.mounted) return;
    sandikSnackError(context, e,
        prefix: takipte ? context.l10n.removeFromWatchlistFailed : null);
  }
}

Future<void> _takibeAl(BuildContext context, WidgetRef ref,
    WatchlistNotifier notifier, VarlikKimligi k) async {
  final user = ref.read(authProvider).valueOrNull;
  if (user == null) return;
  try {
    await notifier.add(k.toWatchlistItem(userId: user.id));
  } on WatchlistLimitException catch (e) {
    if (!context.mounted) return;
    sandikSnack(context, context.l10n.watchlistLimitReached(e.limit),
        kind: SandikSnackKind.warning);
  }
}

/// Üst çubuktaki takip yıldızı (portföy varlık detayı).
///
/// Portföydeki varlıkta yıldız YALNIZCA zaten takipteyse görünür —
/// çıkarabilmek için. Yeni takip önerilmez: portföy ve takip listesi aynı
/// varlığı izler (varlık sayfasının alt çubuğuyla aynı kural).
class TakipYildizi extends ConsumerStatefulWidget {
  const TakipYildizi({super.key, required this.kimlik});

  final VarlikKimligi kimlik;

  @override
  ConsumerState<TakipYildizi> createState() => _TakipYildiziState();
}

class _TakipYildiziState extends ConsumerState<TakipYildizi> {
  @override
  Widget build(BuildContext context) {
    final k = widget.kimlik;
    final takipte = (ref.watch(watchlistProvider).valueOrNull ?? const [])
        .any((w) => w.key == k.key);
    if (!takipte) return const SizedBox.shrink();
    final etiket = context.l10n.vsUnwatchSemantics(k.name);
    // Kilit + gösterge standart bileşende (tek yükleniyor davranışı,
    // 2026-10-08). Eski `_islem` bayrağı `finally`'siz kuruluydu: istek
    // hata verirse yıldız kalıcı olarak pasif kalıyordu. IconButton'un
    // ipucu ve 48pt hedefi korunur.
    return Tooltip(
      message: etiket,
      child: SandikAsyncTap(
        semanticLabel: etiket,
        // Eski IconButton titreşimsizdi.
        haptic: SandikHaptic.none,
        onTap: () => takipDegistir(context, ref, k, takipte: true),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Icon(Icons.star_rounded, color: context.c.gold),
          ),
        ),
      ),
    );
  }
}
