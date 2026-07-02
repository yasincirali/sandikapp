import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, RefreshIndicator;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import 'performance_screen.dart';
import 'portfolio_performance_screen.dart';
import 'portfolio_detail_screen.dart';

class ChartsScreen extends ConsumerStatefulWidget {
  const ChartsScreen({super.key});

  @override
  ConsumerState<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends ConsumerState<ChartsScreen> {
  String? _view = ''; // null = Birlikte, '' = Ben, uuid = ortak
  AssetType? _filteredType; // pie'dan seçilen kategori filtresi

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);

    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20, color: Colors.white),
                    ),
                  ),
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
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) =>
                              PortfolioPerformanceScreen(initialView: _view)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.show_chart_rounded,
                          color: Sandik.amber, size: 24),
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) =>
                              PortfolioDetailScreen(initialView: _view)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.analytics_outlined,
                          color: Sandik.text36, size: 24),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SandikLogoutButton(
                    onPressed: () => confirmAndLogout(context, ref),
                  ),
                  const SizedBox(width: 8),
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

                          final filteredAssets = _filteredType != null
                              ? assets.where((a) => a.type == _filteredType).toList()
                              : assets;

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
                                  onTap: (a) => Navigator.push(
                                        context,
                                        CupertinoPageRoute(
                                            builder: (_) =>
                                                PerformanceScreen(asset: a)),
                                      )),
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
  final void Function(Asset) onTap;

  const _AssetList(
      {required this.assets, required this.pState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: assets
          .map((a) => _AssetCard(a: a, pState: pState, onTap: onTap))
          .toList(),
    );
  }
}

// ── Asset Card ────────────────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final Asset a;
  final PortfolioState pState;
  final void Function(Asset) onTap;

  const _AssetCard(
      {required this.a, required this.pState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final isPos = a.gainLossPercentage >= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: () => onTap(a),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
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
                    Row(
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
                                  fontSize: 11, fontWeight: FontWeight.w800, color: a.type.color),
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${a.quantity.toStringAsFixed(0)} lot · ${a.type.label}',
                      style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36),
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
                        '%${a.gainLossPercentage.abs().toStringAsFixed(1)}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPos ? Sandik.gain : Sandik.loss,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
