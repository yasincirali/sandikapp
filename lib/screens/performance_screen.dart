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
import '../services/history_service.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class GoldTransaction {
  final DateTime date;
  final double gramChange;
  final String label;

  GoldTransaction({
    required this.date,
    required this.gramChange,
    required this.label,
  });
}

class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;

  TransactionSegment({
    required this.spots,
    required this.lineColor,
    required this.areaGradientStart,
    required this.areaGradientEnd,
    required this.thickness,
  });
}

// ── Widget ───────────────────────────────────────────────────────────────────

class PerformanceScreen extends ConsumerStatefulWidget {
  final Asset asset;

  const PerformanceScreen({super.key, required this.asset});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  late int _selectedPeriodIdx;
  String? _view = ''; // '' = Ben (Default), null = Tümü, uuid = Ortak

  static const List<({String label, int days})> _periods = [
    (label: 'GÜNLÜK', days: 1),
    (label: 'HAFTALIK', days: 7),
    (label: 'AYLIK', days: 30),
    (label: '6 AYLIK', days: 180),
    (label: 'YILLIK', days: 365),
  ];

  @override
  void initState() {
    super.initState();
    _selectedPeriodIdx = 4;
  }

  // Sadece ilgili varlığın kendi kayıt tarihine dayalı tek bir gerçek işlem üretiyoruz!
  List<GoldTransaction> get _transactions {
    final txs = <GoldTransaction>[];
    final activePartners = ref.read(activePartnersProvider);
    final allAssetsMap = ref.read(allPartnerAssetsProvider).valueOrNull ?? {};

    // Ben
    if (_view == '' || _view == null) {
      txs.add(GoldTransaction(
        date: widget.asset.addedDate,
        gramChange: widget.asset.quantity,
        label: 'ALIM (Ben)',
      ));
    }

    // Ortaklar
    for (final p in activePartners) {
      if (_view == null || _view == p.id) {
        final assets = allAssetsMap[p.id] ?? [];
        final match = assets.where((a) => a.ticker == widget.asset.ticker);
        if (match.isNotEmpty) {
          final pa = match.first;
          txs.add(GoldTransaction(
            date: pa.addedDate,
            gramChange: pa.quantity,
            label: 'ALIM (${p.displayName})',
          ));
        }
      }
    }

    return txs..sort((a, b) => a.date.compareTo(b.date));
  }

  double get _currentQuantity {
    if (_view == '') return widget.asset.quantity;

    final allAssetsMap = ref.read(allPartnerAssetsProvider).valueOrNull ?? {};

    if (_view != null) {
      final assets = allAssetsMap[_view] ?? [];
      final match = assets.where((a) => a.ticker == widget.asset.ticker);
      return match.isNotEmpty ? match.first.quantity : 0;
    }

    // Tümü
    double total = widget.asset.quantity;
    final activePartners = ref.read(activePartnersProvider);
    for (final p in activePartners) {
      final assets = allAssetsMap[p.id] ?? [];
      final match = assets.where((a) => a.ticker == widget.asset.ticker);
      if (match.isNotEmpty) total += match.first.quantity;
    }
    return total;
  }

  /// Asset'in güncel fiyatına göre geriye dönük fiktif geçmiş simülasyonu
  double _getSimulatedPrice(DateTime date) {
    final asset = widget.asset;
    final endPrice = asset.currentPrice > 0 ? asset.currentPrice : 100.0;

    final now = DateTime.now();
    final differenceDays = now.difference(date).inDays.clamp(0, 3650);

    // Varlık türüne göre tahmini yıllık getiri faktörü
    double yearlyReturn = 0.40;
    if (asset.type == AssetType.hisse) yearlyReturn = 0.70;
    if (asset.type == AssetType.emtia) yearlyReturn = 0.45;
    if (asset.type == AssetType.doviz) yearlyReturn = 0.20;
    if (asset.type == AssetType.fon) yearlyReturn = 0.50;

    // Geçmişteki fiyatı kabaca hesapla
    double simulated =
        endPrice / (1.0 + (yearlyReturn * (differenceDays / 365.0)));

    final noise =
        math.sin(date.millisecondsSinceEpoch / 86400000.0) * (simulated * 0.03);

    return simulated + noise;
  }

  double _getClosestPrice(Map<int, double> history, int targetTs) {
    if (history.isEmpty) return 0;
    if (history.containsKey(targetTs)) return history[targetTs]!;

    final keys = history.keys.toList()..sort();
    if (targetTs < keys.first) return history[keys.first]!;
    if (targetTs > keys.last) return history[keys.last]!;

    // Binary search for closest key
    int low = 0;
    int high = keys.length - 1;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      if (keys[mid] == targetTs) return history[keys[mid]]!;
      if (keys[mid] < targetTs) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    // Check which one is closer: keys[high] or keys[low]
    if (low >= keys.length) return history[keys.last]!;
    if (high < 0) return history[keys.first]!;

    if ((keys[low] - targetTs).abs() < (keys[high] - targetTs).abs()) {
      return history[keys[low]]!;
    } else {
      return history[keys[high]]!;
    }
  }

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (history.isEmpty) return [];

    final segments = <TransactionSegment>[];
    final firstAssetDate = widget.asset.addedDate;
    final firstAssetMidnight =
        DateTime(firstAssetDate.year, firstAssetDate.month, firstAssetDate.day);

    final sortedTs = history.keys.toList()..sort();
    final passiveSpots = <FlSpot>[];
    final activeSpots = <FlSpot>[];

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final x = date.difference(startDate).inDays.toDouble();
      final y = history[ts]!;

      if (date.isBefore(firstAssetMidnight)) {
        passiveSpots.add(FlSpot(x, y));
      } else {
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
        lineColor: Sandik
            .amber, // Use Amber for active tracking to match design system focus
        areaGradientStart: Sandik.amber.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5, // Thicker active line
      ));
    }

    return segments;
  }

  String _formatKiloTL(double value) {
    if (value == 0) return '0 TL';
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k TL';
    }
    return '${value.toStringAsFixed(0)} TL';
  }

  String _formatKiloTLLabel(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M TL';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k TL';
    return '${value.toStringAsFixed(0)} TL';
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriodIdx = i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? Sandik.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Sandik.gold
                          : Colors.white.withOpacity(0.35),
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

  @override
  Widget build(BuildContext context) {
    final endDate = DateTime.now();
    final startDate =
        endDate.subtract(Duration(days: _periods[_selectedPeriodIdx].days));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // No longer generating segments here, moved to FutureBuilder
    final maxX = endDate.difference(startDate).inDays.toDouble();

    // Logic moved inside FutureBuilder

    final activePartners = ref.watch(activePartnersProvider);
    final allPartnerAssetsAsync = ref.watch(allPartnerAssetsProvider);

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
        title: Text(
          'Performans: ${widget.asset.name}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              children: [
                allPartnerAssetsAsync.maybeWhen(
                  data: (allAssetsMap) {
                    final matchingPartners = <AppUser>[];
                    final matchingAssets = <Asset>[];

                    for (final p in activePartners) {
                      final assets = allAssetsMap[p.id] ?? [];
                      final match =
                          assets.where((a) => a.ticker == widget.asset.ticker);
                      if (match.isNotEmpty) {
                        matchingPartners.add(p);
                        matchingAssets.add(match.first);
                      }
                    }

                    if (matchingPartners.isEmpty)
                      return const SizedBox.shrink();

                    return Column(
                      children: [
                        ModernTabSelector(
                          partners: matchingPartners,
                          selectedId: _view,
                          onChanged: (v) => setState(() => _view = v),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
                _buildPeriodToggle(),
                const SizedBox(height: 24),
                FutureBuilder<Map<int, double>>(
                  future: HistoryService.instance.getPortfolioHistory(
                      [widget.asset], _periods[_selectedPeriodIdx].days),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                          height: 400,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Sandik.amber)));
                    }

                    final historyMap = snapshot.data ?? {};
                    final segments = _convertHistoryToSegments(
                        historyMap, startDate, endDate);

                    // Determine Min/Max Y safely
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
                    if (yPadding == 0) yPadding = maxY * 0.1;
                    if (yPadding == 0) yPadding = 10;
                    maxY = maxY + yPadding;
                    minY = (minY - yPadding).clamp(0, double.infinity);

                    // Build Vertical Lines (Transactions)
                    final verticalLines = <VerticalLine>[];
                    for (final tx in _transactions) {
                      if (tx.date.isBefore(startDate) ||
                          tx.date.isAfter(endDate)) continue;
                      final x = tx.date.difference(startDate).inDays.toDouble();
                      final monetaryChange = tx.gramChange.abs() *
                          (historyMap.isNotEmpty
                              ? _getClosestPrice(
                                  historyMap, tx.date.millisecondsSinceEpoch)
                              : _getSimulatedPrice(tx.date));
                      final sign = tx.gramChange > 0
                          ? '+'
                          : (tx.gramChange < 0 ? '-' : '');

                      verticalLines.add(
                        VerticalLine(
                          x: x,
                          color: Colors.white30,
                          strokeWidth: 2,
                          dashArray: [5, 5],
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(left: 6, bottom: 0),
                            labelResolver: (_) =>
                                '${tx.label}\n$sign${tx.gramChange.abs().toStringAsFixed(2)} ${widget.asset.unitType}\n($sign${_formatKiloTLLabel(monetaryChange)})',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.3),
                          ),
                        ),
                      );
                    }

                    return Container(
                      height: 400,
                      decoration: BoxDecoration(
                        color: Sandik.surface1,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      padding: const EdgeInsets.only(
                          top: 36, right: 16, left: 0, bottom: 16),
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
                            horizontalInterval:
                                (maxY - minY) > 0 ? (maxY - minY) / 4 : 50000,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.white.withOpacity(0.05),
                              strokeWidth: 1,
                            ),
                          ),
                          extraLinesData: ExtraLinesData(
                            extraLinesOnTop: true,
                            verticalLines: verticalLines,
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval:
                                    maxX > 0 ? (maxX / 4).ceilToDouble() : 1,
                                reservedSize: 28,
                                getTitlesWidget: (value, meta) {
                                  final date = startDate
                                      .add(Duration(days: value.toInt()));
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      DateFormat('d MMM', 'en_US').format(date),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 48,
                                interval: maxY > 0 ? maxY / 4 : 50000,
                                getTitlesWidget: (value, meta) {
                                  if (value == maxY || value == 0)
                                    return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Text(
                                      _formatKiloTL(value),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineBarsData: segments
                              .map((seg) => LineChartBarData(
                                    spots: seg.spots,
                                    isCurved: false,
                                    color: seg.lineColor,
                                    barWidth: seg.thickness,
                                    isStrokeCapRound: true,
                                    dotData: FlDotData(
                                      show: true,
                                      checkToShowDot: (spot, barData) {
                                        // Show dots at the beginning of each segment (which are transaction points)
                                        // and also check against _transactions dates for safety.
                                        final isFirstInSegment =
                                            spot.x == seg.spots.first.x;
                                        final isLastInSegment =
                                            spot.x == seg.spots.last.x;

                                        // Only show dots on the 'active' line (thickness > 1.5)
                                        if (seg.thickness <= 1.5) return false;

                                        // Show dots at transaction points
                                        final dateAtSpot = startDate.add(
                                            Duration(days: spot.x.toInt()));
                                        final hasTransaction =
                                            _transactions.any((tx) =>
                                                tx.date.year ==
                                                    dateAtSpot.year &&
                                                tx.date.month ==
                                                    dateAtSpot.month &&
                                                tx.date.day == dateAtSpot.day);

                                        return hasTransaction ||
                                            isFirstInSegment ||
                                            isLastInSegment;
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        final isActive = seg.thickness > 1.5;
                                        return FlDotCirclePainter(
                                          radius: isActive ? 4 : 2,
                                          color: isActive
                                              ? Sandik.amber
                                              : Colors.white24,
                                          strokeColor: Sandik.background,
                                          strokeWidth: 2,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: [
                                          seg.areaGradientStart,
                                          seg.areaGradientEnd
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => Colors.black87,
                              getTooltipItems: (touchedSpots) {
                                return touchedSpots.map((spot) {
                                  final date = startDate
                                      .add(Duration(days: spot.x.toInt()));
                                  return LineTooltipItem(
                                    '${DateFormat('d MMM').format(date)}\n${_formatKiloTLLabel(spot.y)}',
                                    const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                // Miktar Bilgisi
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOPLAM MİKTAR',
                        style: GoogleFonts.inter(
                            color: Sandik.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2),
                      ),
                      Text(
                        '${_currentQuantity.toStringAsFixed(2)} ${widget.asset.unitType}',
                        style: GoogleFonts.plusJakartaSans(
                            color: Sandik.gold,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
