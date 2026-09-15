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

  /// Kapsam + yüzey çubuğu — ekranın kalıcı İLK kontrol satırı.
  ///
  /// ## Neden tek satır (2026-09-15)
  /// Bu ekranda beş kontrol satırı üst üste duruyordu: ortak seçici, tür
  /// çipleri, Grafik/Özet, dönem ve grafik araçları. 390pt'lik bir telefonda
  /// grafik ekranın %60'ından sonra başlıyordu — kullanıcı bildirimi: "tab
  /// seçimleri karma karışık ve ekranda çok yer kaplıyor".
  ///
  /// Ayrım KULLANIM SIKLIĞINA göre yapıldı, göze göre değil:
  ///   · sık: yüzey (Grafik/Özet) ve dönem → kalıcı satırlarda kaldı
  ///   · seyrek: kim, hangi tür, hangi mod → tek çipin arkasına alındı
  ///
  /// Çip bunları GİZLEMEZ: seçili kapsamı her zaman yazar ("Birlikte · Fon ·
  /// Simülasyon"). Bir filtrenin açık olduğunu görmek için paneli açmak
  /// gerekmez — "neden portföyüm eksik görünüyor" sınıfı hatanın kaynağı
  /// tam olarak görünmeyen filtredir.
  Widget _buildScopeBar(List<AppUser> activePartners) {
    return Row(
      children: [
        // İkisi de esnek ve eşit: yüzey anahtarı sabit genişlik alsaydı dar
        // ekranda kapsam çipine üç nokta bile sığmıyordu.
        Expanded(child: _buildSurfaceToggle()),
        const SizedBox(width: SandikSpace.sm),
        Expanded(child: _buildScopeChip(activePartners)),
      ],
    );
  }

  /// Kapsamın tek satırlık özeti: "kim · tür · mod".
  ///
  /// Ortak yoksa "kim" yazılmaz — ortağı olmayan kullanıcıya "Birlikte"
  /// demek anlamsız. Mod yalnızca simülasyondayken yazılır: varsayılan
  /// (Gerçek) her çipte tekrar edilecek bir bilgi değil.
  String _kapsamOzeti(List<AppUser> activePartners) {
    final l = context.l10n;
    final parcalar = <String>[
      if (activePartners.isNotEmpty)
        if (_view == null)
          l.scopeTogether
        else if (_view == '')
          l.scopeMe
        else
          activePartners
              .firstWhere((p) => p.id == _view,
                  orElse: () => activePartners.first)
              .displayName
              .split(' ')
              .first,
      _typeFilter == null ? l.allTypes : _typeFilter!.labelOf(l),
      if (_simulate) l.modeSim,
    ];
    return parcalar.join(' · ');
  }

  Widget _buildScopeChip(List<AppUser> activePartners) {
    final acik = _kapsamAcik;
    // Varsayılan dışına çıkılmışsa çip vurgulanır: ekranda bir filtre
    // olduğunu rengiyle de söyler, yalnız metniyle değil.
    final filtreli = _typeFilter != null || _view != null || _simulate;
    final ton = acik || filtreli ? context.c.amberText : context.c.text58;

    return TourAnchor(
      target: TourTarget.kapsamSecici,
      child: Semantics(
        button: true,
        expanded: acik,
        label: '${context.l10n.scopeLabel}: ${_kapsamOzeti(activePartners)}',
        child: ExcludeSemantics(
          child: CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: () => _guncelle(() => _kapsamAcik = !_kapsamAcik),
            // Görsel kabuk 36pt, dokunma hedefi 44pt (HIG #37): şeffaf dolgu
            // ile büyütülür, kabuk büyütülmez.
            child: SizedBox(
              height: SandikTouch.min,
              child: Center(
                child: AnimatedContainer(
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.sm2),
              decoration: BoxDecoration(
                color: acik || filtreli
                    ? context.c.amberFill.withValues(alpha: 0.14)
                    : context.c.surface1,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                  color: acik || filtreli
                      ? context.c.amberFill.withValues(alpha: 0.55)
                      : context.c.overlay,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded, size: 15, color: ton),
                  const SizedBox(width: SandikSpace.xs2),
                  Flexible(
                    child: Text(
                      _kapsamOzeti(activePartners),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ton,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: acik ? 0.5 : 0,
                    duration: SandikMotion.stateOf(context),
                    curve: SandikMotion.enter,
                    child: Icon(Icons.expand_more_rounded, size: 16, color: ton),
                  ),
                ],
              ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Kapsam paneli — çipe dokununca açılan seyrek kontroller.
  ///
  /// Mod anahtarı yalnızca gün dışı dönemde anlamlı (gün içi seride
  /// simülasyonun karşılığı yok), bu yüzden orada hiç çizilmez.
  Widget _buildScopePanel(List<AppUser> activePartners, bool isIntraday) {
    return AnimatedCrossFade(
      duration: SandikMotion.surfaceOf(context),
      sizeCurve: SandikMotion.move,
      firstCurve: SandikMotion.enter,
      secondCurve: SandikMotion.enter,
      crossFadeState:
          _kapsamAcik ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: const SizedBox(width: double.infinity),
      secondChild: Padding(
        padding: const EdgeInsets.only(top: SandikSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activePartners.isNotEmpty) ...[
              ModernTabSelector(
                partners: activePartners,
                selectedId: _view,
                onChanged: (v) => _guncelle(() => _view = v),
              ),
              const SizedBox(height: SandikSpace.sm),
            ],
            HScrollWithFade(
              child: Row(
                children: [
                  _typeChip(null, context.l10n.allTypes),
                  for (final t in AssetType.values)
                    _typeChip(t, t.labelOf(context.l10n)),
                ],
              ),
            ),
            if (!isIntraday && !_ozetSekmesi) ...[
              const SizedBox(height: SandikSpace.sm),
              _buildModeToggle(),
            ],
          ],
        ),
      ),
    );
  }

  /// Dönem satırı — ekranın kalıcı İKİNCİ kontrol satırı.
  ///
  /// Dönem en sık dokunulan denetim, bu yüzden genişliğin çoğunu alır ve
  /// veriye en yakın satırda durur. Grafik araçları (tip, tam ekran) aynı
  /// satırın sağ ucunda ikon olarak: ikisi de seyrek kullanılıyor ve metinli
  /// hâlleri tek başına bir satır yiyordu.
  ///
  /// [araclar] Özet sekmesinde `false` — orada çizilecek bir grafik yok.
  Widget _buildPeriodRow({required bool araclar}) {
    return Row(
      children: [
        Expanded(
          child: TourAnchor(
            target: TourTarget.donemSecici,
            child: _buildPeriodToggle(),
          ),
        ),
        if (araclar) ...[
          const SizedBox(width: SandikSpace.sm),
          const GrafikTipiSecici(compact: true),
          const SizedBox(width: SandikSpace.xs2),
          ChartFullscreenChip(
            onTap: () => FullscreenChartRoute.open(
              context,
              title: context.l10n.portfolioPerformance,
              builder: (_) => PortfolioPerformanceScreen(
                initialView: _view,
                initialTypeFilter: _typeFilter,
                // Yatayda grafik hemen görünsün diye kontroller yukarı
                // kaydırılır. İki satıra indiler; eski 220 fazla kaçıyordu.
                initialScrollOffset: 96,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
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
  /// `_buildModeToggle` ile aynı kabuk (36px, surface1, SandikRadius.md) —
  /// iki anahtar yan yana durabildiği için aynı görünmek zorundalar, yoksa
  /// kullanıcı ikisini farklı sınıf denetimler sanır. Yükseklik 2026-09-15'te
  /// 44'ten 36'ya indi; dokunma hedefi `SandikTouch.minSize` ile 44pt kalır
  /// (görsel kabuk küçülür, dokunulabilir alan küçülmez).
  ///
  /// Dönem seçici DEĞİŞMEZ: `_selectedPeriodIdx` iki sekmede paylaşılıyor.
  Widget _buildSurfaceToggle() {
    final options = [
      (label: context.l10n.tabChart, ozet: false),
      (label: context.l10n.tabSummary, ozet: true),
    ];
    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
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
      height: 36,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
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
