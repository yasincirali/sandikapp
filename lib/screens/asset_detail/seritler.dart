part of '../asset_detail_screen.dart';

/// Dönem değişim satırı, PnL şeridi, overlay çipi, karşılaştırma şeridi,
/// lejant rozeti. `asset_detail_screen.dart`'ın part'ı (2026-09-14).
/// Seçili periyodun değişimi — tek satır, üstteki [_PnlSummaryStrip]'in
/// altında durur.
///
/// İkisi farklı soruları yanıtlar ve bilerek ayrı tutulmuştur:
/// - [_PnlSummaryStrip]: "aldığımdan bugüne ne kazandım?" (toplam PnL)
/// - Bu satır: "seçtiğim dönemde ne oldu?" (dönemsel değişim)
///
/// Değişim ham fiyat farkıdır (son − ilk) × miktar. Grafikteki çizginin iki
/// ucuyla birebir tutarlıdır.
class _PeriodChangeRow extends StatelessWidget {
  /// Değişim TUTARI portföy değeridir → baz para biriminde (3.2).
  final BazPara baz;
  final String label;
  final double changeTRY;
  final double? changePct;

  const _PeriodChangeRow({
    required this.baz,
    required this.label,
    required this.changeTRY,
    required this.changePct,
  });

  @override
  Widget build(BuildContext context) {
    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr — yeşil/kırmızı
    // göstermek "hareket var" yanılgısı yaratır.
    final isFlat =
        changeTRY.abs().round() == 0 && (changePct?.abs() ?? 0) < 0.005;
    final positive = changeTRY >= 0;
    final color =
        isFlat ? context.c.text36 : (positive ? context.c.gain : context.c.loss);
    final tryFmt = baz.formatter(digits: 0);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          // Etiket de kırpılabilmeli: dar ekranda tam genişliği alıp sağdaki
          // tutarı taşırıyordu (320pt'de 54px). Değer zaten Flexible.
          Flexible(
            child: Text(
              context.l10n.periodChangeUpper(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.c.text36,
              ),
            ),
          ),
          const Spacer(),
          if (!isFlat) ...[
            Icon(
              positive
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                isFlat
                    ? 'Değişim yok'
                    : '${positive ? '+' : '−'}${tryFmt.format(changeTRY.abs())}',
                maxLines: 1,
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ),
          if (changePct != null && !isFlat) ...[
            const SizedBox(width: SandikSpace.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: SandikRadius.smAll,
              ),
              child: Text(
                fmtPct(changePct!.abs(), digits: 2),
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PnlSummaryStrip extends StatelessWidget {
  final double anchorUnitPrice;
  final double currentUnitPrice;
  final double pnlPct;
  final double totalPnl;
  final String unitLabel;
  final bool isPositive;

  /// Gösterim birimi (Faz 3.2).
  final BazPara baz;

  const _PnlSummaryStrip({
    required this.baz,
    required this.anchorUnitPrice,
    required this.currentUnitPrice,
    required this.pnlPct,
    required this.totalPnl,
    required this.unitLabel,
    required this.isPositive,
  });

  /// Birim FİYAT ₺ kalır: bir hissenin TL fiyatını dolara çevirmek borsadaki
  /// sayıyla çelişir (bkz. `money_format_scope_test` değer/fiyat ayrımı).
  /// Ondalık korunur ki kullanıcı per-unit farkı algılayabilsin.
  String _fmtPrice(double v) {
    final f = fixedFormatter(2);
    return '${f.format(v)} ₺';
  }

  /// Toplam kâr/zarar bir portföy DEĞERİdir → baz para biriminde.
  String _fmtTotal(double v) => baz.compact(v);

  @override
  Widget build(BuildContext context) {
    // Değişim yoksa (yuvarlanmış tutar ve yüzde ikisi de sıfırsa) nötr göster.
    final bool isFlat =
        totalPnl.abs().round() == 0 && pnlPct.abs() < 0.005;
    final Color accent = isFlat
        ? context.c.text36
        : (isPositive ? context.c.gain : context.c.loss);
    final String sign = isPositive ? '+' : '−';
    final IconData arrow = isPositive
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.8), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.buyPerUnit(unitLabel),
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(anchorUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          color: context.c.text58)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded,
                size: 14, color: context.c.text36),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.todayPerUnit(unitLabel),
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(currentUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.c.text90)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isFlat)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border:
                    Border.all(color: context.c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.horizontal_rule_rounded,
                      size: 14, color: context.c.text58),
                  const SizedBox(width: 4),
                  Text('Değişim yok',
                      style: context.t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text58)),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(arrow, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$sign${_fmtTotal(totalPnl.abs())}',
                          style: context.t.numSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(
                          '$sign${_fmtPrice((currentUnitPrice - anchorUnitPrice).abs())} / $unitLabel',
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.2)),
                      const SizedBox(height: 1),
                      Text(fmtPct(pnlPct.abs(), digits: 2),
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.0)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fullscreen landscape moduna geçiren küçük ikon buton.
/// Grafik üzerine çizilen göstergeleri açıp kapatan küçük toggle chip.
class _OverlayChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OverlayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: AnimatedContainer(
          duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
          curve: SandikMotion.enter,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: active
                  ? context.c.amberFill.withValues(alpha: 0.55)
                  : context.c.overlay,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.check_rounded
                    : Icons.horizontal_rule_rounded,
                size: 12,
                color: active ? context.c.amberText : context.c.text58,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? context.c.amberText : context.c.text58,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grafik container'ının üstünde: legend (rozet) + "Karşılaştır" ekle butonu.
/// Compare seçili değilse sadece + butonu görünür; seçiliyken rozet ve ✕.
class _CompareStrip extends StatelessWidget {
  final String primaryTicker;
  final Asset? compare;
  final VoidCallback onAddPressed;
  final VoidCallback onClearPressed;

  const _CompareStrip({
    required this.primaryTicker,
    required this.compare,
    required this.onAddPressed,
    required this.onClearPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Rozetler + "ekle" düğmesi sabit genişlikte değil: uzun ticker'lar
    // (TEFAS:YKT gibi) veya karşılaştırma rozeti eklenince satır taşıyordu
    // (15px). Yatay kaydırma, rozetleri kırpmadan sığdırır — hiçbir bilgi
    // gizlenmez, yalnızca gerekirse kaydırılır.
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          // Ana varlık rozeti — renk = context.c.amberText
          _LegendBadge(
            color: context.c.amberText,
            label: primaryTicker,
          ),
          const SizedBox(width: 8),
          if (compare != null) ...[
            _LegendBadge(
              color: _kCompareColor,
              label: compare!.ticker,
              onRemove: onClearPressed,
            ),
            const SizedBox(width: 8),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddPressed,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: context.c.overlay,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      compare == null
                          ? Icons.add_rounded
                          : Icons.swap_horiz_rounded,
                      size: 14,
                      color: context.c.text58,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compare == null ? 'Karşılaştır' : 'Değiştir',
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text58,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBadge extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback? onRemove;
  const _LegendBadge({
    required this.color,
    required this.label,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: onRemove == null ? 10 : 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close_rounded, size: 12, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
