import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, CircularProgressIndicator, RefreshIndicator, TextStyle;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/tefas_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import 'performance_screen.dart';
import 'portfolio_performance_screen.dart';
import 'portfolio_detail_screen.dart';

class ChartsScreen extends ConsumerStatefulWidget {
  const ChartsScreen({super.key});

  @override
  ConsumerState<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends ConsumerState<ChartsScreen> {
  String? _view = ''; // null = Birlikte, '' = Ben, uuid = ortak

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);

    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20, color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Portföy',
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) =>
                              PortfolioPerformanceScreen(initialView: _view)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.show_chart_rounded,
                          color: Sandik.amber, size: 24),
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) =>
                              PortfolioDetailScreen(initialView: _view)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.analytics_outlined,
                          color: Sandik.text36, size: 24),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SandikLogoutButton(
                    onPressed: () => confirmAndLogout(context, ref),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: pStateAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: Sandik.amber)),
                error: (e, _) => Center(
                    child: Text('Hata: $e',
                        style: const TextStyle(color: Colors.white))),
                data: (pState) => RefreshIndicator(
                  color: Sandik.amber,
                  onRefresh: () =>
                      ref.read(portfolioProvider.notifier).refreshPrices(),
                  child: ListView(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                    children: [
                      if (activePartners.isNotEmpty)
                        ModernTabSelector(
                          partners: activePartners,
                          selectedId: _view,
                          onChanged: (v) => setState(() => _view = v),
                        ),
                      const SizedBox(height: 24),

                      // Verileri birleştir
                      partnerAssetsAsync.when(
                        loading: () => const Center(
                            child:
                                CircularProgressIndicator(color: Sandik.amber)),
                        error: (e, _) => Center(child: Text('Hata: $e')),
                        data: (partnerMap) {
                          List<Asset> assets = [];
                          if (_view == '') {
                            assets = pState.assets;
                          } else if (_view != null) {
                            assets = partnerMap[_view] ?? [];
                          } else {
                            // Birlikte
                            assets = [...pState.assets];
                            for (final list in partnerMap.values) {
                              assets.addAll(list);
                            }
                          }

                          if (assets.isEmpty) {
                            return const _EmptyState();
                          }

                          return Column(
                            children: [
                              _DonutSection(assets: assets, pState: pState),
                              const SizedBox(height: 32),
                              _AssetList(
                                  assets: assets,
                                  pState: pState,
                                  onTap: (a) => Navigator.push(
                                        context,
                                        CupertinoPageRoute(
                                            builder: (_) =>
                                                PerformanceScreen(asset: a)),
                                      )),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_rounded, size: 64, color: Sandik.text36),
          const SizedBox(height: 16),
          Text('Henüz varlık eklenmemiş',
              style: GoogleFonts.dmSans(color: Sandik.text36)),
        ],
      ),
    );
  }
}

// ── Donut Section (wrapper — varlık tipi + aracı kuruluş toggle) ─────────────

class _DonutSection extends StatefulWidget {
  final List<Asset> assets;
  final PortfolioState pState;

  const _DonutSection({required this.assets, required this.pState});

  @override
  State<_DonutSection> createState() => _DonutSectionState();
}

class _DonutSectionState extends State<_DonutSection> {
  bool _byManager = false; // false = varlık tipi, true = aracı kuruluş

  @override
  Widget build(BuildContext context) {
    final hasFunds = widget.assets.any((a) => a.type == AssetType.fon);

    return Column(
      children: [
        if (hasFunds) ...[
          _DonutToggle(
            byManager: _byManager,
            onChanged: (v) => setState(() => _byManager = v),
          ),
          const SizedBox(height: 20),
        ],
        if (_byManager && hasFunds)
          _ManagerDonut(assets: widget.assets, pState: widget.pState)
        else
          _AssetTypeDonut(assets: widget.assets, pState: widget.pState),
      ],
    );
  }
}

// ── Toggle ────────────────────────────────────────────────────────────────────

class _DonutToggle extends StatelessWidget {
  final bool byManager;
  final ValueChanged<bool> onChanged;
  const _DonutToggle({required this.byManager, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleItem('Varlık Tipi', !byManager, () => onChanged(false)),
          _toggleItem('Aracı Kuruluş', byManager, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Sandik.amber.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: active
              ? Border.all(color: Sandik.amber.withValues(alpha: 0.4))
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Sandik.amber : Sandik.text36,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Varlık Tipi Donut ─────────────────────────────────────────────────────────

class _AssetTypeDonut extends StatelessWidget {
  final List<Asset> assets;
  final PortfolioState pState;

  const _AssetTypeDonut({required this.assets, required this.pState});

  @override
  Widget build(BuildContext context) {
    final totals = <AssetType, double>{};
    double totalVal = 0;
    for (final a in assets) {
      final val = pState.toTRY(a.totalValue, a.currency);
      totals[a.type] = (totals[a.type] ?? 0) + val;
      totalVal += val;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Formatlama: Milyon TL desteği için
    String formattedTotal;
    if (totalVal >= 1000000) {
      formattedTotal =
          '${(totalVal / 1000000).toStringAsFixed(2).replaceAll('.', ',')} mn ₺';
    } else {
      final fmt = NumberFormat.compactCurrency(
          locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
      formattedTotal = fmt.format(totalVal).toLowerCase();
    }

    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            children: [
              PieChart(
                PieChartData(
                  sections: sorted.map((e) {
                    return PieChartSectionData(
                      color: e.key.color,
                      value: e.value,
                      radius: 20,
                      showTitle: false,
                    );
                  }).toList(),
                  sectionsSpace: 4,
                  centerSpaceRadius: 60,
                  startDegreeOffset: -90,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formattedTotal,
                          style: GoogleFonts.dmSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Sandik.gold,
                          ),
                        ),
                      ),
                      Text(
                        'toplam',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: Sandik.text36,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: sorted.map((e) {
            final pct = (e.value / (totalVal > 0 ? totalVal : 1) * 100)
                .toStringAsFixed(0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: e.key.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.key.label} %$pct',
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: Sandik.text58,
                      fontWeight: FontWeight.w500),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Aracı Kuruluş Donut ───────────────────────────────────────────────────────

class _ManagerDonut extends StatefulWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  const _ManagerDonut({required this.assets, required this.pState});

  @override
  State<_ManagerDonut> createState() => _ManagerDonutState();
}

class _ManagerDonutState extends State<_ManagerDonut> {
  // fonKodu → managerName cache (TefasService'ten lazy yüklenir)
  Map<String, String>? _managerCache;
  bool _loading = true;

  // Aracı kuruluş renklerini deterministik üret
  static const _palette = [
    Color(0xFFF5A623), Color(0xFF2D9E6C), Color(0xFF4A90D9),
    Color(0xFFE8503A), Color(0xFFF5C842), Color(0xFF9B59B6),
    Color(0xFF1ABC9C), Color(0xFFE67E22), Color(0xFF3498DB),
    Color(0xFFE74C3C), Color(0xFF2ECC71), Color(0xFF8E44AD),
  ];

  @override
  void initState() {
    super.initState();
    _loadManagers();
  }

  Future<void> _loadManagers() async {
    final funds = await TefasService.instance.fetchAllFunds();
    final map = <String, String>{
      for (final f in funds) f.code: f.managerName,
    };
    if (mounted) setState(() { _managerCache = map; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: Sandik.amber, strokeWidth: 2)),
      );
    }

    // Sadece fon varlıklarını al
    final fonAssets = widget.assets.where((a) => a.type == AssetType.fon).toList();
    if (fonAssets.isEmpty) return const SizedBox.shrink();

    // Aracı kuruluşa göre grupla
    final totals = <String, double>{};
    double totalVal = 0;
    for (final a in fonAssets) {
      final code = a.ticker.replaceFirst('TEFAS:', '');
      final manager = _managerCache?[code] ?? _parseManagerFromName(a.name);
      final val = widget.pState.toTRY(a.totalValue, a.currency);
      totals[manager] = (totals[manager] ?? 0) + val;
      totalVal += val;
    }

    if (totals.isEmpty) return const SizedBox.shrink();

    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    Color colorFor(int i) => _palette[i % _palette.length];

    String formattedTotal;
    if (totalVal >= 1000000) {
      formattedTotal = '${(totalVal / 1000000).toStringAsFixed(2).replaceAll('.', ',')} mn ₺';
    } else {
      formattedTotal = NumberFormat.compactCurrency(
              locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
          .format(totalVal)
          .toLowerCase();
    }

    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            children: [
              PieChart(
                PieChartData(
                  sections: sorted.asMap().entries.map((e) => PieChartSectionData(
                        color: colorFor(e.key),
                        value: e.value.value,
                        radius: 20,
                        showTitle: false,
                      )).toList(),
                  sectionsSpace: 4,
                  centerSpaceRadius: 60,
                  startDegreeOffset: -90,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formattedTotal,
                          style: GoogleFonts.dmSans(
                              fontSize: 24, fontWeight: FontWeight.w700, color: Sandik.gold),
                        ),
                      ),
                      Text('fon toplam',
                          style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Aracı kuruluş listesi
        ...sorted.asMap().entries.map((e) {
          final pct = (e.value.value / (totalVal > 0 ? totalVal : 1) * 100);
          final color = colorFor(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.value.key,
                    style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text58, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '%${pct.toStringAsFixed(1)}',
                  style: GoogleFonts.dmSans(fontSize: 13, color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // TEFAS cache'te yoksa fon adından şirketi tahmin et
  static String _parseManagerFromName(String name) {
    final keywords = ['PORTFÖY', 'VARLIK', 'YATIRIM', 'MENKUL'];
    final parts = name.toUpperCase().split(RegExp(r'\s+'));
    for (int i = 0; i < parts.length; i++) {
      if (keywords.contains(parts[i])) return parts.sublist(0, i + 1).join(' ');
    }
    return parts.take(2).join(' ');
  }
}

// ── Asset List ────────────────────────────────────────────────────────────────

class _AssetList extends StatelessWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  final void Function(Asset) onTap;

  const _AssetList(
      {required this.assets, required this.pState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: assets
          .map((a) => _AssetCard(a: a, pState: pState, onTap: onTap))
          .toList(),
    );
  }
}

// ── Asset Card ────────────────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final Asset a;
  final PortfolioState pState;
  final void Function(Asset) onTap;

  const _AssetCard(
      {required this.a, required this.pState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final isPos = a.gainLossPercentage >= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: () => onTap(a),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              a.currencySymbol != null
                  ? Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: a.type.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          a.currencySymbol!,
                          style: GoogleFonts.dmSans(
                            fontSize: a.currencySymbol!.length > 1 ? 9 : 13,
                            fontWeight: FontWeight.w800,
                            color: a.type.color,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : Icon(a.type.icon, color: a.type.color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (a.showTicker) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: a.type.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              a.displayTicker!,
                              style: GoogleFonts.dmSans(
                                  fontSize: 11, fontWeight: FontWeight.w800, color: a.type.color),
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${a.quantity.toStringAsFixed(0)} lot · ${a.type.label}',
                      style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tryFmt.format(pState.toTRY(a.totalValue, a.currency)),
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isPos
                            ? Icons.arrow_drop_up_rounded
                            : Icons.arrow_drop_down_rounded,
                        color: isPos ? Sandik.gain : Sandik.loss,
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '%${a.gainLossPercentage.abs().toStringAsFixed(1)}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPos ? Sandik.gain : Sandik.loss,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
