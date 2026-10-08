part of '../portfolio_performance_screen.dart';

/// Kontroller: tür çipleri, dönem/yüzey/mod anahtarları, boş durumlar.
/// `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
extension _PerformansKontroller on _PortfolioPerformanceScreenState {
  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? context.c.amberText;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // Seçili tür ekran okuyucuya da söylenir; yalnızca renkteydi (#28).
      child: Semantics(
        container: true,
        selected: selected,
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
  ///   · kim → aynı gün kendi satırına, en üste (`OrtakSecici`):
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
  /// taşındı (`OrtakSecici`). Kullanıcı bildirimi: "ortakları seçtiğim
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
    // Mod bu çipte yazılmaz (2026-10-04, `performans_ayar_sade`; bayrak
    // 2026-10-05'te kalktı): mod Ayarlar › Görünüm'de, çipte yazmak paneli
    // açanı boş panelle karşılardı. Mod kapsam çubuğunun altındaki rozette.
    return l.scopeCategory(kategori);
  }

  Widget _buildScopeChip() {
    final acik = _kapsamAcik;
    // Varsayılan dışına çıkılmışsa çip vurgulanır: ekranda bir filtre
    // olduğunu rengiyle de söyler, yalnız metniyle değil.
    // Kim seçimi artık başlıktaki kişi çipinde; bu çip yalnız tür + mod
    // filtresini yansıtır. `_view` buraya girince "Ben" seçili her
    // kullanıcıda çip sürekli amber yanıyordu — filtre yokken de.
    final filtreli = _typeFilter != null;
    // Varsayılan (filtresiz) durumda da ton koyu: çip soluk `text58` iken
    // düz bir etiket gibi duruyordu ve dokunulabilir olduğu anlaşılmıyordu
    // (kullanıcı bildirimi 2026-09-15: "kişi seçimi çok efektif olmamış").
    // Vurgulu hâl hâlâ ayrışıyor — amber, varsayılan koyu nötr.
    final ton = acik || filtreli ? context.c.amberText : context.c.text90;

    return TourAnchor(
      target: TourTarget.kapsamSecici,
      child: Semantics(
        // Kendi düğümü (2026-10-08): yanındaki yüzey anahtarının segmentleri
        // birleşik düğüm olunca (`SandikSegment` → `MergeSemantics`) bu
        // kapsayıcısız yapılandırma satırın düğümüne sızıyordu; "Kapsam: …"
        // etiketi bütün satırı kaplıyor, ekran okuyucu çipi ayrı bulamıyordu.
        container: true,
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
                  // Ok panelle aynı süre/eğride (animasyon denetimi
                  // 2026-10-01: ok 180 ms `enter`, panel 240 ms `move`).
                  SandikAcilirOk(
                    acik: acik,
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

  /// Kapsam paneli — çipe dokununca açılan seyrek kontroller (tür çipleri).
  Widget _buildScopePanel() {
    // Simülasyon sıfırlaması YOK: tercih Ayarlar'da kalıcıdır ve `_simulate`
    // grafik araçları gizliyken (sade Başlangıç) onu zaten etkisiz sayar.
    // Ortak katlanır bölüm (animasyon denetimi 2026-10-01).
    return SandikAcilir(
      acik: _kapsamAcik,
      child: Padding(
        padding: const EdgeInsets.only(top: SandikSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sarmalı (`Wrap`), yatay kaydırmalı DEĞİL: kaydırmalı satırda
            // Kripto/Emtia/Diğer ekran dışında kalıyor ve kenardaki silik ok
            // fark edilmiyordu — kullanıcı o türlerin var olduğunu
            // kaydırmadan bilemiyordu (2026-09-29 emülatör testi #29). Panel
            // seyrek açılıyor; birkaç satırlık yükseklik seçeneği gizlemekten
            // ucuz.
            Wrap(
              children: [
                _typeChip(null, context.l10n.allTypes),
                for (final t in AssetType.values)
                  _typeChip(t, t.labelOf(context.l10n)),
              ],
            ),
            // Gerçek|Simülasyon anahtarı burada YOK (2026-10-04,
            // `performans_ayar_sade`, madde 5; bayrak ve eski anahtar
            // `_buildModeToggle` 2026-10-05'te kalktı): Ayarlar › Görünüm'e
            // taşındı. Dönemden döneme değiştirilen bir kontrol değil, bir
            // bakış tercihi; panelde kaldığında her açılışta "Gerçek mi,
            // Bugünkü mü?" sorusu soruyordu.
          ],
        ),
      ),
    );
  }

  /// Dönem satırı — ekranın kalıcı İKİNCİ kontrol satırı, grafiğin ÜSTÜNDE.
  ///
  /// 2026-09-28'de bir süre grafiğin altına indirildi ve aynı gün geri
  /// alındı; gerekçe `kartlar.dart` kontrol yığını notunda (grafiğin boyu
  /// dönemle değişiyor, altındaki seçici zıplıyordu). Üç grafik ekranı da
  /// bu sırayı paylaşır: fiyat/kontrol → seçici → grafik.
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

  /// Dönem seçici — ortak [DonemSecici] (tek dönem kümesi ve tek görünüş,
  /// 2026-09-28). İçerik oranlı pay kararı ve gerekçesi o bileşene taşındı;
  /// bu ekran yalnızca seçimi ve gün içi zamanlayıcıyı yönetir.
  Widget _buildPeriodToggle() {
    return DonemSecici(
      donemler: SummaryPeriod.values,
      secili: _selectedPeriodIdx,
      onSec: (i) {
        _guncelle(() => _selectedPeriodIdx = i);
        _startIntradayTickIfNeeded();
      },
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
    // Ortak [SandikSegment] (2026-10-01): seçim zemini kayar.
    return SandikSegment(
      adet: options.length,
      secili: _ozetSekmesi ? 1 : 0,
      onSec: (i) {
        final o = options[i];
        _guncelle(() {
          _ozetSekmesi = o.ozet;
          _sekmeDegismeAni = DateTime.now();
        });
        if (o.ozet) {
          AnalyticsService.instance.logPeriodSummaryViewed(
            period: SummaryPeriod.fromIndex(_selectedPeriodIdx).name,
          );
        }
      },
      oge: (_, i, __) => Text(options[i].label),
    );
  }

  /// "Bugünkü portföyle" rozeti — mod etkinken kapsam çubuğunun altında
  /// (2026-10-04, `performans_ayar_sade`).
  ///
  /// Anahtar Ayarlar › Görünüm'e taşındı; burada bir şey kalmasa kullanıcı
  /// gördüğü eğrinin GERÇEK geçmiş olmadığını bilemezdi ("görünmeyen
  /// filtre", bkz. `_buildScopeBar`). Rozet durum söyler, kontrol değildir:
  /// dokununca modun ne olduğunu ve nereden kapatılacağını anlatır.
  Widget _buildBugunkuPortfoyRozeti() {
    final etiket = context.l10n.todaysPortfolioBadge;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: context.l10n.modeInfoSemantics(etiket),
        child: ExcludeSemantics(
          child: CupertinoButton(
            minimumSize: SandikTouch.minSize,
            padding: EdgeInsets.zero,
            onPressed: _showModeInfoSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.sm2, vertical: SandikSpace.xs),
              decoration: BoxDecoration(
                color: context.c.amberFill.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: context.c.amberFill.withValues(alpha: 0.55)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 15, color: context.c.amberText),
                  const SizedBox(width: SandikSpace.xs2),
                  Flexible(
                    child: Text(
                      etiket,
                      style: context.t.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.amberText,
                      ),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.xs2),
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: context.c.amberText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Bugünkü portföyle" rozetinin bilgi sayfası. Nereden kapatılacağı da
  /// yazılır: anahtar bu ekranda değil, Ayarlar › Görünüm'de. (Gerçek mod
  /// açıklaması `realMode*` eski anahtarın ⓘ'siyle 2026-10-05'te kalktı.)
  void _showModeInfoSheet() {
    final title = context.l10n.simModeTitle;
    final body = context.l10n.simModeBody;
    final ipucu = context.l10n.todaysPortfolioBadgeHint;

    // Uygulamanın öteki ~30 sheet'i gibi Material alt sayfası (animasyon
    // denetimi 2026-10-01): bu tek Cupertino açılır penceresiydi — 335 ms
    // kayıyor, aşağı çekerek KAPANMIYORDU ve köşesi 24'tü (tema 20).
    showSandikSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DefaultTextStyle(
        style: sandikFont(
            color: context.c.text90, decoration: TextDecoration.none),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: const SandikTutamac(),
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
                const SizedBox(height: SandikSpace.sm),
                Text(
                  ipucu,
                  style: context.t.bodyMedium?.copyWith(
                      color: context.c.amberText,
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
      // Özet'in kanonik serisi de yeniden kurulsun (`_OzetSerisi`); bellek
      // de bırakılır — kullanıcı yenilemesi bilinçli bir yeniden ölçümdür.
      _ozetYenileme++;
      _ozetBellek.temizle();
    });
    _zoomController?.reload();
  }
}
