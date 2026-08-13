import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/asset_categories.dart';
import '../providers/bulk_cart_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/price_service.dart';
import '../services/remote_config_service.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/h_scroll_with_fade.dart';
import 'add_deposit_screen.dart';
import 'paywall_screen.dart';
import 'bulk_add_asset_screen.dart';
import '../widgets/custom_loading_indicator.dart';

const _addAssetUuid = Uuid();

// ─── Döviz sabitleri ───────────────────────────────────────────────────────────

typedef _DovizOpt = ({String label, String ticker, String name, String symbol});

// ─── Hızlı giriş veri modeli ──────────────────────────────────────────────────

typedef _ParsedEntry = ({
  AssetType type,
  String? subCategory,
  double qty,
  double price,
  String raw,
});

const _dovizOptions = <_DovizOpt>[
  (label: 'USD', ticker: 'USDTRY=X', name: 'ABD Doları', symbol: '\$'),
  (label: 'EUR', ticker: 'EURTRY=X', name: 'Euro', symbol: '€'),
  (label: 'GBP', ticker: 'GBPTRY=X', name: 'İngiliz Sterlini', symbol: '£'),
  (label: 'TRY', ticker: '', name: 'Türk Lirası', symbol: '₺'),
];

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

  late AssetType _type;
  late String? _subCategory;
  late String _unitType;
  late String _currency;
  late bool _isManualPrice;
  late DateTime _addedDate;
  bool _saving = false;

  // Preview: kullanıcı save'e basmadan önce tahmini birim fiyat.
  // Ticker+tarih değişince debounce ile fetch tetiklenir, sonuç card'da
  // gösterilir. Kullanıcı fiyatı kendisi yazdıysa preview gizlenir.
  double? _previewPrice;
  bool _previewLoading = false;
  bool _previewIsHistorical = false;
  Timer? _previewDebounce;
  int _previewSeq = 0;

  String? _bist100SelectedTicker;
  TefasFund? _selectedFund;

  static const _currencies = ['TRY', 'USD', 'EUR', 'GBP'];
  bool get _isEditing => widget.editingAsset != null;
  bool get _isBist100 =>
      _type == AssetType.hisse &&
      _subCategory == StockSubCategory.bist100.label;
  bool get _isFon => _type == AssetType.fon;
  bool get _isDoviz => _type == AssetType.doviz;

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
    final initType =
        a?.type ?? c?.type ?? widget.prefillType ?? AssetType.hisse;
    // BIST prefill'inde alt kategori de kurulmalı, yoksa aşağıdaki
    // `_bist100SelectedTicker` ataması tetiklenmez ve seçici boş açılır.
    final initSubCat = a?.subCategory ??
        c?.subCategory ??
        (widget.prefillType == AssetType.hisse &&
                (widget.prefillTicker?.endsWith('.IS') ?? false)
            ? StockSubCategory.bist100.label
            : null);
    final initUnit = a?.unitType ?? c?.unitType ?? 'piece';
    final initCurrency = a?.currency ?? c?.currency ?? initType.defaultCurrency;

    _name = TextEditingController(text: initName);
    _ticker = TextEditingController(text: initTicker);
    _quantity = TextEditingController(text: initQty > 0 ? _fmt(initQty) : '');
    _price = TextEditingController(text: initPrice > 0 ? _fmt(initPrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _commission = TextEditingController(
        text: (a?.commission ?? 0) > 0 ? _fmt(a!.commission) : '');
    _type = initType;
    _subCategory = initSubCat;
    _unitType = initUnit;
    _currency = initCurrency;
    _isManualPrice = a?.isManualPrice ?? (c != null && c.ticker.isEmpty);
    _addedDate = a?.addedDate ?? c?.addedDate ?? DateTime.now();
    // Form açılışında preview'ı bir kere tetikle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPricePreview());

    // BIST100 seçili hisse prefill
    if (initType == AssetType.hisse &&
        initSubCat == StockSubCategory.bist100.label &&
        initTicker.isNotEmpty) {
      _bist100SelectedTicker = initTicker;
    }
    // TEFAS fon prefill
    if (initType == AssetType.fon && initTicker.startsWith('TEFAS:')) {
      final code = initTicker.replaceFirst('TEFAS:', '');
      _selectedFund = TefasFund(
          code: code,
          name: initName,
          price: a?.currentPrice ?? 0,
          fundType: '',
          managerName: '');
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    for (final c in [_name, _ticker, _quantity, _price, _notes, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Preview: seçili varlık + tarih için tahmini birim fiyat ──────────────
  //
  // Ticker/tarih değişince 400 ms debounce ile çalışır. Kullanıcı fiyat
  // alanına manuel değer yazdıysa preview gösterilmez (o zaman zaten kesin
  // fiyat var). Sequence sayacı ile eski request sonuçlarını yutar.
  String? _resolveTickerForPreview() {
    if (_isBist100) return _bist100SelectedTicker;
    if (_isFon && _selectedFund != null) return 'TEFAS:${_selectedFund!.code}';
    if (_type == AssetType.altin && _subCategory != null) {
      return goldTickerMap[_subCategory!];
    }
    if (_isDoviz && _subCategory != null) {
      final opt = _dovizOptions.firstWhere(
        (o) => o.label == _subCategory,
        orElse: () => _dovizOptions.first,
      );
      return opt.ticker;
    }
    final t = _ticker.text.trim().toUpperCase();
    return t.isEmpty ? null : t;
  }

  void _schedulePricePreview() {
    _previewDebounce?.cancel();
    _previewDebounce =
        Timer(const Duration(milliseconds: 400), _refreshPricePreview);
  }

  Future<void> _refreshPricePreview() async {
    // Kullanıcı fiyatı kendi yazdıysa preview'a gerek yok.
    final userPrice = _parse(_price.text);
    if (userPrice != null && userPrice > 0) {
      if (mounted && _previewPrice != null) {
        setState(() {
          _previewPrice = null;
          _previewLoading = false;
        });
      }
      return;
    }

    final ticker = _resolveTickerForPreview();
    if (ticker == null || ticker.isEmpty) {
      if (mounted && (_previewPrice != null || _previewLoading)) {
        setState(() {
          _previewPrice = null;
          _previewLoading = false;
        });
      }
      return;
    }

    final now = DateTime.now();
    final isToday = _addedDate.year == now.year &&
        _addedDate.month == now.month &&
        _addedDate.day == now.day;

    final seq = ++_previewSeq;
    if (mounted) setState(() => _previewLoading = true);

    double? fetched;
    bool isHistorical = false;
    try {
      if (!isToday) {
        final hist = await PriceService.instance
            .fetchHistoricalClose(ticker, _addedDate);
        if (hist != null && hist > 0) {
          fetched = hist;
          isHistorical = true;
        }
      }
      if (fetched == null) {
        if (ticker.startsWith('TEFAS:')) {
          final code = ticker.replaceFirst('TEFAS:', '');
          final prices = await TefasService.instance.fetchPrices([code]);
          fetched = prices[code];
        } else {
          final quotes = await PriceService.instance.fetchQuotes([ticker]);
          fetched = quotes[ticker.toUpperCase()]?.regularMarketPrice;
        }
      }
    } catch (_) {}

    // Eski istek dönmüşse yut.
    if (seq != _previewSeq || !mounted) return;
    setState(() {
      _previewPrice = (fetched != null && fetched > 0) ? fetched : null;
      _previewIsHistorical = isHistorical;
      _previewLoading = false;
    });
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

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

  String _getUnitLabel(String unitType) {
    try {
      return UnitType.values
          .firstWhere((u) => u.name == unitType || u.shortcode == unitType)
          .label;
    } catch (_) {
      return 'Adet';
    }
  }

  String get _quantitySuffix {
    if (_isDoviz) return _subCategory ?? 'Adet';
    return _getUnitLabel(_unitType);
  }

  List<String> get _quantityPresets {
    if (_unitType == 'gram') return ['1', '5', '10', '50', '100'];
    if (_unitType == 'ounce') return ['0.1', '0.5', '1', '5', '10'];
    if (_type == AssetType.fon) return ['1', '10', '100', '1000'];
    if (_type == AssetType.hisse) return ['1', '5', '10', '100', '1000'];
    return ['1', '5', '10', '100'];
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  bool _notesExpanded = false;

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final saveLabel = widget.cartMode
        ? (widget.cartInitial != null ? 'Kaydet' : 'Sepete Ekle')
        : (_isEditing ? 'Güncelle' : 'Ekle');
    final title = widget.cartMode
        ? (widget.cartInitial != null ? 'Sepette Düzenle' : 'Sepete Ekle')
        : (_isEditing ? 'Düzenle' : 'Varlık Ekle');

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: context.c.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: context.t.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: context.c.text90),
        ),
        actions: [
          if (!_isEditing && !widget.cartMode) ...[
            IconButton(
              tooltip: 'Toplu ekle',
              icon: Icon(Icons.playlist_add_rounded, color: context.c.text58),
              // Toplu ekleme başarıyla bittiğinde `true` döner; o zaman bu
              // ekran da kapanır ve kullanıcı portföye ulaşır. Aksi halde
              // arkada boş kalan bu formda mahsur kalıyordu.
              onPressed: () async {
                final added = await Navigator.of(context).push<bool>(
                  adaptiveRoute(builder: (_) => const BulkAddAssetScreen()),
                );
                if (added == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
            IconButton(
              tooltip: 'Sesli / Hızlı giriş',
              icon: Icon(Icons.mic_none_rounded, color: context.c.text58),
              onPressed: _showQuickEntrySheet,
            ),
          ],
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _sectionLabel('Varlık Türü'),
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
    );
  }

  // ── Bağlama göre "kimlik" alanının etiketi ─────────────────────────────────
  String _identityLabel() {
    if (_isBist100 || _type == AssetType.hisse) return 'Hisse';
    if (_isFon) return 'Fon';
    if (_type == AssetType.altin) return 'Altın Türü';
    if (_isDoviz) return 'Para Birimi';
    if (_type == AssetType.emtia) return 'Emtia';
    return 'Varlık';
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
          hint: _type == AssetType.emtia ? 'Örn: Petrol (Brent)' : 'Varlık adı',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Ad zorunlu' : null,
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _ticker,
          hint: _type.tickerHint,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (v) {
            if (v.isEmpty) setState(() => _isManualPrice = true);
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
                child: Text('veya listede yok',
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
          hint: 'Sembol yaz (örn: AAPL, THYAO.IS)',
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (v) {
            setState(() {
              if (v.isNotEmpty) {
                _bist100SelectedTicker = null;
                _subCategory = StockSubCategory.other.label;
                _isManualPrice = false;
              } else {
                _isManualPrice = true;
              }
            });
            _schedulePricePreview();
          },
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _name,
          hint: 'Şirket adı (opsiyonel — semboldan otomatik çekilir)',
        ),
      ],
    );
  }

  // ── Altın: 7 türü tek büyük chip grid (dropdown yok) ───────────────────────
  Widget _goldChipGrid(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: GoldSubCategory.values.map((g) {
        final selected = _subCategory == g.label;
        return GestureDetector(
          onTap: () {
            setState(() {
              _subCategory = g.label;
              _unitType = g.unitType;
              _name.text = g.label;
            });
            _schedulePricePreview();
          },
          child: AnimatedContainer(
            duration:
                SandikMotion.of(context, const Duration(milliseconds: 160)),
            curve: SandikMotion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                const SizedBox(width: 6),
                Text(g.label,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? context.c.text90 : context.c.text58)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Miktar bloğu ───────────────────────────────────────────────────────────
  Widget _quantityBlock(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Miktar'),
        const SizedBox(height: 8),
        _brandInput(
          controller: _quantity,
          hint: '0',
          suffixText: _quantitySuffix,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) =>
              (_parse(v ?? '') == null || (_parse(v ?? '') ?? 0) <= 0)
                  ? 'Geçerli miktar'
                  : null,
          onChanged: (_) => setState(() {}),
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
            Flexible(child: _fieldLabel('Alış Fiyatı')),
            const SizedBox(width: 6),
            Flexible(
              child: Text('· opsiyonel',
                  style: context.t.bodySmall?.copyWith(color: context.c.text36),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _price,
          hint: 'Otomatik',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalFormatter()],
          validator: (v) =>
              v != null && v.trim().isNotEmpty && _parse(v) == null
                  ? 'Geçersiz'
                  : null,
          onChanged: (_) {
            setState(() {});
            _schedulePricePreview();
          },
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
            Flexible(child: _fieldLabel('Komisyon / Masraf')),
            const SizedBox(width: 6),
            Flexible(
              child: Text('· opsiyonel',
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
            if (parsed == null) return 'Geçersiz';
            if (parsed < 0) return 'Negatif olamaz';
            return null;
          },
          onChanged: (_) => setState(() {}),
          suffix: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_currency,
                style: context.t.titleSmall?.copyWith(
                    color: context.c.text58, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Alım-satım komisyonu maliyete eklenir — kâr/zarar gerçek rakamı gösterir.',
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
          onChanged: (v) => setState(() => _currency = v ?? _currency),
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
                'Miktar girince toplam maliyet burada görünecek.',
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
    final fmt = NumberFormat.currency(
        locale: 'tr_TR',
        symbol: _currency == 'TRY' ? '₺ ' : '',
        decimalDigits: 2);
    final formatted = _currency == 'TRY'
        ? fmt.format(total)
        : '${NumberFormat('#,##0.##', 'tr_TR').format(total)} $_currency';

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
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOPLAM MALİYET',
                  style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.amberText,
                    letterSpacing: 0.8,
                  )),
              const SizedBox(height: 4),
              Text('${_fmt(qty)} × ${_fmt(price)}',
                  style:
                      context.t.bodySmall?.copyWith(color: context.c.text58)),
            ],
          ),
          const Spacer(),
          Text(
            formatted,
            // Form özeti toplam tutarı — tabular figür, yazarken zıplamasın.
            style: context.t.numLarge.copyWith(
              fontSize: 22,
              color: context.c.gold,
              letterSpacing: -0.5,
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
      final fmt = NumberFormat('#,##0.##', 'tr_TR');
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
          helpText: 'İşlem tarihi',
        );
        if (picked != null) {
          setState(() => _addedDate = picked);
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
              child: Text('İşlem tarihi',
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
            onTap: () => setState(() => _notesExpanded = !_notesExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: context.c.text58),
                  const SizedBox(width: 10),
                  Text('Not ekle',
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
                decoration: context.inputDecoration('Notlarınız...'),
                onChanged: (_) => setState(() {}),
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
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // ── Varlık türü seçici (Sandik brand) ──────────────────────────────────────

  Widget _typeSelector(ColorScheme cs) {
    // Vadeli mevduat feature'ı Remote Config ile kapatılabilir. Kapalıyken
    // add-asset seçicisinden gizlenir — mevcut kayıtlı mevduatlar okunmaya
    // devam eder, sadece yeni ekleme kapanır.
    final types = RemoteConfigService.instance.depositsEnabled
        ? AssetType.values
        : AssetType.values.where((t) => t != AssetType.mevduat).toList();
    return HScrollWithFade(
      fadeColor: context.c.background,
      child: Row(
        children: types.map((t) {
          final selected = _type == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                if (t == AssetType.mevduat) {
                  // Vadeli mevduat için ayrı, form yapısı tamamen farklı ekran.
                  final ok = await Navigator.of(context).push<bool>(
                    adaptiveRoute(
                      builder: (_) => const AddDepositScreen(),
                    ),
                  );
                  if (ok == true && mounted) Navigator.of(context).pop(true);
                  return;
                }
                setState(() {
                  _type = t;
                  _subCategory = null;
                  _unitType = 'piece';
                  _currency = t.defaultCurrency;
                  _bist100SelectedTicker = null;
                  _selectedFund = null;
                  _ticker.clear();
                  _name.clear();
                });
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
                    Text(t.label,
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? context.c.text90 : context.c.text58,
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

  // ── Döviz para birimi seçici (Sandik brand, 4 büyük kart) ──────────────────

  Widget _dovizSelector(ColorScheme cs) {
    return Row(
      children: _dovizOptions.map((opt) {
        final selected = _subCategory == opt.label;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _subCategory = opt.label;
                  _ticker.text = opt.ticker;
                  _currency = 'TRY';
                  _isManualPrice = opt.ticker.isEmpty;
                  _name.text = opt.name;
                });
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
            ),
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
            child: GestureDetector(
              onTap: () => setState(() => _quantity.text = v),
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
                      _getUnitLabel(_unitType),
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
            ),
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
          ? 'Lütfen bir hisse seçin'
          : null,
      builder: (state) => GestureDetector(
        onTap: _showBist100Picker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _bist100SelectedTicker != null,
          hasError: state.hasError,
          badgeText: ticker,
          mainText: selectedName ?? 'Hisse seçmek için dokunun...',
          color: AssetType.hisse.color,
        ),
      ),
    );
  }

  void _showBist100Picker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _Bist100Picker(
        selected: _bist100SelectedTicker,
        onSelect: (ticker) {
          setState(() {
            _bist100SelectedTicker = ticker;
            _ticker.text = ticker;
            _name.text =
                bist100StocksMap[ticker] ?? ticker.replaceAll('.IS', '');
          });
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
          _isFon && _selectedFund == null ? 'Lütfen bir fon seçin' : null,
      builder: (state) => GestureDetector(
        onTap: _showTefasPicker,
        child: _selectorContainer(
          cs: cs,
          hasValue: _selectedFund != null,
          hasError: state.hasError,
          badgeText: _selectedFund?.code,
          mainText: _selectedFund?.name ?? 'Fon seçmek için dokunun...',
          color: AssetType.fon.color,
        ),
      ),
    );
  }

  void _showTefasPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _TefasPicker(
        selected: _selectedFund?.code,
        onSelect: (fund) {
          setState(() {
            _selectedFund = fund;
            _ticker.text = 'TEFAS:${fund.code}';
            _name.text = fund.name;
            // Fon fiyatını alış fiyatına doldur (opsiyonel, kullanıcı silebilir)
            if (fund.price > 0 && _price.text.isEmpty) {
              _price.text = _fmt(fund.price);
            }
          });
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

  _ParsedEntry? _parseLine(String raw) {
    final text = raw.toLowerCase().trim();
    if (text.isEmpty) return null;

    AssetType detectedType = AssetType.hisse;
    String? detectedSub;

    if (RegExp(r'dolar|usd').hasMatch(text)) {
      detectedType = AssetType.doviz;
      detectedSub = 'USD';
    } else if (RegExp(r'euro|eur').hasMatch(text)) {
      detectedType = AssetType.doviz;
      detectedSub = 'EUR';
    } else if (RegExp(r'sterlin|gbp|pound').hasMatch(text)) {
      detectedType = AssetType.doviz;
      detectedSub = 'GBP';
    } else if (RegExp(r'gram\s*alt[ıi]n|alt[ıi]n').hasMatch(text)) {
      detectedType = AssetType.altin;
    } else if (RegExp(r'fon\b').hasMatch(text)) {
      detectedType = AssetType.fon;
    } else if (RegExp(r'hisse|adet').hasMatch(text)) {
      detectedType = AssetType.hisse;
    }

    final normalized = text.replaceAll(RegExp(r'(?<=\d)\.(?=\d{3})'), '');
    final numMatches =
        RegExp(r'(\d+([.,]\d+)?)').allMatches(normalized).toList();
    double qty = 0;
    double price = 0;

    if (numMatches.isNotEmpty) {
      qty =
          double.tryParse(numMatches.first.group(1)!.replaceAll(',', '.')) ?? 0;
    }
    final priceHint =
        RegExp(r'(\d+([.,]\d+)?)\s*(lira|tl|₺)').firstMatch(normalized);
    if (priceHint != null) {
      price = double.tryParse(priceHint.group(1)!.replaceAll(',', '.')) ?? 0;
    } else if (numMatches.length >= 2) {
      price =
          double.tryParse(numMatches[1].group(1)!.replaceAll(',', '.')) ?? 0;
    }

    if (qty <= 0) return null;
    return (
      type: detectedType,
      subCategory: detectedSub,
      qty: qty,
      price: price,
      raw: raw.trim()
    );
  }

  void _showQuickEntrySheet() {
    final ctrl = TextEditingController();
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

  void _applyParsedEntry(_ParsedEntry entry) {
    setState(() {
      _type = entry.type;
      _currency = _type.defaultCurrency;
      if (entry.subCategory != null) {
        _subCategory = entry.subCategory;
        if (_type == AssetType.doviz) {
          final opt = _dovizOptions.firstWhere(
            (o) => o.label == entry.subCategory,
            orElse: () => _dovizOptions.first,
          );
          _ticker.text = opt.ticker;
          _name.text = opt.name;
          _currency = 'TRY';
        }
      }
      _quantity.text = _fmt(entry.qty);
      if (entry.price > 0) _price.text = _fmt(entry.price);
    });
  }

  Future<void> _saveBatch(List<_ParsedEntry> entries) async {
    if (entries.isEmpty) return;
    if (entries.length == 1) {
      _applyParsedEntry(entries.first);
      return;
    }
    setState(() => _saving = true);
    try {
      for (final entry in entries) {
        String ticker = '';
        String assetName = '';
        String currency = entry.type.defaultCurrency;

        if (entry.type == AssetType.doviz && entry.subCategory != null) {
          final opt = _dovizOptions.firstWhere(
            (o) => o.label == entry.subCategory,
            orElse: () => _dovizOptions.first,
          );
          ticker = opt.ticker;
          assetName = opt.name;
          currency = 'TRY';
        } else if (entry.type == AssetType.altin) {
          assetName = entry.subCategory ?? 'Altın';
        }

        double price = entry.price;
        if (price == 0 && ticker.isNotEmpty) {
          try {
            final quotes = await PriceService.instance.fetchQuotes([ticker]);
            final q = quotes[ticker.toUpperCase()];
            if (q?.regularMarketPrice != null && q!.regularMarketPrice! > 0) {
              price = q.regularMarketPrice!;
            }
          } catch (_) {}
        }

        if (assetName.isEmpty) {
          assetName = entry.subCategory ?? entry.type.label;
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
      if (mounted) setState(() => _saving = false);
    }
    // Hızlı giriş de bir kayıttır — `_save()` ile aynı sinyali döndürür.
    if (mounted) Navigator.pop(context, true);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final qty = _parse(_quantity.text)!;
    var price = _parse(_price.text) ?? 0.0;

    String ticker = '';
    String assetName = _name.text.trim();

    if (_isBist100) {
      ticker = _bist100SelectedTicker ?? '';
      assetName = bist100StocksMap[ticker] ?? ticker.replaceAll('.IS', '');
    } else if (_isFon && _selectedFund != null) {
      ticker = 'TEFAS:${_selectedFund!.code}';
      assetName = _selectedFund!.name;
    } else if (_type == AssetType.altin && _subCategory != null) {
      ticker = goldTickerMap[_subCategory!] ?? '';
      if (assetName.isEmpty) assetName = _subCategory!;
    } else if (_isDoviz && _subCategory != null) {
      final opt = _dovizOptions.firstWhere(
        (o) => o.label == _subCategory,
        orElse: () => _dovizOptions.first,
      );
      ticker = opt.ticker;
      if (assetName.isEmpty) assetName = opt.name;
    } else if (_type != AssetType.altin &&
        _type != AssetType.fon &&
        !_isDoviz) {
      ticker = _isManualPrice ? '' : _ticker.text.trim().toUpperCase();
    }

    final manual = _isFon
        ? false
        : (_type == AssetType.altin
            ? ticker.isNotEmpty
                ? false
                : true
            : _isDoviz
                ? ticker.isEmpty
                : _isManualPrice || ticker.isEmpty);

    // ── Sepete ekleme modu: bulkCartProvider'a push, fiyat çekme yok ──
    if (widget.cartMode) {
      if (assetName.isEmpty) {
        assetName = ticker.isNotEmpty ? ticker : (_subCategory ?? _type.label);
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
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // ── Fiyat çek (alış fiyatı boşsa) ──────────────────────────────────────
    // Bugün seçildiyse güncel spot; geçmiş bir tarih seçildiyse o tarihin
    // kapanış fiyatı. Historical fetch başarısızsa spot'a fallback yapar.
    bool priceFromHistorical = false;
    bool priceFallbackToSpot = false;
    if (price == 0.0 && ticker.isNotEmpty) {
      setState(() => _saving = true);
      try {
        final now = DateTime.now();
        final isToday = _addedDate.year == now.year &&
            _addedDate.month == now.month &&
            _addedDate.day == now.day;

        if (!isToday) {
          final hist = await PriceService.instance
              .fetchHistoricalClose(ticker, _addedDate);
          if (hist != null && hist > 0) {
            price = hist;
            priceFromHistorical = true;
          }
        }

        // Historical yoksa veya bugünse spot
        if (price == 0.0) {
          if (ticker.startsWith('TEFAS:') && _selectedFund != null) {
            final code = ticker.replaceFirst('TEFAS:', '');
            final prices = await TefasService.instance.fetchPrices([code]);
            price = prices[code] ?? 0.0;
          } else {
            final quotes = await PriceService.instance.fetchQuotes([ticker]);
            if (!mounted) return;
            final q = quotes[ticker.toUpperCase()];
            if (q?.regularMarketPrice != null && q!.regularMarketPrice! > 0) {
              price = q.regularMarketPrice!;
            }
          }
          if (price > 0 && !isToday) priceFallbackToSpot = true;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _saving = false);
    }

    // ── Şirket adını Yahoo'dan çek (bilinmiyorsa) ──────────────────────────
    if (assetName.isEmpty &&
        ticker.isNotEmpty &&
        !ticker.startsWith('TEFAS:')) {
      try {
        final quotes = await PriceService.instance.fetchQuotes([ticker]);
        if (!mounted) return;
        final q = quotes[ticker.toUpperCase()];
        if (q != null) assetName = q.companyName;
      } catch (_) {}
    }

    if (assetName.isEmpty) {
      assetName = ticker.isNotEmpty ? ticker : 'Varlık';
    }

    setState(() => _saving = true);
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
      if (mounted) setState(() => _saving = false);
      if (!mounted) return;
      // Analytics ve paywall provider tarafından zaten log'landı.
      final upgraded = await PaywallScreen.show(
        context,
        source: 'asset_limit_${e.limit}',
      );
      if (upgraded == true && mounted) {
        // Kullanıcı premium'a geçti — save'i yeniden dene.
        Navigator.pop(context);
        _save();
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) {
      // Tarihli fiyat çekimi yapıldıysa kullanıcıya bildir — atanan değer
      // net görünsün, "güncel geldi sandım" hissi olmasın.
      if (priceFromHistorical || priceFallbackToSpot) {
        final fmt = NumberFormat('#,##0.##', 'tr_TR');
        final dateStr = DateFormat('d MMM yyyy', 'tr_TR').format(_addedDate);
        final msg = priceFromHistorical
            ? '$dateStr kapanışı ${fmt.format(price)} $_currency olarak atandı'
            : '$dateStr için geçmiş fiyat bulunamadı — güncel fiyat '
                '${fmt.format(price)} $_currency atandı';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // İki zemin İKİ farklı mürekkep ister: gain teması takip eder
            // (`onStatus`), amber her iki temada da açıktır (`onAmber`).
            content: Text(msg,
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: priceFromHistorical
                      ? context.c.onStatus
                      : context.c.onAmber,
                )),
            backgroundColor: priceFromHistorical
                ? context.c.gain.withValues(alpha: 0.9)
                : context.c.amberFill.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // `true`: çağıran (MainNavigationScreen) bunu "kayıt oldu" sinyali
      // olarak kullanıp Portföy sekmesine geçer. Sonuçsuz `pop` edilirse
      // kullanıcı hangi sekmedeyse orada kalır ve eklediği varlığı göremez.
      Navigator.pop(context, true);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hızlı / Toplu Giriş Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _QuickEntrySheet extends StatefulWidget {
  final TextEditingController ctrl;
  final _ParsedEntry? Function(String) parseLine;
  final void Function(_ParsedEntry) onConfirmSingle;
  final Future<void> Function(List<_ParsedEntry>) onSaveBatch;

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
  List<_ParsedEntry> _previews = [];
  bool _saving = false;

  void _updatePreviews(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    setState(() {
      _previews =
          lines.map(widget.parseLine).whereType<_ParsedEntry>().toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = _previews.length > 1;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
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
                'Hızlı Giriş',
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
            'Her satıra bir varlık yazın. Fiyat opsiyonel — boş bırakırsanız güncel fiyat otomatik çekilir.\n'
            'Örn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet',
            style: context.t.titleSmall
                ?.copyWith(color: context.c.text58, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.ctrl,
            autofocus: true,
            maxLines: 5,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: context.t.titleMedium?.copyWith(color: context.c.text90),
            decoration: InputDecoration(
              hintText:
                  '100 dolar\n10 gram altın 4500 lira\nGARAN 500 adet 105 lira',
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
                          '${e.type.label}  ·  ${e.qty % 1 == 0 ? e.qty.toInt() : e.qty}'
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
                        label: Text('${_previews.length} varlığı kaydet',
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
                        label: Text('Formu doldur',
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
      title: 'BIST Hisseleri',
      count: filtered.length,
      color: AssetType.hisse.color,
      searchCtrl: _ctrl,
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: filtered.isEmpty
          ? _emptySearch(_q, cs)
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
        String errorMsg = 'Bilinmeyen hata: ${e.toString()}';
        if (errorMsg.contains('HTTP')) {
          errorMsg = 'Sunucu hatası. Lütfen tekrar deneyiniz.';
        } else if (errorMsg.contains('internet') ||
            errorMsg.contains('Connection')) {
          errorMsg = 'İnternet bağlantısı kontrol edin.';
        } else if (errorMsg.contains('timeout') ||
            errorMsg.contains('Timeout')) {
          errorMsg = 'Bağlantı zaman aşımı. Tekrar deneyin.';
        }
        setState(() => _error = errorMsg);
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
    final fmt = NumberFormat('#,##0.######', 'tr_TR');

    return _PickerShell(
      title: 'TEFAS Fonları',
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
                  Text('Fonlar yükleniyor...',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(
                    'Lütfen bekleyin',
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
                          'Fonlar yüklenemedi',
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
                  ? _emptySearch(_q, cs)
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
                              : 'Fiyat bilgisi yok',
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

  const _PickerShell({
    required this.title,
    required this.count,
    required this.color,
    required this.searchCtrl,
    required this.onSearch,
    required this.query,
    required this.cs,
    required this.child,
  });

  @override
  State<_PickerShell> createState() => _PickerShellState();
}

class _PickerShellState extends State<_PickerShell> {
  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(SandikRadius.sm)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(widget.title,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: cs.onSurface)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text('${widget.count}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.color)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.searchCtrl,
                      autofocus: true,
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Ara...',
                        hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            fontSize: 14),
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
                    GestureDetector(
                      onTap: () {
                        widget.searchCtrl.clear();
                        widget.onSearch('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: isSelected
                    ? Border.all(
                        color: color.withValues(alpha: 0.5), width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                badgeText.length > 5 ? badgeText.substring(0, 4) : badgeText,
                style: TextStyle(
                  fontSize: badgeText.length > 4 ? 8 : 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: isSelected ? color : cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 20, color: color)
            else
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}

Widget _emptySearch(String q, ColorScheme cs) => Center(
      child: Text(q.isEmpty ? 'Sonuç bulunamadı' : '"$q" bulunamadı',
          style: TextStyle(color: cs.onSurfaceVariant)),
    );
