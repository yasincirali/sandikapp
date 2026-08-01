import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, CircularProgressIndicator, LinearProgressIndicator, Icons, TextStyle, Material, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../models/technical_signal.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/technical_analysis_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../services/history_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/zoomable_chart.dart';
import '../widgets/fullscreen_chart_route.dart';
import '../providers/preferences_provider.dart' show leaderboardOptInProvider;
import 'leaderboard_screen.dart';
import '../widgets/zoom_data_controller.dart';

class PortfolioPerformanceScreen extends ConsumerStatefulWidget {
  final String? initialView;
  final AssetType? initialTypeFilter;

  final double initialScrollOffset;

  const PortfolioPerformanceScreen({
    super.key,
    this.initialView = '',
    this.initialTypeFilter,
    this.initialScrollOffset = 0,
  });

  @override
  ConsumerState<PortfolioPerformanceScreen> createState() =>
      _PortfolioPerformanceScreenState();
}

class _PortfolioPerformanceScreenState
    extends ConsumerState<PortfolioPerformanceScreen> {
  int _selectedPeriodIdx = 0; // Günlük (intraday)
  late String? _view;
  late AssetType? _typeFilter;
  // Grafik modu: false = gerçek geçmiş (alım/satışlara göre),
  //             true  = simülasyon (bugünkü net pozisyon tüm dönem boyunca).
  bool _simulate = false;
  // Intraday sekmesi seçiliyken şimdiki zaman marker'ının X ekseni üstünde
  // ilerlemesi için periyodik tick. Her 60 sn'de bir setState çağırıyor.
  Timer? _intradayTick;

  // Zoom-aware veri controller'ı. Chart viewport değiştikçe uygun
  // ResolutionTier'da veri yükler, debounce ile spam engeller.
  ZoomDataController? _zoomController;
  // Controller'ın hangi (view, tip, periyot, simülasyon, asset-hash) için
  // kurulduğunu takip et — bunlar değişince yeni controller kurulur.
  String? _zoomKey;

  // Ana grafik + volume subchart aynı X viewport'unu paylaşsın diye
  // ortak controller. Grafiğin fullMinX/fullMaxX'i period değiştikçe
  // güncellenir; ZoomableChart & ZoomableBarChart bunu dinler.
  ChartViewport? _viewport;
  String? _viewportKey;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _typeFilter = widget.initialTypeFilter;
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
    _startIntradayTickIfNeeded();
  }

  @override
  void dispose() {
    _intradayTick?.cancel();
    _zoomController?.dispose();
    _viewport?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Grafik viewport'unu period/asset key değişince yenile.
  /// Aynı key + aynı minX/maxX → controller aynı kalır (kullanıcı zoom'unu
  /// kaybetmez). fullRange değiştiyse controller'ı reset et.
  ChartViewport _ensureViewport({
    required String key,
    required double fullMinX,
    required double fullMaxX,
  }) {
    if (_viewportKey != key || _viewport == null) {
      _viewport?.dispose();
      _viewport = ChartViewport(fullMinX: fullMinX, fullMaxX: fullMaxX);
      _viewportKey = key;
    } else if (_viewport!.fullMinX != fullMinX ||
        _viewport!.fullMaxX != fullMaxX) {
      _viewport!.updateFullRange(fullMinX, fullMaxX);
    }
    return _viewport!;
  }

  /// Chart assets/period/simülasyon değiştiğinde controller'ı yeniden kur.
  /// Aynı key gelirse mevcut controller korunur — kullanıcı zoom yaptığı
  /// yerden çalışmaya devam eder.
  void _ensureController({
    required List<Asset> chartAssets,
    required DateTime from,
    required DateTime to,
    required bool intraday,
  }) {
    final key = '${_view ?? "all"}|${_typeFilter?.name ?? "*"}'
        '|$_selectedPeriodIdx|$_simulate|${chartAssets.length}'
        '|${chartAssets.map((a) => a.id).join(",")}';
    if (_zoomKey == key && _zoomController != null) return;
    _zoomController?.dispose();
    _zoomKey = key;
    _zoomController = ZoomDataController(
      assets: chartAssets,
      initialFrom: from,
      initialTo: to,
      simulate: _simulate,
    );
  }

  void _startIntradayTickIfNeeded() {
    _intradayTick?.cancel();
    if (_periods[_selectedPeriodIdx].intraday) {
      // 30 sn'de bir canlı fiyat çek — son noktanın Y değeri anlık portföy
      // toplamına oturur. refreshPrices bir sonraki portfolio state'ini
      // provider üzerinden yayar, ekran otomatik yeniden build olur.
      _intradayTick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        ref.read(portfolioProvider.notifier).refreshPrices();
        setState(() {}); // marker'ın X'ini şu anki dakikaya kaydır
      });
    }
  }

  // days=0 && intraday=true → günlük (24 saat, 5 dk çözünürlük).
  static const List<({String label, int days, bool intraday})> _periods = [
    (label: 'GÜNLÜK', days: 0, intraday: true),
    (label: '1H', days: 7, intraday: false),
    (label: '1A', days: 30, intraday: false),
    (label: '6A', days: 180, intraday: false),
    (label: '1Y', days: 365, intraday: false),
  ];

  // ── Logic ──────────────────────────────────────────────────────────────────

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    List<Asset> allAssets,
    DateTime startDate,
    DateTime endDate, {
    double? currentTotalOverride,
    bool simulate = false,
    bool intraday = false,
  }) {
    if (history.isEmpty || allAssets.isEmpty) return [];

    // Intraday (günlük): X ekseni = 00:00'dan itibaren dakika. Aktif segment
    // tek parça — bugünün başından şu ana kadar tüm noktalar aynı sarı çizgi
    // üstünde gider. Şimdi'den sonraki (gelecek) slotları göstermeyiz.
    if (intraday) {
      final sortedTs = history.keys.toList()..sort();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final spots = <FlSpot>[];
      double? lastNonZero;
      for (final ts in sortedTs) {
        if (ts > nowMs) break;
        final y = history[ts] ?? 0;
        // 0 dönen slotlar (borsa saatleri dışı ilk slotlar) atlanır; kullanıcı
        // ilk fiyat oluşan noktadan itibaren çizgiyi görür.
        if (y <= 0) continue;
        lastNonZero = y;
        final minutes =
            (ts - startDate.millisecondsSinceEpoch) / 60000.0;
        spots.add(FlSpot(minutes, y));
      }
      // Şu an'ı canlı toplamla sabitle — grafiğin son noktası her zaman
      // "şu andaki portföy değeri" olur.
      if (currentTotalOverride != null && currentTotalOverride > 0) {
        final nowMinutes =
            (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
        if (spots.isNotEmpty && (nowMinutes - spots.last.x).abs() < 5) {
          spots[spots.length - 1] = FlSpot(nowMinutes, currentTotalOverride);
        } else {
          spots.add(FlSpot(nowMinutes, currentTotalOverride));
        }
      } else if (lastNonZero != null && spots.isNotEmpty) {
        final nowMinutes =
            (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
        if ((nowMinutes - spots.last.x).abs() >= 5) {
          spots.add(FlSpot(nowMinutes, lastNonZero));
        }
      }
      if (spots.length < 2) return [];
      return [
        TransactionSegment(
          spots: spots,
          lineColor: Sandik.amber,
          areaGradientStart: Sandik.amber.withValues(alpha: 0.12),
          areaGradientEnd: Colors.transparent,
          thickness: 3.5,
        ),
      ];
    }

    final segments = <TransactionSegment>[];
    // Simülasyon modu: tüm dönem tek aktif segment (sarı çizgi). Anchor
    // yok, passive segment yok; her nokta "o gün bugünkü net pozisyon
    // tutulsaydı" değeri.
    if (simulate) {
      final sortedTs = history.keys.toList()..sort();
      final spots = <FlSpot>[];
      for (final ts in sortedTs) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        // Saatlik veri için kesirli gün (24 → 1.0 gün). inDays saati keser
      // ve tüm saatler aynı X'e düşerdi → grafik zigzag olurdu.
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
        spots.add(FlSpot(x, history[ts]!));
      }
      // Son spot'un Y değerini canlı toplamla override et — X'e dokunma,
      // aksi halde saatlik veride yeni bir spot eklenip zigzag olur.
      if (currentTotalOverride != null && currentTotalOverride > 0) {
        if (spots.isNotEmpty) {
          final last = spots.last;
          spots[spots.length - 1] = FlSpot(last.x, currentTotalOverride);
        } else {
          final nowX =
              endDate.difference(startDate).inMinutes / (60.0 * 24.0);
          spots.add(FlSpot(nowX, currentTotalOverride));
        }
      }
      if (spots.length < 2) return [];
      segments.add(TransactionSegment(
        spots: spots,
        lineColor: Sandik.amber,
        areaGradientStart: Sandik.amber.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
      return segments;
    }

    // Aktif segment başlangıcı = ilk BUY lot tarihi. Sell/deleteLog dahil
    // edilirse edge case'lerde yanlış tarih seçilebilir; buy yoksa segment
    // zaten çizilmeyecek.
    final buyLots = allAssets.where((a) => a.isBuy).toList();
    if (buyLots.isEmpty) return [];
    final firstAssetDate = buyLots
        .map((a) => a.addedDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    // Normalize firstAssetDate to midnight for comparison
    final firstAssetMidnight =
        DateTime(firstAssetDate.year, firstAssetDate.month, firstAssetDate.day);

    final sortedTs = history.keys.toList()..sort();

    // Sadece aktif segment (ilk alımdan bugüne). TradingView tarzı: ilk
    // noktanın Y değeri o günün gerçek piyasa değeri (history[ts]). Alım
    // maliyeti tarihsel Y'yi bastırıp yapay atlama üretmez.
    final activeSpots = <FlSpot>[];

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      final y = history[ts]!;
      activeSpots.add(FlSpot(x, y));
    }

    // Son noktayı, kullanıcının şu an ekranda gördüğü toplam mal varlığı
    // değerine sabitle. X ekseni kesirli gün cinsinden (saatlik veride
    // 1 saat = 1/24 gün). Basit strateji: son spot'un Y değerini canlı
    // toplama override et — X'i değiştirme, böylece grafik zigzag/kırık
    // olmaz. Nokta yoksa endDate'in tam anına yeni bir spot ekle.
    if (currentTotalOverride != null && currentTotalOverride > 0) {
      if (activeSpots.isNotEmpty) {
        final last = activeSpots.last;
        activeSpots[activeSpots.length - 1] =
            FlSpot(last.x, currentTotalOverride);
      } else {
        final nowX =
            endDate.difference(startDate).inMinutes / (60.0 * 24.0);
        activeSpots.add(FlSpot(nowX, currentTotalOverride));
      }
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
    final isIntraday = _periods[_selectedPeriodIdx].intraday;
    // Intraday modda X ekseni bugünün 00:00'ından başlar.
    final startDate = isIntraday
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : endDate.subtract(Duration(days: _periods[_selectedPeriodIdx].days));

    return DefaultTextStyle(
      style: GoogleFonts.dmSans(
          color: Colors.white, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Performans',
                      style: context.t.headlineLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                  SandikLogoutButton(
                    onPressed: () => confirmAndLogout(context, ref),
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: pStateAsync.when(
                loading: () => const SandikLoadingScreen(),
                error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
                data: (pState) => partnerAssetsAsync.when(
                  loading: () => const SandikLoadingScreen(),
                  error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
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
                    // deleteLog'u çıkar (buy row zaten silinmiş, sadece
                    // transaction kaydı). Buy + sell birlikte gider —
                    // HistoryService her gün için buy addedDate <= dayTs
                    // ve sell addedDate <= dayTs kurallarıyla o gün geçerli
                    // net miktarı hesaplar. Böylece grafik hem alınmadan
                    // önceki günlerde 0 gösterir hem de satış günü sonrası
                    // net miktara oturur.
                    targetAssets =
                        targetAssets.where((a) => !a.isDeleteLog).toList();
                    // Apply asset type filter
                    if (_typeFilter != null) {
                      targetAssets = targetAssets
                          .where((a) => a.type == _typeFilter)
                          .toList();
                    }
                    // Simülasyon modu: bugünün net pozisyonlarını
                    // tüm dönem boyunca sabit tut — "şu anki portföyümü o
                    // zaman elimde tutsaydım" senaryosunu HistoryService'e
                    // net display-asset listesi olarak ver.
                    final chartAssets = _simulate
                        ? aggregatePositions(targetAssets)
                            .map((p) => p.asDisplayAsset())
                            .toList()
                        : targetAssets;

                    // TradingView "auto range": kullanıcı seçilen periyot
                    // içinde hiç varlığı yoksa (örn. 1Y seçtiği ama 3 gün
                    // önce başladı), chart ilk alım tarihinden itibaren
                    // çizilir. History fetch'i de bu daraltılmış aralıkta
                    // yapmalıyız — aksi halde controller 1Y'lik boş veri
                    // fetch edip görselde tek nokta gibi gösterir.
                    DateTime effectiveStart = startDate;
                    if (!isIntraday) {
                      final buys = chartAssets.where((a) => a.isBuy);
                      if (buys.isNotEmpty) {
                        final firstBuy = buys
                            .map((a) => a.addedDate)
                            .reduce((a, b) => a.isBefore(b) ? a : b);
                        if (firstBuy.isAfter(startDate)) {
                          effectiveStart = DateTime(
                              firstBuy.year, firstBuy.month, firstBuy.day);
                        }
                      }
                    }

                    // Intraday hâlâ eski hourly servisini kullanır (5 dk
                    // grid, ayrı optimize logic). Diğer periyotlar zoom-aware
                    // ZoomDataController üstünden gider.
                    if (!isIntraday) {
                      _ensureController(
                        chartAssets: chartAssets,
                        from: effectiveStart,
                        to: endDate,
                        intraday: false,
                      );
                    }

                    final controller = _zoomController;
                    return ListenableBuilder(
                      listenable: controller ?? ValueNotifier<int>(0),
                      builder: (context, _) {
                        final Map<int, double> historyMap;
                        final bool waiting;
                        if (isIntraday) {
                          // Intraday için hâlâ tek seferlik future — orası
                          // 5dk grid ve saatte bir tick zaten var.
                          return FutureBuilder<Map<int, double>>(
                            future: HistoryService.instance
                                .getPortfolioHistoryHourly(chartAssets, 24),
                            builder: (context, snapshot) {
                              final loading = snapshot.connectionState ==
                                  ConnectionState.waiting;
                              if (loading && snapshot.data == null) {
                                return const SizedBox(
                                    height: 300,
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            color: Sandik.amber)));
                              }
                              return _buildChartWithData(
                                snapshot.data ?? const {},
                                targetAssets,
                                chartAssets,
                                startDate,
                                endDate,
                                isIntraday,
                                pState,
                                activePartners,
                                waiting: false,
                              );
                            },
                          );
                        }
                        historyMap = controller?.data ?? const {};
                        waiting = controller?.loading ?? false;
                        // Veri henüz hiç gelmediyse spinner göster
                        if (historyMap.isEmpty && waiting) {
                          return const SizedBox(
                              height: 300,
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: Sandik.amber)));
                        }
                        return _buildChartWithData(
                          historyMap,
                          targetAssets,
                          chartAssets,
                          effectiveStart,
                          endDate,
                          isIntraday,
                          pState,
                          activePartners,
                          waiting: waiting,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Chart + wrap widget'ları — hem intraday hem controller-based data için.
  /// waiting: yeni veri yükleniyor (üstte küçük progress bar göster).
  Widget _buildChartWithData(
    Map<int, double> historyMap,
    List<Asset> targetAssets,
    List<Asset> chartAssets,
    DateTime startDate,
    DateTime endDate,
    bool isIntraday,
    PortfolioState pState,
    List<AppUser> activePartners, {
    required bool waiting,
  }) {
    // Ana ekranla birebir aynı TRY hesabı: targetAssets grafik için ham buy
    // lot'ları içeriyor (satılan miktarı geçmişte düşürmemek için). Ancak
    // GÜNCEL toplam net pozisyondan gelmeli — aggregate ile sell'leri düşüp
    // asDisplayAsset.totalValue'yu topla.
    final currentTotal = aggregatePositions(targetAssets)
        .map((p) => p.asDisplayAsset())
        .fold<double>(
            0, (s, a) => s + pState.toTRY(a.totalValue, a.currency));

    // TradingView "auto range" davranışı: kullanıcı seçilen periyot içinde
    // hiç varlığı yoksa (örn. 1Y seçtiği ama 3 gün önce başladı), chart
    // ilk alım tarihinden itibaren çizilir. Böylece kısa geçmişli portföyde
    // grafik boş değil, sıkışık şekilde ilk alıştan bugüne yayılır.
    DateTime effectiveStart = startDate;
    if (!isIntraday) {
      final buys = chartAssets.where((a) => a.isBuy);
      if (buys.isNotEmpty) {
        final firstBuy = buys
            .map((a) => a.addedDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        // Sadece ilk alım, seçili periyot başlangıcından SONRAYSA
        // startDate'i geç kaydır. Aksi halde tam periyodu göster.
        if (firstBuy.isAfter(startDate)) {
          effectiveStart =
              DateTime(firstBuy.year, firstBuy.month, firstBuy.day);
        }
      }
    }

    final segments = _convertHistoryToSegments(
        historyMap, chartAssets, effectiveStart, endDate,
        currentTotalOverride: currentTotal,
        simulate: _simulate,
        intraday: isIntraday);

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        if (activePartners.isNotEmpty) ...[
          ModernTabSelector(
            partners: activePartners,
            selectedId: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 12),
        ],
        HScrollWithFade(
          child: Row(
            children: [
              _typeChip(null, 'Tümü'),
              for (final t in RemoteConfigService.instance.visibleAssetTypes)
                _typeChip(t, t.label),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildPeriodToggle(),
        if (!isIntraday) ...[
          const SizedBox(height: 12),
          _buildModeToggle(),
        ],
        const SizedBox(height: 24),
        // "Yeni çözünürlükte veri yükleniyor" göstergesi — zoom sırasında
        // eski veri ekranda kalır, üstte ince bir bar akıcı hisi verir.
        if (waiting)
          const SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: Sandik.amber,
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (ref.watch(leaderboardOptInProvider) &&
                activePartners.isNotEmpty) ...[
              _LeaderboardChip(
                onTap: () => Navigator.push(
                  context,
                  adaptiveRoute(
                      builder: (_) => const LeaderboardScreen()),
                ),
              ),
              const SizedBox(width: 6),
            ],
            _PortfolioFullscreenChip(
              onTap: () {
                FullscreenChartRoute.open(
                  context,
                  title: 'Portföy Performans',
                  builder: (_) => PortfolioPerformanceScreen(
                    initialView: _view,
                    initialTypeFilter: _typeFilter,
                    // Landscape'te grafik hemen görünsün diye header'ları
                    // aşağı kaydır. Yukarı swipe ile tab/filtre/period gelir.
                    initialScrollOffset: 220,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildChartContainer(
            segments, effectiveStart, endDate, chartAssets,
            intraday: isIntraday,
            allTargetAssets: targetAssets),
        const SizedBox(height: 24),
        _PortfolioSignalPanel(assets: targetAssets),
        const SizedBox(height: 12),
        const DisclaimerWidget(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? Sandik.amber;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: () => setState(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Sandik.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
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
          color: Sandik.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() => _selectedPeriodIdx = i);
                _startIntradayTickIfNeeded();
              },
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF1A3D2E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: context.t.bodyMedium?.copyWith(
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

  /// Gerçek geçmiş / Simülasyon toggle'ı.
  /// - Gerçek: her günün o günkü net miktarına göre değer (alım/satışlar
  ///   tarihlerine göre).
  /// - Simülasyon: bugünkü net portföy tüm dönem boyunca elde tutulmuş gibi.
  Widget _buildModeToggle() {
    const options = [
      (label: 'Gerçek', sim: false),
      (label: 'Simülasyon', sim: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: Sandik.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = _simulate == o.sim;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _simulate = o.sim),
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1A3D2E)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      o.label,
                      style: context.t.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? Sandik.amber : Sandik.text36,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showModeInfoSheet(forSim: o.sim),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: selected
                              ? Sandik.amber.withValues(alpha: 0.85)
                              : Sandik.text36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showModeInfoSheet({required bool forSim}) {
    final title = forSim ? 'Simülasyon Modu' : 'Gerçek Mod';
    final body = forSim
        ? 'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş '
            'olsaydın grafik nasıl görünürdü — geçmişteki alım/satış '
            'kararlarını yok sayar, sadece güncel pozisyonun fiyat '
            'değişimini gösterir.'
        : 'Her günün grafikteki değeri, o gün elinde olan net miktara '
            'göre hesaplanır. Bir noktaya dokununca o günkü portföy değeri '
            've varsa alım / satış tutarları görünür — böylece grafiğin '
            'neden yükseldiğini veya düştüğünü net görebilirsin.';

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => DefaultTextStyle(
        style: GoogleFonts.dmSans(
            color: Colors.white, decoration: TextDecoration.none),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: const BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 20, color: Sandik.amber),
                    const SizedBox(width: 8),
                    Text(title,
                        style: context.t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: context.t.bodyMedium?.copyWith(
                      color: Sandik.text58,
                      height: 1.5,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// TRY değeri için okunabilir kısa etiket (₺1,2M / ₺450K / ₺900)
  String _fmtY(double val) => fmtTRYCompact(val);

  /// Y ekseni interval'i için "nice number" — TradingView tarzı okunması
  /// kolay yuvarlak sayı. 1-2-5-10 tabanında hızlı bulur.
  double _niceRoundNumber(double raw) {
    if (raw <= 0) return 1;
    final exponent = (raw > 0 ? raw : 1.0).abs();
    final magnitude = _pow10((_log10(exponent)).floor());
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

  double _log10(double x) => (x <= 0) ? 0 : (math.log(x) / math.ln10);
  double _pow10(int n) => math.pow(10, n).toDouble();

  Widget _buildChartContainer(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets,
      {bool intraday = false, List<Asset>? allTargetAssets}) {
    if (segments.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
            color: Sandik.surface1, borderRadius: BorderRadius.circular(SandikRadius.lg)),
        child: const Center(
            child: Text('Veri yok',
                style: TextStyle(color: Sandik.text36))),
      );
    }

    // Y ekseni scale'i — SADECE en kalın segmentin (aktif sarı çizgi)
    // değerlerine göre hesaplanır. Passive segment (alım öncesi 0 çizgisi)
    // Y aralığına dahil edilirse min hep 0'a çekilir ve aktif değerler
    // ezik görünür. Bu yüzden en kalın segmenti "ana" kabul edip diğerleri
    // clipData ile alta düşer.
    final primarySeg = segments
        .reduce((a, b) => (a.thickness >= b.thickness) ? a : b);

    // Görünür X aralığındaki spot'lara göre Y sınırlarını hesapla. Zoom
    // sırasında X daraldıkça Y ekseni otomatik yeniden fit olur — kullanıcı
    // dar bir zaman diliminde küçük dalgalanmayı okuyabilir.
    ({double minY, double maxY, double interval}) computeY(
        double viewMinX, double viewMaxX) {
      double minY = double.infinity;
      double maxY = -double.infinity;
      double sumY = 0;
      int countY = 0;
      for (final spot in primarySeg.spots) {
        if (spot.x < viewMinX || spot.x > viewMaxX) continue;
        if (spot.y > maxY) maxY = spot.y;
        if (spot.y < minY) minY = spot.y;
        sumY += spot.y;
        countY++;
      }
      if (minY == double.infinity) minY = 0;
      if (maxY == -double.infinity) maxY = 1000;
      final avgY = countY > 0 ? sumY / countY : (minY + maxY) / 2;
      final dataMinY = minY;
      final dataMaxY = maxY;
      final dataRange = (dataMaxY - dataMinY).clamp(1.0, double.infinity);
      final minSpread = (avgY * 0.08).clamp(1.0, double.infinity);
      final effectiveRange =
          dataRange < minSpread ? minSpread : dataRange;
      final yPadding = effectiveRange * 0.15;
      double outMaxY = (avgY + effectiveRange / 2) + yPadding;
      double outMinY =
          (avgY - effectiveRange / 2 - yPadding).clamp(0, double.infinity);
      final endpointPad = effectiveRange * 0.10;
      if (dataMinY - endpointPad < outMinY) {
        outMinY = (dataMinY - endpointPad).clamp(0, double.infinity);
      }
      if (dataMaxY + endpointPad > outMaxY) {
        outMaxY = dataMaxY + endpointPad;
      }
      // TradingView tarzı "nice numbers": interval'ı okunması kolay
      // yuvarlak sayıya oturt. Ham 137592/4=34398 gibi rakam yerine 25000/
      // 50000/100000 gibi. Chart üzerindeki grid line'lar da bu yuvarlak
      // değerlere denk gelir, Y label'lar temiz görünür.
      final rawInterval = (outMaxY - outMinY) / 4;
      final niceInterval = _niceRoundNumber(rawInterval);
      // Interval yuvarlanınca minY/maxY'yi de yuvarla ki labellar tam denk.
      final niceMin = (outMinY / niceInterval).floor() * niceInterval;
      final niceMax = (outMaxY / niceInterval).ceil() * niceInterval;
      return (
        minY: niceMin.clamp(0.0, double.infinity),
        maxY: niceMax,
        interval: niceInterval,
      );
    }

    // X ekseni — aktif segment çok sıkışıksa (örn. tek gün alım + bugün)
    // viewport'u aktif segment başlangıcından biraz öncesine daralt.
    // Böylece "12 Tem'de aldım, bugün 13" senaryosu tüm 1H window'da
    // dikey çubuk gibi değil, geniş bir eğri gibi görünür. AYRICA
    // başlangıç ve bitiş noktaları hep viewport'un içinde kalmalı —
    // dot çizim yarıçapı (~6px) sınırda clip'lenmesin diye her iki
    // uca minimum yarım günlük pay bırakılır.
    double fullMaxX;
    if (intraday) {
      // Şimdi noktasını viewport'un sağında **hep içeride** tut ki her
      // tick'te güncellenirken görünsün. Nokta viewport'un yaklaşık
      // %82'sinde olacak şekilde fullMaxX'i genişletiyoruz. Alt sınır
      // 1440 (tam gün) — sabahın ilk saatlerinde grafiğin çok dar
      // görünmesini engeller.
      final now = DateTime.now();
      final nowMin = (now.hour * 60 + now.minute).toDouble();
      final needed = nowMin > 0 ? nowMin / 0.82 : 240.0;
      fullMaxX = needed > 1440.0 ? needed : 1440.0;
    } else {
      // Kesirli gün — saatlik veride son X ~6.83, integer olsa 7 kalırdı
      // ve son nokta grafiğin sağında boşta kalırdı.
      fullMaxX = (end.difference(start).inMinutes / (60.0 * 24.0))
          .clamp(1.0, double.infinity);
    }
    double minX = 0;
    double maxX = fullMaxX;
    final activeSpotXs = primarySeg.spots.map((s) => s.x).toList()..sort();
    if (activeSpotXs.isNotEmpty && !intraday) {
      final firstActiveX = activeSpotXs.first;
      final lastActiveX = activeSpotXs.last;
      final activeSpan = lastActiveX - firstActiveX;
      final fullSpan = fullMaxX;
      // Aktif segment tüm periyodun %25'inden azsa viewport'u daralt.
      if (activeSpan < fullSpan * 0.25) {
        // İlk & son noktanın iki tarafına eşit ve cömert bağlam bırak
        // (en az 1 gün, en çok aktif span kadar). Böylece başlangıç
        // ve bitiş noktaları grafiğin ortasında değil, kenardan güvenli
        // bir mesafede görünür.
        final pad = (activeSpan.clamp(1.0, double.infinity)) * 0.8;
        minX = (firstActiveX - pad).clamp(0.0, fullMaxX);
        // clamp(lower, upper) kuralı: lower <= upper olmalı. Aktif segment
        // fullMaxX'e yakınsa "minX + 1" fullMaxX'i geçebilir → crash. O yüzden
        // önce üst sınırı belirle, sonra minX + 1'i onunla clamp'la.
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + pad).clamp(lower, upper);
      }
      // Son güvenlik payı: dot yarıçapı viewport sınırında clip olmasın.
      // Toplam aralığın %3'ü kadar minimum pay bırak.
      final safety = ((maxX - minX) * 0.03).clamp(0.15, double.infinity);
      if (firstActiveX - minX < safety) {
        minX = (firstActiveX - safety).clamp(0.0, fullMaxX);
      }
      if (maxX - lastActiveX < safety) {
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + safety).clamp(lower, upper);
      }
      // Son bir güvenlik: minX ile maxX çakışmışsa hafifçe aç.
      if (maxX <= minX) {
        maxX = (minX + 1).clamp(0.0, fullMaxX);
        if (maxX <= minX) minX = (maxX - 1).clamp(0.0, fullMaxX);
      }
    }

    // Intraday: şimdiki zaman marker'ı — dakika cinsinden 00:00'dan sapma.
    final now = DateTime.now();
    final nowMinutes = intraday
        ? (now.hour * 60 + now.minute).toDouble()
        : 0.0;

    // Zoom durumunda tekrar üretilen LineChartData'yı bir closure'a al.
    // ZoomableChart pinch/pan sırasında minX/maxX değiştirdikçe bu builder
    // yeniden çağrılır; Y ekseni görünür pencereye göre re-fit olur.
    LineChartData buildData(double viewMinX, double viewMaxX) {
      final y = computeY(viewMinX, viewMaxX);
      final double viewMinY = y.minY;
      final double viewMaxY = y.maxY;
      final double yInterval = y.interval;
      // X ekseni için uygun aralık. Intraday'de 4 saatlik (240 dk) etiketler
      // → 00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00 gibi.
      final xInterval = intraday
          ? 240.0
          : _niceRoundNumber((viewMaxX - viewMinX) / 5)
              .clamp(1.0, double.infinity);
      return LineChartData(
          minX: viewMinX,
          maxX: viewMaxX,
          minY: viewMinY,
          maxY: viewMaxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: intraday,
            verticalInterval: intraday ? 240 : null,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.04),
              strokeWidth: 1,
            ),
          ),
          // Sağ Y ekseni band'ı görsel olarak plot area'dan ayrılsın diye
          // sadece sağ kenara ince dikey çizgi. TradingView'de plot | Y ayrık.
          borderData: FlBorderData(
            show: true,
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
          ),
          extraLinesData: intraday
              ? ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: nowMinutes,
                      color: Sandik.amber.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      dashArray: const [5, 4],
                      label: VerticalLineLabel(
                        show: true,
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(bottom: 6, right: 4),
                        style: context.t.labelMedium?.copyWith(
                          letterSpacing: 0,
                          fontWeight: FontWeight.w700,
                          color: Sandik.amber,
                        ),
                        labelResolver: (_) => 'ŞİMDİ',
                      ),
                    ),
                  ],
                )
              : ExtraLinesData(
                  verticalLines: primarySeg.spots.isEmpty
                      ? const []
                      : [
                          // Başlangıç (dönem başı) için dashed amber marker.
                          // Etiket çizginin SAĞINA (grafik içine) yaslanır,
                          // aksi halde sol kenara sıkışıp kırpılır.
                          VerticalLine(
                            x: primarySeg.spots.first.x,
                            color: Sandik.amber.withValues(alpha: 0.75),
                            strokeWidth: 1.6,
                            dashArray: const [4, 4],
                            label: VerticalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(
                                  bottom: 8, left: 6),
                              style: context.t.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Sandik.amber,
                              ),
                              labelResolver: (_) {
                                final startTs = start.add(Duration(
                                    minutes:
                                        (primarySeg.spots.first.x * 1440)
                                            .round()));
                                final showYear =
                                    startTs.year != DateTime.now().year;
                                return '● ${DateFormat(showYear ? 'd MMM yyyy' : 'd MMM', 'tr_TR').format(startTs)}';
                              },
                            ),
                          ),
                          // Son nokta (bugün / şimdi) için dashed marker.
                          // Etiket çizginin SOLUNA (grafik içine) yaslanır.
                          VerticalLine(
                            x: primarySeg.spots.last.x,
                            color: Sandik.gain.withValues(alpha: 0.55),
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
                                color: Sandik.gain,
                              ),
                              labelResolver: (_) => 'ŞİMDİ',
                            ),
                          ),
                        ],
                ),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            // TradingView tarzı: fiyat scale SAĞDA, tarih ekseni ALTTA ayrı bant.
            // leftTitles kapatıldı, rightTitles dolduruldu. Rezerv alanları
            // grafik alanına girmesin diye cömert (Y sağda 60, X altta 40).
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: yInterval,
                getTitlesWidget: (val, meta) {
                  if (val == meta.min || val == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _fmtY(val),
                      textAlign: TextAlign.left,
                      style: context.t.numSmall.copyWith(
                        color: Sandik.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: xInterval,
                getTitlesWidget: (val, meta) {
                  if (val == meta.min || val == meta.max) {
                    return const SizedBox.shrink();
                  }
                  // Dinamik format — dar viewport'ta gün+ay, geniş
                  // viewport'ta (365+ gün) sadece "MMM yy". Çok dar (<3 gün)
                  // görünümde saat de göster.
                  String nonIntradayLabel(double v) {
                    final d = start.add(Duration(
                        minutes: (v * 24 * 60).round()));
                    final span = (meta.max - meta.min).abs();
                    final showYearOnly = span > 400;
                    final showTime = span < 3;
                    final showYear =
                        !showYearOnly && d.year != DateTime.now().year;
                    if (showYearOnly) {
                      return DateFormat('MMM yy', 'tr_TR').format(d);
                    }
                    if (showTime) {
                      return DateFormat('d MMM HH:mm', 'tr_TR').format(d);
                    }
                    return DateFormat(
                            showYear ? 'd MMM yy' : 'd MMM', 'tr_TR')
                        .format(d);
                  }
                  final label = intraday
                      ? () {
                          final h = (val ~/ 60).clamp(0, 23);
                          final m = (val % 60).toInt();
                          return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                        }()
                      : nonIntradayLabel(val);
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      label,
                      style: context.t.numSmall.copyWith(
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
            // Nokta yoğunluğu arttıkça çizgi inceltilir — intraday ve haftalık
            // (saatlik) yüzlerce nokta içerir, kalın çizgi zigzag'i yutar.
            // Trading uygulamalarındaki gibi ince ve okunaklı bir hat için:
            final periodDays = _periods[_selectedPeriodIdx].days;
            final activeBarWidth = intraday
                ? 1.6
                : periodDays <= 7
                    ? 2.0
                    : periodDays <= 30
                        ? 2.4
                        : periodDays <= 90
                            ? 2.0
                            : periodDays <= 180
                                ? 1.8
                                : 1.5;
            final effectiveBarWidth =
                isActive ? activeBarWidth : seg.thickness;
            return LineChartBarData(
              spots: seg.spots,
              isCurved: false,
              color: seg.lineColor,
              barWidth: effectiveBarWidth,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) {
                  if (!isActive) return false;
                  // Simülasyonda nokta yok — sadece süreklilik çizgisi.
                  if (_simulate) return false;
                  // Intraday: sadece ilk ve son noktada dot göster (5 dk
                  // aralıklı yüzlerce nokta olduğu için hepsini işaretlemek
                  // grafiği bulanıklaştırır).
                  if (intraday) {
                    // Trading hissiyatı: sadece "şimdi" noktası görünsün.
                    return spot.x == seg.spots.last.x;
                  }
                  final dateAtSpot =
                      start.add(Duration(minutes: (spot.x * 24 * 60).round()));
                  final hasAddition = assets.any((a) =>
                      a.addedDate.year == dateAtSpot.year &&
                      a.addedDate.month == dateAtSpot.month &&
                      a.addedDate.day == dateAtSpot.day);
                  return hasAddition ||
                      spot.x == seg.spots.first.x ||
                      spot.x == seg.spots.last.x;
                },
                getDotPainter: (spot, percent, barData, index) {
                  final isFirst = spot.x == seg.spots.first.x;
                  final isLast = spot.x == seg.spots.last.x;
                  // Intraday'de sadece "şimdi" noktasını canlı bir amber
                  // dot ile göster — trading uygulaması hissiyatı için
                  // ince halka ile.
                  if (intraday && isLast) {
                    // "Şu an" noktası — canlı vurgulu yeşil (Sandik.gain)
                    // ile trading uygulaması hissiyatı, ince beyaz halka.
                    return FlDotCirclePainter(
                      radius: 5.0,
                      color: Sandik.gain,
                      strokeColor: Colors.white.withValues(alpha: 0.9),
                      strokeWidth: 1.6,
                    );
                  }
                  // Başlangıç dot'u kaldırıldı — "orada alım yapılmış" gibi
                  // yanıltıcı görünüyordu. Başlangıç zaten dashed marker +
                  // label ile işaretli. Son nokta (şimdi) canlı vurgusu için
                  // büyük yeşil dot ile kalır.
                  if (isFirst) {
                    return FlDotCirclePainter(
                      radius: 0,
                      color: Colors.transparent,
                      strokeWidth: 0,
                    );
                  }
                  if (isLast) {
                    return FlDotCirclePainter(
                      radius: 6.0,
                      color: Sandik.gain,
                      strokeColor: Colors.white,
                      strokeWidth: 2.5,
                    );
                  }
                  return FlDotCirclePainter(
                    radius: 4.5,
                    color: Sandik.amber,
                    strokeColor: Colors.white,
                    strokeWidth: 2,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: intraday
                      ? [
                          Sandik.amber.withValues(alpha: 0.22),
                          Sandik.amber.withValues(alpha: 0.06),
                          Colors.transparent,
                        ]
                      : [seg.areaGradientStart, Colors.transparent],
                  stops: intraday ? const [0.0, 0.5, 1.0] : null,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            );
          }).toList(),
          // fl_chart'ın built-in touch'ı kapalı — crosshair TEK KAYNAK.
          // Kullanıcı uzun bastığında `ZoomableChart` snap edilmiş X'te dikey
          // çizgi + pill (fiyat/tarih/getiri/hareketler) gösterir. Tooltip ve
          // crosshair paralel çalışınca X hesabı farklı olup değerler
          // uyumsuz görünüyordu — tek kaynağa çektik.
          lineTouchData: LineTouchData(
            handleBuiltInTouches: false,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Sandik.surface2,
              tooltipRoundedRadius: 10,
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              getTooltipItems: (spots) {
                final tryFmt0 = NumberFormat.currency(
                    symbol: '₺', locale: 'tr_TR', decimalDigits: 0);
                // Primary segmentteki ilk ve son x — anchor / bugün tespiti.
                final firstX = primarySeg.spots.first.x;
                final lastX = primarySeg.spots.last.x;
                final firstY = primarySeg.spots.first.y;
                final lastY = primarySeg.spots.last.y;

                return spots.map((s) {
                  // Non-intraday: s.x kesirli gün → dakika cinsinden ekle.
                  // `.toInt()` kullanılırsa saat/dakika kısmı düşer ve tooltip
                  // etiketi yakınlardaki tarihe kayıyor.
                  final date = intraday
                      ? start.add(Duration(minutes: s.x.toInt()))
                      : start.add(
                          Duration(minutes: (s.x * 24 * 60).round()));
                  final isFirst = s.x == firstX;
                  final isLast = s.x == lastX;

                  // O gün YAPILAN alım/satım hareketleri (Gerçek modda).
                  double dayBuyTRY = 0, daySellTRY = 0;
                  // İlk noktadan (anchor) bugüne kadar KÜMÜLATİF hareketler.
                  double cumBuyTRY = 0, cumSellTRY = 0;
                  if (!_simulate && !intraday) {
                    final spotDayMs =
                        DateTime(date.year, date.month, date.day)
                            .millisecondsSinceEpoch;
                    for (final a in assets) {
                      if (a.isDeleteLog) continue;
                      final aDay = DateTime(a.addedDate.year,
                              a.addedDate.month, a.addedDate.day)
                          .millisecondsSinceEpoch;
                      final onSameDay = aDay == spotDayMs;
                      final onOrBefore = aDay <= spotDayMs;
                      if (a.isBuy) {
                        if (onSameDay) dayBuyTRY += a.totalCostTRY;
                        if (onOrBefore) cumBuyTRY += a.totalCostTRY;
                      } else if (a.isSell) {
                        if (onSameDay) daySellTRY += a.totalCostTRY;
                        if (onOrBefore) cumSellTRY += a.totalCostTRY;
                      }
                    }
                  }

                  final dayNet = dayBuyTRY - daySellTRY;
                  final hasActivity = dayBuyTRY > 0 || daySellTRY > 0;

                  // Anchor'a göre net getiri (bugüne kadarki maliyet vs
                  // portföy değeri). Sadece son nokta için göster.
                  final gainVsAnchor = lastY - firstY;

                  final children = <TextSpan>[
                    TextSpan(
                      text: tryFmt0.format(s.y),
                      style: context.t.numSmall.copyWith(
                        color: Sandik.gold,
                        fontSize: 15,
                      ),
                    ),
                  ];

                  // Bugün (son nokta) → getiri
                  if (isLast && !_simulate && gainVsAnchor.abs() > 0.5) {
                    final positive = gainVsAnchor >= 0;
                    children.add(TextSpan(
                      text:
                          '\nGetiri ${positive ? '+' : '−'}${tryFmt0.format(gainVsAnchor.abs())}',
                      style: context.t.numSmall.copyWith(
                        color: positive ? Sandik.gain : Sandik.loss,
                        fontSize: 11,
                      ),
                    ));
                  }

                  // O gün yapılan hareketler
                  if (hasActivity) {
                    if (dayBuyTRY > 0) {
                      children.add(TextSpan(
                        text: '\nAlım  +${tryFmt0.format(dayBuyTRY)}',
                        style: context.t.numSmall.copyWith(
                          color: Sandik.gain,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ));
                    }
                    if (daySellTRY > 0) {
                      children.add(TextSpan(
                        text: '\nSatış −${tryFmt0.format(daySellTRY)}',
                        style: context.t.numSmall.copyWith(
                          color: Sandik.loss,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ));
                    }
                    if (dayBuyTRY > 0 && daySellTRY > 0) {
                      children.add(TextSpan(
                        text:
                            '\nNet ${dayNet >= 0 ? '+' : '−'}${tryFmt0.format(dayNet.abs())}',
                        style: context.t.numSmall.copyWith(
                          color: dayNet >= 0 ? Sandik.gain : Sandik.loss,
                          fontSize: 11,
                        ),
                      ));
                    }
                  }

                  // İlk nokta (anchor) — birikmiş yatırım toplamı bilgisi
                  // (bu döneme kadar tüm buy - sell). Kullanıcı "grafik
                  // buradan başlıyor, ne kadar para koydum?" sorusuna
                  // cevap alsın.
                  if (isFirst && !_simulate && cumBuyTRY > 0) {
                    final cumNet = cumBuyTRY - cumSellTRY;
                    children.add(TextSpan(
                      text: '\nToplam yatırım ${tryFmt0.format(cumNet)}',
                      style: context.t.labelMedium?.copyWith(
                        letterSpacing: 0,
                        color: Sandik.text58,
                      ),
                    ));
                  }

                  final headerLabel = intraday
                      ? DateFormat('HH:mm', 'tr_TR').format(date)
                      : DateFormat('d MMM yyyy', 'tr_TR').format(date);
                  return LineTooltipItem(
                    '$headerLabel\n',
                    context.t.bodySmall!.copyWith(
                        color: Sandik.text58,
                        fontWeight: FontWeight.w500),
                    children: children,
                  );
                }).toList();
              },
            ),
          ),
        );
    }

    // Volume subchart için sync viewport. Aynı controller ZoomableChart ve
    // ZoomableBarChart tarafından paylaşılır → üstte pinch/pan yapılınca
    // alt panel de aynı X aralığına oturur.
    final viewport = _ensureViewport(
      key:
          '${_zoomKey ?? "n/a"}|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$intraday',
      fullMinX: minX,
      fullMaxX: maxX,
    );

    // Volume verisi: gün-bazlı buy/sell TRY. Intraday'de bar chart mantıklı
    // değil (gün içi işlem yoğunluğu farklı bir metrik) → sadece intraday
    // olmayan periyotlarda çizilir.
    final volumeBars = intraday
        ? const <_VolumeBar>[]
        : _computeVolumeBars(allTargetAssets ?? const [], start);
    final showVolume = volumeBars.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 20, 16, 12),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          ZoomableChart(
        fullMinX: minX,
        fullMaxX: maxX,
        height: 360 - 32,
        builder: buildData,
        viewportController: viewport,
        // Sağdaki Y ekseni rezervi (rightTitles.reservedSize ile aynı).
        // Crosshair bu alana **girmez** — plot area net sınırlı.
        plotPaddingRight: 60,
        onViewportChanged: intraday
            ? null
            : (viewMinX, viewMaxX) {
                final controller = _zoomController;
                if (controller == null) return;
                final from = start.add(
                    Duration(minutes: (viewMinX * 1440).round()));
                final to = start.add(
                    Duration(minutes: (viewMaxX * 1440).round()));
                controller.updateViewport(from, to);
              },
        crosshairSnapX: (x) {
          final spots = primarySeg.spots;
          if (spots.isEmpty) return x;
          final clamped = x.clamp(spots.first.x, spots.last.x);
          int nearestIdx = 0;
          double nearestDx = double.infinity;
          for (int i = 0; i < spots.length; i++) {
            final dx = (spots[i].x - clamped).abs();
            if (dx < nearestDx) {
              nearestDx = dx;
              nearestIdx = i;
            }
          }
          return spots[nearestIdx].x;
        },
        crosshairLabelBuilder: (x) {
          // x zaten crosshairSnapX ile snap edildi — burada eşleşen spot'u bul.
          final spots = primarySeg.spots;
          if (spots.isEmpty) return null;
          FlSpot snapped = spots.first;
          double best = double.infinity;
          for (final s in spots) {
            final d = (s.x - x).abs();
            if (d < best) {
              best = d;
              snapped = s;
            }
          }
          final date = intraday
              ? DateTime(start.year, start.month, start.day)
                  .add(Duration(minutes: snapped.x.round()))
              : start.add(Duration(minutes: (snapped.x * 1440).round()));
          final title = NumberFormat.currency(
                  locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
              .format(snapped.y);
          final subtitle = intraday
              ? DateFormat('HH:mm', 'tr_TR').format(date)
              : DateFormat('d MMM yyyy', 'tr_TR').format(date);
          return (title, subtitle);
        },
        crosshairDetailsBuilder: (x) {
          // Snap edilmiş spot'u bul (crosshairSnapX zaten uyguladı).
          final spots = primarySeg.spots;
          if (spots.isEmpty || _simulate || intraday) return const [];
          FlSpot snapped = spots.first;
          double best = double.infinity;
          for (final s in spots) {
            final d = (s.x - x).abs();
            if (d < best) {
              best = d;
              snapped = s;
            }
          }
          final tryFmt0 = NumberFormat.currency(
              symbol: '₺', locale: 'tr_TR', decimalDigits: 0);
          final firstY = spots.first.y;
          final gain = snapped.y - firstY;
          final date = start.add(
              Duration(minutes: (snapped.x * 1440).round()));
          final spotDayMs =
              DateTime(date.year, date.month, date.day)
                  .millisecondsSinceEpoch;
          double dayBuy = 0, daySell = 0;
          final txAssets = allTargetAssets ?? assets;
          for (final a in txAssets) {
            final addMid = DateTime(a.addedDate.year, a.addedDate.month,
                    a.addedDate.day)
                .millisecondsSinceEpoch;
            if (addMid != spotDayMs) continue;
            if (a.isBuy) dayBuy += a.totalCostTRY;
            if (a.isSell) daySell += a.totalCostTRY;
          }
          final out = <(String, Color)>[];
          if (gain.abs() > 0.5) {
            final positive = gain >= 0;
            out.add((
              'Getiri ${positive ? '+' : '−'}${tryFmt0.format(gain.abs())}',
              positive ? Sandik.gain : Sandik.loss,
            ));
          }
          if (dayBuy > 0) {
            out.add((
              'Alım +${tryFmt0.format(dayBuy)}',
              Sandik.gain,
            ));
          }
          if (daySell > 0) {
            out.add((
              'Satış −${tryFmt0.format(daySell)}',
              Sandik.loss,
            ));
          }
          return out;
        },
      ),
      if (showVolume) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Text(
            'İŞLEM HACMİ',
            style: context.t.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Sandik.text58,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 70,
          child: ListenableBuilder(
            listenable: viewport,
            builder: (_, __) {
              final vp = viewport;
              final maxY = volumeBars
                  .fold<double>(0, (m, b) => b.total > m ? b.total : m);
              // Her bar için 2 spot'lu ayrı bir LineChartBarData → dikey
              // çubuk. fl_chart'ın BarChart'ında X data-space değil, group
              // index olduğu için sync viewport için LineChart hilesi kullanıyoruz.
              final bars = <LineChartBarData>[];
              for (final b in volumeBars) {
                final buyPositive = b.buy >= b.sell;
                final color = buyPositive ? Sandik.gain : Sandik.loss;
                bars.add(LineChartBarData(
                  spots: [FlSpot(b.x, 0), FlSpot(b.x, b.total)],
                  isCurved: false,
                  color: color.withValues(alpha: 0.85),
                  barWidth: 3,
                  isStrokeCapRound: false,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ));
              }
              return LineChart(
                LineChartData(
                  minX: vp.minX,
                  maxX: vp.maxX,
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.15,
                  clipData: const FlClipData.all(),
                  lineTouchData: const LineTouchData(enabled: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineBarsData: bars,
                ),
              );
            },
          ),
        ),
      ],
        ],
      ),
    );
  }

  /// Gün-bazlı buy/sell TRY hacim. X price chart ile aynı gün-fraction
  /// birimde.
  List<_VolumeBar> _computeVolumeBars(
      List<Asset> assets, DateTime start) {
    // Ana chart'ın X birimi ile birebir aynı: kesirli gün (1 saat = 1/24).
    // İşlemi kendi gününün ortasına (12:00) snap et — TradingView tarzı hacim
    // çubuğu tarih çizgisinin üstüne düşer. `inDays` kullanılırsa tam sayıya
    // yuvarlanır ve grafik X ekseni ile hizasız kalır.
    final Map<int, ({double buy, double sell})> perDay = {};
    for (final a in assets) {
      final dayMidnight = DateTime(
          a.addedDate.year, a.addedDate.month, a.addedDate.day);
      final dayIdx =
          dayMidnight.difference(start).inMinutes ~/ (60 * 24);
      if (dayIdx < 0) continue;
      final prev = perDay[dayIdx] ?? (buy: 0.0, sell: 0.0);
      if (a.isBuy) {
        perDay[dayIdx] =
            (buy: prev.buy + a.totalCostTRY, sell: prev.sell);
      } else if (a.isSell) {
        perDay[dayIdx] =
            (buy: prev.buy, sell: prev.sell + a.totalCostTRY);
      }
    }
    final out = <_VolumeBar>[];
    perDay.forEach((day, tot) {
      if (tot.buy + tot.sell <= 0) return;
      // Bar merkezi gün ortasına — tarih etiketinin altına düşer.
      out.add(_VolumeBar(
          x: day.toDouble() + 0.5, buy: tot.buy, sell: tot.sell));
    });
    return out;
  }
}

class _VolumeBar {
  final double x;
  final double buy;
  final double sell;
  const _VolumeBar({required this.x, required this.buy, required this.sell});
  double get total => buy + sell;
}

// ── Portfolio Sinyal Paneli ───────────────────────────────────────────────────

class _PortfolioSignalPanel extends ConsumerWidget {
  final List<Asset> assets;
  const _PortfolioSignalPanel({required this.assets});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (assets.isEmpty) return const SizedBox.shrink();

    // Her varlığı analiz et, sadece AL/SAT olanları göster
    final results = assets.map((asset) {
      final indicators = TechnicalAnalysisService.analyze(asset, []);
      final summary = TechnicalAnalysisService.summarize(indicators);
      return (asset: asset, indicators: indicators, summary: summary);
    }).where((r) => r.summary.signal != SignalType.neutral).toList();

    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Sandik.gain, size: 20),
            const SizedBox(width: 12),
            Text('Güçlü sinyal yok — portföy nötr bölgede',
                style: context.t.bodyMedium?.copyWith(color: Sandik.text58)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('TEKNİK SİNYALLER',
                style: context.t.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Sandik.text36)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Sandik.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(SandikRadius.sm)),
              child: Text('${results.length}',
                  style: context.t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Sandik.amber)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...results.map((r) {
          final isBuy = r.summary.signal == SignalType.buy;
          final color = isBuy ? Sandik.gain : Sandik.loss;
          final label = isBuy ? 'AL' : 'SAT';
          final count = isBuy ? r.summary.buyCount : r.summary.sellCount;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                    color: color.withValues(alpha: 0.22), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık satırı
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                            isBuy
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            color: color,
                            size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (r.asset.showTicker) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                                    ),
                                    child: Text(r.asset.displayTicker!,
                                        style: context.t.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w800, color: color, decoration: TextDecoration.none)),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(r.asset.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.t.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          decoration: TextDecoration.none)),
                                ),
                              ],
                            ),
                            Text(r.asset.type.label,
                                style: context.t.bodySmall?.copyWith(
                                    color: Sandik.text36, decoration: TextDecoration.none)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                        ),
                        child: Text(label,
                            style: context.t.numSmall.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Gösterge özeti
                  Row(
                    children: r.indicators.map((ind) {
                      final c = ind.signal == SignalType.buy
                          ? Sandik.gain
                          : ind.signal == SignalType.sell
                              ? Sandik.loss
                              : Sandik.text36;
                      return Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(SandikRadius.sm),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ind.name.split(' ').first,
                              style: context.t.labelSmall?.copyWith(
                                  letterSpacing: 0,
                                  color: c,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count/5 gösterge $label diyor  ·  ${fmtPct(r.summary.confidence * 100, digits: 0)} güven',
                    style: context.t.bodySmall?.copyWith(color: Sandik.text58),
                  ),
                ],
              ),
            ),
          );
        }),
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
  TransactionSegment(
      {required this.spots,
      required this.lineColor,
      required this.areaGradientStart,
      required this.areaGradientEnd,
      required this.thickness});
}

/// Yarış (leaderboard) ekranını açan küçük ikon buton — grafik container
/// üstünde, fullscreen chip'inin solunda. Opt-in ve partner varsa gösterilir.
class _LeaderboardChip extends StatelessWidget {
  final VoidCallback onTap;
  const _LeaderboardChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Sandik.amber.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border:
                Border.all(color: Sandik.amber.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_rounded,
                  size: 13, color: Sandik.amber),
              const SizedBox(width: 4),
              Text(
                'YARIŞ',
                style: context.t.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Sandik.amber,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Portfolio ekranı grafik container'ının üstündeki "genişlet" ikon butonu.
class _PortfolioFullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _PortfolioFullscreenChip({required this.onTap});

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
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Icon(
            Icons.fullscreen_rounded,
            size: 16,
            color: Sandik.text58,
          ),
        ),
      ),
    );
  }
}
