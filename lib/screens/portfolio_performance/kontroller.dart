part of '../portfolio_performance_screen.dart';

/// Kontroller: tür çipleri, dönem/yüzey/mod anahtarları, boş durumlar.
/// `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
extension _PerformansKontroller on _PortfolioPerformanceScreenState {
  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? context.c.amberText;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        minimumSize: SandikTouch.minSize,
        padding: EdgeInsets.zero,
        onPressed: () => _guncelle(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.15) : context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: selected ? color : context.c.overlay,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : context.c.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_PortfolioPerformanceScreenState._periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: EdgeInsets.zero,
              onPressed: () {
                _guncelle(() => _selectedPeriodIdx = i);
                _startIntradayTickIfNeeded();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    donemEtiketi(context.l10n,
                        _PortfolioPerformanceScreenState._periods[i].label),
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSelected ? context.c.amberText : context.c.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Grafik | Özet yüzey anahtarı.
  ///
  /// `_buildModeToggle` ile aynı kabuk (44px, surface1, SandikRadius.md) —
  /// iki anahtar yan yana durabildiği için aynı görünmek zorundalar, yoksa
  /// kullanıcı ikisini farklı sınıf denetimler sanır.
  ///
  /// Dönem seçici DEĞİŞMEZ: `_selectedPeriodIdx` iki sekmede paylaşılıyor.
  Widget _buildSurfaceToggle() {
    final options = [
      (label: context.l10n.tabChart, ozet: false),
      (label: context.l10n.tabSummary, ozet: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = _ozetSekmesi == o.ozet;
          return Expanded(
            child: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: EdgeInsets.zero,
              onPressed: () {
                if (_ozetSekmesi == o.ozet) return;
                _guncelle(() => _ozetSekmesi = o.ozet);
                if (o.ozet) {
                  AnalyticsService.instance.logPeriodSummaryViewed(
                    period: SummaryPeriod.fromIndex(_selectedPeriodIdx).name,
                  );
                }
              },
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: selected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    o.label,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? context.c.amberText : context.c.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Gerçek geçmiş / Simülasyon toggle'ı.
  /// - Gerçek: her günün o günkü net miktarına göre değer (alım/satışlar
  ///   tarihlerine göre).
  /// - Simülasyon: bugünkü net portföy tüm dönem boyunca elde tutulmuş gibi.
  Widget _buildModeToggle() {
    final options = [
      (label: context.l10n.modeReal, sim: false),
      (label: context.l10n.modeSim, sim: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = _simulate == o.sim;
          return Expanded(
            child: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: EdgeInsets.zero,
              onPressed: () => _guncelle(() => _simulate = o.sim),
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: selected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      o.label,
                      style: context.t.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color:
                            selected ? context.c.amberText : context.c.text36,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: context.l10n.modeInfoSemantics(o.label),
                      child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showModeInfoSheet(forSim: o.sim),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: selected
                              ? context.c.amberFill.withValues(alpha: 0.85)
                              : context.c.text36,
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showModeInfoSheet({required bool forSim}) {
    final title = forSim ? context.l10n.simModeTitle : context.l10n.realModeTitle;
    final body = forSim
        ? context.l10n.simModeBody
        : context.l10n.realModeBody;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => DefaultTextStyle(
        style: sandikFont(
            color: context.c.text90, decoration: TextDecoration.none),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.c.overlay,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: context.c.amberText),
                    const SizedBox(width: 8),
                    Text(title,
                        style: context.t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.text90,
                            decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: context.t.bodyMedium?.copyWith(
                      color: context.c.text58,
                      height: 1.5,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Grafik alanında spinner yerine gösterilecek boş durum — yoksa null.
  ///
  /// Üçü de "veri hiç gelmeyecek" hâli ve üçü de eskiden sonsuz spinner
  /// üretiyordu:
  ///   • portföy tamamen boş (yeni kullanıcı, "Tümü" seçili),
  ///   • seçili türde varlık yok (kullanıcının şikâyet ettiği durum),
  ///   • varlık var ama türün fiyat geçmişi izlenmiyor — mevduat, "Diğer"
  ///     ve elle fiyatlanan fonlar `isRenderable` elemesine takılır, geriye
  ///     çizilecek tek bir varlık kalmaz.
  ///
  /// [holdsSelectedType] NET pozisyona bakar, ham satıra DEĞİL. Ayrım bir
  /// kez ham satırlara dayandırılmıştı ve yanlış mesaj veriyordu: temettü
  /// satırı (miktarsız) ya da satılıp bitmiş bir pozisyon türde "varlık
  /// var" saydırıp, çizilecek bir şey olmadığı için ekranı "grafik verisi
  /// yok"a düşürüyordu — oysa kullanıcının o türden hiçbir şeyi yoktu.
  /// [chartAssets] ise çizilebilir varlıklar; boş olması şart, aksi halde
  /// grafik zaten çizilir.
  Widget? _chartEmptyState(bool holdsSelectedType, List<Asset> chartAssets) {
    if (chartAssets.isNotEmpty) return null;
    final type = _typeFilter;

    if (!holdsSelectedType) {
      return _ChartPlaceholder(
        icon: type?.icon ?? Icons.inbox_rounded,
        iconColor: type?.color,
        title: type == null
            ? context.l10n.noAssetsYetTitle
            : context.l10n.noAssetsOfTypeTitle(
                type.labelOf(context.l10n).toLowerCase()),
        message: type == null
            ? context.l10n.noAssetsChartBody
            : context.l10n.noAssetsOfTypeChartBody,
      );
    }

    // Varlık var ama hiçbirinin fiyat serisi yok (mevduat, "Diğer", elle
    // fiyatlanan fon). Değerleri portföy toplamına dahildir — kullanıcı
    // "varlığım kayboldu" diye okumasın diye bunu açıkça söylüyoruz.
    return _ChartPlaceholder(
      icon: Icons.timeline_rounded,
      iconColor: type?.color,
      title: context.l10n.noChartData,
      message: type == null
          ? context.l10n.noHistoryAllBody
          : context.l10n.noHistoryTypeBody(type.labelOf(context.l10n)),
    );
  }

  /// "Veri alınamadı" durumundaki tekrar dene. Her iki veri yolunu da
  /// sıfırlar: gün içi memoize edilmiş future'ı ve zoom controller'ı.
  void _retryChartData() {
    _guncelle(() {
      _intradayKey = null;
      _intradayFuture = null;
    });
    _zoomController?.reload();
  }
}
