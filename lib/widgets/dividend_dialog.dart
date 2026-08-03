import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import 'custom_loading_indicator.dart';

/// Nakit temettü kaydı.
///
/// Temettü **miktarı değiştirmez** — eline geçen parayı kaydeder ve getiriye
/// eklenir. Kullanıcı stopaj sonrası NET tutarı girer; uygulama vergi hesabı
/// yapmaz (yatırım/vergi tavsiyesi vermemek için bilinçli tercih).
Future<void> showDividendDialog(
  BuildContext context,
  WidgetRef ref, {
  required Asset asset,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DividendDialog(asset: asset, ref: ref),
  );
}

class _DividendDialog extends StatefulWidget {
  final Asset asset;
  final WidgetRef ref;

  const _DividendDialog({required this.asset, required this.ref});

  @override
  State<_DividendDialog> createState() => _DividendDialogState();
}

class _DividendDialogState extends State<_DividendDialog> {
  final _amount = TextEditingController();
  late DateTime _paidAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paidAt = DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? _parse(String raw) {
    final t = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _save() async {
    final amount = _parse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Geçerli bir tutar girin');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.ref.read(portfolioProvider.notifier).addDividend(
            asset: widget.asset,
            amount: amount,
            paidAt: _paidAt,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temettü kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kaydedilemedi: $e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickSandikDate(
      context,
      initialDate: _paidAt,
      helpText: 'Temettü ödeme tarihi',
    );
    if (picked != null) setState(() => _paidAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final dateFmt = DateFormat('dd/MM/yyyy', 'tr_TR');

    return AlertDialog(
      backgroundColor: Sandik.surface2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      title: Row(
        children: [
          const Icon(Icons.savings_outlined, color: Sandik.gain, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Temettü Ekle',
                style: context.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.displayTicker ?? a.name} · ele geçen net tutar',
            style: context.t.bodySmall?.copyWith(color: Sandik.text58),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: context.t.titleMedium?.copyWith(color: Colors.white),
            decoration: InputDecoration(
              hintText: '0',
              suffixText: a.currency,
              suffixStyle: context.t.titleSmall?.copyWith(
                  color: Sandik.text58, fontWeight: FontWeight.w700),
              filled: true,
              fillColor: Sandik.surface1,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SandikRadius.sm),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
          const SizedBox(height: 12),
          // Ödeme tarihi — TRY karşılığı bu günün kuruyla sabitlenir.
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 18, color: Sandik.text58),
                  const SizedBox(width: 8),
                  Text('Ödeme tarihi: ${dateFmt.format(_paidAt)}',
                      style:
                          context.t.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Temettü miktarı değiştirmez; toplam getirine eklenir.',
            style: context.t.bodySmall?.copyWith(color: Sandik.text36),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: context.t.bodySmall
                    ?.copyWith(color: const Color(0xFFEF4444))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Sandik.gain),
          onPressed: _saving ? null : _save,
          // Buton kutusuna sığacak boyut verilmeli: CustomLoadingView
          // varsayılanı `large` ve 18pt'lik kutuyu taşırıyordu.
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomLoadingIndicator(size: 18),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}
