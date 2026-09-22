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
        // Tür filtresi de tohumu atar — kapsamla aynı gerekçe
        // (`_gunIciTohumuAt`): başka bir türün serisi bu türün özeti
        // sanılmamalı.
        onPressed: () => _guncelle(() {
          _typeFilter = type;
          _gunIciTohumuAt();
        }),
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
  ///   · seyrek: hangi tür, hangi mod → tek çipin arkasına alındı
  ///   · kim → aynı gün kendi satırına, en üste (`KapsamKisiSecici`):
  ///     panelin arkasında görünmez kalıyordu, oysa ekranın öznesi
  ///
  /// Çip bunları GİZLEMEZ: seçili kapsamı her zaman yazar ("Fon ·
  /// Simülasyon"). Bir filtrenin açık olduğunu görmek için paneli açmak
  /// gerekmez — "neden portföyüm eksik görünüyor" sınıfı hatanın kaynağı
  /// tam olarak görünmeyen filtredir.
  Widget _buildScopeBar() {
    return Row(
      children: [
        // İkisi de esnek ve eşit: yüzey anahtarı sabit genişlik alsaydı dar
        // ekranda kapsam çipine üç nokta bile sığmıyordu.
        //
        // 2026-09-21'de dönem seçicisi bu satıra alınıp yüzey anahtarı kendi
        // satırına çıkarılmak istendi; GERİ ALINDI: beş dönem etiketi
        // 320pt'te ancak tam genişlikte kırpılmadan sığıyor
        // (`performans_kontrol_yigini_test`). Sadeleşme Özet'in içinde
        // (üç başlık + katlanır Derinlik), kontrol yığını iki satır kalır.
        Expanded(child: _buildSurfaceToggle()),
        const SizedBox(width: SandikSpace.sm),
        Expanded(child: _buildScopeChip()),
      ],
    );
  }

  /// Kapsamın tek satırlık özeti: "tür · mod".
  ///
  /// "Kim" 2026-09-15'te buradan ÇIKTI — kontrol yığınının ilk satırına
  /// taşındı (`KapsamKisiSecici`). Kullanıcı bildirimi: "ortakları seçtiğim
  /// filtre daha görülebilir olmalı". Panelin arkasında kalınca kimin
  /// portföyüne bakıldığı bir metin parçasına indirgeniyordu; oysa bu bir
  /// filtre ayrıntısı değil, ekranın öznesi.
  ///
  /// Mod yalnızca simülasyondayken yazılır: varsayılan (Gerçek) her çipte
  /// tekrar edilecek bir bilgi değil.
  ///
  /// Kategori öneki HEP taşınır ("Kategori: Tümü", "Kategori: Fon") —
  /// kullanıcı bildirimi 2026-09-15: "varlık kategorisi yazılmalı Tümü
  /// yerine". Çıplak "Tümü" neyin tümü olduğunu söylemiyordu; çipin bir
  /// VARLIK KATEGORİSİ seçtiği ancak paneli açınca anlaşılıyordu.
  String _kapsamOzeti() {
    final l = context.l10n;
    final kategori =
        _typeFilter == null ? l.allTypes : _typeFilter!.labelOf(l);
    return [
      l.scopeCategory(kategori),
      if (_simulate) l.modeSim,
    ].join(' · ');
  }

  Widget _buildScopeChip() {
    final acik = _kapsamAcik;
    // Varsayılan dışına çıkılmışsa çip vurgulanır: ekranda bir filtre
    // olduğunu rengiyle de söyler, yalnız metniyle değil.
    // Kim seçimi artık başlıktaki kişi çipinde; bu çip yalnız tür + mod
    // filtresini yansıtır. `_view` buraya girince "Ben" seçili her
    // kullanıcıda çip sürekli amber yanıyordu — filtre yokken de.
    final filtreli = _typeFilter != null || _simulate;
    // Varsayılan (filtresiz) durumda da ton koyu: çip soluk `text58` iken
    // düz bir etiket gibi duruyordu ve dokunulabilir olduğu anlaşılmıyordu
    // (kullanıcı bildirimi 2026-09-15: "kişi seçimi çok efektif olmamış").
    // Vurgulu hâl hâlâ ayrışıyor — amber, varsayılan koyu nötr.
    final ton = acik || filtreli ? context.c.amberText : context.c.text90;

    return TourAnchor(
      target: TourTarget.kapsamSecici,
      child: Semantics(
        button: true,
        expanded: acik,
        label: '${context.l10n.scopeLabel}: ${_kapsamOzeti()}',
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
                // Varsayılan hâl `surface2` + `hairline`: yüzeyden ayrışan
                // bir kabuk, "dokunulabilir" sinyali. Eski `surface1` +
                // `overlay` arka planla neredeyse aynı tondaydı ve çip
                // kayboluyordu.
                color: acik || filtreli
                    ? context.c.amberFill.withValues(alpha: 0.14)
                    : context.c.surface2,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                  color: acik || filtreli
                      ? context.c.amberFill.withValues(alpha: 0.55)
                      : context.c.hairline,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded, size: 15, color: ton),
                  const SizedBox(width: SandikSpace.xs2),
                  Flexible(
                    child: Text(
                      _kapsamOzeti(),
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
  Widget _buildScopePanel(bool isIntraday) {
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
  /// Dönem en sık dokunulan denetim, veriye en yakın satırda durur. Grafik
  /// araçları 2026-09-15'te bu satırdan grafik kartının İÇİNE taşındı: tip
  /// seçici kartın dibine, tam ekran kartın sağ üstüne ("vertical butonu da
  /// grafiğin sağ üstünde olmalı"). Araç etkilediği şeyin üstünde durur,
  /// satır yalnız dönemi taşır.
  Widget _buildPeriodRow() {
    // Tam genişlik: kabuk üstündeki iki satırla (kişi seçici, Grafik|Özet +
    // kapsam çipi) AYNI hizada biter. İçerik genişliğinde bırakılmıştı ve
    // sağında asimetrik bir boşluk kalıyordu — kullanıcı bildirimi
    // 2026-09-15: "time interval da ortalanmalı, tasarımda garip
    // gözüküyor". Üç satır hizalanınca yığın tek blok okunur.
    return TourAnchor(
      target: TourTarget.donemSecici,
      child: _buildPeriodToggle(),
    );
  }

  /// Dönem seçici — kabuk TAM GENİŞLİK, segmentler İÇERİK ORANINDA pay alır.
  ///
  /// ## Neden eşit pay (`Expanded`) DEĞİL
  /// 2026-09-15'e kadar beş segment `Expanded` ile eşit bölünüyordu; 390pt
  /// ekranda her biri ~63pt ve altı harfli "GÜNLÜK" oraya sığmıyordu. İkinci
  /// deneme (`Flexible` + `softWrap: false`) da kesti: içerideki `Center` boş
  /// alanı doldurup segmentleri yine eşitliyordu. Emülatör render edemediği
  /// için UI ağacından okunan ölçümler yanıltmıştı; hata gerçek cihaz
  /// görüntüsünde göründü ("GÜNLÜ" diye kırpılmış).
  ///
  /// ## Neden içerik ORANI
  /// Üçüncü deneme içerik genişliğinde bir kabuktu (kayan satır); bu kez
  /// kabuk üstündeki iki satırdan dar kalıyor ve sağında asimetrik boşluk
  /// bırakıyordu ("time interval da ortalanmalı, tasarımda garip
  /// gözüküyor"). Şimdi kabuk satırı dolduruyor ama pay eşit değil:
  /// `flex` her segmentin ÖLÇÜLEN metin genişliğinden (+ yan boşluk)
  /// türetiliyor, yani GÜNLÜK payın ~%29'unu, iki harfliler ~%18'ini alıyor.
  /// Hem hizalı hem kırpılmasız.
  ///
  /// `flex` tam sayı ister; ölçüm 100 ile çarpılıp yuvarlanıyor. Metin
  /// ölçeği (Dynamic Type) ve dil değişince oranlar kendiliğinden yeniden
  /// hesaplanır — sabit bir oran tablosu EN "DAILY"de bozulurdu.
  Widget _buildPeriodToggle() {
    final periods = _PortfolioPerformanceScreenState._periods;
    final stil = context.t.bodyMedium;
    // Seçili segment w600 çizilir; ölçüm en GENİŞ hâlle yapılır ki seçim
    // değiştikçe segmentler yatay zıplamasın.
    final olcumStili = stil?.copyWith(fontWeight: FontWeight.w600);
    final olcek = MediaQuery.textScalerOf(context);

    int paySayisi(int i) {
      final tp = TextPainter(
        text: TextSpan(
            text: donemEtiketi(context.l10n, periods[i].label),
            style: olcumStili),
        textDirection: Directionality.of(context),
        textScaler: olcek,
      )..layout();
      // + iki yandan 10pt: segmentin kendi nefes payı.
      return ((tp.width + 2 * SandikSpace.sm2) * 100).round();
    }

    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Flexible(
            flex: paySayisi(i),
            child: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: EdgeInsets.zero,
              onPressed: () {
                _guncelle(() => _selectedPeriodIdx = i);
                _startIntradayTickIfNeeded();
              },
              child: Container(
                height: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Text(
                  donemEtiketi(context.l10n, periods[i].label),
                  maxLines: 1,
                  softWrap: false,
                  // Pay metne göre verildiği için taşma beklenmez; çok
                  // büyük metin ölçeğinde son çare olarak küçültülür —
                  // kırpmak (`clip`) etiketi okunmaz yapardı.
                  overflow: TextOverflow.visible,
                  style: stil?.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        isSelected ? context.c.amberText : context.c.text36,
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
