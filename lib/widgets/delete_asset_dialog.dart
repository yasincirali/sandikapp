import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';

/// "Varlığı sil" onayı + silme — tek yerde.
///
/// Aynı diyalog `portfolio_screen` ve `asset_detail_screen`'de ayrı ayrı
/// yazılmıştı (metin, uyarı kutusu, buton renkleri dahil). Bir tanesinde
/// yapılan düzeltme ötekine taşınmıyordu. Şimdi her iki ekran da bunu
/// çağırır; `true` dönerse silme başarıyla yapılmıştır (çağıran isterse
/// ekranı kapatır).
///
/// [lots] içinde deleteLog izleri OLMAMALI — çağıran
/// `position.lots.where((l) => !l.isDeleteLog)` ile süzer.
Future<bool> confirmAndDeletePosition(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required List<Asset> lots,
}) async {
  final multi = lots.length > 1;
  final ok = await showSandikConfirm(
    context: context,
    title: 'Varlığı Sil',
    message: multi
        ? '"$name" için ${lots.length} işlem kaydı (alım/satım/temettü) '
            'kalıcı olarak silinsin mi?'
        : '"$name" kalıcı olarak silinsin mi?',
    confirmLabel: 'Yine de sil',
    cancelLabel: 'İptal',
    destructive: true,
    detail: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.danger.withValues(alpha: 0.25)),
      ),
      child: Text(
        'Bu bir satış değil — varlık portföyden çıkar, toplamlardan ve '
        'geçmiş grafiğinden düşer. İşlem kayıtları "Portföy Hareketleri"nde '
        'kalır. Sattıysan bunun yerine "Sat" kullan; realize kâr/zararın '
        'hesaba dahil olur.',
        style: context.t.bodySmall?.copyWith(
          height: 1.4,
          color: context.c.text90,
        ),
      ),
    ),
  );
  if (!ok || !context.mounted) return false;
  try {
    final notifier = ref.read(portfolioProvider.notifier);
    final kayit = await notifier.deletePositionLots(lots);
    if (context.mounted) {
      // Geri alma: HIG yıkıcı eylemde geri alma ister; silme yumuşak olduğu
      // için ucuz. Geri alma başarısız olursa sebep söylenir — satırın
      // sessizce gelmemesi hata gibi görünürdü.
      sandikSnack(
        context,
        'Varlık silindi',
        onUndo: kayit == null
            ? null
            : () async {
                try {
                  await notifier.restorePositionLots(kayit);
                } catch (e) {
                  if (context.mounted) {
                    sandikSnackError(context, e, prefix: 'Geri alınamadı');
                  }
                }
              },
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) sandikSnackError(context, e, prefix: 'Silinemedi');
    return false;
  }
}
