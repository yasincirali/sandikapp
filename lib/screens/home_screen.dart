import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/signal_provider.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
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
  AssetType? _typeFilter;
  final _scrollCtrl = ScrollController();

  bool _reloading = false;

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    await ref.read(portfolioProvider.notifier).refreshPrices();
    if (mounted) setState(() => _reloading = false);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToSignals() {
    final signals = ref.read(signalProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SignalsBottomSheet(
        signals: signals,
        onDismiss: (id) => ref.read(signalProvider.notifier).dismiss(id),
        onDismissAll: () => ref.read(signalProvider.notifier).dismissAll(),
        onTap: (alert) {
          Navigator.pop(context);
          final asset = ref
              .read(portfolioProvider)
              .valueOrNull
              ?.assets
              .where((a) => a.id == alert.assetId)
              .firstOrNull;
          if (asset != null) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => PerformanceScreen(asset: asset)));
          }
        },
      ),
    );
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
    final sw = MediaQuery.of(context).size.width;
    final hp = sw < 360 ? 14.0 : 20.0; // horizontal padding
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

    // ── Apply type filter for summary/distribution ────────────────────────
    final filteredForSummary = _typeFilter == null
        ? displayedAssets
        : displayedAssets.where((a) => a.type == _typeFilter).toList();

    final displayedState = PortfolioState(
      assets: filteredForSummary,
      usdTry: myState.usdTry,
      eurTry: myState.eurTry,
      gbpTry: myState.gbpTry,
      lastUpdated: myState.lastUpdated,
    );

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
              createdAt: DateTime.now()),
        );
        rightLabel = p.displayName.split(' ')[0];
        rightInitial = p.displayName[0].toUpperCase();
        for (final a in allPartnerAssets[_view!] ?? <Asset>[]) {
          rightTotal += myState.toTRY(a.totalValue, a.currency);
        }
      }
    }

    // ── Apply type filter ─────────────────────────────────────────────────
    final filteredAssets = _typeFilter == null
        ? displayedAssets
        : displayedAssets.where((a) => a.type == _typeFilter).toList();

    // ── Sorted transactions (newest first) ────────────────────────────────
    final sortedAssets = [...filteredAssets]
      ..sort((a, b) => b.addedDate.compareTo(a.addedDate));

    return RefreshIndicator(
      color: Sandik.amber,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: Sandik.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 64,
            titleSpacing: hp,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Sandik.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Sandik.amber.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SandikLogo(size: 20, color: Sandik.amber),
                  const SizedBox(width: 7),
                  Text(
                    'sandık',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Sandik.gold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              _HeaderIconButton(
                onTap: _reload,
                child: _reloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Sandik.amber),
                      )
                    : const Icon(Icons.refresh_rounded,
                        color: Sandik.text58, size: 22),
              ),
              const SizedBox(width: 8),
              _SignalBadgeButton(
                onTap: () => _scrollToSignals(),
              ),
              SizedBox(width: hp),
            ],
          ),
          // ── Portfolio summary ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PortfolioPerformanceScreen(
                      initialView: _view,
                      initialTypeFilter: _typeFilter,
                    ),
                  ),
                ),
                child: PortfolioSummaryWidget(state: displayedState),
              ),
            ),
          ),
          // ── Mini cards ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 16, hp, 20),
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
                padding: EdgeInsets.fromLTRB(hp, 0, hp, 8),
                child: ModernTabSelector(
                  partners: allActivePartners,
                  selectedId: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
          // ── Asset type filter chips ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _typeChip(null, 'Tümü'),
                    for (final t in AssetType.values) _typeChip(t, t.label),
                  ],
                ),
              ),
            ),
          ),
          // ── Distribution ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 16, hp, 8),
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
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: _buildDistributionList(displayedState),
            ),
          ),
          // ── Recent transactions header ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 24, hp, 8),
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
                            initialTypeFilter: _typeFilter,
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
                padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
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

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? Sandik.amber;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = type),
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
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : Sandik.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _personMiniCard(String name, double total, Color color,
      NumberFormat fmt, String initial) {
    final sw = MediaQuery.of(context).size.width;
    final cardFontSize = sw < 360 ? 14.0 : 18.0;
    return Container(
      padding: EdgeInsets.all(sw < 360 ? 12 : 16),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(initial,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 10),
          Text(name,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Sandik.text58,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmt.format(total),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: cardFontSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
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
    final hp = MediaQuery.of(context).size.width < 360 ? 14.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 0, hp, 10),
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
                      style: GoogleFonts.inter(fontSize: 12, color: Sandik.text36),
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

// ── Sinyaller Bottom Sheet ────────────────────────────────────────────────────

class _SignalsBottomSheet extends StatelessWidget {
  final List<SignalAlert> signals;
  final void Function(String assetId) onDismiss;
  final VoidCallback onDismissAll;
  final void Function(SignalAlert alert) onTap;

  const _SignalsBottomSheet({
    required this.signals,
    required this.onDismiss,
    required this.onDismissAll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Sandik.text36,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Başlık
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Teknik Sinyaller',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                if (signals.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Sandik.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${signals.length}',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Sandik.amber),
                    ),
                  ),
                const Spacer(),
                if (signals.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      onDismissAll();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Tümünü Temizle',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Sandik.text36,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // İçerik
          if (signals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Sandik.gain, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    'Şu an aktif sinyal yok',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: Sandik.text58),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: signals.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final alert = signals[i];
                  final isBuy = alert.signal == SignalType.buy;
                  final color = isBuy ? Sandik.gain : Sandik.loss;
                  final label = isBuy ? 'AL' : 'SAT';
                  final icon = isBuy
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded;
                  final count =
                      isBuy ? alert.buyCount : alert.sellCount;

                  return GestureDetector(
                    onTap: () => onTap(alert),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: color.withValues(alpha: 0.25),
                            width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      alert.assetName,
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            color.withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: color),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$count/5 gösterge · %${(alert.confidence * 100).toStringAsFixed(0)} güven',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Sandik.text58),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: Sandik.text36),
                            onPressed: () => onDismiss(alert.assetId),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header ikon kutusu ───────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _HeaderIconButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── Notification Badge Butonu ─────────────────────────────────────────────────

class _SignalBadgeButton extends ConsumerWidget {
  final VoidCallback onTap;
  const _SignalBadgeButton({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(signalProvider).length;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: count > 0
                  ? Sandik.amber.withValues(alpha: 0.12)
                  : Sandik.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: count > 0
                    ? Sandik.amber.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.07),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                color: count > 0 ? Sandik.amber : Sandik.text58,
                size: 22,
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Sandik.loss,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Sandik.background, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    count > 9 ? '+9' : '$count',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
