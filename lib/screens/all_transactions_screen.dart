import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/h_scroll_with_fade.dart';
import 'performance_screen.dart';

class AllTransactionsScreen extends ConsumerStatefulWidget {
  final List<Asset> myAssets;
  final Map<String, List<Asset>> allPartnerAssets;
  final List<AppUser> partners;
  final double usdTry;
  final double eurTry;
  final double gbpTry;
  final String? initialView;
  final AssetType? initialTypeFilter;

  const AllTransactionsScreen({
    super.key,
    required this.myAssets,
    required this.allPartnerAssets,
    required this.partners,
    required this.usdTry,
    required this.eurTry,
    required this.gbpTry,
    this.initialView,
    this.initialTypeFilter,
  });

  @override
  ConsumerState<AllTransactionsScreen> createState() =>
      _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends ConsumerState<AllTransactionsScreen> {
  late String? _view;
  AssetType? _typeFilter;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView ?? '';
    _typeFilter = widget.initialTypeFilter;
  }

  double _toTRY(double value, String currency) {
    switch (currency) {
      case 'USD':
        return value * widget.usdTry;
      case 'EUR':
        return value * widget.eurTry;
      case 'GBP':
        return value * widget.gbpTry;
      default:
        return value;
    }
  }

  List<Asset> get _filtered {
    final List<Asset> base;
    if (_view == '') {
      base = widget.myAssets;
    } else if (_view != null && _view!.isNotEmpty) {
      base = widget.allPartnerAssets[_view!] ?? [];
    } else {
      base = [
        ...widget.myAssets,
        for (final list in widget.allPartnerAssets.values) ...list,
      ];
    }

    final sorted = [...base]
      ..sort((a, b) => b.addedDate.compareTo(a.addedDate));

    if (_typeFilter == null) return sorted;
    return sorted.where((a) => a.type == _typeFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activePartners = ref.watch(activePartnersProvider);
    final assets = _filtered;
    final tryFmt =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

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
          'Tüm İşlemler',
          style: context.t.headlineMedium?.copyWith(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // ── Partner tab bar ────────────────────────────────────────────
          if (activePartners.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ModernTabSelector(
                partners: activePartners,
                selectedId: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
          // ── Asset type filter chips ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: HScrollWithFade(
              child: Row(
                children: [
                  _typeChip(null, 'Tümü'),
                  for (final t in RemoteConfigService.instance.visibleAssetTypes)
                    _typeChip(t, t.label),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // ── Transaction list ──────────────────────────────────────────
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox_rounded,
                            size: 52, color: Sandik.text36),
                        const SizedBox(height: 12),
                        Text('İşlem bulunamadı',
                            style: context.t.titleMedium?.copyWith(color: Sandik.text36)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    itemCount: assets.length,
                    itemBuilder: (ctx, i) => _buildTile(assets[i], tryFmt),
                  ),
          ),
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
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : Sandik.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Asset asset, NumberFormat tryFmt) {
    final totalTRY = _toTRY(asset.totalValue, asset.currency);
    final hasPnl = asset.purchasePrice > 0 && asset.currentPrice > 0;
    final gainLossTRY = hasPnl ? totalTRY - asset.totalCostTRY : 0.0;
    final isPos = gainLossTRY >= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          adaptiveRoute(
              builder: (_) =>
                  PerformanceScreen(asset: asset, showBackButton: true)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              asset.currencySymbol != null
                  ? Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: asset.type.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          asset.currencySymbol!,
                          style: context.t.bodyMedium!.copyWith(
                            fontSize: asset.currencySymbol!.length > 1 ? 9 : 13,
                            fontWeight: FontWeight.w800,
                            color: asset.type.color,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : Icon(asset.type.icon, color: asset.type.color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (asset.showTicker) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: asset.type.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(asset.displayTicker!,
                            style: context.t.labelMedium?.copyWith(
                                letterSpacing: 0,
                                fontWeight: FontWeight.w800,
                                color: asset.type.color)),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(asset.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: asset.type.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(asset.type.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: asset.type.color,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('d MMM yyyy', 'tr_TR')
                              .format(asset.addedDate),
                          style: context.t.bodySmall?.copyWith(color: Sandik.text36),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            asset.unitIsPrefix
                                ? '${asset.unitLabel}${NumberFormat('#,##0.####', 'tr_TR').format(asset.quantity)}'
                                : '${NumberFormat('#,##0.####', 'tr_TR').format(asset.quantity)} ${asset.unitLabel}',
                            style: context.t.labelMedium?.copyWith(
                                letterSpacing: 0,
                                color: Sandik.text58,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tryFmt.format(totalTRY),
                      style: context.t.numSmall.copyWith(
                          fontSize: 15,
                          color: Colors.white)),
                  if (hasPnl) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${isPos ? '+' : ''}₺${NumberFormat('#,###', 'tr_TR').format(gainLossTRY.abs().toInt())}',
                      style: context.t.numSmall.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPos ? Sandik.gain : Sandik.loss),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
