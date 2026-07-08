import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        RefreshIndicator,
        ScaffoldMessenger,
        SnackBar,
        Material,
        MaterialType,
        AlertDialog,
        TextButton,
        FilledButton,
        ListTile,
        Divider,
        showDialog,
        showModalBottomSheet;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/quick_adjust_dialog.dart';
import 'performance_screen.dart';
import 'portfolio_performance_screen.dart';

enum _SortOrder {
  valueDesc,
  valueAsc,
  gainDesc,
  gainAsc,
  gainPctDesc,
  gainPctAsc,
}

class ChartsScreen extends ConsumerStatefulWidget {
  const ChartsScreen({super.key});

  @override
  ConsumerState<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends ConsumerState<ChartsScreen> {
  String? _view = '';
  AssetType? _filteredType;
  _SortOrder _sortOrder = _SortOrder.valueDesc;

  List<Asset> _applySortOrder(List<Asset> list, PortfolioState pState) {
    switch (_sortOrder) {
      case _SortOrder.valueDesc:
        return list..sort((a, b) => pState.toTRY(b.totalValue, b.currency).compareTo(pState.toTRY(a.totalValue, a.currency)));
      case _SortOrder.valueAsc:
        return list..sort((a, b) => pState.toTRY(a.totalValue, a.currency).compareTo(pState.toTRY(b.totalValue, b.currency)));
      case _SortOrder.gainDesc:
        return list..sort((a, b) {
          final ga = (a.purchasePrice > 0 && a.currentPrice > 0) ? pState.toTRY(a.totalValue, a.currency) - a.totalCostTRY : double.negativeInfinity;
          final gb = (b.purchasePrice > 0 && b.currentPrice > 0) ? pState.toTRY(b.totalValue, b.currency) - b.totalCostTRY : double.negativeInfinity;
          return gb.compareTo(ga);
        });
      case _SortOrder.gainAsc:
        return list..sort((a, b) {
          final ga = (a.purchasePrice > 0 && a.currentPrice > 0) ? pState.toTRY(a.totalValue, a.currency) - a.totalCostTRY : double.infinity;
          final gb = (b.purchasePrice > 0 && b.currentPrice > 0) ? pState.toTRY(b.totalValue, b.currency) - b.totalCostTRY : double.infinity;
          return ga.compareTo(gb);
        });
      case _SortOrder.gainPctDesc:
        return list..sort((a, b) {
          final pa = (a.purchasePrice > 0 && a.currentPrice > 0) ? a.gainLossPercentage : double.negativeInfinity;
          final pb = (b.purchasePrice > 0 && b.currentPrice > 0) ? b.gainLossPercentage : double.negativeInfinity;
          return pb.compareTo(pa);
        });
      case _SortOrder.gainPctAsc:
        return list..sort((a, b) {
          final pa = (a.purchasePrice > 0 && a.currentPrice > 0) ? a.gainLossPercentage : double.infinity;
          final pb = (b.purchasePrice > 0 && b.currentPrice > 0) ? b.gainLossPercentage : double.infinity;
          return pa.compareTo(pb);
        });
    }
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref, Asset asset) {
    showDialog<void>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: const Text('Varlığı Sil'),
        content: Text('"${asset.name}" kalıcı olarak silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              Navigator.pop(dlg);
              try {
                await ref
                    .read(portfolioProvider.notifier)
                    .deleteAsset(asset.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Varlık silindi')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Silinemedi: $e')),
                );
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;

    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Portföy',
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  _SortButton(
                    current: _sortOrder,
                    onChanged: (o) => setState(() => _sortOrder = o),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) =>
                              PortfolioPerformanceScreen(initialView: _view)),
                    ),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Center(
                        child: Icon(Icons.show_chart_rounded, color: Sandik.amber, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SandikLogoutButton(
                    onPressed: () => confirmAndLogout(context, ref),
                  ),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: pStateAsync.when(
                loading: () => const SandikLoadingScreen(),
                error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
                data: (pState) => RefreshIndicator(
                  color: Sandik.amber,
                  onRefresh: () =>
                      ref.read(portfolioProvider.notifier).refreshPrices(),
                  child: ListView(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                    children: [
                      if (activePartners.isNotEmpty)
                        ModernTabSelector(
                          partners: activePartners,
                          selectedId: _view,
                          onChanged: (v) => setState(() { _view = v; _filteredType = null; }),
                        ),
                      const SizedBox(height: 24),

                      // Verileri birleştir
                      partnerAssetsAsync.when(
                        loading: () => const SandikLoadingScreen(),
                        error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
                        data: (partnerMap) {
                          List<Asset> assets = [];
                          if (_view == '') {
                            assets = pState.assets;
                          } else if (_view != null) {
                            assets = partnerMap[_view] ?? [];
                          } else {
                            // Birlikte
                            assets = [...pState.assets];
                            for (final list in partnerMap.values) {
                              assets.addAll(list);
                            }
                          }

                          if (assets.isEmpty) {
                            return const _EmptyState();
                          }

                          final filteredAssets = _applySortOrder(
                            _filteredType != null
                                ? assets.where((a) => a.type == _filteredType).toList()
                                : List<Asset>.from(assets),
                            pState,
                          );

                          return Column(
                            children: [
                              _AssetTypeDonut(
                                assets: assets,
                                pState: pState,
                                onTypeSelected: (type) => setState(() => _filteredType = type),
                              ),
                              const SizedBox(height: 32),
                              _AssetList(
                                assets: filteredAssets,
                                pState: pState,
                                currentUserId: currentUserId,
                                onTap: (a) => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                      builder: (_) =>
                                          PerformanceScreen(asset: a, showBackButton: true)),
                                ),
                                onDelete: (a) =>
                                    _confirmDelete(context, ref, a),
                                onAdd: (a) => showQuickAdjustDialog(
                                    context, ref,
                                    asset: a,
                                    mode: QuickAdjustMode.add),
                                onRemove: (a) => showQuickAdjustDialog(
                                    context, ref,
                                    asset: a,
                                    mode: QuickAdjustMode.remove),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_rounded, size: 64, color: Sandik.text36),
          const SizedBox(height: 16),
          Text('Henüz varlık eklenmemiş',
              style: GoogleFonts.dmSans(color: Sandik.text36)),
        ],
      ),
    );
  }
}

// ── Donut Chart ───────────────────────────────────────────────────────────────

class _AssetTypeDonut extends StatefulWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  final void Function(AssetType?) onTypeSelected;
  const _AssetTypeDonut({required this.assets, required this.pState, required this.onTypeSelected});

  @override
  State<_AssetTypeDonut> createState() => _AssetTypeDonutState();
}

class _AssetTypeDonutState extends State<_AssetTypeDonut> {
  int? _touchedIndex;

  static String _formatTL(double val) {
    if (val >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(2).replaceAll('.', ',')} mn ₺';
    }
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(val);
  }

  @override
  Widget build(BuildContext context) {
    final totals = <AssetType, double>{};
    double totalVal = 0;
    for (final a in widget.assets) {
      final val = widget.pState.toTRY(a.totalValue, a.currency);
      totals[a.type] = (totals[a.type] ?? 0) + val;
      totalVal += val;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final touched = _touchedIndex != null && _touchedIndex! < sorted.length
        ? sorted[_touchedIndex!]
        : null;

    // Ortada gösterilecek metin
    final centerLabel = touched != null ? touched.key.label : 'toplam';
    final centerValue = touched != null
        ? _formatTL(touched.value)
        : _formatTL(totalVal);
    final centerPct = touched != null
        ? '%${(touched.value / (totalVal > 0 ? totalVal : 1) * 100).toStringAsFixed(1)}'
        : null;
    final centerColor = touched != null ? touched.key.color : Sandik.gold;

    return Column(
      children: [
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent) {
                        final idx = response?.touchedSection?.touchedSectionIndex;
                        final newIdx = (idx != null && idx >= 0 && idx < sorted.length)
                            ? (_touchedIndex == idx ? null : idx)
                            : null;
                        setState(() => _touchedIndex = newIdx);
                        widget.onTypeSelected(newIdx != null ? sorted[newIdx].key : null);
                      }
                    },
                  ),
                  sections: sorted.asMap().entries.map((e) {
                    final isTouched = e.key == _touchedIndex;
                    return PieChartSectionData(
                      color: e.value.key.color,
                      value: e.value.value,
                      radius: isTouched ? 42 : 34,
                      showTitle: false,
                    );
                  }).toList(),
                  sectionsSpace: 3,
                  centerSpaceRadius: 88,
                  startDegreeOffset: -90,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centerPct != null) ...[
                        Text(
                          centerPct,
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: centerColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerValue,
                          style: GoogleFonts.dmSans(
                            fontSize: centerPct != null ? 16 : 22,
                            fontWeight: FontWeight.w700,
                            color: centerColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: Sandik.text36,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        // Kategori legend
        Wrap(
          spacing: 20,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: sorted.asMap().entries.map((e) {
            final isTouched = e.key == _touchedIndex;
            final pct = (e.value.value / (totalVal > 0 ? totalVal : 1) * 100)
                .toStringAsFixed(1);
            return GestureDetector(
              onTap: () {
                final newIdx = _touchedIndex == e.key ? null : e.key;
                setState(() => _touchedIndex = newIdx);
                widget.onTypeSelected(newIdx != null ? sorted[newIdx].key : null);
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _touchedIndex == null || isTouched ? 1.0 : 0.45,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isTouched ? 10 : 8,
                      height: isTouched ? 10 : 8,
                      decoration: BoxDecoration(
                        color: e.value.key.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${e.value.key.label} %$pct',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: isTouched ? FontWeight.w700 : FontWeight.w500,
                        color: isTouched ? e.value.key.color : Sandik.text58,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Asset List ────────────────────────────────────────────────────────────────

class _AssetList extends StatelessWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  final String? currentUserId;
  final void Function(Asset) onTap;
  final void Function(Asset) onDelete;
  final void Function(Asset) onAdd;
  final void Function(Asset) onRemove;

  const _AssetList({
    required this.assets,
    required this.pState,
    required this.currentUserId,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SlidableAutoCloseBehavior(
      child: Column(
        children: assets
            .map((a) => _AssetCard(
                  a: a,
                  pState: pState,
                  canEdit:
                      currentUserId != null && a.userId == currentUserId,
                  onTap: onTap,
                  onDelete: onDelete,
                  onAdd: onAdd,
                  onRemove: onRemove,
                ))
            .toList(),
      ),
    );
  }
}

// ── Asset Card ────────────────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final Asset a;
  final PortfolioState pState;
  final bool canEdit;
  final void Function(Asset) onTap;
  final void Function(Asset) onDelete;
  final void Function(Asset) onAdd;
  final void Function(Asset) onRemove;

  const _AssetCard({
    required this.a,
    required this.pState,
    required this.canEdit,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final isPos = a.gainLossPercentage >= 0;

    Widget card = CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: () => onTap(a),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(canEdit ? 0 : 16),
        ),
          child: Row(
            children: [
              a.currencySymbol != null
                  ? Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: a.type.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          a.currencySymbol!,
                          style: GoogleFonts.dmSans(
                            fontSize: a.currencySymbol!.length > 1 ? 9 : 13,
                            fontWeight: FontWeight.w800,
                            color: a.type.color,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : Icon(a.type.icon, color: a.type.color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (a.showTicker) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: a.type.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          a.displayTicker!,
                          style: GoogleFonts.dmSans(
                              fontSize: 10, fontWeight: FontWeight.w800, color: a.type.color),
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.25),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      a.unitIsPrefix
                          ? '${a.unitLabel}${a.quantity.toStringAsFixed(a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} · ${a.type.label}'
                          : '${a.quantity.toStringAsFixed(a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} ${a.unitLabel} · ${a.type.label}',
                      style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text36),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tryFmt.format(pState.toTRY(a.totalValue, a.currency)),
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  if (a.purchasePrice > 0 && a.currentPrice > 0 && a.gainLoss != 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isPos
                              ? Icons.arrow_drop_up_rounded
                              : Icons.arrow_drop_down_rounded,
                          color: isPos ? Sandik.gain : Sandik.loss,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${tryFmt.format((pState.toTRY(a.totalValue, a.currency) - a.totalCostTRY).abs())} · %${a.gainLossPercentage.abs().toStringAsFixed(3)}',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isPos ? Sandik.gain : Sandik.loss,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );

    if (canEdit) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Slidable(
          key: ValueKey('asset-${a.id}'),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.5,
            children: [
              SlidableAction(
                onPressed: (_) => onAdd(a),
                backgroundColor: Sandik.gain,
                foregroundColor: Colors.white,
                icon: Icons.add_rounded,
                label: 'Ekle',
              ),
              SlidableAction(
                onPressed: (_) => onRemove(a),
                backgroundColor: Sandik.loss.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
                icon: Icons.remove_rounded,
                label: 'Çıkar',
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => onDelete(a),
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                icon: Icons.delete_outline_rounded,
                label: 'Sil',
              ),
            ],
          ),
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
  }
}

// ── Sort Button ───────────────────────────────────────────────────────────────

class _SortButton extends StatelessWidget {
  final _SortOrder current;
  final void Function(_SortOrder) onChanged;

  const _SortButton({required this.current, required this.onChanged});

  static const _options = <(_SortOrder, String, String)>[
    (_SortOrder.valueDesc,   'Piyasa Değeri',     'Büyükten Küçüğe'),
    (_SortOrder.valueAsc,    'Piyasa Değeri',     'Küçükten Büyüğe'),
    (_SortOrder.gainDesc,    'Kazanç (TL)',        'En Yüksek Önce'),
    (_SortOrder.gainAsc,     'Kazanç (TL)',        'En Düşük Önce'),
    (_SortOrder.gainPctDesc, 'Kazanç (%)',         'En Yüksek Önce'),
    (_SortOrder.gainPctAsc,  'Kazanç (%)',         'En Düşük Önce'),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Sandik.surface1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _SortSheet(current: current, onChanged: (o) {
          onChanged(o);
          Navigator.pop(context);
        }),
      ),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: current != _SortOrder.valueDesc
              ? Sandik.amber.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: current != _SortOrder.valueDesc
                ? Sandik.amber.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Icon(
          Icons.sort_rounded,
          size: 20,
          color: current != _SortOrder.valueDesc ? Sandik.amber : Sandik.text58,
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final _SortOrder current;
  final void Function(_SortOrder) onChanged;

  const _SortSheet({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'SIRALAMA KRİTERİ',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Sandik.text36,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          ..._SortButton._options.map((opt) {
            final (order, group, label) = opt;
            final selected = current == order;
            return ListTile(
              dense: true,
              leading: Icon(
                _iconFor(order),
                size: 18,
                color: selected ? Sandik.amber : Sandik.text58,
              ),
              title: Text(
                group,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Sandik.amber : Colors.white,
                ),
              ),
              subtitle: Text(
                label,
                style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text36),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: Sandik.amber, size: 18)
                  : null,
              tileColor: selected ? Sandik.amber.withValues(alpha: 0.07) : null,
              onTap: () => onChanged(order),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _iconFor(_SortOrder o) => switch (o) {
    _SortOrder.valueDesc  => Icons.arrow_downward_rounded,
    _SortOrder.valueAsc   => Icons.arrow_upward_rounded,
    _SortOrder.gainDesc   => Icons.trending_up_rounded,
    _SortOrder.gainAsc    => Icons.trending_down_rounded,
    _SortOrder.gainPctDesc => Icons.percent_rounded,
    _SortOrder.gainPctAsc  => Icons.percent_rounded,
  };
}
