import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/kur_ayrismasi.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// "Fiyattan +₺X · Kurdan +₺Y" — varlık detayı pozisyon kartında enflasyon
/// satırının altı (Ar-Ge 2026-11-07 #1, Premium). Hesap [kurAyrismasi]'nda.
///
/// ## Görünürlük (temettü "maliyetine göre verim" satırıyla aynı desen, #309)
/// - Premium özellikleri görünmüyorsa (paywall kapalı, admin değil) hiçbir
///   şey çizilmez.
/// - Kilitliyse [KilitSatiri] (kaynak `kur_ayrismasi` → paywall'da X-Ray
///   kartı: "paran gerçekte nerede"). Kilit de ancak hesaplanacak sayı
///   varken çıkar — çağıran [ayrisma] `null` ise bu widget'ı kurmaz;
///   kaydı olmayana "Premium'da kur ayrışman var" demek boş vaat olurdu.
/// - Açıksa iki işaretli tutar. Anlam işarette (+/−) ve kelimede
///   ("Fiyattan/Kurdan"); renk yalnız pekiştirir (HIG renk körlüğü).
///
/// Tutarlar kartın öteki TL tutarları gibi [baz]'dan geçer: bakiye gizliyken
/// `₺••••` yazar, baz birim seçiliyse o birimde. İşaret gizli modda da
/// kalır — kartın "Toplam kâr/zarar" satırı da öyle (`kazancSatiri`).
/// Dokunulmaz; ekran okuyucu tek cümle okur.
class KurAyrismasiSatiri extends ConsumerWidget {
  const KurAyrismasiSatiri(
      {super.key, required this.ayrisma, required this.baz});

  final KurAyrismasi ayrisma;
  final BazPara baz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Padding(
        padding: const EdgeInsets.only(top: SandikSpace.xs),
        child: KilitSatiri(
          metin: l.fxSplitLocked,
          kaynak: 'kur_ayrismasi',
          ozellik: 'kur_ayrismasi',
          kilitEtiketi: l.goalDateLockedLabel,
        ),
      );
    }
    final c = context.c;
    final bicim = baz.formatter(digits: 0);
    String isaretli(double v) {
      if (v.abs().round() == 0) return bicim.format(0);
      return '${v > 0 ? '+' : '−'}${bicim.format(v.abs())}';
    }

    Color renk(double v) => v.abs().round() == 0
        ? c.text58
        : (v > 0 ? c.gain : c.loss);

    final fiyat = isaretli(ayrisma.fiyatEtkisi);
    final kur = isaretli(ayrisma.kurEtkisi);
    final stil = context.t.labelSmall?.copyWith(color: c.text58);
    final vurgu = stil?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Semantics(
        container: true,
        label: l.fxSplitA11y(fiyat, kur),
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.currency_exchange_rounded,
                size: SandikSpace.md, color: c.text58),
            const SizedBox(width: SandikSpace.xs),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: stil,
                  children: [
                    TextSpan(text: '${l.fxSplitPrice} '),
                    TextSpan(
                        text: fiyat,
                        style: vurgu?.copyWith(
                            color: renk(ayrisma.fiyatEtkisi))),
                    TextSpan(text: ' · ${l.fxSplitFx} '),
                    TextSpan(
                        text: kur,
                        style:
                            vurgu?.copyWith(color: renk(ayrisma.kurEtkisi))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
