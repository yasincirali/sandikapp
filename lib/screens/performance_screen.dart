import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/spot_lookup.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/zoomable_chart.dart';
import '../providers/preferences_provider.dart';
import '../widgets/fullscreen_chart_route.dart';
import 'signal_settings_screen.dart';
import '../models/asset_categories.dart';
import '../services/tefas_service.dart';
import '../widgets/custom_loading_indicator.dart';

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
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: context.c.text58, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bu varlık türü için hiçbir gösterge seçilmemiş. '
                'Profil → Sinyal Ayarları\'ndan aktifleştir.',
                style: context.t.titleSmall?.copyWith(color: context.c.text58),
              ),
            ),
          ],
        ),
      );
    }
    final isBuy = summary.signal == SignalType.buy;
    final isSell = summary.signal == SignalType.sell;
    final isNeutral = summary.signal == SignalType.neutral;

    final signalColor = isBuy ? context.c.gain : isSell ? context.c.loss : context.c.text58;
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
            // Başlık + sayaç dar ekranda sağdaki ayar bağlantısını taşırıyordu.
            // Flexible: önce sayaç, gerekirse başlık kırpılır.
            Flexible(
              child: Text(
                'TEKNİK ANALİZ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.c.text58,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '· ${enabledIds.length}/${IndicatorId.all.length} gösterge',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                adaptiveRoute(
                    builder: (_) => const SignalSettingsScreen()),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: context.c.amberText),
                  const SizedBox(width: 4),
                  Text(
                    'Göstergeleri Ayarla',
                    style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.amberText,
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
            borderRadius: BorderRadius.circular(SandikRadius.lg),
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
                      style: context.t.headlineLarge?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: signalColor,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.buyCount} AL · ${summary.sellCount} SAT · ${indicators.length - summary.buyCount - summary.sellCount} NÖTR',
                      style: context.t.titleSmall?.copyWith(color: context.c.text58),
                    ),
                  ],
                ),
              ),
              // Güven skoru
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtPct(summary.confidence, digits: 0),
                    // Güven skoru (%) — tabular figür, değişince zıplamasın.
                    style: context.t.numLarge.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: signalColor,
                    ),
                  ),
                  Text(
                    'güven',
                    style: context.t.bodySmall?.copyWith(color: context.c.text36),
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
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
          child: Column(
            children: indicators.asMap().entries.map((entry) {
              final i = entry.key;
              final ind = entry.value;
              final isLast = i == indicators.length - 1;
              final c = ind.signal == SignalType.buy
                  ? context.c.gain
                  : ind.signal == SignalType.sell
                      ? context.c.loss
                      : context.c.text58;
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
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ind.name,
                                style: context.t.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.c.text90,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ind.description,
                                style: context.t.bodySmall
                                    ?.copyWith(color: context.c.text36),
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
                            borderRadius: BorderRadius.circular(SandikRadius.sm),
                          ),
                          child: Text(
                            lbl,
                            style: context.t.titleSmall?.copyWith(
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
                      color: context.c.overlay,
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
  /// Landscape fullscreen'de açılınca grafik hemen görünsün diye body
  /// başlangıçta bu offset kadar aşağı kayar. Kullanıcı yukarı swipe ile
  /// header'a döner.
  final double initialScrollOffset;

  const PerformanceScreen({
    super.key,
    required this.asset,
    this.showBackButton = false,
    this.lots,
    this.initialScrollOffset = 0,
  });

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  /// Y/X ekseni interval'i için TradingView tarzı "nice number" —
  /// 1/2/2.5/5/10 tabanında yuvarlar. Örn: 34398 → 50000, 137 → 200.
  double _niceRound(double raw) {
    if (raw <= 0) return 1;
    final magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    double nice;
    if (normalized <= 1) {
      nice = 1;
    } else if (normalized <= 2) {
      nice = 2;
    } else if (normalized <= 2.5) {
      nice = 2.5;
    } else if (normalized <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  late int _selectedPeriodIdx;
  String? _view = ''; // '' = Ben (Default), null = Tümü, uuid = Ortak
  late Future<Map<int, double>> _historyFuture;
  late ScrollController _scrollController;
  // Compare mode: seçili karşılaştırma varlığı (kullanıcının portföyünden).
  // null = compare kapalı. Bu varlığın history serisi ana varlıkla aynı
  // periyotta fetch edilir, ilk nokta 100 kabul edilip % normalize edilir.
  Asset? _compareAsset;
  Future<Map<int, double>>? _compareHistoryFuture;

  static const List<({String label, int days})> _periods = [
    (label: 'HAFTALIK', days: 7),
    (label: 'AYLIK', days: 30),
    (label: '6 AYLIK', days: 180),
    (label: 'YILLIK', days: 365),
  ];

  // Son başarılı history sonucu. Periyot değiştiğinde FutureBuilder yeni
  // future'ı "waiting" sayar ve snapshot.data null olur; bu alan olmadan
  // grafik + altındaki tüm kontroller (compare, MA20/LOG, fullscreen) o
  // sürede ağaçtan düşüyordu. Artık eski seri yerinde kalır, sadece grafik
  // alanı "yükleniyor" hissi verir ve filtreler tıklanabilir kalır.
  Map<int, double>? _lastHistory;

  @override
  void initState() {
    super.initState();
    _selectedPeriodIdx = 0;
    _historyFuture = _loadHistory(_periods[0].days);
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
  }

  /// History fetch + son başarılı sonucu sakla.
  Future<Map<int, double>> _loadHistory(int days) {
    return HistoryService.instance
        .getPortfolioHistory([widget.asset], days)
      ..then((v) {
        if (mounted && v.isNotEmpty) _lastHistory = v;
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPeriod(int idx) {
    setState(() {
      _selectedPeriodIdx = idx;
      _historyFuture = _loadHistory(_periods[idx].days);
      // Compare aktifse aynı yeni periyot için compare history'yi de yenile.
      if (_compareAsset != null) {
        _compareHistoryFuture = HistoryService.instance
            .getPortfolioHistory([_compareAsset!], _periods[idx].days);
      }
    });
  }

  void _openComparePicker() {
    final pState = ref.read(portfolioProvider).valueOrNull;
    final all = pState?.assets ?? const <Asset>[];
    // Aynı ticker hariç — kendisiyle karşılaştırma yok. Aynı ticker'ın
    // birden fazla lot'u olabilir (birden çok alım); ticker bazlı dedup.
    final seen = <String>{};
    final choices = <Asset>[];
    for (final a in all) {
      if (a.ticker == widget.asset.ticker) continue;
      if (!seen.add(a.ticker)) continue;
      choices.add(a);
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.c.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return _ComparePickerSheet(
          choices: choices,
          currentSelectionTicker: _compareAsset?.ticker,
          onSelected: (choice) {
            final vAsset = choice?.toVirtualAsset();
            setState(() {
              _compareAsset = vAsset;
              _compareHistoryFuture = vAsset == null
                  ? null
                  : HistoryService.instance.getPortfolioHistory(
                      [vAsset], _periods[_selectedPeriodIdx].days);
            });
            Navigator.pop(sheetCtx);
          },
        );
      },
    );
  }


  void _confirmDelete(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(SandikRadius.lg)),
        title: const Text('Varlığı Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${widget.asset.name}" kalıcı olarak silinsin mi?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.c.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color:
                        context.c.danger.withValues(alpha: 0.25)),
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
                backgroundColor: context.c.danger,
                foregroundColor: context.c.onStatus),
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
            child: const Text('Yine de sil'),
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
    final activeSpots = <FlSpot>[];
    bool firstActiveReplaced = false;

    // Passive segment (alış öncesi dashed çizgi) kaldırıldı — portfolio
    // performance ekranıyla görsel bütünlük için. Grafik sadece alış → şimdi
    // aralığını gösterir; kullanıcı "elimde olmadığı dönemin" fiyatını
    // aramaz, bu aralık zaten periyot seçimi ile ayarlanır.
    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      // Saatlik veride (haftalık) her saat farklı X'e düşmeli — inDays saati
      // keser ve tüm saatler aynı X'e sıkışırdı, grafik dikey zigzag olurdu.
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      final y = history[ts]! / divisor;

      if (!firstActiveReplaced && anchorUnitPrice > 0) {
        // Aktif segmentin İLK noktası her zaman anchor (ort. maliyet).
        activeSpots.add(FlSpot(x, anchorUnitPrice));
        firstActiveReplaced = true;
      } else {
        activeSpots.add(FlSpot(x, y));
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
            DateTime.now().difference(startDate).inMinutes / (60.0 * 24.0);
        // Aynı gün ise minik bir ε ekle ki iki nokta farklı X'te olsun.
        final endX = todayX > anchorX ? todayX : anchorX + 0.01;
        activeSpots.add(FlSpot(endX, currentUnitPriceOverride));
      }
    }

    if (activeSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: activeSpots,
        lineColor: Sandik
            .amber, // Use Amber for active tracking to match design system focus
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5, // Thicker active line
      ));
    }

    return segments;
  }


  Widget _buildPeriodToggle() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
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
                duration: SandikMotion.of(context, const Duration(milliseconds: 200)),
                curve: SandikMotion.enter,
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? context.c.gold
                          : context.c.text36,
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
    // Kesirli gün — saatlik veride son X gün sınırında değil, gerçek
    // anlarında olmalı. Yoksa nokta grafiğin ortasında yalnız kalır.
    final maxX = endDate.difference(startDate).inMinutes / (60.0 * 24.0);

    // Logic moved inside FutureBuilder

    final activePartners = ref.watch(activePartnersProvider);
    final allPartnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;
    final isOwnAsset = currentUserId != null && widget.asset.userId == currentUserId;

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: context.c.text90),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Performans: ${widget.asset.name}',
          style: context.t.headlineSmall?.copyWith(color: context.c.text90),
          // Varlık adı kullanıcı girdisidir ve uzun olabilir ("Yapı Kredi
          // Koray Gayrimenkul Yatırım Ortaklığı"). AppBar başlığı tek
          // satırdır; koruma olmadan taşma çizgileri çıkar.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isOwnAsset && !widget.showBackButton)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: context.c.text90),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SandikRadius.md)),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: context.c.danger, size: 20),
                      const SizedBox(width: 10),
                      Text('Sil',
                          style: TextStyle(color: context.c.danger)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
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
                    final waiting =
                        snapshot.connectionState == ConnectionState.waiting;
                    // Periyot değişiminde eski seriye düş — böylece bu
                    // FutureBuilder'ın altındaki compare/MA20/LOG kontrolleri
                    // ve özet şeritleri ağaçta kalır. Hiç veri yoksa (ilk
                    // açılış) yalnızca grafik alanı spinner gösterir.
                    // Bayat seri ÖNCEKİ periyoda ait. Yeni periyot daha darsa
                    // aralık dışı noktalar negatif X'e düşüp ekseni kaydırırdı
                    // — bu yüzden seçili pencereye kırpılır.
                    Map<int, double>? fallback;
                    if (snapshot.data == null && _lastHistory != null) {
                      final fromMs = startDate.millisecondsSinceEpoch;
                      final toMs = endDate.millisecondsSinceEpoch;
                      final clipped = <int, double>{
                        for (final e in _lastHistory!.entries)
                          if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
                      };
                      if (clipped.length >= 2) fallback = clipped;
                    }
                    final data = snapshot.data ?? fallback;
                    final isStale = snapshot.data == null && data != null;
                    if (data == null) {
                      return const SizedBox(
                          height: 400,
                          child: CustomLoadingView());
                    }

                    final historyMap = data;

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

                    // Compare mode devrede mi? Öncelikli — log-scale ile
                    // aynı anda anlamlı değil (biri % biri log), compare
                    // aktifken log ignore edilir.
                    final compareOn = _compareAsset != null;
                    final logOnPref = ref.watch(chartLogScaleProvider);
                    final logOn = compareOn ? false : logOnPref;

                    final rawSegments = _convertHistoryToSegments(
                        historyMap, startDate, endDate,
                        currentUnitPriceOverride: currentUnitTRY);

                    // Normalize base: aktif segmentin ilk noktası. Bunun
                    // altında ana varlığın Y'leri (y / base) * 100 → % olur.
                    final rawActiveForBase = rawSegments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final normBase = rawActiveForBase.spots.isNotEmpty
                        ? rawActiveForBase.spots.first.y
                        : 1.0;

                    // Y ekseni transform: compare → % normalize; log → log10;
                    // default → identity. `fromY` label/tooltip'te ters
                    // çeviren fonksiyon (compare'de gösterim değişik: "+%12.4"
                    // formatı için ayrıca handle edilir).
                    double toY(double y) {
                      if (compareOn) return (y / (normBase.abs() < 1e-9 ? 1 : normBase)) * 100.0;
                      if (logOn) return math.log(y < 1e-6 ? 1e-6 : y) / math.ln10;
                      return y;
                    }
                    double fromY(double v) {
                      if (compareOn) return v; // % zaten, ters çevirme yok
                      if (logOn) return math.pow(10, v).toDouble();
                      return v;
                    }

                    final segments = (compareOn || logOn)
                        ? rawSegments
                            .map((s) => TransactionSegment(
                                  spots: s.spots
                                      .map((sp) =>
                                          FlSpot(sp.x, toY(sp.y)))
                                      .toList(),
                                  lineColor: s.lineColor,
                                  areaGradientStart: s.areaGradientStart,
                                  areaGradientEnd: s.areaGradientEnd,
                                  thickness: s.thickness,
                                  dashed: s.dashed,
                                ))
                            .toList()
                        : rawSegments;

                    // Aktif segmenti bul (kesikli olmayan, yani alım sonrası)
                    final activeSeg = segments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final anchorSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.first : null;
                    final lastSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.last : null;

                    // Compare mode: ikinci varlığın history'sini alt bir
                    // FutureBuilder ile fetch ediyoruz. Veri hazır olunca
                    // ilk noktası 100 kabul edilip (val/first)*100 normalize.

                    // MA20 overlay: aktif segmentin fiyat serisi üzerinden
                    // hesaplanır. İlk 19 nokta NaN olur (yetersiz veri) →
                    // atlanır. Kullanıcı chip ile açıp kapatır.
                    final ma20On = ref.watch(chartMA20Provider);
                    List<FlSpot>? ma20Spots;
                    if (ma20On && activeSeg.spots.length >= 20) {
                      // MA20 her zaman ham fiyat serisinden hesaplanır;
                      // sonra grafiğe koyulurken log domain'e alınır.
                      final rawActive = rawSegments.firstWhere(
                        (s) => !s.dashed && s.spots.isNotEmpty,
                        orElse: () => TransactionSegment(
                          spots: const [],
                          lineColor: context.c.amberText,
                          areaGradientStart: Colors.transparent,
                          areaGradientEnd: Colors.transparent,
                          thickness: 3.5,
                        ),
                      );
                      final prices =
                          rawActive.spots.map((s) => s.y).toList();
                      final sma = TechnicalAnalysisService.smaSeries(
                          prices, 20);
                      ma20Spots = <FlSpot>[];
                      for (int i = 0; i < sma.length; i++) {
                        if (sma[i].isNaN) continue;
                        ma20Spots
                            .add(FlSpot(rawActive.spots[i].x, toY(sma[i])));
                      }
                    }
                    // Seçili periyodun değişimi — HAM fiyat serisinden.
                    // activeSeg normalize/log dönüşümü almış olabilir; oradan
                    // okumak yüzdeyi bozar. rawSegments her zaman TRY birim
                    // fiyattır.
                    final rawActiveSeg = rawSegments.firstWhere(
                      (s) => !s.dashed && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    double? periodChangeTRY;
                    double? periodChangePct;
                    if (rawActiveSeg.spots.length >= 2) {
                      final f = rawActiveSeg.spots.first.y;
                      final l = rawActiveSeg.spots.last.y;
                      // Birim fiyat farkı × elde tutulan miktar = dönem etkisi.
                      periodChangeTRY = (l - f) * qty;
                      if (f > 0) periodChangePct = ((l - f) / f) * 100;
                    }

                    final anchorY = anchorSpot?.y ?? 0.0;
                    final totalCostTRY = asset.totalCostTRY;
                    final totalPnlTRY = currentValueTRY - totalCostTRY;
                    final pnlPct = totalCostTRY > 0
                        ? (totalPnlTRY / totalCostTRY) * 100
                        : 0.0;
                    final gainPositive = totalPnlTRY >= 0;
                    final endpointColor =
                        gainPositive ? context.c.gain : context.c.loss;

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

                    // Y sınırlarını görünür X aralığındaki spot'lara göre
                    // hesaplayan closure — zoom sırasında yeniden çağrılır.
                    ({double minY, double maxY}) computeY(
                        double viewMinX, double viewMaxX,
                        {List<FlSpot>? extraSpots}) {
                      double minY = double.infinity;
                      double maxY = -double.infinity;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      // Compare barı da Y aralığına dahil edilsin ki
                      // 2. varlığın çizgisi grafik dışına düşmesin.
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      if (minY == double.infinity) minY = 0;
                      if (maxY == -double.infinity) maxY = 1000;

                      // Compare modda anchor 100 (normalize base). Aksi
                      // halde anchorY (ham ilk noktanın normalize hali).
                      final center = compareOn
                          ? 100.0
                          : (anchorY > 0 ? anchorY : (minY + maxY) / 2);
                      double maxAbsDev = 0;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      final minDev =
                          (center * 0.01).clamp(1.0, double.infinity);
                      final halfRange =
                          maxAbsDev < minDev ? minDev : maxAbsDev;
                      final yPad = halfRange * 0.35;
                      final rawMaxY = center + halfRange + yPad;
                      // Compare modda negatif % olabilir (varlık düşmüş) —
                      // 0'a clamp'lemeyelim; ham hesabı bırak.
                      final rawMinY = compareOn
                          ? (center - halfRange - yPad)
                          : (center - halfRange - yPad)
                              .clamp(0, double.infinity)
                              .toDouble();
                      // TradingView tarzı nice-round Y bound: label'lar temiz
                      // yuvarlak sayılar olsun ve grid çizgilerine denk gelsin.
                      final rawInterval = (rawMaxY - rawMinY) / 4;
                      if (rawInterval <= 0) {
                        return (
                          minY: rawMinY.toDouble(),
                          maxY: rawMaxY.toDouble()
                        );
                      }
                      final niceInterval = _niceRound(rawInterval);
                      final niceMin = compareOn
                          ? (rawMinY / niceInterval).floor() * niceInterval
                          : ((rawMinY / niceInterval).floor() *
                                  niceInterval)
                              .clamp(0.0, double.infinity);
                      final niceMax =
                          (rawMaxY / niceInterval).ceil() * niceInterval;
                      return (
                        minY: niceMin.toDouble(),
                        maxY: niceMax.toDouble()
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Yeni periyot yüklenirken ince bar — eski grafik
                        // ekranda kalır, kontroller tıklanabilir.
                        if (waiting)
                          SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: context.c.amberFill,
                            ),
                          ),
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
                          const SizedBox(height: SandikSpace.sm),
                        // Seçili periyodun değişimi — üstteki strip alış→bugün
                        // toplam PnL'i gösterir, bu satır "bu dönemde ne oldu"
                        // sorusunu yanıtlar. İkisi farklı sorular.
                        // Bayat seride GİZLENİR: rakam hâlâ eski periyoda ait
                        // olurdu ama etiket yeni periyodu yazardı — yanıltıcı.
                        // (Üstteki strip periyottan bağımsız, o kalır.)
                        if (periodChangeTRY != null && !isStale)
                          _PeriodChangeRow(
                            label: _periods[_selectedPeriodIdx].label,
                            changeTRY: periodChangeTRY,
                            changePct: periodChangePct,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: 12),
                        // Grafik overlay chip'leri (MA20 vb.). Basit toggle.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _OverlayChip(
                              label: 'MA20',
                              active: ma20On,
                              onTap: () {
                                ref
                                    .read(chartMA20Provider.notifier)
                                    .set(!ma20On);
                              },
                            ),
                            const SizedBox(width: 6),
                            _OverlayChip(
                              label: 'LOG',
                              active: logOn,
                              onTap: () {
                                ref
                                    .read(chartLogScaleProvider.notifier)
                                    .set(!logOn);
                              },
                            ),
                            const SizedBox(width: 6),
                            _FullscreenChip(
                              onTap: () {
                                FullscreenChartRoute.open(
                                  context,
                                  title: widget.asset.name,
                                  builder: (_) => PerformanceScreen(
                                    asset: widget.asset,
                                    lots: widget.lots,
                                    showBackButton: false,
                                    // Landscape'te grafiği hemen üste getir;
                                    // header/tab/chip'ler yukarı swipe ile.
                                    initialScrollOffset: 240,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _CompareStrip(
                          primaryTicker: widget.asset.ticker,
                          compare: _compareAsset,
                          onAddPressed: _openComparePicker,
                          onClearPressed: () {
                            setState(() {
                              _compareAsset = null;
                              _compareHistoryFuture = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<Map<int, double>>(
                          future: _compareHistoryFuture,
                          builder: (context, compareSnap) {
                            // Compare barı — snapshot hazır olduğunda
                            // normalize edilip LineChartBarData olur.
                            LineChartBarData? compareBar;
                            if (compareOn &&
                                compareSnap.hasData &&
                                compareSnap.data!.isNotEmpty) {
                              final entries = compareSnap.data!.entries
                                  .toList()
                                ..sort((a, b) => a.key.compareTo(b.key));
                              final firstY = entries.first.value;
                              if (firstY.abs() > 1e-9) {
                                final spots = <FlSpot>[];
                                for (final e in entries) {
                                  final ts = e.key;
                                  final date = DateTime
                                      .fromMillisecondsSinceEpoch(ts);
                                  final x = date
                                          .difference(startDate)
                                          .inMinutes /
                                      (60.0 * 24.0);
                                  if (x < 0) continue;
                                  spots.add(FlSpot(
                                      x, (e.value / firstY) * 100.0));
                                }
                                if (spots.length >= 2) {
                                  compareBar = LineChartBarData(
                                    spots: spots,
                                    isCurved: false,
                                    color: _kCompareColor,
                                    barWidth: 1.6,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData:
                                        BarAreaData(show: false),
                                  );
                                }
                              }
                            }
                            // Bayat seri soluk çizilir — spinner yerine
                            // bağlam sunar, ama "bu henüz yeni periyodun
                            // verisi değil" hissini korur.
                            return AnimatedOpacity(
                              opacity: isStale ? 0.35 : 1.0,
                              duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
                              curve: SandikMotion.enter,
                              child: Container(
                          height: 400,
                          decoration: BoxDecoration(
                            color: context.c.surface1,
                            borderRadius: BorderRadius.circular(SandikRadius.md),
                            border: Border.all(
                                color: context.c.overlay),
                          ),
                          padding: const EdgeInsets.only(
                              top: 36, right: 16, left: 8, bottom: 16),
                          child: Builder(builder: (_) {
                            // Aktif segment (alış → bugün) tüm dönemin
                            // %25'inden azsa viewport'u aktif segmentin
                            // etrafına daralt — kullanıcı yıllık seçse
                            // bile 2 gün önce aldığı varlık için grafik
                            // dolgun görünsün, dikey çubuk gibi değil.
                            // Sağa daha fazla pay (~%8) → son nokta ve
                            // "ŞİMDİ" etiketi x-tick'lerle çakışmasın.
                            double focusMin = -maxX * 0.03;
                            double focusMax = maxX * 1.08;
                            if (anchorSpot != null && lastSpot != null) {
                              final firstX = anchorSpot.x;
                              final lastX = lastSpot.x;
                              final activeSpan = lastX - firstX;
                              if (activeSpan < maxX * 0.25) {
                                final pad = activeSpan < 1.0
                                    ? 1.0
                                    : activeSpan * 0.8;
                                focusMin = (firstX - pad).clamp(-maxX * 0.03, maxX);
                                // Sağa fazladan %25 pay → son nokta
                                // grafiğin sağ kenarında değil, biraz
                                // içeride kalsın ki "şimdi" etiketi ve
                                // dot rahat okunsun.
                                focusMax = (lastX + pad * 1.25)
                                    .clamp(focusMin + 0.5, maxX * 1.08);
                              }
                            }
                            // Seyreltme adayları viewport'a bağlı DEĞİL —
                            // yalnızca segment'lere ve lot günlerine bağlı.
                            // Builder içinde bırakılırsa her pinch/pan
                            // karesinde expand+map+where zinciri baştan
                            // kurulurdu. Bir kez hesapla.
                            final dotCandidates = segments
                                .expand((s) => s.spots)
                                .map((sp) => sp.x)
                                .where((x) =>
                                    lotDayIsSell.containsKey(x.toInt()))
                                .toList(growable: false);
                            return ZoomableChart(
                            fullMinX: focusMin,
                            fullMaxX: focusMax,
                            height: 400 - 36 - 16,
                            plotPaddingRight: 60,
                            builder: (viewMinX, viewMaxX) {
                              final yBounds = computeY(
                                viewMinX,
                                viewMaxX,
                                extraSpots: compareBar?.spots,
                              );
                              final viewMinY = yBounds.minY;
                              final viewMaxY = yBounds.maxY;
                              // Lot marker'ları piksel bazlı seyreltmeden
                              // geçer — arka arkaya alım yapılan günlerde
                              // dot'lar üst üste binip yığın gibi
                              // görünüyordu. Zoom'da viewport daralınca
                              // gizlenenler tek tek ortaya çıkar.
                              // Adaylar gerçek spot X'leridir: `spot.x`
                              // kesirli gün (dakika/1440), gün anahtarı ise
                              // `spot.x.toInt()`. Gün anahtarını doğrudan
                              // aday yaparsak hiçbir spot'a eşleşmez.
                              final dotThinner = DotThinner.build(
                                candidates: dotCandidates,
                                viewMinX: viewMinX,
                                viewMaxX: viewMaxX,
                                plotWidthPx: (MediaQuery.of(context)
                                            .size
                                            .width -
                                        60 -
                                        40)
                                    .clamp(120.0, 2000.0),
                                minSeparationPx: 16,
                                alwaysKeep: {
                                  if (anchorSpot != null) anchorSpot.x,
                                  if (lastSpot != null) lastSpot.x,
                                },
                              );
                              return LineChartData(
                          minX: viewMinX,
                          maxX: viewMaxX,
                          minY: viewMinY,
                          maxY: viewMaxY,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: (viewMaxY - viewMinY) > 0
                                ? _niceRound(
                                    (viewMaxY - viewMinY) / 4)
                                : 50000,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: context.c.overlay,
                              strokeWidth: 1,
                            ),
                          ),
                          // TradingView paritesi: plot area sağ kenarına
                          // ince Y-ekseni ayraç çizgisi — Y bandı görsel
                          // olarak plot area'dan ayrılsın.
                          borderData: FlBorderData(
                            show: true,
                            border: Border(
                              right: BorderSide(
                                color: context.c.overlay,
                                width: 1,
                              ),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            // Y ekseni SAĞDA (TradingView convention).
                            // leftTitles kapalı. rightTitles nice-round
                            // interval ile temiz sayılar (100K/200K/...).
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                interval: (viewMaxY - viewMinY) > 0
                                    ? _niceRound(
                                        (viewMaxY - viewMinY) / 4)
                                    : 50000,
                                getTitlesWidget: (value, meta) {
                                  if (value == meta.min ||
                                      value == meta.max) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = compareOn
                                      ? '${(value - 100).toStringAsFixed(1)}%'
                                      : fmtTRYCompact(fromY(value));
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.left,
                                      // Eksen etiketi — tabular figür, tik
                                      // değerleri değişince kaymasın.
                                      style: context.t.numSmall.copyWith(
                                        color: context.c.text58,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // X ekseni: dinamik format (span'a göre yıl/saat
                            // ekle), nice-round interval.
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: (viewMaxX - viewMinX) > 0
                                    ? _niceRound(
                                        (viewMaxX - viewMinX) / 5)
                                    : 1,
                                getTitlesWidget: (value, meta) {
                                  final span =
                                      (meta.max - meta.min).abs();
                                  // Etiket tick'in üzerinde ortalanır; kenara
                                  // çok yakın tick'in etiketi plot alanının
                                  // dışına taşar. Zoom'da interval sınırlara
                                  // denk gelmediği için min/max eşitliği
                                  // yetmiyor — %6 kenar payı bırak.
                                  final edge = span * 0.06;
                                  if (value <= meta.min + edge ||
                                      value >= meta.max - edge) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = startDate.add(Duration(
                                      minutes:
                                          (value * 60 * 24).round()));
                                  final showYearOnly = span > 400;
                                  final showTime = span < 3;
                                  final showYear = !showYearOnly &&
                                      date.year != DateTime.now().year;
                                  final label = showYearOnly
                                      ? DateFormat('MMM yy', 'tr_TR')
                                          .format(date)
                                      : showTime
                                          ? DateFormat('d MMM HH:mm',
                                                  'tr_TR')
                                              .format(date)
                                          : DateFormat(
                                                  showYear
                                                      ? 'd MMM yy'
                                                      : 'd MMM',
                                                  'tr_TR')
                                              .format(date);
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(top: 10),
                                    // Sabit genişlik + ortalama: taşan metin
                                    // ellipsis olur, komşu etiketle çakışmaz.
                                    child: SizedBox(
                                      width: 74,
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        // Eksen etiketi — tabular figür, tik
                                        // değerleri değişince kaymasın.
                                        style: context.t.numSmall.copyWith(
                                          color: context.c.text58,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
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
                                      color: context.c.text36,
                                      strokeWidth: 1,
                                      dashArray: const [4, 4],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        alignment: Alignment.topLeft,
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 2),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w800,
                                          color: context.c.text90
                                              .withValues(alpha: 0.75),
                                        ),
                                        labelResolver: (_) =>
                                            'ALIŞ  ${NumberFormat('#,##0.00', 'tr_TR').format(anchorY)} ₺',
                                      ),
                                    ),
                                  ],
                                  verticalLines: [
                                    // Başlangıç (alış) X'i — tarih etiketli
                                    // dashed vertical marker.
                                    VerticalLine(
                                      x: anchorSpot.x,
                                      color: context.c.amberText
                                          .withValues(alpha: 0.4),
                                      strokeWidth: 1.2,
                                      dashArray: const [4, 4],
                                      label: VerticalLineLabel(
                                        show: true,
                                        alignment: Alignment.topRight,
                                        padding: const EdgeInsets.only(
                                            bottom: 8, left: 6),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w700,
                                          color: context.c.amberText,
                                        ),
                                        labelResolver: (_) {
                                          final buyDate = startDate.add(
                                              Duration(
                                                  minutes:
                                                      (anchorSpot.x * 1440)
                                                          .round()));
                                          return 'ALIŞ ${DateFormat('d MMM', 'tr_TR').format(buyDate)}';
                                        },
                                      ),
                                    ),
                                    // Bitiş (bugün) X'i — "ŞİMDİ" etiketi
                                    // ile net görünsün.
                                    if (lastSpot != null)
                                      VerticalLine(
                                        x: lastSpot.x,
                                        color: endpointColor
                                            .withValues(alpha: 0.55),
                                        strokeWidth: 1.2,
                                        dashArray: const [4, 4],
                                        label: VerticalLineLabel(
                                          show: true,
                                          alignment: Alignment.topLeft,
                                          padding: const EdgeInsets.only(
                                              bottom: 8, right: 6),
                                          style: context.t.labelMedium?.copyWith(
                                            letterSpacing: 0,
                                            fontWeight: FontWeight.w700,
                                            color: endpointColor,
                                          ),
                                          labelResolver: (_) => 'ŞİMDİ',
                                        ),
                                      ),
                                  ],
                                )
                              : const ExtraLinesData(),
                          lineBarsData: <LineChartBarData>[
                            if (ma20Spots != null && ma20Spots.length >= 2)
                              LineChartBarData(
                                spots: ma20Spots,
                                isCurved: false,
                                color: context.c.text58,
                                barWidth: 1.4,
                                isStrokeCapRound: true,
                                dashArray: const [3, 3],
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            if (compareBar != null) compareBar,
                            ...segments
                              .map((seg) {
                                // Trading estetiği: dönem uzadıkça ince
                                // çizgi, kısa dönemde biraz belirgin.
                                final periodDays = _periods[_selectedPeriodIdx].days;
                                final baseWidth = periodDays <= 7
                                    ? 2.0
                                    : periodDays <= 30
                                        ? 2.4
                                        : periodDays <= 90
                                            ? 2.0
                                            : periodDays <= 180
                                                ? 1.8
                                                : 1.5;
                                final effective = seg.dashed ? seg.thickness : baseWidth;
                                return LineChartBarData(
                                    spots: seg.spots,
                                    isCurved: false,
                                    color: seg.lineColor,
                                    barWidth: effective,
                                    isStrokeCapRound: true,
                                    dashArray: seg.dashed ? const [4, 4] : null,
                                    dotData: FlDotData(
                                      show: !seg.dashed,
                                      checkToShowDot: (spot, barData) {
                                        if (seg.dashed) return false;
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
                                        if (!lotDayIsSell
                                            .containsKey(spot.x.toInt())) {
                                          return false;
                                        }
                                        return dotThinner.shows(spot.x);
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        // Alış: beyaz halkalı amber (ince).
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: context.c.amberText,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 2,
                                          );
                                        }
                                        // Son (şimdi): kar/zarar rengi.
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: endpointColor,
                                            strokeColor: context.c.text90
                                                .withValues(alpha: 0.85),
                                            strokeWidth: 1.5,
                                          );
                                        }
                                        // Ek alım / satış marker'ları
                                        final isSell =
                                            lotDayIsSell[spot.x.toInt()];
                                        if (isSell != null) {
                                          return FlDotCirclePainter(
                                            radius: 4.5,
                                            color: isSell
                                                ? context.c.loss
                                                : context.c.gain,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 2,
                                          );
                                        }
                                        return FlDotCirclePainter(
                                          radius: 3.0,
                                          color: context.c.amberText,
                                          strokeColor: context.c.background,
                                          strokeWidth: 1.5,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: seg.dashed
                                            ? [
                                                seg.areaGradientStart,
                                                seg.areaGradientEnd,
                                              ]
                                            : [
                                                context.c.amberText
                                                    .withValues(alpha: 0.22),
                                                context.c.amberText
                                                    .withValues(alpha: 0.06),
                                                Colors.transparent,
                                              ],
                                        stops: seg.dashed
                                            ? null
                                            : const [0.0, 0.5, 1.0],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  );
                              }),
                          ],
                          // Built-in tooltip kapalı — crosshair TEK KAYNAK.
                          // fl_chart tooltip'i ile ZoomableChart crosshair'ı
                          // paralel çalışınca X hesabı farklı olup değerler
                          // uyumsuz görünüyordu.
                          lineTouchData: LineTouchData(
                            enabled: false,
                            handleBuiltInTouches: false,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  context.c.surface1.withValues(alpha: 0.95),
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
                                  final tipText = compareOn
                                      ? '${(spot.y - 100).toStringAsFixed(2)}%'
                                      : '${valueFmt.format(fromY(spot.y))} ₺';
                                  return LineTooltipItem(
                                    tipText,
                                    context.t.numSmall.copyWith(
                                      color: context.c.text90,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '\n$dateLabel',
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          color: context.c.text58,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        );
                            },
                            crosshairSnapX: (x) {
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return x;
                              final clamped =
                                  x.clamp(spots.first.x, spots.last.x);
                              // Sıralı seri → ikili arama. Parmak her
                              // kaydığında çağrılıyor (bkz. nearestSpotIndex).
                              return spots[nearestSpotIndex(spots, clamped)].x;
                            },
                            crosshairLabelBuilder: (x) {
                              // x zaten snap edildi — spot'u bul.
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return null;
                              final snapped =
                                  spots[nearestSpotIndex(spots, x)];
                              final date = startDate.add(Duration(
                                  minutes:
                                      (snapped.x * 1440).round()));
                              final title = compareOn
                                  ? '${(snapped.y - 100).toStringAsFixed(2)}%'
                                  : NumberFormat.currency(
                                          locale: 'tr_TR',
                                          symbol: '₺',
                                          decimalDigits: 2)
                                      .format(fromY(snapped.y));
                              final subtitle = DateFormat(
                                      'd MMM yyyy', 'tr_TR')
                                  .format(date);
                              return (title, subtitle);
                            },
                          );
                          }),
                        ),
                            ); // AnimatedOpacity (bayat seri solukluğu)
                          },
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
                    color: context.c.overlay,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(color: context.c.hairline),
                  ),
                  // Etiket + değer yan yana; ikisi de sınırsızdı ve büyük
                  // miktarlarda satır taşıyordu (105px). Etiket kırpılabilir,
                  // değer ise FittedBox ile küçülerek sığar — rakam kırpmak
                  // yanlış okumaya yol açar.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'TOPLAM MİKTAR',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelLarge?.copyWith(
                              color: context.c.amberText,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${fmtNum(_currentQuantity, digits: 2)} ${widget.asset.unitType}',
                            maxLines: 1,
                            style: context.t.numLarge.copyWith(
                                color: context.c.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
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

/// Seçili periyodun değişimi — tek satır, üstteki [_PnlSummaryStrip]'in
/// altında durur.
///
/// İkisi farklı soruları yanıtlar ve bilerek ayrı tutulmuştur:
/// - [_PnlSummaryStrip]: "aldığımdan bugüne ne kazandım?" (toplam PnL)
/// - Bu satır: "seçtiğim dönemde ne oldu?" (dönemsel değişim)
///
/// Değişim ham fiyat farkıdır (son − ilk) × miktar. Grafikteki çizginin iki
/// ucuyla birebir tutarlıdır.
class _PeriodChangeRow extends StatelessWidget {
  final String label;
  final double changeTRY;
  final double? changePct;

  const _PeriodChangeRow({
    required this.label,
    required this.changeTRY,
    required this.changePct,
  });

  @override
  Widget build(BuildContext context) {
    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr — yeşil/kırmızı
    // göstermek "hareket var" yanılgısı yaratır.
    final isFlat =
        changeTRY.abs().round() == 0 && (changePct?.abs() ?? 0) < 0.005;
    final positive = changeTRY >= 0;
    final color =
        isFlat ? context.c.text36 : (positive ? context.c.gain : context.c.loss);
    final tryFmt = NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          // Etiket de kırpılabilmeli: dar ekranda tam genişliği alıp sağdaki
          // tutarı taşırıyordu (320pt'de 54px). Değer zaten Flexible.
          Flexible(
            child: Text(
              '$label DEĞİŞİM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.c.text36,
              ),
            ),
          ),
          const Spacer(),
          if (!isFlat) ...[
            Icon(
              positive
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                isFlat
                    ? 'Değişim yok'
                    : '${positive ? '+' : '−'}${tryFmt.format(changeTRY.abs())}',
                maxLines: 1,
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ),
          if (changePct != null && !isFlat) ...[
            const SizedBox(width: SandikSpace.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: SandikRadius.smAll,
              ),
              child: Text(
                fmtPct(changePct!.abs(), digits: 2),
                style: context.t.numSmall.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1000000) return '$sign${fmtNum(abs / 1000000, digits: 2)}M ₺';
    if (abs >= 1000) return '$sign${fmtNum(abs / 1000, digits: 1)}k ₺';
    return '$sign${fmtNum(abs, digits: 0)} ₺';
  }

  @override
  Widget build(BuildContext context) {
    // Değişim yoksa (yuvarlanmış tutar ve yüzde ikisi de sıfırsa) nötr göster.
    final bool isFlat =
        totalPnl.abs().round() == 0 && pnlPct.abs() < 0.005;
    final Color accent = isFlat
        ? context.c.text36
        : (isPositive ? context.c.gain : context.c.loss);
    final String sign = isPositive ? '+' : '−';
    final IconData arrow = isPositive
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
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
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(anchorUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          color: context.c.text58)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded,
                size: 14, color: context.c.text36),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUGÜN / $unitLabel',
                    style: context.t.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.c.text36)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_fmtPrice(currentUnitPrice),
                      maxLines: 1,
                      style: context.t.numSmall.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.c.text90)),
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
                color: context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border:
                    Border.all(color: context.c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.horizontal_rule_rounded,
                      size: 14, color: context.c.text58),
                  const SizedBox(width: 4),
                  Text('Değişim yok',
                      style: context.t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text58)),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(SandikRadius.md),
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
                          style: context.t.numSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(
                          '$sign${_fmtPrice((currentUnitPrice - anchorUnitPrice).abs())} / $unitLabel',
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.85),
                              height: 1.2)),
                      const SizedBox(height: 1),
                      Text(fmtPct(pnlPct.abs(), digits: 2),
                          style: context.t.numSmall.copyWith(
                              fontSize: 10,
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

/// Fullscreen landscape moduna geçiren küçük ikon buton.
class _FullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _FullscreenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: context.c.overlay,
            ),
          ),
          child: Icon(
            Icons.fullscreen_rounded,
            size: 16,
            color: context.c.text58,
          ),
        ),
      ),
    );
  }
}

/// Grafik üzerine çizilen göstergeleri açıp kapatan küçük toggle chip.
class _OverlayChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OverlayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: AnimatedContainer(
          duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
          curve: SandikMotion.enter,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? context.c.amberFill.withValues(alpha: 0.18)
                : context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: active
                  ? context.c.amberFill.withValues(alpha: 0.55)
                  : context.c.overlay,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.check_rounded
                    : Icons.horizontal_rule_rounded,
                size: 12,
                color: active ? context.c.amberText : context.c.text58,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? context.c.amberText : context.c.text58,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Compare mode UI ─────────────────────────────────────────────────────────

/// Grafik container'ının üstünde: legend (rozet) + "Karşılaştır" ekle butonu.
/// Compare seçili değilse sadece + butonu görünür; seçiliyken rozet ve ✕.
class _CompareStrip extends StatelessWidget {
  final String primaryTicker;
  final Asset? compare;
  final VoidCallback onAddPressed;
  final VoidCallback onClearPressed;

  const _CompareStrip({
    required this.primaryTicker,
    required this.compare,
    required this.onAddPressed,
    required this.onClearPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Rozetler + "ekle" düğmesi sabit genişlikte değil: uzun ticker'lar
    // (TEFAS:YKT gibi) veya karşılaştırma rozeti eklenince satır taşıyordu
    // (15px). Yatay kaydırma, rozetleri kırpmadan sığdırır — hiçbir bilgi
    // gizlenmez, yalnızca gerekirse kaydırılır.
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          // Ana varlık rozeti — renk = context.c.amberText
          _LegendBadge(
            color: context.c.amberText,
            label: primaryTicker,
          ),
          const SizedBox(width: 8),
          if (compare != null) ...[
            _LegendBadge(
              color: _kCompareColor,
              label: compare!.ticker,
              onRemove: onClearPressed,
            ),
            const SizedBox(width: 8),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAddPressed,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SandikRadius.md),
                  border: Border.all(
                    color: context.c.overlay,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      compare == null
                          ? Icons.add_rounded
                          : Icons.swap_horiz_rounded,
                      size: 14,
                      color: context.c.text58,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compare == null ? 'Karşılaştır' : 'Değiştir',
                      style: context.t.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.text58,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBadge extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback? onRemove;
  const _LegendBadge({
    required this.color,
    required this.label,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: onRemove == null ? 10 : 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close_rounded, size: 12, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compare picker satır kaynağı — hem portföydeki varlık hem de
/// katalog (BIST100 / döviz / altın) aynı yapıyla temsil edilir.
class _CompareChoice {
  final String ticker;
  final String name;
  final AssetType type;
  final String currency;
  final String source; // 'portfolio' | 'bist' | 'fx' | 'gold'

  const _CompareChoice({
    required this.ticker,
    required this.name,
    required this.type,
    required this.currency,
    required this.source,
  });

  /// HistoryService'in beklediği minimum alanları sağlayan sanal Asset.
  /// Grafik için sadece ticker/type/currency kullanılıyor.
  /// addedDate çok geriye ayarlanır — HistoryService `addedTs > dayTs` ise
  /// quantity=0 döndürüyor, bu compare için tüm dönemde quantity=1 olsun.
  Asset toVirtualAsset() {
    return Asset(
      id: 'compare-$ticker',
      userId: '',
      name: name,
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 1,
      currency: currency,
      notes: '',
      addedDate: DateTime(2000, 1, 1),
    );
  }
}

/// Katalog seçenekleri — kullanıcının portföyde tutmadığı varlıklarla
/// da karşılaştırma yapabilsin diye statik olarak sağlanır.
List<_CompareChoice> _catalogChoices() {
  final out = <_CompareChoice>[];
  // BIST100 hisseleri
  bist100StocksMap.forEach((ticker, name) {
    out.add(_CompareChoice(
      ticker: ticker,
      name: name,
      type: AssetType.hisse,
      currency: 'TRY',
      source: 'bist',
    ));
  });
  // Major dövizler
  out.addAll(const [
    _CompareChoice(
        ticker: 'USDTRY=X',
        name: 'ABD Doları',
        type: AssetType.doviz,
        currency: 'USD',
        source: 'fx'),
    _CompareChoice(
        ticker: 'EURTRY=X',
        name: 'Euro',
        type: AssetType.doviz,
        currency: 'EUR',
        source: 'fx'),
    _CompareChoice(
        ticker: 'GBPTRY=X',
        name: 'İngiliz Sterlini',
        type: AssetType.doviz,
        currency: 'GBP',
        source: 'fx'),
  ]);
  // Altın (gram karşılığı, HistoryService altın için USD/gr → TRY dönüşümü yapar)
  out.add(const _CompareChoice(
    ticker: 'XAU',
    name: 'Altın (Gram)',
    type: AssetType.altin,
    currency: 'USD',
    source: 'gold',
  ));
  return out;
}

/// Compare için varlık seçim sheet — iki sekme: Portföyüm + Diğer.
/// Arama kutusu aktif sekmede filtreler.
class _ComparePickerSheet extends StatefulWidget {
  final List<Asset> choices; // portföy varlıkları
  final String? currentSelectionTicker;
  final void Function(_CompareChoice?) onSelected;

  const _ComparePickerSheet({
    required this.choices,
    required this.currentSelectionTicker,
    required this.onSelected,
  });

  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late TabController _tabController;
  late List<_CompareChoice> _catalog = _catalogChoices();
  late final List<_CompareChoice> _portfolio = widget.choices
      .map((a) => _CompareChoice(
            ticker: a.ticker,
            name: a.name,
            type: a.type,
            currency: a.currency,
            source: 'portfolio',
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _appendTefas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// TEFAS fonlarını katalog listesine ekle. Uygulama açılışında disk
  /// cache'ten hazır geldiği için pratikte anında döner; spinner gösterme.
  Future<void> _appendTefas() async {
    try {
      final funds = await TefasService.instance.fetchAllFunds();
      if (!mounted || funds.isEmpty) return;
      final extra = funds.map((f) => _CompareChoice(
            ticker: 'TEFAS:${f.code}',
            name: f.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ));
      setState(() {
        _catalog = [..._catalog, ...extra];
      });
    } catch (_) {
      // Cache yoksa TEFAS sekmesi olmadan devam et.
    }
  }

  // TEFAS liste API'sinde olmayan (kurucu-only) fonlar için tek-fon
  // lookup — kullanıcı ALE / YLB gibi bir kod yazınca arka planda çağrılır.
  final Set<String> _lookupInFlight = {};
  final Set<String> _lookupTried = {};

  Future<void> _tryLookupTefas(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length < 3 || code.length > 6) return;
    if (_lookupTried.contains(code)) return;
    if (_lookupInFlight.contains(code)) return;
    if (_catalog.any((c) => c.ticker == 'TEFAS:$code')) return;
    _lookupInFlight.add(code);
    try {
      final fund = await TefasService.instance.lookupFund(code);
      _lookupTried.add(code);
      if (!mounted || fund == null) return;
      setState(() {
        _catalog = [
          ..._catalog,
          _CompareChoice(
            ticker: 'TEFAS:${fund.code}',
            name: fund.name,
            type: AssetType.fon,
            currency: 'TRY',
            source: 'tefas',
          ),
        ];
      });
    } catch (_) {
      _lookupTried.add(code); // spam engelle
    } finally {
      _lookupInFlight.remove(code);
    }
  }

  List<_CompareChoice> _filter(List<_CompareChoice> src) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((c) {
      return c.ticker.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();
  }

  Widget _list(List<_CompareChoice> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sonuç yok.',
          style: context.t.bodyMedium?.copyWith(color: context.c.text58),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final selected = widget.currentSelectionTicker == c.ticker;
        return ListTile(
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c.type.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            c.ticker,
            style: context.t.titleMedium?.copyWith(
              color: context.c.text90,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
          trailing: selected
              ? Icon(Icons.check_rounded, color: context.c.amberText)
              : null,
          onTap: () => widget.onSelected(c),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.overlay,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Karşılaştır',
                      style: context.t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.c.text90,
                      ),
                    ),
                    const Spacer(),
                    if (widget.currentSelectionTicker != null)
                      TextButton(
                        onPressed: () => widget.onSelected(null),
                        child: const Text('Temizle'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  style: TextStyle(color: context.c.text90),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.c.text58),
                    hintText: 'Ticker veya isim ara…',
                    hintStyle:
                        TextStyle(color: context.c.text36, fontSize: 13),
                    filled: true,
                    fillColor: context.c.overlay,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _query = v);
                    // Kurucu-only TEFAS fonları (ör. ALE, YLB) fetchAllFunds
                    // içinde yok — kullanıcı kısa bir kod yazınca arka
                    // planda lookup yap, bulunursa katalog liste güncellenir.
                    _tryLookupTefas(v);
                  },
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: context.c.amberText,
                labelColor: context.c.amberText,
                unselectedLabelColor: context.c.text58,
                labelStyle: context.t.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Portföyüm'),
                  Tab(text: 'Diğer'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _list(_filter(_portfolio)),
                    _list(_filter(_catalog)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Color _kCompareColor = Sandik.info;

