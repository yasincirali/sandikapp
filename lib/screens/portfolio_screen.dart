import 'dart:async' show FutureOr, unawaited;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        RefreshIndicator,
        Material,
        MaterialType,
        ListTile,
        Divider,
        showModalBottomSheet;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/base_currency_provider.dart';
import '../providers/price_alert_provider.dart';
import '../widgets/alarm_kur_sheet.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/sparkline_service.dart';
import '../theme/sandik.dart';
import '../widgets/delete_asset_dialog.dart';
import '../utils/tr_format.dart';
import '../widgets/asset_sparkline.dart';
import '../widgets/tour_anchor.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/dividend_dialog.dart';
import '../widgets/quick_adjust_dialog.dart';
import 'comparison_screen.dart';
import 'asset_detail_screen.dart';
import 'watchlist_screen.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/custom_loading_indicator.dart';
import '../l10n/l10n.dart';

enum _SortOrder {
  valueDesc,
  valueAsc,
  gainDesc,
  gainAsc,
  gainPctDesc,
  gainPctAsc,
}

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  String? _view = '';
  AssetType? _filteredType;
  _SortOrder _sortOrder = _SortOrder.valueDesc;

  /// Gövde sekmesi: 0 = Varlıklarım, 1 = Takip Listesi.
  ///
  /// Takip listesi eskiden bu ekranın EN DİBİNDE, uzun bir listenin altında
  /// 32pt boşluktan sonra duran bir satırdı — kullanıcı bulgusu "daha görünür
  /// bir yerde olmalı" idi. Alt gezinme çubuğu ise dolu
  /// (Ana·Portföy·[+]·Performans·Profil); beşinci bir sekme HIG'in
  /// "Don't overcrowd with too many buttons" kuralına girerdi ve bu kısıt
  /// `test/watchlist_placement_test.dart`'ta ölçülmüş bir karar olarak duruyor.
  ///
  /// Segment gövdenin EN ÜSTÜNDE: bir dokunuşla görünür, üst bar
  /// kalabalıklaşmaz. Ortak seçici "Varlıklarım" dalının İÇİNDE kalır —
  /// iki yatay seçici asla yan yana çizilmez.
  int _bodyTab = 0;

  List<Position> _applyPositionSortOrder(
      List<Position> list, PortfolioState pState) {
    switch (_sortOrder) {
      case _SortOrder.valueDesc:
        return list
          ..sort((a, b) => pState
              .toTRY(b.totalValue, b.representative.currency)
              .compareTo(
                  pState.toTRY(a.totalValue, a.representative.currency)));
      case _SortOrder.valueAsc:
        return list
          ..sort((a, b) => pState
              .toTRY(a.totalValue, a.representative.currency)
              .compareTo(
                  pState.toTRY(b.totalValue, b.representative.currency)));
      case _SortOrder.gainDesc:
        return list
          ..sort((a, b) {
            final ga = a.weightedPurchasePrice > 0
                ? pState.toTRY(a.totalValue, a.representative.currency) -
                    a.totalCostTRY
                : double.negativeInfinity;
            final gb = b.weightedPurchasePrice > 0
                ? pState.toTRY(b.totalValue, b.representative.currency) -
                    b.totalCostTRY
                : double.negativeInfinity;
            return gb.compareTo(ga);
          });
      case _SortOrder.gainAsc:
        return list
          ..sort((a, b) {
            final ga = a.weightedPurchasePrice > 0
                ? pState.toTRY(a.totalValue, a.representative.currency) -
                    a.totalCostTRY
                : double.infinity;
            final gb = b.weightedPurchasePrice > 0
                ? pState.toTRY(b.totalValue, b.representative.currency) -
                    b.totalCostTRY
                : double.infinity;
            return ga.compareTo(gb);
          });
      case _SortOrder.gainPctDesc:
        return list
          ..sort((a, b) {
            final pa = a.weightedPurchasePrice > 0
                ? a.gainLossPercentage
                : double.negativeInfinity;
            final pb = b.weightedPurchasePrice > 0
                ? b.gainLossPercentage
                : double.negativeInfinity;
            return pb.compareTo(pa);
          });
      case _SortOrder.gainPctAsc:
        return list
          ..sort((a, b) {
            final pa = a.weightedPurchasePrice > 0
                ? a.gainLossPercentage
                : double.infinity;
            final pb = b.weightedPurchasePrice > 0
                ? b.gainLossPercentage
                : double.infinity;
            return pa.compareTo(pb);
          });
    }
  }

  /// Kaydırma → "Sil": pozisyonun TÜM lot'ları gider.
  ///
  /// Kullanıcının gördüğü satır bir kayıt değil, aynı `positionKey`'e düşen
  /// lot yığınıdır. Eskiden buraya `p.representative` (= en son eklenen alım)
  /// geliyordu ve yalnızca o siliniyordu; parça parça eklenmiş bir varlık
  /// "son eklenen kadarı" eksilmiş halde listede kalıyordu.
  void _confirmDelete(BuildContext ctx, WidgetRef ref, Position position) {
    final asset = position.representative;
    // Silinecek gerçek kayıt sayısı — deleteLog izleri lot listesinde
    // olabilir ama silinmez.
    final lots = position.lots.where((l) => !l.isDeleteLog).toList();
    confirmAndDeletePosition(ctx, ref, name: asset.name, lots: lots);
  }

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;

    return CupertinoPageScaffold(
      backgroundColor: context.c.background,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.portfolio,
                        style: context.t.headlineLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                        ),
                      ),
                    ),
                    _SortButton(
                      current: _sortOrder,
                      onChanged: (o) => setState(() => _sortOrder = o),
                    ),
                    const SizedBox(width: 8),
                    // NOT: Performans ekranına giden düğme KALDIRILDI —
                    // alt gezinme çubuğunda zaten "Performans" sekmesi var ve
                    // aynı ekranı açıyordu. Bu satır dört kontrol taşıyordu.
                    //
                    // Kaybedilen tek şey: düğme `initialView: _view` geçirip
                    // Portföy'deki ortak seçimini taşıyordu; sekme her zaman
                    // varsayılanla ("Ben") açılır. Kullanıcı seçimi performans
                    // ekranında yeniden yapabilir.
                    // Karşılaştırma — portföyde OLMAYAN varlıkları da
                    // kıyaslayan keşif aracı. Performans ekranından ayrı
                    // durur: o "bende ne var", bu "almasaydım ne olurdu".
                    CupertinoButton(
                      minimumSize: SandikTouch.minSize,
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.push(
                        context,
                        CupertinoPageRoute<void>(
                            builder: (_) => const ComparisonScreen()),
                      ),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.c.overlay,
                          borderRadius: BorderRadius.circular(SandikRadius.md),
                          border: Border.all(color: context.c.overlay),
                        ),
                        child: Center(
                          child: Icon(Icons.compare_arrows_rounded,
                              color: context.c.amberText, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SandikLogoutButton(
                      onPressed: () => confirmAndLogout(context, ref),
                    ),
                  ],
                ),
              ),
              // ── Gövde sekmesi ─────────────────────────────────────────────
              // Takip listesinin giriş noktası. Gövdenin en üstünde durur;
              // üst bar (sırala · karşılaştır · çıkış) kalabalıklaşmaz.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TourAnchor(
                  target: TourTarget.govdeSekmeleri,
                  child: _BodyTabs(
                    selected: _bodyTab,
                    count: ref.watch(watchlistCountProvider),
                    onChanged: (i) => setState(() => _bodyTab = i),
                  ),
                ),
              ),
              // ── Body ──────────────────────────────────────────────────────
              if (_bodyTab == 1)
                // Takip listesi ayrı bir veri kümesi: bu ekranın hiçbir
                // toplamına girmez. Portföy özeti "Varlıklarım" dalının
                // içinde kaldığı için değişmez korunuyor.
                const Expanded(child: WatchlistBody())
              else
              Expanded(
                child: pStateAsync.when(
                  loading: () => const SandikLoadingScreen(),
                  error: (e, _) => SandikErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(portfolioProvider)),
                  data: (pState) => RefreshIndicator(
                    color: context.c.amberText,
                    // Kullanıcı yenilemesi — fiyat önbelleği atlanır.
                    onRefresh: () => ref
                        .read(portfolioProvider.notifier)
                        .refreshPrices(force: true),
                    child: ListView(
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                      children: [
                        if (activePartners.isNotEmpty)
                          ModernTabSelector(
                            partners: activePartners,
                            selectedId: _view,
                            onChanged: (v) => setState(() {
                              _view = v;
                              _filteredType = null;
                            }),
                          ),
                        const SizedBox(height: 24),

                        // Verileri birleştir. NOT: burada iç Scaffold koymayız —
                        // SandikLoadingScreen bir Scaffold içerir ve ListView
                        // child olarak konulunca layout crash oluyor
                        // ("!_debugDoingThisLayout" assertion). Bunun yerine
                        // inline bir loading göstergesi kullanıyoruz.
                        //
                        // `when` yerine `AsyncValue` üzerinde manuel dallanma:
                        // `when(loading:)` her TAZELEMEDE (ortak sekmesi
                        // değişimi, refreshPrices sonrası reload) listeyi söküp
                        // 300px'lik spinner koyuyordu — oysa elde gösterilebilir
                        // bir önceki liste zaten var. `valueOrNull` yeniden
                        // yükleme boyunca önceki değeri korur, bu yüzden spinner
                        // artık YALNIZCA hiç veri yokken (ilk açılış) çıkar.
                        (partnerAssetsAsync.valueOrNull == null
                            ? (partnerAssetsAsync.hasError
                                ? SandikErrorView(
                                    error: partnerAssetsAsync.error!,
                                    onRetry: () =>
                                        ref.invalidate(portfolioProvider))
                                : const SizedBox(
                                    height: 300,
                                    child: CustomLoadingView(),
                                  ))
                            : ((Map<String, List<Asset>> partnerMap) {
                                // Sahiplik sınırı KORUNMALI: `positionKey` sahip
                                // bilgisi taşımaz, bu yüzden tüm ortakların lot'ları
                                // tek listede aggregate edilirse aynı hisseye sahip
                                // iki kişi tek pozisyonda birleşir ve kâr/zarar
                                // tekil sekmelerin toplamıyla tutarsız çıkar.
                                // Ayrıntı: aggregatePositionsByOwner dökümantasyonu.
                                final List<List<Asset>> ownerLots;
                                if (_view == '') {
                                  ownerLots = [pState.assets];
                                } else if (_view != null) {
                                  ownerLots = [partnerMap[_view] ?? const []];
                                } else {
                                  // Birlikte
                                  ownerLots = [
                                    pState.assets,
                                    ...partnerMap.values,
                                  ];
                                }

                                final positions =
                                    aggregatePositionsByOwner(ownerLots);

                                if (positions.isEmpty) {
                                  return const _EmptyState();
                                }

                                final filteredPositions =
                                    _applyPositionSortOrder(
                                  _filteredType != null
                                      ? positions
                                          .where((p) =>
                                              p.representative.type ==
                                              _filteredType)
                                          .toList()
                                      : List<Position>.from(positions),
                                  pState,
                                );
                                final displayAssets = positions
                                    .map(
                                        (position) => position.asDisplayAsset())
                                    .toList();

                                // Sparkline serilerini şimdiden hazırla.
                                // Kart açıldığında ağ beklemesi olmasın —
                                // eskiden grafik boş beliriyor, saniyeler
                                // sonra doluyordu (bkz. `prefetch`).
                                SparklineService.instance
                                    .prefetch(displayAssets);

                                return Column(
                                  children: [
                                    _AssetTypeDonut(
                                      assets: displayAssets,
                                      pState: pState,
                                      baz: ref.watch(bazParaProvider),
                                      onTypeSelected: (type) =>
                                          setState(() => _filteredType = type),
                                    ),
                                    const SizedBox(height: 32),
                                    _AssetList(
                                      positions: filteredPositions,
                                      pState: pState,
                                      baz: ref.watch(bazParaProvider),
                                      currentUserId: currentUserId,
                                      onTap: (p) => Navigator.push(
                                        context,
                                        CupertinoPageRoute<void>(
                                            builder: (_) => AssetDetailScreen(
                                                  asset: p.asDisplayAsset(),
                                                  showBackButton: true,
                                                  lots: p.lots,
                                                )),
                                      ),
                                      onDelete: (p) =>
                                          _confirmDelete(context, ref, p),
                                      onAdd: (p) => showQuickAdjustDialog(
                                          context, ref,
                                          asset: p.asDisplayAsset(),
                                          mode: QuickAdjustMode.add),
                                      onRemove: (p) => showQuickAdjustDialog(
                                          context, ref,
                                          asset: p.asDisplayAsset(),
                                          mode: QuickAdjustMode.remove),
                                      onDividend: (p) => showDividendDialog(
                                          context, ref,
                                          asset: p.asDisplayAsset()),
                                    ),
                                  ],
                                );
                              })(partnerAssetsAsync.valueOrNull!)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Gövde sekmesi ───────────────────────────────────────────────────────────

/// `Varlıklarım | Takip Listesi` seçicisi.
///
/// ## Neden burada (üst barda ikon DEĞİL, alt barda sekme DEĞİL)
/// Takip listesi ilk olarak Ana ekranın üst barına ikon olarak kondu. Orası
/// zaten dört düğme taşıyordu ve satır o hâliyle bile taşıyordu: marka
/// rozetinin `Flexible`+`FittedBox` sarmalayıcısı 17px'lik bir taşmayı
/// kapatmak için eklenmişti. Beşinci düğme HIG'in navigation bar kuralını
/// çiğniyordu ("Don't overcrowd with too many buttons" — Severity: High).
/// Portföy'ün üst barı da üç kontrol taşıyor; oraya taşımak sorunu yalnızca
/// yer değiştirirdi.
///
/// Sonra listenin EN DİBİNE, 32pt boşluktan sonra bir satır olarak kondu.
/// Orada kimse bulamadı — kullanıcı bulgusu bunun üzerine geldi.
///
/// Alt gezinme çubuğuna beşinci sekme de olmaz: bar zaten
/// Ana·Portföy·[+]·Performans·Profil ile dolu ve aynı HIG kuralına girer.
///
/// Geriye kalan doğru yer gövdenin EN ÜSTÜ: bir dokunuşla görünür, hiçbir
/// bar kalabalıklaşmaz, ve ortak seçici "Varlıklarım" dalının içinde kaldığı
/// için iki yatay seçici asla yan yana çizilmez.
///
/// ## Neden sayı rozeti var
/// Sekme, altındaki içerik görünmediğinde ne olduğunu söylemeli. Boş bir
/// takip listesiyle dolu bir liste arasındaki farkı sekmeye dokunmadan
/// görmek, dokunmaya değip değmeyeceğini söyler.
class _BodyTabs extends StatelessWidget {
  const _BodyTabs({
    required this.selected,
    required this.count,
    required this.onChanged,
  });

  final int selected;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Row(
        children: [
          _tab(context, 0, context.l10n.myAssets, null),
          _tab(context, 1, context.l10n.watchlist, count > 0 ? count : null),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int i, String label, int? rozet) {
    final secili = i == selected;
    return Expanded(
      child: Semantics(
        button: true,
        selected: secili,
        label: rozet == null ? label : '$label, $rozet varlık',
        child: ExcludeSemantics(
          child: GestureDetector(
            // Opaque: sekmenin boş kalan alanı da dokunmayı yakalasın.
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (secili) return;
              SandikHaptic.selection.perform();
              onChanged(i);
            },
            child: Container(
              // 44pt HIG dokunma hedefi.
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                // Seçili değilken dolgu YOK — `Colors` bu dosyada import
                // edilmiyor (material yalnızca `show` listesiyle geliyor).
                color: secili ? context.c.amberFill : null,
                borderRadius: BorderRadius.circular(SandikRadius.sm),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: secili ? context.c.onAmber : context.c.text58,
                      ),
                    ),
                  ),
                  if (rozet != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: secili
                            ? context.c.onAmber.withValues(alpha: 0.18)
                            : context.c.amberFill.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(SandikRadius.sm),
                      ),
                      child: Text(
                        '$rozet',
                        style: context.t.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              secili ? context.c.onAmber : context.c.amberText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
          Icon(Icons.inbox_rounded, size: 64, color: context.c.text36),
          const SizedBox(height: 16),
          Text(context.l10n.noAssetsYet,
              style: context.t.bodyMedium?.copyWith(color: context.c.text36)),
        ],
      ),
    );
  }
}

// ── Donut Chart ───────────────────────────────────────────────────────────────

class _AssetTypeDonut extends StatefulWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  final BazPara baz;
  final void Function(AssetType?) onTypeSelected;
  const _AssetTypeDonut(
      {required this.assets,
      required this.pState,
      required this.baz,
      required this.onTypeSelected});

  @override
  State<_AssetTypeDonut> createState() => _AssetTypeDonutState();
}

class _AssetTypeDonutState extends State<_AssetTypeDonut> {
  int? _touchedIndex;

  String _formatTL(double val) {
    // Ana ekran hero'suyla birebir aynı format: ₺1.234.567 (baz birimde)
    return widget.baz.fmt(val);
  }

  @override
  Widget build(BuildContext context) {
    final totals = <AssetType, double>{};
    double totalVal = 0;
    for (final a in widget.assets) {
      final val = widget.pState.toTRY(a.totalValue, a.currency);
      totals[a.type] = (totals[a.type] ?? 0) + val;
      totalVal += val;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final touched = _touchedIndex != null && _touchedIndex! < sorted.length
        ? sorted[_touchedIndex!]
        : null;

    // Ortada gösterilecek metin
    final centerLabel = touched != null ? touched.key.label : 'toplam';
    final centerValue =
        touched != null ? _formatTL(touched.value) : _formatTL(totalVal);
    final centerPct = touched != null
        ? fmtPct(touched.value / (totalVal > 0 ? totalVal : 1) * 100, digits: 1)
        : null;
    final centerColor = touched != null ? touched.key.color : context.c.gold;

    return Column(
      children: [
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent) {
                        final idx =
                            response?.touchedSection?.touchedSectionIndex;
                        final newIdx =
                            (idx != null && idx >= 0 && idx < sorted.length)
                                ? (_touchedIndex == idx ? null : idx)
                                : null;
                        setState(() => _touchedIndex = newIdx);
                        widget.onTypeSelected(
                            newIdx != null ? sorted[newIdx].key : null);
                      }
                    },
                  ),
                  sections: sorted.asMap().entries.map((e) {
                    final isTouched = e.key == _touchedIndex;
                    return PieChartSectionData(
                      color: e.value.key.color,
                      value: e.value.value,
                      radius: isTouched ? 42 : 34,
                      showTitle: false,
                    );
                  }).toList(),
                  sectionsSpace: 3,
                  centerSpaceRadius: 88,
                  startDegreeOffset: -90,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centerPct != null) ...[
                        Text(
                          centerPct,
                          style: context.t.numLarge.copyWith(
                            fontSize: 18,
                            color: centerColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerValue,
                          style: context.t.numLarge.copyWith(
                            fontSize: centerPct != null ? 16 : 22,
                            fontWeight: FontWeight.w700,
                            color: centerColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerLabel,
                        style: context.t.titleSmall?.copyWith(
                          color: context.c.text36,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        // Kategori legend
        Wrap(
          spacing: 20,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: sorted.asMap().entries.map((e) {
            final isTouched = e.key == _touchedIndex;
            final pct = fmtPct(
                e.value.value / (totalVal > 0 ? totalVal : 1) * 100,
                digits: 1);
            return GestureDetector(
              onTap: () {
                final newIdx = _touchedIndex == e.key ? null : e.key;
                setState(() => _touchedIndex = newIdx);
                widget
                    .onTypeSelected(newIdx != null ? sorted[newIdx].key : null);
              },
              child: AnimatedOpacity(
                duration:
                    SandikMotion.of(context, const Duration(milliseconds: 150)),
                // Eksikti: curve verilmeyince Curves.linear devreye girer.
                // Lejant sönümlemesi bir DURUM değişimidir → enter.
                curve: SandikMotion.enter,
                opacity: _touchedIndex == null || isTouched ? 1.0 : 0.45,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: SandikMotion.of(
                          context, const Duration(milliseconds: 150)),
                      curve: SandikMotion.enter,
                      width: isTouched ? 10 : 8,
                      height: isTouched ? 10 : 8,
                      decoration: BoxDecoration(
                        color: e.value.key.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Etiket ESNEK + kısaltılabilir olmalı. `Wrap` çipi
                    // alt satıra indirir ama TEK çip satıra sığmıyorsa
                    // çaresizdir: büyük metin ayarında "Hisse Senedi
                    // %45,2" 320pt'yi tek başına aşıyor ve 2×'te 45px,
                    // 3×'te 199px taşıyordu.
                    Flexible(
                      child: Text(
                        '${e.value.key.label} $pct',
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight:
                              isTouched ? FontWeight.w700 : FontWeight.w500,
                          color:
                              isTouched ? e.value.key.color : context.c.text58,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Asset List ────────────────────────────────────────────────────────────────

class _AssetList extends StatelessWidget {
  final List<Position> positions;
  final PortfolioState pState;
  final BazPara baz;
  final String? currentUserId;
  final void Function(Position) onTap;
  final void Function(Position) onDelete;
  // Bu üçü dialog açar ve `Future` döndürür; kaydırma paneli dialog
  // KAPANDIKTAN sonra kapanabilsin diye tip `void` değil `FutureOr<void>`.
  // `void` kalsaydı `await` beklemez, panel yine erken kapanırdı.
  final FutureOr<void> Function(Position) onAdd;
  final FutureOr<void> Function(Position) onRemove;
  final FutureOr<void> Function(Position) onDividend;

  const _AssetList({
    required this.positions,
    required this.pState,
    required this.baz,
    required this.currentUserId,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
    required this.onDividend,
  });

  @override
  Widget build(BuildContext context) {
    // `Column` + `.map()` her kartı bir kerede kurardı. Free tier 20 varlıkla
    // sınırlı ama premium sınırsız — büyük portföyde ekran dışındaki kartlar
    // da (sparkline yükleyen State'leriyle birlikte) boşuna inşa ediliyordu.
    //
    // Dış ListView zaten kaydırmayı yönetiyor, bu yüzden burada
    // shrinkWrap + NeverScrollable: iç içe iki kaydırma olmaz, ama
    // `itemBuilder` yalnızca görünür aralığı kurar.
    return SlidableAutoCloseBehavior(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: positions.length,
        // Sıralama değişince kartlar yeniden kullanılmasın: aksi halde bir
        // satırın açık/kapalı durumu ve sparkline'ı başka varlığa taşınır.
        itemBuilder: (context, i) {
          final position = positions[i];
          return _AssetCard(
            key: ValueKey(position.key),
            position: position,
            pState: pState,
            baz: baz,
            canEdit: currentUserId != null &&
                position.representative.userId == currentUserId,
            onTap: onTap,
            onDelete: onDelete,
            onAdd: onAdd,
            onRemove: onRemove,
            onDividend: onDividend,
          );
        },
      ),
    );
  }
}

// ── Asset Card ────────────────────────────────────────────────────────────────

/// Kaydırma aksiyonu (Ekle / Çıkar / Temettü / Sil).
///
/// `SlidableAction` yerine elle kuruldu: o widget ikon + etiketi sabit
/// padding'li bir `Column`'a koyuyor ve satır yüksekliği kısaldığında alttan
/// KIRPIYOR — kullanıcı ekranında "Ekle"/"Çıkar" yazıları yarım görünüyordu.
///
/// Buradaki çözüm: içerik [FittedBox] ile ölçeklenir ve dikeyde ortalanır;
/// yükseklik ne olursa olsun taşma olmaz, yazı küçülerek sığar.
Widget _rowAction(
  BuildContext context, {
  /// `Future` döndürebilir: dialog açan aksiyonlarda panel, dialog
  /// KAPANDIKTAN sonra kapatılır (bkz. onTap).
  required FutureOr<void> Function() onPressed,
  required Color background,
  required Color foreground,
  required IconData icon,
  required String label,
}) {
  return Expanded(
    // `Slidable.of` bir InheritedWidget aramasıdır: yalnızca `Slidable`'ın
    // ALTINDAKİ bir context'ten çalışır. Buraya gelen `context`
    // `_AssetCardState.build`'in context'idir ve `Slidable` o build içinde
    // kurulduğu için ONUN ÜSTÜNDE kalır → arama `null` döner, `close()`
    // sessizce hiçbir şey yapmazdı. Panel her aksiyondan sonra açık
    // kalıyordu; "Sil" düzelmiş görünüyordu çünkü onay dialogu listeyi
    // yeniden kurup paneli yan etkiyle sıfırlıyordu.
    //
    // `Builder` aramayı bir seviye aşağı taşır — artık gerçek `Slidable`
    // bulunur.
    child: Builder(
      builder: (innerContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          // Panel kapanışı bir ANİMASYONDUR. Eskiden `close()` çağrılıp hemen
          // ardından dialog açılıyordu; dialog açılış animasyonu araya girince
          // kapanış yarıda kalıyor ve dialog kapandığında panel hâlâ açık
          // duruyordu.
          //
          // Sıra tersine çevrildi: önce aksiyonun kendisi (dialog) beklenir,
          // sonra panel kapatılır. `Slidable.of` referansı ÖNCEDEN alınır —
          // await sonrası bu context artık geçerli olmayabilir.
          final slidable = Slidable.of(innerContext);
          await onPressed();
          unawaited(slidable?.close());
        },
        child: Container(
          color: background,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: context.t.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Satır kolonlarının genişlik dağıtımı.
///
/// **Sabit genişlik YOK, cihaz eşiği YOK.** Kolonlar satırın gerçek
/// genişliğinden (LayoutBuilder) pay alır; her ekranda kendiliğinden doğru
/// oranı bulur.
///
/// Dağıtım sırası — önce zorunlu olan:
///   1. İsim bloğu [minNameWidth] alır; asla feda edilmez.
///   2. Tutar kolonu [minValueWidth]–[maxValueWidth] arasında ölçeklenir.
///   3. Kalan her şey isme gider.
///
/// Eskiden tam tersiydi: sparkline (56pt) ve tutar (108pt) sabitti, isme
/// "kalan ne varsa" düşüyordu — iPhone 12 mini'de 45pt, 320pt'lik cihazlarda
/// neredeyse hiç. Sparkline artık satırda değil (bkz. _AssetDetailsPanel):
/// telefon genişliklerinde yuvaya 2–22pt kalıyordu ve o boyutta eğri bilgi
/// taşımıyordu.
abstract final class _AssetCardMetrics {
  /// İsim bloğunun taban genişliği — "THYAO" + alt satır ("10 adet · Hisse").
  /// 320pt'lik cihazlarda bile ulaşılabilir olsun diye ölçülü tutuldu.
  static const double minNameWidth = 112;

  /// Tutar kolonu. FittedBox içeriği zaten küçültür; alt sınır, rakamların
  /// okunamayacak kadar ufalmasını engeller.
  static const double minValueWidth = 88;
  static const double maxValueWidth = 108;

  /// Kolonlar arası boşluk (SandikSpace.sm).
  static const double columnGap = 8;

  /// İkon + ikon boşluğu — satır başındaki sabit blok.
  static const double leadingWidth = 28 + 14;

  /// Satır sonundaki genişletme oku (32pt) + öncesindeki 4pt boşluk.
  static const double trailingChevronWidth = 32 + 4;

  /// [rowWidth] = kart iç genişliği (padding düşülmüş).
  static ({double name, double value}) resolve(double rowWidth) {
    final afterLeading = rowWidth - leadingWidth - trailingChevronWidth;

    // Tutar kolonu: alan bollaştıkça max'a doğru büyür, dar kalınca isim
    // tabanını korumak için minValueWidth'e kadar kısılır.
    double value = maxValueWidth;
    if (afterLeading < minNameWidth + columnGap + value) {
      value = (afterLeading - minNameWidth - columnGap)
          .clamp(minValueWidth, maxValueWidth);
    }

    // Kalan her şey isme.
    double name = afterLeading - columnGap - value;

    // Aşırı dar cihazda (katlanabilir kapak ekranı vb.) negatife düşmesin.
    if (name < 0) name = 0;
    return (name: name, value: value);
  }
}

/// Satır başındaki tür ikonu / döviz sembolü — sabit 28×28.
class _AssetLeadingIcon extends StatelessWidget {
  const _AssetLeadingIcon({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final symbol = asset.currencySymbol;
    if (symbol == null) {
      // İkonu da 28×28 kutuya oturt: sembollü ve sembolsüz satırlarda
      // başlık bloğu aynı x konumundan başlasın.
      return SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Icon(asset.type.icon,
              color: asset.type.onSurface(context), size: 22),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: asset.type.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SandikRadius.sm),
      ),
      child: Center(
        child: Text(
          symbol,
          style: context.t.bodyMedium!.copyWith(
            fontSize: symbol.length > 1 ? 9 : 13,
            fontWeight: FontWeight.w800,
            color: asset.type.onSurface(context),
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Tutarın altındaki kâr/zarar satırı — ok + tutar · yüzde.
///
/// Sabit genişlikli kolona sığması için [FittedBox] ile küçültülür;
/// kırpmak yerine ölçeklemek tercih edildi çünkü "₺125.4..." okunmaz.
class _GainLossLine extends StatelessWidget {
  const _GainLossLine({
    required this.gainLossTRY,
    required this.totalCostTRY,
    required this.isPositive,
    required this.tryFmt,
  });

  final double gainLossTRY;
  final double totalCostTRY;
  final bool isPositive;
  final ParaBicimi tryFmt;

  @override
  Widget build(BuildContext context) {
    final pct = totalCostTRY > 0 ? (gainLossTRY / totalCostTRY) * 100 : 0.0;
    final isFlat = gainLossTRY.abs().round() == 0 && pct.abs() < 0.005;

    final Color color = isFlat
        ? context.c.text58
        : (isPositive ? context.c.gain : context.c.loss);

    final IconData icon = isFlat
        ? Icons.horizontal_rule_rounded
        : (isPositive
            ? Icons.arrow_drop_up_rounded
            : Icons.arrow_drop_down_rounded);

    final String label = isFlat
        ? 'Değişim yok'
        : '${tryFmt.format(gainLossTRY.abs())} · ${fmtPct(pct.abs(), digits: 2)}';

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 2),
          Text(
            label,
            maxLines: 1,
            style: context.t.numSmall.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetCard extends StatefulWidget {
  final Position position;
  final PortfolioState pState;
  final BazPara baz;
  final bool canEdit;
  final void Function(Position) onTap;
  final void Function(Position) onDelete;
  // Bu üçü dialog açar ve `Future` döndürür; kaydırma paneli dialog
  // KAPANDIKTAN sonra kapanabilsin diye tip `void` değil `FutureOr<void>`.
  // `void` kalsaydı `await` beklemez, panel yine erken kapanırdı.
  final FutureOr<void> Function(Position) onAdd;
  final FutureOr<void> Function(Position) onRemove;
  final FutureOr<void> Function(Position) onDividend;

  const _AssetCard({
    super.key,
    required this.position,
    required this.pState,
    required this.baz,
    required this.canEdit,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
    required this.onDividend,
  });

  @override
  State<_AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<_AssetCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final pState = widget.pState;
    final canEdit = widget.canEdit;
    final onTap = widget.onTap;
    final onAdd = widget.onAdd;
    final onRemove = widget.onRemove;
    final onDelete = widget.onDelete;
    final onDividend = widget.onDividend;

    final a = position.asDisplayAsset();
    final tryFmt = widget.baz.formatter(digits: 0);
    // Temettü dahil — üstteki özet de dahil ediyor, satır onunla tutarlı olmalı.
    final gainLossTRY = pState.toTRY(position.totalValue, a.currency) -
        position.totalCostTRY +
        totalDividendTRY(position.lots);
    final isPos = gainLossTRY >= 0;

    // Kart iç boşluğu sabit: eşiğe bağlı bir sıçrama, kolon dağıtımının
    // sürekliliğini bozardı. 12pt her cihazda hem nefes payı bırakır hem de
    // eski 16pt'ye göre isme 8pt kazandırır.
    const cardPad = SandikSpace.sm + 4;

    Widget card = Container(
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(canEdit ? 0 : SandikRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikTappable(
            onTap: () => onTap(position),
            child: Padding(
              padding: const EdgeInsets.all(cardPad),
              // Kolon genişlikleri satırın GERÇEK genişliğinden hesaplanır —
              // sabit değer veya cihaz eşiği yok. Böylece her telefonda,
              // katlanabilirlerde ve bölünmüş ekranda doğru oran çıkar.
              child: LayoutBuilder(
                builder: (context, rowConstraints) {
                  final m = _AssetCardMetrics.resolve(rowConstraints.maxWidth);
                  final valueW = m.value;
                  return
                      // crossAxisAlignment.center: ikon, başlık bloğu, sparkline ve
                      // tutar kolonu ortak bir yatay eksende hizalanır. Satır
                      // yüksekliği içeriğe göre değişse de (tek/çift satır başlık)
                      // öğeler birbirine göre kaymaz.
                      Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AssetLeadingIcon(asset: a),
                      const SizedBox(width: 14),

                      // ── Başlık bloğu — esnek, kalan tüm alanı alır ──────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Fon/hisse: yalnızca KOD (THYAO). Uzun tam ad
                            // satırı taşırıyordu — tam ad artık detay panelinde
                            // "TAM ADI" alanında, kırpılmadan.
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    a.showTicker ? a.displayTicker! : a.name,
                                    maxLines: a.showTicker ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: context.c.text90,
                                      height: 1.25,
                                      letterSpacing:
                                          a.showTicker ? 0.2 : -0.2,
                                    ),
                                  ),
                                ),
                                // Aktif fiyat alarmı olan varlık belli olsun:
                                // kullanıcı "hangisine alarm koymuştum" diye
                                // Ayarlar'a gitmesin (2026-09-14).
                                _AlarmRozeti(
                                  sembol: alarmSembolu(a.ticker, a.subCategory),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              a.unitIsPrefix
                                  ? '${a.unitLabel}${fmtNum(a.quantity, digits: a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} · ${a.type.label}'
                                  : '${fmtNum(a.quantity, digits: a.quantity == a.quantity.truncateToDouble() ? 0 : 2)} ${a.unitLabel} · ${a.type.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.bodySmall
                                  ?.copyWith(color: context.c.text36),
                            ),
                          ],
                        ),
                      ),

                      // Sparkline SATIRDA YOK — bkz. _AssetCardMetrics.
                      // Telefon genişliklerinde yuvaya 2–22pt kalıyordu; o boyutta
                      // eğri bilgi taşımaz, yalnızca isimden yer yerdi. Grafik
                      // artık satır genişletildiğinde detay panelinde TAM
                      // GENİŞLİKTE çiziliyor.

                      // ── Tutar + kâr/zarar — SABİT genişlik ─────────────────
                      //
                      // Sınırsız bırakılırsa kolon genişliğini en uzun sayı
                      // belirler ve isim alanını yer: büyük portföyde isimler
                      // daha çok kırpılırdı. Sabit genişlik hem bunu önler hem
                      // de tüm satırların sağ kenarını hizalar.
                      const SizedBox(width: SandikSpace.sm),
                      SizedBox(
                        width: valueW,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                tryFmt.format(
                                    pState.toTRY(a.totalValue, a.currency)),
                                maxLines: 1,
                                style: context.t.numMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.c.text90),
                              ),
                            ),
                            if (a.purchasePrice > 0 && a.currentPrice > 0) ...[
                              const SizedBox(height: 4),
                              _GainLossLine(
                                gainLossTRY: gainLossTRY,
                                totalCostTRY: position.totalCostTRY,
                                isPositive: isPos,
                                tryFmt: tryFmt,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _ExpandChevron(
                        expanded: _expanded,
                        onTap: () => setState(() => _expanded = !_expanded),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          AnimatedSize(
            duration:
                SandikMotion.of(context, const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _AssetDetailsPanel(
                    position: position, pState: pState, baz: widget.baz)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    final showsDividend = a.supportsDividend;

    if (canEdit) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Slidable(
          key: ValueKey('asset-${a.id}'),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            // Temettü yalnızca temettü ödeyen türlerde görünür → aksiyon
            // sayısı 2 veya 3 olabilir, pane genişliği de ona göre.
            //
            // 0.72 fazlaydı: 375pt ekranda pane 270pt yer kaplıyor, geriye
            // satır içeriğine 105pt kalıyordu ve varlık adı "AVOD 90 lot · H"
            // gibi ortadan kesiliyordu. Aksiyonlar kaydırma sırasında hangi
            // satırda olduğunu görebilmeyi engellememeli.
            //
            // 0.62'de her buton 78pt (HIG #37 minimumu 44pt), satıra 142pt
            // kalıyor — hem etiketler sığıyor hem satır okunur kalıyor.
            extentRatio: showsDividend ? 0.62 : 0.44,
            children: [
              // "Ekle/Çıkar" envanter dilidir; bu aksiyonlar ise FİYATLI
              // işlem kaydeder (alışta birim fiyat zorunlu, satışta güncel
              // fiyattan `addSellTransaction`). Kullanıcı "listeye satır
              // ekle" sanıp fiyat sorulunca şaşırıyordu. Veri modeli zaten
              // `isSell` ile alım/satım tutuyor — etiket ona hizalandı.
              _rowAction(
                context,
                onPressed: () => onAdd(position),
                background: context.c.gain,
                // `text90` YÜZEY metnidir; renkli dolgu üstünde iki temada
                // da kırılır (light 3.02:1, dark 2.54:1). Dolgu mürekkebi
                // `onStatus` — light'ta beyaz, dark'ta koyu (5.37/5.73:1).
                foreground: context.c.onStatus,
                icon: Icons.trending_up_rounded,
                label: 'Al',
              ),
              _rowAction(
                context,
                onPressed: () => onRemove(position),
                background: context.c.loss.withValues(alpha: 0.85),
                foreground: context.c.onStatus,
                icon: Icons.trending_down_rounded,
                label: 'Sat',
              ),
              // Temettü nakit dağıtan varlıklara özgü — altın/döviz/emtia'da
              // anlamsız.
              if (showsDividend)
                _rowAction(
                  context,
                  onPressed: () => onDividend(position),
                  // Dolgu için `amberFill`, üstündeki içerik için `onAmber`.
                  // Eskiden zemin `amberText` (METİN token'ı) + sabit
                  // `black87` idi: light'ta ikisi de koyulaşıp 1.75:1'e
                  // düşüyordu — buton yazısı okunmuyordu.
                  background: context.c.amberFill,
                  foreground: context.c.onAmber,
                  icon: Icons.savings_outlined,
                  label: 'Temettü',
                ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.28,
            children: [
              _rowAction(
                context,
                onPressed: () => onDelete(position),
                background: context.c.danger,
                // `danger` de bir DOLGU; `loss` ile aynı parlaklık ailesinde
                // olduğu için mürekkebi de aynı (`onStatus`).
                foreground: context.c.onStatus,
                icon: Icons.delete_outline_rounded,
                label: 'Sil',
              ),
            ],
          ),
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
  }
}

// ── Expand Chevron ────────────────────────────────────────────────────────────

/// Sembolde aktif alarm varsa küçük zil; yoksa hiçbir şey.
class _AlarmRozeti extends ConsumerWidget {
  final String? sembol;
  const _AlarmRozeti({required this.sembol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = sembol;
    if (s == null) return const SizedBox.shrink();
    final aktif =
        ref.watch(symbolAlertsProvider(s)).where((a) => a.isActive).length;
    if (aktif == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: SandikSpace.xs),
      child: Semantics(
        label: '$aktif aktif fiyat alarmı',
        child: Icon(Icons.notifications_active_rounded,
            size: 14, color: context.c.amberText),
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ExpandChevron({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Dokunma alanı 44×44 (HIG #37, High severity) — görsel ikon 32'de
      // kalır. `Container` 32 iken parmakla ıskalanabiliyordu; büyütmek
      // yerine ŞEFFAF dolgu ekliyoruz, böylece yerleşim değişmez.
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: AnimatedRotation(
          turns: expanded ? 0.5 : 0.0,
          duration: SandikMotion.of(context, const Duration(milliseconds: 200)),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.c.text58,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ── Asset Details Panel (expandable) ──────────────────────────────────────────

class _AssetDetailsPanel extends StatelessWidget {
  final Position position;
  final PortfolioState pState;
  final BazPara baz;

  const _AssetDetailsPanel(
      {required this.position, required this.pState, required this.baz});

  @override
  Widget build(BuildContext context) {
    final rep = position.representative;
    final tryFmt3 = baz.formatter(digits: 3);
    final numFmt = qtyFormatter();
    final costFmt3 = fixedFormatter(3);

    // İlk alış tarihi = en eski buy lot
    final buyLots = position.lots.where((l) => l.isBuy).toList()
      ..sort((a, b) => a.addedDate.compareTo(b.addedDate));
    final firstBuyDate = buyLots.isNotEmpty ? buyLots.first.addedDate : null;

    final avgCostStr = position.weightedPurchasePrice > 0
        ? '${numFmt.format(position.weightedPurchasePrice)} ${rep.currency}'
        : '—';

    final qty = position.totalQuantity;
    final qtyStr = qty == qty.truncateToDouble()
        ? fixedFormatter(0).format(qty.toInt())
        : numFmt.format(qty);
    final qtyDisplay = rep.unitIsPrefix
        ? '${rep.unitLabel}$qtyStr'
        : '$qtyStr ${rep.unitLabel}';

    final currentValueTRY = pState.toTRY(position.totalValue, rep.currency);

    // Grafiğin rengi satırdaki yüzdeyle aynı kaynaktan gelmeli (temettü dahil),
    // yoksa eğri yeşilken yazı kırmızı olabilir.
    final gainLossTRY = currentValueTRY -
        position.totalCostTRY +
        totalDividendTRY(position.lots);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 12),
            color: context.c.overlay,
          ),
          // Son 1 ayın fiyat eğrisi — TAM GENİŞLİKTE.
          //
          // Eskiden satır içinde 56pt'lik bir yuvadaydı; responsive dağıtımda
          // telefonlarda 2–22pt'ye düşüyor ve okunmuyordu. Burada panelin
          // tamamını kullanır, yükseklik de 24→48pt'ye çıkar: eğrinin şekli
          // gerçekten görünür.
          if (SparklineService.supports(rep)) ...[
            LayoutBuilder(
              builder: (context, c) => AssetSparkline(
                asset: rep,
                isPositive: gainLossTRY >= 0,
                width: c.maxWidth,
                height: 48,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Son 1 ay',
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
            const SizedBox(height: 14),
          ],
          // Tam ad — satırda yalnızca kod (THYAO) gösterilen varlıklar için.
          // Kırpma yok: burada yer var, isim tam okunmalı.
          if (rep.showTicker) ...[
            _DetailItem(label: 'Tam Adı', value: rep.name, isText: true),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'İlk Alış',
                  value: firstBuyDate != null
                      ? DateFormat('d MMM yyyy', 'tr_TR').format(firstBuyDate)
                      : '—',
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Miktar',
                  value: qtyDisplay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Ort. Maliyet',
                  value: avgCostStr,
                ),
              ),
              Expanded(
                child: _DetailItem(
                  label: 'Toplam Maliyet',
                  value: position.weightedPurchasePrice > 0
                      ? '${costFmt3.format(position.totalCost)} ${rep.currency}'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: 'Güncel Tutar',
                  value: tryFmt3.format(currentValueTRY),
                  emphasize: true,
                ),
              ),
            ],
          ),
          if (position.lots.length > 1) ...[
            const SizedBox(height: 10),
            Text(
              '${buyLots.length} alım · ${position.lots.where((l) => l.isSell).length} çıkarma',
              style: context.t.bodySmall?.copyWith(
                  color: context.c.text36, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  /// Değer bir sayı değil, düz metinse (örn. varlığın tam adı).
  ///
  /// Tabular figür hizalaması yalnızca rakamlar için anlamlı; metinde
  /// harf aralıklarını bozar.
  final bool isText;

  const _DetailItem({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.isText = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle =
        isText ? context.t.bodyMedium ?? const TextStyle() : context.t.numSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: context.t.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.c.text36,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: valueStyle.copyWith(
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: emphasize ? context.c.gold : context.c.text90,
            height: isText ? 1.35 : null, // sarma satırları sıkışmasın
          ),
        ),
      ],
    );
  }
}

// ── Sort Button ───────────────────────────────────────────────────────────────

class _SortButton extends StatelessWidget {
  final _SortOrder current;
  final void Function(_SortOrder) onChanged;

  const _SortButton({required this.current, required this.onChanged});

  static const _options = <(_SortOrder, String, String)>[
    (_SortOrder.valueDesc, 'Piyasa Değeri', 'Büyükten Küçüğe'),
    (_SortOrder.valueAsc, 'Piyasa Değeri', 'Küçükten Büyüğe'),
    (_SortOrder.gainDesc, 'Kazanç (TL)', 'En Yüksek Önce'),
    (_SortOrder.gainAsc, 'Kazanç (TL)', 'En Düşük Önce'),
    (_SortOrder.gainPctDesc, 'Kazanç (%)', 'En Yüksek Önce'),
    (_SortOrder.gainPctAsc, 'Kazanç (%)', 'En Düşük Önce'),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: SandikTouch.minSize,
      padding: EdgeInsets.zero,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.c.surface1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _SortSheet(
            current: current,
            onChanged: (o) {
              onChanged(o);
              Navigator.pop(context);
            }),
      ),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: current != _SortOrder.valueDesc
              ? context.c.amberFill.withValues(alpha: 0.15)
              : context.c.overlay,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
            color: current != _SortOrder.valueDesc
                ? context.c.amberFill.withValues(alpha: 0.5)
                : context.c.overlay,
          ),
        ),
        child: Icon(
          Icons.sort_rounded,
          size: 20,
          color: current != _SortOrder.valueDesc
              ? context.c.amberText
              : context.c.text58,
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final _SortOrder current;
  final void Function(_SortOrder) onChanged;

  const _SortSheet({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'SIRALAMA KRİTERİ',
              style: context.t.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: context.c.text58,
              ),
            ),
          ),
          Divider(color: context.c.hairline, height: 1),
          ..._SortButton._options.map((opt) {
            final (order, group, label) = opt;
            final selected = current == order;
            return ListTile(
              dense: true,
              leading: Icon(
                _iconFor(order),
                size: 18,
                color: selected ? context.c.amberText : context.c.text58,
              ),
              title: Text(
                group,
                style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? context.c.amberText : context.c.text90,
                ),
              ),
              subtitle: Text(
                label,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded,
                      color: context.c.amberText, size: 18)
                  : null,
              tileColor:
                  selected ? context.c.amberFill.withValues(alpha: 0.07) : null,
              onTap: () => onChanged(order),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _iconFor(_SortOrder o) => switch (o) {
        _SortOrder.valueDesc => Icons.arrow_downward_rounded,
        _SortOrder.valueAsc => Icons.arrow_upward_rounded,
        _SortOrder.gainDesc => Icons.trending_up_rounded,
        _SortOrder.gainAsc => Icons.trending_down_rounded,
        _SortOrder.gainPctDesc => Icons.percent_rounded,
        _SortOrder.gainPctAsc => Icons.percent_rounded,
      };
}
