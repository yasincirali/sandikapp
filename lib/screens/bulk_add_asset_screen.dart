import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/bulk_cart_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/price_service.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'add_asset_screen.dart';

class BulkAddAssetScreen extends ConsumerStatefulWidget {
  const BulkAddAssetScreen({super.key});

  @override
  ConsumerState<BulkAddAssetScreen> createState() =>
      _BulkAddAssetScreenState();
}

class _BulkAddAssetScreenState extends ConsumerState<BulkAddAssetScreen> {
  bool _saving = false;
  int _saved = 0;

  Future<void> _openAddForm({BulkCartItem? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddAssetScreen(
          cartMode: true,
          cartInitial: existing,
        ),
      ),
    );
  }

  Future<void> _saveAll() async {
    final items = ref.read(bulkCartProvider);
    if (items.isEmpty) return;

    setState(() {
      _saving = true;
      _saved = 0;
    });

    final failures = <String>[];
    final portfolio = ref.read(portfolioProvider.notifier);

    for (final item in items) {
      try {
        var price = item.price;
        if (price <= 0 && item.ticker.isNotEmpty) {
          try {
            if (item.ticker.startsWith('TEFAS:')) {
              final code = item.ticker.replaceFirst('TEFAS:', '');
              final prices =
                  await TefasService.instance.fetchPrices([code]);
              price = prices[code] ?? 0.0;
            } else {
              final quotes =
                  await PriceService.instance.fetchQuotes([item.ticker]);
              final q = quotes[item.ticker.toUpperCase()];
              if (q?.regularMarketPrice != null &&
                  q!.regularMarketPrice! > 0) {
                price = q.regularMarketPrice!;
              }
            }
          } catch (_) {}
        }
        await portfolio.addAsset(
          name: item.name,
          ticker: item.ticker,
          type: item.type,
          quantity: item.quantity,
          purchasePrice: price,
          currency: item.currency,
          notes: '',
          isManualPrice: item.isManualPrice,
          subCategory: item.subCategory,
          unitType: item.unitType,
        );
        if (mounted) setState(() => _saved++);
      } catch (e) {
        failures.add('${item.name}: ${e.toString()}');
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (failures.isEmpty) {
      ref.read(bulkCartProvider.notifier).clear();
      await showAppSuccess(
        context,
        title: 'Tümü Eklendi',
        message: '${items.length} varlık portföyüne eklendi.',
      );
      if (mounted) Navigator.of(context).pop();
    } else {
      await showSandikDialog(
        context: context,
        kind: SandikDialogKind.error,
        title: 'Bazı Varlıklar Eklenemedi',
        message:
            '${items.length - failures.length}/${items.length} eklendi.\n\nBaşarısız:\n${failures.take(3).join('\n')}',
      );
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sandik.surface1,
        title: const Text('Sepeti Temizle',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Sepetteki tüm varlıklar silinecek. Emin misin?',
          style: GoogleFonts.dmSans(color: Sandik.text58),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle',
                style: TextStyle(color: Sandik.loss)),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(bulkCartProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(bulkCartProvider);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Sandik.background,
        appBar: AppBar(
          title: Text('Toplu Ekle${items.isEmpty ? '' : ' (${items.length})'}'),
          actions: [
            if (items.isNotEmpty && !_saving)
              IconButton(
                tooltip: 'Sepeti temizle',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _confirmClear,
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: items.isEmpty ? _emptyState() : _list(items),
            ),
            _bottomBar(items),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Sandik.amber.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Sandik.amber.withValues(alpha: 0.30), width: 1),
              ),
              child: const Icon(Icons.playlist_add_rounded,
                  color: Sandik.amber, size: 34),
            ),
            const SizedBox(height: 16),
            Text('Sepet boş',
                style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              'Aşağıdaki + Varlık Ekle butonuyla art arda varlık ekleyip hepsini tek seferde kaydedebilirsin.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: Sandik.text58, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<BulkCartItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        return _BulkItemTile(
          item: it,
          onEdit: _saving ? null : () => _openAddForm(existing: it),
          onDelete: _saving
              ? null
              : () => ref.read(bulkCartProvider.notifier).remove(it.id),
        );
      },
    );
  }

  Widget _bottomBar(List<BulkCartItem> items) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _openAddForm(),
                icon: const Icon(Icons.add_rounded, color: Sandik.amber),
                label: Text(
                  'Varlık Ekle',
                  style: GoogleFonts.dmSans(
                      color: Sandik.amber,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: Sandik.amber.withValues(alpha: 0.45), width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed:
                    _saving || items.isEmpty ? null : _saveAll,
                style: FilledButton.styleFrom(
                  backgroundColor: Sandik.amber,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      Sandik.amber.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Kaydediliyor $_saved / ${items.length}',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ],
                      )
                    : Text(
                        items.isEmpty
                            ? 'Kaydet'
                            : 'Tümünü Kaydet (${items.length})',
                        style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liste kartı
// ─────────────────────────────────────────────────────────────────────────────

class _BulkItemTile extends StatelessWidget {
  const _BulkItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final BulkCartItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  String _unitLabel() {
    switch (item.unitType) {
      case 'gram':
        return 'gr';
      case 'ounce':
        return 'oz';
      case 'kilogram':
        return 'kg';
      case 'liter':
        return 'lt';
      case 'barrel':
        return 'bbl';
      default:
        return 'adet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      '${_fmt(item.quantity)} ${_unitLabel()}',
      if (item.price > 0) '${_fmt(item.price)} ${item.currency}',
      if (item.price <= 0) 'Fiyat otomatik',
      if (item.subCategory != null && item.subCategory!.isNotEmpty)
        item.subCategory!,
    ].join(' · ');

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.type.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.type.icon, color: item.type.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.isEmpty ? item.type.label : item.name,
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          color: Sandik.text58, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined,
                  color: Sandik.text58, size: 20),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded,
                  color: Sandik.text58, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
