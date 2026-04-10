import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../providers/portfolio_provider.dart';
import '../widgets/asset_row_widget.dart';
import '../widgets/portfolio_summary_widget.dart';
import 'add_asset_screen.dart';
import 'asset_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _search = '';
  AssetType? _filter;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Asset> _filtered(List<Asset> assets) => assets.where((a) {
        final matchType = _filter == null || a.type == _filter;
        final q = _search.toLowerCase();
        final matchSearch = q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.ticker.toLowerCase().contains(q);
        return matchType && matchSearch;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(portfolioProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portföyüm'),
        centerTitle: false,
        actions: [
          asyncState.whenOrNull(
                data: (s) => IconButton(
                  tooltip: 'Fiyatları Güncelle',
                  icon: s.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onPressed: s.isLoading
                      ? null
                      : () =>
                          ref.read(portfolioProvider.notifier).refreshPrices(),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: _buildBody,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pushAdd(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildBody(PortfolioState s) {
    final filtered = _filtered(s.assets);

    return RefreshIndicator(
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        slivers: [
          // Summary card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PortfolioSummaryWidget(state: s),
            ),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SearchBar(
                controller: _searchCtrl,
                hintText: 'Varlık veya sembol ara...',
                leading: const Icon(Icons.search_rounded),
                trailing: _search.isNotEmpty
                    ? [
                        IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                        )
                      ]
                    : null,
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ),

          // Filter chips
          SliverToBoxAdapter(child: _filterChips()),

          // Asset list or empty state
          if (filtered.isEmpty)
            SliverFillRemaining(
                hasScrollBody: false, child: _emptyState(s))
          else
            SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (ctx, i) => AssetRowWidget(
                asset: filtered[i],
                state: s,
                onTap: () => _pushDetail(ctx, filtered[i]),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _chip('Tümü', null, Colors.blue),
          ...AssetType.values.map((t) => _chip(t.label, t, t.color)),
        ],
      ),
    );
  }

  Widget _chip(String label, AssetType? type, Color color) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: color,
        showCheckmark: false,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        backgroundColor: color.withValues(alpha: 0.1),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: selected ? Colors.white : color,
        ),
        onSelected: (_) =>
            setState(() => _filter = selected ? null : type),
      ),
    );
  }

  Widget _emptyState(PortfolioState s) {
    final hasFilter = _search.isNotEmpty || _filter != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            hasFilter ? 'Sonuç bulunamadı' : 'Henüz varlık eklenmedi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _pushAdd(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('İlk varlığı ekle'),
            ),
          ],
        ],
      ),
    );
  }

  void _pushAdd(BuildContext ctx) => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const AddAssetScreen()),
      );

  void _pushDetail(BuildContext ctx, Asset asset) => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => AssetDetailScreen(asset: asset)),
      );
}
