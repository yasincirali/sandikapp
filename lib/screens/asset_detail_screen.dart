import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../providers/portfolio_provider.dart';
import '../utils/tr_format.dart';
import 'add_asset_screen.dart';
import 'performance_screen.dart';

class AssetDetailScreen extends ConsumerStatefulWidget {
  final Asset asset;
  const AssetDetailScreen({super.key, required this.asset});

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  late final _manualPriceCtrl = TextEditingController();
  late final _priceFocusNode = FocusNode();

  @override
  void dispose() {
    _manualPriceCtrl.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(portfolioProvider).valueOrNull;
    final asset = widget.asset;
    final valueTRY = s != null
        ? s.toTRY(asset.totalValue, asset.currency)
        : asset.totalValue;
    final costTRY = asset.totalCostTRY;
    final isPriceKnown = asset.purchasePrice > 0 && asset.currentPrice > 0;
    final gainLossTRY = valueTRY - costTRY;
    final isPositive = isPriceKnown ? gainLossTRY >= 0 : false;
    final cs = Theme.of(context).colorScheme;
    const green = Color(0xFF10B981);
    const red = Color(0xFFEF4444);
    final gainColor =
        isPriceKnown ? (isPositive ? green : red) : cs.onSurfaceVariant;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.####', 'tr_TR');

    final ticker = asset.showTicker ? asset.displayTicker : null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              asset.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (ticker != null)
              Text(
                ticker,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            icon: Icon(Icons.edit_outlined, color: cs.primary, size: 22),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AddAssetScreen(editingAsset: asset)),
              );
              if (mounted) {
                ref.read(portfolioProvider.notifier).refreshPrices();
              }
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant, size: 22),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'delete') _confirmDelete(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: red, size: 20),
                    const SizedBox(width: 8),
                    Text('Sil', style: TextStyle(color: red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── Value card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: asset.type.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: asset.type.color.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              children: [
                // Type badge + quantity
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: asset.type.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(asset.type.icon,
                              size: 14, color: asset.type.color),
                          const SizedBox(width: 5),
                          Text(
                            asset.type.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: asset.type.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (asset.subCategory != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color:
                              cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          asset.subCategory!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      asset.unitIsPrefix
                          ? '${asset.unitLabel}${numFmt.format(asset.quantity)}'
                          : '${numFmt.format(asset.quantity)} ${asset.unitLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Total value
                Text(
                  tryFmt.format(valueTRY),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -1,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Toplam Değer',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                // Gain/loss badge
                if (isPriceKnown) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: gainColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 18,
                          color: gainColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${isPositive ? '+' : ''}${tryFmt.format(gainLossTRY)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: gainColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: gainColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            fmtPct(asset.gainLossPercentage, digits: 3, showSign: true),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: gainColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Performance button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PerformanceScreen(asset: asset, showBackButton: true),
                  ),
                );
              },
              icon: const Icon(Icons.trending_up_rounded),
              label: const Text('Performansı Görüntüle'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: cs.primary,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Price details ──────────────────────────────────────────────
          _sectionTitle('Fiyat Bilgileri', cs),
          const SizedBox(height: 10),
          _detailCard(
            cs: cs,
            children: [
              _row(
                cs,
                'Güncel Fiyat',
                '${numFmt.format(asset.currentPrice)} ${asset.currency}',
                valueStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              if (isPriceKnown) ...[
                _divider(cs),
                _row(
                  cs,
                  'Alış Fiyatı',
                  '${numFmt.format(asset.purchasePrice)} ${asset.currency}',
                ),
                _divider(cs),
                _row(cs, 'Toplam Maliyet', tryFmt.format(costTRY)),
              ],
              if (!isPriceKnown) ...[
                _divider(cs),
                _row(cs, 'Alış Fiyatı', 'Belirtilmedi',
                    valueColor: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
              if (asset.lastUpdated != null) ...[
                _divider(cs),
                _row(
                  cs,
                  'Son Güncelleme',
                  DateFormat('dd MMM yyyy, HH:mm', 'tr_TR')
                      .format(asset.lastUpdated!),
                  valueColor: cs.onSurfaceVariant,
                ),
              ],
            ],
          ),

          // ── Manual price update ────────────────────────────────────────
          if (asset.isManualPrice || asset.ticker.isEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle('Fiyat Güncelle', cs),
            const SizedBox(height: 10),
            _detailCard(
              cs: cs,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        focusNode: _priceFocusNode,
                        controller: _manualPriceCtrl,
                        style: const TextStyle(fontSize: 14),
                        cursorColor: cs.primary,
                        enableInteractiveSelection: true,
                        decoration: InputDecoration(
                          hintText: 'Yeni fiyat girin',
                          hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                          suffixText: asset.currency,
                          suffixStyle: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.25),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.25),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 1.5,
                            ),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        final p = double.tryParse(
                            _manualPriceCtrl.text.replaceAll(',', '.'));
                        if (p != null && p > 0) {
                          ref
                              .read(portfolioProvider.notifier)
                              .updateManualPrice(asset, p);
                          _manualPriceCtrl.clear();
                          setState(() {});
                        }
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('Güncelle',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ],

          // ── Notes ──────────────────────────────────────────────────────
          if (asset.notes.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle('Notlar', cs),
            const SizedBox(height: 10),
            _detailCard(
              cs: cs,
              children: [
                Text(
                  asset.notes,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ],

          // ── Meta info ──────────────────────────────────────────────────
          const SizedBox(height: 24),
          _sectionTitle('Detaylar', cs),
          const SizedBox(height: 10),
          _detailCard(
            cs: cs,
            children: [
              _row(cs, 'Eklenme Tarihi',
                  DateFormat('dd MMM yyyy', 'tr_TR').format(asset.addedDate)),
              if (ticker != null) ...[
                _divider(cs),
                _row(cs, 'Sembol', ticker),
              ],
              _divider(cs),
              _row(
                cs,
                'Fiyat Kaynağı',
                asset.isManualPrice || asset.ticker.isEmpty
                    ? 'Manuel'
                    : 'Otomatik',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text, ColorScheme cs) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: cs.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _detailCard({
    required ColorScheme cs,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _row(
    ColorScheme cs,
    String label,
    String value, {
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ??
                  TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? cs.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme cs) {
    return Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.25),
    );
  }

  void _confirmDelete(BuildContext ctx) => showDialog(
        context: ctx,
        builder: (dlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Varlığı Sil'),
          content: Text('"${widget.asset.name}" kalıcı olarak silinsin mi?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('İptal')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444)),
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
