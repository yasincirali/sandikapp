part of '../add_asset_screen.dart';

/// Varlık ekleme formunun TUTAR alanları: miktar, fiyat, komisyon, toplam,
/// fiyat önizlemesi, tarih. Bölünme 2026-10-24, davranış aynı.
extension _TutarAlanlari on _AddAssetScreenState {
  // ── Adet / Tutar kipi (2026-10-24, Ar-Ge raporu §2) ───────────────────────
  //
  // Fon ve altın biriktiren kişi aldığını TL tutarıyla hatırlar ("5.000 TL
  // fon aldım"); adedi bulmak için bankaya gitmek ilk varlığı yarıda
  // bıraktırır. Kipte kullanıcı tutarı yazar, adet = tutar ÷ birim fiyat
  // (`tutardanAdet`) hesaplanır. Kayıt bugünkü gibi adet + fiyattır; şema
  // değişmez. Varsayılan Adet: bugünkü kullanıcı formu değişmiş görmez.
  //
  // Yalnız yeni kayıtta: düzenlemede adet zaten bilinir. Eurobondda yok:
  // fiyat temiz %, miktar nominal — bölme anlamsız.
  bool get _tutarKipiVar => _kolay && !_s.isEurobond;
  bool get _tutarModu => _tutarKipiVar && _s.tutarModu;

  String get _paraSembolu => _currency == 'TRY' ? '₺' : _currency;

  /// Adedin bölüneceği fiyat: yazılan fiyat, yoksa kayıtta atanacak fiyat.
  /// Önizleme yüklenirken eski önizleme fiyatı KULLANILMAZ (yeni tarih
  /// seçildiyse o fiyat başka günündür).
  double? get _tutarBirimFiyati => tutarBirimFiyati(
        kullaniciFiyati: _parse(_price.text),
        onizlemeFiyati: _previewLoading ? null : _previewPrice,
        onizlemeSatis: _previewLoading ? null : _s.previewSatis,
      );

  /// Kayda girecek adet: Adet kipinde alan, Tutar kipinde hesap.
  double? get _etkinAdet => _tutarModu
      ? tutardanAdet(tutar: _parse(_tutar.text), birimFiyat: _tutarBirimFiyati)
      : _parse(_quantity.text);

  Widget _miktarKipiSegmenti() {
    final l = context.l10n;
    final etiketler = [l.miktarModuAdet, l.miktarModuTutar(_paraSembolu)];
    return SandikSegment(
      adet: 2,
      secili: _s.tutarModu ? 1 : 0,
      onSec: _miktarKipiniSec,
      semantik: (i) => l.miktarModuSemantik(etiketler[i]),
      oge: (context, i, _) => Text(etiketler[i],
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// Tutar → Adet dönüşünde hesaplanan adet alana yazılır: "bankadaki adet
  /// farklıysa adedi düzelt" ipucunun yolu budur. Adet → Tutar'da tutar
  /// alanı olduğu gibi kalır (ön doldurulan tutar kullanıcının girdisi
  /// sanılırdı).
  void _miktarKipiniSec(int i) {
    final tutar = i == 1;
    if (tutar == _s.tutarModu) return;
    if (!tutar) {
      final adet = _etkinAdet;
      if (adet != null) _quantity.text = _fmt(adet);
    }
    _n.setTutarModu(tutar);
  }

  Widget _tutarBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context.l10n.tutarAlani),
        const SizedBox(height: SandikSpace.sm),
        _brandInput(
          controller: _tutar,
          hint: '0',
          suffixText: _paraSembolu,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) {
            final t = _parse(v ?? '');
            if (t == null || t <= 0) return context.l10n.tutarGecersiz;
            // Fiyat yoksa adet hesaplanmaz; kayıt uydurma adetle gitmez.
            if (_tutarBirimFiyati == null) {
              return context.l10n.tutarFiyatGerekli;
            }
            return null;
          },
        ),
      ],
    );
  }

  /// Hesaplanan adet (yuvarlanmadan) ve fon ipucu. Fiyat yoksa adet yazılmaz.
  Widget _tutardanAdetSatiri() {
    final l = context.l10n;
    final tutar = _parse(_tutar.text);
    final adet = _etkinAdet;
    final String? metin = adet != null
        ? l.tutardanAdetSatiri(
            '${fmtNumFlex(adet, maxDigits: 8)} $_quantitySuffix'.trim())
        : (tutar != null && tutar > 0 && !_previewLoading)
            ? l.tutardanAdetFiyatYok
            : null;
    final stil = context.t.bodySmall?.copyWith(color: context.c.text58);
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (metin != null)
            Text(metin,
                key: const ValueKey('tutardan-adet'),
                style: context.t.bodyMedium?.copyWith(
                    color: context.c.text90, fontWeight: FontWeight.w600)),
          // Fonlarda banka tam pay alır, artanı hesapta bırakır; alım çoğu
          // fonda ertesi günün fiyatından gerçekleşir. Uydurma adet yerine
          // kullanıcıya düzeltme yolu söylenir.
          if (_isFon) ...[
            if (metin != null) const SizedBox(height: SandikSpace.xs),
            Text(l.fonAdetIpucu, style: stil),
          ],
        ],
      ),
    );
  }

  /// Önizleme kartındaki tek bilgi satırı: kuyumcu farkı ve bugün
  /// bozdurulunca ele geçen. "Zarardasın" denmez: yeni varlığın ilk gün
  /// eksi görünmesinin nedeni açıklanır (Ar-Ge raporu §1).
  String _kuyumcuFarkiSatiri({required double alis, required double satis}) {
    final l = context.l10n;
    final fark = fmtPct(kuyumcuFarkiYuzde(alis: alis, satis: satis), digits: 1);
    final adet = _etkinAdet;
    final tutar = adet != null && adet > 0
        ? fmtTRY(adet * alis, digits: 2)
        : l.fiyatBirimBasina(fmtTRYFiyat(alis));
    return _type == AssetType.altin
        ? l.kuyumcuFarkiAltin(fark, tutar)
        : l.kuyumcuFarkiDoviz(fark, tutar);
  }

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

  /// Boş fiyat alanının ipucu: kayıtta atanacak fiyatın KENDİSİ (müşteri
  /// raporu 31 Eki 13:15 tasarım #8, yasin "yap"). "Otomatik" yazısı ne
  /// atanacağını söylemiyordu; rakamı gören kullanıcı alana dokunmadan
  /// güveniyor. Altın/dövizde satış fiyatı (maliyet ondan yazılır,
  /// `maliyetSatisFiyati`). Fiyat kaynak basamağıyla (`fmtFiyat` + türün
  /// azami hanesi), yuvarlama yok. Önizleme gelmediyse "Otomatik" kalır:
  /// uydurma sayı yok. Düzenlemede de "Otomatik" kalır: orada boş alan
  /// fiyat ATAMAZ (maliyeti bilinmeyen lot işaretli kalır,
  /// `veri_kalitesi_akis_test`), rakam yanlış söz verirdi.
  String _fiyatIpucu() {
    if (_isEditing) return context.l10n.auto;
    final p = _previewLoading ? null : (_s.previewSatis ?? _previewPrice);
    if (p == null || p <= 0) return context.l10n.auto;
    final azami = _type.fiyatAzamiOndalik;
    return _currency == 'TRY'
        ? fmtFiyat(p, azami: azami)
        : '${fmtFiyat(p, azami: azami, symbol: '')} $_currency';
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
          hint: _s.isEurobond ? '98,75' : _fiyatIpucu(),
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
    final qty = _etkinAdet;
    // Eurobond: alan temiz %; toplam nominal × kirli birim değerdir. Fiyat
    // zorunlu olduğundan "boş fiyat otomatik atanır" kartı gösterilmez —
    // çevrilemeyen fiyatta ipucu kartına düşülür.
    final eurobond = _s.isEurobond;
    final price = eurobond
        ? _s.eurobondBirimFiyati(_parse(_price.text))
        : _parse(_price.text);
    final isPriceEmpty = !eurobond &&
        (_price.text.trim().isEmpty || (price != null && price == 0));

    // Miktar yoksa hiçbir şey gösterme. 2026-10-31'e kadar burada "miktarı
    // yaz, toplam burada görünsün" diyen BOŞ bir kart vardı (müşteri raporu
    // 31 Eki 13:15 tasarım #7, yasin "yap"): yorumun kendisi "hiçbir şey
    // gösterme" diyordu, kart ise formun ortasında içeriksiz bir kutu olarak
    // ritmi bozuyordu. Toplam miktar yazılınca belirir.
    if (qty == null || qty <= 0 || (eurobond && price == null)) {
      return const SizedBox.shrink();
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
    } else if (_previewPrice != null && _s.previewSatis != null) {
      // Boş fiyatlı yeni altın/döviz, bugün: maliyet satıştan yazılacak
      // (`maliyetSatisFiyati`). Başlık atanacak fiyatı, satır farkı söyler.
      final satis = _s.previewSatis!;
      color = context.c.amberText;
      icon = Icons.auto_awesome_rounded;
      title = context.l10n.fiyatBirimBasina(
          '${qtyFormatter(maxDigits: 2).format(satis)} $_currency');
      subtitle = _kuyumcuFarkiSatiri(alis: _previewPrice!, satis: satis);
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
