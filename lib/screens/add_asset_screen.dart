import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';

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
  late String _currency;
  late bool _isManualPrice;

  static const _currencies = ['TRY', 'USD', 'EUR', 'GBP'];
  bool get _isEditing => widget.editingAsset != null;

  @override
  void initState() {
    super.initState();
    final a = widget.editingAsset;
    _name = TextEditingController(text: a?.name ?? '');
    _ticker = TextEditingController(text: a?.ticker ?? '');
    _quantity = TextEditingController(
        text: a != null ? _fmt(a.quantity) : '');
    _price = TextEditingController(
        text: a != null ? _fmt(a.purchasePrice) : '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _type = a?.type ?? AssetType.hisse;
    _currency = a?.currency ?? AssetType.hisse.defaultCurrency;
    _isManualPrice = a?.isManualPrice ?? false;
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

  double? _parse(String text) =>
      double.tryParse(text.replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Varlığı Düzenle' : 'Yeni Varlık Ekle'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              _isEditing ? 'Güncelle' : 'Ekle',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Varlık Türü', [_typeDropdown()]),
            const SizedBox(height: 16),
            _section('Genel Bilgiler', [
              _field(_name, 'Varlık adı', hint: 'Örn: Türk Hava Yolları',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ad zorunludur' : null),
              const SizedBox(height: 12),
              _tickerField(),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _isManualPrice,
                onChanged: (v) => setState(() => _isManualPrice = v),
                title: const Text('Manuel fiyat gir'),
                subtitle: const Text('Sembol kullanma'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ]),
            const SizedBox(height: 16),
            _section('Miktar ve Fiyat', [
              _field(_quantity, 'Adet / Miktar',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      _parse(v ?? '') == null ? 'Geçerli miktar girin' : null,
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(_price, 'Alış Fiyatı',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (v) =>
                            _parse(v ?? '') == null
                                ? 'Geçerli fiyat girin'
                                : null,
                        onChanged: (_) => setState(() {})),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 110, child: _currencyDropdown()),
                ],
              ),
              _totalPreview(),
            ]),
            const SizedBox(height: 16),
            _section('Notlar (opsiyonel)', [
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Notlarınız...',
                ),
                maxLines: 3,
              ),
            ]),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ---- Widget helpers -------------------------------------------------------

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...children,
        ],
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) =>
      TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          hintText: hint,
        ),
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
      );

  Widget _typeDropdown() => InputDecorator(
        decoration: const InputDecoration(
            border: OutlineInputBorder(), labelText: 'Tür'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<AssetType>(
            value: _type,
            isDense: true,
            items: AssetType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Row(children: [
                        Icon(t.icon, color: t.color, size: 18),
                        const SizedBox(width: 8),
                        Text(t.label),
                      ]),
                    ))
                .toList(),
            onChanged: (t) {
              if (t == null) return;
              setState(() {
                _type = t;
                _currency = t.defaultCurrency;
              });
            },
          ),
        ),
      );

  Widget _tickerField() => TextFormField(
        controller: _ticker,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Yahoo Finance Sembolü (opsiyonel)',
          helperText: _type.tickerHint,
          helperMaxLines: 2,
        ),
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        onChanged: (v) {
          if (v.isEmpty) setState(() => _isManualPrice = true);
        },
      );

  Widget _currencyDropdown() => InputDecorator(
        decoration: const InputDecoration(
            border: OutlineInputBorder(), labelText: 'Para'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currency,
            isDense: true,
            items: _currencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _currency = v ?? _currency),
          ),
        ),
      );

  Widget _totalPreview() {
    final qty = _parse(_quantity.text);
    final price = _parse(_price.text);
    if (qty == null || price == null) return const SizedBox.shrink();
    final total = qty * price;
    final fmt = total == total.truncateToDouble()
        ? total.toInt().toString()
        : total.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text('Toplam: $fmt $_currency',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ---- Save -----------------------------------------------------------------

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final qty = _parse(_quantity.text)!;
    final price = _parse(_price.text)!;
    final ticker =
        _isManualPrice ? '' : _ticker.text.trim().toUpperCase();
    final manual = _isManualPrice || ticker.isEmpty;

    if (_isEditing) {
      final a = widget.editingAsset!;
      a
        ..name = _name.text.trim()
        ..ticker = ticker
        ..type = _type
        ..quantity = qty
        ..purchasePrice = price
        ..currency = _currency
        ..notes = _notes.text.trim()
        ..isManualPrice = manual;
      ref.read(portfolioProvider.notifier).updateAsset(a);
    } else {
      ref.read(portfolioProvider.notifier).addAsset(
            name: _name.text.trim(),
            ticker: ticker,
            type: _type,
            quantity: qty,
            purchasePrice: price,
            currency: _currency,
            notes: _notes.text.trim(),
            isManualPrice: manual,
          );
    }
    Navigator.pop(context);
  }
}
