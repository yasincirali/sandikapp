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
import '../models/position.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/deposit_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
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

  List<Position> _applyPositionSortOrder(
      List<Position> list, PortfolioState pState) {
    switch (_sortOrder) {
      case _SortOrder.valueDesc:
        return list
          ..sort((a, b) => pState
              .toTRY(b.totalValue, b.representative.currency)
              .compareTo(pState.toTRY(a.totalValue, a.representative.currency)));
      case _SortOrder.valueAsc:
        return list
          ..sort((a, b) => pState
              .toTRY(a.totalValue, a.representative.currency)
              .compareTo(pState.toTRY(b.totalValue, b.representative.currency)));
      case _SortOrder.gainDesc:
        return list..sort((a, b) {
          final ga = a.weightedPurchasePrice > 0
              ? pState.toTRY(a.totalValue, a.representative.currency) -
                  a.totalCostTRY
              : double.negativeInfinity;
          final gb = b.weightedPurchasePrice > 0
              ? pState.toTRY(b.totalValue, b.representative.currency) -
                  b.totalCostTRY
              : double.negativeInfinity;
          return gb.compareTo(ga);
        });
      case _SortOrder.gainAsc:
        return list..sort((a, b) {
          final ga = a.weightedPurchasePrice > 0
              ? pState.toTRY(a.totalValue, a.representative.currency) -
                  a.totalCostTRY
              : double.infinity;
          final gb = b.weightedPurchasePrice > 0
              ? pState.toTRY(b.totalValue, b.representative.currency) -
                  b.totalCostTRY
              : double.infinity;
          return ga.compareTo(gb);
        });
      case _SortOrder.gainPctDesc:
        return list..sort((a, b) {
          final pa = a.weightedPurchasePrice > 0
              ? a.gainLossPercentage
              : double.negativeInfinity;
          final pb = b.weightedPurchasePrice > 0
              ? b.gainLossPercentage
              : double.negativeInfinity;
          return pb.compareTo(pa);
        });
      case _SortOrder.gainPctAsc:
        return list..sort((a, b) {
          final pa =
              a.weightedPurchasePrice > 0 ? a.gainLossPercentage : double.infinity;
          final pb =
              b.weightedPurchasePrice > 0 ? b.gainLossPercentage : double.infinity;
          return pa.compareTo(pb);
        });
    }
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref, Asset asset) {
    showDialog<void>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: const Text('Varlığı Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${asset.name}" kalıcı olarak silinsin mi?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color:
                        const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: const Text(
                'Bu bir satış değil — kayıt tamamen silinir ve geçmiş '
                'grafiğinden de düşer. Sattıysan bunun yerine "Çıkar" '
                'kullan; realize kâr/zararın ve alım geçmişin korunur.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
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
            child: const Text('Yine de sil'),
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
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Center(
                        child: Icon(Icons.show_chart_rounded,
                            color: Sandik.amber, size: 22),
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

                          final positions = aggregatePositions(assets);

                          if (positions.isEmpty) {
                            return const _EmptyState();
                          }

                          final filteredPositions = _applyPositionSortOrder(
                            _filteredType != null
                                ? positions
                                    .where((p) =>
                                        p.representative.type == _filteredType)
                                    .toList()
                                : List<Position>.from(positions),
                            pState,
                          );
                          final displayAssets = positions
                              .map((position) => position.asDisplayAsset())
                              .toList();

                          return Column(
                            children: [
                              _AssetTypeDonut(
                                assets: displayAssets,
                                pState: pState,
                                onTypeSelected: (type) => setState(() => _filteredType = type),
                              ),
                              const SizedBox(height: 32),
                              _AssetList(
                                positions: filteredPositions,
                                pState: pState,
                                currentUserId: currentUserId,
                                onTap: (p) => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                      builder: (_) => PerformanceScreen(
                                            asset: p.asDisplayAsset(),
                                            showBackButton: true,
                                            lots: p.lots,
                                          )),
                                ),
                                onDelete: (p) =>
                                    _confirmDelete(context, ref, p.representative),
                                onAdd: (p) => showQuickAdjustDialog(
                                    context, ref,
                                    asset: p.asDisplayAsset(),
                                    mode: QuickAdjustMode.add),
                                onRemove: (p) => showQuickAdjustDialog(
                                    context, ref,
                                    asset: p.asDisplayAsset(),
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
    // Ana ekran hero'suyla birebir aynı format: ₺1.234.567
    return NumberFormat.currency(
            locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
        .format(val);
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
        ? fmtPct(touched.value / (totalVal > 0 ? totalVal : 1) * 100, digits: 1)
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
            final pct =
                fmtPct(e.value.value / (totalVal > 0 ? totalVal : 1) * 100, digits: 1);
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
                      '${e.value.key.label} $pct',
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
  final List<Position> positions;
  final PortfolioState pState;
  final String? currentUserId;
  final void Function(Position) onTap;
  final void Function(Position) onDelete;
  final void Function(Position) onAdd;
  final void Function(Position) onRemove;

  const _AssetList({
    required this.positions,
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
        children: positions
            .map((position) => _AssetCard(
                  position: position,
                  pState: pState,
                  canEdit:
                      currentUserId != null &&
                          position.representative.userId == currentUserId,
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

class _AssetCard extends StatefulWidget {
  final Position position;
  final PortfolioState pState;
  final bool canEdit;
  final void Function(Position) onTap;
  final void Function(Position) onDelete;
  final void Function(Position) onAdd;
  final void Function(Position) onRemove;

  const _AssetCard({
    required this.position,
    required this.pState,
    required this.canEdit,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<_AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<_AssetCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final pState = widget.pState;
    final canEdit = widget.canEdit;
    final onTap = widget.onTap;
    final onAdd = widget.onAdd;
    final onRemove = widget.onRemove;
    final onDelete = widget.onDelete;

    final a = position.asDisplayAsset();
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final gainLossTRY =
        pState.toTRY(position.totalValue, a.currency) - position.totalCostTRY;
    final isPos = gainLossTRY >= 0;

    Widget card = Container(
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(canEdit ? 0 : 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoButton(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            onPressed: () => onTap(position),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          ? '${a.unitLabel}${fmtNum(a.quantity, digits: a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} · ${a.type.label}'
                          : '${fmtNum(a.quantity, digits: a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} ${a.unitLabel} · ${a.type.label}',
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
                  if (a.purchasePrice > 0 && a.currentPrice > 0) ...[
                    const SizedBox(height: 4),
                    Builder(builder: (_) {
                      final pctTRY = position.totalCostTRY > 0
                          ? (gainLossTRY / position.totalCostTRY) * 100
                          : 0.0;
                      final isFlat =
                          gainLossTRY.abs().round() == 0 && pctTRY.abs() < 0.005;
                      if (isFlat) {
                        return Row(
                          children: [
                            const Icon(Icons.horizontal_rule_rounded,
                                color: Sandik.text58, size: 14),
                            const SizedBox(width: 2),
                            Text('Değişim yok',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Sandik.text58)),
                          ],
                        );
                      }
                      return Row(
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
                            '${tryFmt.format(gainLossTRY.abs())} · ${fmtPct(pctTRY.abs(), digits: 2)}',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isPos ? Sandik.gain : Sandik.loss,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              _ExpandChevron(
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _AssetDetailsPanel(position: position, pState: pState)
                : const SizedBox(width: double.infinity),
          ),
        ],
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
                onPressed: (_) => onAdd(position),
                backgroundColor: Sandik.gain,
                foregroundColor: Colors.white,
                icon: Icons.add_rounded,
                label: 'Ekle',
              ),
              SlidableAction(
                onPressed: (_) => onRemove(position),
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
                onPressed: (_) => onDelete(position),
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

// ── Expand Chevron ────────────────────────────────────────────────────────────

class _ExpandChevron extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ExpandChevron({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: AnimatedRotation(
          turns: expanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Sandik.text58,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ── Asset Details Panel (expandable) ──────────────────────────────────────────

class _AssetDetailsPanel extends StatelessWidget {
  final Position position;
  final PortfolioState pState;

  const _AssetDetailsPanel({required this.position, required this.pState});

  @override
  Widget build(BuildContext context) {
    final rep = position.representative;
    final tryFmt3 =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 3);
    final numFmt = NumberFormat('#,##0.####', 'tr_TR');
    final costFmt3 = NumberFormat('#,##0.000', 'tr_TR');

    // Vadeli mevduat için özel panel — normal Position gösteriminden farklı.
    if (rep.type == AssetType.mevduat) {
      return _DepositDetailsPanel(asset: rep);
    }

    // İlk alış tarihi = en eski buy lot
    final buyLots = position.lots.where((l) => l.isBuy).toList()
      ..sort((a, b) => a.addedDate.compareTo(b.addedDate));
    final firstBuyDate = buyLots.isNotEmpty ? buyLots.first.addedDate : null;

    final avgCostStr = position.weightedPurchasePrice > 0
        ? '${numFmt.format(position.weightedPurchasePrice)} ${rep.currency}'
        : '—';

    final qty = position.totalQuantity;
    final qtyStr = qty == qty.truncateToDouble()
        ? NumberFormat('#,###', 'tr_TR').format(qty.toInt())
        : numFmt.format(qty);
    final qtyDisplay =
        rep.unitIsPrefix ? '${rep.unitLabel}$qtyStr' : '$qtyStr ${rep.unitLabel}';

    final currentValueTRY = pState.toTRY(position.totalValue, rep.currency);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'İlk Alış',
                  value: firstBuyDate != null
                      ? DateFormat('d MMM yyyy', 'tr_TR').format(firstBuyDate)
                      : '—',
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Miktar',
                  value: qtyDisplay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Ort. Maliyet',
                  value: avgCostStr,
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Toplam Maliyet',
                  value: position.weightedPurchasePrice > 0
                      ? '${costFmt3.format(position.totalCost)} ${rep.currency}'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Güncel Tutar',
                  value: tryFmt3.format(currentValueTRY),
                  emphasize: true,
                ),
              ),
            ],
          ),
          if (position.lots.length > 1) ...[
            const SizedBox(height: 10),
            Text(
              '${buyLots.length} alım · ${position.lots.where((l) => l.isSell).length} çıkarma',
              style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: Sandik.text36,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Deposit Details Panel ─────────────────────────────────────────────────────
// Vadeli mevduat için özel expand panel — vade sayacı, faiz, brüt/net getiri.

class _DepositDetailsPanel extends StatelessWidget {
  final Asset asset;
  const _DepositDetailsPanel({required this.asset});

  @override
  Widget build(BuildContext context) {
    final terms = DepositService.decode(asset);
    if (terms == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Mevduat bilgileri okunamadı.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final money = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
    final dateFmt = DateFormat('d MMM yyyy', 'tr_TR');

    final principal = asset.quantity;
    final currentUnit = DepositService.currentUnitValue(terms);
    final currentValue = principal * currentUnit;
    final maturityValue = principal * DepositService.maturityUnitValue(terms);

    final currentGain = currentValue - principal;
    final maturityGain = maturityValue - principal;

    final currentPct = principal > 0 ? (currentGain / principal) * 100 : 0.0;
    final maturityPct = principal > 0 ? (maturityGain / principal) * 100 : 0.0;

    final daysLeft = DepositService.daysToMaturity(terms);
    final matured = DepositService.isMatured(terms);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white.withValues(alpha: 0.06),
          ),

          // Vade durumu banner'ı
          _MaturityStatus(matured: matured, daysLeft: daysLeft),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Anapara',
                  value: money.format(principal),
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Yıllık Faiz',
                  value:
                      '${fmtPct(terms.annualRatePct, digits: 2)} ${terms.interestType == DepositInterestType.compound ? '· bileşik' : '· basit'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Başlangıç',
                  value: dateFmt.format(terms.start),
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Vade Sonu',
                  value: dateFmt.format(terms.end),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Şu anki net değer
          _MevduatGetiriRow(
            label: 'Şu Anki Net Değer',
            value: currentValue,
            gain: currentGain,
            pct: currentPct,
            money: money,
            emphasize: true,
          ),
          const SizedBox(height: 8),
          _MevduatGetiriRow(
            label: 'Vade Sonu Net (Öngörü)',
            value: maturityValue,
            gain: maturityGain,
            pct: maturityPct,
            money: money,
          ),

          const SizedBox(height: 10),
          Text(
            terms.taxWasProvided
                ? 'Stopaj: ${fmtPct(terms.taxRatePct, digits: 2)} (kullanıcı)'
                : 'Stopaj: ${fmtPct(terms.taxRatePct, digits: 0)} (varsayılan — banka dekontunuzu kontrol edin)',
            style: GoogleFonts.dmSans(
              fontSize: 10,
              color: Sandik.text36,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaturityStatus extends StatelessWidget {
  final bool matured;
  final int daysLeft;
  const _MaturityStatus({required this.matured, required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    final IconData icon;
    if (matured) {
      color = Sandik.gain;
      icon = Icons.check_circle_rounded;
      text = 'Vade doldu';
    } else if (daysLeft <= 7) {
      color = Sandik.amber;
      icon = Icons.access_time_rounded;
      text = '$daysLeft gün kaldı';
    } else {
      color = AssetType.mevduat.color;
      icon = Icons.savings_rounded;
      text = '$daysLeft gün kaldı';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MevduatGetiriRow extends StatelessWidget {
  final String label;
  final double value;
  final double gain;
  final double pct;
  final NumberFormat money;
  final bool emphasize;

  const _MevduatGetiriRow({
    required this.label,
    required this.value,
    required this.gain,
    required this.pct,
    required this.money,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final positive = gain >= 0;
    final color = positive ? Sandik.gain : Sandik.loss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasize
            ? color.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasize
              ? color.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: Sandik.text58,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  money.format(value),
                  style: GoogleFonts.dmSans(
                    fontSize: emphasize ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${money.format(gain)}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                fmtPct(pct, digits: 2, showSign: true),
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _DetailItem({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Sandik.text36,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: emphasize ? Sandik.gold : Colors.white,
          ),
        ),
      ],
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
