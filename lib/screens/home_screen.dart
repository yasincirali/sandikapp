import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../widgets/portfolio_summary_widget.dart';
import '../widgets/modern_tab_selector.dart';
import 'performance_screen.dart';
import 'portfolio_performance_screen.dart';
import 'all_transactions_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _view = ''; // null = Birlikte, '' = Ben, uuid = ortak

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(portfolioProvider.notifier).refreshPrices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(portfolioProvider);
    final partners = ref.watch(activePartnersProvider);

    return Scaffold(
      backgroundColor: Sandik.background,
      body: asyncState.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Sandik.amber)),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (myState) {
          if (partners.isEmpty) {
            return _buildBody(myState, {}, []);
          }
          return ref.watch(allPartnerAssetsProvider).when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: Sandik.amber)),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (allPartnerAssets) =>
                    _buildBody(myState, allPartnerAssets, partners),
              );
        },
      ),
    );
  }

  Widget _buildBody(
    PortfolioState myState,
    Map<String, List<Asset>> allPartnerAssets,
    List<AppUser> partners,
  ) {
    final user = ref.watch(authProvider).valueOrNull;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final allActivePartners = ref.watch(activePartnersProvider);

    // ── Displayed assets based on current tab ──────────────────────────────
    final List<Asset> displayedAssets;
    if (_view == '') {
      displayedAssets = myState.assets;
    } else if (_view != null && _view!.isNotEmpty) {
      displayedAssets = allPartnerAssets[_view!] ?? [];
    } else {
      displayedAssets = [
        ...myState.assets,
        for (final list in allPartnerAssets.values) ...list,
      ];
    }

    final displayedState = PortfolioState(
      assets: displayedAssets,
      usdTry: myState.usdTry,
      eurTry: myState.eurTry,
      gbpTry: myState.gbpTry,
      lastUpdated: myState.lastUpdated,
    );

    // ── Greeting ──────────────────────────────────────────────────────────
    final String greetingName;
    if (_view != null && _view!.isNotEmpty) {
      final p = partners.firstWhere(
        (p) => p.id == _view,
        orElse: () => AppUser(
            id: '',
            email: '',
            displayName: 'Ortak',
            passwordHash: '',
            createdAt: DateTime.now()),
      );
      greetingName = '${p.displayName.split(' ')[0]} 👋';
    } else if (_view == null && partners.isNotEmpty) {
      greetingName =
          '${user?.displayName.split(' ')[0] ?? ''} & ${partners[0].displayName.split(' ')[0]} 👋';
    } else {
      greetingName = '${user?.displayName.split(' ')[0] ?? 'Hazine Sahibi'} 👋';
    }

    // ── Right mini card ───────────────────────────────────────────────────
    final bool showRightCard = _view != '';
    String rightLabel = '';
    double rightTotal = 0;
    String rightInitial = 'O';
    Color rightColor = Sandik.gain;

    if (showRightCard) {
      if (_view == null) {
        // Birlikte — combined partner total
        rightLabel = partners.length == 1
            ? partners[0].displayName.split(' ')[0]
            : 'Ortaklar';
        rightInitial = partners.isNotEmpty
            ? partners[0].displayName[0].toUpperCase()
            : 'O';
        for (final assets in allPartnerAssets.values) {
          for (final a in assets) {
            rightTotal += myState.toTRY(a.totalValue, a.currency);
          }
        }
      } else {
        // Specific partner
        final p = partners.firstWhere(
          (p) => p.id == _view,
          orElse: () => AppUser(
              id: '',
              email: '',
              displayName: 'Ortak',
              passwordHash: '',
              createdAt: DateTime.now()),
        );
        rightLabel = p.displayName.split(' ')[0];
        rightInitial = p.displayName[0].toUpperCase();
        for (final a in allPartnerAssets[_view!] ?? <Asset>[]) {
          rightTotal += myState.toTRY(a.totalValue, a.currency);
        }
      }
    }

    // ── Sorted transactions (newest first) ────────────────────────────────
    final sortedAssets = [...displayedAssets]
      ..sort((a, b) => b.addedDate.compareTo(a.addedDate));

    return RefreshIndicator(
      color: Sandik.amber,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const SandikLogo(size: 24, color: Sandik.amber),
                  const SizedBox(width: 8),
                  Text(
                    'toka',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Sandik.gold,
                      letterSpacing: -1,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_none_rounded,
                          color: Sandik.text58, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Greeting ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Merhaba,',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Sandik.text58,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    greetingName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Portfolio summary ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PortfolioPerformanceScreen()),
                ),
                child: PortfolioSummaryWidget(state: displayedState),
              ),
            ),
          ),
          // ── Mini cards ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _personMiniCard(
                      'Ben',
                      myState.totalValue,
                      Sandik.amber,
                      tryFmt,
                      user?.displayName.isNotEmpty == true
                          ? user!.displayName[0].toUpperCase()
                          : 'B',
                    ),
                  ),
                  if (showRightCard && partners.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _personMiniCard(
                        rightLabel,
                        rightTotal,
                        rightColor,
                        tryFmt,
                        rightInitial,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── Tab bar ─────────────────────────────────────────────────────
          if (allActivePartners.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: ModernTabSelector(
                  partners: allActivePartners,
                  selectedId: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
          // ── Distribution ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'VARLIK DAĞILIMI',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Sandik.text36,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildDistributionList(displayedState),
            ),
          ),
          // ── Recent transactions header ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SON İŞLEMLER',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Sandik.text36,
                      ),
                    ),
                  ),
                  if (sortedAssets.length > 3)
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AllTransactionsScreen(
                            myAssets: myState.assets,
                            allPartnerAssets: allPartnerAssets,
                            partners: partners,
                            usdTry: myState.usdTry,
                            eurTry: myState.eurTry,
                            gbpTry: myState.gbpTry,
                            initialView: _view,
                          ),
                        ),
                      ),
                      child: Text(
                        'Tümünü Gör',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Sandik.amber,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ── Last 3 transactions ───────────────────────────────────────────
          if (sortedAssets.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('Henüz işlem yok',
                      style: TextStyle(color: Sandik.text36)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildTransactionItem(sortedAssets[i]),
                childCount: sortedAssets.length > 3 ? 3 : sortedAssets.length,
              ),
            ),
          // ── "See all" button (only when > 3 items) ────────────────────────
          if (sortedAssets.length > 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllTransactionsScreen(
                        myAssets: myState.assets,
                        allPartnerAssets: allPartnerAssets,
                        partners: partners,
                        usdTry: myState.usdTry,
                        eurTry: myState.eurTry,
                        gbpTry: myState.gbpTry,
                        initialView: _view,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Sandik.surface1,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Tüm İşlemleri Gör (${sortedAssets.length})',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Sandik.amber,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _personMiniCard(String name, double total, Color color,
      NumberFormat fmt, String initial) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(initial,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 12),
          Text(name,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Sandik.text58,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(fmt.format(total),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildDistributionList(PortfolioState state) {
    final totals = <AssetType, double>{};
    for (final a in state.assets) {
      totals[a.type] =
          (totals[a.type] ?? 0) + state.toTRY(a.totalValue, a.currency);
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sorted.take(3).map((e) {
        final ratio = e.value / (state.totalValue > 0 ? state.totalValue : 1);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: e.key.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(e.key.label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
              ),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    color: e.key.color,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 40,
                child: Text(
                  '%${(ratio * 100).toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Sandik.text58,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTransactionItem(Asset asset) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PerformanceScreen(asset: asset)),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: asset.type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    asset.name.substring(0, 2).toUpperCase(),
                    style: TextStyle(
                        color: asset.type.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.name,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      '${asset.type.label} · ${DateFormat('d MMM', 'tr_TR').format(asset.addedDate)}',
                      style:
                          GoogleFonts.inter(fontSize: 12, color: Sandik.text36),
                    ),
                  ],
                ),
              ),
              Text(
                '${asset.gainLoss >= 0 ? '+' : ''}₺${NumberFormat('#,###').format(asset.gainLoss.abs().toInt())}',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: asset.gainLoss >= 0 ? Sandik.gain : Sandik.loss),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
