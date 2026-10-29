import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';

/// Çan sayfasının ortak satır iskeleti — açılır/kapanır (2026-10-29).
///
/// ## Neden (yasin, 2026-10-29: "tüm bildirimler push içinde ve çanda
/// okunabilir olmalı; çandaki liste expandable olabilir")
/// Satıra dokunmak doğrudan varlığa/ekrana gidiyordu; başlık 3, gövde 2
/// satırda kesiliyordu. Çoklu takip listesi bildirimi ("Günlük değişim
/// (önceki kapanışa göre): THYAO +%5,3 ₺312,40 · …") ve brifingin gövdesi
/// hiç tam okunamıyordu. Geçmiş (soluk) satırda tarih GÖVDENİN YERİNE
/// yazılıyordu: kapatılmış bildirimin ne dediği kayboluyordu.
///
/// Şimdi: dokunuş satırı açar/kapar (tam başlık ve gövde, `maxLines` yok);
/// gezinme açık satırdaki "Aç" düğmesine taşındı — okumak isteyen
/// istemeden ekrandan çıkmasın. Soluk satır da gövdeyi gösterir, tarih
/// kendi satırında.
///
/// Üç satır türü (fiyat alarmı, genel bildirim, sinyal) bu iskeleti
/// paylaşır; tür yalnız renk, ikon, rozet ve metni belirler. Eskiden üç
/// kopya vardı (bkz. `PriceAlertTile` notu: "tekrar bilinçli") — tekrar
/// yalnızca iskeletteydi, açılır davranış üç yere ayrı ayrı yazılınca
/// birbirinden kayacaktı.
class BildirimSatiri extends StatefulWidget {
  /// Yön/anlam rengi (alarm: gain/loss, genel: amber, sinyal: al/sat).
  final Color renk;
  final IconData ikon;
  final String baslik;

  /// Kapalıyken başlığın satır sınırı (genel bildirimde 3 — asıl bilgi
  /// başlığın sonunda; alarm/sinyalde varlık adı, 1).
  final int kapaliBaslikSatiri;
  final String rozet;

  /// Gövde; boşsa yazılmaz. Kapalıyken 2 satır.
  final String? govde;

  /// Yalnız AÇIK satırda görünen ek açıklama (ör. alarmın tek seferlik
  /// olduğu). Kapalı satırı kalabalıklaştırmaz.
  final String? ekAciklama;

  /// Zaman satırı ("Bugün 18:25", "28.10.2026 · silindi").
  final String? zaman;
  final bool faded;

  /// Bildirimin varış yeri — açık satırdaki "Aç" düğmesi.
  final VoidCallback onAc;
  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  /// Test ve vitrin için açık başlatma.
  final bool baslangictaAcik;

  const BildirimSatiri({
    super.key,
    required this.renk,
    required this.ikon,
    required this.baslik,
    required this.rozet,
    required this.faded,
    required this.onAc,
    this.kapaliBaslikSatiri = 3,
    this.govde,
    this.ekAciklama,
    this.zaman,
    this.onDismiss,
    this.onDelete,
    this.baslangictaAcik = false,
  });

  @override
  State<BildirimSatiri> createState() => _BildirimSatiriState();
}

class _BildirimSatiriState extends State<BildirimSatiri> {
  late bool _acik = widget.baslangictaAcik;

  void _degistir() {
    SandikHaptic.selection.perform();
    setState(() => _acik = !_acik);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final faded = widget.faded;
    final color = widget.renk;

    // Soluk satırda METİN opaklıkla değil ton basamağıyla iner (HIG denetimi
    // 2026-10-10): %45 opak text58 açık temada 2,1:1 idi. İkon ve zemin
    // (metin dışı) opaklıkla solmaya devam eder.
    final double alphaFactor = faded ? 0.45 : 1.0;
    final double bgAlpha = faded ? 0.05 : 0.10;
    final double borderAlpha = faded ? 0.12 : 0.28;

    final govde = widget.govde?.trim() ?? '';
    final ek = widget.ekAciklama?.trim() ?? '';
    final zaman = widget.zaman;

    final metinSutunu = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                widget.baslik,
                maxLines: _acik ? null : widget.kapaliBaslikSatiri,
                overflow: _acik ? TextOverflow.visible : TextOverflow.ellipsis,
                style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: faded ? context.c.text58 : context.c.text90,
                    decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18 * alphaFactor),
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: Text(widget.rozet,
                  style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: faded ? context.c.text36 : color,
                      decoration: TextDecoration.none)),
            ),
          ],
        ),
        if (govde.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            govde,
            maxLines: _acik ? null : 2,
            overflow: _acik ? TextOverflow.visible : TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(
                color: faded ? context.c.text36 : context.c.text58,
                decoration: TextDecoration.none),
          ),
        ],
        if (_acik && ek.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.xs),
          Text(
            ek,
            style: context.t.bodySmall?.copyWith(
                color: faded ? context.c.text36 : context.c.text58,
                decoration: TextDecoration.none),
          ),
        ],
        // Zaman her satırda, kendi satırında: aynı hisse için "düştü" ve
        // "yükseldi" alt alta duruyordu, hangisinin bugün olduğu
        // anlaşılmıyordu (2026-10-02 müşteri testi). Yanındaki ok satırın
        // açılabildiğini söyler (yalnız renkle/konumla değil, şekille).
        Row(
          children: [
            Expanded(
              child: zaman == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: SandikSpace.xxs),
                      child: Text(
                        zaman,
                        style: context.t.labelSmall?.copyWith(
                            color: context.c.text36,
                            decoration: TextDecoration.none),
                      ),
                    ),
            ),
            AnimatedRotation(
              turns: _acik ? 0.5 : 0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.move,
              child: Icon(Icons.expand_more_rounded,
                  size: 18, color: context.c.text36),
            ),
          ],
        ),
        if (_acik)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: widget.onAc,
              style: TextButton.styleFrom(
                minimumSize: SandikTouch.minSize,
                padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm),
                foregroundColor: faded ? context.c.text58 : context.c.amberText,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(l10n.notifOpenAction),
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      expanded: _acik,
      onTapHint: _acik ? l10n.notifCollapseHint : l10n.notifExpandHint,
      child: SandikBasma(
        onTap: _degistir,
        // Uzun satırda %3 küçülme metni titretir; açılır satır büyük yüzey.
        olcek: 0.98,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: bgAlpha),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
                color: color.withValues(alpha: borderAlpha), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18 * alphaFactor),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.ikon,
                    color: color.withValues(alpha: alphaFactor), size: 20),
              ),
              const SizedBox(width: SandikSpace.md),
              Expanded(
                // Açılış yüksekliği yumuşak; hareketi azalt açıkken anında
                // (`SandikMotion.stateOf` sıfır döner).
                child: AnimatedSize(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.move,
                  alignment: Alignment.topCenter,
                  child: metinSutunu,
                ),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  tooltip: l10n.close,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: context.c.text36),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                )
              else if (widget.onDelete != null)
                IconButton(
                  tooltip: l10n.delete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: context.c.text36),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: SandikTouch.min, minHeight: SandikTouch.min),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
