import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
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
    // NOT: Push bildirimi burada tetiklenmez — bu widget her ekran açılışında
    // yeniden build olduğu için her tıklamada yeni push atardı. Sinyal push'u
    // artık sadece günlük cron (analyze-signals edge function → analyzePortfolio)
    // tarafından üretilir. Bu panel sadece göstergelerin özetini gösterir.

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
  /// Aggregate edilmiş pozisyonun tüm lot'ları (buy + sell). Grafik üstünde
  /// işlem marker'ları çizmek için kullanılır. Boş bırakılırsa sadece
  /// [asset]'in kendisi tek buy olarak varsayılır.
  final List<Asset>? lots;

  const PerformanceScreen({
    super.key,
    required this.asset,
    this.showBackButton = false,
    this.lots,
  });

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
    DateTime endDate, {
    double? currentUnitPriceOverride,
  }) {
    if (history.isEmpty) return [];

    final segments = <TransactionSegment>[];
    final firstAssetDate = widget.asset.addedDate;
    final firstAssetMidnight =
        DateTime(firstAssetDate.year, firstAssetDate.month, firstAssetDate.day);

    // Grafik "birim fiyat" (TL) gösterir — HistoryService'in döndürdüğü
    // toplam pozisyon değerini quantity'ye bölerek per-unit fiyata çeviririz.
    // Böylece ek alım/sell miktarı değiştirdiğinde grafik çizgisinde suni
    // sıçrama olmaz; sadece cost basis (yatay çizgi) rebase olur.
    final qty = widget.asset.quantity;
    final divisor = qty > 0 ? qty : 1.0;

    // Anchor = alım anındaki birim fiyat (TL cinsinden).
    final anchorUnitPrice =
        widget.asset.purchasePrice * widget.asset.purchaseFxRate;

    final sortedTs = history.keys.toList()..sort();
    final passiveSpots = <FlSpot>[];
    final activeSpots = <FlSpot>[];
    bool firstActiveReplaced = false;

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final x = date.difference(startDate).inDays.toDouble();
      final y = history[ts]! / divisor;

      if (date.isBefore(firstAssetMidnight)) {
        passiveSpots.add(FlSpot(x, y));
      } else {
        if (!firstActiveReplaced && anchorUnitPrice > 0) {
          // Aktif segmentin İLK noktası her zaman anchor (ort. maliyet).
          // Passive çizgisiyle görsel bağlantı için: anchor spot'unu
          // passive segmentin de sonuna ekliyoruz. Böylece kesikli çizgi
          // anchor noktasına kadar uzanır, aktif çizgi de aynı noktadan
          // başlar — arada boşluk kalmaz.
          activeSpots.add(FlSpot(x, anchorUnitPrice));
          passiveSpots.add(FlSpot(x, anchorUnitPrice));
          firstActiveReplaced = true;
        } else {
          activeSpots.add(FlSpot(x, y));
        }
      }
    }

    // Son aktif spot'u canlı fiyat ile değiştir — böylece grafik bitiş
    // noktası ve üstteki PnL chip aynı değeri gösterir (Yahoo history son
    // bar'ı ile canlı `currentPrice` arasındaki gecikme/ölçek farkını kapat).
    // ANCAK aktif segmentte tek spot varsa (yani ilk alım = bugün), o spot
    // anchor'dır — override edersen anchor "bugünkü fiyat" olur ve ALIŞ
    // çizgisi yanlış yerde çizilir. Bu durumda anchor'ı olduğu gibi bırakıp
    // canlı fiyat için ayrı bir "son" spot ekleriz (biraz farklı X ile).
    if (currentUnitPriceOverride != null &&
        currentUnitPriceOverride > 0 &&
        activeSpots.isNotEmpty) {
      if (activeSpots.length >= 2) {
        final last = activeSpots.last;
        activeSpots[activeSpots.length - 1] =
            FlSpot(last.x, currentUnitPriceOverride);
      } else {
        // Tek spot (anchor) var — ayrı bir "bugün" noktası ekle. X biraz
        // ileride (bugünün offset'i) olsun.
        final anchorX = activeSpots.first.x;
        final todayX =
            DateTime.now().difference(startDate).inDays.toDouble();
        // Aynı gün ise minik bir ε ekle ki iki nokta farklı X'te olsun.
        final endX = todayX > anchorX ? todayX : anchorX + 0.01;
        activeSpots.add(FlSpot(endX, currentUnitPriceOverride));
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

  String _formatKiloTL(double value, {double? scaleHint}) {
    if (value == 0) return '0 TL';
    // scaleHint: grafik aralığı (maxY-minY). Küçükse daha çok ondalık göster
    // ki komşu etiketler farklı görünsün (40.5k vs 40.7k gibi).
    final hint = scaleHint ?? value;
    if (value >= 1000) {
      final digits = hint < 5000 ? 2 : (hint < 50000 ? 1 : 0);
      return '${(value / 1000).toStringAsFixed(digits)}k TL';
    }
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
    final pState = ref.watch(portfolioProvider).valueOrNull;

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
                if (!widget.showBackButton)
                  allPartnerAssetsAsync.maybeWhen(
                    data: (allAssetsMap) {
                      final matchingPartners = <AppUser>[];
                      final matchingAssets = <Asset>[];

                      for (final p in activePartners) {
                        final assets = allAssetsMap[p.id] ?? [];
                        final match = assets
                            .where((a) => a.ticker == widget.asset.ticker);
                        if (match.isNotEmpty) {
                          matchingPartners.add(p);
                          matchingAssets.add(match.first);
                        }
                      }

                      if (matchingPartners.isEmpty) {
                        return const SizedBox.shrink();
                      }

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

                    // ── PnL: KART İLE BİREBİR AYNI FORMÜL ───────────────────
                    // Grafiğin son noktasını da bu canlı değerle sabitliyoruz
                    // (aşağıdaki `currentUnitPriceOverride`) — böylece grafik
                    // bitiş noktası ve chip her zaman aynı sayıyı gösterir.
                    final asset = widget.asset;
                    final qty = asset.quantity;
                    final anchorUnitTRY =
                        asset.purchasePrice * asset.purchaseFxRate;
                    final currentValueTRY = pState != null
                        ? pState.toTRY(asset.totalValue, asset.currency)
                        : asset.totalValue;
                    final currentUnitTRY = qty > 0 ? currentValueTRY / qty : 0.0;

                    final segments = _convertHistoryToSegments(
                        historyMap, startDate, endDate,
                        currentUnitPriceOverride: currentUnitTRY);

                    // Aktif segmenti bul (kesikli olmayan, yani alım sonrası)
                    final activeSeg = segments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: Sandik.amber,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final anchorSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.first : null;
                    final lastSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.last : null;
                    final anchorY = anchorSpot?.y ?? 0.0;
                    final totalCostTRY = asset.totalCostTRY;
                    final totalPnlTRY = currentValueTRY - totalCostTRY;
                    final pnlPct = totalCostTRY > 0
                        ? (totalPnlTRY / totalCostTRY) * 100
                        : 0.0;
                    final gainPositive = totalPnlTRY >= 0;
                    final endpointColor =
                        gainPositive ? Sandik.gain : Sandik.loss;

                    // Lot marker'ları için: gün-hassasiyetli tarih → (isSell) map.
                    // Aynı güne birden fazla işlem düşerse buy önceliklidir
                    // (ek alım genelde daha anlamlı sinyal).
                    final Map<int, bool> lotDayIsSell = {};
                    final activeLots = widget.lots ?? [widget.asset];
                    for (final lot in activeLots) {
                      if (lot.isDeleteLog) continue;
                      final d = DateTime(lot.addedDate.year,
                          lot.addedDate.month, lot.addedDate.day);
                      if (d.isBefore(startDate)) continue;
                      final dayKey = d.difference(startDate).inDays;
                      final isSell = lot.isSell;
                      // Buy varsa buy kalsın (override etme)
                      if (lotDayIsSell.containsKey(dayKey) &&
                          !lotDayIsSell[dayKey]!) {
                        continue;
                      }
                      lotDayIsSell[dayKey] = isSell;
                    }

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

                    // Y ekseni ölçeği ANCHOR MERKEZLİ:
                    // - ALIŞ çizgisi grafiğin tam ortasında dursun,
                    // - Küçük hareketler (%0.5 gibi) görsel olarak belirgin
                    //   çıksın (minimum spread anchor'ın ±%1'i),
                    // - Anchor'dan uzaklaşan noktalar simetrik ile sığdırılır.
                    final center = anchorY > 0 ? anchorY : (minY + maxY) / 2;
                    double maxAbsDev = 0;
                    for (final seg in segments) {
                      for (final spot in seg.spots) {
                        final dev = (spot.y - center).abs();
                        if (dev > maxAbsDev) maxAbsDev = dev;
                      }
                    }
                    // Minimum sapma: anchor'ın %1'i — küçük değişimler bile
                    // grafikte gözle görülür genlikte çizilsin.
                    final minDev = (center * 0.01).clamp(1.0, double.infinity);
                    final halfRange = maxAbsDev < minDev ? minDev : maxAbsDev;
                    final yPad = halfRange * 0.35;
                    maxY = center + halfRange + yPad;
                    minY = (center - halfRange - yPad).clamp(0, double.infinity);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (anchorSpot != null && lastSpot != null)
                          _PnlSummaryStrip(
                            anchorUnitPrice: anchorUnitTRY,
                            currentUnitPrice: currentUnitTRY,
                            pnlPct: pnlPct,
                            totalPnl: totalPnlTRY,
                            unitLabel: widget.asset.unitLabel,
                            isPositive: gainPositive,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: 12),
                        Container(
                          height: 400,
                          decoration: BoxDecoration(
                            color: Sandik.surface1,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.05)),
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
                                      _formatKiloTL(value,
                                          scaleHint: maxY - minY),
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
                          extraLinesData: anchorSpot != null
                              ? ExtraLinesData(
                                  horizontalLines: [
                                    HorizontalLine(
                                      y: anchorY,
                                      color: Colors.white.withValues(alpha: 0.35),
                                      strokeWidth: 1,
                                      dashArray: const [4, 4],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        alignment: Alignment.topLeft,
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 2),
                                        style: GoogleFonts.dmSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white
                                              .withValues(alpha: 0.75),
                                        ),
                                        labelResolver: (_) =>
                                            'ALIŞ  ${NumberFormat('#,##0.00', 'tr_TR').format(anchorY)} ₺',
                                      ),
                                    ),
                                  ],
                                )
                              : const ExtraLinesData(),
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
                                        // Başlangıç (alış) ve bitiş (son) her zaman görünsün.
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return true;
                                        }
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return true;
                                        }
                                        // Lot işlem günleri (ek alım/sell) marker göster.
                                        return lotDayIsSell
                                            .containsKey(spot.x.toInt());
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        // Alış noktası (ilk buy): beyaz halkalı amber
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 7,
                                            color: Sandik.amber,
                                            strokeColor: Colors.white,
                                            strokeWidth: 3,
                                          );
                                        }
                                        // Son nokta: kar/zarar rengi
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 8,
                                            color: endpointColor,
                                            strokeColor: Colors.white,
                                            strokeWidth: 3,
                                          );
                                        }
                                        // Ek alım / satış marker'ları
                                        final isSell =
                                            lotDayIsSell[spot.x.toInt()];
                                        if (isSell != null) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: isSell
                                                ? Sandik.loss
                                                : Sandik.gain,
                                            strokeColor: Colors.white,
                                            strokeWidth: 2,
                                          );
                                        }
                                        return FlDotCirclePainter(
                                          radius: 3.5,
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
                              getTooltipColor: (_) =>
                                  Sandik.surface1.withValues(alpha: 0.95),
                              tooltipRoundedRadius: 10,
                              tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (touchedSpots) {
                                final valueFmt =
                                    NumberFormat('#,##0.000', 'tr_TR');
                                // Passive + active segmentler anchor noktasında
                                // aynı (x, y) spot'unu paylaşır → aynı tooltip
                                // iki kere görünür. Yakın olanları filtrele.
                                final seen = <String>{};
                                return touchedSpots.map<LineTooltipItem?>((spot) {
                                  final key =
                                      '${spot.x.toStringAsFixed(2)}|${spot.y.toStringAsFixed(2)}';
                                  if (!seen.add(key)) return null;
                                  final date = startDate
                                      .add(Duration(days: spot.x.toInt()));
                                  final dateLabel = DateFormat('d MMM', 'tr_TR')
                                      .format(date);
                                  return LineTooltipItem(
                                    '${valueFmt.format(spot.y)} ₺',
                                    GoogleFonts.dmSans(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '\n$dateLabel',
                                        style: GoogleFonts.dmSans(
                                          color: Sandik.text58,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ),
                      ),
                        ),
                      ],
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
                if (widget.asset.type != AssetType.mevduat)
                  _TechnicalSignalPanel(asset: widget.asset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PnL özet strip'i (alış → şimdi + değişim) ────────────────────────────────

class _PnlSummaryStrip extends StatelessWidget {
  final double anchorUnitPrice;
  final double currentUnitPrice;
  final double pnlPct;
  final double totalPnl;
  final String unitLabel;
  final bool isPositive;

  const _PnlSummaryStrip({
    required this.anchorUnitPrice,
    required this.currentUnitPrice,
    required this.pnlPct,
    required this.totalPnl,
    required this.unitLabel,
    required this.isPositive,
  });

  String _fmtPrice(double v) {
    // Birim fiyat — kullanıcı per-unit farkı algılayabilsin diye ondalık koru.
    // Grup ayraçlı, 2 ondalıklı (tr locale).
    final f = NumberFormat('#,##0.00', 'tr_TR');
    return '${f.format(v)} ₺';
  }

  String _fmtTotal(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M ₺';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k ₺';
    return '${v.toStringAsFixed(0)} ₺';
  }

  @override
  Widget build(BuildContext context) {
    // Değişim yoksa (yuvarlanmış tutar ve yüzde ikisi de sıfırsa) nötr göster.
    final bool isFlat =
        totalPnl.abs().round() == 0 && pnlPct.abs() < 0.005;
    final Color accent = isFlat
        ? Sandik.text36
        : (isPositive ? Sandik.gain : Sandik.loss);
    final String sign = isPositive ? '+' : '−';
    final IconData arrow = isPositive
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.8), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ALIŞ / $unitLabel',
                    style: GoogleFonts.dmSans(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: Sandik.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(anchorUnitPrice),
                      maxLines: 1,
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.75))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded,
                size: 14, color: Sandik.text36),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUGÜN / $unitLabel',
                    style: GoogleFonts.dmSans(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: Sandik.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(currentUnitPrice),
                      maxLines: 1,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isFlat)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.horizontal_rule_rounded,
                      size: 14, color: Sandik.text58),
                  const SizedBox(width: 4),
                  Text('Değişim yok',
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Sandik.text58)),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(arrow, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$sign${_fmtTotal(totalPnl.abs())}',
                          style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(
                          '$sign${_fmtPrice((currentUnitPrice - anchorUnitPrice).abs())} / $unitLabel',
                          style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.2)),
                      const SizedBox(height: 1),
                      Text('%${pnlPct.abs().toStringAsFixed(2)}',
                          style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.0)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
