import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/history_service.dart';
import '../services/symbol_search_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/quick_adjust_dialog.dart';
import 'add_asset_screen.dart';

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

  /// Veri çekilemeyen semboller — ağ hatası ya da seçilen periyotta iki
  /// noktadan az veri. Kullanıcı boş bir çizgi yerine sebebini görmeli.
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

  /// Test kancası — arama sayfasını açmadan sembol eklemek için.
  ///
  /// Buton mantığı (Ekle vs Al/Sat) seriden bağımsızdır; testin ağ
  /// çağrısına ya da bottom sheet etkileşimine ihtiyacı yok.
  @visibleForTesting
  Future<void> addForTest(SymbolHit hit) => _add(hit);

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

    // Portföy serileri piyasada kote DEĞİLDİR — lot'lardan hesaplanır.
    // Bu yüzden sembol geçmişi yerine portföy geçmişi yolundan geçerler.
    final raw = PortfolioSeries.isPortfolio(ticker)
        ? await _loadPortfolioSeries(ticker, days)
        : await HistoryService.instance
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

  /// Portföy serisini lot'lardan hesaplar.
  ///
  /// `getPortfolioHistory` TL cinsinden TOPLAM DEĞER döner; [normalizeSeries]
  /// bunu dönem başına göre yüzdeye çevirir. Böylece portföy, tek bir hisse
  /// ile aynı düzlemde kıyaslanabilir.
  ///
  /// **Sahiplik sınırı korunur.** `PortfolioPerformanceScreen`'deki ile aynı
  /// kural: "Birlikte" görünümünde kendi lot'larım ile ortağınkiler AYNI
  /// listede akar ama `getPortfolioHistory` her lot'un kendi `addedDate` ve
  /// alım/satım geçmişini ayrı yorumlar. Burada ek bir aggregate YAPILMAZ —
  /// aynı ticker'ın iki sahipteki lot'unu tek havuzda toplamak kâr/zarar
  /// hesabını bozar (bkz. aggregatePositionsByOwner).
  Future<Map<int, double>> _loadPortfolioSeries(String ticker, int days) async {
    final pState = ref.read(portfolioProvider).valueOrNull;
    if (pState == null) return const {};

    final partnerMap =
        ref.read(allPartnerAssetsProvider).valueOrNull ?? const {};

    final List<Asset> assets;
    if (ticker == PortfolioSeries.mine) {
      assets = pState.assets;
    } else if (ticker == PortfolioSeries.together) {
      assets = [pState.assets, ...partnerMap.values].expand((l) => l).toList();
    } else {
      final pid = PortfolioSeries.partnerIdOf(ticker);
      assets = pid == null ? const [] : (partnerMap[pid] ?? const []);
    }

    // Mezar taşları ve yumuşak silinmiş lot'lar grafiğe girmez — silinen
    // varlık hiç olmamış sayılır (performans ekranındaki `keep` ile aynı).
    final active = assets.where((a) => a.isActive).toList();
    if (active.isEmpty) return const {};

    return HistoryService.instance.getPortfolioHistory(active, days);
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
          _selectionRow(
            p,
            _selected[i],
            colors[i % colors.length],
            // Portföy serilerine bu rozet takılmaz: "Portföyüm" satırına
            // "Portföyümde" yazmak anlamsız tekrar olurdu.
            !PortfolioSeries.isPortfolio(_selected[i].ticker) &&
                owned.contains(_selected[i].ticker),
          ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                          child: Text(_displayTicker(hit),
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
          _actionRow(p, hit),
        ],
      ),
    );
  }

  /// Satır altındaki işlem butonları.
  ///
  /// Portföy serilerinde gösterilmez — "Portföyüm"ü satın almak anlamsız.
  /// Sahip olunan varlıkta **Al / Sat**, olmayanda **Ekle** çıkar.
  Widget _actionRow(SandikPalette p, SymbolHit hit) {
    if (PortfolioSeries.isPortfolio(hit.ticker)) {
      return const SizedBox.shrink();
    }

    // Portföy henüz yüklenmediyse HİÇBİR buton gösterilmez.
    //
    // Düzeltilen hata: `valueOrNull` yükleme sırasında null döner ve
    // `_positionFor` da null verir — yani sahip OLUNAN bir varlıkta bile
    // "Portföyüme ekle" çıkıyordu. Kullanıcı ona basıp zaten sahip olduğu
    // varlık için ikinci bir kayıt açardı. Yükleme bitene kadar beklemek
    // yanlış butonu göstermekten iyidir.
    if (ref.watch(portfolioProvider).valueOrNull == null) {
      return const SizedBox.shrink();
    }

    final pos = _positionFor(hit.ticker);

    if (pos == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openAdd(hit),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Portföyüme ekle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.amberText,
              side: BorderSide(color: p.hairline),
              padding: const EdgeInsets.symmetric(vertical: 8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: _miniAction(
              label: 'Al',
              icon: Icons.trending_up_rounded,
              // Dolgu üstündeki mürekkep `onStatus` — `text90` renkli
              // zeminde iki temada da kırılıyor (bkz. charts_screen).
              background: p.gain,
              foreground: p.onStatus,
              onPressed: () => _openAdjust(pos, QuickAdjustMode.add),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniAction(
              label: 'Sat',
              icon: Icons.trending_down_rounded,
              background: p.loss.withValues(alpha: 0.85),
              foreground: p.onStatus,
              onPressed: () => _openAdjust(pos, QuickAdjustMode.remove),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction({
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Satırda gösterilecek etiket.
  ///
  /// Portföy serilerinin sanal ticker'ı (`PORTFOLIO:MINE`) kullanıcıya
  /// gösterilmez; TEFAS öneki de gereksiz gürültüdür — fon kodu yeter.
  String _displayTicker(SymbolHit hit) {
    if (hit.ticker == PortfolioSeries.mine) return 'Portföyüm';
    if (hit.ticker == PortfolioSeries.together) return 'Birlikte';
    if (PortfolioSeries.partnerIdOf(hit.ticker) != null) {
      return hit.name.split(' — ').first;
    }
    return hit.ticker.replaceFirst('TEFAS:', '');
  }

  /// Getiri rozeti — yön renkle BİRLİKTE ok işareti taşır (renk körlüğü).
  Widget _returnBadge(SandikPalette p, double pct) {
    final isPos = pct >= 0;
    final color = isPos ? p.gain : p.loss;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isPos ? '▲' : '▼', style: TextStyle(color: color, fontSize: 9)),
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

  /// Sembolden varlık türünü çıkarır — `AddAssetScreen` prefill'i için.
  ///
  /// Ticker formatı türü belli eder: `.IS` BIST hissesi, `TEFAS:` fon,
  /// `ALTIN_` altın ürünü, `TRY=X` döviz. Kalanlar (emtia vadelileri)
  /// emtia sayılır.
  static AssetType _typeOf(String ticker) {
    if (ticker.startsWith('TEFAS:')) return AssetType.fon;
    if (ticker.startsWith('ALTIN_')) return AssetType.altin;
    if (ticker.endsWith('TRY=X')) return AssetType.doviz;
    if (ticker.endsWith('.IS')) return AssetType.hisse;
    return AssetType.emtia;
  }

  /// Portföyde bu ticker'a ait pozisyon (varsa) — Al/Sat için gerekir.
  ///
  /// `aggregatePositions` kullanılır: al/sat lot'ları netlenir, böylece
  /// "Sat" diyaloğu doğru miktarı görür. Ortak lot'ları BURAYA girmez —
  /// kullanıcı yalnızca kendi pozisyonunu satabilir.
  Position? _positionFor(String ticker) {
    final state = ref.read(portfolioProvider).valueOrNull;
    if (state == null) return null;
    final mine = state.activeAssets
        .where((a) => a.ticker.toUpperCase() == ticker.toUpperCase())
        .toList();
    if (mine.isEmpty) return null;
    final positions = aggregatePositions(mine);
    if (positions.isEmpty) return null;
    // Aynı ticker tek pozisyona düşer; yine de net miktarı sıfır olan
    // (tamamı satılmış) pozisyon "sahip" sayılmamalı.
    final pos = positions.first;
    return pos.totalQuantity > 0 ? pos : null;
  }

  /// Portföyde olmayan varlığı ekleme akışı.
  ///
  /// Dönüşte seri YENİDEN ÇEKİLİR: kullanıcı varlığı eklediyse artık
  /// "Portföyümde" rozetini hak eder ve portföy serileri de değişmiştir.
  Future<void> _openAdd(SymbolHit hit) async {
    await Navigator.push(
      context,
      adaptiveRoute(
        builder: (_) => AddAssetScreen(
          prefillTicker: hit.ticker,
          prefillName: hit.name,
          prefillType: _typeOf(hit.ticker),
        ),
      ),
    );
    if (!mounted) return;
    // Portföy değişmiş olabilir → rozetler ve portföy serileri tazelensin.
    setState(() {});
    for (final s in _selected) {
      if (PortfolioSeries.isPortfolio(s.ticker)) {
        unawaited(_load(s.ticker));
      }
    }
  }

  /// Sahip olunan varlık için hızlı al/sat.
  Future<void> _openAdjust(Position pos, QuickAdjustMode mode) async {
    await showQuickAdjustDialog(
      context,
      ref,
      asset: pos.asDisplayAsset(),
      mode: mode,
    );
    if (!mounted) return;
    setState(() {});
    for (final s in _selected) {
      if (PortfolioSeries.isPortfolio(s.ticker)) {
        unawaited(_load(s.ticker));
      }
    }
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
      builder: (_) => _SymbolSearchSheet(portfolioOptions: _portfolioOptions()),
    );
    if (hit != null) await _add(hit);
  }

  /// Karşılaştırmaya eklenebilecek PORTFÖY serileri.
  ///
  /// Bunlar aranabilir semboller değil, hesaplanan serilerdir; bu yüzden
  /// arama sayfasının üstünde sabit bir bölüm olarak sunulurlar.
  /// "Birlikte" yalnızca ortak varsa görünür — tek başına kullanan biri
  /// için kendi portföyüyle aynı şeydir ve kafa karıştırır.
  List<SymbolHit> _portfolioOptions() {
    final out = <SymbolHit>[
      const SymbolHit(
        ticker: PortfolioSeries.mine,
        name: 'Tüm varlıklarımın toplam getirisi',
        source: 'Portföy',
      ),
    ];

    final partners = ref.read(activePartnersProvider);
    for (final p in partners) {
      out.add(SymbolHit(
        ticker: '${PortfolioSeries.partnerPrefix}${p.id}',
        name: '${p.displayName} — tüm portföyü',
        source: 'Ortak',
      ));
    }

    if (partners.isNotEmpty) {
      out.add(const SymbolHit(
        ticker: PortfolioSeries.together,
        name: 'Benim + ortaklarımın tümü',
        source: 'Portföy',
      ));
    }
    return out;
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
  /// Portföy serileri — aranmaz, listenin üstünde sabit durur.
  final List<SymbolHit> portfolioOptions;

  const _SymbolSearchSheet({this.portfolioOptions = const []});

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

  /// Portföy bölümü yalnızca sorgu boşken gösterilir.
  bool get _showPortfolio =>
      widget.portfolioOptions.isNotEmpty && _ctrl.text.trim().isEmpty;

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

  Widget _sectionLabel(SandikPalette p, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(
          text,
          style: TextStyle(
            color: p.text36,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _tile(SandikPalette p, SymbolHit h, {bool isPortfolio = false}) {
    return ListTile(
      leading: isPortfolio
          ? Icon(Icons.account_balance_wallet_rounded,
              size: 20, color: p.amberText)
          : null,
      title: Text(
        // Portföy serilerinde sanal ticker (PORTFOLIO:MINE) kullanıcıya
        // gösterilmez — anlamsız bir teknik dize olurdu.
        isPortfolio ? _portfolioTitle(h) : h.ticker,
        style: TextStyle(
            color: p.text90, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(h.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.text58, fontSize: 12)),
      trailing: Text(h.source, style: TextStyle(color: p.text36, fontSize: 11)),
      onTap: () => Navigator.pop(context, h),
    );
  }

  String _portfolioTitle(SymbolHit h) {
    if (h.ticker == PortfolioSeries.mine) return 'Portföyüm';
    if (h.ticker == PortfolioSeries.together) return 'Birlikte';
    // Ortak: adı `name` alanının ilk parçasında ("Ayşe — tüm portföyü").
    return h.name.split(' — ').first;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            if (_busy)
              LinearProgressIndicator(color: p.amberFill, minHeight: 2),
            Expanded(
              child: _results.isEmpty && !_busy && !_showPortfolio
                  ? Center(
                      child: Text('Sonuç bulunamadı',
                          style: TextStyle(color: p.text58)),
                    )
                  : ListView(
                      children: [
                        // Portföy serileri yalnızca arama BOŞKEN görünür:
                        // kullanıcı bir şey yazdığında sonuçların üstünü
                        // işgal etmemeli.
                        if (_showPortfolio) ...[
                          _sectionLabel(p, 'PORTFÖYLER'),
                          for (final h in widget.portfolioOptions)
                            _tile(p, h, isPortfolio: true),
                          if (_results.isNotEmpty)
                            _sectionLabel(p, 'VARLIKLAR'),
                        ],
                        for (final h in _results) _tile(p, h),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
