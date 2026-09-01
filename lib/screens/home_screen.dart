import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/signal_provider.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/portfolio_summary_widget.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/transaction_row.dart';
import '../widgets/h_scroll_with_fade.dart';
import 'add_asset_screen.dart';
import 'all_transactions_screen.dart';
import 'performance_screen.dart';
import '../widgets/custom_loading_indicator.dart';

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

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    await ref.read(portfolioProvider.notifier).refreshPrices(force: true);
    if (mounted) setState(() => _reloading = false);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToSignals() {
    // NOT: Liste sheet'e PARAMETRE OLARAK GEÇİLMEZ.
    //
    // Eskiden `ref.read(...)` ile anlık kopya geçiliyordu ve sheet
    // `StatelessWidget`'tı. Sheet ayrı bir route olduğu için provider
    // güncellemeleri ona hiç ulaşmıyordu: kullanıcı bir bildirimi silince
    // sunucuda silinse bile LİSTE EKRANDA DEĞİŞMİYORDU. "Silmiyor"
    // şikâyetinin görünür sebebi buydu.
    // Sheet artık `ConsumerWidget` ve provider'ı kendisi izliyor.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SignalsBottomSheet(
        onDismiss: (id) => ref.read(signalProvider.notifier).dismiss(id),
        onDelete: (id) => ref.read(signalProvider.notifier).delete(id),
        onDismissAll: () => ref.read(signalProvider.notifier).dismissAll(),
        onTap: (alert) {
          Navigator.pop(context);
          AnalyticsService.instance.logSignalViewed(
            ticker: alert.assetTicker,
            action: alert.signal.name,
          );
          final asset = ref
              .read(portfolioProvider)
              .valueOrNull
              ?.assets
              .where((a) => a.id == alert.assetId)
              .firstOrNull;
          if (asset != null) {
            Navigator.push(
              context,
              adaptiveRoute(
                  builder: (_) =>
                      PerformanceScreen(asset: asset, showBackButton: true)),
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
    final hasPartners = partners.isNotEmpty;

    // İki provider birbirinden BAĞIMSIZ (`allPartnerAssetsProvider` yalnızca
    // `activePartnersProvider`'a bakar). Eskiden `.when()`'ler iç içeydi:
    // ortak varlıkları ancak portföy çözüldükten SONRA watch ediliyor, bu da
    // arka arkaya iki loading ekranı demekti. Artık ikisi de en baştan watch
    // edilir → paralel başlar, tek loading ekranı gösterilir.
    final asyncPartnerAssets =
        hasPartners ? ref.watch(allPartnerAssetsProvider) : null;

    return Scaffold(
      backgroundColor: context.c.background,
      body: Builder(
        builder: (_) {
          // Hata önceliği: hangisi patlarsa tek hata görünümü.
          final error = asyncState.error ?? asyncPartnerAssets?.error;
          if (error != null) {
            return SandikErrorView(error: error, onRetry: _reload);
          }
          // Tek loading: ikisi birden hazır olana kadar.
          final myState = asyncState.valueOrNull;
          if (myState == null ||
              (hasPartners && asyncPartnerAssets?.valueOrNull == null)) {
            return const SandikLoadingScreen();
          }
          return _buildBody(
            myState,
            asyncPartnerAssets?.valueOrNull ?? const {},
            partners,
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
    final hp = sw < 360 ? 14.0 : 20.0;
    final allActivePartners = ref.watch(activePartnersProvider);

    // Ham `assets` transaction ledger'ıdır — buy/sell/deleteLog hepsi karışık.
    // Ana sayfadaki summary, dağılım, mini card, hareket listesi ve kâr/zarar
    // portföy ekranı ile birebir tutarlı olmalı. Portföy ekranı
    // `aggregatePositions` kullanıyor: sell lot'ları buy qty'sinden düşer,
    // deleteLog skip edilir, totalQty <= 0 pozisyonlar liste dışı kalır.
    // Aynı aggregate'i burada da uyguluyoruz ve `asDisplayAsset()` ile
    // downstream widget'ların beklediği Asset formatına çeviriyoruz.
    List<Asset> positionedAssets(Iterable<Asset> raw) =>
        aggregatePositions(raw.toList())
            .map((p) => p.asDisplayAsset())
            .toList();

    final List<Asset> displayedAssets;
    if (_view == '') {
      displayedAssets = positionedAssets(myState.assets);
    } else if (_view != null && _view!.isNotEmpty) {
      displayedAssets = positionedAssets(allPartnerAssets[_view!] ?? const []);
    } else {
      displayedAssets = [
        ...positionedAssets(myState.assets),
        for (final list in allPartnerAssets.values) ...positionedAssets(list),
      ];
    }

    // "PORTFÖY HAREKETLERİ" listesi aggregate'i KULLANAMAZ.
    //
    // `positionedAssets` her varlığı tek bir sentetik pozisyona indirger:
    // sell lot'ları buy miktarından düşer, temettü ve deleteLog satırları
    // tamamen elenir. Summary/dağılım için doğru olan bu davranış, hareket
    // listesi için yanlıştı — kullanıcı Al/Sat/Temettü yaptığında listede
    // yeni bir kayıt GÖRÜNMÜYORDU; yalnızca mevcut satırın miktarı değişiyordu.
    //
    // Hareketler ham ledger'dan gelir: her işlem kendi satırıdır.
    // `TransactionRow` dört türü de (Alım/Satım/Temettü/Silindi) kendi ikon,
    // etiket ve tutarıyla çiziyor.
    //
    // Silinen varlığın satırları da BURADA KALIR: silme artık fiziksel
    // değil, `deleted_at` damgasıdır. Böylece "ne aldım, ne sattım, sonra
    // sildim" zinciri okunabilir. Damgalı satırlar `aggregatePositions`
    // ve `PortfolioState.activeAssets` tarafından elendiği için hiçbir
    // toplama girmez — yalnızca bu listede görünürler.
    //
    // Silme işleminin kendisi ayrıca bir `deleteLog` satırı yazar; o da
    // en üstte "Silindi · N kayıt" olarak görünür.
    final List<Asset> ledgerAssets;
    if (_view == '') {
      ledgerAssets = myState.assets;
    } else if (_view != null && _view!.isNotEmpty) {
      ledgerAssets = allPartnerAssets[_view!] ?? const [];
    } else {
      ledgerAssets = [
        ...myState.assets,
        for (final list in allPartnerAssets.values) ...list,
      ];
    }

    final filteredForSummary = _typeFilter == null
        ? displayedAssets
        : displayedAssets.where((a) => a.type == _typeFilter).toList();

    // "Ben" mini card'ı — kendi net pozisyon toplamı (satışlar düşülmüş).
    final myBuyTotal = positionedAssets(myState.assets).fold<double>(
        0, (s, a) => s + myState.toTRY(a.totalValue, a.currency));

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
    Color rightColor = context.c.gain;

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
            // `isActive`: yumuşak silinmiş lot toplama girmemeli.
            if (!a.isBuy || !a.isActive) continue;
            rightTotal += myState.toTRY(a.totalValue, a.currency);
          }
        }
      } else {
        final p = partners.firstWhere(
          (p) => p.id == _view,
          orElse: () => AppUser(
              id: '',
              email: '',
              displayName: 'Ortak',
              createdAt: DateTime.now()),
        );
        final name = p.displayName.isEmpty ? 'Ortak' : p.displayName;
        rightLabel = name.split(' ').first;
        rightInitial = name[0].toUpperCase();
        for (final a in allPartnerAssets[_view!] ?? <Asset>[]) {
          if (!a.isBuy || !a.isActive) continue;
          rightTotal += myState.toTRY(a.totalValue, a.currency);
        }
      }
    }

    // Hareket sayısı — "Tümünü Gör" rozeti ve eşiği için. Ledger'dan
    // sayılır; aggregate edilmiş pozisyon sayısı hareket sayısı DEĞİLDİR.
    final ledgerCount = _typeFilter == null
        ? ledgerAssets.length
        : ledgerAssets.where((a) => a.type == _typeFilter).length;

    return RefreshIndicator(
      color: context.c.amberText,
      // Kullanıcı yenilemesi — fiyat önbelleği atlanır.
      onRefresh: () =>
          ref.read(portfolioProvider.notifier).refreshPrices(force: true),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // AppBar
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: context.c.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 66,
            titleSpacing: 0,
            title: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
              child: Row(
                children: [
                  // Yön A: blur + gölge kaldırıldı — marka rozeti bir vurgu
                  // öğesi değil, kimlik işareti. Cam efekti hero karta ayrıldı.
                  //
                  // Flexible + FittedBox: rozet sabit genişlikteyken sağdaki
                  // dört aksiyon düğmesiyle birlikte satırı taşırıyordu
                  // (17px). Aksiyonlar kimlik işaretinden önceliklidir —
                  // gerekirse rozet küçülür, hiçbir düğme gizlenmez.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: context.c.amberFill.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(SandikRadius.md),
                          border: Border.all(
                              color: context.c.amberFill.withValues(alpha: 0.24),
                              width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SandikLogo(size: 20, color: context.c.amberText),
                            const SizedBox(width: SandikSpace.sm),
                            Text(
                              'sandık',
                              style: context.t.headlineMedium?.copyWith(
                                color: context.c.gold,
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
                        ? const CustomLoadingIndicator(size: 20)
                        : Icon(Icons.refresh_rounded,
                            color: context.c.text58, size: 22),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  const _BalanceToggleButton(),
                  const SizedBox(width: SandikSpace.sm),
                  _SignalBadgeButton(onTap: _scrollToSignals),
                  const SizedBox(width: SandikSpace.sm),
                  SandikLogoutButton(
                      onPressed: () => confirmAndLogout(context, ref)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border:
                        Border.all(color: context.c.amberFill.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: context.c.amberText, size: 16),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          'Fiyatlar güncellenemedi — eski veriler gösteriliyor.',
                          style: context.t.titleSmall
                              ?.copyWith(color: context.c.amberText),
                        ),
                      ),
                      SandikTappable(
                        onTap: _reload,
                        semanticLabel: 'Tekrar Dene',
                        child: Text(
                          'Tekrar Dene',
                          style: context.t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.c.amberText),
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
                      myBuyTotal,
                      context.c.amberText,
                      tryFmt,
                      user?.displayName.isNotEmpty == true
                          ? user!.displayName[0].toUpperCase()
                          : 'B',
                      hideBalance: ref.watch(balanceHiddenProvider),
                    ),
                  ),
                  if (showRightCard && partners.isNotEmpty) ...[
                    const SizedBox(width: SandikSpace.md),
                    Expanded(
                      child: _personMiniCard(
                        rightLabel,
                        rightTotal,
                        rightColor,
                        tryFmt,
                        rightInitial,
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
                    for (final t in RemoteConfigService.instance.visibleAssetTypes)
                      _typeChip(t, t.label),
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
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.c.text58,
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
              child: Text(
                'PORTFÖY HAREKETLERİ',
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: context.c.text58,
                ),
              ),
            ),
          ),
          // Recent transaction list (show individual asset transactions newest -> oldest)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
              child: Builder(builder: (_) {
                // Tür filtresi hareketlere de uygulanır, ama liste ham
                // ledger'dan gelir — her Al/Sat/Temettü kaydı ayrı satır.
                final recentAssets = (_typeFilter == null
                    ? ledgerAssets.toList()
                    : ledgerAssets.where((a) => a.type == _typeFilter).toList())
                  ..sort((a, b) => b.addedDate.compareTo(a.addedDate));

                if (recentAssets.isEmpty) {
                  // Yatay `hp` ÜST Padding'te zaten uygulanıyor; burada
                  // tekrarlanınca içerik kutusu iki kat daralıyor ve 320pt'de
                  // "İlk Varlığını Ekle" düğmesi 119px taşıyordu.
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                    child: Column(
                      children: [
                        Icon(Icons.savings_outlined,
                            color: context.c.text36, size: 48),
                        const SizedBox(height: SandikSpace.md),
                        Text(
                          'Henüz varlık eklenmemiş',
                          style: context.t.titleLarge
                              ?.copyWith(color: context.c.text90),
                        ),
                        const SizedBox(height: SandikSpace.sm),
                        Text(
                          'İlk varlığını ekleyerek sandığını oluşturmaya başla.',
                          textAlign: TextAlign.center,
                          style: context.t.bodyMedium
                              ?.copyWith(color: context.c.text36),
                        ),
                        const SizedBox(height: SandikSpace.lg),
                        SandikTappable(
                          haptic: SandikHaptic.medium,
                          semanticLabel: 'Varlık ekle',
                          onTap: () => pushGuarded(
                            context,
                            adaptiveRoute(
                                builder: (_) => const AddAssetScreen()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            decoration: BoxDecoration(
                              color: context.c.amberFill.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(SandikRadius.md),
                              border: Border.all(
                                  color: context.c.amberFill.withValues(alpha: 0.5)),
                            ),
                            // 28pt yatay padding + ikon + etiket dar ekranda
                            // sığmıyor. FittedBox içeriği kırpmadan küçültür;
                            // düğme metni her cihazda tam okunur.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded,
                                      color: context.c.amberText, size: 20),
                                  const SizedBox(width: SandikSpace.sm),
                                  Text(
                                    'İlk Varlığını Ekle',
                                    style: context.t.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: context.c.amberText),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Ana sayfa yalnızca son 3 kaydı gösterir; tamamı için
                // `AllTransactionsScreen` (filtre + sayfalama). Burada
                // sınırsız büyütmek, log niteliğindeki bu listeyi ana
                // sayfanın altına yığardı.
                final count = recentAssets.length > 3 ? 3 : recentAssets.length;

                final hideBalance = ref.watch(balanceHiddenProvider);
                return Column(
                  children: List.generate(
                      count,
                      (i) => TransactionRow(
                            asset: recentAssets[i],
                            portfolioState: myState,
                            hideBalance: hideBalance,
                          )),
                );
              }),
            ),
          ),
          // "Tümünü Gör" — hareket ekranına götürür.
          //
          // Sayı ledger'dan okunur, aggregate edilmiş pozisyonlardan DEĞİL:
          // pozisyon sayısı hareket sayısını olduğundan az gösterirdi
          // (3 lot + 1 satış = 1 pozisyon ama 4 hareket).
          if (ledgerCount > 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                child: SandikTappable(
                  semanticLabel: 'Tüm hareketleri gör',
                  onTap: () => pushGuarded(
                    context,
                    adaptiveRoute(
                      builder: (_) => AllTransactionsScreen(
                        allPartnerAssets: allPartnerAssets,
                        partners: partners,
                        initialView: _view,
                        initialTypeFilter: _typeFilter,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: SandikSpace.md),
                    decoration: context.surfaceCard(),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tümünü Gör ($ledgerCount)',
                            style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.c.amberText,
                            ),
                          ),
                          const SizedBox(width: SandikSpace.xs),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 13, color: context.c.amberText),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: SandikSpace.xxl)),
        ],
      ),
    );
  }

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? context.c.amberText;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SandikTappable(
        onTap: () => setState(() => _typeFilter = type),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
              horizontal: SandikSpace.md, vertical: SandikSpace.sm),
          decoration: context.chip(
            selected: selected,
            accent: color,
            radius: SandikRadius.lg,
          ),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : context.c.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _personMiniCard(
      String name, double total, Color color, NumberFormat fmt, String initial,
      {bool hideBalance = false}) {
    final sw = MediaQuery.of(context).size.width;
    final cardFontSize = sw < 360 ? 14.0 : 18.0;
    // Yön A: blur kaldırıldı — opak yüzey. Cam efekti hero karta ayrıldı.
    return Container(
      padding: EdgeInsets.all(sw < 360 ? SandikSpace.sm : SandikSpace.md),
      decoration: context.surfaceCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              initial,
              style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(name,
              style: context.t.bodySmall?.copyWith(
                  color: context.c.text58,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: SandikSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hideBalance ? '••••••' : fmt.format(total),
              // cardFontSize dinamik (tutar uzunluğuna göre küçülür), o
              // yüzden boyut override'ı kalıyor; tabular figür tema'dan.
              style: context.t.numSmall.copyWith(
                  fontSize: cardFontSize,
                  color: context.c.text90),
            ),
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
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: e.key.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                flex: 2,
                child: Text(e.key.label,
                    style: context.t.titleMedium
                        ?.copyWith(color: context.c.text90)),
              ),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                  // Fiyat yenilendiğinde çubuk zıplamak yerine akar.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      backgroundColor: context.c.overlay,
                      color: e.key.color,
                      minHeight: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              SizedBox(
                width: 52,
                child: Text(
                  fmtPct(ratio * 100, digits: 1),
                  textAlign: TextAlign.right,
                  // Sabit 52pt kolonda sağa dayalı — tabular figür şart.
                  style: context.t.numSmall.copyWith(
                      color: context.c.text58,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

}

// ── Sinyaller Bottom Sheet ────────────────────────────────────────────────────

/// Bildirim çanı sayfası.
///
/// **`ConsumerWidget` olmak ZORUNDA.** Sheet ayrı bir route'ta yaşar; listeyi
/// parametre olarak alsaydı (eski hâli) provider güncellemeleri ona ulaşmaz ve
/// silinen bildirim ekranda durmaya devam ederdi.
class _SignalsBottomSheet extends ConsumerWidget {
  /// Geriye `Future` döndürürler: başarısızlık çağırana ulaşmalı ki kullanıcı
  /// "silindi" sanmasın (bkz. `SignalNotifier.dismiss`).
  final Future<void> Function(String id) onDismiss;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function() onDismissAll;
  final void Function(SignalAlert alert) onTap;

  const _SignalsBottomSheet({
    required this.onDismiss,
    required this.onDelete,
    required this.onDismissAll,
    required this.onTap,
  });

  /// Başarısız silmeyi kullanıcıya SÖYLE.
  ///
  /// Sessiz başarısızlık en kötü seçenek: kullanıcı sildiğini sanır, uygulama
  /// yeniden açılınca kayıt geri gelir ve uygulamaya güveni sarsılır.
  static void _hataGoster(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bildirim silinemedi. Bağlantını kontrol et.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.c.loss,
      ),
    );
  }

  /// Silme çağrısını sarar: başarısızlıkta kullanıcıya haber verir.
  ///
  /// Provider iyimser güncelleme yapıp hata durumunda state'i geri alır
  /// (bkz. `SignalNotifier.dismiss`), yani satır ekrana geri döner. Buradaki
  /// görev o geri dönüşü AÇIKLAMAK — satırın sessizce geri gelmesi kullanıcıya
  /// bir hata gibi görünürdü.
  VoidCallback _guarded(BuildContext context, Future<void> Function() action) {
    return () async {
      try {
        await action();
      } catch (_) {
        if (context.mounted) _hataGoster(context);
      }
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = ref.watch(signalProvider).valueOrNull ?? const [];
    final active = signals.where((a) => !a.isDismissed).toList();
    final history = signals.where((a) => a.isDismissed).toList();
    return DefaultTextStyle(
      style: GoogleFonts.dmSans(
          color: context.c.text90, decoration: TextDecoration.none),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            // Sabit koyu yeşildi; light modda ekranın üstünde yabancı bir
            // levha gibi duruyor ve üstündeki (doğru tokenlı) metin
            // okunmuyordu — koyu zemine koyu yazı.
            color: context.c.surface2,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(color: context.c.hairline),
            boxShadow: context.c.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: SandikSpace.md),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.c.text36,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                ),
              ),
              const SizedBox(height: SandikSpace.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Teknik Sinyaller',
                      style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                          decoration: TextDecoration.none),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    if (signals.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.c.amberFill.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                          border: Border.all(
                              color: context.c.amberFill.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${signals.length}',
                          style: context.t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.amberText,
                              decoration: TextDecoration.none),
                        ),
                      ),
                    const Spacer(),
                    if (signals.isNotEmpty)
                      SandikTappable(
                        semanticLabel: 'Tüm sinyalleri temizle',
                        // Toplu ve geri alınamaz bir işlem: HIG "forgiveness"
                        // ilkesi onay ister. Tek satır silmede onay yok
                        // (aşırıya kaçmamak için), ama "tümü" farklıdır.
                        //
                        // Sheet ARTIK HEMEN KAPANMIYOR: eskiden `Navigator.pop`
                        // silme işleminin sonucunu beklemeden çağrılıyordu ve
                        // hata olsa bile kullanıcı temizlenmiş sanıyordu.
                        onTap: () async {
                          final onay = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Tümünü temizle'),
                              content: Text(
                                '${active.length} bildirim listeden '
                                'kaldırılacak. Geri alınamaz.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Vazgeç'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text('Temizle',
                                      style: TextStyle(color: context.c.loss)),
                                ),
                              ],
                            ),
                          );
                          if (onay != true) return;
                          try {
                            await onDismissAll();
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (context.mounted) _hataGoster(context);
                          }
                        },
                        child: Text(
                          'Tümünü Temizle',
                          style: context.t.titleSmall?.copyWith(
                              color: context.c.text36,
                              decoration: TextDecoration.none),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SandikSpace.md),
              if (active.isEmpty && history.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: context.c.gain, size: 22),
                      const SizedBox(width: SandikSpace.md),
                      Text('Şu an aktif sinyal yok',
                          style: context.t.titleMedium?.copyWith(
                              color: context.c.text58,
                              decoration: TextDecoration.none)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.60),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final a in active) ...[
                            _SignalTile(
                              alert: a,
                              faded: false,
                              onTap: () => onTap(a),
                              onDismiss: a.id != null
                                  ? _guarded(context, () => onDismiss(a.id!))
                                  : null,
                              onDelete: a.id != null
                                  ? _guarded(context, () => onDelete(a.id!))
                                  : null,
                            ),
                            const SizedBox(height: SandikSpace.sm),
                          ],
                          if (history.isNotEmpty) ...[
                            const SizedBox(height: SandikSpace.xs),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                              child: Text(
                                'GEÇMİŞ',
                                style: context.t.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: context.c.text58,
                                    decoration: TextDecoration.none),
                              ),
                            ),
                            for (final a in history) ...[
                              _SignalTile(
                                alert: a,
                                faded: true,
                                onTap: () => onTap(a),
                                onDismiss: null,
                                onDelete: a.id != null
                                    ? _guarded(context, () => onDelete(a.id!))
                                    : null,
                              ),
                              const SizedBox(height: SandikSpace.sm),
                            ],
                          ],
                        ],
                      ),
                    ),
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

// ── Tekil sinyal satırı ───────────────────────────────────────────────────────

class _SignalTile extends StatelessWidget {
  final SignalAlert alert;
  final bool faded;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  const _SignalTile({
    required this.alert,
    required this.faded,
    required this.onTap,
    required this.onDismiss,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = alert.signal == SignalType.buy;
    final isSell = alert.signal == SignalType.sell;
    final Color color = isBuy
        ? context.c.gain
        : (isSell ? context.c.loss : context.c.text58);
    final String label = isBuy ? 'AL' : (isSell ? 'SAT' : 'NÖTR');
    final IconData icon = isBuy
        ? Icons.trending_up_rounded
        : (isSell
            ? Icons.trending_down_rounded
            : Icons.horizontal_rule_rounded);
    final int count =
        isBuy ? alert.buyCount : (isSell ? alert.sellCount : 0);

    final double alphaFactor = faded ? 0.45 : 1.0;
    final double bgAlpha = faded ? 0.05 : 0.10;
    final double borderAlpha = faded ? 0.12 : 0.28;

    final Widget content = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: bgAlpha),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border:
              Border.all(color: color.withValues(alpha: borderAlpha), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18 * alphaFactor),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: color.withValues(alpha: alphaFactor), size: 20),
            ),
            const SizedBox(width: SandikSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          alert.assetName,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.c.text90
                                  .withValues(alpha: alphaFactor),
                              decoration: TextDecoration.none),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              color.withValues(alpha: 0.18 * alphaFactor),
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                        ),
                        child: Text(label,
                            style: context.t.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color.withValues(alpha: alphaFactor),
                                decoration: TextDecoration.none)),
                      ),
                    ],
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    faded
                        ? '${_formatDate(alert.detectedAt)} · silindi'
                        : '$count gösterge · ${fmtPct(alert.confidence, digits: 0)} güven',
                    style: context.t.bodySmall?.copyWith(
                        color: context.c.text58.withValues(alpha: alphaFactor),
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: context.c.text36),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
              )
            else if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: context.c.text36),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );

    return content;
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Bugün ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}.${d.month}.${d.year}';
  }
}

// ── Bakiye gizle/göster butonu ────────────────────────────────────────────────

class _BalanceToggleButton extends ConsumerWidget {
  const _BalanceToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balanceHiddenProvider);
    return SandikTappable(
      onTap: () => ref.read(balanceHiddenProvider.notifier).set(!hidden),
      semanticLabel: hidden ? 'Bakiyeyi göster' : 'Bakiyeyi gizle',
      child: Container(
        width: 44,
        height: 44,
        decoration: context.chip(selected: hidden),
        child: Center(
          child: Icon(
            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: hidden ? context.c.amberText : context.c.text58,
            size: 20,
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
    return SandikTappable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: context.chip(selected: false),
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
    final count = ref.watch(activeSignalsProvider).length;

    return SandikTappable(
      onTap: onTap,
      semanticLabel: count > 0 ? '$count yeni sinyal' : 'Sinyaller',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: context.chip(selected: count > 0),
            child: Center(
              child: Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                color: count > 0 ? context.c.amberText : context.c.text58,
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
                  color: context.c.loss,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                  border: Border.all(color: context.c.background, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    count > 9 ? '+9' : '$count',
                    style: context.t.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        // `loss` DOLGU; üstüne yüzey metni (`text90`) değil
                        // dolgu mürekkebi gelir — light modda 2.89:1 idi.
                        color: context.c.onStatus),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
