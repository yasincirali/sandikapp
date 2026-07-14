import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../widgets/h_scroll_with_fade.dart';
import 'add_deposit_screen.dart';
import 'paywall_screen.dart';
import 'bulk_add_asset_screen.dart';

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

  const AddAssetScreen({
    super.key,
    this.editingAsset,
    this.cartMode = false,
    this.cartInitial,
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

  late AssetType _type;
  late String? _subCategory;
  late String _unitType;
  late String _currency;
  late bool _isManualPrice;
  bool _saving = false;

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

    final initName = a?.name ?? c?.name ?? '';
    final initTicker = a?.ticker ?? c?.ticker ?? '';
    final initQty = a?.quantity ?? c?.quantity ?? 0;
    final initPrice = a?.purchasePrice ?? c?.price ?? 0;
    final initType = a?.type ?? c?.type ?? AssetType.hisse;
    final initSubCat = a?.subCategory ?? c?.subCategory;
    final initUnit = a?.unitType ?? c?.unitType ?? 'piece';
    final initCurrency =
        a?.currency ?? c?.currency ?? initType.defaultCurrency;

    _name = TextEditingController(text: initName);
    _ticker = TextEditingController(text: initTicker);
    _quantity =
        TextEditingController(text: initQty > 0 ? _fmt(initQty) : '');
    _price = TextEditingController(
        text: initPrice > 0 ? _fmt(initPrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _type = initType;
    _subCategory = initSubCat;
    _unitType = initUnit;
    _currency = initCurrency;
    _isManualPrice = a?.isManualPrice ?? (c != null && c.ticker.isEmpty);

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
    for (final c in [_name, _ticker, _quantity, _price, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String text) {
    if (text.trim().isEmpty) return null;
    final val = double.tryParse(text.trim().replaceAll(',', '.'));
    if (val == null || !val.isFinite) return null;
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
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Sandik.text58,
        ),
      );

  Widget _fieldLabel(String text) => Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Sandik.text90,
        ),
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
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Sandik.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Sandik.text90),
        ),
        actions: [
          if (!_isEditing && !widget.cartMode) ...[
            IconButton(
              tooltip: 'Toplu ekle',
              icon: const Icon(Icons.playlist_add_rounded,
                  color: Sandik.text58),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BulkAddAssetScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Sesli / Hızlı giriş',
              icon: const Icon(Icons.mic_none_rounded,
                  color: Sandik.text58),
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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          hint: _type == AssetType.emtia
              ? 'Örn: Petrol (Brent)'
              : 'Varlık adı',
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Ad zorunlu'
              : null,
        ),
        const SizedBox(height: 8),
        _brandInput(
          controller: _ticker,
          hint: _type.tickerHint,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (v) {
            if (v.isEmpty) setState(() => _isManualPrice = true);
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
                  height: 1,
                  color: Sandik.text36.withValues(alpha: 0.3)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('veya listede yok',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: Sandik.text36)),
            ),
            Expanded(
              child: Container(
                  height: 1,
                  color: Sandik.text36.withValues(alpha: 0.3)),
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
          onTap: () => setState(() {
            _subCategory = g.label;
            _unitType = g.unitType;
            _name.text = g.label;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AssetType.altin.color.withValues(alpha: 0.18)
                  : Sandik.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AssetType.altin.color
                    : Colors.white.withValues(alpha: 0.06),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color:
                            AssetType.altin.color.withValues(alpha: 0.25),
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
                        ? AssetType.altin.color
                        : Sandik.text58),
                const SizedBox(width: 6),
                Text(g.label,
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? Sandik.text90 : Sandik.text58)),
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
        Row(
          children: [
            _fieldLabel('Alış Fiyatı'),
            const SizedBox(width: 6),
            Text('· opsiyonel',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: Sandik.text36)),
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
          onChanged: (_) => setState(() {}),
          suffix: _isDoviz ? null : _inlineCurrencyPicker(),
        ),
      ],
    );
  }

  Widget _inlineCurrencyPicker() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _currency,
        isDense: true,
        dropdownColor: Sandik.surface2,
        style: GoogleFonts.dmSans(
            color: Sandik.amber, fontWeight: FontWeight.w700, fontSize: 12),
        icon: const Icon(Icons.arrow_drop_down,
            color: Sandik.amber, size: 18),
        items: _currencies
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c),
                ))
            .toList(),
        onChanged: (v) => setState(() => _currency = v ?? _currency),
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
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        child: Row(
          children: [
            Icon(Icons.calculate_outlined,
                color: Sandik.text36, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Miktar girince toplam maliyet burada görünecek.',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: Sandik.text58),
              ),
            ),
          ],
        ),
      );
    }

    if (isPriceEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Sandik.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Sandik.amber.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: Sandik.amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Alış fiyatı boş — kaydederken güncel piyasa fiyatı otomatik atanacak.',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: Sandik.text90,
                    height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    if (price == null || price <= 0) return const SizedBox.shrink();

    final total = qty * price;
    final fmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: _currency == 'TRY' ? '₺ ' : '', decimalDigits: 2);
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
            Sandik.amber.withValues(alpha: 0.16),
            Sandik.amber.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Sandik.amber.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: Sandik.amber.withValues(alpha: 0.16),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Sandik.amber,
                    letterSpacing: 0.8,
                  )),
              const SizedBox(height: 4),
              Text('${_fmt(qty)} × ${_fmt(price)}',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: Sandik.text58)),
            ],
          ),
          const Spacer(),
          Text(
            formatted,
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Sandik.gold,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Notlar collapsible ─────────────────────────────────────────────────────
  Widget _notesCollapsible(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                setState(() => _notesExpanded = !_notesExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded,
                      size: 16, color: Sandik.text58),
                  const SizedBox(width: 10),
                  Text('Not ekle',
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Sandik.text90)),
                  const Spacer(),
                  if (_notes.text.isNotEmpty && !_notesExpanded)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Sandik.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Icon(
                      _notesExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Sandik.text58,
                      size: 20),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _notesExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextFormField(
                controller: _notes,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: Sandik.text90),
                maxLines: 3,
                decoration: Sandik.inputDecoration('Notlarınız...'),
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
          color: Sandik.background,
          border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.05), width: 1),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Sandik.amber,
              foregroundColor: Colors.black,
              disabledBackgroundColor:
                  Sandik.amber.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.black),
                  )
                : Text(
                    saveLabel,
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2),
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
      style: GoogleFonts.dmSans(
          fontSize: 15,
          color: Sandik.text90,
          fontWeight: FontWeight.w500),
      decoration: Sandik.inputDecoration(hint).copyWith(
        suffixText: suffixText,
        suffixStyle: GoogleFonts.dmSans(
            fontSize: 12,
            color: Sandik.text58,
            fontWeight: FontWeight.w600),
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
      fadeColor: Sandik.background,
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
                    MaterialPageRoute(
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
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? t.color.withValues(alpha: 0.18)
                      : Sandik.surface1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? t.color
                        : Colors.white.withValues(alpha: 0.06),
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
                        size: 18,
                        color: selected ? t.color : Sandik.text58),
                    const SizedBox(width: 8),
                    Text(t.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Sandik.text90 : Sandik.text58,
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
              onTap: () => setState(() {
                _subCategory = opt.label;
                _ticker.text = opt.ticker;
                _currency = 'TRY';
                _isManualPrice = opt.ticker.isEmpty;
                _name.text = opt.name;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? AssetType.doviz.color.withValues(alpha: 0.18)
                      : Sandik.surface1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AssetType.doviz.color
                        : Colors.white.withValues(alpha: 0.06),
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AssetType.doviz.color
                                .withValues(alpha: 0.25),
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
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? AssetType.doviz.color
                            : Sandik.text90,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      opt.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AssetType.doviz.color
                            : Sandik.text58,
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
      fadeColor: Sandik.background,
      child: Row(
        children: presets.map((v) {
          final selected = _quantity.text == v;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _quantity.text = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? Sandik.amber.withValues(alpha: 0.16)
                      : Sandik.surface1,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? Sandik.amber.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Sandik.amber : Sandik.text58,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getUnitLabel(_unitType),
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        color: selected
                            ? Sandik.amber.withValues(alpha: 0.75)
                            : Sandik.text36,
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
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? Sandik.loss
              : (hasValue ? color : Colors.white.withValues(alpha: 0.06)),
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
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badgeText,
                  style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              mainText,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                color: hasValue ? Sandik.text90 : Sandik.text36,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.search_rounded, size: 18, color: Sandik.text58),
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
    final numMatches = RegExp(r'(\d+([.,]\d+)?)').allMatches(normalized).toList();
    double qty = 0;
    double price = 0;

    if (numMatches.isNotEmpty) {
      qty = double.tryParse(numMatches.first.group(1)!.replaceAll(',', '.')) ?? 0;
    }
    final priceHint = RegExp(r'(\d+([.,]\d+)?)\s*(lira|tl|₺)').firstMatch(normalized);
    if (priceHint != null) {
      price = double.tryParse(priceHint.group(1)!.replaceAll(',', '.')) ?? 0;
    } else if (numMatches.length >= 2) {
      price = double.tryParse(numMatches[1].group(1)!.replaceAll(',', '.')) ?? 0;
    }

    if (qty <= 0) return null;
    return (type: detectedType, subCategory: detectedSub, qty: qty, price: price, raw: raw.trim());
  }

  void _showQuickEntrySheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Sandik.surface1,
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

        if (assetName.isEmpty) assetName = entry.subCategory ?? entry.type.label;

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
    if (mounted) Navigator.pop(context);
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

    // ── Güncel fiyat çek (alış fiyatı boşsa) ──────────────────────────────
    if (price == 0.0 && ticker.isNotEmpty) {
      setState(() => _saving = true);
      try {
        if (ticker.startsWith('TEFAS:') && _selectedFund != null) {
          // TEFAS fiyatı API'den çek
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
          ..isManualPrice = manual;
        await ref.read(portfolioProvider.notifier).updateAsset(a);
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
    if (mounted) Navigator.pop(context);
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
      _previews = lines
          .map(widget.parseLine)
          .whereType<_ParsedEntry>()
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = _previews.length > 1;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Sandik.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                'Hızlı Giriş',
                style: GoogleFonts.dmSans(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Her satıra bir varlık yazın. Fiyat opsiyonel — boş bırakırsanız güncel fiyat otomatik çekilir.\n'
            'Örn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet',
            style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text58, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.ctrl,
            autofocus: true,
            maxLines: 5,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: '100 dolar\n10 gram altın 4500 lira\nGARAN 500 adet 105 lira',
              hintStyle: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Sandik.amber.withValues(alpha: 0.6)),
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
                    width: 6, height: 6,
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
                      style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text58),
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
                ? const Center(child: CircularProgressIndicator(color: Sandik.amber, strokeWidth: 2))
                : isMulti
                    ? FilledButton.icon(
                        onPressed: () async {
                          setState(() => _saving = true);
                          await widget.onSaveBatch(_previews);
                        },
                        style: FilledButton.styleFrom(backgroundColor: Sandik.amber, foregroundColor: Sandik.dark),
                        icon: const Icon(Icons.playlist_add_check_rounded),
                        label: Text('${_previews.length} varlığı kaydet',
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
                      )
                    : FilledButton.icon(
                        onPressed: _previews.isEmpty
                            ? null
                            : () => widget.onConfirmSingle(_previews.first),
                        style: FilledButton.styleFrom(backgroundColor: Sandik.amber, foregroundColor: Sandik.dark),
                        icon: const Icon(Icons.check_rounded),
                        label: Text('Formu doldur',
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
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
      title: 'BIST 100',
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

  @override
  void initState() {
    super.initState();
    _load();
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
      onSearch: (v) => setState(() => _q = v),
      query: _q,
      cs: cs,
      child: _funds == null && _error == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AssetType.fon.color),
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
                borderRadius: BorderRadius.circular(2)),
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
                    borderRadius: BorderRadius.circular(8),
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
                borderRadius: BorderRadius.circular(12),
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
                borderRadius: BorderRadius.circular(10),
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
