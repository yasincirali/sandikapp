part of '../add_asset_screen.dart';

/// Varlık ekleme formunun TUTAR alanları: miktar, fiyat, komisyon, toplam,
/// fiyat önizlemesi, tarih. Bölünme 2026-10-24, davranış aynı.
extension _TutarAlanlari on _AddAssetScreenState {
  // ── Miktar bloğu ───────────────────────────────────────────────────────────
  Widget _quantityBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context.l10n.quantity),
        const SizedBox(height: 8),
        _brandInput(
          controller: _quantity,
          hint: '0',
          suffixText: _quantitySuffix,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) =>
              (_parse(v ?? '') == null || (_parse(v ?? '') ?? 0) <= 0)
                  ? context.l10n.quantityInvalid
                  : null,
        ),
      ],
    );
  }

  // ── Fiyat bloğu (para birimi dropdown right-side) ──────────────────────────
  Widget _priceBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bu blok "Miktar" ile aynı Row'da `Expanded` içinde duruyor, yani
        // ekranın ~yarısı kadar yer var. "Alış Fiyatı · opsiyonel" 375pt'de
        // 138px taşıyordu — NORMAL metin boyutunda, büyük fontta değil.
        // Eurobond: bankanın kote ettiği TEMİZ fiyat, nominalin yüzdesi
        // ("98,75"). Zorunlu — tarihli kapanış önizlemesi yok (gerekçe
        // `AddAssetFormState.resolveTicker`); seçimde piyasa fiyatı ön
        // doldurulur. Kayıtta kirli birim değere çevrilir.
        Row(
          children: [
            Flexible(
                child: _fieldLabel(_s.isEurobond
                    ? context.l10n.eurobondCleanPrice
                    : context.l10n.purchasePrice)),
            if (!_s.isEurobond) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(context.l10n.optional,
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _price,
          hint: _s.isEurobond ? '98,75' : context.l10n.auto,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) {
            if (_s.isEurobond && (_parse(v ?? '') ?? 0) <= 0) {
              return context.l10n.eurobondCleanPriceRequired;
            }
            return v != null && v.trim().isNotEmpty && _parse(v) == null
                ? context.l10n.invalid
                : null;
          },
          onChanged: (_) => _schedulePricePreview(),
          suffix: _isDoviz ? null : _inlineCurrencyPicker(),
        ),
      ],
    );
  }

  /// Fiyat alanının altındaki "İşlemiş faiz · Ödenen" satırı (eurobond).
  ///
  /// Kullanıcının cebinden çıkan para temiz fiyat DEĞİL, kirli fiyattır;
  /// bunu göstermemek maliyeti eksik yazmak olur (bkz. `eurobond.dart`).
  /// Hesap `AddAssetFormState.eurobondBirimFiyati`'nda; burada yalnız yazılır.
  /// Sözleşme seçilmediyse satır yok.
  Widget _eurobondFaizSatiri() {
    final s = _s.eurobondSozlesmesi;
    if (!_s.isEurobond || s == null) return const SizedBox.shrink();
    final faiz = fmtPct(s.islemisFaiz(_addedDate), digits: 3);
    final qty = _parse(_quantity.text);
    final birim = _s.eurobondBirimFiyati(_parse(_price.text));
    final metin = qty != null && qty > 0 && birim != null
        ? context.l10n
            .eurobondAccruedLine(faiz, '${fmtNum(qty * birim)} $_currency')
        : context.l10n.eurobondAccruedOnly(faiz);
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Text(
        metin,
        style: context.t.bodySmall?.copyWith(color: context.c.text58),
      ),
    );
  }

  // ── Komisyon / masraf (opsiyonel) ─────────────────────────────────────────
  // Komisyon maliyete girmezse kâr olduğundan yüksek görünür. İşlem başına
  // toplam tutar girilir (birim başına değil) ve varlığın para birimindedir.
  Widget _commissionBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: _fieldLabel(context.l10n.commission)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(context.l10n.optional,
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _commission,
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final parsed = _parse(v);
            if (parsed == null) return context.l10n.invalid;
            if (parsed < 0) return context.l10n.cannotBeNegative;
            return null;
          },
          suffix: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_currency,
                style: context.t.titleSmall?.copyWith(
                    color: context.c.text58, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.commissionNote,
          style: context.t.bodySmall?.copyWith(color: context.c.text36),
        ),
      ],
    );
  }

  Widget _inlineCurrencyPicker() {
    // ABD hissesi USD'ye kilitli (`AddAssetFormNotifier.setCurrency`):
    // açılır liste yerine sabit "USD" — seçenek sunup reddetmek kafa
    // karıştırırdı.
    // Eurobond da tahvilin kendi para birimine kilitli (aynı gerekçe).
    if (_s.isEurobond) {
      return Tooltip(
        message: context.l10n.eurobondCurrencyLocked,
        child: Text(_currency,
            style: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w700)),
      );
    }
    if (_s.isAbd) {
      return Tooltip(
        message: context.l10n.usStockCurrencyLocked,
        child: Text('USD',
            style: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w700)),
      );
    }
    // `DropdownButton` içeride kendi `Row`'unu kurar ve o Row daralamaz;
    // 320pt × 3.0× ölçekte 10px taşıyordu. İçerik üç harflik bir para
    // birimi kodu ("TRY") olduğu için ölçeği sınırlamak burada güvenli:
    // metin yine büyür, ama alan kaybına yol açacak noktada durur.
    //
    // Bu, Dynamic Type'ı YOK SAYMAK değil — üst sınır koymaktır. Genel
    // kural hâlâ geçerli: `TextScaler.noScaling` kullanılmaz.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currency,
          isDense: true,
          dropdownColor: context.c.surface2,
          style: context.t.titleSmall?.copyWith(
              color: context.c.amberText, fontWeight: FontWeight.w700),
          icon:
              Icon(Icons.arrow_drop_down_rounded, color: context.c.amberText, size: 18),
          items: _AddAssetScreenState._currencies
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c),
                  ))
              .toList(),
          onChanged: (v) => _n.setCurrency(v ?? _currency),
        ),
      ),
    );
  }

  // ── Toplam maliyet hero card ───────────────────────────────────────────────
  Widget _totalHero(ColorScheme cs) {
    final qty = _parse(_quantity.text);
    // Eurobond: alan temiz %; toplam nominal × kirli birim değerdir. Fiyat
    // zorunlu olduğundan "boş fiyat otomatik atanır" kartı gösterilmez —
    // çevrilemeyen fiyatta ipucu kartına düşülür.
    final eurobond = _s.isEurobond;
    final price = eurobond
        ? _s.eurobondBirimFiyati(_parse(_price.text))
        : _parse(_price.text);
    final isPriceEmpty = !eurobond &&
        (_price.text.trim().isEmpty || (price != null && price == 0));

    // Miktar yoksa hiçbir şey gösterme
    if (qty == null || qty <= 0 || (eurobond && price == null)) {
      return SandikCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.calculate_outlined, color: context.c.text36, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.costPreviewHint,
                style: context.t.titleSmall?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
    }

    if (isPriceEmpty) {
      final now = DateTime.now();
      final isToday = _addedDate.year == now.year &&
          _addedDate.month == now.month &&
          _addedDate.day == now.day;
      final msg = isToday
          ? 'Alış fiyatı boş. Kaydederken güncel piyasa fiyatı otomatik atanacak.'
          : 'Alış fiyatı boş. ${DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate)} '
              'tarihli kapanış fiyatı otomatik atanacak.';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.c.amberFill.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
              color: context.c.amberFill.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                color: context.c.amberText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: context.t.titleSmall
                    ?.copyWith(color: context.c.text90, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    if (price == null || price <= 0) return const SizedBox.shrink();

    final total = qty * price;
    final fmt = tryFormatter(digits: 2, symbol: _currency == 'TRY' ? '₺ ' : '');
    final formatted = _currency == 'TRY'
        ? fmt.format(total)
        : '${qtyFormatter(maxDigits: 2).format(total)} $_currency';
    final tlKuru = _tlKuru();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.c.amberFill.withValues(alpha: 0.16),
            context.c.amberFill.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
            color: context.c.amberFill.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: context.c.amberFill.withValues(alpha: 0.16),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      // İki taraf da ESNEK: eskiden sol kolon ve tutar sabit genişlikteydi,
      // `add_asset_screen_overflow_test` düzenleme modunda 320pt'te 309px
      // yatay taşma buldu (kesirli fon miktarı × NAV çarpımı + tutar).
      // Sol taraf kısalır, tutar sığmazsa ÖLÇEKLENİR — sayı kırpılmaz.
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.totalCostUpper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText,
                      letterSpacing: 0.8,
                    )),
                const SizedBox(height: 4),
                Text(
                    eurobond
                        ? context.l10n.eurobondTotalBreakdown(
                            fmtNumFlex(qty, maxDigits: 2),
                            fmtNum(price * 100, digits: 3))
                        : '${_fmt(qty)} × ${_fmt(price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatted,
                    // Form özeti toplam tutarı — tabular figür, yazarken
                    // zıplamasın.
                    style: context.t.numLarge.copyWith(
                      fontSize: 22,
                      color: context.c.gold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                // Dövizli alımın TL karşılığı: portföy toplamına giren
                // maliyet budur (aynı kur kuralı, bkz. `tlKarsiligiKuru`).
                // Kur bilinmiyorsa satır yok — uydurma tutar yazılmaz.
                if (tlKuru != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.l10n.totalCostTlEquivalent(
                        fmtTRY(total * tlKuru, digits: 2),
                        _currency,
                        fmtNum(tlKuru, digits: 4),
                      ),
                      key: const ValueKey('toplam-tl-karsiligi'),
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Toplam kartındaki TL satırının kuru; TRY'de ya da kur bilinmiyorken
  /// `null`. Geriye tarihli alımda alım günü kuru sorgulanır.
  double? _tlKuru() {
    if (_currency == 'TRY') return null;
    final p = ref.watch(portfolioProvider).valueOrNull;
    final canli = switch (_currency.toUpperCase()) {
      'USD' => p?.usdTry,
      'EUR' => p?.eurTry,
      'GBP' => p?.gbpTry,
      _ => null,
    };
    final simdi = DateTime.now();
    final geriTarihli = dayKey(_addedDate).isBefore(dayKey(simdi));
    final tarihli = geriTarihli
        ? ref
            .watch(alimGunuKuruProvider(
                (currency: _currency, gun: dayKey(_addedDate))))
            .valueOrNull
        : null;
    return tlKarsiligiKuru(
      currency: _currency,
      tarih: _addedDate,
      canliKur: canli ?? 0,
      tarihli: tarihli,
      now: simdi,
    );
  }

  // ── Tahmini birim fiyat kartı ──────────────────────────────────────────────
  //
  // Kullanıcı fiyat alanını boş bıraktığında, seçili varlık + tarih için
  // asenkron çekilen birim fiyatı burada gösterir. Kullanıcı save'e basmadan
  // "kaç TL'den atanacak" bilgisine sahip olur. Manuel fiyat yazıldığında
  // gizlenir (o zaman zaten bilinen değer var).
  Widget _pricePreviewCard(ColorScheme cs) {
    final userPrice = _parse(_price.text);
    // Kullanıcı fiyat yazmışsa preview gerekmez.
    if (userPrice != null && userPrice > 0) {
      return const SizedBox(height: 6);
    }
    final ticker = _resolveTickerForPreview();
    if (ticker == null || ticker.isEmpty) {
      return const SizedBox(height: 6);
    }

    final now = DateTime.now();
    final isToday = _addedDate.year == now.year &&
        _addedDate.month == now.month &&
        _addedDate.day == now.day;
    final dateLabel = isToday
        ? 'bugün'
        : DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate);

    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;

    if (_previewLoading && _previewPrice == null) {
      color = context.c.text58;
      icon = Icons.hourglass_top_rounded;
      title = 'Fiyat çekiliyor…';
      subtitle = '$dateLabel için kapanış aranıyor';
    } else if (_previewPrice != null) {
      final p = _previewPrice!;
      final fmt = qtyFormatter(maxDigits: 2);
      color = _previewIsHistorical ? context.c.gain : context.c.amberText;
      icon = _previewIsHistorical
          ? Icons.event_available_rounded
          : Icons.auto_awesome_rounded;
      title = '${fmt.format(p)} $_currency / birim';
      // Hafta sonu seçildiyse gelen kapanış Cuma'nındır; metin seçilen
      // günü değil, fiyatın GERÇEK gününü söyler (emülatör testi #31).
      final islemGunu = haftaSonuKapanisGunu(_addedDate,
          yediGun: _type == AssetType.kripto);
      subtitle = !_previewIsHistorical
          ? 'Tarihli fiyat bulunamadı, güncel piyasa fiyatı kullanılacak'
          : islemGunu != null
              ? context.l10n.pricePreviewLastTradingClose(
                  DateFormat('d MMM', context.tarihDili).format(islemGunu))
              : context.l10n.pricePreviewClose(dateLabel);
    } else {
      color = context.c.loss.withValues(alpha: 0.8);
      icon = Icons.help_outline_rounded;
      title = 'Fiyat bulunamadı';
      subtitle = 'İnternet yok ya da bu sembol için veri gelmedi. '
          'Alış fiyatını elle girebilirsin.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: _previewLoading && _previewPrice == null
                  ? const CustomLoadingIndicator(size: 14)
                  : Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.c.text90,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.text58,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── İşlem tarihi chip'i ────────────────────────────────────────────────────
  //
  // Varsayılan: bugün. Kullanıcı geriye dönük bir tarih seçerse ve alış
  // fiyatı boşsa, kaydederken o tarihin kapanış fiyatı otomatik atanır.
  // UX: küçük tek satır, dokununca native date picker açılır.
  Widget _dateChip(ColorScheme cs) {
    final now = DateTime.now();
    final isToday = _addedDate.year == now.year &&
        _addedDate.month == now.month &&
        _addedDate.day == now.day;
    final label = isToday
        ? 'Bugün'
        : DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate);

    return InkWell(
      borderRadius: BorderRadius.circular(SandikRadius.md),
      onTap: () async {
        final picked = await pickSandikDate(
          context,
          initialDate: _addedDate,
          helpText: context.l10n.transactionDate,
        );
        if (picked != null) {
          _n.setDate(picked);
          _schedulePricePreview();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
            color: isToday
                ? context.c.overlay
                : context.c.amberFill.withValues(alpha: 0.35),
            width: isToday ? 1 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded,
                size: 16,
                color: isToday ? context.c.text58 : context.c.amberText),
            const SizedBox(width: 10),
            // Etiket ve tarih değeri ikisi de esnek olmalı: dar ekranda
            // (320pt) "İşlem tarihi" + "14 Mart 2026" 38px taşıyordu.
            // `Spacer` boşluğu doldurur ama kimseyi daraltmaz.
            Flexible(
              child: Text(context.l10n.transactionDate,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: context.c.text90),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Spacer(),
            Flexible(
              child: Text(label,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isToday ? context.c.text58 : context.c.amberText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 16,
                color: isToday ? context.c.text36 : context.c.amberText),
          ],
        ),
      ),
    );
  }
}
