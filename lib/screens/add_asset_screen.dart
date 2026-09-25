import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/asset_categories.dart';
import '../models/altin_kisayollari.dart';
import '../providers/add_asset_form_provider.dart';
import '../providers/bulk_cart_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../services/crash_reporter.dart';
import '../utils/friendly_error.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/h_scroll_with_fade.dart';
import 'paywall_screen.dart';
import 'bulk_add_asset_screen.dart';
import '../widgets/alarm_kur_sheet.dart' show AlarmAdayi, alarmSembolu;
import '../widgets/custom_loading_indicator.dart';
import '../widgets/tour_anchor.dart';
import '../l10n/l10n.dart';

const _addAssetUuid = Uuid();

// Klavye kuralı (kullanıcı, 2026-09-25): "klavye otomatik açılmamalı,
// textbox'a tıklayınca açmalı, dışarı tıklandığında kapatılabilmeli."
// Bu yüzden ekranda ve seçici/hızlı giriş sayfalarında `autofocus` yok;
// her alan `onTapOutside` ile odağı bırakır (Flutter'ın varsayılanı
// dokunmatikte dışarı dokunuşu yok sayar, yalnızca fareyle kapatır).
// Alt sayfa açılmadan önce de odak bırakılır: kapanan sayfa odağı önceki
// alana geri verdiğinde klavye kendiliğinden yeniden açılmasın.
void _klavyeyiKapat([PointerDownEvent? _]) =>
    FocusManager.instance.primaryFocus?.unfocus();

// Döviz sabitleri, hızlı giriş modeli ve durum makinesi
// `providers/add_asset_form_provider.dart`'ta (Faz 3.10).

// ─── Decimal formatter ────────────────────────────────────────────────────────

class _DecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    // Allow digits, comma, dot. Only one decimal separator.
    final filtered = next.text.replaceAll(RegExp(r'[^\d.,]'), '');
    if (filtered == next.text) return next;
    return next.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class AddAssetScreen extends ConsumerStatefulWidget {
  final Asset? editingAsset;

  /// Sepete ekleme modu: kaydetmek yerine bulkCartProvider'a push edilir.
  final bool cartMode;

  /// Sepetten düzenleme: mevcut sepet öğesinin değerlerini prefill için.
  final BulkCartItem? cartInitial;

  /// Karşılaştırma ekranından gelen ön seçim — henüz sahip OLUNMAYAN bir
  /// varlık için tür/ticker/ad hazır gelir, kullanıcı yalnızca miktar,
  /// fiyat ve tarih girer.
  ///
  /// [editingAsset] ve [cartInitial]'dan farkı: onlar var olan bir kaydı
  /// düzenler, bu ise YENİ kayıt için yalnızca kimlik alanlarını doldurur.
  final String? prefillTicker;
  final String? prefillName;
  final AssetType? prefillType;

  const AddAssetScreen({
    super.key,
    this.editingAsset,
    this.cartMode = false,
    this.cartInitial,
    this.prefillTicker,
    this.prefillName,
    this.prefillType,
  });

  @override
  ConsumerState<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends ConsumerState<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _ticker;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _notes;
  late final TextEditingController _commission;

  // Durum makinesi `addAssetFormProvider`'da (Faz 3.10). Aşağıdaki getter'lar
  // eski alan adlarını korur ki 2000 satırlık widget ağacı dokunulmadan
  // okumaya devam etsin; YAZMA yalnızca `_n` (notifier) üzerinden yapılır.
  late final AddAssetFormArgs _args = AddAssetFormArgs(
    editingAsset: widget.editingAsset,
    cartInitial: widget.cartInitial,
    prefillTicker: widget.prefillTicker,
    prefillType: widget.prefillType,
  );
  AddAssetFormState get _s => ref.read(addAssetFormProvider(_args));
  AddAssetFormNotifier get _n =>
      ref.read(addAssetFormProvider(_args).notifier);

  AssetType get _type => _s.type;
  String? get _subCategory => _s.subCategory;
  String get _unitType => _s.unitType;
  String get _currency => _s.currency;
  DateTime get _addedDate => _s.addedDate;
  bool get _saving => _s.saving;
  double? get _previewPrice => _s.previewPrice;
  bool get _previewLoading => _s.previewLoading;
  bool get _previewIsHistorical => _s.previewIsHistorical;
  String? get _bist100SelectedTicker => _s.bist100Ticker;
  TefasFund? get _selectedFund => _s.selectedFund;
  bool get _notesExpanded => _s.notesExpanded;

  static const _currencies = ['TRY', 'USD', 'EUR', 'GBP'];
  bool get _isEditing => widget.editingAsset != null;
  bool get _isBist100 => _s.isBist100;
  bool get _isFon => _s.isFon;
  bool get _isDoviz => _s.isDoviz;

  @override
  void initState() {
    super.initState();
    final a = widget.editingAsset;
    final c = widget.cartInitial;

    // Prefill (karşılaştırma ekranından) en SONDA gelir: var olan bir kayıt
    // düzenleniyorsa onun değerleri her zaman kazanır.
    final initName = a?.name ?? c?.name ?? widget.prefillName ?? '';
    final initTicker = a?.ticker ?? c?.ticker ?? widget.prefillTicker ?? '';
    final initQty = a?.quantity ?? c?.quantity ?? 0;
    final initPrice = a?.purchasePrice ?? c?.price ?? 0;

    _name = TextEditingController(text: initName);
    _ticker = TextEditingController(text: initTicker);
    _quantity = TextEditingController(text: initQty > 0 ? _fmt(initQty) : '');
    _price = TextEditingController(text: initPrice > 0 ? _fmt(initPrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _commission = TextEditingController(
        text: (a?.commission ?? 0) > 0 ? _fmt(a!.commission) : '');
    // Form açılışında preview'ı bir kere tetikle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPricePreview());
  }

  @override
  void dispose() {
    for (final c in [_name, _ticker, _quantity, _price, _notes, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Bir geçişin döndürdüğü metin alanı yazımlarını controller'lara uygular.
  void _yaz(AlanYazimi y) {
    if (y.name != null) _name.text = y.name!;
    if (y.ticker != null) _ticker.text = y.ticker!;
    if (y.quantity != null) _quantity.text = y.quantity!;
    if (y.price != null) _price.text = y.price!;
  }

  // ── Preview: seçili varlık + tarih için tahmini birim fiyat ──────────────
  String? _resolveTickerForPreview() => _s.resolveTicker(_ticker.text);

  void _schedulePricePreview() => _n.schedulePreview(
        userPrice: _parse(_price.text),
        tickerText: _ticker.text,
      );

  Future<void> _refreshPricePreview() {
    if (!mounted) return Future.value();
    return _n.refreshPreview(
      userPrice: _parse(_price.text),
      tickerText: _ticker.text,
    );
  }

  String _fmt(double v) => AddAssetFormNotifier.fmtInput(v);

  double? _parse(String text) {
    // Türkçede `.` BİNLİK ayracıdır. Eski hâli `replaceAll(',', '.')` idi ve
    // "1.000" girdisini 1.0 olarak okuyordu; kullanıcı 1000 adet yazıp
    // portföyüne 1 adet kaydediyordu.
    final val = parseTrNumber(text);
    if (val == null) return null;
    // Aşırı büyük değerleri engelle (Simetrik UI için limit)
    if (val > 1000000000000) return 999999999999;
    return val;
  }

  String get _quantitySuffix => _s.quantitySuffix;
  List<String> get _quantityPresets => _s.quantityPresets;

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: context.t.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.c.text58,
        ),
      );

  /// Alan etiketi. Tek satır + kısaltma **varsayılan**: bu etiketler dar
  /// kolonlarda (Miktar/Fiyat yan yana) ve büyük metin ayarında taşıyordu.
  /// Çağıran ayrıca `Flexible` ile sarmalı — `overflow` yalnızca kısıt
  /// verilmişse iş görür.
  Widget _fieldLabel(String text) => Text(
        text,
        style: context.t.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.c.text90,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Toplam maliyet, önizleme kartı, preset çipleri ve not rozeti metin
  /// alanlarını okur; eski kod her tuş vuruşunda tüm ekranı yeniden kuruyordu.
  /// Controller'lar zaten `Listenable`: tek dinleyiciyle aynı yeniden çizim.
  late final Listenable _metinler =
      Listenable.merge([_quantity, _price, _commission, _notes]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Durum değişimi bu ekranı yeniden kurar; getter'lar `ref.read` ile aynı
    // değeri okur.
    ref.watch(addAssetFormProvider(_args));

    final saveLabel = widget.cartMode
        ? (widget.cartInitial != null ? context.l10n.save : 'Sepete Ekle')
        : (_isEditing ? context.l10n.update : context.l10n.add);
    final title = widget.cartMode
        ? (widget.cartInitial != null ? 'Sepette Düzenle' : 'Sepete Ekle')
        : (_isEditing ? context.l10n.editAsset : context.l10n.addAssetTitle);

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        titleWidget: Text(
          title,
          style: context.t.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: context.c.text90),
        ),
        actions: [
          if (!_isEditing && !widget.cartMode) ...[
            TourAnchor(
              target: TourTarget.topluEkle,
              child: IconButton(
              tooltip: context.l10n.bulkAdd,
              icon: Icon(Icons.playlist_add_rounded, color: context.c.text58),
              // Toplu ekleme başarıyla bittiğinde `true` döner; o zaman bu
              // ekran da kapanır ve kullanıcı portföye ulaşır. Aksi halde
              // arkada boş kalan bu formda mahsur kalıyordu.
              onPressed: () async {
                final added = await pushGuarded<bool>(
                  context,
                  adaptiveRoute(builder: (_) => const BulkAddAssetScreen()),
                );
                if (added == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              ),
            ),
            TourAnchor(
              target: TourTarget.hizliGiris,
              child: IconButton(
                tooltip: context.l10n.quickEntryVoice,
                icon: Icon(Icons.mic_none_rounded, color: context.c.text58),
                onPressed: _showQuickEntrySheet,
              ),
            ),
          ],
        ],
      ),
      body: ListenableBuilder(
        listenable: _metinler,
        builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _klavyeyiKapat,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 4, SandikSpace.screenH(context), 24),
                  children: [
                    _sectionLabel(context.l10n.assetType),
                    const SizedBox(height: 10),
                    _typeSelector(cs),
                    const SizedBox(height: 22),

                    // ── Kimlik: Bağlama göre TEK giriş alanı ──────────────
                    _sectionLabel(_identityLabel()),
                    const SizedBox(height: 10),
                    _identitySection(cs),
                    const SizedBox(height: 22),

                    // ── Miktar + Fiyat yan yana ───────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _quantityBlock(cs)),
                        const SizedBox(width: 12),
                        Expanded(child: _priceBlock(cs)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _quantityPresetsRow(cs),
                    const SizedBox(height: 20),

                    // ── Toplam maliyet hero card ─────────────────────────
                    _totalHero(cs),
                    const SizedBox(height: 10),

                    // ── Tahmini birim fiyat preview ──────────────────────
                    _pricePreviewCard(cs),

                    // ── İşlem tarihi (chip) ──────────────────────────────
                    _dateChip(cs),
                    const SizedBox(height: 16),

                    // ── Komisyon / masraf ────────────────────────────────
                    _commissionBlock(cs),
                    const SizedBox(height: 16),

                    // ── Notlar (collapsible) ─────────────────────────────
                    _notesCollapsible(cs),
                  ],
                ),
              ),
              _stickyBottomBar(saveLabel),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ── Bağlama göre "kimlik" alanının etiketi ─────────────────────────────────
  String _identityLabel() {
    if (_isBist100 || _type == AssetType.hisse) return context.l10n.identityStock;
    if (_isFon) return context.l10n.identityFund;
    if (_type == AssetType.altin) return context.l10n.identityGoldKind;
    if (_isDoviz) return context.l10n.identityCurrency;
    if (_type == AssetType.emtia) return context.l10n.identityCommodity;
    return context.l10n.assetFallbackName;
  }

  // ── Kimlik bölümü: hisse/fon → picker; altın → chip grid; döviz → 4 kart
  Widget _identitySection(ColorScheme cs) {
    if (_type == AssetType.hisse) return _stockIdentityBlock(cs);
    if (_isFon) return _tefasSelectorField(cs);
    if (_type == AssetType.altin) return _goldChipGrid(cs);
    if (_isDoviz) return _dovizSelector(cs);
    // Emtia / Diğer — manuel ad + opsiyonel sembol
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

  // ── Hisse: birleşik "BIST100'den seç veya sembol yaz" bloğu ────────────────
  //
  // BIST100 seçilirse subCategory = "BIST 100 Hisseleri" yazılır (data korunur).
  // Manuel sembol → subCategory = "Diğer Hisseler".
  Widget _stockIdentityBlock(ColorScheme cs) {
    return Column(
      children: [
        _bist100SelectorField(cs),
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
          hint: context.l10n.symbolHint,
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

  // ── Altın: seçim alanı + kısayol çipleri ─────────────────────────────────────
  //
  // 2026-09-25: 16 tür tek çip ızgarasında ekranı dolduruyordu. Kullanıcının
  // üç alternatif arasından seçtiği düzen (C): hisse/fon seçicisiyle aynı
  // alan (tümü aramalı, gruplu alt sayfada) + altında 5 kısayol. Kısayolların
  // kuralı `altinKisayollari`'nda (portföydeki türler, 5'e popülerle tamamla).
  Widget _goldChipGrid(ColorScheme cs) {
    final secili = _seciliAltin;
    final kisayollar = altinKisayollari(
        ref.watch(portfolioProvider).valueOrNull?.assets ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: secili == null
              ? context.l10n.pickGoldTap
              : context.l10n.goldSelectedSemantics(secili.label),
          child: GestureDetector(
            onTap: _showGoldPicker,
            child: _selectorContainer(
              cs: cs,
              hasValue: secili != null,
              hasError: false,
              badgeText: secili == null ? null : _altinBirimi(secili),
              mainText: secili?.label ?? context.l10n.pickGoldTap,
              color: AssetType.altin.color,
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.smd),
        Text(context.l10n.goldQuickPick,
            style: context.t.bodySmall?.copyWith(color: context.c.text36)),
        const SizedBox(height: SandikSpace.sm),
        Wrap(
          spacing: SandikSpace.sm,
          runSpacing: SandikSpace.sm,
          children: [for (final g in kisayollar) _goldChip(g, g == secili)],
        ),
      ],
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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

  Widget _goldChip(GoldSubCategory g, bool selected) {
    // Diğer çipler gibi (tür, döviz, miktar): ekran okuyucu 'düğme' ve
    // 'seçili' bilgisini Semantics olmadan alamaz (Faz 2.13).
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.goldSemantics(g.label),
      child: GestureDetector(
        onTap: () => _selectGold(g),
        child: AnimatedContainer(
          duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md2, vertical: SandikSpace.sm2),
          decoration: BoxDecoration(
            color: selected
                ? AssetType.altin.color.withValues(alpha: 0.18)
                : context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: selected ? AssetType.altin.color : context.c.overlay,
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
                  color: selected ? AssetType.altin.color : context.c.text58),
              const SizedBox(width: SandikSpace.xs2),
              Text(g.label,
                  style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? context.c.text90 : context.c.text58)),
            ],
          ),
        ),
      ),
    );
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

  // ── Fiyat bloğu (para birimi dropdown right-side) ──────────────────────────
  Widget _priceBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bu blok "Miktar" ile aynı Row'da `Expanded` içinde duruyor, yani
        // ekranın ~yarısı kadar yer var. "Alış Fiyatı · opsiyonel" 375pt'de
        // 138px taşıyordu — NORMAL metin boyutunda, büyük fontta değil.
        Row(
          children: [
            Flexible(child: _fieldLabel(context.l10n.purchasePrice)),
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
          controller: _price,
          hint: context.l10n.auto,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) =>
              v != null && v.trim().isNotEmpty && _parse(v) == null
                  ? context.l10n.invalid
                  : null,
          onChanged: (_) => _schedulePricePreview(),
          suffix: _isDoviz ? null : _inlineCurrencyPicker(),
        ),
      ],
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
              Icon(Icons.arrow_drop_down, color: context.c.amberText, size: 18),
          items: _currencies
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
    final price = _parse(_price.text);
    final isPriceEmpty =
        _price.text.trim().isEmpty || (price != null && price == 0);

    // Miktar yoksa hiçbir şey gösterme
    if (qty == null || qty <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
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
          ? 'Alış fiyatı boş — kaydederken güncel piyasa fiyatı otomatik atanacak.'
          : 'Alış fiyatı boş — ${DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate)} '
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
                Text('${_fmt(qty)} × ${_fmt(price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall
                        ?.copyWith(color: context.c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.md),
          Flexible(
            child: FittedBox(
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
          ),
        ],
      ),
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
      subtitle = _previewIsHistorical
          ? '$dateLabel kapanışı — kayıtta bu fiyat kullanılacak'
          : 'Tarihli fiyat bulunamadı — güncel piyasa fiyatı kullanılacak';
    } else {
      color = context.c.loss.withValues(alpha: 0.8);
      icon = Icons.help_outline_rounded;
      title = 'Fiyat bulunamadı';
      subtitle = 'İnternet yok ya da bu sembol için veri gelmedi — '
          'alış fiyatını manuel girmek isteyebilirsin';
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

  // ── Notlar collapsible ─────────────────────────────────────────────────────
  Widget _notesCollapsible(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            onTap: _n.toggleNotes,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: context.c.text58),
                  const SizedBox(width: 10),
                  Text(context.l10n.addNote,
                      style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.c.text90)),
                  const Spacer(),
                  if (_notes.text.isNotEmpty && !_notesExpanded)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.c.amberFill,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Icon(
                      _notesExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: context.c.text58,
                      size: 20),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: SandikMotion.state,
            firstCurve: SandikMotion.enter,
            secondCurve: SandikMotion.enter,
            sizeCurve: SandikMotion.move,
            crossFadeState: _notesExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextFormField(
                controller: _notes,
                style: context.t.titleMedium?.copyWith(color: context.c.text90),
                maxLines: 3,
                onTapOutside: _klavyeyiKapat,
                decoration: context.inputDecoration(context.l10n.notesHint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky bottom CTA ──────────────────────────────────────────────────────
  Widget _stickyBottomBar(String saveLabel) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: context.c.background,
          border: Border(
            top: BorderSide(color: context.c.overlay, width: 1),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill,
              foregroundColor: context.c.onAmber,
              disabledBackgroundColor:
                  context.c.amberFill.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SandikRadius.md)),
              elevation: 0,
            ),
            child: _saving
                ? const CustomLoadingIndicator(size: 22)
                : Text(
                    saveLabel,
                    style: context.t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Ortak input builder (Sandik marka) ─────────────────────────────────────
  Widget _brandInput({
    required TextEditingController controller,
    required String hint,
    String? suffixText,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      style: context.t.bodyLarge
          ?.copyWith(color: context.c.text90, fontWeight: FontWeight.w500),
      decoration: context.inputDecoration(hint).copyWith(
            suffixText: suffixText,
            suffixStyle: context.t.titleSmall?.copyWith(
                color: context.c.text58, fontWeight: FontWeight.w600),
            suffixIcon: suffix,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 60, minHeight: 40),
          ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      validator: validator,
      onChanged: onChanged,
      onTapOutside: _klavyeyiKapat,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // ── Varlık türü seçici (Sandik brand) ──────────────────────────────────────

  Widget _typeSelector(ColorScheme cs) {
    // Vadeli mevduat türü 2026-09-14'te kaldırıldı (hiç yayına çıkmamıştı,
    // ayrı form + lokal faiz motoru bakım yükü getiriyordu); seçici artık
    // enum'un tamamını gösterir.
    const types = AssetType.values;
    return HScrollWithFade(
      fadeColor: context.c.background,
      child: Row(
        children: types.map((t) {
          final selected = _type == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            // Semantics: çip yalnızca görsel; ekran okuyucu "seçili" ve
            // "düğme" bilgisini yoksa alamaz (Faz 2.13).
            child: Semantics(
              button: true,
              selected: selected,
              label: context.l10n.assetTypeSemantics(t.labelOf(context.l10n)),
              child: GestureDetector(
              onTap: () async {
                _yaz(_n.selectType(t));
                _schedulePricePreview();
              },
              child: AnimatedContainer(
                duration: SandikMotion.stateOf(context),
                curve: SandikMotion.enter,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? t.color.withValues(alpha: 0.18)
                      : context.c.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: selected ? t.color : context.c.overlay,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: t.color.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: -6,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon,
                        size: 18, color: selected ? t.color : context.c.text58),
                    const SizedBox(width: 8),
                    Text(t.labelOf(context.l10n),
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? context.c.text90 : context.c.text58,
                        )),
                  ],
                ),
              ),
            )),
          );
        }).toList(),
      ),
    );
  }

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
              child: GestureDetector(
              onTap: () {
                _yaz(_n.selectDoviz(opt));
                _schedulePricePreview();
              },
              child: AnimatedContainer(
                duration:
                    SandikMotion.of(context, const Duration(milliseconds: 160)),
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
                        color:
                            selected ? AssetType.doviz.color : context.c.text90,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      opt.label,
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? AssetType.doviz.color : context.c.text58,
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
              child: GestureDetector(
              onTap: () => _quantity.text = v,
              child: AnimatedContainer(
                duration:
                    SandikMotion.of(context, const Duration(milliseconds: 140)),
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
                      AddAssetFormState.unitLabel(_unitType),
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: selected
                            ? context.c.amberFill.withValues(alpha: 0.75)
                            : context.c.text36,
                      ),
                    ),
                  ],
                ),
              ),
            )),
          );
        }).toList(),
      ),
    );
  }

  // ── BIST100 seçici ─────────────────────────────────────────────────────────

  Widget _bist100SelectorField(ColorScheme cs) {
    final selectedName = _bist100SelectedTicker != null
        ? bist100StocksMap[_bist100SelectedTicker!] ?? _bist100SelectedTicker!
        : null;
    final ticker = _bist100SelectedTicker?.replaceAll('.IS', '');

    return FormField<String>(
      validator: (_) => _isBist100 && _bist100SelectedTicker == null
          ? context.l10n.pickStockPrompt
          : null,
      builder: (state) => Semantics(
        button: true,
        label: selectedName == null
            ? context.l10n.pickStock
            : 'Seçili hisse: $selectedName. Değiştirmek için çift dokun.',
        child: GestureDetector(
        onTap: _showBist100Picker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _bist100SelectedTicker != null,
          hasError: state.hasError,
          badgeText: ticker,
          mainText: selectedName ?? context.l10n.pickStockTap,
          color: AssetType.hisse.color,
        ),
      )),
    );
  }

  void _showBist100Picker() {
    _klavyeyiKapat();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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

  Widget _tefasSelectorField(ColorScheme cs) {
    return FormField<String>(
      validator: (_) =>
          _isFon && _selectedFund == null ? context.l10n.pickFundPrompt : null,
      builder: (state) => Semantics(
        button: true,
        label: _selectedFund == null
            ? context.l10n.pickFund
            : 'Seçili fon: ${_selectedFund!.name}. Değiştirmek için çift dokun.',
        child: GestureDetector(
        onTap: _showTefasPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _selectedFund != null,
          hasError: state.hasError,
          badgeText: _selectedFund?.code,
          mainText: _selectedFund?.name ?? context.l10n.pickFundTap,
          color: AssetType.fon.color,
        ),
      )),
    );
  }

  void _showTefasPicker() {
    _klavyeyiKapat();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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

  // ── Shared selector container ──────────────────────────────────────────────

  Widget _selectorContainer({
    required ColorScheme cs,
    required bool hasValue,
    required bool hasError,
    required String? badgeText,
    required String mainText,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: hasError
              ? context.c.loss
              : (hasValue ? color : context.c.overlay),
          width: hasValue ? 1.4 : 1,
        ),
        boxShadow: hasValue
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 14,
                  spreadRadius: -6,
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
              child: Text(badgeText,
                  style: context.t.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
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
          Icon(Icons.search_rounded, size: 18, color: context.c.text58),
        ],
      ),
    );
  }

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _QuickEntrySheet(
        ctrl: ctrl,
        parseLine: _parseLine,
        onConfirmSingle: (entry) {
          Navigator.pop(ctx);
          _applyParsedEntry(entry);
        },
        onSaveBatch: (entries) async {
          Navigator.pop(ctx);
          await _saveBatch(entries);
        },
      ),
    );
  }

  void _applyParsedEntry(ParsedEntry entry) =>
      _yaz(_n.applyParsedEntry(entry));

  Future<void> _saveBatch(List<ParsedEntry> entries) async {
    // Sözlük döngüden ÖNCE çözülür: `context` async boşlukların ardında
    // kullanılamaz (`use_build_context_synchronously`), tür adı ise fiyat
    // çekiminden sonra gerekiyor.
    final l = context.l10n;
    if (entries.isEmpty) return;
    if (entries.length == 1) {
      _applyParsedEntry(entries.first);
      return;
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
              subCategory: entry.subCategory,
              unitType: entry.type == AssetType.altin ? 'gram' : 'piece',
            );
      }
    } finally {
      _n.setSaving(false);
    }
    // Hızlı giriş de bir kayıttır — `_save()` ile aynı sinyali döndürür.
    if (mounted) Navigator.pop(context, true);
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
    if (!_formKey.currentState!.validate()) return;
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
    final qty = _parse(_quantity.text)!;
    var price = _parse(_price.text) ?? 0.0;

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
    bool priceFromHistorical = false;
    // Kayıt sonrası alarm önerisi (2026-09-20): yeni varlık fiyat kaynağı
    // olan bir sembolse çağıran ekran "Alarm kur" eylemi gösterir.
    AlarmAdayi? alarmAdayi;
    bool priceFallbackToSpot = false;
    if (price == 0.0 && ticker.isNotEmpty) {
      final sonuc = await fiyatBul(
        lookup: ref.read(addAssetPriceLookupProvider),
        ticker: ticker,
        date: _addedDate,
      );
      if (!mounted) return _KayitSonu.kaldi;
      price = sonuc.price ?? 0.0;
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
      if (_isEditing) {
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
            commission: a.commission,
            // Bu kopya kaydın TÜM alanlarını taşımalı; eksik bırakılan alan
            // tarih düzenlemesinde sessizce sıfırlanır (temettü tutarı
            // böyle kaybolurdu).
            dividendAmount: a.dividendAmount,
            deletedCount: a.deletedCount,
          );
          await ref.read(portfolioProvider.notifier).updateAsset(updated);
        } else {
          await ref.read(portfolioProvider.notifier).updateAsset(a);
        }
      } else {
        final alarmSembol = manual ? null : alarmSembolu(ticker, _subCategory);
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
            );
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
      final msg = priceFromHistorical
          ? '$dateStr kapanışı ${fmt.format(price)} $_currency olarak atandı'
          : '$dateStr için geçmiş fiyat bulunamadı — güncel fiyat '
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
    Navigator.pop(context, alarmAdayi ?? true);
    return _KayitSonu.kapandi;
  }
}

/// `_kaydet`'in sonucu: bayrağın inip inmeyeceğine ve yeniden denemeye
/// `_save` karar verir (2026-09-23 denetimi F14).
enum _KayitSonu { kapandi, kaldi, yenidenDene }

// ─────────────────────────────────────────────────────────────────────────────
// Hızlı / Toplu Giriş Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _QuickEntrySheet extends StatefulWidget {
  final TextEditingController ctrl;
  final ParsedEntry? Function(String) parseLine;
  final void Function(ParsedEntry) onConfirmSingle;
  final Future<void> Function(List<ParsedEntry>) onSaveBatch;

  const _QuickEntrySheet({
    required this.ctrl,
    required this.parseLine,
    required this.onConfirmSingle,
    required this.onSaveBatch,
  });

  @override
  State<_QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<_QuickEntrySheet> {
  List<ParsedEntry> _previews = [];
  bool _saving = false;

  void _updatePreviews(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    setState(() {
      _previews =
          lines.map(widget.parseLine).whereType<ParsedEntry>().toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = _previews.length > 1;
    return Padding(
      padding: EdgeInsets.only(
        left: SandikSpace.screenH(context),
        right: SandikSpace.screenH(context),
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: context.c.amberText, size: 22),
              const SizedBox(width: 8),
              Text(
                context.l10n.quickEntryTitle,
                style: context.t.headlineSmall?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.c.text90,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.quickEntryHelp,
            style: context.t.titleSmall
                ?.copyWith(color: context.c.text58, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.ctrl,
            onTapOutside: _klavyeyiKapat,
            maxLines: 5,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: context.t.titleMedium?.copyWith(color: context.c.text90),
            decoration: InputDecoration(
              hintText:
                  context.l10n.quickEntryPlaceholder,
              hintStyle:
                  context.t.bodyMedium?.copyWith(color: context.c.text36),
              filled: true,
              fillColor: context.c.overlay,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                borderSide: BorderSide(color: context.c.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                borderSide: BorderSide(color: context.c.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SandikRadius.md),
                borderSide: BorderSide(
                    color: context.c.amberFill.withValues(alpha: 0.6)),
              ),
            ),
            onChanged: _updatePreviews,
          ),
          if (_previews.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...(_previews.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: e.type.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.type.labelOf(context.l10n)}  ·  ${e.qty % 1 == 0 ? e.qty.toInt() : e.qty}'
                          '${e.subCategory != null ? '  ${e.subCategory}' : ''}'
                          '${e.price > 0 ? '  @ ${e.price % 1 == 0 ? e.price.toInt() : e.price} ₺' : '  (fiyat otomatik)'}',
                          style: context.t.titleSmall
                              ?.copyWith(color: context.c.text58),
                        ),
                      ),
                    ],
                  ),
                ))),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _saving
                ? const CustomLoadingView()
                : isMulti
                    ? FilledButton.icon(
                        onPressed: () async {
                          // Kilit çift kaydı önler. finally olmadan, kaydetme
                          // hata verirse buton kalıcı olarak spinner'da
                          // kalıyordu — kullanıcı tekrar deneyemiyordu.
                          if (_saving) return;
                          setState(() => _saving = true);
                          try {
                            await widget.onSaveBatch(_previews);
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                        style: FilledButton.styleFrom(
                            backgroundColor: context.c.amberFill,
                            foregroundColor: context.c.onAmber),
                        icon: const Icon(Icons.playlist_add_check_rounded),
                        label: Text(context.l10n.saveNAssets(_previews.length),
                            style: context.t.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      )
                    : FilledButton.icon(
                        onPressed: _previews.isEmpty
                            ? null
                            : () => widget.onConfirmSingle(_previews.first),
                        style: FilledButton.styleFrom(
                            backgroundColor: context.c.amberFill,
                            foregroundColor: context.c.onAmber),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(context.l10n.fillTheForm,
                            style: context.t.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BIST100 Picker
// ─────────────────────────────────────────────────────────────────────────────

class _Bist100Picker extends StatefulWidget {
  final String? selected;
  final void Function(String ticker) onSelect;
  const _Bist100Picker({required this.selected, required this.onSelect});

  @override
  State<_Bist100Picker> createState() => _Bist100PickerState();
}

class _Bist100PickerState extends State<_Bist100Picker> {
  final _ctrl = TextEditingController();
  String _q = '';

  List<MapEntry<String, String>> get _filtered {
    final all = bist100StocksMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    return all
        .where((e) =>
            e.value.toLowerCase().contains(q) ||
            e.key.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return _PickerShell(
      title: context.l10n.bistStocks,
      count: filtered.length,
      color: AssetType.hisse.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: filtered.isEmpty
          ? _emptySearch(context, _q, cs)
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final e = filtered[i];
                final isSelected = e.key == widget.selected;
                final ticker = e.key.replaceAll('.IS', '');
                return _PickerRow(
                  badgeText:
                      ticker.length > 5 ? ticker.substring(0, 4) : ticker,
                  title: e.value,
                  subtitle: e.key,
                  isSelected: isSelected,
                  color: AssetType.hisse.color,
                  cs: cs,
                  onTap: () => widget.onSelect(e.key),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Altın türü seçici — tüm türler, gruplu ve aramalı
// ─────────────────────────────────────────────────────────────────────────────

class _GoldPicker extends StatefulWidget {
  final GoldSubCategory? selected;
  final String Function(GoldSubCategory) birim;
  final void Function(GoldSubCategory) onSelect;
  const _GoldPicker(
      {required this.selected, required this.birim, required this.onSelect});

  @override
  State<_GoldPicker> createState() => _GoldPickerState();
}

class _GoldPickerState extends State<_GoldPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  String _grupAdi(AltinGrubu g) => switch (g) {
        AltinGrubu.gram => context.l10n.goldGroupGram,
        AltinGrubu.ziynet => context.l10n.goldGroupZiynet,
        AltinGrubu.sikke => context.l10n.goldGroupSikke,
        AltinGrubu.ons => context.l10n.goldGroupOns,
      };

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final eslesen = altinTurleriniAra(_q);
    // Grup başlığı + satırlar düz listeye açılır; boş grup başlığı çizilmez.
    final ogeler = <Object>[
      for (final grup in AltinGrubu.values)
        if (eslesen.any((g) => g.grup == grup)) ...[
          grup,
          ...eslesen.where((g) => g.grup == grup),
        ],
    ];
    return _PickerShell(
      title: context.l10n.goldTypes,
      searchHint: context.l10n.goldSearchHint,
      count: eslesen.length,
      color: AssetType.altin.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: eslesen.isEmpty
          ? _emptySearch(context, _q, cs)
          : ListView.builder(
              itemCount: ogeler.length,
              itemBuilder: (_, i) {
                final o = ogeler[i];
                if (o is AltinGrubu) {
                  // HIG gruplu liste başlığı: satır metniyle aynı sol
                  // hizada, ikincil renkte, üstünde grup ayıracı boşluk.
                  final yatay = SandikSpace.screenH(context);
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                        yatay, i == 0 ? SandikSpace.md : SandikSpace.lg,
                        yatay, SandikSpace.xs),
                    child: Semantics(
                      header: true,
                      child: Text(_grupAdi(o),
                          style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.text58)),
                    ),
                  );
                }
                final g = o as GoldSubCategory;
                return _PickerRow(
                  badgeText: widget.birim(g),
                  title: g.label,
                  subtitle: g.description,
                  isSelected: g == widget.selected,
                  color: AssetType.altin.color,
                  cs: cs,
                  onTap: () => widget.onSelect(g),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEFAS Picker
// ─────────────────────────────────────────────────────────────────────────────

class _TefasPicker extends StatefulWidget {
  final String? selected;
  final void Function(TefasFund fund) onSelect;
  const _TefasPicker({required this.selected, required this.onSelect});

  @override
  State<_TefasPicker> createState() => _TefasPickerState();
}

class _TefasPickerState extends State<_TefasPicker> {
  final _ctrl = TextEditingController();
  String _q = '';
  List<TefasFund>? _funds;
  String? _error;

  // TEFAS liste API'sinde olmayan ama fiyat API'sinde bulunan
  // (kurucu-only) fonlar için lookup sonucu. Kullanıcı örn. "ALE" ya da
  // "YLB" yazdığında liste boş çıkarsa, arka planda tek-fon sorgusu
  // gönderilir ve sonuç buraya konur — kullanıcı "para piyasası fonu"
  // gibi görünmeyen fonları da bulabilsin.
  final Map<String, TefasFund?> _lookupCache = {};
  final Set<String> _lookupInFlight = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _tryLookup(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 2 || code.length > 6) return;
    if (_lookupCache.containsKey(code)) return;
    if (_lookupInFlight.contains(code)) return;
    _lookupInFlight.add(code);
    try {
      final fund = await TefasService.instance.lookupFund(code);
      if (!mounted) return;
      setState(() {
        _lookupCache[code] = fund;
        if (fund != null && _funds != null) {
          // Cache'e yansı — bir sonraki filtreleme direkt bulur.
          if (!_funds!.any((f) => f.code == fund.code)) {
            _funds = [..._funds!, fund]
              ..sort((a, b) => a.name.compareTo(b.name));
          }
        }
      });
    } finally {
      _lookupInFlight.remove(code);
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _funds = null;
    });
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      if (mounted) {
        // Always succeed - funds will never be null
        if (funds.isNotEmpty) {
          setState(() => _funds = funds);
        } else {
          // Fallback should have funds, but handle edge case
          setState(() => _error = 'Fon listesi boş (fallback kullanılıyor)');
        }
      }
    } catch (e) {
      // This should never happen, but keep for safety
      if (mounted) {
        // Elle string eşleme yerine ortak çevirici — ağ/timeout/HTTP
        // ayrımını zaten yapıyor, ham metin sızdırmıyor.
        setState(() => _error = friendlyError(e));
      }
    }
  }

  List<TefasFund> get _filtered {
    final all = _funds ?? [];
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    return all
        .where((f) =>
            f.name.toLowerCase().contains(q) ||
            f.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final fmt = qtyFormatter(maxDigits: 6);

    return _PickerShell(
      title: context.l10n.tefasFunds,
      count: filtered.length,
      color: AssetType.fon.color,
      searchCtrl: _ctrl,
      onSearch: (v) {
        setState(() => _q = v);
        // TEFAS liste API'sinde olmayan (kurucu-only) fon kodları için —
        // örn. ALE, YLB gibi para piyasası fonları — arama filtresi boş
        // çıkarsa arka planda tek-fon lookup gönder. Bulunursa cache'e
        // eklenip filtreye dâhil olur.
        final code = v.trim().toUpperCase();
        if (code.length >= 3 && code.length <= 6) {
          final already = (_funds ?? []).any((f) => f.code == code);
          if (!already) _tryLookup(code);
        }
      },
      query: _q,
      cs: cs,
      child: _funds == null && _error == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomLoadingIndicator(),
                  const SizedBox(height: 12),
                  Text(context.l10n.fundsLoading,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.pleaseWait,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            color: cs.error, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.fundsLoadFailed,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Tekrar Dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? _emptySearch(context, _q, cs)
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final f = filtered[i];
                        final isSelected = f.code == widget.selected;
                        return _PickerRow(
                          badgeText: f.code,
                          title: f.name,
                          subtitle: f.price > 0
                              ? '₺ ${fmt.format(f.price)}'
                              : context.l10n.priceNotAvailable,
                          isSelected: isSelected,
                          color: AssetType.fon.color,
                          cs: cs,
                          onTap: () => widget.onSelect(f),
                        );
                      },
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared picker shell & row widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PickerShell extends StatefulWidget {
  final String title;
  final int count;
  final Color color;
  final TextEditingController searchCtrl;
  final void Function(String) onSearch;
  final String query;
  final ColorScheme cs;
  final Widget child;
  /// Arama kutusunun ipucu; verilmezse genel "Ara…".
  final String? searchHint;

  const _PickerShell({
    required this.title,
    required this.count,
    required this.color,
    required this.searchCtrl,
    required this.onSearch,
    required this.query,
    required this.cs,
    required this.child,
    this.searchHint,
  });

  @override
  State<_PickerShell> createState() => _PickerShellState();
}

// Hisse, fon ve altın seçicilerinin ortak kabuğu.
//
// 2026-09-25 ("liste uygulama ve HIG standartlarına uygun olmalı",
// kullanıcı): kabuk ham `TextStyle(fontSize:)` ve Material `cs.*` tonlarıyla
// yazılmıştı; uygulamanın geri kalanından farklı font boyutu/rengi
// taşıyordu. Artık tipografi `context.t`, renk `context.c`, boşluk
// `SandikSpace` — aynı liste her yerde aynı görünür. HIG: arama alanı 44pt,
// temizle düğmesi 44pt dokunma hedefi, başlık büyük ve kalın.
class _PickerShellState extends State<_PickerShell> {
  @override
  Widget build(BuildContext context) {
    final yatay = SandikSpace.screenH(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: SandikSpace.sm2),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: context.c.text20,
                borderRadius: BorderRadius.circular(SandikRadius.sm)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.smd),
            child: Row(
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text('${widget.count}',
                      style: context.t.labelLarge
                          ?.copyWith(color: widget.color)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.smd),
            child: Container(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              decoration: BoxDecoration(
                color: context.c.background,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(color: context.c.hairline),
              ),
              child: Row(
                children: [
                  const SizedBox(width: SandikSpace.smd),
                  Icon(Icons.search_rounded,
                      size: 18, color: context.c.text58),
                  const SizedBox(width: SandikSpace.sm),
                  Expanded(
                    child: TextField(
                      controller: widget.searchCtrl,
                      onTapOutside: _klavyeyiKapat,
                      style: context.t.bodyLarge,
                      decoration: InputDecoration(
                        hintText:
                            widget.searchHint ?? context.l10n.searchEllipsis,
                        hintStyle: context.t.bodyLarge
                            ?.copyWith(color: context.c.text36),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: widget.onSearch,
                    ),
                  ),
                  if (widget.query.isNotEmpty)
                    Semantics(
                      button: true,
                      label: context.l10n.clearSearch,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.searchCtrl.clear();
                          widget.onSearch('');
                        },
                        child: SizedBox.fromSize(
                          size: SandikTouch.minSize,
                          child: Icon(Icons.cancel_rounded,
                              size: 18, color: context.c.text36),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.c.hairline),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String badgeText;
  final String title;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PickerRow({
    required this.badgeText,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.cs,
    required this.onTap,
  });

  // HIG seçim listesi: seçili satırda onay işareti, diğerlerinde HİÇBİR
  // işaret yok. Eski `chevron_right` "yeni sayfaya gider" demekti (HIG'de
  // ok = disclosure); burada dokunuş seçer ve sayfayı kapatır.
  @override
  Widget build(BuildContext context) {
    final yatay = SandikSpace.screenH(context);
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: yatay, vertical: SandikSpace.sm2),
          child: Row(
            children: [
              Container(
                width: SandikTouch.min,
                height: SandikTouch.min,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.16)
                      : context.c.surface2,
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: isSelected
                      ? Border.all(color: color.withValues(alpha: 0.5))
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeText.length > 5 ? badgeText.substring(0, 4) : badgeText,
                  maxLines: 1,
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? color : context.c.text90,
                  ),
                ),
              ),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: context.t.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: SandikSpace.xxs),
                      Text(subtitle,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text58),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: SandikSpace.sm),
                Icon(Icons.check_rounded, size: 22, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _emptySearch(BuildContext context, String q, ColorScheme cs) => Center(
      child: Padding(
        padding: const EdgeInsets.all(SandikSpace.lg),
        child: Text(
            q.isEmpty ? context.l10n.noResults : context.l10n.noResultsFor(q),
            textAlign: TextAlign.center,
            style: context.t.bodyLarge?.copyWith(color: context.c.text58)),
      ),
    );
