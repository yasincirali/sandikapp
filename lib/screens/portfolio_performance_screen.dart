import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, CircularProgressIndicator, Icons, TextStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
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

class PortfolioPerformanceScreen extends ConsumerStatefulWidget {
  final String? initialView;
  final AssetType? initialTypeFilter;

  const PortfolioPerformanceScreen({
    super.key,
    this.initialView = '',
    this.initialTypeFilter,
  });

  @override
  ConsumerState<PortfolioPerformanceScreen> createState() =>
      _PortfolioPerformanceScreenState();
}

class _PortfolioPerformanceScreenState
    extends ConsumerState<PortfolioPerformanceScreen> {
  int _selectedPeriodIdx = 0; // Haftalık (1H)
  late String? _view;
  late AssetType? _typeFilter;
  // Grafik modu: false = gerçek geçmiş (alım/satışlara göre),
  //             true  = simülasyon (bugünkü net pozisyon tüm dönem boyunca).
  bool _simulate = false;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _typeFilter = widget.initialTypeFilter;
  }

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
    DateTime endDate, {
    double? currentTotalOverride,
    bool simulate = false,
  }) {
    if (history.isEmpty || allAssets.isEmpty) return [];

    final segments = <TransactionSegment>[];
    // Simülasyon modu: tüm dönem tek aktif segment (sarı çizgi). Anchor
    // yok, passive segment yok; her nokta "o gün bugünkü net pozisyon
    // tutulsaydı" değeri.
    if (simulate) {
      final sortedTs = history.keys.toList()..sort();
      final spots = <FlSpot>[];
      for (final ts in sortedTs) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        final x = date.difference(startDate).inDays.toDouble();
        spots.add(FlSpot(x, history[ts]!));
      }
      if (currentTotalOverride != null && currentTotalOverride > 0) {
        final todayX = DateTime(endDate.year, endDate.month, endDate.day)
            .difference(startDate)
            .inDays
            .toDouble();
        if (spots.isNotEmpty && spots.last.x == todayX) {
          spots[spots.length - 1] = FlSpot(todayX, currentTotalOverride);
        } else {
          spots.add(FlSpot(todayX, currentTotalOverride));
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

    // Alım maliyeti (sabit) — active segmentin başlangıç noktası olarak
    // kullanılır. Sadece BUY lot'ları toplanır; sell lot'unun totalCostTRY'si
    // buy fiyatını taşır ve toplama tekrar eklenirse maliyet ikiye katlanır.
    double totalCostTRY = 0.0;
    for (final a in buyLots) {
      totalCostTRY += a.totalCostTRY;
    }

    final sortedTs = history.keys.toList()..sort();

    // Sadece aktif segment (ilk alımdan bugüne). Alım öncesi "passive"
    // 0-çizgisi çizmiyoruz — grafik Y ekseni ilk alım maliyetinden başlar,
    // 0'dan değil. Böylece "12 Tem'de aldım, ekranda 0'dan başlıyor" gibi
    // yanlış okuma olmaz; ilk nokta gerçek yatırım tutarını gösterir.
    final activeSpots = <FlSpot>[];
    bool firstActiveReplaced = false;

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      final x = date.difference(startDate).inDays.toDouble();
      final y = history[ts]!;

      if (!firstActiveReplaced && totalCostTRY > 0) {
        activeSpots.add(FlSpot(x, totalCostTRY));
        firstActiveReplaced = true;
      } else {
        activeSpots.add(FlSpot(x, y));
      }
    }

    // Son noktayı, kullanıcının şu an ekranda gördüğü toplam mal varlığı
    // değerine sabitle. HistoryService USDTRY için hardcoded oran ve son
    // Yahoo verisi kullandığından son nokta ana ekranla eşleşmeyebilir.
    // Bugüne ait spot varsa onu güncelle; yoksa bugünün x'inde yeni bir
    // spot ekle — son nokta her zaman ekrandaki güncel toplamı gösterir.
    if (currentTotalOverride != null && currentTotalOverride > 0) {
      final todayX = DateTime(endDate.year, endDate.month, endDate.day)
          .difference(startDate)
          .inDays
          .toDouble();
      if (activeSpots.isNotEmpty && activeSpots.last.x == todayX) {
        activeSpots[activeSpots.length - 1] =
            FlSpot(todayX, currentTotalOverride);
      } else {
        activeSpots.add(FlSpot(todayX, currentTotalOverride));
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
    final startDate =
        endDate.subtract(Duration(days: _periods[_selectedPeriodIdx].days));

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
                      style: GoogleFonts.dmSans(
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

                    return FutureBuilder<Map<int, double>>(
                      future: HistoryService.instance.getPortfolioHistory(
                          chartAssets, _periods[_selectedPeriodIdx].days,
                          simulate: _simulate),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox(
                              height: 300,
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: Sandik.amber)));
                        }

                        final historyMap = snapshot.data ?? {};
                        // Ana ekranla birebir aynı TRY hesabı: targetAssets
                        // grafik için ham buy lot'ları içeriyor (satılan
                        // miktarı geçmişte düşürmemek için). Ancak GÜNCEL
                        // toplam net pozisyondan gelmeli — aggregate ile
                        // sell'leri düşüp asDisplayAsset.totalValue'yu topla.
                        final currentTotal = aggregatePositions(targetAssets)
                            .map((p) => p.asDisplayAsset())
                            .fold<double>(
                                0,
                                (s, a) =>
                                    s + pState.toTRY(a.totalValue, a.currency));
                        final segments = _convertHistoryToSegments(
                            historyMap, chartAssets, startDate, endDate,
                            currentTotalOverride: currentTotal,
                            simulate: _simulate);

                        return ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
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
                            const SizedBox(height: 12),
                            _buildModeToggle(),
                            const SizedBox(height: 24),
                            _buildChartContainer(
                                segments, startDate, endDate, chartAssets),
                            const SizedBox(height: 24),
                            _PortfolioSignalPanel(assets: targetAssets),
                            const SizedBox(height: 12),
                            const DisclaimerWidget(),
                            const SizedBox(height: 16),
                          ],
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
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
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
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _selectedPeriodIdx = i),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF1A3D2E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: GoogleFonts.dmSans(
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

  /// Gerçek geçmiş / Simülasyon toggle'ı.
  /// - Gerçek: her günün o günkü net miktarına göre değer (alım/satışlar
  ///   tarihlerine göre).
  /// - Simülasyon: bugünkü net portföy tüm dönem boyunca elde tutulmuş gibi.
  Widget _buildModeToggle() {
    final options = const [
      (label: 'Gerçek', sim: false),
      (label: 'Simülasyon', sim: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: Sandik.surface1, borderRadius: BorderRadius.circular(12)),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      o.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
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
                      borderRadius: BorderRadius.circular(2),
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
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
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

  Widget _buildChartContainer(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets) {
    if (segments.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
            color: Sandik.surface1, borderRadius: BorderRadius.circular(24)),
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
    double minY = double.infinity;
    double maxY = -double.infinity;
    double sumY = 0;
    int countY = 0;
    for (final spot in primarySeg.spots) {
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
    // Küçük gerçek değişimlerin dramatik görünmesini önlemek için Y ekseni
    // aralığını ortalamanın en az %8'i kadar tut.
    final minSpread = (avgY * 0.08).clamp(1.0, double.infinity);
    final effectiveRange =
        dataRange < minSpread ? minSpread : dataRange;
    final yPadding = effectiveRange * 0.15;
    // Merkezleme: primary segment değerleri viewport'un ortasında görünsün.
    maxY = (avgY + effectiveRange / 2) + yPadding;
    minY = (avgY - effectiveRange / 2 - yPadding).clamp(0, double.infinity);
    // Güvence: başlangıç (ilk buy) veya bitiş (bugün) noktası viewport
    // dışında kalmasın — merkezleme sırasında minSpread küçük olduğunda
    // uçtaki değerler kırpılabiliyordu. Data uçlarını her zaman içerecek
    // şekilde genişlet ve üstüne dot yarıçapı için pay bırak.
    final endpointPad = effectiveRange * 0.10;
    if (dataMinY - endpointPad < minY) {
      minY = (dataMinY - endpointPad).clamp(0, double.infinity);
    }
    if (dataMaxY + endpointPad > maxY) {
      maxY = dataMaxY + endpointPad;
    }

    // X ekseni — aktif segment çok sıkışıksa (örn. tek gün alım + bugün)
    // viewport'u aktif segment başlangıcından biraz öncesine daralt.
    // Böylece "12 Tem'de aldım, bugün 13" senaryosu tüm 1H window'da
    // dikey çubuk gibi değil, geniş bir eğri gibi görünür. AYRICA
    // başlangıç ve bitiş noktaları hep viewport'un içinde kalmalı —
    // dot çizim yarıçapı (~6px) sınırda clip'lenmesin diye her iki
    // uca minimum yarım günlük pay bırakılır.
    final fullMaxX =
        end.difference(start).inDays.toDouble().clamp(1.0, double.infinity);
    double minX = 0;
    double maxX = fullMaxX;
    final activeSpotXs = primarySeg.spots.map((s) => s.x).toList()..sort();
    if (activeSpotXs.isNotEmpty) {
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
        maxX = (lastActiveX + pad).clamp(minX + 1, fullMaxX);
      }
      // Son güvenlik payı: dot yarıçapı viewport sınırında clip olmasın.
      // Toplam aralığın %3'ü kadar minimum pay bırak.
      final safety = ((maxX - minX) * 0.03).clamp(0.15, double.infinity);
      if (firstActiveX - minX < safety) {
        minX = (firstActiveX - safety).clamp(0.0, fullMaxX);
      }
      if (maxX - lastActiveX < safety) {
        maxX = (lastActiveX + safety).clamp(minX + 1, fullMaxX);
      }
    }

    // 4 eşit aralıklı Y etiketi (min ve max hariç)
    // fl_chart `assert(interval > 0)` — tek-nokta veride çökmemesi için clamp
    final yInterval = ((maxY - minY) / 4).clamp(1.0, double.infinity);
    // X ekseni için uygun aralık (4 etiket) — viewport genişliği baz alınır.
    final xInterval = ((maxX - minX) / 4).ceilToDouble().clamp(1.0, double.infinity);

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
          minX: minX,
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
                      style: GoogleFonts.dmSans(
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
                      style: GoogleFonts.dmSans(
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
            // Uzun dönemlerde (6A/1Y) kalın çizgi kıvrımları yutuyor —
            // dönem uzadıkça ince tut, kısa dönemde belirgin kalınlıkta bırak.
            final periodDays = _periods[_selectedPeriodIdx].days;
            final activeBarWidth = periodDays <= 7
                ? 3.5
                : periodDays <= 30
                    ? 2.8
                    : periodDays <= 90
                        ? 2.2
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
                  final dateAtSpot = start.add(Duration(days: spot.x.toInt()));
                  final hasAddition = assets.any((a) =>
                      a.addedDate.year == dateAtSpot.year &&
                      a.addedDate.month == dateAtSpot.month &&
                      a.addedDate.day == dateAtSpot.day);
                  return hasAddition ||
                      spot.x == seg.spots.first.x ||
                      spot.x == seg.spots.last.x;
                },
                getDotPainter: (spot, percent, barData, index) {
                  // Tüm noktalar aynı marka rengi (amber) + beyaz halka.
                  // Alım/satış bilgisi renkte değil, dokunma tooltip'inde
                  // gösteriliyor.
                  final isFirst = spot.x == seg.spots.first.x;
                  final isLast = spot.x == seg.spots.last.x;
                  final radius = (isFirst || isLast) ? 5.5 : 4.5;
                  return FlDotCirclePainter(
                    radius: radius,
                    color: Sandik.amber,
                    strokeColor: Colors.white,
                    strokeWidth: 2,
                  );
                },
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
              getTooltipItems: (spots) {
                final tryFmt0 = NumberFormat.currency(
                    symbol: '₺', locale: 'tr_TR', decimalDigits: 0);
                // Primary segmentteki ilk ve son x — anchor / bugün tespiti.
                final firstX = primarySeg.spots.first.x;
                final lastX = primarySeg.spots.last.x;
                final firstY = primarySeg.spots.first.y;
                final lastY = primarySeg.spots.last.y;

                return spots.map((s) {
                  final date = start.add(Duration(days: s.x.toInt()));
                  final isFirst = s.x == firstX;
                  final isLast = s.x == lastX;

                  // O gün YAPILAN alım/satım hareketleri (Gerçek modda).
                  double dayBuyTRY = 0, daySellTRY = 0;
                  // İlk noktadan (anchor) bugüne kadar KÜMÜLATİF hareketler.
                  double cumBuyTRY = 0, cumSellTRY = 0;
                  if (!_simulate) {
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
                      style: GoogleFonts.dmSans(
                        color: Sandik.gold,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ];

                  // Bugün (son nokta) → getiri
                  if (isLast && !_simulate && gainVsAnchor.abs() > 0.5) {
                    final positive = gainVsAnchor >= 0;
                    children.add(TextSpan(
                      text:
                          '\nGetiri ${positive ? '+' : '−'}${tryFmt0.format(gainVsAnchor.abs())}',
                      style: GoogleFonts.dmSans(
                        color: positive ? Sandik.gain : Sandik.loss,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ));
                  }

                  // O gün yapılan hareketler
                  if (hasActivity) {
                    if (dayBuyTRY > 0) {
                      children.add(TextSpan(
                        text: '\nAlım  +${tryFmt0.format(dayBuyTRY)}',
                        style: GoogleFonts.dmSans(
                          color: Sandik.gain,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ));
                    }
                    if (daySellTRY > 0) {
                      children.add(TextSpan(
                        text: '\nSatış −${tryFmt0.format(daySellTRY)}',
                        style: GoogleFonts.dmSans(
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
                        style: GoogleFonts.dmSans(
                          color: dayNet >= 0 ? Sandik.gain : Sandik.loss,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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
                      style: GoogleFonts.dmSans(
                        color: Sandik.text58,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ));
                  }

                  return LineTooltipItem(
                    '${DateFormat('d MMM yyyy', 'tr_TR').format(date)}\n',
                    GoogleFonts.dmSans(
                        color: Sandik.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                    children: children,
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Sandik.gain, size: 20),
            const SizedBox(width: 12),
            Text('Güçlü sinyal yok — portföy nötr bölgede',
                style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text58)),
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
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Sandik.text36)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Sandik.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${results.length}',
                  style: GoogleFonts.dmSans(
                      fontSize: 11,
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
                borderRadius: BorderRadius.circular(14),
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
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(r.asset.displayTicker!,
                                        style: GoogleFonts.dmSans(
                                            fontSize: 11, fontWeight: FontWeight.w800, color: color, decoration: TextDecoration.none)),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(r.asset.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          decoration: TextDecoration.none)),
                                ),
                              ],
                            ),
                            Text(r.asset.type.label,
                                style: GoogleFonts.dmSans(
                                    fontSize: 11, color: Sandik.text36, decoration: TextDecoration.none)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(label,
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
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
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ind.name.split(' ').first,
                              style: GoogleFonts.dmSans(
                                  fontSize: 9,
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
                    style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text58),
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
