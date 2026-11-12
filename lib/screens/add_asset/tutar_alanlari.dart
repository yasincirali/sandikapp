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

  // ── Bu alımla ortalama maliyet (Ar-Ge 2026-11-12 #5) ──────────────────────
  //
  // Hızlı Al "Yeni ortalama maliyetin X (şimdi Y)" satırını gösteriyordu ama
  // portföydeki varlığa bu formdan alım eklenince aynı soru cevapsızdı. Aynı
  // metin (`quickBuyAvgCost`), aynı hesap ([yeniOrtalamaMaliyet]: komisyon
  // girmez, renksiz — yeni ortalama iyi ya da kötü değil, bilgi) ve aynı
  // maliyet tabanı (aktif lotların ağırlıklı ortalaması,
  // [eldekiPozisyonMaliyeti]). Gizli bakiyede tutar maskelenir (Hızlı Al
  // gibi).
  //
  // Yok: yeni varlıkta (elde yok), düzenlemede/yeniden kurmada (alım değil),
  // sepette (satış satırı olabilir, sepetteki öteki alımlar hesaba girmez),
  // sözleşmeli türde, maliyeti bilinmeyen lotta, fiyat ya da miktar
  // bilinmiyorken.

  /// Seçili varlığın bugünkü pozisyonu; sağlayıcı izlemesi olduğu için
  /// ekran kurulumunda çağrılır (her tuşta değil).
  ({double adet, double maliyet})? _eldekiPozisyon() {
    if (_isEditing || widget.cartMode || _type.sozlesmeli) return null;
    final k = _s.resolveIdentity(nameText: _name.text, tickerText: _ticker.text);
    if (k.ticker.isEmpty && k.name.isEmpty) return null;
    final anahtar = positionKey(Asset(
      id: '',
      userId: '',
      name: k.name,
      ticker: k.ticker,
      type: _type,
      quantity: 0,
      purchasePrice: 0,
      currency: _currency,
      notes: '',
      subCategory: _subCategory,
    ));
    return ref.watch(eldekiPozisyonMaliyetiProvider(anahtar));
  }

  Widget? _ortalamaSatiri(
      ({double adet, double maliyet})? eldeki, bool gizli) {
    if (eldeki == null) return null;
    final birim = _s.isEurobond
        ? _s.eurobondBirimFiyati(_parse(_price.text))
        : _tutarBirimFiyati;
    final yeni = yeniOrtalamaMaliyet(
      eskiAdet: eldeki.adet,
      eskiMaliyet: eldeki.maliyet,
      yeniAdet: _etkinAdet,
      fiyat: birim,
    );
    if (yeni == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: Text(
        context.l10n.quickBuyAvgCost(
            _birimMaliyetMetni(yeni, gizli), _birimMaliyetMetni(eldeki.maliyet, gizli)),
        key: const ValueKey('form-ortalama-onizleme'),
        style: context.t.bodyMedium?.copyWith(color: context.c.text58),
      ),
    );
  }

  /// Birim maliyet biçimi Hızlı Al'daki gibi: ₺ varlıkta `fmtTRYFiyat`
  /// (0 ondalık ₺41,23'ü ₺41 okuturdu), dövizde 4 haneye kadar.
  String _birimMaliyetMetni(double v, bool gizli) {
    if (_currency == 'TRY') {
      // Maske Hızlı Al'daki lira maskesiyle aynı biçim. Baz para nesnesi
      // burada kullanılmaz: form fiyat dosyasıdır, kote fiyat baz para
      // birimine çevrilmez (`money_format_scope_test`).
      return gizli ? '₺••••' : fmtTRYFiyat(v);
    }
    if (gizli) return '•••• $_currency';
    return '${qtyFormatter(maxDigits: 4).format(v)} $_currency';
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
        _metinle(_price, (_) => _fiyatBosIpucuSatiri()),
      ],
    );
  }

  /// Boş fiyat alanının altındaki tek satır (Ar-Ge 2026-11-12 #6). Eskiden
  /// miktar yazılınca formun ortasına amber çerçeveli bir bilgi kutusu
  /// geliyordu ("Alış fiyatı boş. Kaydederken… otomatik atanacak", ham
  /// literal); bilgi fiyat alanının kendisine ait ve tek satır yeter. "O
  /// gün" seçili tarihtir: bugünse canlı fiyat, geçmişse o günün kapanışı —
  /// cümle ikisini de doğru söyler, tarih değişince metin değişmez.
  ///
  /// Eurobondda yok (fiyat zorunlu). Düzenlemede yok: orada boş alan fiyat
  /// atamaz (gerekçe [_fiyatIpucu]). Fiyat yazılınca yükseklikle kapanır.
  Widget _fiyatBosIpucuSatiri() {
    final goster =
        !_s.isEurobond && !_isEditing && _price.text.trim().isEmpty;
    return _Beliren(
      child: !goster
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: SandikSpace.xs2),
              child: Text(
                context.l10n.fiyatBosIpucu,
                key: const ValueKey('fiyat-bos-ipucu'),
                style: context.t.bodySmall?.copyWith(color: context.c.text58),
              ),
            ),
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
  //
  // Altında (fiziki altın, `AssetType.altin`) aynı alan "İşçilik / masraf"
  // adını alır: kuyumcudan alan kişi işçiliği "komisyon" diye düşünmez ve
  // gram fiyatına gömerek yazıyordu; o zaman maliyet piyasanın üstünde
  // başlar, ilk gün zarar görünür. Alan ve maliyet hesabı aynı, yalnız ad
  // ve not değişir.
  Widget _commissionBlock(ColorScheme cs) {
    final altin = _s.isAltin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
                child: _fieldLabel(altin
                    ? context.l10n.commissionGold
                    : context.l10n.commission)),
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
                    color: context.c.text58, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          altin ? context.l10n.commissionNoteGold : context.l10n.commissionNote,
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
                color: context.c.text58, fontWeight: FontWeight.w600)),
      );
    }
    if (_s.isAbd) {
      return Tooltip(
        message: context.l10n.usStockCurrencyLocked,
        child: Text('USD',
            style: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w600)),
      );
    }
    // Fon ve BIST hissesi her zaman TL (müşteri raporu 2 Kas 17:15 #2):
    // açılır liste yalnız yanlış kayıt üretebiliyordu. Kilit yalnız para
    // birimi ZATEN TRY iken; geçmişte yanlışlıkla başka birimle kaydedilmiş
    // bir lot düzenlenirken liste açık kalır ki düzeltilebilsin. "Diğer
    // Hisseler" yurt dışı olabilir, kilitlenmez.
    final borsaIstanbul = _type == AssetType.hisse &&
        !_s.isAbd &&
        _s.subCategory != StockSubCategory.other.label;
    if ((_s.isFon || borsaIstanbul) && _currency == 'TRY') {
      return Tooltip(
        message: context.l10n.tlCurrencyLocked,
        child: Text('TRY',
            style: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w600)),
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
          // Nötr (amber bütçesi, Ar-Ge 2026-11-12 #1): açılır ok seçilebilir
          // olduğunu söyler; amber kaydet düğmesine kalır.
          style: context.t.titleSmall?.copyWith(
              color: context.c.text90, fontWeight: FontWeight.w600),
          icon:
              Icon(Icons.arrow_drop_down_rounded, color: context.c.text58, size: 18),
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

  // ── Toplam maliyet: alt çubukta, kaydet düğmesinin üstünde ────────────────
  //
  // Ar-Ge 2026-11-12 #2: toplam eskiden formun ortasında gradyanlı, amber
  // parıltılı bir karttı. Tarih, komisyon, not girerken ekrandan çıkıyor ve
  // komisyonu içermiyordu (`qty * price`). Banka emir ekranlarında olduğu
  // gibi artık kaydet düğmesinin hemen üstünde sabit: kullanıcı fazladan
  // sıfırı kayıttan HEMEN önce görür. Komisyon dahil ([formToplamMaliyeti]);
  // yazılıysa dökümde "komisyon dahil" der. Gradyan, gölge ve çift çerçeve
  // kalktı (unslop "Colored glows"); tutar nötr metin, tek vurgu kaydet.
  //
  // Birim fiyat: yazılan fiyat, boşsa kayıtta atanacak önizleme fiyatı
  // ([_tutarBirimFiyati], önizleme kartının söylediği sayı). Önizleme
  // yüklenirken ya da fiyat bilinmiyorken satır yok — uydurma tutar yazılmaz.
  // Eurobond: alan temiz %; toplam nominal × kirli birim değer.
  //
  // Düzen (HIG Dynamic Type): `Wrap` — normal yazıda açıklama solda, tutar
  // sağda; 2× yazıda tutar ikinci satıra iner, kırpılmaz; yine sığmazsa
  // ölçeklenir (`FittedBox`), sayı kesilmez. Ekran okuyucu tek düğüm okur.
  Widget? _toplamSatiri(double? tlKuru) {
    if (_type.sozlesmeli) return null;
    final qty = _etkinAdet;
    final birim = _s.isEurobond
        ? _s.eurobondBirimFiyati(_parse(_price.text))
        : _tutarBirimFiyati;
    final komisyon = _parse(_commission.text);
    final toplam = formToplamMaliyeti(
        adet: qty, birimFiyat: birim, komisyon: komisyon);
    if (toplam == null || qty == null || birim == null) return null;
    final l = context.l10n;

    final tutar = _currency == 'TRY'
        ? fmtTRY(toplam, digits: 2)
        : '${qtyFormatter(maxDigits: 2).format(toplam)} $_currency';
    final carpim = _s.isEurobond
        ? l.eurobondTotalBreakdown(fmtNumFlex(qty, maxDigits: 2),
            fmtNum(birim * 100, digits: 3))
        : '${_fmt(qty)} × ${_fmt(birim)}';
    final ayrinti = (komisyon ?? 0) > 0
        ? '$carpim · ${l.toplamKomisyonDahil}'
        : carpim;
    // Dövizli alımın TL karşılığı: portföy toplamına giren maliyet budur
    // (aynı kur kuralı, bkz. `tlKarsiligiKuru`). Kur bilinmiyorsa satır yok.
    final tl = tlKuru == null
        ? null
        : l.totalCostTlEquivalent(fmtTRY(toplam * tlKuru, digits: 2),
            _currency, fmtNum(tlKuru, digits: 4));

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [l.totalCostUpper, tutar, ayrinti, if (tl != null) tl].join(', '),
      child: Padding(
        key: const ValueKey('alt-cubuk-toplam'),
        padding: const EdgeInsets.only(bottom: SandikSpace.sm),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: SandikSpace.sm,
          runSpacing: SandikSpace.xxs,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.totalCostUpper, style: _etiketStili),
                Text(ayrinti,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tutar,
                    key: const ValueKey('alt-cubuk-toplam-tutar'),
                    // Tabular figür (numMedium): yazarken rakamlar zıplamasın.
                    // 20 pt (headlineMedium) + tabular: eski kartın ham
                    // 22 pt ham boyutu yerine token; düğmenin yanında
                    // okunur ama onunla yarışmaz (renk nötr, w600).
                    style: (context.t.headlineMedium ?? const TextStyle())
                        .copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: context.c.text90,
                    ),
                  ),
                ),
                if (tl != null)
                  Text(
                    tl,
                    key: const ValueKey('toplam-tl-karsiligi'),
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Alt çubuk toplamındaki TL satırının kuru; TRY'de ya da kur bilinmiyorken
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
      // Nötr ton (amber bütçesi, Ar-Ge 2026-11-12 #1): bu bir uyarı değil,
      // atanacak fiyatın bilgisi; yıldız/parıltı simgesi de "yapay zekâ"
      // gibi okunuyordu (unslop 2026-11-05 #5).
      color = context.c.text58;
      icon = Icons.sell_outlined;
      title = context.l10n.fiyatBirimBasina(
          '${qtyFormatter(maxDigits: 2).format(satis)} $_currency');
      subtitle = _kuyumcuFarkiSatiri(alis: _previewPrice!, satis: satis);
    } else if (_previewPrice != null) {
      final p = _previewPrice!;
      final fmt = qtyFormatter(maxDigits: 2);
      // Müşteri raporu 2 Kas 17:15 (#1): Bugün seçiliyken fiyat ZATEN
      // canlı kotasyondan gelir (`fiyatBul` Bugün'de tarihli kapanış
      // aramaz); kart yine de amber + yıldızla "Tarihli fiyat bulunamadı"
      // diyordu ve ilk varlığını ekleyen kişi bir şeyin ters gittiğini
      // sanıyordu. Bugün: nötr ton, doğru cümle. Uyarı tonu yalnız geçmiş
      // bir gün seçilip o günün kapanışı bulunamadığında (gerçek uyarı).
      // Başlık uygulamanın geri kalanı gibi ₺ ve birim adıyla ("/ lot",
      // "/ gr"), "TRY / birim" değil.
      final tutar =
          _currency == 'TRY' ? '₺${fmt.format(p)}' : '${fmt.format(p)} $_currency';
      final gecmisteBulunamadi = !_previewIsHistorical && !isToday;
      color = _previewIsHistorical
          ? context.c.gain
          : gecmisteBulunamadi
              ? context.c.amberText
              : context.c.text58;
      icon = _previewIsHistorical
          ? Icons.event_available_rounded
          : gecmisteBulunamadi
              ? Icons.info_outline_rounded
              : Icons.show_chart_rounded;
      title = _quantitySuffix.isEmpty
          ? tutar
          : context.l10n.fiyatBirimiyle(tutar, _quantitySuffix);
      // Hafta sonu seçildiyse gelen kapanış Cuma'nındır; metin seçilen
      // günü değil, fiyatın GERÇEK gününü söyler (emülatör testi #31).
      final islemGunu = haftaSonuKapanisGunu(_addedDate,
          yediGun: _type == AssetType.kripto);
      subtitle = isToday && !_previewIsHistorical
          ? context.l10n.pricePreviewToday
          : !_previewIsHistorical
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
                      fontWeight: FontWeight.w600,
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

  // ── İşlem tarihi çipleri ───────────────────────────────────────────────
  //
  // Varsayılan: bugün. Kullanıcı geriye dönük bir tarih seçerse ve alış
  // fiyatı boşsa, kaydederken o tarihin kapanış fiyatı otomatik atanır.
  //
  // 2026-11-11: tek "Bugün" çipi (dokununca takvim) yerine ortak
  // [TarihCipleri] — Bugün · Dün · son iş günü · Başka tarih. Geçmiş tarihli
  // kayıtların çoğu dün ya da son iş günüdür; takvim yalnız gerisi için.
  // Seçim aynı yoldan yazılır (`setDate` + önizleme), davranış değişmez.
  Widget _dateChip(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context.l10n.transactionDate),
        const SizedBox(height: SandikSpace.xs2),
        TarihCipleri(
          secili: _addedDate,
          onSecildi: (gun) {
            // Varsayılan tarih saatiyle gelir (`DateTime.now()`, hareket
            // listesinde "· 14:32"). Aynı güne dokunmak saati silmesin;
            // "Bugün"e dönüş de saati geri getirsin — eski tek çipte bugün
            // hiç yeniden yazılmıyordu.
            if (dayKey(gun) == dayKey(_addedDate)) return;
            final simdi = DateTime.now();
            _n.setDate(dayKey(gun) == dayKey(simdi) ? simdi : gun);
            _schedulePricePreview();
          },
          takvim: () => pickSandikDate(
            context,
            initialDate: _addedDate,
            helpText: context.l10n.transactionDate,
          ),
        ),
      ],
    );
  }
}

/// Formda beliren/kaybolan satır (toplam, ortalama maliyet, fiyat ipucu):
/// [child] varken yükseklikle açılır, `null` olunca kapanır (Ar-Ge
/// 2026-11-12 #3). Eskiden satır `SizedBox.shrink()`'ten tek karede
/// beliriyor, altındaki alanlar ~70 pt sıçrıyordu; yazarken odak kayıyordu.
///
/// Hareket uygulamanın tek katlanır bölüm hareketi [SandikAcilir]: süre ve
/// eğri orada, hareketi azalt'ta anlık. Kapanırken SON içerik solarak
/// kalır (boş kutu küçülmez — `SandikAcilir` gerekçesi). İlk kurulumda
/// içerik varsa hareket yok: düzenleme formu açılırken toplam yerinde
/// gelir, form zıplamaz.
class _Beliren extends StatefulWidget {
  const _Beliren({required this.child});

  final Widget? child;

  @override
  State<_Beliren> createState() => _BelirenState();
}

class _BelirenState extends State<_Beliren> {
  Widget? _son;

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) _son = widget.child;
    return SandikAcilir(
      acik: widget.child != null,
      child: _son ?? const SizedBox.shrink(),
    );
  }
}
