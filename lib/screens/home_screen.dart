import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/database_service.dart';
import '../widgets/portfolio_summary_widget.dart';
import 'add_asset_screen.dart';
import 'asset_detail_screen.dart';
import 'charts_screen.dart';
import 'profile_screen.dart';

// Ortak portföy provider — seçilen partner'ın varlıklarını yükler
final _partnerAssetsProvider =
    FutureProvider.family<List<Asset>, String>((ref, partnerId) {
  return DatabaseService.instance.fetchByUser(partnerId);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _search = '';
  AssetType? _filter;
  final _searchCtrl = TextEditingController();

  // Ortak görünüm — null = bireysel, dolu = seçili partner id
  String? _selectedPartnerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(portfolioProvider.notifier).refreshPrices();
    });
  }

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
    final cs = Theme.of(context).colorScheme;

    final user = ref.watch(authProvider).valueOrNull;
    final partners = ref.watch(partnersProvider).valueOrNull ?? [];
    final hasPartners = partners.isNotEmpty;

    // Ortak görünümde partner'ın varlıklarını yükle
    final partnerAssetsAsync = _selectedPartnerId != null
        ? ref.watch(_partnerAssetsProvider(_selectedPartnerId!))
        : null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: _selectedPartnerId == null
            ? const Text('Portföy')
            : Text(
                '${partners.firstWhere((p) => p.id == _selectedPartnerId, orElse: () => AppUser(id: '', email: '', displayName: 'Ortak', passwordHash: '', createdAt: DateTime.now())).displayName} + Ben',
              ),
        actions: [
          IconButton(
            tooltip: 'Performans Grafikleri',
            icon: Icon(Icons.bar_chart_rounded, color: cs.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChartsScreen()),
            ),
          ),
          asyncState.whenOrNull(
                data: (s) => IconButton(
                  tooltip: 'Fiyatları Güncelle',
                  icon: s.isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.primary),
                        )
                      : Icon(Icons.refresh_rounded, color: cs.primary),
                  onPressed: s.isLoading
                      ? null
                      : () =>
                          ref.read(portfolioProvider.notifier).refreshPrices(),
                ),
              ) ??
              const SizedBox.shrink(),
          // Profil butonu
          if (user != null)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Ortak seçici — sadece partner varsa göster
          if (hasPartners)
            _PartnerSelector(
              partners: partners,
              selectedPartnerId: _selectedPartnerId,
              onChanged: (id) => setState(() => _selectedPartnerId = id),
              cs: cs,
            ),
          Expanded(
            child: asyncState.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: cs.primary),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: cs.error.withValues(alpha: 0.6)),
                    const SizedBox(height: 12),
                    Text('Hata: $e',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              data: (myState) {
                if (_selectedPartnerId == null) return _buildBody(myState);
                // Ortak görünümü
                return partnerAssetsAsync!.when(
                  loading: () =>
                      Center(child: CircularProgressIndicator(color: cs.primary)),
                  error: (e, _) => Center(child: Text(e.toString())),
                  data: (partnerAssets) {
                    final combined = PortfolioState(
                      assets: [...myState.assets, ...partnerAssets],
                      usdTry: myState.usdTry,
                      eurTry: myState.eurTry,
                      gbpTry: myState.gbpTry,
                      lastUpdated: myState.lastUpdated,
                    );
                    return _buildCombinedBody(
                      combined,
                      myState,
                      partnerAssets,
                      partners.firstWhere(
                        (p) => p.id == _selectedPartnerId,
                        orElse: () => AppUser(
                            id: '',
                            email: '',
                            displayName: 'Ortak',
                            passwordHash: '',
                            createdAt: DateTime.now()),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pushAdd(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  // ── Ortak görünümü ──────────────────────────────────────────────────────────

  Widget _buildCombinedBody(
    PortfolioState combined,
    PortfolioState myState,
    List<Asset> partnerAssets,
    AppUser partner,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Kombine özet
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PortfolioSummaryWidget(state: combined),
            ),
          ),
          // Ben
          SliverToBoxAdapter(
            child: _combinedUserHeader('Ben', myState.totalValue, cs, tryFmt),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _slidable(ctx, myState.assets[i], combined),
              childCount: myState.assets.length,
            ),
          ),
          // Ortak
          SliverToBoxAdapter(
            child: _combinedUserHeader(
                partner.displayName,
                partnerAssets.fold(
                    0, (s, a) => s + combined.toTRY(a.totalValue, a.currency)),
                cs,
                tryFmt),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _slidable(ctx, partnerAssets[i], combined),
              childCount: partnerAssets.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _combinedUserHeader(
      String name, double total, ColorScheme cs, NumberFormat fmt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primaryContainer,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            fmt.format(total),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(PortfolioState s) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered(s.assets);
    final hasActiveFilter = _search.isNotEmpty || _filter != null;

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Hero summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PortfolioSummaryWidget(state: s),
            ),
          ),

          // Arama çubuğu
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _searchBar(cs),
            ),
          ),

          // Filtre chipleri
          SliverToBoxAdapter(child: _filterChips(s, cs)),

          // Boş durum
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(s, cs),
            )
          else if (hasActiveFilter)
            // Filtre aktifken düz liste
            _flatList(filtered, s)
          else
            // Kategoriye göre gruplu liste
            _groupedList(filtered, s),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ---- Arama ----------------------------------------------------------------

  Widget _searchBar(ColorScheme cs) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(fontSize: 14, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Varlık veya sembol ara...',
                hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_search.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() => _search = '');
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.close_rounded,
                    size: 16, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Filtre chipleri ------------------------------------------------------

  Widget _filterChips(PortfolioState s, ColorScheme cs) {
    // Mevcut kategorileri say
    final counts = <AssetType, int>{};
    for (final a in s.assets) {
      counts[a.type] = (counts[a.type] ?? 0) + 1;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _chip('Tümü', null, cs.primary, s.assets.length, cs),
          ...AssetType.values
              .where((t) => counts.containsKey(t))
              .map((t) => _chip(t.label, t, t.color, counts[t]!, cs)),
        ],
      ),
    );
  }

  Widget _chip(
      String label, AssetType? type, Color color, int count, ColorScheme cs) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = selected ? null : type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : color,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Listeler -------------------------------------------------------------

  Widget _flatList(List<Asset> assets, PortfolioState s) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) => Column(
          children: [
            _slidable(ctx, assets[i], s),
            if (i < assets.length - 1)
              Divider(
                height: 1,
                indent: 76,
                endIndent: 20,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.35),
              ),
          ],
        ),
        childCount: assets.length,
      ),
    );
  }

  Widget _groupedList(List<Asset> assets, PortfolioState s) {
    final cs = Theme.of(context).colorScheme;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    // Kategoriye göre grupla
    final grouped = <AssetType, List<Asset>>{};
    for (final a in assets) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    final orderedTypes =
        AssetType.values.where((t) => grouped.containsKey(t)).toList();

    // Düz item listesi (header + varlıklar)
    final items = <_Item>[];
    for (final type in orderedTypes) {
      final typeAssets = grouped[type]!;
      final total = typeAssets.fold<double>(
          0, (sum, a) => sum + s.toTRY(a.totalValue, a.currency));
      items.add(_Item.header(type, total, typeAssets.length, tryFmt));
      for (var i = 0; i < typeAssets.length; i++) {
        items.add(
            _Item.asset(typeAssets[i], isLast: i == typeAssets.length - 1));
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final item = items[i];
          if (item.isHeader) {
            return _groupHeader(item.type!, item.totalLabel!, cs);
          }
          return Column(
            children: [
              _slidable(ctx, item.asset!, s),
              if (!item.isLast)
                Divider(
                  height: 1,
                  indent: 76,
                  endIndent: 20,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
            ],
          );
        },
        childCount: items.length,
      ),
    );
  }

  Widget _groupHeader(AssetType type, String totalLabel, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: type.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            type.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: type.color,
            ),
          ),
          const Spacer(),
          Text(
            totalLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Boş durum ------------------------------------------------------------

  Widget _emptyState(PortfolioState s, ColorScheme cs) {
    final hasFilter = _search.isNotEmpty || _filter != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              hasFilter ? Icons.search_off_rounded : Icons.show_chart_rounded,
              size: 40,
              color: cs.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasFilter ? 'Sonuç bulunamadı' : 'Portföyünüz boş',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Farklı bir arama deneyin'
                : 'İlk varlığınızı ekleyerek başlayın',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pushAdd(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Varlık Ekle'),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Navigasyon -----------------------------------------------------------

  void _pushAdd(BuildContext ctx) => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const AddAssetScreen()),
      );

  void _pushDetail(BuildContext ctx, Asset asset) => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => AssetDetailScreen(asset: asset)),
      );

  // ---- Asset Row Widget -----------------------------------------------------

  Widget _slidable(BuildContext ctx, Asset asset, PortfolioState s) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _pushDetail(ctx, asset),
      child: Container(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: asset.type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    asset.type.icon,
                    color: asset.type.color,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (asset.ticker.isNotEmpty)
                          Text(
                            asset.ticker,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (asset.ticker.isNotEmpty &&
                            asset.subCategory != null)
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (asset.subCategory != null)
                          Text(
                            asset.subCategory!,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Value
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₺ ${NumberFormat('#,##0.00', 'tr_TR').format(s.toTRY(asset.totalValue, asset.currency))}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${asset.quantity} ${asset.unitType == 'gram' ? 'gr' : asset.unitType == 'ounce' ? 'oz' : 'adet'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
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

// ---------------------------------------------------------------------------
// Yardımcı model
// ---------------------------------------------------------------------------

class _Item {
  final bool isHeader;
  final AssetType? type;
  final String? totalLabel;
  final Asset? asset;
  final bool isLast;

  const _Item._({
    required this.isHeader,
    this.type,
    this.totalLabel,
    this.asset,
    this.isLast = false,
  });

  factory _Item.header(
          AssetType type, double total, int count, NumberFormat fmt) =>
      _Item._(
        isHeader: true,
        type: type,
        totalLabel: fmt.format(total),
      );

  factory _Item.asset(Asset asset, {bool isLast = false}) =>
      _Item._(isHeader: false, asset: asset, isLast: isLast);
}

// ---------------------------------------------------------------------------
// Partner seçici şeridi
// ---------------------------------------------------------------------------

class _PartnerSelector extends StatelessWidget {
  final List<AppUser> partners;
  final String? selectedPartnerId;
  final ValueChanged<String?> onChanged;
  final ColorScheme cs;

  const _PartnerSelector({
    required this.partners,
    required this.selectedPartnerId,
    required this.onChanged,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('Bireysel', null),
            ...partners.map((p) => _chip(p.displayName, p.id)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? id) {
    final selected = selectedPartnerId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => onChanged(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              if (id != null) ...[
                Icon(Icons.people_rounded,
                    size: 14,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
