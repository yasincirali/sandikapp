import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/tur_filtre_ozeti.dart';
import '../theme/sandik.dart';

/// Performans › Filtre alt sayfasının kategori seçimi (bayrak `goz_alici`).
///
/// Tasarım geçmişi (kullanıcı geri bildirimi, 2026-10-09) — üç tur:
///   1. Sayılı/paylı döşemeler → "sevmedim, daha tasarım öğesi olsun".
///   2. Halka / mozaik / renkli kart / şerit → "hepsi çok göz yoruyor;
///      fonksiyonel basit ama göz dolduran ve SİMETRİK olmalı".
///   3. Bu hâl: sayı, yüzde, çubuk YOK. Her tür aynı boyda bir kare, 3×3
///      eşit ızgara; renk yalnız SEÇİLİ karede yanar. Dolgunluğu kutuların
///      düzeni ve büyük ikon veriyor, bilgi kalabalığı değil.
///
/// Elde olmayan tür sönük (ikon + ad `text36`) ama SEÇİLEBİLİR: işlev kaybı
/// yok, eski seçim/derin bağlantı yine görünür. Sıra enum sırasıdır; kişi
/// değişince kareler yer değiştirmez.
///
/// Simetri: tür sayısı 3'ün katı değilse (ör. `eurobond` açık → 10) artan
/// kareler Tümü'nün satırına geçer, Tümü kalan genişliği alır — ızgara hep
/// tam satırlardan oluşur.
class TurFiltreIzgarasi extends StatelessWidget {
  const TurFiltreIzgarasi({
    super.key,
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onSec,
  });

  final AssetType? secili;
  final TurFiltreOzeti ozet;

  /// Gösterilecek türler (bayrakla kapalı tür çağıranda elenir).
  final List<AssetType> turlar;
  final ValueChanged<AssetType?> onSec;

  static const int _sutun = 3;

  @override
  Widget build(BuildContext context) {
    final artan = turlar.length % _sutun;
    final ust = turlar.sublist(turlar.length - artan);
    final izgara = turlar.sublist(0, turlar.length - artan);
    return LayoutBuilder(builder: (context, k) {
      const ara = SandikSpace.sm;
      final kenar = (k.maxWidth - ara * (_sutun - 1)) / _sutun;
      // Kare biraz yassı (0,82): 3 satır + Tümü, sayfanın alt kısmını
      // (anahtar + düğme) ekrandan itmeden sığsın.
      final boy = kenar * 0.82;
      Widget kare(AssetType t, {bool yatay = false}) => SizedBox(
            width: kenar,
            height: yatay ? SandikTouch.min + SandikSpace.sm : boy,
            child: _Kare(
              tur: t,
              secili: secili == t,
              eldeYok: (ozet.adet[t] ?? 0) == 0,
              yatay: yatay,
              onTap: () => onSec(t),
            ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TumuKutusu(
                    secili: secili == null, onTap: () => onSec(null)),
              ),
              for (final t in ust) ...[
                const SizedBox(width: ara),
                kare(t, yatay: true),
              ],
            ],
          ),
          const SizedBox(height: ara),
          Wrap(
            spacing: ara,
            runSpacing: ara,
            children: [for (final t in izgara) kare(t)],
          ),
        ],
      );
    });
  }
}

/// Seçim kabuğu — Tümü ve kareler aynı kenarı/dolguyu paylaşır.
BoxDecoration _kabuk(BuildContext context,
        {required bool secili, required Color renk}) =>
    BoxDecoration(
      color: secili ? renk.withValues(alpha: 0.12) : context.c.surface2,
      borderRadius: SandikRadius.mdAll,
      border: Border.all(
        color: secili ? renk : context.c.hairline,
        width: secili ? 1.5 : 1,
      ),
    );

class _TumuKutusu extends StatelessWidget {
  const _TumuKutusu({required this.secili, required this.onTap});
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ton = secili ? context.c.amberText : context.c.text58;
    final ad = context.l10n.allTypes;
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: ad,
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        height: SandikTouch.min + SandikSpace.sm,
        decoration: _kabuk(context, secili: secili, renk: context.c.amberFill),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_rounded, size: 18, color: ton),
            const SizedBox(width: SandikSpace.sm),
            Text(ad,
                style: context.t.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600, color: ton)),
          ],
        ),
      ),
    );
  }
}

class _Kare extends StatelessWidget {
  const _Kare({
    required this.tur,
    required this.secili,
    required this.eldeYok,
    required this.onTap,
    this.yatay = false,
  });

  final AssetType tur;
  final bool secili;
  final bool eldeYok;

  /// Tümü satırına geçen artan kare: Tümü'yle aynı boy, ikon + ad yan yana.
  final bool yatay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ad = tur.labelOf(l);
    final ikonRengi = secili ? tur.onSurface(context) : context.c.text58;
    final adRengi = secili ? tur.onSurface(context) : context.c.text90;
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: eldeYok ? '$ad, ${l.s2FiltreYok}' : ad,
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        decoration: _kabuk(context, secili: secili, renk: tur.color),
        // Elde olmayan tür içerikçe sönük (kabuk aynı kalır: ızgara
        // simetrisi bozulmasın); seçiliyse tam parlak.
        child: AnimatedOpacity(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          opacity: eldeYok && !secili ? 0.45 : 1,
          child: Flex(
            direction: yatay ? Axis.horizontal : Axis.vertical,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tur.icon, size: yatay ? 18 : 24, color: ikonRengi),
              SizedBox(
                  width: yatay ? SandikSpace.xs2 : 0,
                  height: yatay ? 0 : SandikSpace.sm),
              Flexible(
                child: Text(ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: adRengi)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
