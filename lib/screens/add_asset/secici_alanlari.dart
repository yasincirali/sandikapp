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
              child: SandikTappable(
              soluk: true,
              haptic: SandikHaptic.none,
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
                  // Seçili kutu parıltısı kalktı (amber bütçesi, Ar-Ge
                  // 2026-11-12 #1): seçim dolgu + çerçeveyle okunur.
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt.symbol,
                      style: context.t.headlineLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
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

  // ── Miktar önayar çipleri ──────────────────────────────────────────────────
  //
  // Ar-Ge 2026-11-12 #7: çipler kendi kabuğundaydı; görsel ~32 pt
  // (dokunma 44'e tamamlanmıştı ama kalın parmak görsel kutuya nişan alır),
  // her çipte "lot"/"gr" eki vardı ve seçim yalnız amber tonla okunuyordu.
  // Artık tarih çipleriyle AYNI bileşen ([SandikFiltreCipi]: 44 pt görsel,
  // seçiliyken amber dolgu + onay işareti — yalnız renkle anlam yok, sabit
  // en). Birim eki kalktı: miktar alanının sonunda zaten yazıyor; satır
  // daralır, "1000" sığar. Ekran okuyucu birimi yine duyar.
  Widget _quantityPresetsRow(ColorScheme cs) {
    final presets = _quantityPresets;
    return HScrollWithFade(
      fadeColor: context.c.background,
      child: Row(
        children: [
          for (final v in presets)
            Padding(
              padding: const EdgeInsets.only(right: SandikSpace.sm),
              child: SandikFiltreCipi(
                key: ValueKey('miktar-cipi-$v'),
                ad: v,
                semantik: context.l10n
                    .quantitySemantics('$v $_quantitySuffix'.trim()),
                secili: _quantity.text == v,
                onTap: () => _quantity.text = v,
              ),
            ),
        ],
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
      child: SandikTappable(
        soluk: true,
        haptic: SandikHaptic.none,
        onTap: _showAbdPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: ad != null,
          hasError: hata,
          badgeText: ad == null ? null : ticker,
          mainText: ad ?? context.l10n.pickUsStockTap,
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
        portfoyKodlari: _portfoyKodlari(
            (a) => a.abdHissesi ? a.ticker.toUpperCase() : null),
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
      child: SandikTappable(
        soluk: true,
        haptic: SandikHaptic.none,
        onTap: _showBist100Picker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _bist100SelectedTicker != null,
          hasError: hata,
          badgeText: ticker,
          mainText: selectedName ?? context.l10n.pickStockTap,
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
        // Katalog anahtarı `.IS`'li; eski lotlarda sonek olmayabilir.
        portfoyKodlari: _portfoyKodlari((a) {
          if (a.type != AssetType.hisse || a.abdHissesi) return null;
          final t = a.ticker.toUpperCase();
          return t.endsWith('.IS') ? t : '$t.IS';
        }),
        onSelect: (ticker) {
          _yaz(_n.selectBist100(ticker));
          _schedulePricePreview();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  /// Seçicinin "Portföyündekiler" bölümü için bugün tutulan kodlar
  /// (`portfoydekiKodlar`: aktif lot, sahibe göre, değere göre sıralı).
  /// Sayfa açılırken bir kez okunur; açıkken portföy değişmez.
  List<String> _portfoyKodlari(String? Function(Asset) kod) => portfoydekiKodlar(
      ref.read(portfolioProvider).valueOrNull?.assets ?? const [], kod);

  // ── TEFAS fon seçici ───────────────────────────────────────────────────────

  Widget _tefasSelectorField(ColorScheme cs, {required bool hata}) {
    return Semantics(
      button: true,
      label: _selectedFund == null
          ? context.l10n.pickFund
          : 'Seçili fon: ${_selectedFund!.name}. Değiştirmek için çift dokun.',
      child: SandikTappable(
        soluk: true,
        haptic: SandikHaptic.none,
        onTap: _showTefasPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _selectedFund != null,
          hasError: hata,
          badgeText: _selectedFund?.code,
          mainText: _selectedFund?.name ?? context.l10n.pickFundTap,
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
        portfoyKodlari: _portfoyKodlari((a) => a.type == AssetType.fon
            ? a.ticker.replaceFirst('TEFAS:', '').toUpperCase()
            : null),
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
      child: SandikTappable(
        soluk: true,
        haptic: SandikHaptic.none,
        onTap: _showKriptoPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: kod != null,
          hasError: hata,
          badgeText: kod,
          mainText: kod == null ? context.l10n.pickCryptoTap : (ad ?? kod),
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
      child: SandikTappable(
        soluk: true,
        haptic: SandikHaptic.none,
        onTap: _showEurobondPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: s != null,
          hasError: hata,
          badgeText: s == null ? null : '${s.vade.year}',
          mainText: s?.ad ?? context.l10n.pickEurobondTap,
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
        // Amber bütçesi (Ar-Ge 2026-11-12 #1, unslop "Colored glows",
        // "Every element highlighted"): dolu seçici eskiden tür renginde
        // kalın çerçeve + dış parıltı taşıyordu; hisse rengi amber olduğu
        // için formda kaydet düğmesiyle yarışan yedi amber öğeden biriydi.
        // Dolu olduğu metnin kendisinden okunur (ağırlık + text90), çerçeve
        // öteki alanlarla aynı kıl çizgisi. Hata kırmızısı kalır.
        border: Border.all(
          color: hasError ? context.c.loss : context.c.hairline,
        ),
      ),
      child: Row(
        children: [
          if (badgeText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              // Sembol rozeti nötr yüzey (amber bütçesi, yukarıda): tür
              // rengini taşıyınca hisse/altında ikinci bir amber leke oluyordu.
              decoration: BoxDecoration(
                color: context.c.surface2,
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: Text(badgeText,
                  style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90)),
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
