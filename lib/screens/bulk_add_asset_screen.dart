import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/bulk_cart_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/price_service.dart';
import '../services/tefas_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'add_asset_screen.dart';
import 'paywall_screen.dart';

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

    // ── 1) Eksik fiyatları çek ─────────────────────────────────────────────
    // Bugün seçilmiş item'lar için toplu spot fetch (tek batch).
    // Geçmiş tarihli item'lar için per-item tarihsel kapanış fetch et —
    // aksi halde 6 ay önce alınmış varlık bugünkü fiyatla eklenir ve
    // portföy PnL'i yanlış görünür.
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final tefasCodes = <String>{};
    final yahooSymbols = <String>{};
    for (final item in items) {
      if (item.price > 0 || item.ticker.isEmpty) continue;
      if (!isToday(item.addedDate)) continue; // tarihsel için per-item fetch
      if (item.ticker.startsWith('TEFAS:')) {
        tefasCodes.add(item.ticker.replaceFirst('TEFAS:', ''));
      } else {
        yahooSymbols.add(item.ticker);
      }
    }

    final priceFetches = await Future.wait([
      if (tefasCodes.isNotEmpty)
        TefasService.instance.fetchPrices(tefasCodes.toList()).catchError(
            (_) => <String, double>{})
      else
        Future.value(<String, double>{}),
      if (yahooSymbols.isNotEmpty)
        PriceService.instance.fetchQuotes(yahooSymbols.toList()).catchError(
            (_) => <String, YahooQuote>{})
      else
        Future.value(<String, YahooQuote>{}),
    ]);
    final tefasPrices = priceFetches[0] as Map<String, double>;
    final yahooQuotes = priceFetches[1] as Map<String, YahooQuote>;

    // Geçmiş tarihli item'lar için tarihsel kapanış — paralel fetch.
    final historicalPrices = <String, double>{}; // key: itemId
    await Future.wait(items.where((it) {
      return it.price <= 0 &&
          it.ticker.isNotEmpty &&
          !isToday(it.addedDate);
    }).map((it) async {
      try {
        final hist = await PriceService.instance
            .fetchHistoricalClose(it.ticker, it.addedDate);
        if (hist != null && hist > 0) {
          historicalPrices[it.id] = hist;
        }
      } catch (_) {
        // Sessiz — resolvePrice fallback olarak spot deneyecek.
      }
    }));

    double resolvePrice(BulkCartItem item) {
      if (item.price > 0 || item.ticker.isEmpty) return item.price;
      // Tarihsel varsa onu kullan.
      final hist = historicalPrices[item.id];
      if (hist != null && hist > 0) return hist;
      // Bugün ya da tarihsel fetch başarısız → spot fallback.
      if (item.ticker.startsWith('TEFAS:')) {
        final code = item.ticker.replaceFirst('TEFAS:', '');
        return tefasPrices[code] ?? 0.0;
      }
      final q = yahooQuotes[item.ticker.toUpperCase()];
      if (q?.regularMarketPrice != null && q!.regularMarketPrice! > 0) {
        return q.regularMarketPrice!;
      }
      return 0.0;
    }

    // ── 2) Insert'leri paralel çalıştır ────────────────────────────────────
    bool limitHit = false;
    await Future.wait(items.map((item) async {
      try {
        await portfolio.addAsset(
          name: item.name,
          ticker: item.ticker,
          type: item.type,
          quantity: item.quantity,
          purchasePrice: resolvePrice(item),
          currency: item.currency,
          notes: '',
          isManualPrice: item.isManualPrice,
          subCategory: item.subCategory,
          unitType: item.unitType,
          addedDate: item.addedDate,
        );
        if (mounted) setState(() => _saved++);
      } on AssetLimitExceededException {
        limitHit = true;
        failures.add('${item.name}: varlık limitine ulaşıldı');
      } catch (e) {
        failures.add('${item.name}: ${e.toString()}');
      }
    }));

    if (limitHit && mounted) {
      setState(() => _saving = false);
      final upgraded = await PaywallScreen.show(
        context,
        source: 'bulk_add_asset_limit',
      );
      if (upgraded == true && mounted) {
        // Kullanıcı premium'a geçti — kalan item'ları tekrar dene.
        _saveAll();
      }
      return;
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
    final now = DateTime.now();
    final isToday = item.addedDate.year == now.year &&
        item.addedDate.month == now.month &&
        item.addedDate.day == now.day;
    final dateLabel = isToday
        ? null
        : DateFormat('d MMM yyyy', 'tr_TR').format(item.addedDate);

    final subtitle = <String>[
      '${_fmt(item.quantity)} ${_unitLabel()}',
      if (item.price > 0) '${_fmt(item.price)} ${item.currency}',
      if (item.price <= 0) 'Fiyat otomatik',
      if (dateLabel != null) dateLabel,
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
