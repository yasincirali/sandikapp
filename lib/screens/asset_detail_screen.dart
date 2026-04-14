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
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
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
    final isPriceKnown = asset.purchasePrice > 0;
    final isPositive = isPriceKnown ? asset.gainLoss >= 0 : false;
    final cs = Theme.of(context).colorScheme;
    final gainColor = isPriceKnown
        ? (isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444))
        : cs.onSurfaceVariant;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final numFmt = NumberFormat('#,##0.####', 'tr_TR');

    final ticker = asset.ticker.isNotEmpty
        ? asset.ticker.replaceAll('.IS', '').replaceAll('=X', '')
        : null;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero AppBar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            actions: [
              IconButton(
                tooltip: 'Düzenle',
                icon: Icon(Icons.edit_rounded, color: cs.primary),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddAssetScreen(editingAsset: asset)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _heroHeader(
                  context, asset, valueTRY, isPriceKnown, isPositive,
                  gainColor, tryFmt, numFmt, ticker, cs),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  // Varlık bilgileri
                  _section(
                    context,
                    label: 'VARLIK BİLGİLERİ',
                    icon: Icons.info_outline_rounded,
                    color: asset.type.color,
                    cs: cs,
                    children: [
                      _infoRow(cs, 'Tür', asset.type.label),
                      if (asset.subCategory != null)
                        _infoRow(cs, 'Alt Kategori', asset.subCategory!),
                      if (ticker != null)
                        _infoRow(cs, 'Sembol', ticker),
                      _infoRow(
                        cs,
                        'Miktar',
                        '${numFmt.format(asset.quantity)} ${_unitLabel(asset.unitType)}',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Fiyat bilgileri
                  _section(
                    context,
                    label: 'FİYAT',
                    icon: Icons.bar_chart_rounded,
                    color: cs.primary,
                    cs: cs,
                    children: [
                      _infoRow(
                        cs,
                        'Alış Fiyatı',
                        isPriceKnown
                            ? '${numFmt.format(asset.purchasePrice)} ${asset.currency}'
                            : 'Bilinmiyor',
                      ),
                      _infoRow(
                        cs,
                        'Güncel Fiyat',
                        '${numFmt.format(asset.currentPrice)} ${asset.currency}',
                        valueColor: asset.currentPrice > 0 ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                      if (isPriceKnown) ...[
                        _infoRow(
                          cs,
                          'Toplam Maliyet',
                          tryFmt.format(s != null
                              ? s.toTRY(asset.totalCost, asset.currency)
                              : asset.totalCost),
                        ),
                        _infoRow(
                          cs,
                          'Kar / Zarar',
                          '${isPositive ? '+' : ''}${numFmt.format(asset.gainLoss)} ${asset.currency}',
                          valueColor: gainColor,
                          bold: true,
                        ),
                      ],
                      if (asset.lastUpdated != null)
                        _infoRow(
                          cs,
                          'Son Güncelleme',
                          DateFormat('dd.MM.yyyy HH:mm').format(asset.lastUpdated!),
                          valueColor: cs.onSurfaceVariant,
                        ),
                    ],
                  ),

                  // Manuel fiyat güncelleme
                  if (asset.isManualPrice || asset.ticker.isEmpty) ...[
                    const SizedBox(height: 12),
                    _manualPriceSection(context, asset, cs),
                  ],

                  // Notlar
                  if (asset.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _section(
                      context,
                      label: 'NOTLAR',
                      icon: Icons.notes_rounded,
                      color: cs.secondary,
                      cs: cs,
                      children: [
                        Text(
                          asset.notes,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Sil butonu
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFEF4444), size: 18),
                      label: const Text('Varlığı Sil',
                          style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(
                            color: Color(0xFFEF4444), width: 1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero header (gradient card) ─────────────────────────────────────────

  Widget _heroHeader(
    BuildContext context,
    Asset asset,
    double valueTRY,
    bool isPriceKnown,
    bool isPositive,
    Color gainColor,
    NumberFormat tryFmt,
    NumberFormat numFmt,
    String? ticker,
    ColorScheme cs,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            asset.type.color,
            asset.type.color.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Dekoratif daireler
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // İkon + tür
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(asset.type.icon,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.type.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          if (ticker != null) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ticker,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Varlık adı
                  Text(
                    asset.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Toplam değer
                  Text(
                    tryFmt.format(valueTRY),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Kar/zarar satırı
                  if (isPriceKnown)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isPositive
                            ? const Color(0xFF10B981).withValues(alpha: 0.25)
                            : const Color(0xFFEF4444).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositive
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 14,
                            color: gainColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${isPositive ? '+' : ''}%${asset.gainLossPercentage.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: gainColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${isPositive ? '+' : ''}${numFmt.format(asset.gainLoss)} ${asset.currency}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: gainColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '${numFmt.format(asset.quantity)} ${_unitLabel(asset.unitType)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section container ───────────────────────────────────────────────────

  Widget _section(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required ColorScheme cs,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // ── Info row ────────────────────────────────────────────────────────────

  Widget _infoRow(
    ColorScheme cs,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Manuel fiyat güncelle ───────────────────────────────────────────────

  Widget _manualPriceSection(
      BuildContext context, Asset asset, ColorScheme cs) {
    return _section(
      context,
      label: 'FİYAT GÜNCELLE',
      icon: Icons.edit_note_rounded,
      color: cs.tertiary,
      cs: cs,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualPriceCtrl,
                decoration: InputDecoration(
                  labelText: 'Güncel fiyat',
                  suffixText: asset.currency,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 10),
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
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _unitLabel(String unitType) {
    switch (unitType) {
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
        return 'Adet';
    }
  }

  void _confirmDelete(BuildContext ctx) => showDialog(
        context: ctx,
        builder: (dlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Varlığı Sil'),
          content: Text(
              '"${widget.asset.name}" kalıcı olarak silinsin mi?'),
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
