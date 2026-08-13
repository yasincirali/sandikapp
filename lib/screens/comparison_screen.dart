import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/portfolio_provider.dart';
import '../services/history_service.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Varlık karşılaştırma — "almadığım şey ne yapardı?"
///
/// Uygulamanın geri kalanı *"bende ne var"* sorusunu yanıtlar; bu ekran
/// **keşif** aracıdır: kullanıcı portföyünde OLMAYAN bir varlığı arayıp
/// elindekilerle aynı grafikte kıyaslar.
///
/// ## Neden yüzde, neden tutar değil
/// Sahip olunmayan bir varlık için alım fiyatı yoktur — "ne kadar
/// kazandın" tanımsızdır. Tanımlı tek ölçü dönem başına göre yüzde
/// değişimdir. Bu aynı zamanda ölçek sorununu da çözer: ₺12'lik bir hisse
/// ile ₺4.800'lük altın ancak normalize edilince aynı grafikte anlamlı
/// görünür. (bkz. [normalizeSeries])
class ComparisonScreen extends ConsumerStatefulWidget {
  /// Ekran açılırken seçili gelecek semboller — varlık detayından
  /// "bununla karşılaştır" akışı için.
  final List<String> initialTickers;

  const ComparisonScreen({super.key, this.initialTickers = const []});

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  /// Grafikte çizili semboller. Sıra korunur — renk ataması buna bağlı.
  final List<SymbolHit> _selected = [];

  /// Her sembolün normalize serisi. Sembol eklendiğinde doldurulur.
  final Map<String, NormalizedSeries> _series = {};

  /// Yüklenmekte olan semboller — satırda spinner göstermek için.
  final Set<String> _loading = {};

  /// Veri çekilemeyen semboller. Yahoo'dan gelen serbest sonuçlarda
  /// geçmiş boş olabilir; kullanıcı sebebini görmeli.
  final Set<String> _failed = {};

  int _periodIdx = 2;

  /// Periyotlar `getSymbolHistory`'nin range eşlemesiyle uyumlu seçildi.
  static const _periods = <({String label, int days})>[
    (label: '1H', days: 7),
    (label: '1A', days: 30),
    (label: '3A', days: 90),
    (label: '1Y', days: 365),
    (label: '5Y', days: 1825),
  ];

  /// Seri renkleri — marka paletinden, birbirinden ayırt edilebilir sırada.
  ///
  /// `gain`/`loss` BİLEREK kullanılmadı: bu grafikte yeşil/kırmızı "kâr/
  /// zarar" anlamına gelmez, yalnızca farklı varlıkları ayırır. Aynı renkleri
  /// kullanmak kullanıcıya yanlış anlam okutur.
  static List<Color> _seriesColors(SandikPalette p) => [
        p.amberFill,
        p.info,
        p.gold,
        const Color(0xFF9B8AFB),
        const Color(0xFF4DD0C7),
      ];

  @override
  void initState() {
    super.initState();
    // Detay ekranından gelen ön seçimler.
    if (widget.initialTickers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        for (final t in widget.initialTickers) {
          final hits = await SymbolSearchService.instance.search(t);
          final hit = hits.where((h) => h.ticker == t).firstOrNull;
          if (hit != null && mounted) _add(hit);
        }
      });
    }
  }

  Future<void> _add(SymbolHit hit) async {
    if (_selected.any((s) => s.ticker == hit.ticker)) return;
    // Beşten fazla seri grafiği okunamaz hale getirir; renk paleti de
    // beş renkte bitiyor.
    if (_selected.length >= 5) return;

    setState(() {
      _selected.add(hit);
      _loading.add(hit.ticker);
      _failed.remove(hit.ticker);
    });
    await _load(hit.ticker);
  }

  Future<void> _load(String ticker) async {
    final days = _periods[_periodIdx].days;
    final raw = await HistoryService.instance
        .getSymbolHistory(ticker, periodDays: days);
    final norm = normalizeSeries(raw);

    if (!mounted) return;
    setState(() {
      _loading.remove(ticker);
      if (norm == null) {
        _failed.add(ticker);
        _series.remove(ticker);
      } else {
        _failed.remove(ticker);
        _series[ticker] = norm;
      }
    });
  }

  void _remove(String ticker) {
    setState(() {
      _selected.removeWhere((s) => s.ticker == ticker);
      _series.remove(ticker);
      _loading.remove(ticker);
      _failed.remove(ticker);
    });
  }

  /// Periyot değişince TÜM seriler yeniden çekilir — normalize referansı
  /// (dönem başı) değiştiği için eski yüzdeler geçersizdir.
  Future<void> _changePeriod(int idx) async {
    setState(() {
      _periodIdx = idx;
      _series.clear();
      _loading.addAll(_selected.map((s) => s.ticker));
    });
    await Future.wait(_selected.map((s) => _load(s.ticker)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Karşılaştır'),
        backgroundColor: p.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _periodSelector(p),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _chartCard(p),
                  const SizedBox(height: 16),
                  _selectionList(p),
                  const SizedBox(height: 12),
                  _addButton(p),
                  const SizedBox(height: 16),
                  _disclaimer(p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Periyot seçici ────────────────────────────────────────────────────────

  Widget _periodSelector(SandikPalette p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _periods.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => _changePeriod(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: i == _periodIdx ? p.amberFill : Colors.transparent,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    _periods[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == _periodIdx ? p.onAmber : p.text58,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Grafik ────────────────────────────────────────────────────────────────

  Widget _chartCard(SandikPalette p) {
    if (_selected.isEmpty) return _emptyState(p);

    final ready = _series.entries.toList();
    if (ready.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: CircularProgressIndicator(color: p.amberFill),
        ),
      );
    }

    // Tüm serilerin ortak zaman ekseni: en erken ve en geç nokta.
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    final colors = _seriesColors(p);
    final bars = <LineChartBarData>[];

    for (final entry in ready) {
      final idx = _selected.indexWhere((s) => s.ticker == entry.key);
      if (idx < 0) continue;
      final keys = entry.value.points.keys.toList()..sort();
      final spots = <FlSpot>[];
      for (final k in keys) {
        final x = k.toDouble();
        final y = entry.value.points[k]!;
        spots.add(FlSpot(x, y));
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      bars.add(LineChartBarData(
        spots: spots,
        color: colors[idx % colors.length],
        barWidth: 2,
        isCurved: false,
        dotData: const FlDotData(show: false),
      ));
    }

    if (bars.isEmpty) return _emptyState(p);

    // Y ekseninde nefes payı; düz çizgide (minY == maxY) sıfıra bölme olmasın.
    final span = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);
    final pad = span * 0.12;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: context.surfaceCard(),
      height: 280,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY - pad,
          maxY: maxY + pad,
          lineBarsData: bars,
          // Sıfır çizgisi: "dönem başı" referansı görünür olmalı, yoksa
          // yüzdeler neye göre okunacağı belirsiz kalır.
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 0,
                color: p.text36.withValues(alpha: 0.4),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: p.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: p.text58),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => p.surface2,
              getTooltipItems: (spots) => spots.map((s) {
                final hit = _selected[s.barIndex % _selected.length];
                return LineTooltipItem(
                  '${hit.ticker}  ${fmtPct(s.y, digits: 1, showSign: true)}',
                  TextStyle(
                    color: colors[s.barIndex % colors.length],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(SandikPalette p) {
    return Container(
      height: 280,
      decoration: context.surfaceCard(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insights_rounded, size: 40, color: p.text36),
          const SizedBox(height: 12),
          Text('Karşılaştırmak için varlık ekleyin',
              style: TextStyle(color: p.text58, fontSize: 14)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Portföyünüzde olmayan varlıkları da ekleyebilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text36, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Seçili varlık listesi ─────────────────────────────────────────────────

  Widget _selectionList(SandikPalette p) {
    if (_selected.isEmpty) return const SizedBox.shrink();
    final colors = _seriesColors(p);
    final owned = _ownedTickers();

    return Column(
      children: [
        for (var i = 0; i < _selected.length; i++)
          _selectionRow(p, _selected[i], colors[i % colors.length],
              owned.contains(_selected[i].ticker)),
      ],
    );
  }

  Widget _selectionRow(
      SandikPalette p, SymbolHit hit, Color color, bool isOwned) {
    final norm = _series[hit.ticker];
    final isLoading = _loading.contains(hit.ticker);
    final isFailed = _failed.contains(hit.ticker);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: context.surfaceCard(),
      child: Row(
        children: [
          Container(width: 3, height: 30, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(hit.ticker,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.text90,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (isOwned) ...[
                      const SizedBox(width: 6),
                      // Kullanıcının sahip olduğu varlıklar işaretlenir:
                      // grafikte "benim" ile "olsaydı" ayrımı kritik.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.amberFill.withValues(alpha: 0.18),
                          borderRadius:
                              BorderRadius.circular(SandikRadius.sm),
                        ),
                        child: Text('Portföyümde',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: p.amberText)),
                      ),
                    ],
                  ],
                ),
                Text(hit.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text58, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isLoading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: p.amberFill),
            )
          else if (isFailed)
            Text('veri yok',
                style: TextStyle(color: p.text36, fontSize: 11))
          else if (norm != null)
            _returnBadge(p, norm.totalReturnPct),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: p.text36),
            onPressed: () => _remove(hit.ticker),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Getiri rozeti — yön renkle BİRLİKTE ok işareti taşır (renk körlüğü).
  Widget _returnBadge(SandikPalette p, double pct) {
    final isPos = pct >= 0;
    final color = isPos ? p.gain : p.loss;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isPos ? '▲' : '▼',
            style: TextStyle(color: color, fontSize: 9)),
        const SizedBox(width: 3),
        Text(
          fmtPct(pct.abs(), digits: 2),
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  /// Kullanıcının portföyündeki ticker'lar — "Portföyümde" rozeti için.
  Set<String> _ownedTickers() {
    final state = ref.read(portfolioProvider).valueOrNull;
    if (state == null) return const {};
    return state.activeAssets
        .map((a) => a.ticker.toUpperCase())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  // ── Ekleme ────────────────────────────────────────────────────────────────

  Widget _addButton(SandikPalette p) {
    final full = _selected.length >= 5;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: full ? null : _openSearch,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(full ? 'En fazla 5 varlık' : 'Varlık ekle'),
        style: OutlinedButton.styleFrom(
          foregroundColor: p.amberText,
          side: BorderSide(color: p.hairline),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final hit = await showModalBottomSheet<SymbolHit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SymbolSearchSheet(),
    );
    if (hit != null) await _add(hit);
  }

  Widget _disclaimer(SandikPalette p) {
    return Text(
      'Geçmiş performans gelecek getiri için gösterge değildir. '
      'Grafikteki değerler dönem başına göre yüzde değişimi gösterir; '
      'komisyon, vergi ve temettü dahil değildir.',
      style: TextStyle(color: p.text36, fontSize: 11, height: 1.4),
    );
  }
}

// ── Arama sayfası ───────────────────────────────────────────────────────────

/// Sembol arama alt sayfası — yerleşik listeler + Yahoo serbest arama.
class _SymbolSearchSheet extends StatefulWidget {
  const _SymbolSearchSheet();

  @override
  State<_SymbolSearchSheet> createState() => _SymbolSearchSheetState();
}

class _SymbolSearchSheetState extends State<_SymbolSearchSheet> {
  final _ctrl = TextEditingController();
  List<SymbolHit> _results = const [];
  bool _busy = false;

  /// Her tuş vuruşunda ağa çıkmamak için sorgu sayacı.
  ///
  /// Debounce yerine sayaç: kullanıcı hızlı yazarken eski isteğin GEÇ gelen
  /// yanıtı yenisinin üstünü ezmemeli (race). Sayaç uyuşmazsa sonuç atılır.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final mySeq = ++_seq;
    setState(() => _busy = true);
    final r = await SymbolSearchService.instance.search(q);
    if (!mounted || mySeq != _seq) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: p.surface1,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SandikRadius.lg)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: p.text20,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _search,
                style: TextStyle(color: p.text90),
                decoration: InputDecoration(
                  hintText: 'Hisse, fon, altın veya endeks ara',
                  hintStyle: TextStyle(color: p.text36, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: p.text58),
                  filled: true,
                  fillColor: p.overlay,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_busy) LinearProgressIndicator(color: p.amberFill, minHeight: 2),
            Expanded(
              child: _results.isEmpty && !_busy
                  ? Center(
                      child: Text('Sonuç bulunamadı',
                          style: TextStyle(color: p.text58)),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final h = _results[i];
                        return ListTile(
                          title: Text(h.ticker,
                              style: TextStyle(
                                  color: p.text90,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(h.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: p.text58, fontSize: 12)),
                          trailing: Text(h.source,
                              style: TextStyle(
                                  color: p.text36, fontSize: 11)),
                          onTap: () => Navigator.pop(context, h),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
