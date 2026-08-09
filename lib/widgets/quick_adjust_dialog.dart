import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import 'custom_loading_indicator.dart';

/// Bir varlığa hızlıca miktar EKLE veya ÇIKAR — form açmadan.
///
/// Ekle: yeni miktar + birim fiyat girer, ağırlıklı ortalama maliyet
/// yeniden hesaplanır (mevcut maliyet + yeni maliyet) / toplam adet.
///
/// Çıkar: sadece miktar girer; alış fiyatı (birim maliyet) korunur.
/// Miktar sıfıra düşerse varlık silinir.
enum QuickAdjustMode { add, remove }

Future<void> showQuickAdjustDialog(
  BuildContext context,
  WidgetRef ref, {
  required Asset asset,
  required QuickAdjustMode mode,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _QuickAdjustDialog(asset: asset, mode: mode, ref: ref),
  );
}

class _QuickAdjustDialog extends StatefulWidget {
  final Asset asset;
  final QuickAdjustMode mode;
  final WidgetRef ref;

  const _QuickAdjustDialog({
    required this.asset,
    required this.mode,
    required this.ref,
  });

  @override
  State<_QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<_QuickAdjustDialog> {
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isAdd => widget.mode == QuickAdjustMode.add;

  @override
  void initState() {
    super.initState();
    if (_isAdd) {
      final currentPrice = widget.asset.currentPrice > 0
          ? widget.asset.currentPrice
          : widget.asset.purchasePrice;
      if (currentPrice > 0) {
        _priceCtrl.text = _fmt(currentPrice);
      }
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String text) {
    if (text.trim().isEmpty) return null;
    final val = double.tryParse(text.trim().replaceAll(',', '.'));
    if (val == null || !val.isFinite) return null;
    return val;
  }

  String get _unitLabel => widget.asset.unitLabel;

  String get _currencySymbol {
    switch (widget.asset.currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '₺';
    }
  }

  Future<void> _submit() async {
    final qty = _parse(_qtyCtrl.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Geçerli bir miktar gir');
      return;
    }

    if (_isAdd) {
      final price = _parse(_priceCtrl.text);
      if (price == null || price <= 0) {
        setState(() => _error = 'Geçerli bir birim fiyat gir');
        return;
      }
    } else {
      if (qty > widget.asset.quantity) {
        setState(() => _error =
            'Mevcut miktarı (${_fmt(widget.asset.quantity)}) aşamazsın');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final asset = widget.asset;
      final notifier = widget.ref.read(portfolioProvider.notifier);

      if (_isAdd) {
        final addPrice = _parse(_priceCtrl.text)!;
        await notifier.addAsset(
          name: asset.name,
          ticker: asset.ticker,
          type: asset.type,
          quantity: qty,
          purchasePrice: addPrice,
          currency: asset.currency,
          notes: asset.notes,
          isManualPrice: asset.isManualPrice,
          subCategory: asset.subCategory,
          unitType: asset.unitType,
        );
      } else {
        await notifier.addSellTransaction(
          asset: asset,
          quantity: qty,
          sellPrice: asset.currentPrice > 0 ? asset.currentPrice : asset.purchasePrice,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAdd
              ? '${_fmt(qty)} $_unitLabel eklendi'
              : '${_fmt(qty)} $_unitLabel çıkarıldı'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'İşlem başarısız: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final numFmt = NumberFormat('#,##0.####', 'tr_TR');
    final accent = _isAdd ? context.c.gain : context.c.loss;
    final qty = _parse(_qtyCtrl.text) ?? 0;
    final price = _parse(_priceCtrl.text) ?? 0;
    final total = qty * (_isAdd ? price : asset.purchasePrice);

    return Dialog(
      backgroundColor: context.c.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SandikRadius.lg)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Başlık ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                  ),
                  child: Icon(
                    _isAdd ? Icons.add_rounded : Icons.remove_rounded,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAdd ? 'Ekle' : 'Çıkar',
                        style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.c.text90,
                        ),
                      ),
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.titleSmall?.copyWith(
                          color: context.c.text58,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: context.c.text58, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Mevcut durum ──────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: Row(
                children: [
                  Text('Mevcut',
                      style: context.t.bodySmall?.copyWith(color: context.c.text36)),
                  const Spacer(),
                  Text(
                    '${numFmt.format(asset.quantity)} $_unitLabel · '
                    'ort. ${numFmt.format(asset.purchasePrice)} $_currencySymbol',
                    style: context.t.numSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.c.text90,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Miktar ────────────────────────────────────────────────
            Text('Miktar',
                style: context.t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.c.text58)),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              style: context.t.numLarge.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.c.text90),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle:
                    context.t.headlineSmall?.copyWith(color: context.c.text36),
                suffixText: _unitLabel,
                suffixStyle:
                    context.t.titleMedium?.copyWith(color: context.c.text58),
                filled: true,
                fillColor: context.c.overlay,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _quickChips(),

            // Remove modunda tüm miktarı çıkarırken kısa bilgi: bu bir
            // "satış" kaydı; delete değil. Kullanıcı "sattım = sil" diye
            // düşünmesin diye net bir metinle ayrımı vurguluyoruz.
            if (!_isAdd && qty > 0 && (qty - asset.quantity).abs() < 0.0001)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: context.c.amberText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tüm miktarı çıkarıyorsun — pozisyon listeden '
                          'kalkar ama bu bir satış kaydı olarak durur. '
                          'İşlem geçmişin ve realize kâr/zararın korunur. '
                          'Kaydı tamamen silmek istiyorsan varlık detayından '
                          '"Sil"i kullan.',
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.text58,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Fiyat (sadece ekleme için) ────────────────────────────
            if (_isAdd) ...[
              const SizedBox(height: 16),
              Text('Birim fiyat',
                  style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text58)),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: context.t.numMedium.copyWith(
                    fontWeight: FontWeight.w500, color: context.c.text90),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle:
                      context.t.titleLarge?.copyWith(color: context.c.text36),
                  suffixText: _currencySymbol,
                  suffixStyle:
                      context.t.titleMedium?.copyWith(color: context.c.text58),
                  filled: true,
                  fillColor: context.c.overlay,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],

            // ── Toplam önizleme ──────────────────────────────────────
            if (qty > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.25), width: 1),
                ),
                child: Row(
                  children: [
                    Text(_isAdd ? 'Toplam maliyet' : 'Çıkarılan değer',
                        style: context.t.titleSmall?.copyWith(color: context.c.text58)),
                    const Spacer(),
                    Text(
                      '${numFmt.format(total)} $_currencySymbol',
                      style: context.t.numSmall.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: context.t.titleSmall?.copyWith(color: context.c.loss),
              ),
            ],

            const SizedBox(height: 20),

            // ── Butonlar ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: context.c.overlay,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: Text('İptal',
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.text90)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SandikRadius.md)),
                    ),
                    child: _saving
                        ? const CustomLoadingIndicator(size: 18)
                        : Text(_isAdd ? 'Ekle' : 'Çıkar',
                            style: context.t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.c.text90)),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _quickChips() {
    // Varlığın türüne göre hızlı miktar önerileri
    final presets = <String>[];
    final unit = widget.asset.unitType;
    if (unit == 'gram') {
      presets.addAll(['1', '5', '10', '50']);
    } else if (unit == 'ounce') {
      presets.addAll(['0.1', '0.5', '1']);
    } else if (widget.asset.type == AssetType.doviz) {
      presets.addAll(['10', '50', '100', '500']);
    } else if (widget.asset.type == AssetType.fon ||
        widget.asset.type == AssetType.hisse) {
      presets.addAll(['1', '10', '100', '1000']);
    } else {
      presets.addAll(['1', '5', '10', '100']);
    }
    // Çıkar modunda "hepsi" seçeneği
    if (!_isAdd) presets.add(_fmt(widget.asset.quantity));

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() {
                  _qtyCtrl.text = p;
                  _error = null;
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.c.overlay,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p == _fmt(widget.asset.quantity) && !_isAdd
                        ? 'Hepsi ($p)'
                        : p,
                    style: context.t.numSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.c.text90,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
