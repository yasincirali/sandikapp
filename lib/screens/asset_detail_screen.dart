import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import 'add_asset_screen.dart';

class AssetDetailScreen extends ConsumerStatefulWidget {
  final Asset asset;
  const AssetDetailScreen({super.key, required this.asset});

  @override
  ConsumerState<AssetDetailScreen> createState() =>
      _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  final _manualPriceCtrl = TextEditingController();

  @override
  void dispose() {
    _manualPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(portfolioProvider).valueOrNull;
    final asset = widget.asset;
    final valueTRY =
        s != null ? s.toTRY(asset.totalValue, asset.currency) : asset.totalValue;
    final isPositive = asset.gainLoss >= 0;
    final gainColor = isPositive ? Colors.green : Colors.red;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.####', 'tr_TR');

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddAssetScreen(editingAsset: asset)),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ---- Header card ----
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: asset.type.color.withValues(alpha: 0.15),
                    child: Icon(asset.type.icon,
                        color: asset.type.color, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(asset.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(tryFmt.format(valueTRY),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                        color: gainColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${numFmt.format(asset.gainLoss)} ${asset.currency}'
                        '  (%${asset.gainLossPercentage.toStringAsFixed(2)})',
                        style: TextStyle(
                            color: gainColor, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ---- Details ----
          _card(context, 'Varlık Bilgileri', [
            _row(context, 'Tür', asset.type.label),
            if (asset.ticker.isNotEmpty)
              _row(context, 'Sembol', asset.ticker),
            _row(context, 'Miktar', numFmt.format(asset.quantity)),
            _row(context, 'Alış Fiyatı',
                '${numFmt.format(asset.purchasePrice)} ${asset.currency}'),
            _row(context, 'Güncel Fiyat',
                '${numFmt.format(asset.currentPrice)} ${asset.currency}'),
            _row(context, 'Toplam Maliyet (TL)',
                tryFmt.format(s != null
                    ? s.toTRY(asset.totalCost, asset.currency)
                    : asset.totalCost)),
            if (asset.lastUpdated != null)
              _row(context, 'Son Güncelleme',
                  DateFormat('dd.MM.yyyy HH:mm').format(asset.lastUpdated!)),
          ]),

          // ---- Manual price update ----
          if (asset.isManualPrice || asset.ticker.isEmpty)
            _card(context, 'Fiyat Güncelle', [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualPriceCtrl,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Güncel fiyat',
                        suffixText: asset.currency,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final p = double.tryParse(
                          _manualPriceCtrl.text.replaceAll(',', '.'));
                      if (p != null) {
                        ref
                            .read(portfolioProvider.notifier)
                            .updateManualPrice(asset, p);
                        _manualPriceCtrl.clear();
                      }
                    },
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ]),

          // ---- Notes ----
          if (asset.notes.isNotEmpty)
            _card(context, 'Notlar', [
              Text(asset.notes,
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),

          // ---- Delete ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: OutlinedButton.icon(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
              label: const Text('Varlığı Sil',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext ctx, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary)),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _row(BuildContext ctx, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    color:
                        Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  void _confirmDelete(BuildContext ctx) => showDialog(
        context: ctx,
        builder: (dlg) => AlertDialog(
          title: const Text('Varlığı Sil'),
          content: Text(
              '"${widget.asset.name}" silinsin mi? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('İptal')),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                ref
                    .read(portfolioProvider.notifier)
                    .deleteAsset(widget.asset.id);
                Navigator.pop(dlg);
                Navigator.pop(ctx);
              },
              child: const Text('Sil'),
            ),
          ],
        ),
      );
}
