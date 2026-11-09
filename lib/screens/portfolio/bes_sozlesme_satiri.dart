part of '../portfolio_screen.dart';

/// Sözleşme satırının başlığı: "MetLife Emeklilik · BES". Kurum önce lot
/// adından, okunamazsa (eski biçimli lot adı) sözleşme kaydının kendi
/// `kurum` alanından gelir; e2e (2026-10-29) eski sözleşmenin satırda yalnız
/// "BES", kartında "BES · Anadolu Hayat" yazdığını gösterdi. İkisi de yoksa
/// yalnız "BES".
String besSozlesmeBasligi(
    BuildContext context, WidgetRef ref, BesSozlesmePozisyonu s,
    {bool izle = true}) {
  final tur = context.l10n.pensionCardTitle;
  // `build` dışından (silme onayı) çağrılınca `watch` değil `read`.
  final durum =
      izle ? ref.watch(sozlesmeProvider) : ref.read(sozlesmeProvider);
  final kayitKurumu = durum.value?.sozlesme(s.sozlesmeId)?.kurum.trim();
  final kurum = s.kurum ??
      (kayitKurumu == null || kayitKurumu.isEmpty ? null : kayitKurumu);
  return kurum == null ? tur : '$kurum · $tur';
}

/// Portföy listesinde BES sözleşmesinin TEK satırı (2026-10-29).
///
/// Satır sözleşmenin toplamını ve kâr/zararını gösterir; ok fon fon dökümü
/// açar (kod, sözleşme içindeki pay, tutar, getiri). Satıra dokunmak en
/// büyük fonun varlık sayfasını açar — sözleşme kartı (fon dağılımı ve
/// "Fon değiştir" dahil) orada; panelde bir fona dokunmak o fonun sayfasını.
///
/// Kaydırma panelinde yalnız Sil var: Al/Sat/Temettü sözleşmede anlamsız
/// (katkı ve fon değişimi sözleşme kartından yapılır), Taşı/Güncelle tek
/// varlık içindir. Sil, sözleşmenin bütün fonlarını tek onayla siler.
class _BesSozlesmeSatiri extends ConsumerStatefulWidget {
  const _BesSozlesmeSatiri({
    super.key,
    required this.sozlesme,
    required this.pState,
    required this.baz,
    required this.canEdit,
    required this.onFonTap,
    required this.onDelete,
  });

  final BesSozlesmePozisyonu sozlesme;
  final PortfolioState pState;
  final BazPara baz;
  final bool canEdit;
  final void Function(Position fon) onFonTap;
  final VoidCallback onDelete;

  @override
  ConsumerState<_BesSozlesmeSatiri> createState() => _BesSozlesmeSatiriState();
}

class _BesSozlesmeSatiriState extends ConsumerState<_BesSozlesmeSatiri> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = widget.sozlesme;
    final pState = widget.pState;
    final a = s.asDisplayAsset();
    final tryFmt = widget.baz.formatter(digits: 0);
    final degerTRY = pState.toTRY(s.totalValue, a.currency);
    final karZararTRY =
        degerTRY - s.totalCostTRY + totalDividendTRY(s.lots);
    final baslik = besSozlesmeBasligi(context, ref, s);
    final alt = [
      l10n.pensionFundCount(s.fonSayisi),
      if (s.devletKatkisiVar) l10n.pensionGov,
    ].join(' · ');
    const kartBoslugu = SandikSpace.sm + 4;

    Widget kart = Container(
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius:
            BorderRadius.circular(widget.canEdit ? 0 : SandikRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikTappable(
            onTap: () => widget.onFonTap(s.enBuyukFon),
            child: Padding(
              padding: const EdgeInsets.all(kartBoslugu),
              child: LayoutBuilder(builder: (context, kisit) {
                final m = _AssetCardMetrics.resolve(kisit.maxWidth);
                // Büyük yazı düzeni `_AssetCard` ile aynı (HIG denetimi
                // 2026-10-10): tutar başlığın altına iner, küçültülmez.
                final buyukYazi = MediaQuery.textScalerOf(context).scale(1) >
                    _ikiSutunMetinOlcegi;
                final tutar = Text(
                  tryFmt.format(degerTRY),
                  maxLines: 1,
                  style: context.t.numMedium.copyWith(
                      fontWeight: FontWeight.w700, color: context.c.text90),
                );
                final karZarar = a.purchasePrice > 0 && a.currentPrice > 0
                    ? _GainLossLine(
                        gainLossTRY: karZararTRY,
                        totalCostTRY: s.totalCostTRY,
                        isPositive: karZararTRY >= 0,
                        tryFmt: tryFmt,
                        olcekle: !buyukYazi,
                      )
                    : null;
                return Row(
                  children: [
                    _AssetLeadingIcon(asset: a),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            baslik,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.text90,
                              height: 1.25,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: SandikSpace.xxs),
                          Text(
                            alt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall
                                ?.copyWith(color: context.c.text36),
                          ),
                          if (buyukYazi) ...[
                            const SizedBox(height: SandikSpace.xs),
                            tutar,
                            if (karZarar != null) ...[
                              const SizedBox(height: SandikSpace.xxs),
                              karZarar,
                            ],
                          ],
                        ],
                      ),
                    ),
                    if (!buyukYazi) ...[
                      const SizedBox(width: SandikSpace.sm),
                      SizedBox(
                        width: m.value,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: tutar,
                            ),
                            if (karZarar != null) ...[
                              const SizedBox(height: SandikSpace.xs),
                              karZarar,
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(width: SandikSpace.xs),
                    _ExpandChevron(
                      expanded: _acik,
                      onTap: () => setState(() => _acik = !_acik),
                    ),
                  ],
                );
              }),
            ),
          ),
          SandikAcilir(
            acik: _acik,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  kartBoslugu, 0, kartBoslugu, kartBoslugu),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                    child: SizedBox(
                        height: 1,
                        child: ColoredBox(color: context.c.hairline)),
                  ),
                  for (final f in s.fonSatirlari)
                    BesFonSatiriGorunumu(
                      satir: f,
                      tutar: tryFmt.format(pState.toTRY(f.deger, a.currency)),
                      onTap: () => widget.onFonTap(f.pozisyon),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.canEdit) {
      kart = ClipRRect(
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Slidable(
          key: ValueKey('bes-sozlesme-${s.sozlesmeId}'),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.28,
            children: [
              _rowAction(
                context,
                onPressed: widget.onDelete,
                background: context.c.danger,
                foreground: context.c.onStatus,
                icon: Icons.delete_outline_rounded,
                label: l10n.deleteAction,
              ),
            ],
          ),
          child: kart,
        ),
      );
      kart = SandikBaglamMenusu(
        baslik: baslik,
        eylemler: [
          SandikBaglamEylemi(
            etiket: l10n.deleteAction,
            ikon: Icons.delete_outline_rounded,
            yikici: true,
            onSec: widget.onDelete,
          ),
        ],
        child: kart,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: kart,
    );
  }
}
