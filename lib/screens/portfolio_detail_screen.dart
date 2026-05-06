import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';

class PortfolioDetailScreen extends ConsumerStatefulWidget {
  final String? initialView;
  const PortfolioDetailScreen({super.key, this.initialView});

  @override
  ConsumerState<PortfolioDetailScreen> createState() =>
      _PortfolioDetailScreenState();
}

class _PortfolioDetailScreenState extends ConsumerState<PortfolioDetailScreen> {
  late String? _view;
  int _selectedPeriodIdx = 4; // 1Y

  static const List<({String label, int days})> _periods = [
    (label: '1H', days: 7),
    (label: '1A', days: 30),
    (label: '3A', days: 90),
    (label: '6A', days: 180),
    (label: '1Y', days: 365),
  ];

  @override
  void initState() {
    super.initState();
    _view = widget.initialView ?? '';
  }

  // ── Logic (Same as PortfolioPerformanceScreen but refined) ─────────────────

  double _getSimulatedPrice(Asset asset, DateTime date) {
    final endPrice = asset.currentPrice > 0 ? asset.currentPrice : 100.0;
    final now = DateTime.now();
    final differenceDays = now.difference(date).inDays.clamp(0, 3650);
    double yearlyReturn = 0.40;
    if (asset.type == AssetType.hisse) yearlyReturn = 0.70;
    if (asset.type == AssetType.emtia) yearlyReturn = 0.45;
    if (asset.type == AssetType.doviz) yearlyReturn = 0.20;
    if (asset.type == AssetType.fon) yearlyReturn = 0.50;
    double simulated =
        endPrice / (1.0 + (yearlyReturn * (differenceDays / 365.0)));
    final noise =
        math.sin(date.millisecondsSinceEpoch / 86400000.0) * (simulated * 0.03);
    return simulated + noise;
  }

  List<TransactionSegment> _generatePortfolioSegments(
      List<Asset> allAssets, DateTime startDate, DateTime endDate) {
    final segments = <TransactionSegment>[];
    if (allAssets.isEmpty) return [];
    final events = <DateTime>{startDate, endDate};
    for (final a in allAssets) {
      if (a.addedDate.isAfter(startDate) && a.addedDate.isBefore(endDate))
        events.add(a.addedDate);
    }
    final sortedEvents = events.toList()..sort();
    final firstAssetDate = allAssets
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    for (int i = 0; i < sortedEvents.length - 1; i++) {
      final segStart = sortedEvents[i];
      final segEnd = sortedEvents[i + 1];
      final isPassive = segStart.isBefore(firstAssetDate);
      final lineColor =
          isPassive ? Colors.white.withValues(alpha: 0.15) : Sandik.amber;
      final areaStart = isPassive
          ? Colors.white.withValues(alpha: 0.05)
          : Sandik.amber.withValues(alpha: 0.12);
      final spots = <FlSpot>[];
      DateTime current = segStart;
      while (current.isBefore(segEnd) || current.isAtSameMomentAs(segEnd)) {
        final double x = current.difference(startDate).inDays.toDouble();
        double totalVal = 0;
        for (final a in allAssets) {
          if (current.isBefore(a.addedDate) && !isPassive) continue;
          totalVal += _getSimulatedPrice(a, current) * a.quantity;
        }
        if (totalVal == 0 && !isPassive) totalVal = 1.0;
        spots.add(FlSpot(x, totalVal));
        if (current.isAtSameMomentAs(segEnd)) break;
        current = current.add(const Duration(days: 1));
      }
      if (spots.isNotEmpty) {
        segments.add(TransactionSegment(
            spots: spots,
            lineColor: lineColor,
            areaGradientStart: areaStart,
            areaGradientEnd: Colors.transparent,
            thickness: isPassive ? 1.5 : 3.5));
      }
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);
    final endDate = DateTime.now();
    final startDate =
        endDate.subtract(Duration(days: _periods[_selectedPeriodIdx].days));

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Detaylı Portföy Analizi',
            style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
      body: pStateAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Sandik.amber)),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (pState) => partnerAssetsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: Sandik.amber)),
          error: (e, _) => Center(child: Text('Hata: $e')),
          data: (partnerMap) {
            List<Asset> targetAssets = [];
            if (_view == '')
              targetAssets = pState.assets;
            else if (_view != null)
              targetAssets = partnerMap[_view] ?? [];
            else {
              targetAssets = [...pState.assets];
              for (final list in partnerMap.values) targetAssets.addAll(list);
            }

            final segments =
                _generatePortfolioSegments(targetAssets, startDate, endDate);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                if (activePartners.isNotEmpty) ...[
                  ModernTabSelector(
                    partners: activePartners,
                    selectedId: _view,
                    onChanged: (v) => setState(() => _view = v),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildPeriodToggle(),
                const SizedBox(height: 24),
                _buildChartSection(segments, startDate, endDate, targetAssets),
                const SizedBox(height: 32),
                _SectionTitle('KATEGORİ DAĞILIMI'),
                const SizedBox(height: 16),
                _buildCategoryBreakdown(targetAssets, pState),
                const SizedBox(height: 32),
                if (_view == null && activePartners.isNotEmpty) ...[
                  _SectionTitle('ORTAKLAR'),
                  const SizedBox(height: 16),
                  _buildPartnerBreakdown(pState, partnerMap, activePartners),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: Sandik.surface1, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriodIdx = i),
              child: Container(
                decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1A3D2E)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: Center(
                    child: Text(_periods[i].label,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Sandik.amber : Sandik.text36))),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChartSection(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets) {
    if (segments.isEmpty)
      return const SizedBox(
          height: 200, child: Center(child: Text('Veri yok')));
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final seg in segments) {
      for (final spot in seg.spots) {
        if (spot.y > maxY) maxY = spot.y;
        if (spot.y < minY) minY = spot.y;
      }
    }
    if (minY == double.infinity) minY = 0;
    if (maxY == -double.infinity) maxY = 1000;
    double yPadding = (maxY - minY) * 0.2;
    maxY += yPadding;
    minY = (minY - yPadding).clamp(0, double.infinity);
    final maxX = end.difference(start).inDays.toDouble();

    return Container(
      height: 300,
      padding: const EdgeInsets.fromLTRB(0, 24, 16, 12),
      decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    interval: maxX / 4,
                    getTitlesWidget: (val, meta) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            DateFormat('d MMM')
                                .format(start.add(Duration(days: val.toInt()))),
                            style: const TextStyle(
                                color: Sandik.text36, fontSize: 10))))),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    getTitlesWidget: (val, meta) => (val == maxY || val == minY)
                        ? const SizedBox.shrink()
                        : Text(
                            NumberFormat.compactCurrency(
                                    symbol: '₺', locale: 'tr_TR')
                                .format(val),
                            style: const TextStyle(
                                color: Sandik.text36, fontSize: 10)))),
          ),
          lineBarsData: segments.map((seg) {
            final isActive = seg.thickness > 2.0;
            return LineChartBarData(
              spots: seg.spots,
              isCurved: true,
              color: seg.lineColor,
              barWidth: seg.thickness,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) {
                  if (!isActive) return false;
                  final dateAtSpot = start.add(Duration(days: spot.x.toInt()));
                  final hasAddition = assets.any((a) =>
                      a.addedDate.year == dateAtSpot.year &&
                      a.addedDate.month == dateAtSpot.month &&
                      a.addedDate.day == dateAtSpot.day);
                  return hasAddition ||
                      spot.x == seg.spots.first.x ||
                      spot.x == seg.spots.last.x;
                },
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: Sandik.amber,
                  strokeColor: Sandik.background,
                  strokeWidth: 2,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [seg.areaGradientStart, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            );
          }).toList(),
          lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Sandik.surface2,
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                          NumberFormat.currency(
                                  symbol: '₺',
                                  locale: 'tr_TR',
                                  decimalDigits: 0)
                              .format(s.y),
                          const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)))
                      .toList())),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<Asset> assets, PortfolioState pState) {
    final totals = <AssetType, double>{};
    double totalVal = 0;
    for (final a in assets) {
      final val = pState.toTRY(a.totalValue, a.currency);
      totals[a.type] = (totals[a.type] ?? 0) + val;
      totalVal += val;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sorted.map((e) {
        final pct =
            (e.value / (totalVal > 0 ? totalVal : 1) * 100).toStringAsFixed(1);
        return _breakdownTile(e.key.label, e.value, pct, e.key.color);
      }).toList(),
    );
  }

  Widget _buildPartnerBreakdown(PortfolioState myState,
      Map<String, List<Asset>> partnerMap, List<AppUser> partners) {
    final fmt =
        NumberFormat.currency(symbol: '₺', locale: 'tr_TR', decimalDigits: 0);
    double totalAll = myState.totalValue;
    for (final list in partnerMap.values)
      totalAll +=
          list.fold(0, (s, a) => s + myState.toTRY(a.totalValue, a.currency));

    return Column(
      children: [
        _breakdownTile(
            'Ben',
            myState.totalValue,
            (myState.totalValue / (totalAll > 0 ? totalAll : 1) * 100)
                .toStringAsFixed(1),
            Sandik.amber),
        ...partners.map((p) {
          final pAssets = partnerMap[p.id] ?? [];
          final pTotal = pAssets.fold<double>(
              0, (s, a) => s + myState.toTRY(a.totalValue, a.currency));
          return _breakdownTile(
              p.displayName,
              pTotal,
              (pTotal / (totalAll > 0 ? totalAll : 1) * 100).toStringAsFixed(1),
              Sandik.gain);
        }),
      ],
    );
  }

  Widget _breakdownTile(String label, double val, String pct, Color color) {
    final fmt =
        NumberFormat.currency(symbol: '₺', locale: 'tr_TR', decimalDigits: 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Sandik.surface1, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 16),
          Expanded(
              child: Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(val),
                  style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              Text('%$pct',
                  style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36)),
            ],
          ),
        ],
      ),
    );
  }
}

class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;
  TransactionSegment(
      {required this.spots,
      required this.lineColor,
      required this.areaGradientStart,
      required this.areaGradientEnd,
      required this.thickness});
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Sandik.text36));
}
