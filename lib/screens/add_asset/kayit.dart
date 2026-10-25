part of '../add_asset_screen.dart';

/// Kayıt yolu: hızlı/toplu giriş ve `_save` → `_kaydet`. Bölünme
/// 2026-10-24, davranış aynı.
extension _Kayit on _AddAssetScreenState {
  // ── Hızlı / Toplu Giriş ───────────────────────────────────────────────────
  //
  // Her satır bir varlık. Fiyat opsiyonel — girilmezse güncel fiyat çekilir.
  // Her satır parse edilir, önizleme gösterilir, onaylanınca toplu kaydedilir.
  //
  // Desteklenen formatlar:
  //   "100 dolar"                     → 100 USD (fiyatsız)
  //   "100 dolar 32 liradan"          → qty=100, price=32, USD
  //   "10 gram altın 4500 liradan"    → qty=10, price=4500
  //   "GARAN 500 adet 105 lira"       → ticker=GARAN, qty=500, price=105
  //   "10 gram altın"                 → qty=10, fiyat otomatik

  ParsedEntry? _parseLine(String raw) => parseQuickEntry(raw);

  void _showQuickEntrySheet() {
    final ctrl = TextEditingController();
    _klavyeyiKapat();
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      // Klavye + uzun önizleme sayfayı tepeye iterse durum çubuğunun
      // altına girmesin.
      useSafeArea: true,
      backgroundColor: context.c.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: SandikRadius.sheetTop),
      builder: (ctx) => _QuickEntrySheet(
        ctrl: ctrl,
        parseLine: _parseLine,
        onConfirmSingle: (entry) {
          Navigator.pop(ctx);
          _applyParsedEntry(entry);
        },
        // Toplu kayıt sayfanın düğmesinin İÇİNDE koşar (tek yükleniyor
        // davranışı, 2026-10-08): eskiden sayfa hemen kapanıyor, kayıtlar
        // arkada sürerken yalnızca alttaki "Ekle" dönüyordu. Sayfa iş
        // bitince kapanır, ardından ekran `true` ile kapanır (eski sinyal).
        // Hata: eskiden kimseye söylenmiyordu (yakalanmamış async hata);
        // şimdi sayfa kapanır ve hata gösterilir. Sayfa açık kalıp yeniden
        // denenmez — döngü yarıda kesildiyse ilk satırlar çoktan eklendi,
        // aynı listeyi yeniden kaydetmek onları çiftlerdi.
        onSaveBatch: (entries) async {
          bool kaydedildi;
          try {
            kaydedildi = await _saveBatch(entries);
          } on AssetLimitExceededException catch (e) {
            // Sınıra kadar olanlar eklendi; kalanı için paywall (genel hata
            // değil — paywall kapıları incelemesi, 2026-10-11).
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              await PaywallScreen.show(context,
                  source: 'asset_limit_${e.limit}');
            }
            return;
          } catch (e) {
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) showAppError(context, e);
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
          // Hızlı giriş de bir kayıttır — `_save()` ile aynı sinyali döndürür.
          if (kaydedildi && mounted) _kayitBitti(true);
        },
      ),
    );
  }

  /// Hızlı giriş türü de seçer: ızgara açıksa katlanır, yoksa yazılan
  /// miktar/fiyat gizli formda kalırdı.
  void _applyParsedEntry(ParsedEntry entry) {
    _yaz(_n.applyParsedEntry(entry));
    _n.turIzgarasi(acik: false);
  }

  /// `true` → kayıtlar eklendi (çağıran sayfayı ve ekranı kapatır);
  /// `false` → tek satır forma uygulandı, kayıt yok.
  Future<bool> _saveBatch(List<ParsedEntry> entries) async {
    // Sözlük döngüden ÖNCE çözülür: `context` async boşlukların ardında
    // kullanılamaz (`use_build_context_synchronously`), tür adı ise fiyat
    // çekiminden sonra gerekiyor.
    final l = context.l10n;
    if (entries.isEmpty) return false;
    if (entries.length == 1) {
      _applyParsedEntry(entries.first);
      return false;
    }
    final lookup = ref.read(addAssetPriceLookupProvider);
    _n.setSaving(true);
    try {
      for (final entry in entries) {
        String ticker = '';
        String assetName = '';
        String currency = entry.type.defaultCurrency;

        if (entry.type == AssetType.doviz && entry.subCategory != null) {
          final opt = dovizOptFor(entry.subCategory);
          ticker = opt.ticker;
          assetName = opt.name;
          currency = 'TRY';
        } else if (entry.type == AssetType.altin) {
          assetName = entry.subCategory ?? 'Altın';
        } else if (entry.type == AssetType.kripto && entry.subCategory != null) {
          // Fiyat sunucuda TL (kripto_fiyat); ikinci çevrim yok.
          ticker = kriptoSembolu(entry.subCategory!);
          assetName = entry.subCategory!;
          currency = 'TRY';
        }

        double price = entry.price;
        if (price == 0 && ticker.isNotEmpty) {
          try {
            final spot = await lookup.spot(ticker);
            if (spot != null && spot > 0) price = spot;
          } catch (_) {
            // Fiyat isteğe bağlı; çekilemezse 0 kalır, kullanıcı düzenler.
          }
        }

        if (assetName.isEmpty) {
          assetName = entry.subCategory ?? entry.type.labelOf(l);
        }

        await ref.read(portfolioProvider.notifier).addAsset(
              name: assetName,
              ticker: ticker,
              type: entry.type,
              quantity: entry.qty,
              purchasePrice: price,
              currency: currency,
              notes: '',
              isManualPrice: price > 0 && ticker.isEmpty,
              subCategory:
                  entry.type == AssetType.kripto ? null : entry.subCategory,
              unitType: entry.type == AssetType.altin ? 'gram' : 'piece',
              portfoyId: _hedefPortfoy,
              yol: 'hizli_metin',
            );
      }
    } finally {
      _n.setSaving(false);
    }
    return true;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  // ## Neden tek bir bayrak kaydın TAMAMINI kapsıyor (2026-09-23 denetimi F14)
  // Eskiden `saving` üç ayrı parçada açılıp kapanıyordu: fiyat çözümü
  // (`fiyatCoz` kendi `finally`'sinde bayrağı İNDİRİYORDU), ardından
  // korumasız şirket adı sorgusu, en son da insert. Ad sorgusu sürerken
  // "Ekle" yeniden etkinleşiyor, ikinci dokunuş ikinci bir `_save` başlatıyor
  // ve aynı varlık iki kez ekleniyordu. Artık bayrak doğrulamadan hemen
  // sonra, ilk `await`'ten ÖNCE eşzamanlı açılır ve kayıt bitene kadar
  // (başarıda ekran kapanana kadar) inmez; butonun `onPressed`'i de aynı
  // bayrağa bağlı. Fiyat bu yüzden `fiyatCoz` yerine doğrudan `fiyatBul` ile
  // çözülür — `fiyatCoz`'un bayrağı kendi indirmesi tam da açığın kaynağıydı.
  Future<void> _save() async {
    if (_saving) return;
    _n.kayitDenendi();
    if (!_formKey.currentState!.validate()) return;
    // Güncelleme geri dönüşü olmayan bir silme içerir: kayıttan ÖNCE sayıyla
    // sorulur. Onay `islem:` almaz — iş (fiyat çözümü + sil + ekle) formun
    // kaydet düğmesinde döner; `_kaydet` başarıda ekranı kapattığı için
    // diyalog içinde koşsaydı kapanan diyalog olurdu, ekran değil.
    if (_yenidenKur) {
      if (_onaySoruluyor) return; // diyalog açılırken ikinci dokunuş
      _onaySoruluyor = true;
      final bool onay;
      try {
        onay = await _yenidenKurOnayi();
      } finally {
        _onaySoruluyor = false;
      }
      if (!onay || !mounted || _saving) return;
    }
    _n.setSaving(true);
    var sonu = _KayitSonu.kaldi;
    try {
      sonu = await _kaydet();
    } finally {
      // Ekran kapandıysa bayrak açık kalır: kapanış animasyonu boyunca buton
      // yeniden basılabilir görünmesin. Dispose sonrası `ref` okunamaz.
      if (mounted && sonu != _KayitSonu.kapandi) _n.setSaving(false);
    }
    // Premium'a geçildiyse aynı form üzerinde yeniden dene. Eskiden önce
    // `Navigator.pop` ile form kapatılıp kayıt arka planda yeniden
    // başlatılıyordu; başarılı kayıt sonundaki ikinci `pop` bu kez ALTTAKİ
    // ekranı kapatabiliyordu. Yerinde denemek sonucu (`true`) da çağırana
    // ulaştırır, Portföy sekmesine geçiş çalışır.
    if (sonu == _KayitSonu.yenidenDene && mounted) {
      CrashReporter.arkaPlan(_save(), reason: 'add_asset_screen._save');
    }
  }

  /// `_save`'in gövdesi; `saving` bayrağı çağıran tarafından tutulur.
  Future<_KayitSonu> _kaydet() async {
    // Tutar kipinde adet hesaptır (`tutardanAdet`); alanın doğrulayıcısı
    // fiyatsız tutarı buraya bırakmaz.
    final qty = _etkinAdet!;
    var price = _parse(_price.text) ?? 0.0;
    // Eurobond: alan temiz %, kayıt kirli birim değer (kirli/100) — fiyat
    // servisi kotasyonuyla aynı ölçek. Sözleşme yoksa kimlik doğrulaması
    // buraya gelmeden durdurur; yine de çevrilemezse 0 kalır ve aşağıdaki
    // fiyat çözümü kotasyonu (zaten birim değer) atar — temiz % asla birim
    // değer diye yazılmaz.
    if (_s.isEurobond) price = _s.eurobondBirimFiyati(price) ?? 0.0;
    // Kullanıcının YAZDIĞI fiyat — aşağıdaki fiyat çözümü boş alanı o günün
    // kotasyonuyla doldurur; "maliyet bilinmiyor" işareti (0162) yalnız
    // kullanıcı bir değer girdiyse düşer.
    final fiyatGirildi = price > 0;
    // Tutar kipinde fiyat boşsa adet ÖNİZLEME fiyatına bölündü; kayıt aynı
    // fiyatı yazar ki adet × fiyat girilen tutarı tutsun (kayıt anında
    // yeniden çekilen kotasyon birkaç kuruş oynayabilirdi).
    var onizlemeFiyatiKullanildi = false;
    if (price == 0.0 && _tutarModu) {
      final birim = _tutarBirimFiyati;
      if (birim != null) {
        price = birim;
        onizlemeFiyatiKullanildi = true;
      }
    }

    final kimlik = _s.resolveIdentity(
      nameText: _name.text,
      tickerText: _ticker.text,
    );
    final ticker = kimlik.ticker;
    var assetName = kimlik.name;
    final manual = kimlik.manual;

    // ── Sepete ekleme modu: bulkCartProvider'a push, fiyat çekme yok ──
    if (widget.cartMode) {
      if (assetName.isEmpty) {
        assetName =
            ticker.isNotEmpty ? ticker : (_subCategory ?? _type.labelOf(context.l10n));
      }
      final item = BulkCartItem(
        id: widget.cartInitial?.id ?? _addAssetUuid.v4(),
        type: _type,
        name: assetName,
        ticker: ticker,
        quantity: qty,
        price: price,
        currency: _currency,
        subCategory: _subCategory,
        unitType: _unitType,
        isManualPrice: manual,
        addedDate: _addedDate,
        // Düzenleme satırı alım/satım yönünü KORUR: form yalnız alım
        // bilir; ekstreden gelen satış satırı düzenlenince alıma dönüp
        // pozisyonu şişirirdi (karar 5.4).
        satis: widget.cartInitial?.satis ?? false,
        // Ekran görüntüsünden gelen "maliyet sonra" işareti fiyat boş
        // kaldıkça durur; kullanıcı maliyeti girince düşer.
        maliyetSonra: price <= 0 && (widget.cartInitial?.maliyetSonra ?? false),
        yol: widget.cartInitial?.yol ?? 'toplu', // ölçüm: geldiği yol
      );
      final notifier = ref.read(bulkCartProvider.notifier);
      if (widget.cartInitial != null) {
        notifier.update(item);
      } else {
        notifier.add(item);
      }
      if (!mounted) return _KayitSonu.kaldi;
      Navigator.of(context).pop();
      return _KayitSonu.kapandi;
    }

    // ── Fiyat çek (alış fiyatı boşsa) ──────────────────────────────────────
    // Bugün seçildiyse güncel spot; geçmiş bir tarih seçildiyse o tarihin
    // kapanış fiyatı. Historical fetch başarısızsa spot'a fallback yapar.
    bool priceFromHistorical = onizlemeFiyatiKullanildi && _previewIsHistorical;
    // Kayıt sonrası alarm önerisi (2026-09-20): yeni varlık fiyat kaynağı
    // olan bir sembolse çağıran ekran "Alarm kur" eylemi gösterir.
    AlarmAdayi? alarmAdayi;
    bool priceFallbackToSpot = false;
    if (price == 0.0 && ticker.isNotEmpty) {
      final sonuc = await fiyatBul(
        lookup: ref.read(addAssetPriceLookupProvider),
        ticker: ticker,
        date: _addedDate,
        // Yalnız yeni kayıtta dolu: boş fiyatlı bugünkü altın/döviz alımının
        // maliyeti satış fiyatından (`maliyetSatisFiyati`, 2026-10-24).
        satisParaBirimi: _n.satisParaBirimi,
      );
      if (!mounted) return _KayitSonu.kaldi;
      price = sonuc.satis ?? sonuc.price ?? 0.0;
      priceFromHistorical = sonuc.historical;
      priceFallbackToSpot = sonuc.fallbackToSpot;
    }

    // ── Şirket adını Yahoo'dan çek (bilinmiyorsa) ──────────────────────────
    if (assetName.isEmpty &&
        ticker.isNotEmpty &&
        !ticker.startsWith('TEFAS:')) {
      try {
        final ad = await ref.read(addAssetPriceLookupProvider).companyName(ticker);
        if (!mounted) return _KayitSonu.kaldi;
        if (ad != null) assetName = ad;
      } catch (_) {
        // Ad kozmetik; bulunamazsa aşağıda sembol ad olur.
      }
    }

    if (assetName.isEmpty) {
      assetName = ticker.isNotEmpty ? ticker : context.l10n.assetFallbackName;
    }

    try {
      if (_yenidenKur) {
        final notifier = ref.read(portfolioProvider.notifier);
        await notifier.pozisyonuYenidenKur(
          widget.yerineGecenLotlar!,
          () => notifier.addAsset(
            name: assetName,
            ticker: ticker,
            type: _type,
            quantity: qty,
            purchasePrice: price,
            currency: _currency,
            notes: _notes.text.trim(),
            isManualPrice: manual,
            subCategory: _subCategory,
            unitType: _unitType,
            addedDate: _addedDate,
            commission: _parse(_commission.text) ?? 0,
            // Eski pozisyonun portföyünde kalır (karışık pozisyon bu kipe
            // hiç gelmez, `varlikGuncellenebilir`).
            portfoyId: widget.editingAsset!.portfoyId,
          ),
        );
      } else if (_isEditing) {
        final a = widget.editingAsset!;
        a
          ..name = assetName
          ..ticker = ticker
          ..type = _type
          ..subCategory = _subCategory
          ..unitType = _unitType
          ..quantity = qty
          ..purchasePrice = price
          ..currency = _currency
          ..notes = _notes.text.trim()
          ..isManualPrice = manual
          ..commission = _parse(_commission.text) ?? 0;
        // Maliyeti girildi: "bilgi eksik" listesinden düşer. `null` (işaret
        // hiç olmamış) olduğu gibi kalır — sunucuya anahtar yazılmaz.
        if (a.maliyetBilinmiyor == true && fiyatGirildi) {
          a.maliyetBilinmiyor = false;
        }
        // addedDate final — direkt set edilemez; kullanıcı düzenlemede tarih
        // değiştirdiyse Asset'i yeniden inşa edip provider'a yolla.
        if (a.addedDate != _addedDate) {
          final updated = Asset(
            id: a.id,
            userId: a.userId,
            name: a.name,
            ticker: a.ticker,
            type: a.type,
            quantity: a.quantity,
            purchasePrice: a.purchasePrice,
            currency: a.currency,
            notes: a.notes,
            subCategory: a.subCategory,
            unitType: a.unitType,
            purchaseFxRate: a.purchaseFxRate,
            currentPrice: a.currentPrice,
            lastUpdated: a.lastUpdated,
            addedDate: _addedDate,
            isManualPrice: a.isManualPrice,
            kind: a.kind,
            refAssetId: a.refAssetId,
            sellPrice: a.sellPrice,
            sellFxRate: a.sellFxRate,
            commission: a.commission,
            // Bu kopya kaydın TÜM alanlarını taşımalı; eksik bırakılan alan
            // tarih düzenlemesinde sessizce sıfırlanır (temettü tutarı
            // böyle kaybolurdu).
            dividendAmount: a.dividendAmount,
            deletedCount: a.deletedCount,
            // Sözleşme bağı, giriş anı ve portföy de taşınır (2026-10-10):
            // eksik kopya düzenlemede lotu bellekte sözleşmesiz/Ana'da
            // bırakıyordu (sunucuda gövdede yoklar, değişmezlerdi).
            sozlesmeId: a.sozlesmeId,
            createdAt: a.createdAt,
            portfoyId: a.portfoyId,
            maliyetBilinmiyor: a.maliyetBilinmiyor,
          );
          await ref.read(portfolioProvider.notifier).updateAsset(updated);
        } else {
          await ref.read(portfolioProvider.notifier).updateAsset(a);
        }
      } else {
        // Eurobond alarmı yok: sunucu alarm denetimi `EUROBOND:` sembolünü
        // fiyatlamaz ve fiyat birim değerdir (kirli/100) — kurulan alarm
        // hiç tetiklenmezdi.
        final alarmSembol = manual || _s.isEurobond
            ? null
            : alarmSembolu(ticker, _subCategory);
        if (alarmSembol != null && price > 0) {
          alarmAdayi = AlarmAdayi(alarmSembol, assetName, price);
        }
        await ref.read(portfolioProvider.notifier).addAsset(
              name: assetName,
              ticker: ticker,
              type: _type,
              quantity: qty,
              purchasePrice: price,
              currency: _currency,
              notes: _notes.text.trim(),
              isManualPrice: manual,
              subCategory: _subCategory,
              unitType: _unitType,
              addedDate: _addedDate,
              commission: _parse(_commission.text) ?? 0,
              portfoyId: _hedefPortfoy,
              yol: widget.ekleYolu ?? 'form',
            );
        // Kipe geçiş değil KAYIT sayılır: geçip vazgeçen merak etmiştir,
        // kaydeden kullanmıştır. 19 Kasım kararı "kullanılıyor mu"yu sorar.
        // Tutar gönderilmez, yalnız özellik kodu.
        if (_tutarModu) OzellikOlcumu.say(Ozellik.tutarKipi);
      }
    } on AssetLimitExceededException catch (e) {
      if (!mounted) return _KayitSonu.kaldi;
      // Analytics ve paywall provider tarafından zaten log'landı. Paywall
      // açıkken bayrak açık kalır; form arkada kilitli durur.
      final upgraded = await PaywallScreen.show(
        context,
        source: 'asset_limit_${e.limit}',
      );
      // Kullanıcı premium'a geçti — `_save` bayrağı indirip yeniden dener.
      return upgraded == true ? _KayitSonu.yenidenDene : _KayitSonu.kaldi;
    } catch (e, st) {
      // ## Neden genel bir catch
      // YOKTU. `onPressed: _save` bir `Future` döndürüyor ve kimse onu
      // beklemiyor: kayıt sırasında ağ koparsa (`ClientException`,
      // `TimeoutException`) hata `runZonedGuarded` handler'ına düşüp
      // Crashlytics'te ÇÖKME olarak kaydediliyordu — üretim raporu
      // 2026-09-19: `IOClient.send → DbLogger.log →
      // SupabaseService.updateAsset`.
      //
      // Kullanıcı tarafı daha kötüydü: hiçbir şey olmuyordu. Form açık
      // kalıyor, "kaydediliyor" durumu sıfırlanıyor, ama varlık
      // KAYDEDİLMEMİŞ oluyordu ve bunu söyleyen tek satır yoktu.
      //
      // `return` şart: aşağıdaki `Navigator.pop(context, true)` çağıran
      // ekrana "kayıt oldu" sinyali gönderiyor. Yutup devam etmek
      // başarısız kaydı başarı gibi gösterirdi.
      CrashReporter.report(e, st, reason: 'AddAssetScreen.save');
      if (!mounted) return _KayitSonu.kaldi;
      sandikSnack(context, friendlyError(e), kind: SandikSnackKind.error);
      return _KayitSonu.kaldi;
    }
    if (!mounted) return _KayitSonu.kaldi;
    // Tarihli fiyat çekimi yapıldıysa kullanıcıya bildir — atanan değer
    // net görünsün, "güncel geldi sandım" hissi olmasın.
    if (priceFromHistorical || priceFallbackToSpot) {
      final fmt = qtyFormatter(maxDigits: 2);
      final dateStr = DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate);
      final islemGunu = haftaSonuKapanisGunu(_addedDate,
          yediGun: _type == AssetType.kripto);
      final fiyatStr = '${fmt.format(price)} $_currency';
      final msg = priceFromHistorical
          ? (islemGunu != null
              ? context.l10n.priceAssignedLastTradingClose(
                  DateFormat('d MMM', context.tarihDili).format(islemGunu),
                  fiyatStr)
              : context.l10n.priceAssignedClose(dateStr, fiyatStr))
          : '$dateStr için geçmiş fiyat bulunamadı, güncel fiyat '
              '${fmt.format(price)} $_currency atandı';
      // Tarihli kapanış bulundu → başarı; bulunamadı → uyarı zemini.
      sandikSnack(
        context,
        msg,
        kind: priceFromHistorical
            ? SandikSnackKind.success
            : SandikSnackKind.warning,
        duration: const Duration(seconds: 4),
      );
    }
    // `true` ya da `AlarmAdayi`: çağıran (MainNavigationScreen) bunu
    // "kayıt oldu" sinyali olarak kullanıp Portföy sekmesine geçer; aday
    // geldiyse ayrıca "Alarm kur" eylemli bir bildirim gösterir. Sonuçsuz
    // `pop` edilirse kullanıcı hangi sekmedeyse orada kalır ve eklediği
    // varlığı göremez.
    _kayitBitti(alarmAdayi ?? true);
    return _KayitSonu.kapandi;
  }
}

extension on _AddAssetScreenState {
  /// Kayıt öncesi son söz: kaç hareketin gideceği ve yerine ne kalacağı.
  Future<bool> _yenidenKurOnayi() {
    final l = context.l10n;
    return showSandikConfirm(
      context: context,
      title: l.varlikGuncelleOnayBaslik(widget.yerineGecenLotlar!.length),
      message: l.varlikGuncelleOnayGovde(
          widget.editingAsset!.name, widget.yerineGecenLotlar!.length),
      confirmLabel: l.update,
      cancelLabel: l.cancelWord,
      destructive: true,
    );
  }
}

/// `_kaydet`'in sonucu: bayrağın inip inmeyeceğine ve yeniden denemeye
/// `_save` karar verir (2026-09-23 denetimi F14).
enum _KayitSonu { kapandi, kaldi, yenidenDene }
