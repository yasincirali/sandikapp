import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';

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
        final addQty = qty;
        final addPrice = _parse(_priceCtrl.text)!;
        final existingCost = asset.quantity * asset.purchasePrice;
        final addedCost = addQty * addPrice;
        final newQty = asset.quantity + addQty;
        final newAvgPrice =
            newQty > 0 ? (existingCost + addedCost) / newQty : addPrice;
        asset
          ..quantity = newQty
          ..purchasePrice = newAvgPrice;
        await notifier.updateAsset(asset);
      } else {
        final newQty = asset.quantity - qty;
        if (newQty <= 0.0000001) {
          await notifier.deleteAsset(asset.id);
        } else {
          asset.quantity = newQty;
          await notifier.updateAsset(asset);
        }
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
    final accent = _isAdd ? Sandik.gain : Sandik.loss;
    final qty = _parse(_qtyCtrl.text) ?? 0;
    final price = _parse(_priceCtrl.text) ?? 0;
    final total = qty * (_isAdd ? price : asset.purchasePrice);

    return Dialog(
      backgroundColor: Sandik.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    borderRadius: BorderRadius.circular(10),
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
                        style: GoogleFonts.dmSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: Sandik.text58,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Sandik.text58, size: 22),
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
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('Mevcut',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: Sandik.text36)),
                  const Spacer(),
                  Text(
                    '${numFmt.format(asset.quantity)} $_unitLabel · '
                    'ort. ${numFmt.format(asset.purchasePrice)} $_currencySymbol',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Miktar ────────────────────────────────────────────────
            Text('Miktar',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Sandik.text58)),
            const SizedBox(height: 6),
            TextField(
              controller: _qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle:
                    GoogleFonts.dmSans(color: Sandik.text36, fontSize: 18),
                suffixText: _unitLabel,
                suffixStyle:
                    GoogleFonts.dmSans(color: Sandik.text58, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _quickChips(),

            // ── Fiyat (sadece ekleme için) ────────────────────────────
            if (_isAdd) ...[
              const SizedBox(height: 16),
              Text('Birim fiyat',
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Sandik.text58)),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: GoogleFonts.dmSans(
                    fontSize: 16, color: Colors.white),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle:
                      GoogleFonts.dmSans(color: Sandik.text36, fontSize: 16),
                  suffixText: _currencySymbol,
                  suffixStyle:
                      GoogleFonts.dmSans(color: Sandik.text58, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.25), width: 1),
                ),
                child: Row(
                  children: [
                    Text(_isAdd ? 'Toplam maliyet' : 'Çıkarılan değer',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: Sandik.text58)),
                    const Spacer(),
                    Text(
                      '${numFmt.format(total)} $_currencySymbol',
                      style: GoogleFonts.dmSans(
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
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: Sandik.loss),
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
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('İptal',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
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
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isAdd ? 'Ekle' : 'Çıkar',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
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
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p == _fmt(widget.asset.quantity) && !_isAdd
                        ? 'Hepsi ($p)'
                        : p,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
