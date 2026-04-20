import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../services/database_service.dart';
import '../services/history_service.dart';
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

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Portföy',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart_rounded, color: Sandik.amber),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PortfolioPerformanceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Sandik.text36),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PortfolioDetailScreen(initialView: _view)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: pStateAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Sandik.amber)),
        error: (e, _) => Center(
            child:
                Text('Hata: $e', style: const TextStyle(color: Colors.white))),
        data: (pState) => RefreshIndicator(
          color: Sandik.amber,
          onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
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
                    child: CircularProgressIndicator(color: Sandik.amber)),
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
                    return _buildEmptyState();
                  }

                  return Column(
                    children: [
                      _buildDonutSection(assets, pState),
                      const SizedBox(height: 32),
                      _buildAssetList(assets, pState),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 64, color: Sandik.text36),
          const SizedBox(height: 16),
          Text('Henüz varlık eklenmemiş',
              style: GoogleFonts.inter(color: Sandik.text36)),
        ],
      ),
    );
  }

  Widget _buildDonutSection(List<Asset> assets, PortfolioState pState) {
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
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Sandik.gold,
                          ),
                        ),
                      ),
                      Text(
                        'toplam',
                        style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
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

  Widget _buildAssetList(List<Asset> assets, PortfolioState pState) {
    return Column(
      children: assets.map((a) => _buildAssetCard(a, pState)).toList(),
    );
  }

  Widget _buildAssetCard(Asset a, PortfolioState pState) {
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final isPos = a.gainLossPercentage >= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PerformanceScreen(asset: a)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: a.type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    a.name.substring(0, min(2, a.name.length)).toUpperCase(),
                    style: TextStyle(
                        color: a.type.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${a.quantity.toStringAsFixed(0)} lot',
                      style:
                          GoogleFonts.inter(fontSize: 12, color: Sandik.text36),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tryFmt.format(pState.toTRY(a.totalValue, a.currency)),
                    style: GoogleFonts.plusJakartaSans(
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
                        size: 20,
                      ),
                      Text(
                        '%${a.gainLossPercentage.abs().toStringAsFixed(1)}',
                        style: GoogleFonts.inter(
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
