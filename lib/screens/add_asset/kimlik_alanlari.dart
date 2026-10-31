part of '../add_asset_screen.dart';

/// Varlık ekleme formunun KİMLİK alanları: hangi varlık (ad/kod, emtia,
/// hisse pazarı, altın türü). `add_asset_screen.dart`'tan bölündü
/// (2026-10-24, davranış aynı): 4.200 satırlık dosyada bir alanı bulmak
/// için kaydırmak gerekiyordu. State üyeleri `extension` ile (CLAUDE.md proje
/// yapısı, asset_detail deseni).
extension _KimlikAlanlari on _AddAssetScreenState {
  // ── Bağlama göre "kimlik" alanının etiketi ─────────────────────────────────
  String _identityLabel() {
    if (_isBist100 || _type == AssetType.hisse) return context.l10n.identityStock;
    if (_isFon) return context.l10n.identityFund;
    if (_type == AssetType.altin) return context.l10n.identityGoldKind;
    if (_isDoviz) return context.l10n.identityCurrency;
    if (_type == AssetType.emtia) return context.l10n.identityCommodity;
    if (_type == AssetType.kripto) return context.l10n.identityCrypto;
    if (_type == AssetType.eurobond) return context.l10n.identityEurobond;
    return context.l10n.assetFallbackName;
  }

  // ── Kimlik bölümü: hisse/fon → picker; altın → chip grid; döviz → 4 kart
  //
  // Seçim gerektiren türlerde varlık seçilmeden kayıt YOK (kullanıcı
  // bildirimi 2026-09-29: hisse seçmeden "Ekle" adsız bir lot yazıyordu).
  // Kural `AddAssetFormState.kimlikEksigi`'nde; burada tek bir FormField
  // onu doğrular ve uyarıyı alanın ALTINDA satır içi yazar. Eskiden hisse
  // (BIST seçili değilken), altın ve döviz hiç doğrulanmıyordu; fon ve
  // kripto doğrulanıyor ama yalnızca kenar kırmızıya dönüyordu — metin
  // yoktu, "Ekle" neden çalışmıyor belli değildi.
  Widget _identitySection(ColorScheme cs) {
    return FormField<void>(
      validator: (_) => _kimlikUyarisi(_s.kimlikEksigi(
        tickerText: _ticker.text,
        muaf: _isEditing,
      )),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kimlikAlani(cs, hata: state.hasError),
          if (state.hasError) ...[
            const SizedBox(height: SandikSpace.xs2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
              child: Text(
                state.errorText!,
                style: context.t.bodySmall?.copyWith(color: context.c.loss),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _kimlikUyarisi(KimlikEksigi? e) => switch (e) {
        null => null,
        KimlikEksigi.hisse => context.l10n.pickStockPrompt,
        KimlikEksigi.fon => context.l10n.pickFundPrompt,
        KimlikEksigi.altin => context.l10n.pickGoldPrompt,
        KimlikEksigi.doviz => context.l10n.pickCurrencyPrompt,
        KimlikEksigi.kripto => context.l10n.pickCryptoPrompt,
        KimlikEksigi.eurobond => context.l10n.pickEurobondPrompt,
        KimlikEksigi.emtia => context.l10n.pickCommodityPrompt,
      };

  Widget _kimlikAlani(ColorScheme cs, {required bool hata}) {
    if (_type == AssetType.hisse) return _stockIdentityBlock(cs, hata: hata);
    if (_isFon) return _tefasSelectorField(cs, hata: hata);
    if (_type == AssetType.altin) return _goldChipGrid(cs, hata: hata);
    if (_isDoviz) return _dovizSelector(cs);
    if (_type == AssetType.kripto) return _kriptoSelectorField(cs, hata: hata);
    if (_type == AssetType.eurobond) {
      return _eurobondSelectorField(cs, hata: hata);
    }
    if (_type == AssetType.emtia) return _emtiaSecici(cs, hata: hata);
    // Diğer — manuel ad + opsiyonel sembol
    return _elleKimlik();
  }

  /// Serbest ad + opsiyonel sembol: "Diğer" türü ve emtia listesinin
  /// "Diğer" yolu (listede olmayan emtia, eski kayıt).
  Widget _elleKimlik() {
    return Column(
      children: [
        _brandInput(
          controller: _name,
          hint: _type == AssetType.emtia ? context.l10n.commodityHint : context.l10n.assetName,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? context.l10n.nameRequired : null,
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _ticker,
          hint: _type.tickerHintOf(context.l10n),
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (v) {
            if (v.isEmpty) _n.setManualPrice(true);
            _schedulePricePreview();
          },
        ),
      ],
    );
  }

  // ── Emtia: listeden seç (2026-10-18) ─────────────────────────────────────
  //
  // yasin: "emtia seçenekleri listelense, free text yerine". Kullanıcı Yahoo
  // sembolünü (`CL=F`) bilmiyor; serbest girişte çoğu emtia sembolsüz, yani
  // fiyatsız kaydediliyordu. Liste `emtiaKatalogu` (arama ile tek kaynak);
  // "Diğer" eski serbest girişi açar. Seçim yapılmadan kayıt yok
  // (`KimlikEksigi.emtia`; uyarıyı `_identitySection` yazar).

  String _emtiaBirimi(EmtiaBirimi b) => switch (b) {
        EmtiaBirimi.ons => context.l10n.goldUnitOunce,
        EmtiaBirimi.gram => context.l10n.goldUnitGram,
        EmtiaBirimi.libre => context.l10n.commodityUnitPound,
        EmtiaBirimi.varil => context.l10n.commodityUnitBarrel,
        EmtiaBirimi.mmbtu => context.l10n.commodityUnitMmbtu,
      };

  void _emtiaSec(EmtiaSecenegi? e) {
    SandikHaptic.selection.perform();
    _yaz(e == null
        ? _n.emtiaDiger(tickerText: _ticker.text)
        : _n.selectEmtia(e));
    _schedulePricePreview();
  }

  // Açılır liste (yasin 18 Eki: "çipler yerine listeden dropdowndan
  // seçilemez mi"). İlk hâli çip ızgarasıydı; yedi emtia + Diğer üç satır
  // kaplıyor, formu aşağı itiyordu. Alan kripto/eurobond seçicisiyle aynı
  // kutu (`_selectorContainer`); kısa ve aramasız liste olduğu için alt
  // sayfa yerine alanın altında açılan menü (iOS pull-down menüsü kalıbı).
  // Menü değeri sembol; '' = Diğer.
  Widget _emtiaSecici(ColorScheme cs, {required bool hata}) {
    final elle = _s.emtiaElle;
    final secili = elle ? null : emtiaSecenegi(_ticker.text);
    final l = context.l10n;
    final ana =
        elle ? l.commodityOtherSelected : (secili?.ad ?? l.pickCommodityTap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: secili == null && !elle
              ? l.pickCommodityTap
              : l.commoditySelectedSemantics(secili == null
                  ? ana
                  : '${secili.ad}, ${_emtiaBirimi(secili.birim)}'),
          excludeSemantics: true,
          // Menü alanla aynı genişlikte açılır (dropdown okunuşu); içerik
          // genişliğinde dar bir kutu alanın yarısında asılı kalıyordu.
          child: LayoutBuilder(
            builder: (context, kutu) => PopupMenuButton<String>(
              tooltip: '',
              position: PopupMenuPosition.under,
              constraints: BoxConstraints.tightFor(width: kutu.maxWidth),
              color: context.c.surface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                side: BorderSide(color: context.c.hairline),
              ),
              onSelected: (t) =>
                  _emtiaSec(t.isEmpty ? null : emtiaSecenegi(t)),
              itemBuilder: (_) => [
                for (final e in emtiaKatalogu)
                  _emtiaSatiri(e.ticker, e.ad, _emtiaBirimi(e.birim),
                      secili: e == secili),
                _emtiaSatiri('', l.commodityOther, null, secili: elle),
              ],
              child: _selectorContainer(
                cs: cs,
                hasValue: secili != null || elle,
                hasError: hata,
                badgeText: secili == null ? null : _emtiaBirimi(secili.birim),
                mainText: ana,
                color: AssetType.emtia.color,
                trailingIcon: Icons.expand_more_rounded,
              ),
            ),
          ),
        ),
        if (elle) ...[
          const SizedBox(height: SandikSpace.md),
          _elleKimlik(),
        ],
      ],
    );
  }

  PopupMenuItem<String> _emtiaSatiri(String deger, String ad, String? birim,
      {required bool secili}) {
    return PopupMenuItem<String>(
      value: deger,
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: ad,
                  style: context.t.bodyMedium?.copyWith(
                      color: context.c.text90,
                      fontWeight: secili ? FontWeight.w700 : FontWeight.w400),
                ),
                if (birim != null)
                  TextSpan(
                    text: ' · $birim',
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text36),
                  ),
              ]),
            ),
          ),
          // Seçili satır yalnız kalın yazıyla değil, işaretle de belli.
          if (secili)
            Icon(Icons.check_rounded, size: 18, color: context.c.amberText),
        ],
      ),
    );
  }

  // ── Hisse: birleşik "BIST100'den seç veya sembol yaz" bloğu ────────────────
  //
  // BIST100 seçilirse subCategory = "BIST 100 Hisseleri" yazılır (data korunur).
  // Manuel sembol → subCategory = "Diğer Hisseler".
  //
  // ABD (bayrak `abd_hisse`, 2026-10-08): üstte "BIST | ABD" pazar seçimi;
  // ABD'de seçici `abdHisseleri` kataloğunu açar, serbest sembol Yahoo
  // biçimine çevrilir (`abdSembolu`). Bayrak kapalıyken segment hiç
  // kurulmaz ve blok birebir eski.
  Widget _stockIdentityBlock(ColorScheme cs, {required bool hata}) {
    final abd = _s.isAbd;
    return Column(
      children: [
        if (_s.abdAcik) ...[
          _hissePazariSecici(),
          const SizedBox(height: SandikSpace.sm2),
        ],
        if (abd)
          _abdSelectorField(cs, hata: hata)
        else
          _bist100SelectorField(cs, hata: hata),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                  height: 1, color: context.c.text36.withValues(alpha: 0.3)),
            ),
            // Ayraç metni büyük font ayarında iki çizgiyi dışarı itiyordu.
            // Çizgiler zaten `Expanded`; daralması gereken metindir.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(context.l10n.orNotInList,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            Expanded(
              child: Container(
                  height: 1, color: context.c.text36.withValues(alpha: 0.3)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _ticker,
          hint: abd ? context.l10n.usSymbolHint : context.l10n.symbolHint,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (v) {
            _n.tickerTyped(v);
            _schedulePricePreview();
          },
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _name,
          hint: context.l10n.companyNameHint,
        ),
      ],
    );
  }

  // ── Altın: tek yatay çip satırı ─────────────────────────────────────────────
  //
  // 2026-09-25: 16 tür tek çip ızgarasında ekranı dolduruyordu; düzen (C)
  // seçildi: hisse/fon seçicisiyle aynı alan + altında 5 kısayol.
  // 2026-10-31 (müşteri raporu 31 Eki 13:15 tasarım #6, yasin "yap"): seçim
  // alanı + "Hızlı seçim" başlığı + üç satıra kayan beş çip, ekranın en
  // dağınık yeriydi ve aynı şeyi iki kez soruyordu. Şimdi TEK yatay satır:
  // kısayollar + sonda "Tümü ›" (aramalı gruplu alt sayfa, nadir türler
  // için, satırın sağında sabit). Satır sarmaz, kayar: büyük yazıda
  // yükseklik sabit kalır.
  // Kısayolların kuralı `altinKisayollari`'nda (portföydeki türler, 5'e
  // popülerle tamamla). Alt sayfadan kısayolda olmayan bir tür seçilirse
  // satırın BAŞINA eklenir: seçim her zaman görünür.
  Widget _goldChipGrid(ColorScheme cs, {required bool hata}) {
    final secili = _seciliAltin;
    final kisayollar = altinKisayollari(
        ref.watch(portfolioProvider).valueOrNull?.assets ?? const []);
    final cipler = [
      if (secili != null && !kisayollar.contains(secili)) secili,
      ...kisayollar,
    ];
    // "Tümü" kayan satırın DIŞINDA, sağda sabit: dar ekranda kaydırmanın
    // sonunda kalsaydı nadir türlere giden tek yol görünmezdi.
    return Row(
      children: [
        Expanded(
          // Düz kaydırma, `HScrollWithFade` DEĞİL: onun ok rozeti dar
          // satırda yarım görünen çipin üstüne biniyordu (önce/sonra
          // görüntüsü 2026-10-31). Kenarda kesilen çip kaydırmayı zaten
          // söylüyor.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final g in cipler) ...[
                  _goldChip(g, g == secili, hata: hata && secili == null),
                  const SizedBox(width: SandikSpace.sm),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: SandikSpace.xs),
        _tumAltinlarCipi(hata: hata && secili == null),
      ],
    );
  }

  Widget _tumAltinlarCipi({required bool hata}) {
    return Semantics(
      button: true,
      label: context.l10n.altinTumTurlerSemantik,
      excludeSemantics: true,
      child: SandikBasma(
        onTap: _showGoldPicker,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(SandikSpace.md2,
                  SandikSpace.sm2, SandikSpace.sm, SandikSpace.sm2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: hata ? context.c.loss : context.c.overlay),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.altinTumTurler,
                      style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.amberText)),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: context.c.amberText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  GoldSubCategory? get _seciliAltin {
    for (final g in GoldSubCategory.values) {
      if (g.label == _subCategory) return g;
    }
    return null;
  }

  /// Rozet ve liste satırında birim: türün nasıl alındığı (gram / adet / ons)
  /// seçimden önce görünsün — miktar alanına ne yazılacağını belirler.
  String _altinBirimi(GoldSubCategory g) => switch (g.unitType) {
        'gr' => context.l10n.goldUnitGram,
        'ounce' => context.l10n.goldUnitOunce,
        _ => context.l10n.unitPiece,
      };

  void _selectGold(GoldSubCategory g) {
    _yaz(_n.selectGold(g));
    _schedulePricePreview();
  }

  void _showGoldPicker() {
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _GoldPicker(
        selected: _seciliAltin,
        birim: _altinBirimi,
        onSelect: (g) {
          _selectGold(g);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Widget _goldChip(GoldSubCategory g, bool selected, {bool hata = false}) {
    // Diğer çipler gibi (tür, döviz, miktar): ekran okuyucu 'düğme' ve
    // 'seçili' bilgisini Semantics olmadan alamaz (Faz 2.13).
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.goldSemantics(g.label),
      child: SandikBasma(
        onTap: () {
          SandikHaptic.selection.perform();
          _selectGold(g);
        },
        child: ConstrainedBox(
          // HIG 44 pt (seçici denetimi 2026-10-12): görsel çip aynı, dokunma
          // alanı 44'e tamamlanır.
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Center(widthFactor: 1, heightFactor: 1, child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md2, vertical: SandikSpace.sm2),
          decoration: BoxDecoration(
            color: selected
                ? AssetType.altin.color.withValues(alpha: 0.18)
                : context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: selected
                  ? AssetType.altin.color
                  : (hata ? context.c.loss : context.c.overlay),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AssetType.altin.color.withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: -6,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded,
                  size: 14,
                  color: selected
                      ? AssetType.altin.onSurface(context)
                      : context.c.text58),
              const SizedBox(width: SandikSpace.xs2),
              Text(g.label,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? context.c.text90 : context.c.text58)),
            ],
          ),
        )),
        ),
      ),
    );
  }

}
