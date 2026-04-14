import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../services/database_service.dart';

// ── Period definitions ────────────────────────────────────────────────────────

class _Period {
  final String label;
  final int days;
  const _Period(this.label, this.days);
}

const _periods = [
  _Period('1G', 1),
  _Period('1H', 7),
  _Period('1A', 30),
  _Period('3A', 90),
  _Period('6A', 180),
  _Period('1Y', 365),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ChartsScreen extends ConsumerStatefulWidget {
  const ChartsScreen({super.key});

  @override
  ConsumerState<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends ConsumerState<ChartsScreen> {
  int _periodIdx = 2; // default: 1A (30 days)
  List<({int ts, Map<String, double> values})> _snapshots = [];
  bool _loading = true;
  AssetType? _focusedCategory; // null = total portfolio

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshThenLoad());
  }

  /// Refreshes prices (saves snapshot), then loads snapshots for current period.
  Future<void> _refreshThenLoad() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final pState = ref.read(portfolioProvider).valueOrNull;
      if (pState != null && pState.assets.isNotEmpty) {
        await ref.read(portfolioProvider.notifier).refreshPrices();
      }
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final since = DateTime.now()
          .subtract(Duration(days: _periods[_periodIdx].days))
          .millisecondsSinceEpoch;
      final snaps = await DatabaseService.instance.fetchSnapshots(since);
      if (mounted)
        setState(() {
          _snapshots = snaps;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Data helpers ─────────────────────────────────────────────────────────

  double _total(Map<String, double> values) =>
      values.values.fold(0.0, (s, v) => s + v);

  /// Normalized spots (X: 0–100, Y: TRY value)
  List<FlSpot> _spots({AssetType? category}) {
    if (_snapshots.length < 2) return [];
    final firstTs = _snapshots.first.ts.toDouble();
    final range = (_snapshots.last.ts - _snapshots.first.ts).toDouble();
    if (range <= 0) return [];
    return _snapshots.map((s) {
      final x = (s.ts - firstTs) / range * 100;
      final y = category == null
          ? _total(s.values)
          : (s.values[category.name] ?? 0.0);
      return FlSpot(x, y);
    }).toList();
  }

  String _dateLabel(int tsMs, {bool short = true}) {
    final d = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final days = _periods[_periodIdx].days;
    if (days <= 1) return DateFormat('HH:mm').format(d);
    if (days <= 7) return DateFormat(short ? 'EEE' : 'EEE d/M').format(d);
    if (days <= 90) return DateFormat(short ? 'd/M' : 'd MMM yy').format(d);
    return DateFormat(short ? 'M/yy' : 'MMM yyyy').format(d);
  }

  int _tsFromNormX(double nx) {
    if (_snapshots.length < 2) return 0;
    final first = _snapshots.first.ts;
    final last = _snapshots.last.ts;
    return first + ((last - first) * nx / 100).round();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pState = ref.watch(portfolioProvider).valueOrNull;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Performans'),
        actions: [
          if (!_loading)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: cs.primary),
              tooltip: 'Yenile',
              onPressed: _refreshThenLoad,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : RefreshIndicator(
              color: cs.primary,
              onRefresh: _refreshThenLoad,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _periodSelector(cs),
                          const SizedBox(height: 16),
                          _mainChartCard(cs, pState),
                          if (pState != null && pState.assets.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _allocationCard(cs, pState),
                            const SizedBox(height: 16),
                            _categorySection(cs),
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Period selector ───────────────────────────────────────────────────────

  Widget _periodSelector(ColorScheme cs) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final selected = _periodIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_periodIdx == i) return;
                setState(() {
                  _periodIdx = i;
                  _focusedCategory = null;
                });
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: cs.primary.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : cs.onSurfaceVariant,
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

  // ── Main portfolio chart card ─────────────────────────────────────────────

  Widget _mainChartCard(ColorScheme cs, PortfolioState? pState) {
    final spots = _spots(category: _focusedCategory);
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final lineColor = _focusedCategory?.color ?? cs.primary;

    // Current value
    final currentVal = pState == null
        ? 0.0
        : _focusedCategory == null
            ? pState.totalValue
            : pState.assets.where((a) => a.type == _focusedCategory).fold(
                0.0, (s, a) => s + pState.toTRY(a.totalValue, a.currency));

    // Period start value
    final startVal = _snapshots.isNotEmpty
        ? (_focusedCategory == null
            ? _total(_snapshots.first.values)
            : (_snapshots.first.values[_focusedCategory!.name] ?? 0.0))
        : null;

    final pctChange = (startVal != null && startVal > 0)
        ? (currentVal - startVal) / startVal * 100
        : null;
    final isPos = pctChange == null || pctChange >= 0;
    final gainColor = isPos ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_focusedCategory != null) ...[
                            Icon(_focusedCategory!.icon,
                                size: 13, color: _focusedCategory!.color),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            _focusedCategory == null
                                ? 'TOPLAM PORTFÖY'
                                : _focusedCategory!.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: _focusedCategory?.color ??
                                  cs.onSurfaceVariant,
                            ),
                          ),
                          if (_focusedCategory != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _focusedCategory = null),
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tryFmt.format(currentVal),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pctChange != null) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: gainColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPos
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: gainColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${isPos ? '+' : ''}${pctChange.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: gainColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _periods[_periodIdx].label,
                        style:
                            TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Chart or empty state
          if (spots.length < 2)
            _emptyChart(cs)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 16, 16),
              child: SizedBox(
                height: 180,
                child: _buildLineChart(spots, lineColor, gainColor, cs,
                    showAxes: true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyChart(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3), size: 36),
              const SizedBox(height: 10),
              Text(
                'Grafik için yeterli veri yok',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ana sayfadan fiyatları birkaç kez güncelleyin',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── LineChart builder ─────────────────────────────────────────────────────

  Widget _buildLineChart(
    List<FlSpot> spots,
    Color lineColor,
    Color gainColor,
    ColorScheme cs, {
    bool showAxes = false,
    bool showTouch = true,
  }) {
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = maxY == minY ? maxY * 0.05 + 100 : (maxY - minY) * 0.12;
    final yMin = (minY - pad).clamp(0.0, double.infinity);
    final yMax = maxY + pad;

    final tryCompact = NumberFormat.compactCurrency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 1);
    final tryFull =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return LineChart(
      LineChartData(
        minY: yMin,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: showAxes,
          drawVerticalLine: false,
          horizontalInterval: (yMax - yMin) / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.2),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showAxes,
              reservedSize: 58,
              interval: (yMax - yMin) / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  tryCompact.format(v),
                  style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showAxes,
              reservedSize: 24,
              interval: 25,
              getTitlesWidget: (v, _) {
                final ts = _tsFromNormX(v);
                if (ts == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dateLabel(ts),
                    style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: lineColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: spots.length <= 8,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: lineColor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withValues(alpha: 0.28),
                  lineColor.withValues(alpha: 0.04),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: showTouch
            ? LineTouchData(
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (_, indices) => indices
                    .map((_) => TouchedSpotIndicatorData(
                          FlLine(
                              color: lineColor.withValues(alpha: 0.5),
                              strokeWidth: 1.5,
                              dashArray: [4, 4]),
                          FlDotData(
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 5,
                              color: lineColor,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ))
                    .toList(),
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      cs.inverseSurface.withValues(alpha: 0.92),
                  tooltipRoundedRadius: 10,
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                    final ts = _tsFromNormX(s.x);
                    final dateStr = ts > 0 ? _dateLabel(ts, short: false) : '';
                    return LineTooltipItem(
                      '$dateStr\n${tryFull.format(s.y)}',
                      TextStyle(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    );
                  }).toList(),
                ),
              )
            : const LineTouchData(enabled: false),
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ── Allocation donut card ─────────────────────────────────────────────────

  Widget _allocationCard(ColorScheme cs, PortfolioState pState) {
    final totals = <AssetType, double>{};
    for (final a in pState.assets) {
      totals[a.type] =
          (totals[a.type] ?? 0) + pState.toTRY(a.totalValue, a.currency);
    }
    if (totals.isEmpty || pState.totalValue == 0)
      return const SizedBox.shrink();

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.donut_large_rounded, size: 13, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'GÜNCEL DAĞILIM',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.primary,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              // Donut chart
              SizedBox(
                width: 140,
                height: 140,
                child: PieChart(
                  PieChartData(
                    sections: sorted.asMap().entries.map((e) {
                      final type = e.value.key;
                      final val = e.value.value;
                      final pct = val / pState.totalValue * 100;
                      final selected = _focusedCategory == type;
                      return PieChartSectionData(
                        color: type.color,
                        value: val,
                        radius: selected ? 52 : 40,
                        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        if (!event.isInterestedForInteractions) return;
                        final idx =
                            response?.touchedSection?.touchedSectionIndex;
                        setState(() {
                          if (idx != null && idx >= 0 && idx < sorted.length) {
                            final cat = sorted[idx].key;
                            _focusedCategory =
                                _focusedCategory == cat ? null : cat;
                          } else {
                            _focusedCategory = null;
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sorted.map((e) {
                    final pct =
                        (e.value / pState.totalValue * 100).toStringAsFixed(1);
                    final selected = _focusedCategory == e.key;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _focusedCategory =
                            _focusedCategory == e.key ? null : e.key;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected
                              ? e.key.color.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(
                                  color: e.key.color.withValues(alpha: 0.35),
                                  width: 1)
                              : null,
                        ),
                        child: Row(children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: e.key.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              e.key.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          if (_focusedCategory != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _focusedCategory!.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _focusedCategory!.color.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(_focusedCategory!.icon,
                    size: 16, color: _focusedCategory!.color),
                const SizedBox(width: 8),
                Text(
                  _focusedCategory!.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _focusedCategory!.color,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  tryFmt.format(totals[_focusedCategory!] ?? 0),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── Per-category charts ───────────────────────────────────────────────────

  Widget _categorySection(ColorScheme cs) {
    if (_snapshots.length < 2) return const SizedBox.shrink();

    final cats = AssetType.values
        .where((t) => _snapshots.any((s) => (s.values[t.name] ?? 0) > 0))
        .toList();

    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'KATEGORİ GELİŞİMİ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        ...cats.map((cat) => _categoryCard(cat, cs)),
      ],
    );
  }

  Widget _categoryCard(AssetType cat, ColorScheme cs) {
    final spots = _spots(category: cat);
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    final latestVal =
        _snapshots.isNotEmpty ? (_snapshots.last.values[cat.name] ?? 0.0) : 0.0;
    final firstVal = _snapshots.isNotEmpty
        ? (_snapshots.first.values[cat.name] ?? 0.0)
        : 0.0;
    final pctChange =
        firstVal > 0 ? (latestVal - firstVal) / firstVal * 100 : null;
    final isPos = pctChange == null || pctChange >= 0;
    final gainColor = isPos ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final isFocused = _focusedCategory == cat;

    return GestureDetector(
      onTap: () {
        setState(() {
          _focusedCategory = isFocused ? null : cat;
        });
        // Kategori değiştiğinde veri tazelensin
        if (!isFocused) {
          _load();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFocused
                ? cat.color.withValues(alpha: 0.5)
                : cs.outlineVariant.withValues(alpha: 0.3),
            width: isFocused ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(cat.icon, size: 16, color: cat.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        tryFmt.format(latestVal),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pctChange != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: gainColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isPos ? '+' : ''}${pctChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: gainColor,
                      ),
                    ),
                  ),
              ]),
            ),
            if (spots.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 12, 10),
                child: SizedBox(
                  height: 72,
                  child: _buildLineChart(
                    spots,
                    cat.color,
                    gainColor,
                    cs,
                    showAxes: false,
                    showTouch: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
