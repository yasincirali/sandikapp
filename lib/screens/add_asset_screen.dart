import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/asset_categories.dart';
import '../providers/portfolio_provider.dart';
import '../services/price_service.dart';
import '../services/tefas_service.dart';

// ─── Döviz sabitleri ───────────────────────────────────────────────────────────

typedef _DovizOpt = ({String label, String ticker, String name, String symbol});

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
  const AddAssetScreen({super.key, this.editingAsset});

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
    _name = TextEditingController(text: a?.name ?? '');
    _ticker = TextEditingController(text: a?.ticker ?? '');
    _quantity = TextEditingController(text: a != null ? _fmt(a.quantity) : '');
    _price = TextEditingController(
        text: a != null && a.purchasePrice > 0 ? _fmt(a.purchasePrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _type = a?.type ?? AssetType.hisse;
    _subCategory = a?.subCategory;
    _unitType = a?.unitType ?? 'piece';
    _currency = a?.currency ?? AssetType.hisse.defaultCurrency;
    _isManualPrice = a?.isManualPrice ?? false;

    if (a != null) {
      if (a.type == AssetType.hisse &&
          a.subCategory == StockSubCategory.bist100.label &&
          a.ticker.isNotEmpty) {
        _bist100SelectedTicker = a.ticker;
      }
      if (a.type == AssetType.fon && a.ticker.startsWith('TEFAS:')) {
        final code = a.ticker.replaceFirst('TEFAS:', '');
        _selectedFund = TefasFund(
            code: code, name: a.name, price: a.currentPrice, fundType: '', managerName: '');
      }
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

  List<String> _getSubCategories() {
    switch (_type) {
      case AssetType.altin:
        return GoldSubCategory.values.map((g) => g.label).toList();
      case AssetType.doviz:
        return _dovizOptions.map((o) => o.label).toList();
      case AssetType.hisse:
        return StockSubCategory.values.map((s) => s.label).toList();
      default:
        return [];
    }
  }

  String _getUnitTypeForSubCategory(String subCat) {
    if (_type == AssetType.altin) {
      final gold = GoldSubCategory.values.firstWhere(
        (g) => g.label == subCat,
        orElse: () => GoldSubCategory.gr22,
      );
      return gold.unitType;
    }
    return 'piece';
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subCategories = _getSubCategories();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(_isEditing ? 'Düzenle' : 'Varlık Ekle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                minimumSize: const Size(0, 36),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEditing ? 'Güncelle' : 'Ekle'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            // Varlık Türü
            _label('Varlık Türü'),
            const SizedBox(height: 8),
            _typeSelector(cs),
            const SizedBox(height: 20),

            // Alt kategori (hisse / altın / döviz)
            if (subCategories.isNotEmpty) ...[
              _label(_type == AssetType.doviz ? 'Para Birimi' : 'Alt Kategori'),
              const SizedBox(height: 8),
              _subCategoryWidget(cs),
              const SizedBox(height: 20),
            ],

            // BIST100 seçici
            if (_isBist100) ...[
              _label('Hisse Seç'),
              const SizedBox(height: 8),
              _bist100SelectorField(cs),
              const SizedBox(height: 20),
            ]
            // TEFAS fon seçici
            else if (_isFon) ...[
              _label('Fon Seç'),
              const SizedBox(height: 8),
              _tefasSelectorField(cs),
              const SizedBox(height: 20),
            ] else ...[
              if (_type != AssetType.altin && !_isDoviz) ...[
                _label('Varlık Adı'),
                const SizedBox(height: 8),
                _inputField(_name,
                    hint: 'Örn: Apple Inc.',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ad zorunludur'
                        : null),
                const SizedBox(height: 20),
              ],
              if (_type == AssetType.hisse) ...[
                _label('Sembol (opsiyonel)'),
                const SizedBox(height: 8),
                _tickerInputField(cs),
                const SizedBox(height: 8),
                _manualSwitch(cs),
                const SizedBox(height: 20),
              ],
            ],

            // Miktar
            _label('Miktar'),
            const SizedBox(height: 8),
            _inputField(
              _quantity,
              hint: '0',
              suffix: _quantitySuffix,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_DecimalFormatter()],
              validator: (v) =>
                  (_parse(v ?? '') == null || (_parse(v ?? '') ?? 0) <= 0)
                      ? 'Geçerli miktar girin'
                      : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _quantityPresetsRow(cs),
            const SizedBox(height: 16),

            // Alış fiyatı + para birimi
            _label('Alış Fiyatı (opsiyonel)'),
            const SizedBox(height: 4),
            Text(
              'Boş bırakılırsa güncel piyasa fiyatı kullanılır',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _inputField(
                    _price,
                    hint: '0.00',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalFormatter()],
                    validator: (v) =>
                        v != null && v.trim().isNotEmpty && _parse(v) == null
                            ? 'Geçerli fiyat girin'
                            : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (!_isDoviz) ...[
                  const SizedBox(width: 10),
                  SizedBox(width: 100, child: _currencySelector(cs)),
                ],
              ],
            ),

            _totalPreview(cs),
            const SizedBox(height: 20),

            // Notlar
            _label('Notlar (opsiyonel)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Notlarınız...',
                hintStyle: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.6)),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );

  // ── Varlık türü seçici ─────────────────────────────────────────────────────

  Widget _typeSelector(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: AssetType.values.map((t) {
          final selected = _type == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _type = t;
                _subCategory = null;
                _unitType = 'piece';
                _currency = t.defaultCurrency;
                _bist100SelectedTicker = null;
                _selectedFund = null;
                _ticker.clear();
                _name.clear();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? t.color.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? t.color
                        : cs.outlineVariant.withValues(alpha: 0.4),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon,
                        size: 16,
                        color: selected ? t.color : cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(t.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? t.color : cs.onSurface,
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

  // ── Alt kategori widget router ─────────────────────────────────────────────

  Widget _subCategoryWidget(ColorScheme cs) {
    if (_type == AssetType.doviz) return _dovizSelector(cs);
    if (_type == AssetType.altin) return _goldSubCategoryWidget(cs);
    return _bubbleSelector(_getSubCategories(), cs);
  }

  // ── Döviz para birimi seçici ───────────────────────────────────────────────

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
                _currency = 'TRY'; // doviz her zaman TRY bazlı
                _isManualPrice = opt.ticker.isEmpty;
                _name.text = opt.name;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AssetType.doviz.color.withValues(alpha: 0.14)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AssetType.doviz.color
                        : cs.outlineVariant.withValues(alpha: 0.35),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opt.symbol,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: selected ? AssetType.doviz.color : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AssetType.doviz.color
                            : cs.onSurfaceVariant,
                        letterSpacing: 0.5,
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

  // ── Altın alt kategori (bubble + dropdown) ─────────────────────────────────

  Widget _goldSubCategoryWidget(ColorScheme cs) {
    final cats = GoldSubCategory.values.map((g) => g.label).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bubble buttons
        _bubbleSelector(cats, cs),
        const SizedBox(height: 10),
        // Dropdown — alternative selection
        DropdownButtonFormField<String>(
          initialValue: _subCategory,
          decoration: InputDecoration(
            hintText: 'Listeden seç...',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon: Icon(Icons.star_rounded,
                color: AssetType.altin.color, size: 18),
          ),
          items: cats
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: const TextStyle(fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _subCategory = v;
              _unitType = _getUnitTypeForSubCategory(v);
            });
          },
        ),
      ],
    );
  }

  // ── Genel bubble seçici ────────────────────────────────────────────────────

  Widget _bubbleSelector(List<String> cats, ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cats.map((cat) {
        final selected = _subCategory == cat;
        return GestureDetector(
          onTap: () => setState(() {
            _subCategory = cat;
            _unitType = _getUnitTypeForSubCategory(cat);
            _bist100SelectedTicker = null;
            _ticker.clear();
            _name.clear();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _type.color.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? _type.color
                    : cs.outlineVariant.withValues(alpha: 0.35),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(cat,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? _type.color : cs.onSurface,
                )),
          ),
        );
      }).toList(),
    );
  }

  // ── Miktar preset chipleri ─────────────────────────────────────────────────

  Widget _quantityPresetsRow(ColorScheme cs) {
    final presets = _quantityPresets;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
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
                      ? cs.primary.withValues(alpha: 0.12)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.4)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _getUnitLabel(_unitType),
                      style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? cs.primary.withValues(alpha: 0.7)
                            : cs.onSurfaceVariant.withValues(alpha: 0.6),
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
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? cs.error
              : (hasValue ? color : cs.outlineVariant.withValues(alpha: 0.4)),
          width: hasValue ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (badgeText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badgeText,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              mainText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                color: hasValue
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }

  // ── Input fields ───────────────────────────────────────────────────────────

  Widget _inputField(
    TextEditingController ctrl, {
    String? hint,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) =>
      TextFormField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffix,
          suffixStyle: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: onChanged,
      );

  Widget _tickerInputField(ColorScheme cs) => TextFormField(
        controller: _ticker,
        style: const TextStyle(fontSize: 14),
        decoration:
            InputDecoration(hintText: _type.tickerHint, hintMaxLines: 2),
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        onChanged: (v) {
          if (v.isEmpty) setState(() => _isManualPrice = true);
        },
      );

  Widget _manualSwitch(ColorScheme cs) => Row(
        children: [
          Expanded(
            child: Text('Manuel fiyat gir (sembol kullanma)',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Switch(
            value: _isManualPrice,
            onChanged: (v) => setState(() => _isManualPrice = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      );

  Widget _currencySelector(ColorScheme cs) => Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.4), width: 1),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currency,
            isDense: true,
            icon: const SizedBox.shrink(),
            items: _currencies
                .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600))))
                .toList(),
            onChanged: (v) => setState(() => _currency = v ?? _currency),
          ),
        ),
      );

  Widget _totalPreview(ColorScheme cs) {
    final qty = _parse(_quantity.text);
    final price = _parse(_price.text);
    final isPriceEmpty =
        _price.text.trim().isEmpty || (price != null && price == 0);

    if (qty == null || qty <= 0) return const SizedBox.shrink();

    if (isPriceEmpty) {
      // Price will be fetched on save
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: cs.secondary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alış fiyatı boş — kaydederken güncel piyasa fiyatı otomatik atanacak.',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (price == null || price <= 0) return const SizedBox.shrink();

    final total = qty * price;
    final fmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.##', 'tr_TR');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text('Toplam maliyet',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const Spacer(),
            Text(
              _currency == 'TRY'
                  ? fmt.format(total)
                  : '${numFmt.format(total)} $_currency',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary),
            ),
          ],
        ),
      ),
    );
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.pop(context);
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
