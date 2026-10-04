import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/ilk_varlik_secimi.dart';
import '../theme/sandik.dart';

/// Boş ana ekranda "Ne biriktiriyorsun?" — beş büyük çip (sadeleştirme 2,
/// liste madde 4; bayrak `ilk_varlik_kolay`).
///
/// Değerlendirmedeki bulgu: yeni kullanıcının ilk ekranı Varlık Ekle'nin
/// dokuz tür çipi + arama + miktar + fiyat + üç önizleme + tarih + komisyon
/// formuydu. Bu bileşen soruyu kullanıcının diliyle sorar ("ne
/// biriktiriyorsun"), cevabı formu ön seçimli açmaya çevirir. Kararı çağıran
/// verir ([onSec]): bileşen gezinme bilmez, testte rota kurmadan sınanır.
class IlkVarlikSecici extends StatelessWidget {
  const IlkVarlikSecici({super.key, required this.onSec});

  final ValueChanged<IlkVarlikSecimi> onSec;

  String _etiket(BuildContext context, IlkVarlikSecimi s) => switch (s) {
        IlkVarlikSecimi.gramAltin => context.l10n.firstAssetGoldGram,
        IlkVarlikSecimi.dolar => context.l10n.firstAssetUsd,
        IlkVarlikSecimi.euro => context.l10n.firstAssetEur,
        IlkVarlikSecimi.fon => context.l10n.firstAssetFund,
        IlkVarlikSecimi.hisse => context.l10n.firstAssetStock,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          context.l10n.firstAssetPickTitle,
          textAlign: TextAlign.center,
          style: context.t.titleMedium?.copyWith(
              fontWeight: FontWeight.w700, color: context.c.text90),
        ),
        const SizedBox(height: SandikSpace.xs),
        Text(
          context.l10n.firstAssetPickHint,
          textAlign: TextAlign.center,
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
        const SizedBox(height: SandikSpace.smd),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SandikSpace.sm,
          runSpacing: SandikSpace.sm,
          children: [
            for (final s in IlkVarlikSecimi.values)
              _Cip(
                etiket: _etiket(context, s),
                ikon: s.tur.icon,
                renk: s.tur.color,
                onTap: () => onSec(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _Cip extends StatelessWidget {
  const _Cip({
    required this.etiket,
    required this.ikon,
    required this.renk,
    required this.onTap,
  });

  final String etiket;
  final IconData ikon;
  final Color renk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: etiket,
      excludeSemantics: true,
      child: SandikBasma(
        olcek: 0.95,
        onTap: onTap,
        child: Container(
          // 44pt alt sınır (HIG): çip ilk ekranın birincil eylemi.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md2, vertical: SandikSpace.sm2),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: SandikRadius.mdAll,
            border: Border.all(color: renk.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: 18, color: renk),
              const SizedBox(width: SandikSpace.xs2),
              Text(
                etiket,
                style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600, color: context.c.text90),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
