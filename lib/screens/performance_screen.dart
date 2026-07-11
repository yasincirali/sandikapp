import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../services/notification_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../providers/preferences_provider.dart';
import 'signal_settings_screen.dart';

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

// ── Teknik Sinyal Paneli ─────────────────────────────────────────────────────

class _TechnicalSignalPanel extends ConsumerStatefulWidget {
  final Asset asset;
  const _TechnicalSignalPanel({required this.asset});

  @override
  ConsumerState<_TechnicalSignalPanel> createState() =>
      _TechnicalSignalPanelState();
}

class _TechnicalSignalPanelState extends ConsumerState<_TechnicalSignalPanel> {
  bool _notified = false;

  @override
  Widget build(BuildContext context) {
    // Kullanıcı tercihleri değiştikçe otomatik yeniden hesapla
    final prefs = ref.watch(indicatorPrefsProvider);
    final premium = ref.watch(premiumUnlockedProvider);
    final enabledIds = prefs[widget.asset.type] ??
        TechnicalAnalysisService.defaultEnabledFor(widget.asset.type);

    final indicators = TechnicalAnalysisService.analyze(
      widget.asset,
      const [],
      enabledIds: enabledIds,
      premiumUnlocked: premium,
    );

    final summary = TechnicalAnalysisService.summarize(indicators);

    // Güçlü sinyal — sadece bir kez bildirim gönder
    if (!_notified && summary.signal != SignalType.neutral && indicators.isNotEmpty) {
      _notified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.instance.sendSignalNotification(
          assetName: widget.asset.name,
          ticker: widget.asset.ticker,
          signal: summary.signal,
          buyCount: summary.buyCount,
          sellCount: summary.sellCount,
        );
      });
    }

    if (indicators.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, color: Sandik.text58, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bu varlık türü için hiçbir gösterge seçilmemiş. '
                'Profil → Sinyal Ayarları\'ndan aktifleştir.',
                style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text58),
              ),
            ),
          ],
        ),
      );
    }
    final isBuy = summary.signal == SignalType.buy;
    final isSell = summary.signal == SignalType.sell;
    final isNeutral = summary.signal == SignalType.neutral;

    final signalColor = isBuy ? Sandik.gain : isSell ? Sandik.loss : Sandik.text58;
    // Yasal not: kesin "AL/SAT" ifadesi yerine trend yönü kullanıyoruz.
    final signalLabel = isBuy ? 'YUKARI TREND' : isSell ? 'AŞAĞI TREND' : 'YATAY';
    final signalIcon = isBuy ? Icons.trending_up_rounded
        : isSell ? Icons.trending_down_rounded
        : Icons.remove_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Başlık ──────────────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'TEKNİK ANALİZ',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Sandik.text36,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· ${enabledIds.length}/${IndicatorId.all.length} gösterge',
              style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text36),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SignalSettingsScreen()),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: Sandik.amber),
                  const SizedBox(width: 4),
                  Text(
                    'Göstergeleri Ayarla',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Sandik.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const DisclaimerWidget(),
        const SizedBox(height: 12),

        // ── Özet sinyal kartı ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: signalColor.withValues(alpha: isNeutral ? 0.04 : 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: signalColor.withValues(alpha: isNeutral ? 0.08 : 0.25),
              width: isNeutral ? 1 : 1.5,
            ),
          ),
          child: Row(
            children: [
              // Sinyal ikonu
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(signalIcon, color: signalColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signalLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: signalColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.buyCount} AL · ${summary.sellCount} SAT · ${indicators.length - summary.buyCount - summary.sellCount} NÖTR',
                      style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text58),
                    ),
                  ],
                ),
              ),
              // Güven skoru
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '%${(summary.confidence * 100).toStringAsFixed(0)}',
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: signalColor,
                    ),
                  ),
                  Text(
                    'güven',
                    style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text36),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Gösterge listesi ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: indicators.asMap().entries.map((entry) {
              final i = entry.key;
              final ind = entry.value;
              final isLast = i == indicators.length - 1;
              final c = ind.signal == SignalType.buy
                  ? Sandik.gain
                  : ind.signal == SignalType.sell
                      ? Sandik.loss
                      : Sandik.text58;
              final lbl = ind.signal == SignalType.buy
                  ? 'AL'
                  : ind.signal == SignalType.sell
                      ? 'SAT'
                      : 'NÖTR';

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(
                      children: [
                        // Renkli gösterge çubuğu
                        Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ind.name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ind.description,
                                style: GoogleFonts.dmSans(
                                    fontSize: 11, color: Sandik.text36),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lbl,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.05),
                      indent: 31,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const DisclaimerWidget(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;
  final bool dashed;

  TransactionSegment({
    required this.spots,
    required this.lineColor,
    required this.areaGradientStart,
    required this.areaGradientEnd,
    required this.thickness,
    this.dashed = false,
  });
}

// ── Widget ───────────────────────────────────────────────────────────────────

class PerformanceScreen extends ConsumerStatefulWidget {
  final Asset asset;
  final bool showBackButton;

  const PerformanceScreen({super.key, required this.asset, this.showBackButton = false});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  late int _selectedPeriodIdx;
  String? _view = ''; // '' = Ben (Default), null = Tümü, uuid = Ortak
  late Future<Map<int, double>> _historyFuture;

  static const List<({String label, int days})> _periods = [
    (label: 'HAFTALIK', days: 7),
    (label: 'AYLIK', days: 30),
    (label: '6 AYLIK', days: 180),
    (label: 'YILLIK', days: 365),
  ];

  @override
  void initState() {
    super.initState();
    _selectedPeriodIdx = 0;
    _historyFuture = HistoryService.instance
        .getPortfolioHistory([widget.asset], _periods[0].days);
  }

  void _selectPeriod(int idx) {
    setState(() {
      _selectedPeriodIdx = idx;
      _historyFuture = HistoryService.instance
          .getPortfolioHistory([widget.asset], _periods[idx].days);
    });
  }


  void _confirmDelete(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Varlığı Sil'),
        content:
            Text('"${widget.asset.name}" kalıcı olarak silinsin mi?'),
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
                    .deleteAsset(widget.asset.id);
                if (!mounted) return;
                Navigator.pop(context);
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

    // Aktif segmentin ilk history noktasını alım maliyetiyle değiştir.
    final anchorCost = widget.asset.totalCostTRY;

    final sortedTs = history.keys.toList()..sort();
    final passiveSpots = <FlSpot>[];
    final activeSpots = <FlSpot>[];
    bool firstActiveReplaced = false;

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final x = date.difference(startDate).inDays.toDouble();
      final y = history[ts]!;

      if (date.isBefore(firstAssetMidnight)) {
        passiveSpots.add(FlSpot(x, y));
      } else {
        if (!firstActiveReplaced && anchorCost > 0) {
          if (passiveSpots.isNotEmpty) {
            activeSpots.add(passiveSpots.last);
          }
          activeSpots.add(FlSpot(x, anchorCost));
          firstActiveReplaced = true;
        } else {
          activeSpots.add(FlSpot(x, y));
        }
      }
    }

    if (passiveSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: passiveSpots,
        lineColor: Colors.white.withValues(alpha: 0.10),
        areaGradientStart: Colors.white.withValues(alpha: 0.02),
        areaGradientEnd: Colors.transparent,
        thickness: 1.2,
        dashed: true,
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
              onTap: () => _selectPeriod(i),
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
                    style: GoogleFonts.dmSans(
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
    final period = _periods[_selectedPeriodIdx];
    final startDate = endDate.subtract(Duration(days: period.days));
    final maxX = endDate.difference(startDate).inDays.toDouble();

    // Logic moved inside FutureBuilder

    final activePartners = ref.watch(activePartnersProvider);
    final allPartnerAssetsAsync = ref.watch(allPartnerAssetsProvider);

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;
    final isOwnAsset = currentUserId != null && widget.asset.userId == currentUserId;

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Performans: ${widget.asset.name}',
          style: GoogleFonts.dmSans(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          if (isOwnAsset && !widget.showBackButton)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFEF4444), size: 20),
                      SizedBox(width: 10),
                      Text('Sil',
                          style: TextStyle(color: Color(0xFFEF4444))),
                    ],
                  ),
                ),
              ],
            ),
        ],
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
                  future: _historyFuture,
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
                    double sumY = 0;
                    int countY = 0;
                    for (final seg in segments) {
                      for (final spot in seg.spots) {
                        if (spot.y > maxY) maxY = spot.y;
                        if (spot.y < minY) minY = spot.y;
                        sumY += spot.y;
                        countY++;
                      }
                    }
                    if (minY == double.infinity) minY = 0;
                    if (maxY == -double.infinity) maxY = 1000;
                    final avgY = countY > 0 ? sumY / countY : (minY + maxY) / 2;
                    final dataRange = (maxY - minY).clamp(1.0, double.infinity);
                    final minSpread = (avgY * 0.08).clamp(1.0, double.infinity);
                    final effectiveRange =
                        dataRange < minSpread ? minSpread : dataRange;
                    final yPad = effectiveRange * 0.1;
                    maxY = (avgY + effectiveRange / 2) + yPad;
                    minY = (avgY - effectiveRange / 2 - yPad).clamp(0, double.infinity);

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
                                  final date = startDate.add(Duration(days: value.toInt()));
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
                                    dashArray: seg.dashed ? const [4, 4] : null,
                                    dotData: FlDotData(
                                      show: !seg.dashed,
                                      checkToShowDot: (spot, barData) {
                                        // Pasif (silik) segmentte hiç nokta yok.
                                        if (seg.dashed) return false;
                                        // Sadece gerçek alım tarihine denk gelen noktada göster.
                                        final dateAtSpot = startDate.add(Duration(days: spot.x.toInt()));
                                        return _transactions.any((tx) =>
                                            tx.date.year == dateAtSpot.year &&
                                            tx.date.month == dateAtSpot.month &&
                                            tx.date.day == dateAtSpot.day);
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                          radius: 2.5,
                                          color: Sandik.amber,
                                          strokeColor: Sandik.background,
                                          strokeWidth: 1.5,
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
                                  final date = startDate.add(Duration(days: spot.x.toInt()));
                                  final dateLabel = DateFormat('d MMM').format(date);
                                  return LineTooltipItem(
                                    '$dateLabel\n${_formatKiloTLLabel(spot.y)}',
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
                        style: GoogleFonts.dmSans(
                            color: Sandik.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2),
                      ),
                      Text(
                        '${_currentQuantity.toStringAsFixed(2)} ${widget.asset.unitType}',
                        style: GoogleFonts.dmSans(
                            color: Sandik.gold,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _TechnicalSignalPanel(asset: widget.asset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
