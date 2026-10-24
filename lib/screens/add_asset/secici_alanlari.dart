part of '../add_asset_screen.dart';

/// Katalog seçici alanları (döviz, BIST, ABD, TEFAS, kripto, eurobond) ve
/// açtıkları sayfalar. Sayfaların kendisi `secici_sayfalari.dart`'ta.
/// Bölünme 2026-10-24, davranış aynı.
extension _SeciciAlanlari on _AddAssetScreenState {
  // ── Döviz para birimi seçici (Sandik brand, 4 büyük kart) ──────────────────

  Widget _dovizSelector(ColorScheme cs) {
    return Row(
      children: dovizOptions.map((opt) {
        final selected = _subCategory == opt.label;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.label,
              child: SandikBasma(
              onTap: () {
                SandikHaptic.selection.perform();
                _yaz(_n.selectDoviz(opt));
                _schedulePricePreview();
              },
              child: AnimatedContainer(
                duration:
                    SandikMotion.stateOf(context),
                curve: SandikMotion.enter,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? AssetType.doviz.color.withValues(alpha: 0.18)
                      : context.c.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: selected ? AssetType.doviz.color : context.c.overlay,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color:
                                AssetType.doviz.color.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: -6,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt.symbol,
                      style: context.t.headlineLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? AssetType.doviz.onSurface(context)
                            : context.c.text90,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      opt.label,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AssetType.doviz.onSurface(context)
                            : context.c.text58,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            )),
          ),
        );
      }).toList(),
    );
  }

  // ── Miktar preset chipleri (Sandik brand) ──────────────────────────────────

  Widget _quantityPresetsRow(ColorScheme cs) {
    final presets = _quantityPresets;
    return HScrollWithFade(
      fadeColor: context.c.background,
      child: Row(
        children: presets.map((v) {
          final selected = _quantity.text == v;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              button: true,
              selected: selected,
              label: context.l10n.quantitySemantics(v),
              child: SandikBasma(
              onTap: () {
                SandikHaptic.selection.perform();
                _quantity.text = v;
              },
              child: ConstrainedBox(
          // HIG 44 pt (seçici denetimi 2026-10-12): görsel çip aynı, dokunma
          // alanı 44'e tamamlanır.
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Center(widthFactor: 1, heightFactor: 1, child: AnimatedContainer(
                duration:
                    SandikMotion.stateOf(context),
                curve: SandikMotion.enter,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? context.c.amberFill.withValues(alpha: 0.16)
                      : context.c.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: selected
                        ? context.c.amberFill.withValues(alpha: 0.45)
                        : context.c.overlay,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v,
                      style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? context.c.amberText : context.c.text58,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      // Miktar alanının son ekiyle AYNI birim (bulgu #22):
                      // eski `UnitType.label` hisse/fonda "Adet" yazıyordu.
                      _quantitySuffix,
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: selected
                            ? context.c.amberFill.withValues(alpha: 0.75)
                            : context.c.text36,
                      ),
                    ),
                  ],
                ),
              )),
        ),
            )),
          );
        }).toList(),
      ),
    );
  }

  // ── Hisse pazarı: BIST | ABD (bayrak `abd_hisse`) ───────────────────────────
  //
  // Ortak `SandikSegment`: uygulamadaki öteki "birini seç" kontrolleriyle
  // aynı davranış (kayan zemin, 44 pt dokunma hedefi, hareketi azalt).
  Widget _hissePazariSecici() {
    final etiketler = [
      context.l10n.stockMarketBist,
      context.l10n.stockMarketUs,
    ];
    return SandikSegment(
      adet: 2,
      secili: _s.isAbd ? 1 : 0,
      onSec: (i) {
        _yaz(_n.selectHisseBorsasi(abd: i == 1));
        _schedulePricePreview();
      },
      semantik: (i) => context.l10n.stockMarketSemantics(etiketler[i]),
      oge: (context, i, _) => Text(etiketler[i], maxLines: 1),
    );
  }

  /// ABD seçicisi — BIST seçicisiyle aynı alan, aynı alt sayfa düzeni.
  /// Seçili hisse ayrı durumda tutulmaz: kimlik sembol alanıdır
  /// ([AddAssetFormState.resolveIdentity]), seçici yalnız onu doldurur.
  Widget _abdSelectorField(ColorScheme cs, {required bool hata}) {
    final ticker = abdSembolu(_ticker.text);
    final ad = abdHisseleri[ticker];
    return Semantics(
      button: true,
      label: ad == null
          ? context.l10n.pickUsStock
          : context.l10n.selectedUsStockSemantics(ad),
      child: SandikBasma(
        onTap: _showAbdPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: ad != null,
          hasError: hata,
          badgeText: ad == null ? null : ticker,
          mainText: ad ?? context.l10n.pickUsStockTap,
          color: AssetType.hisse.color,
        ),
      ),
    );
  }

  void _showAbdPicker() {
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _AbdPicker(
        selected: abdSembolu(_ticker.text),
        onSelect: (ticker) {
          _yaz(_n.selectAbdHisse(ticker));
          _schedulePricePreview();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── BIST100 seçici ─────────────────────────────────────────────────────────

  Widget _bist100SelectorField(ColorScheme cs, {required bool hata}) {
    final selectedName = _bist100SelectedTicker != null
        ? BistHisseKatalogu.instance.hisseler[_bist100SelectedTicker!] ?? _bist100SelectedTicker!
        : null;
    final ticker = _bist100SelectedTicker?.replaceAll('.IS', '');

    // Doğrulama kimlik bölümünün FormField'ında (`_identitySection`).
    return Semantics(
      button: true,
      label: selectedName == null
          ? context.l10n.pickStock
          : 'Seçili hisse: $selectedName. Değiştirmek için çift dokun.',
      child: SandikBasma(
        onTap: _showBist100Picker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _bist100SelectedTicker != null,
          hasError: hata,
          badgeText: ticker,
          mainText: selectedName ?? context.l10n.pickStockTap,
          color: AssetType.hisse.color,
        ),
      ),
    );
  }

  void _showBist100Picker() {
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _Bist100Picker(
        selected: _bist100SelectedTicker,
        onSelect: (ticker) {
          _yaz(_n.selectBist100(ticker));
          _schedulePricePreview();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── TEFAS fon seçici ───────────────────────────────────────────────────────

  Widget _tefasSelectorField(ColorScheme cs, {required bool hata}) {
    return Semantics(
      button: true,
      label: _selectedFund == null
          ? context.l10n.pickFund
          : 'Seçili fon: ${_selectedFund!.name}. Değiştirmek için çift dokun.',
      child: SandikBasma(
        onTap: _showTefasPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _selectedFund != null,
          hasError: hata,
          badgeText: _selectedFund?.code,
          mainText: _selectedFund?.name ?? context.l10n.pickFundTap,
          color: AssetType.fon.color,
        ),
      ),
    );
  }

  void _showTefasPicker() {
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _TefasPicker(
        selected: _selectedFund?.code,
        onSelect: (fund) {
          // Fon fiyatı alış fiyatına dolar (opsiyonel, kullanıcı silebilir).
          _yaz(_n.selectFund(fund, priceEmpty: _price.text.isEmpty));
          _schedulePricePreview();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── Kripto seçici ──────────────────────────────────────────────────────────
  //
  // Fon seçicisiyle aynı alan + alt sayfa. Sembol serbest yazılmaz; yalnız
  // `kripto_varlik` kataloğundan seçilir, böylece her kayıt sunucunun
  // fiyatladığı bir koda bağlanır (fiyat kaynağı sözleşmesi madde 1).
  Widget _kriptoSelectorField(ColorScheme cs, {required bool hata}) {
    final kod = kriptoKodu(_ticker.text);
    final ad = _name.text.trim().isEmpty ? kod : _name.text.trim();
    return Semantics(
      button: true,
      label: kod == null
          ? context.l10n.pickCryptoTap
          : context.l10n.cryptoSelectedSemantics(ad ?? kod),
      child: SandikBasma(
        onTap: _showKriptoPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: kod != null,
          hasError: hata,
          badgeText: kod,
          mainText: kod == null ? context.l10n.pickCryptoTap : (ad ?? kod),
          color: AssetType.kripto.color,
        ),
      ),
    );
  }

  void _showKriptoPicker() {
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _KriptoPicker(
        selected: kriptoKodu(_ticker.text),
        onSelect: (o) {
          _yaz(_n.selectKripto(o, priceEmpty: _price.text.isEmpty));
          _schedulePricePreview();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── Eurobond seçici (bayrak `eurobond`) ────────────────────────────────────
  //
  // Kripto seçicisiyle aynı alan + alt sayfa. ISIN serbest alana yazılmaz;
  // seçicinin aramasına yazılır ve katalogda aranır (kontrol hanesi
  // `isinGecerli`). Böylece her kayıt sunucunun fiyatladığı bir sözleşmeye
  // bağlanır (fiyat kaynağı sözleşmesi madde 1) ve kupon/vade elle girilmez.
  // Rozet vade yılı: ISIN 12 hane, rozete sığmaz; ISIN ekran okuyucuda ve
  // seçici satırında.
  Widget _eurobondSelectorField(ColorScheme cs, {required bool hata}) {
    final s = _s.eurobondSozlesmesi;
    return Semantics(
      button: true,
      label: s == null
          ? context.l10n.pickEurobondTap
          : context.l10n.eurobondSelectedSemantics('${s.ad} (${s.isin})'),
      child: SandikBasma(
        onTap: _showEurobondPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: s != null,
          hasError: hata,
          badgeText: s == null ? null : '${s.vade.year}',
          mainText: s?.ad ?? context.l10n.pickEurobondTap,
          color: AssetType.eurobond.color,
        ),
      ),
    );
  }

  void _showEurobondPicker() {
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _EurobondPicker(
        selected: _s.eurobondSozlesmesi?.isin,
        onSelect: (o) {
          _yaz(_n.selectEurobond(o.$1, o.$2, priceEmpty: _price.text.isEmpty));
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── Shared selector container ──────────────────────────────────────────────

  Widget _selectorContainer({
    required ColorScheme cs,
    required bool hasValue,
    required bool hasError,
    required String? badgeText,
    required String mainText,
    required Color color,
    IconData trailingIcon = Icons.search_rounded,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        // Seçici bir giriş alanı gibi okunur ve aynı formda TextFormField'ların
        // yanında durur: dolgu ve boş kenar onlarla aynı kuraldan
        // (`inputFill` + hairline). `surface1` + `overlay` kenar idi — dark'ta
        // komşu alanlar şeffafken bu tek kutu dolu görünüyordu.
        color: context.inputFill,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: hasError
              ? context.c.loss
              : (hasValue ? color : context.c.hairline),
          width: hasValue ? 1.4 : 1,
        ),
        // Parlama YALNIZ dışarıda (`BlurStyle.outer`). Flutter gölgeyi
        // kutunun tamamı olarak çizer; eski opak `surface1` dolgu içini
        // örtüyordu. Dolgu dark'ta şeffaf olunca (`inputFill`) gölge kutunun
        // içini varlık rengine boyadı — düzeltilen "içi farklı renk" hatasının
        // aynısı. `outer` negatif yayılmayla kullanılamaz (içeride bir şerit
        // boyar), bu yüzden yayılma 0 ve bulanıklık kısaltıldı.
        boxShadow: hasValue
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 10,
                  blurStyle: BlurStyle.outer,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (badgeText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              // Rozet METNİ açık temada koyulaştırılmış ton (`metinTonu`);
              // dolgu ham renkte kalır.
              child: Text(badgeText,
                  style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color.metinTonu(context),
                      letterSpacing: 0.5)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              mainText,
              style: context.t.titleMedium?.copyWith(
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                color: hasValue ? context.c.text90 : context.c.text36,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(trailingIcon, size: 18, color: context.c.text58),
        ],
      ),
    );
  }

}
