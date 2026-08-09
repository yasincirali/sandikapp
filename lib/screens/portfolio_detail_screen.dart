import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/custom_loading_indicator.dart';

class PortfolioDetailScreen extends ConsumerStatefulWidget {
  final String? initialView;
  const PortfolioDetailScreen({super.key, this.initialView});

  @override
  ConsumerState<PortfolioDetailScreen> createState() =>
      _PortfolioDetailScreenState();
}

class _PortfolioDetailScreenState extends ConsumerState<PortfolioDetailScreen> {
  late String? _view;
  int _selectedPeriodIdx = 0; // 1H

  /// Son başarılı grafik verisi — stale-while-revalidate.
  ///
  /// Dönem (1H → 1A) veya sekme değiştiğinde `FutureBuilder` yeni bir future'a
  /// geçer ve `snapshot.data` bir frame boyunca null olur. Bunu doğrudan
  /// gösterirsek grafik yerini spinner'a bırakır: kullanıcı her dönem
  /// dokunuşunda çizimin kaybolup geri gelmesini görür. Bunun yerine ESKİ
  /// seriyi ekranda tutup üzerine ince bir "yenileniyor" göstergesi koyuyoruz —
  /// layout zıplamaz, kullanıcı bağlamını kaybetmez.
  Map<int, double>? _lastHistory;

  /// Geçmiş future'ını memoize et.
  ///
  /// `FutureBuilder`'a build içinde doğrudan `getPortfolioHistory(...)`
  /// verilirse HER rebuild (sekme çipi, provider tick'i, fiyat güncellemesi)
  /// yeni bir future — dolayısıyla yeni bir ağ turu — doğurur ve FutureBuilder
  /// bunu `waiting` sayıp grafiği söker. Aynı (varlık kümesi + dönem) için
  /// aynı future yeniden kullanılır; yalnızca gerçekten değiştiğinde yenilenir.
  /// Aynı düzeltme `portfolio_performance_screen`'de de uygulanmıştır.
  Future<Map<int, double>>? _historyFuture;
  String? _historyKey;

  /// Bayat seriyi yeni dönem penceresine kırp. Sınır noktaları dahildir.
  static Map<int, double> _clipToWindow(
      Map<int, double> raw, DateTime from, DateTime to) {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    return {
      for (final e in raw.entries)
        if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
    };
  }

  Future<Map<int, double>> _history(List<Asset> targetAssets, int days) {
    final key = '$days|${targetAssets.map((a) => a.id).join(',')}';
    if (_historyKey == key && _historyFuture != null) return _historyFuture!;
    _historyKey = key;
    _historyFuture =
        HistoryService.instance.getPortfolioHistory(targetAssets, days);
    return _historyFuture!;
  }

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

  // ── Logic ─────────────────────────────────────────────────────────────────

  /// UK3 fix: Sahte simülasyon (`_getSimulatedPrice` ile %40-70 yıllık return
  /// varsayan yapay grafik) kaldırıldı. Yatırım uygulamasında uydurma
  /// performans verisi göstermek yanıltıcı ve yasal sorun yaratabilir.
  /// Bunun yerine `HistoryService.getPortfolioHistory` ile gerçek snapshot
  /// + canlı fiyat verisini kullanıyoruz. Yeterli veri yoksa empty state.
  List<TransactionSegment> _buildSegmentsFromHistory(
    Map<int, double> historyMap,
    DateTime startDate,
  ) {
    if (historyMap.isEmpty) return [];
    final entries = historyMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final spots = <FlSpot>[];
    for (final entry in entries) {
      final ts = DateTime.fromMillisecondsSinceEpoch(entry.key);
      final x = ts.difference(startDate).inDays.toDouble();
      if (x < 0) continue;
      spots.add(FlSpot(x, entry.value));
    }
    if (spots.length < 2) return [];
    return [
      TransactionSegment(
        spots: spots,
        lineColor: context.c.amberText,
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ),
    ];
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
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: context.c.text90),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Detaylı Portföy Analizi',
            style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: context.c.text90)),
      ),
      body: pStateAsync.when(
        loading: () => const SandikLoadingScreen(),
        error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
        data: (pState) => partnerAssetsAsync.when(
          loading: () => const SandikLoadingScreen(),
          error: (e, _) => SandikErrorView(error: e, onRetry: () => ref.invalidate(portfolioProvider)),
          data: (partnerMap) {
            // Sahiplik sınırı korunmalı — bkz. aggregatePositionsByOwner.
            // Tüm ortakların lot'ları tek havuzda toplanırsa aynı hisseye
            // sahip iki kişi tek pozisyona düşer ve kategori dağılımı ile
            // kâr/zarar tekil sekmelerle tutarsız olur.
            final List<List<Asset>> ownerLots;
            if (_view == '') {
              ownerLots = [pState.assets];
            } else if (_view != null) {
              ownerLots = [partnerMap[_view] ?? const []];
            } else {
              ownerLots = [pState.assets, ...partnerMap.values];
            }
            // Grafik geçmişi ham ledger ister (HistoryService buy/sell
            // tarihlerini kendisi yorumlar), dağılım ise net pozisyon.
            final targetAssets = [for (final l in ownerLots) ...l];
            final positionedAssets = aggregatePositionsByOwner(ownerLots)
                .map((p) => p.asDisplayAsset())
                .toList();

            return FutureBuilder<Map<int, double>>(
              future:
                  _history(targetAssets, _periods[_selectedPeriodIdx].days),
              builder: (context, snap) {
                if (snap.hasData) _lastHistory = snap.data;
                final busy = snap.connectionState == ConnectionState.waiting;
                // Yeni dönem yüklenirken eski seriyi göstermeye devam et.
                // KRİTİK: bayat seri YENİ pencereye kırpılmalı. 1Y → 1A
                // geçişinde eski seri `startDate`'ten önceki noktaları da
                // içerir; kırpmazsak grafik negatif X'e çizilir, eksen kayar
                // ve çizgi sola taşar. Aynı kural `stale_window_clip_test`
                // içinde davranış olarak sabitlenmiştir.
                final Map<int, double> historyMap;
                if (snap.data != null) {
                  historyMap = snap.data!;
                } else {
                  final stale = _lastHistory;
                  final clipped = stale == null
                      ? const <int, double>{}
                      : _clipToWindow(stale, startDate, endDate);
                  // Tek nokta çizgi yapmaz — o durumda spinner daha dürüst.
                  historyMap =
                      clipped.length >= 2 ? clipped : const <int, double>{};
                }
                final segments =
                    _buildSegmentsFromHistory(historyMap, startDate);
                // Spinner SADECE gösterilecek hiçbir veri yokken (ilk açılış).
                final loading = busy && segments.isEmpty;

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
                    if (loading)
                      const SizedBox(
                        height: 300,
                        child: CustomLoadingView(),
                      )
                    else if (segments.isEmpty)
                      _buildEmptyChartState(targetAssets.isEmpty)
                    else
                      // Bayat seri gösterilirken hafifçe soluklaştır: veri
                      // tazeleniyor sinyali verir ama grafiği kaldırmaz.
                      AnimatedOpacity(
                        opacity: busy ? 0.45 : 1.0,
                        duration: SandikMotion.stateOf(context),
                        curve: SandikMotion.enter,
                        child: _buildChartSection(
                            segments, startDate, endDate, targetAssets),
                      ),
                    const SizedBox(height: 32),
                    const _SectionTitle('KATEGORİ DAĞILIMI'),
                    const SizedBox(height: 16),
                    _buildCategoryBreakdown(positionedAssets, pState),
                    const SizedBox(height: 32),
                    if (_view == null && activePartners.isNotEmpty) ...[
                      const _SectionTitle('ORTAKLAR'),
                      const SizedBox(height: 16),
                      _buildPartnerBreakdown(
                          pState, partnerMap, activePartners),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// UK3 empty state: gerçek snapshot verisi yetersizse veya hiç varlık
  /// yoksa kullanıcıya sahte trend gösterme — açıkça "yeterli veri yok" de.
  Widget _buildEmptyChartState(bool noAssets) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded,
                size: 36, color: context.c.text36),
            const SizedBox(height: 12),
            Text(
              noAssets ? 'Henüz varlığın yok' : 'Yeterli veri yok',
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.c.text90,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              noAssets
                  ? 'Varlık ekledikçe performans grafiğin oluşacak.'
                  : 'Birkaç günlük veri biriktikten sonra grafiğin oluşacak.',
              textAlign: TextAlign.center,
              style: context.t.titleSmall?.copyWith(
                color: context.c.text58,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
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
                        ? context.c.surface2
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(SandikRadius.sm)),
                child: Center(
                    child: Text(_periods[i].label,
                        style: context.t.bodyMedium?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? context.c.amberText : context.c.text36))),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChartSection(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets) {
    if (segments.isEmpty) {
      return const SizedBox(
          height: 200, child: Center(child: Text('Veri yok')));
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
    // Tek-nokta veride padding=0 → minY==maxY → fl_chart assert crash.
    // En az 1.0 padding garanti ediyoruz.
    double yPadding = ((maxY - minY) * 0.2).clamp(1.0, double.infinity);
    maxY += yPadding;
    minY = (minY - yPadding).clamp(0, double.infinity);
    final maxX =
        end.difference(start).inDays.toDouble().clamp(1.0, double.infinity);

    return Container(
      height: 300,
      padding: const EdgeInsets.fromLTRB(0, 24, 16, 12),
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          border: Border.all(color: context.c.hairline)),
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
                            style: TextStyle(
                                color: context.c.text36, fontSize: 10))))),
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
                            style: TextStyle(
                                color: context.c.text36, fontSize: 10)))),
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
                  color: context.c.amberText,
                  strokeColor: context.c.background,
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
                  getTooltipColor: (_) => context.c.surface2,
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                          NumberFormat.currency(
                                  symbol: '₺',
                                  locale: 'tr_TR',
                                  decimalDigits: 0)
                              .format(s.y),
                          TextStyle(
                              color: context.c.text90,
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
            fmtPct(e.value / (totalVal > 0 ? totalVal : 1) * 100, digits: 1);
        return _breakdownTile(e.key.label, e.value, pct, e.key.color);
      }).toList(),
    );
  }

  Widget _buildPartnerBreakdown(PortfolioState myState,
      Map<String, List<Asset>> partnerMap, List<AppUser> partners) {
    // Her sahibin NET pozisyon değeri — ham lot toplamı satışları da pozitif
    // sayardı ve "Ben" satırı (net) ortak satırlarıyla (brüt) kıyaslanamazdı.
    double ownerValue(List<Asset> lots) => ownerScopedTotalValue(
          [lots],
          toTRY: myState.toTRY,
        );

    final myTotal = ownerValue(myState.assets);
    double totalAll = myTotal;
    for (final list in partnerMap.values) {
      totalAll += ownerValue(list);
    }

    return Column(
      children: [
        _breakdownTile(
            'Ben',
            myTotal,
            fmtPct(myTotal / (totalAll > 0 ? totalAll : 1) * 100, digits: 1),
            context.c.amberText),
        ...partners.map((p) {
          final pTotal = ownerValue(partnerMap[p.id] ?? const []);
          return _breakdownTile(
              p.displayName,
              pTotal,
              fmtPct(pTotal / (totalAll > 0 ? totalAll : 1) * 100, digits: 1),
              context.c.gain);
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
          color: context.c.surface1, borderRadius: BorderRadius.circular(SandikRadius.md)),
      child: Row(
        children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 16),
          Expanded(
              child: Text(label,
                  style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.c.text90))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(val),
                  style: context.t.numSmall.copyWith(
                      fontSize: 14,
                      color: context.c.text90)),
              Text(pct,
                  style: context.t.numSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.c.text36)),
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
      style: context.t.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: context.c.text58));
}
