import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';

class PortfolioPerformanceScreen extends ConsumerStatefulWidget {
  const PortfolioPerformanceScreen({super.key});

  @override
  ConsumerState<PortfolioPerformanceScreen> createState() =>
      _PortfolioPerformanceScreenState();
}

class _PortfolioPerformanceScreenState
    extends ConsumerState<PortfolioPerformanceScreen> {
  int _selectedPeriodIdx = 4; // Yıllık
  String? _view = ''; // null = Birlikte, '' = Ben, uuid = Ortak
  AssetType? _typeFilter;

  static const List<({String label, int days})> _periods = [
    (label: '1H', days: 7),
    (label: '1A', days: 30),
    (label: '3A', days: 90),
    (label: '6A', days: 180),
    (label: '1Y', days: 365),
  ];

  // ── Logic ──────────────────────────────────────────────────────────────────

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    List<Asset> allAssets,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (history.isEmpty || allAssets.isEmpty) return [];

    final segments = <TransactionSegment>[];
    final firstAssetDate = allAssets
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    // Normalize firstAssetDate to midnight for comparison
    final firstAssetMidnight =
        DateTime(firstAssetDate.year, firstAssetDate.month, firstAssetDate.day);

    final sortedTs = history.keys.toList()..sort();

    // Split into two segments: before first asset (passive) and after (active)
    final passiveSpots = <FlSpot>[];
    final activeSpots = <FlSpot>[];

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final x = date.difference(startDate).inDays.toDouble();
      final y = history[ts]!;

      if (date.isBefore(firstAssetMidnight)) {
        passiveSpots.add(FlSpot(x, y));
      } else {
        // To make segments continuous, add the last passive spot to active if active starts
        if (activeSpots.isEmpty && passiveSpots.isNotEmpty) {
          activeSpots.add(passiveSpots.last);
        }
        activeSpots.add(FlSpot(x, y));
      }
    }

    if (passiveSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: passiveSpots,
        lineColor: Colors.white.withValues(alpha: 0.15),
        areaGradientStart: Colors.white.withValues(alpha: 0.05),
        areaGradientEnd: Colors.transparent,
        thickness: 1.5,
      ));
    }

    if (activeSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: activeSpots,
        lineColor: Sandik.amber,
        areaGradientStart: Sandik.amber.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
    }

    return segments;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
        title: Text(
          'Performans',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
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
            // Filter assets based on view
            List<Asset> targetAssets = [];
            if (_view == '') {
              targetAssets = pState.assets;
            } else if (_view != null) {
              targetAssets = partnerMap[_view] ?? [];
            } else {
              targetAssets = [...pState.assets];
              for (final list in partnerMap.values) {
                targetAssets.addAll(list);
              }
            }
            // Apply asset type filter
            if (_typeFilter != null) {
              targetAssets =
                  targetAssets.where((a) => a.type == _typeFilter).toList();
            }

            return FutureBuilder<Map<int, double>>(
              future: HistoryService.instance.getPortfolioHistory(
                  targetAssets, _periods[_selectedPeriodIdx].days),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                      height: 300,
                      child: Center(
                          child:
                              CircularProgressIndicator(color: Sandik.amber)));
                }

                final historyMap = snapshot.data ?? {};
                final segments = _convertHistoryToSegments(
                    historyMap, targetAssets, startDate, endDate);

                return ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    if (activePartners.isNotEmpty) ...[
                      ModernTabSelector(
                        partners: activePartners,
                        selectedId: _view,
                        onChanged: (v) => setState(() => _view = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Asset type filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _typeChip(null, 'Tümü'),
                          for (final t in AssetType.values)
                            _typeChip(t, t.label),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodToggle(),
                    const SizedBox(height: 24),
                    _buildChartContainer(
                        segments, startDate, endDate, targetAssets),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? Sandik.amber;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Sandik.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : Sandik.text58,
            ),
          ),
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
                  color:
                      isSelected ? const Color(0xFF1A3D2E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Sandik.amber : Sandik.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// TRY değeri için okunabilir kısa etiket (₺1.2M / ₺450K / ₺900)
  String _fmtY(double val) {
    if (val >= 1000000) return '₺${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '₺${(val / 1000).toStringAsFixed(0)}K';
    return '₺${val.toStringAsFixed(0)}';
  }

  Widget _buildChartContainer(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets) {
    if (segments.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
            color: Sandik.surface1, borderRadius: BorderRadius.circular(24)),
        child: const Center(
            child: Text('Veri yok', style: TextStyle(color: Sandik.text36))),
      );
    }

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
    final yRange = (maxY - minY).clamp(1.0, double.infinity);
    final yPadding = yRange * 0.18;
    maxY += yPadding;
    minY = (minY - yPadding * 0.5).clamp(0, double.infinity);

    final maxX =
        end.difference(start).inDays.toDouble().clamp(1.0, double.infinity);

    // 4 eşit aralıklı Y etiketi (min ve max hariç)
    final yInterval = (maxY - minY) / 4;
    // X ekseni için uygun aralık (4 etiket)
    final xInterval = (maxX / 4).ceilToDouble().clamp(1.0, double.infinity);

    return Container(
      height: 360,
      padding: const EdgeInsets.fromLTRB(4, 20, 16, 12),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
          ),
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
                reservedSize: 32,
                interval: xInterval,
                getTitlesWidget: (val, meta) {
                  if (val == meta.min || val == meta.max) {
                    return const SizedBox.shrink();
                  }
                  final date = start.add(Duration(days: val.toInt()));
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('d MMM', 'tr_TR').format(date),
                      style: GoogleFonts.inter(
                        color: Sandik.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 72,
                interval: yInterval,
                getTitlesWidget: (val, meta) {
                  if (val == meta.min || val == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _fmtY(val),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        color: Sandik.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: segments.map((seg) {
            final isActive = seg.thickness > 2.0;
            return LineChartBarData(
              spots: seg.spots,
              isCurved: true,
              color: seg.lineColor,
              barWidth: seg.thickness,
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
                  radius: isActive ? 4.5 : 2,
                  color: isActive ? Sandik.amber : Colors.white24,
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
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Sandik.surface2,
              tooltipRoundedRadius: 10,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              getTooltipItems: (spots) => spots.map((s) {
                final date = start.add(Duration(days: s.x.toInt()));
                return LineTooltipItem(
                  '${DateFormat('d MMM yyyy', 'tr_TR').format(date)}\n',
                  GoogleFonts.inter(
                      color: Sandik.text58,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                  children: [
                    TextSpan(
                      text: NumberFormat.currency(
                              symbol: '₺', locale: 'tr_TR', decimalDigits: 0)
                          .format(s.y),
                      style: GoogleFonts.plusJakartaSans(
                        color: Sandik.gold,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
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
