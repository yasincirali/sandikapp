import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/signal_provider.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
import '../theme/sandik.dart';
import '../widgets/portfolio_summary_widget.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/h_scroll_with_fade.dart';
import 'add_asset_screen.dart';
import 'performance_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _view = '';
  AssetType? _typeFilter;
  final _scrollCtrl = ScrollController();
  bool _reloading = false;
  bool _showAllTransactions = false;

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    await ref.read(portfolioProvider.notifier).refreshPrices();
    if (mounted) setState(() => _reloading = false);
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PerformanceScreen(asset: asset)),
            );
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
        loading: () => const SandikLoadingScreen(),
        error: (e, _) => SandikErrorView(error: e, onRetry: _reload),
        data: (myState) {
          if (partners.isEmpty) return _buildBody(myState, {}, []);
          return ref.watch(allPartnerAssetsProvider).when(
            loading: () => const SandikLoadingScreen(),
            error: (e, _) => SandikErrorView(error: e, onRetry: _reload),
            data: (allPartnerAssets) => _buildBody(myState, allPartnerAssets, partners),
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
    final tryFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
    final sw = MediaQuery.of(context).size.width;
    final hp = sw < 360 ? 14.0 : 20.0;
    final allActivePartners = ref.watch(activePartnersProvider);

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


    final bool showRightCard = _view != '';
    String rightLabel = '';
    double rightTotal = 0;
    String rightInitial = 'O';
    Color rightColor = Sandik.gain;

    if (showRightCard) {
      if (_view == null) {
        if (partners.length == 1) {
          final name = partners[0].displayName;
          rightLabel = name.isEmpty ? 'Ortak' : name.split(' ').first;
        } else {
          rightLabel = 'Ortaklar';
        }
        rightInitial = partners.isNotEmpty && partners[0].displayName.isNotEmpty
            ? partners[0].displayName[0].toUpperCase()
            : 'O';
        for (final assets in allPartnerAssets.values) {
          for (final a in assets) {
            rightTotal += myState.toTRY(a.totalValue, a.currency);
          }
        }
      } else {
        final p = partners.firstWhere(
          (p) => p.id == _view,
          orElse: () => AppUser(id: '', email: '', displayName: 'Ortak', createdAt: DateTime.now()),
        );
        final name = p.displayName.isEmpty ? 'Ortak' : p.displayName;
        rightLabel = name.split(' ').first;
        rightInitial = name[0].toUpperCase();
        for (final a in allPartnerAssets[_view!] ?? <Asset>[]) {
          rightTotal += myState.toTRY(a.totalValue, a.currency);
        }
      }
    }

    final filteredAssets = _typeFilter == null
        ? displayedAssets
        : displayedAssets.where((a) => a.type == _typeFilter).toList();

    final sortedAssets = [...filteredAssets]..sort((a, b) => b.addedDate.compareTo(a.addedDate));

    return RefreshIndicator(
      color: Sandik.amber,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // AppBar
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: Sandik.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 66,
            titleSpacing: 0,
            title: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Sandik.amber.withValues(alpha: 0.28), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
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
                              style: GoogleFonts.dmSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Sandik.gold,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _HeaderIconButton(
                    onTap: _reload,
                    child: _reloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Sandik.amber),
                          )
                        : const Icon(Icons.refresh_rounded, color: Sandik.text58, size: 22),
                  ),
                  const SizedBox(width: 8),
                  const _BalanceToggleButton(),
                  const SizedBox(width: 8),
                  _SignalBadgeButton(onTap: _scrollToSignals),
                  const SizedBox(width: 8),
                  SandikLogoutButton(onPressed: () => confirmAndLogout(context, ref)),
                ],
              ),
            ),
          ),
          // Offline / price error banner
          if (myState.errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Sandik.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Sandik.amber.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Sandik.amber, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fiyatlar güncellenemedi — eski veriler gösteriliyor.',
                          style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.amber),
                        ),
                      ),
                      GestureDetector(
                        onTap: _reload,
                        child: Text(
                          'Tekrar Dene',
                          style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: Sandik.amber),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Portfolio summary
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: PortfolioSummaryWidget(
                state: displayedState,
                hideBalance: ref.watch(balanceHiddenProvider),
              ),
            ),
          ),
          // Mini cards
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
                      user?.displayName.isNotEmpty == true ? user!.displayName[0].toUpperCase() : 'B',
                      hideBalance: ref.watch(balanceHiddenProvider),
                    ),
                  ),
                  if (showRightCard && partners.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _personMiniCard(
                        rightLabel, rightTotal, rightColor, tryFmt, rightInitial,
                        hideBalance: ref.watch(balanceHiddenProvider),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Tab bar
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
          // Asset type filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
              child: HScrollWithFade(
                child: Row(
                  children: [
                    _typeChip(null, 'Tümü'),
                    for (final t in AssetType.values) _typeChip(t, t.label),
                  ],
                ),
              ),
            ),
          ),
          // Distribution header
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 16, hp, 8),
              child: Text(
                'VARLIK DAĞILIMI',
                style: GoogleFonts.dmSans(
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
          // Recent transactions header
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 24, hp, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SON İŞLEMLER',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Sandik.text36,
                      ),
                    ),
                  ),
                  if (sortedAssets.length > 3)
                    GestureDetector(
                      onTap: () => setState(() => _showAllTransactions = !_showAllTransactions),
                      child: Text(
                        _showAllTransactions ? 'Daha Az Göster' : 'Tümünü Gör',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _showAllTransactions ? Sandik.text36 : Sandik.amber,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Transactions list
          if (sortedAssets.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 16, hp, 8),
                child: Column(
                  children: [
                    const Icon(Icons.savings_outlined, color: Sandik.text36, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Henüz varlık eklenmemiş',
                      style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'İlk varlığını ekleyerek sandığını oluşturmaya başla.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddAssetScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        decoration: BoxDecoration(
                          color: Sandik.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Sandik.amber.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded, color: Sandik.amber, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'İlk Varlığını Ekle',
                              style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: Sandik.amber),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildTransactionItem(sortedAssets[i]),
                childCount: _showAllTransactions
                    ? sortedAssets.length
                    : (sortedAssets.length > 3 ? 3 : sortedAssets.length),
              ),
            ),
          // Show all / less button
          if (sortedAssets.length > 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                child: GestureDetector(
                  onTap: () => setState(() => _showAllTransactions = !_showAllTransactions),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: Center(
                          child: Text(
                            _showAllTransactions
                                ? 'Daha Az Göster'
                                : 'Tümünü Gör (${sortedAssets.length})',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _showAllTransactions ? Sandik.text36 : Sandik.amber,
                            ),
                          ),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? color.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.10),
                  width: selected ? 1.5 : 1.0,
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
        ),
      ),
    );
  }

  Widget _personMiniCard(String name, double total, Color color, NumberFormat fmt, String initial, {bool hideBalance = false}) {
    final sw = MediaQuery.of(context).size.width;
    final cardFontSize = sw < 360 ? 14.0 : 18.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.all(sw < 360 ? 12 : 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: color.withValues(alpha: 0.2),
                child: Text(
                  initial,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                ),
              ),
              const SizedBox(height: 10),
              Text(name,
                  style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text58, fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  hideBalance ? '••••••' : fmt.format(total),
                  style: GoogleFonts.dmSans(fontSize: cardFontSize, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionList(PortfolioState state) {
    final totals = <AssetType, double>{};
    for (final a in state.assets) {
      totals[a.type] = (totals[a.type] ?? 0) + state.toTRY(a.totalValue, a.currency);
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

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
                decoration: BoxDecoration(color: e.key.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(e.key.label,
                    style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
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
                  style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text58, fontWeight: FontWeight.w500),
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
    final portfolioState = ref.watch(portfolioProvider).valueOrNull;
    final hideBalance = ref.watch(balanceHiddenProvider);
    final tryFmt = NumberFormat('#,###', 'tr_TR');

    final bool isRemoved = asset.quantity <= 0;

    // Miktar metni: birime göre formatla
    String quantityText;
    if (isRemoved) {
      quantityText = 'Çıkarıldı';
    } else {
      final q = asset.quantity;
      final unit = asset.unitLabel;
      final isInt = q == q.truncateToDouble();
      final fractionDigits = asset.type == AssetType.doviz
          ? 2
          : (unit == 'gr' || unit == 'oz' || unit == 'kg' ? 2 : 4);
      final qStr = isInt
          ? NumberFormat('#,###', 'tr_TR').format(q.toInt())
          : q.toStringAsFixed(fractionDigits);
      quantityText = asset.unitIsPrefix ? '$unit$qStr' : '$qStr $unit';
    }

    // TL karşılığı
    final double tryValue = portfolioState != null
        ? portfolioState.toTRY(asset.totalValue, asset.currency)
        : asset.totalValue;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 0, hp, 10),
      child: GestureDetector(
        onTap: isRemoved
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PerformanceScreen(asset: asset)),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isRemoved
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isRemoved
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.09),
                ),
              ),
              child: Row(
                children: [
                  Opacity(
                    opacity: isRemoved ? 0.4 : 1.0,
                    child: asset.currencySymbol != null
                        ? Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: asset.type.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Center(
                              child: Text(
                                asset.currencySymbol!,
                                style: GoogleFonts.dmSans(
                                  fontSize: asset.currencySymbol!.length > 1 ? 9 : 13,
                                  fontWeight: FontWeight.w800,
                                  color: asset.type.color,
                                  height: 1,
                                ),
                              ),
                            ),
                          )
                        : Icon(asset.type.icon,
                            color: asset.type.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (asset.showTicker && !isRemoved) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: asset.type.color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  asset.displayTicker!,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: asset.type.color),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                asset.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isRemoved ? Sandik.text36 : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${asset.type.label} · ${DateFormat('d MMM', 'tr_TR').format(asset.addedDate)}',
                          style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isRemoved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Sandik.loss.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Çıkarıldı',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Sandik.loss,
                            ),
                          ),
                        )
                      else ...[
                        Text(
                          hideBalance ? '₺••••' : '₺${tryFmt.format(tryValue.toInt())}',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          quantityText,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Sandik.text36,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
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
    return DefaultTextStyle(
      style: GoogleFonts.dmSans(color: Colors.white, decoration: TextDecoration.none),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F2A1F),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Teknik Sinyaller',
                      style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, decoration: TextDecoration.none),
                    ),
                    const SizedBox(width: 8),
                    if (signals.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Sandik.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Sandik.amber.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${signals.length}',
                          style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: Sandik.amber, decoration: TextDecoration.none),
                        ),
                      ),
                    const Spacer(),
                    if (signals.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          onDismissAll();
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Tümünü Temizle',
                          style: GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (signals.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: Sandik.gain, size: 22),
                      const SizedBox(width: 12),
                      Text('Şu an aktif sinyal yok',
                          style: GoogleFonts.dmSans(fontSize: 14, color: Sandik.text58, decoration: TextDecoration.none)),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: signals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final alert = signals[i];
                      final isBuy = alert.signal == SignalType.buy;
                      final color = isBuy ? Sandik.gain : Sandik.loss;
                      final label = isBuy ? 'AL' : 'SAT';
                      final icon = isBuy ? Icons.trending_up_rounded : Icons.trending_down_rounded;
                      final count = isBuy ? alert.buyCount : alert.sellCount;

                      return GestureDetector(
                        onTap: () => onTap(alert),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: color.withValues(alpha: 0.28), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.18),
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
                                        Builder(builder: (_) {
                                          final t = alert.assetTicker.replaceAll('.IS', '').replaceAll('=X', '').trim();
                                          if (t.isEmpty) return const SizedBox.shrink();
                                          return Row(mainAxisSize: MainAxisSize.min, children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.18),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(t, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: color, decoration: TextDecoration.none)),
                                            ),
                                            const SizedBox(width: 6),
                                          ]);
                                        }),
                                        Flexible(
                                          child: Text(
                                            alert.assetName,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.dmSans(
                                                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, decoration: TextDecoration.none),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(label,
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 11, fontWeight: FontWeight.w800, color: color, decoration: TextDecoration.none)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$count/5 gösterge · %${(alert.confidence * 100).toStringAsFixed(0)} güven',
                                      style: GoogleFonts.dmSans(fontSize: 11, color: Sandik.text58, decoration: TextDecoration.none),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Sandik.text36),
                                onPressed: () => onDismiss(alert.assetId),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DisclaimerWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bakiye gizle/göster butonu ────────────────────────────────────────────────

class _BalanceToggleButton extends ConsumerWidget {
  const _BalanceToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balanceHiddenProvider);
    return GestureDetector(
      onTap: () => ref.read(balanceHiddenProvider.notifier).set(!hidden),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: hidden
                  ? Sandik.amber.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hidden
                    ? Sandik.amber.withValues(alpha: 0.40)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: hidden ? Sandik.amber : Sandik.text58,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ikon kutusu ────────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _HeaderIconButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            ),
            child: Center(child: child),
          ),
        ),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: count > 0
                      ? Sandik.amber.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: count > 0
                        ? Sandik.amber.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                    color: count > 0 ? Sandik.amber : Sandik.text58,
                    size: 22,
                  ),
                ),
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
                    style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
