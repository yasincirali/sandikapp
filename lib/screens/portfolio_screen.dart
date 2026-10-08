import 'dart:async' show FutureOr, unawaited;

import '../widgets/sandik_skeleton.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart'
    show
        RefreshIndicator,
        Material,
        MaterialType,
        ListTile,
        Divider;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/base_currency_provider.dart';
import '../providers/price_alert_provider.dart';
import '../widgets/alarm_kur_sheet.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/sozlesme.dart';
import '../models/position.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/sparkline_service.dart';
import '../theme/sandik.dart';
import '../widgets/sekme_basa_don.dart';
import '../widgets/sandik_acilir.dart';
import '../widgets/delete_asset_dialog.dart';
import '../utils/tr_format.dart';
import '../widgets/asset_sparkline.dart';
import '../widgets/mevduat_vade_seridi.dart';
import '../widgets/tour_anchor.dart';
import '../widgets/ortak_secici.dart';
import '../widgets/sandik_segment.dart';
import '../widgets/varlik_baslik_hero.dart';
import '../services/remote_config_service.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/pozisyon_islemleri.dart';
import 'comparison_screen.dart';
import 'asset_detail_screen.dart';
import 'watchlist_screen.dart';
import '../providers/watchlist_provider.dart';
import '../l10n/l10n.dart';
import '../widgets/gorunum_cipi.dart';
import '../services/islem_notu.dart';
import '../widgets/islem_notu_sheet.dart';
import '../widgets/fon_karnesi_karti.dart';
import '../widgets/transaction_row.dart' show hareketTurEtiketi;

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

  /// Varlıklarım listesinin denetleyicisi — açık Portföy sekmesine yeniden
  /// dokununca başa döner (bkz. [SekmeBasaDon], animasyon denetimi
  /// 2026-10-01).
  final _kaydirma = ScrollController();
  late final VoidCallback _basaDonBirak;

  // ── Yeni eklenen varlık (animasyon denetimi 2026-10-01, özgün dokunuş) ──
  //
  // Varlık eklenince uygulama Portföy sekmesine geçiyor ama yeni satır
  // ötekilerin arasında hiçbir işaret vermeden duruyordu; uzun listede
  // kullanıcı "nereye gitti?" diye arıyordu. Şimdi liste o satıra kayar ve
  // satır BİR KEZ amber çerçeveyle parlayıp söner. Ekleme ekranı kimlik
  // döndürmediği için yeni satır, bir önceki kurulumda görülen anahtar
  // kümesinden farkla bulunur: ilk yüklemede, görünüm (Ben/ortak/Birlikte)
  // değişince ve birden çok satır birden gelince (toplu ekleme, ilk senkron)
  // parlatılmaz — yalnız "tek yeni satır" anı.

  /// Önceki kurulumda görülen pozisyon anahtarları; `null` = henüz yok.
  Set<String>? _gorulenAnahtarlar;
  String? _gorulenGorunum;

  /// Parlatılacak satır ve onu görünür kılmak için anahtarı.
  String? _vurgulanan;
  final _vurguAnahtari = GlobalKey();

  void _yeniSatiriBul(List<Position> positions) {
    final anahtarlar = {for (final p in positions) p.key};
    final onceki = _gorulenAnahtarlar;
    final ayniGorunum = _gorulenGorunum == _view;
    _gorulenAnahtarlar = anahtarlar;
    _gorulenGorunum = _view;
    // Görünüm değişince eski parlama bir daha oynamasın.
    if (!ayniGorunum) _vurgulanan = null;
    if (onceki == null || !ayniGorunum) return;
    final yeni = anahtarlar.difference(onceki);
    if (yeni.length != 1) return;
    _vurgulanan = yeni.single;
    // Build içindeyiz: kaydırma kareden sonra. Satır liste dışındaysa
    // (filtre) bağlam yoktur, sessizce geçer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _vurguAnahtari.currentContext;
      if (!mounted || c == null) return;
      Scrollable.ensureVisible(
        c,
        alignment: 0.3,
        duration: SandikMotion.surfaceOf(context),
        curve: SandikMotion.move,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _basaDonBirak = SekmeBasaDon.dinle(
        1, () => SekmeBasaDon.basaKaydir(context, _kaydirma));
  }

  @override
  void dispose() {
    _basaDonBirak();
    _kaydirma.dispose();
    super.dispose();
  }
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

  /// Dağılım şeridinin "Halka ›" bağlantısı: eski halkayı alt sayfada açar.
  ///
  /// Halkanın dilim dokunuşu sayfanın ARKASINDAKİ listeyi süzer — çiplerle
  /// aynı `_filteredType`. Halka mevcut süzgeçle açılır ki şeritte seçili
  /// tür halkada da seçili görünsün. Sayfa dilim seçilince kapanmaz: ortadaki
  /// tutar/yüzde halkanın asıl bilgisidir, kapanırsa görünmez.
  void _halkayiAc(List<Asset> varliklar, PortfolioState pState) {
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.c.surface1,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (sayfa) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(SandikSpace.md, SandikSpace.smd,
            SandikSpace.md, SandikSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SandikTutamac(),
            const SizedBox(height: SandikSpace.md),
            SandikSectionHeader(title: sayfa.l10n.s3DagilimBaslik),
            const SizedBox(height: SandikSpace.md),
            _AssetTypeDonut(
              assets: varliklar,
              pState: pState,
              baz: ref.read(gosterimBazParaProvider),
              baslangicTuru: _filteredType,
              onTypeSelected: (type) {
                if (mounted) setState(() => _filteredType = type);
              },
            ),
          ],
        ),
      ),
    );
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
    // Gizlenen/çıkarılan ortak seçili görünümde KALMASIN: toplam ₺0'a düşer
    // (bkz. `GorunumCipi.gecerli`, 2026-09-28).
    ref.listen(activePartnersProvider, (_, next) {
      final v = GorunumCipi.gecerli(next, _view);
      if (v != _view) {
        setState(() {
          _view = v;
          _filteredType = null;
        });
      }
    });

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;

    return CupertinoPageScaffold(
      backgroundColor: context.c.background,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              // Ölçüler Performans ekranının başlık çubuğuyla BİREBİR
              // (2026-09-28): dikey xs, başlık `headlineMedium`. Eskiden
              // 12/`headlineLarge`+22pt idi ve sekmeler arasında üst
              // şerit zıplıyordu.
              Padding(
                padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                    SandikSpace.xs, SandikSpace.screenH(context), SandikSpace.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.portfolio,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: context.t.headlineMedium
                            ?.copyWith(color: context.c.text90),
                      ),
                    ),
                    _SortButton(
                      current: _sortOrder,
                      onChanged: (o) => setState(() => _sortOrder = o),
                    ),
                    // Düğme aralığı her ekranda `SandikSpace.sm`
                    // (2026-09-28; burada 8 ve 4 karışıktı).
                    const SizedBox(width: SandikSpace.sm),
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
                      onPressed: () => pushGuarded(
                        context,
                        adaptiveRoute<void>(
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
                              semanticLabel: context.l10n.compare,
                              color: context.c.amberText, size: 22),
                        ),
                      ),
                    ),
                    // Çıkış düğmesi KALDIRILDI (sadeleştirme 2026-10-04):
                    // dört sekmenin dördünde de duruyordu; yanlışlıkla
                    // dokunulan, işi bitiren bir eylem. Ana ekran üst barında
                    // (kullanıcı kuralı) ve Profil'de kalır.
                  ],
                ),
              ),
              // ── Gövde sekmesi ─────────────────────────────────────────────
              // Takip listesinin giriş noktası. Gövdenin en üstünde durur;
              // üst bar (sırala · karşılaştır · çıkış) kalabalıklaşmaz.
              Padding(
                padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 0, SandikSpace.screenH(context), 8),
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
                  // Yeniden yüklemede (bağımlılık tazelendi, ör. ortak listesi ya da
                  // oturum belirteci) önceki veri ekranda KALIR. Varsayılan `when`
                  // bu anda tam ekran yükleme çizip geri dönüyordu: ekran bir kare
                  // boşalıp doluyordu (titreme bulgusu 2026-10-02). Ana ekran aynı
                  // şeyi `valueOrNull` ile baştan beri yapıyor.
                  skipLoadingOnReload: true,
                  loading: () => const SandikLoadingScreen(),
                  error: (e, _) => SandikErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(portfolioProvider)),
                  data: (pState) => RefreshIndicator.adaptive(
                    color: context.c.amberText,
                    // Kullanıcı yenilemesi — fiyat önbelleği atlanır.
                    onRefresh: () => ref
                        .read(portfolioProvider.notifier)
                        .refreshPrices(force: true),
                    // Kaydırma paneli grubu listenin TAMAMINI sarar: kartlar
                    // artık doğrudan dış listenin çocukları (bkz. [_AssetList]).
                    child: SlidableAutoCloseBehavior(
                    child: ListView(
                      // Varlıklarım ↔ Takip Listesi geçişinde liste sökülüp
                      // yeniden kuruluyor; anahtar konumu PageStorage'da
                      // tutar — geri dönünce kaldığı yerden devam eder
                      // (animasyon denetimi 2026-10-01: her geçişte başa
                      // atıyordu).
                      key: const PageStorageKey('portfoy-varliklarim'),
                      controller: _kaydirma,
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 80),
                      children: [
                        if (activePartners.isNotEmpty)
                          OrtakSecici(
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
                        //
                        // Sonuç bir LİSTE ve dış listeye YAYILIR (`...`):
                        // kartlar dış ListView'in doğrudan çocuğu olunca
                        // yalnızca görünenler kurulur (bkz. [_AssetList]).
                        ...(partnerAssetsAsync.valueOrNull == null
                            ? <Widget>[
                                partnerAssetsAsync.hasError
                                ? SandikErrorView(
                                    error: partnerAssetsAsync.error!,
                                    onRetry: () =>
                                        ref.invalidate(portfolioProvider))
                                : const SizedBox(
                                    height: 300,
                                    child: SandikSkeletonList(
                                        rows: 4, padding: EdgeInsets.zero),
                                  )]
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

                                // Birlikte'de aynı varlık TEK satır: hesap
                                // sahip başına kalır, satır parçaların
                                // toplamını gösterir (bkz. `BirlesikPozisyon`;
                                // "KCHOL iki kez görünüyor", 2026-10-01).
                                final positions = sahiplerArasiBirlestir(
                                    aggregatePositionsByOwner(ownerLots));
                                _yeniSatiriBul(positions);

                                if (positions.isEmpty) {
                                  return const <Widget>[_EmptyState()];
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

                                return <Widget>[
                                    // Sadeleştirme 2 (bayrak
                                    // `portfoy_dagilim_cubugu`): ~390pt'lik
                                    // halka listeyi ekranın altına itiyordu;
                                    // aynı bilgi (tür payı + türe göre süzme)
                                    // tek şerit + çiplerle ~120pt'ye sığar.
                                    // Halka kaybolmaz: "Halka ›" onu alt
                                    // sayfada açar. Bayrak kapalıyken eski
                                    // halka birebir.
                                    if (RemoteConfigService
                                        .instance.portfoyDagilimCubugu) ...[
                                      _DagilimCubugu(
                                        dilimler: turDagilimi(
                                            displayAssets, pState),
                                        secili: _filteredType,
                                        onTypeSelected: (type) => setState(
                                            () => _filteredType = type),
                                        onHalka: () => _halkayiAc(
                                            displayAssets, pState),
                                      ),
                                      const SizedBox(height: SandikSpace.lg),
                                    ] else ...[
                                    _AssetTypeDonut(
                                      assets: displayAssets,
                                      pState: pState,
                                      baz: ref.watch(gosterimBazParaProvider),
                                      onTypeSelected: (type) =>
                                          setState(() => _filteredType = type),
                                    ),
                                    const SizedBox(height: 32),
                                    ],
                                    ..._AssetList(
                                      vurgulanan: _vurgulanan,
                                      vurguAnahtari: _vurguAnahtari,
                                      positions: filteredPositions,
                                      pState: pState,
                                      baz: ref.watch(gosterimBazParaProvider),
                                      currentUserId: currentUserId,
                                      // Ham `CupertinoPageRoute` + korumasız
                                      // push: satıra hızlı iki dokunuş aynı
                                      // detay ekranını iki kez açıyor, Android'de
                                      // de iOS geçişi veriyordu (2026-09-23
                                      // denetimi F21).
                                      heroAcik: RemoteConfigService
                                          .instance.varlikHeroGecisi,
                                      onTap: (p, hero) => pushGuarded(
                                        context,
                                        adaptiveRoute<void>(
                                            builder: (_) => AssetDetailScreen(
                                                  asset: p.asDisplayAsset(),
                                                  showBackButton: true,
                                                  lots: p.lots,
                                                  heroEtiketi: hero,
                                                )),
                                      ),
                                      onDelete: (p) =>
                                          _confirmDelete(context, ref, p),
                                      // Varlık ekranının işlem çubuğuyla
                                      // AYNI kod yolu (`pozisyonIslemiAc`).
                                      onAdd: (p) => pozisyonIslemiAc(
                                          context, ref,
                                          varlik: p.asDisplayAsset(),
                                          islem: PozisyonIslemi.al),
                                      onRemove: (p) => pozisyonIslemiAc(
                                          context, ref,
                                          varlik: p.asDisplayAsset(),
                                          islem: PozisyonIslemi.sat),
                                      onDividend: (p) => pozisyonIslemiAc(
                                          context, ref,
                                          varlik: p.asDisplayAsset(),
                                          islem: PozisyonIslemi.temettu),
                                    ).kartlar(),
                                ];
                              })(partnerAssetsAsync.valueOrNull!)),
                      ],
                    ),
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

  // Kabuk ortak [SandikSegment] (tek seçici, 2026-10-08 — yol haritası
  // 2.12). Eskiden amber dolgulu, kendi elle yazılmış bir segmentti; hemen
  // altındaki ortak seçici (`OrtakSecici`) kayan zeminliydi ve aynı ekranda
  // iki farklı "birini seç" görünüşü vardı. Dokunma hedefi (≥ 44 pt,
  // `SandikTouch`), seçili/düğme semantiği ve seçiliye dokunuşun yok
  // sayılması artık bileşenin sözleşmesi; burada tekrar yazılmaz.
  @override
  Widget build(BuildContext context) {
    final etiketler = [context.l10n.myAssets, context.l10n.watchlist];
    final rozetler = <int?>[null, count > 0 ? count : null];
    return SandikSegment(
      adet: 2,
      secili: selected,
      onSec: onChanged,
      // Rozetli sekme sayıyı da okutur ("Takip listesi, 3 varlık").
      semantik: (i) => rozetler[i] == null
          ? etiketler[i]
          : context.l10n.tabSemanticsCount(etiketler[i], rozetler[i]!),
      oge: (context, i, secili) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              etiketler[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          if (rozetler[i] != null) ...[
            const SizedBox(width: 6),
            _SayiRozeti(sayi: rozetler[i]!),
          ],
        ],
      ),
    );
  }
}

/// Gövde sekmesindeki sayı rozeti. Seçimden bağımsız tek ton: seçim artık
/// amber dolgu değil kayan nötr zemin olduğu için rozetin seçiliye göre
/// renk tersinmesi (onAmber) gereksizleşti.
class _SayiRozeti extends StatelessWidget {
  const _SayiRozeti({required this.sayi});

  final int sayi;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: context.c.amberFill.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
        child: Text(
          '$sayi',
          style: context.t.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.c.amberText,
          ),
        ),
      );
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

// ── Dağılım şeridi (bayrak `portfoy_dagilim_cubugu`) ─────────────────────────

/// Tür başına pay — dağılım şeridinin verisi, büyükten küçüğe.
///
/// Hesap halkanınkiyle AYNI (`pState.toTRY(totalValue, currency)` toplamı):
/// şerit ile "Halka ›" sayfası aynı yüzdeleri göstermeli. `build()` dışında,
/// saf fonksiyon olarak durur ki test edilebilsin.
List<({AssetType tur, double tutar, double pay})> turDagilimi(
    List<Asset> varliklar, PortfolioState pState) {
  final toplamlar = <AssetType, double>{};
  var toplam = 0.0;
  for (final a in varliklar) {
    final v = pState.toTRY(a.totalValue, a.currency);
    toplamlar[a.type] = (toplamlar[a.type] ?? 0) + v;
    toplam += v;
  }
  final sirali = toplamlar.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in sirali)
      (tur: e.key, tutar: e.value, pay: toplam > 0 ? e.value / toplam : 0.0),
  ];
}

/// Halkanın yerine geçen kompakt kart: başlık + tek yığılmış şerit + çipler.
///
/// Çip dokunuşu halka dilimiyle aynı işi yapar (`onTypeSelected`); seçili
/// çipe yeniden dokunmak ya da "Tümü" süzgeci kaldırır. Seçim durumu
/// ebeveynin `_filteredType`'ıdır — şeridin kendi durumu yok, böylece
/// "Halka ›" sayfasında yapılan seçim de burada görünür.
class _DagilimCubugu extends StatelessWidget {
  const _DagilimCubugu({
    required this.dilimler,
    required this.secili,
    required this.onTypeSelected,
    required this.onHalka,
  });

  final List<({AssetType tur, double tutar, double pay})> dilimler;
  final AssetType? secili;
  final ValueChanged<AssetType?> onTypeSelected;
  final VoidCallback onHalka;

  @override
  Widget build(BuildContext context) {
    if (dilimler.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return SandikCard(
      padding: const EdgeInsets.fromLTRB(
          SandikSpace.md, SandikSpace.xs, SandikSpace.xs, SandikSpace.smd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(
            title: l10n.s3DagilimBaslik,
            // Ekran Cupertino tabanlı (sıralama düğmesiyle aynı yol).
            trailing: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding:
                  const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
              onPressed: onHalka,
              child: Text(
                l10n.s3HalkaBaglanti,
                style: context.t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.c.amberText,
                ),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.xs),
          Padding(
            padding: const EdgeInsets.only(right: SandikSpace.smd),
            // Tek yığılmış şerit: segmentler halkanın renkleriyle, aralarında
            // ince boşluk. Pay `flex` olarak binde bir hassasiyetle verilir;
            // küçük bir tür bile en az 1 pay alır ki görünmez olmasın.
            // Şerit dokunulmaz: 12pt'lik dilim 44pt hedef veremez, süzme
            // çiplerdedir.
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SandikSpace.xs2),
                child: SizedBox(
                  height: SandikSpace.smd,
                  child: Row(
                    children: [
                      for (var i = 0; i < dilimler.length; i++) ...[
                        if (i > 0) const SizedBox(width: SandikSpace.xxs),
                        Expanded(
                          flex: (dilimler[i].pay * 1000).round().clamp(1, 1000),
                          child: AnimatedOpacity(
                            duration: SandikMotion.stateOf(context),
                            curve: SandikMotion.enter,
                            opacity:
                                secili == null || secili == dilimler[i].tur
                                    ? 1.0
                                    : 0.35,
                            child: ColoredBox(color: dilimler[i].tur.color),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Wrap(
            spacing: SandikSpace.xs2,
            children: [
              _DagilimCipi(
                etiket: l10n.allTypes,
                tur: null,
                secili: secili == null,
                onTap: () => onTypeSelected(null),
              ),
              for (final d in dilimler)
                _DagilimCipi(
                  etiket:
                      '${d.tur.labelOf(l10n)} ${fmtPct(d.pay * 100, digits: 1)}',
                  tur: d.tur,
                  secili: secili == d.tur,
                  onTap: () => onTypeSelected(secili == d.tur ? null : d.tur),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dağılım çipi: görsel ~30pt, dokunma hedefi 44pt (`SandikTouch.min`).
class _DagilimCipi extends StatelessWidget {
  const _DagilimCipi({
    required this.etiket,
    required this.tur,
    required this.secili,
    required this.onTap,
  });

  final String etiket;

  /// `null`: "Tümü" çipi (nokta yok, seçim rengi amber).
  final AssetType? tur;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tur = this.tur;
    final vurgu = tur?.color ?? context.c.amberFill;
    final metinRengi = secili
        ? (tur?.onSurface(context) ?? context.c.amberText)
        : context.c.text58;
    return Semantics(
      button: true,
      selected: secili,
      child: SandikBasma(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
              decoration: BoxDecoration(
                color:
                    secili ? vurgu.withValues(alpha: 0.15) : context.c.overlay,
                borderRadius: BorderRadius.circular(SandikRadius.sm),
                border: Border.all(
                  color:
                      secili ? vurgu.withValues(alpha: 0.6) : context.c.overlay,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tur != null) ...[
                    Container(
                      width: SandikSpace.sm,
                      height: SandikSpace.sm,
                      decoration: BoxDecoration(
                        color: tur.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: SandikSpace.xs2),
                  ],
                  // Büyük yazıda tek çip satıra sığmazsa kısaltılır (halka
                  // lejantındaki taşma dersi).
                  Flexible(
                    child: Text(
                      etiket,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: metinRengi,
                      ),
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
}

// ── Donut Chart ───────────────────────────────────────────────────────────────

class _AssetTypeDonut extends StatefulWidget {
  final List<Asset> assets;
  final PortfolioState pState;
  final BazPara baz;
  final void Function(AssetType?) onTypeSelected;

  /// Halka açılırken seçili gelecek tür (dağılım şeridinin "Halka ›"
  /// sayfası; bkz. `_halkayiAc`). Ekrandaki eski halkada verilmez — orada
  /// seçim halkanın kendi durumudur.
  final AssetType? baslangicTuru;
  const _AssetTypeDonut(
      {required this.assets,
      required this.pState,
      required this.baz,
      required this.onTypeSelected,
      this.baslangicTuru});

  @override
  State<_AssetTypeDonut> createState() => _AssetTypeDonutState();
}

class _AssetTypeDonutState extends State<_AssetTypeDonut> {
  int? _touchedIndex;

  /// [_AssetTypeDonut.baslangicTuru] yalnız İLK kurulumda uygulanır; sonra
  /// seçim kullanıcının dokunuşudur.
  bool _baslangicUygulandi = false;

  /// Son çizilen dilimler (tür → pay) ve seçili dilim. Halka YALNIZ
  /// görünür bir değişimde morf eder (animasyon denetimi 2026-10-01,
  /// ölçüm): `PieChartData` dokunma geri çağrısı taşıdığı için fl_chart her
  /// kurulumu "yeni veri" sayıyor, fiyatı değişmeyen her 30 sn tikinde
  /// 12 kare boşuna boyuyordu. Paydaki binde birin altındaki oynama da
  /// gözle görülmez; o da anında uygulanır.
  List<(AssetType, double)>? _oncekiPaylar;
  int? _oncekiDokunulan;

  bool _gorunurDegisti(List<MapEntry<AssetType, double>> dilimler, double toplam) {
    final paylar = [
      for (final d in dilimler) (d.key, toplam > 0 ? d.value / toplam : 0.0),
    ];
    final eski = _oncekiPaylar;
    final eskiDokunulan = _oncekiDokunulan;
    _oncekiPaylar = paylar;
    _oncekiDokunulan = _touchedIndex;
    if (eski == null || eski.length != paylar.length) return true;
    if (eskiDokunulan != _touchedIndex) return true;
    for (var i = 0; i < paylar.length; i++) {
      if (eski[i].$1 != paylar[i].$1) return true;
      if ((eski[i].$2 - paylar[i].$2).abs() > 0.001) return true;
    }
    return false;
  }

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
    if (!_baslangicUygulandi) {
      _baslangicUygulandi = true;
      final i = widget.baslangicTuru == null
          ? -1
          : sorted.indexWhere((e) => e.key == widget.baslangicTuru);
      if (i >= 0) _touchedIndex = i;
    }
    final morf = _gorunurDegisti(sorted, totalVal);
    final touched = _touchedIndex != null && _touchedIndex! < sorted.length
        ? sorted[_touchedIndex!]
        : null;

    // Ortada gösterilecek metin
    final centerLabel =
        touched != null ? touched.key.labelOf(context.l10n) : context.l10n.total;
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
              // RepaintBoundary: halka morf ederken (dilim seçimi, fiyat
              // tiki) kart listesiyle aynı katmanda boyanıyordu — her karede
              // bütün liste yeniden çiziliyordu. Süre/eğri token'dan: fl_chart
              // varsayılanı 150 ms DOĞRUSAL ve hareketi azalt'ı bilmez
              // (animasyon denetimi 2026-10-01).
              RepaintBoundary(
                child: PieChart(
                swapAnimationDuration:
                    morf ? SandikMotion.stateOf(context) : Duration.zero,
                swapAnimationCurve: SandikMotion.enter,
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
            return SandikBasma(
              onTap: () {
                final newIdx = _touchedIndex == e.key ? null : e.key;
                setState(() => _touchedIndex = newIdx);
                widget
                    .onTypeSelected(newIdx != null ? sorted[newIdx].key : null);
              },
              child: AnimatedOpacity(
                duration:
                    SandikMotion.stateOf(context),
                // Eksikti: curve verilmeyince Curves.linear devreye girer.
                // Lejant sönümlemesi bir DURUM değişimidir → enter.
                curve: SandikMotion.enter,
                opacity: _touchedIndex == null || isTouched ? 1.0 : 0.45,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
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
                        '${e.value.key.labelOf(context.l10n)} $pct',
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

/// Varlık kartlarını üretir — WIDGET DEĞİL, dış listeye yayılan bir liste.
///
/// Eskiden `ListView.builder(shrinkWrap: true, NeverScrollable)` idi ve
/// yorumu "yalnızca görünür aralığı kurar" diyordu; doğru değildi:
/// sınırsız yükseklikte `shrinkWrap` görünümü, boyunu bulmak için BÜTÜN
/// kartları kurar ve yerleştirir. Her kartta `Slidable` + `ClipRRect` +
/// `AnimatedSize` var; büyük portföyde her fiyat tikinde hepsi yeniden
/// kuruluyor, bir kart açılınca iç ve dış liste her karede yeniden
/// yerleşiyordu (animasyon denetimi 2026-10-01). Kartlar artık dış
/// `ListView`'in doğrudan çocukları: yalnızca ekrana girenler kurulur.
/// Kaydırma paneli grubu (`SlidableAutoCloseBehavior`) dış listeyi sarar.
class _AssetList {
  final List<Position> positions;
  final PortfolioState pState;
  final BazPara baz;
  final String? currentUserId;

  /// İkinci argüman başlık uçuşunun etiketi (bayrak kapalı → `null`).
  final void Function(Position, Object? heroEtiketi) onTap;
  final void Function(Position) onDelete;

  /// `varlik_hero_gecisi` (yol haritası 2.14).
  final bool heroAcik;
  // Bu üçü dialog açar ve `Future` döndürür; kaydırma paneli dialog
  // KAPANDIKTAN sonra kapanabilsin diye tip `void` değil `FutureOr<void>`.
  // `void` kalsaydı `await` beklemez, panel yine erken kapanırdı.
  final FutureOr<void> Function(Position) onAdd;
  final FutureOr<void> Function(Position) onRemove;
  final FutureOr<void> Function(Position) onDividend;

  /// Bir kez parlayacak yeni satırın anahtarı (bkz. `_yeniSatiriBul`).
  final String? vurgulanan;
  final GlobalKey vurguAnahtari;

  const _AssetList({
    required this.vurgulanan,
    required this.vurguAnahtari,
    required this.positions,
    required this.pState,
    required this.baz,
    required this.currentUserId,
    required this.onTap,
    required this.onDelete,
    required this.onAdd,
    required this.onRemove,
    required this.onDividend,
    this.heroAcik = false,
  });

  /// Kullanıcının bu satırdaki KENDİ pozisyonu — yoksa `null` (satır
  /// tamamen ortağın). Birleşik satırda yalnız kendi parçası: aksiyonlar
  /// ortağın lot'una yazamaz (RLS) ve Sil yalnız kendi lot'larını siler.
  Position? _kendiParcasi(Position p) {
    if (currentUserId == null) return null;
    if (p is BirlesikPozisyon) return p.parcasi(currentUserId);
    return p.representative.userId == currentUserId ? p : null;
  }

  List<Widget> kartlar() => [
        // Sıralama değişince kartlar yeniden kullanılmasın: aksi halde bir
        // satırın açık/kapalı durumu ve sparkline'ı başka varlığa taşınır.
        for (final position in positions)
          _kart(position, _kendiParcasi(position)),
      ];

  Widget _kart(Position position, Position? kendi) {
    // Etiket GÖSTERİLEN satırın anahtarından: tekil (`ValueKey` ile aynı),
    // açılan pozisyon ortak satırda farklı olsa da.
    final hero = heroAcik ? varlikHeroEtiketi(position.key) : null;
    return _YeniVarlikParlamasi(
        key: ValueKey(position.key),
        aktif: position.key == vurgulanan,
        child: _AssetCard(
          key: position.key == vurgulanan ? vurguAnahtari : null,
          position: position,
          pState: pState,
          baz: baz,
          canEdit: kendi != null,
          heroEtiketi: hero,
          // Varlık ekranı tek sahipli pozisyon bekler; birleşik satırda
          // önce kendi parçası, yoksa ilk sahibinki.
          onTap: (p) => onTap(
              kendi ?? (p is BirlesikPozisyon ? p.parcalar.first : p), hero),
          onDelete: (_) => onDelete(kendi!),
          onAdd: (_) => onAdd(kendi!),
          onRemove: (_) => onRemove(kendi!),
          onDividend: (_) => onDividend(kendi!),
        ),
      );
  }
}

/// Yeni eklenen satırın tek seferlik parlaması: amber çerçeve belirir ve
/// yavaşça söner (~1,1 sn). Yalnız RENK — konum/ölçek yok; bu yüzden
/// "hareketi azalt" açıkken de gösterilir (bkz. `DegisimVurgusu`).
///
/// Sekme görünür olana ve ekleme ekranı kapanana kadar bekler: Portföy
/// gizli sekmedeyken (`TickerMode` kapalı) saat yine akar ve parlama
/// kimse görmeden biterdi.
class _YeniVarlikParlamasi extends StatefulWidget {
  const _YeniVarlikParlamasi({
    super.key,
    required this.aktif,
    required this.child,
  });

  final bool aktif;
  final Widget child;

  @override
  State<_YeniVarlikParlamasi> createState() => _YeniVarlikParlamasiState();
}

class _YeniVarlikParlamasiState extends State<_YeniVarlikParlamasi>
    with SingleTickerProviderStateMixin {
  // Yalnız parlayacak satırda kurulur: tembel `late` denetleyici hiç
  // parlamayan kartta ilk kez `dispose` içinde kurulup ağaçtan ata
  // arıyordu ("deactivated widget's ancestor", kart listesi testleri).
  AnimationController? _c;
  ValueListenable<TickerModeData>? _gorunurluk;

  @override
  void initState() {
    super.initState();
    if (widget.aktif) {
      _c = AnimationController(
        vsync: this,
        duration: SandikMotion.flow * 2,
        value: 1,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _bekleVeYak());
    }
  }

  void _bekleVeYak() {
    if (!mounted) return;
    final g = TickerMode.getValuesNotifier(context);
    if (g.value.enabled) {
      _yak();
      return;
    }
    _gorunurluk = g..addListener(_gorunurlukDegisti);
  }

  void _gorunurlukDegisti() {
    if (!mounted || !(_gorunurluk?.value.enabled ?? false)) return;
    _gorunurluk?.removeListener(_gorunurlukDegisti);
    _gorunurluk = null;
    _yak();
  }

  void _yak() {
    // Ekleme ekranı alttan iniyor; parlama onun ARDINDAN görünsün. Ticker
    // future'ı hata üretmez (yalnız `orCancel` üretir) — beklenmez.
    Future<void>.delayed(SandikMotion.modal, () {
      final c = _c;
      if (mounted && c != null) c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _gorunurluk?.removeListener(_gorunurlukDegisti);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (!widget.aktif || c == null) return widget.child;
    final amber = context.c.amberFill;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        final t = SandikMotion.glide.transform(c.value);
        if (t >= 1) return child!;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: amber.withValues(alpha: 0.9 * (1 - t)),
              width: 2,
            ),
          ),
          child: child,
        );
      },
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
      builder: (innerContext) => SandikBasma(
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

    // Yön METİNDE de yazılır (bulgu #6, 2026-09-29): eskiden tutar ve yüzde
    // mutlak değerdi ("ATATP ₺5 · %2,23" zararda), yön yalnız renk ve oktan
    // okunuyordu — renk körü ve ekran okuyucu için kayıp. Tutar U+2212 ile,
    // yüzde `fmtPctIsaretli` ile: Ana'daki Bugün kartıyla aynı dil. Tutarın
    // işareti yüzdenin işaretiyle aynı kaynaktan (`gainLossTRY`) gelir.
    final String label = isFlat
        ? context.l10n.noChange
        : '${isPositive ? '+' : '\u2212'}${tryFmt.format(gainLossTRY.abs())}'
            ' · ${fmtPctIsaretli(pct)}';

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

  /// Başlık uçuşu etiketi (`varlik_baslik_hero.dart`); `null` → uçuş yok.
  final Object? heroEtiketi;
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
    this.heroEtiketi,
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
                                  child: VarlikBaslikHero(
                                    etiket: widget.heroEtiketi,
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
                              _satirAltMetni(context, a),
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
          // Ok ile panel AYNI süre ve eğriyle (animasyon denetimi,
          // 2026-09-30): ok 200, panel 220 ms'de bitiyordu — hareket tek
          // parça hissettirmiyordu. 2026-10-01: ortak [SandikAcilir] —
          // kapanırken panel ilk karede silinmiyor, solarak kapanıyor.
          SandikAcilir(
            acik: _expanded,
            child: _AssetDetailsPanel(
                position: position, pState: pState, baz: widget.baz),
          ),
        ],
      ),
    );

    // Kural varlık ekranının çubuğuyla ortak (`pozisyonIslemleri`).
    final showsDividend =
        pozisyonIslemleri(a).contains(PozisyonIslemi.temettu);

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
                label: context.l10n.buyAction,
              ),
              _rowAction(
                context,
                onPressed: () => onRemove(position),
                background: context.c.loss.withValues(alpha: 0.85),
                foreground: context.c.onStatus,
                icon: Icons.trending_down_rounded,
                label: context.l10n.sellAction,
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
                  label: context.l10n.dividend,
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
                label: context.l10n.deleteAction,
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
        label: context.l10n.activeAlertsCount(aktif),
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
    // Etiket + açık/kapalı durumu (emülatör testi #28): ok yalnızca
    // görseldi, TalkBack etiketsiz bir düğme okuyordu.
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: expanded
          ? context.l10n.hideDetailsSemantics
          : context.l10n.showDetailsSemantics,
      child: SandikBasma(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Dokunma alanı 44×44 (HIG #37, High severity) — görsel ikon 32'de
      // kalır. `Container` 32 iken parmakla ıskalanabiliyordu; büyütmek
      // yerine ŞEFFAF dolgu ekliyoruz, böylece yerleşim değişmez.
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: SandikAcilirOk(
          acik: expanded,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.c.text58,
            size: 22,
          ),
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
    // Tutarlar (toplam maliyet, güncel değer, temettü) 2 ondalık — 2026-09-23
    // denetimi U14: 3 ondalık "₺10.000,000" on milyon gibi okunuyordu.
    // Birim fiyat (ortalama maliyet) `numFmt` ile değişken hassasiyette
    // kalır; fon fiyatında 4-6 hane anlamlıdır.
    final tryFmt2 = baz.formatter(digits: 2);
    final numFmt = qtyFormatter(maxDigits: rep.azamiOndalik);
    final costFmt2 = fixedFormatter(2);

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

    // Mevduatta miktar (birim) ve ortalama maliyet (1 TRY) iç hesabın
    // paylarıdır, kullanıcıya bir şey söylemez (2026-10-01 emülatör testi);
    // panel ilk alış + toplam maliyet + güncel tutar gösterir.
    final birimsiz = rep.type == AssetType.mevduat;
    final toplamMaliyet = _DetailItem(
      label: context.l10n.totalCost,
      // Alış para biriminde yazılır, `baz`dan geçmez → gizleme
      // elle (bulgu #3). Ortalama maliyet birim FİYATTIR, açık.
      value: position.weightedPurchasePrice <= 0
          ? '—'
          : baz.gizli
              ? baz.gizliTutar
              : '${costFmt2.format(position.totalCost)} ${rep.currency}',
    );

    // Grafiğin rengi satırdaki yüzdeyle aynı kaynaktan gelmeli (temettü dahil),
    // yoksa eğri yeşilken yazı kırmızı olabilir.
    // Tek kaynak: hem kâr/zarar hem de aşağıdaki temettü satırı bunu kullanır.
    // İki ayrı çağrı yapılsaydı biri değişip diğeri kalınca panel kendi
    // içinde çelişirdi (Şu ana kadar bu projede beş kez yaşanmış sınıf).
    final dividendTRY = totalDividendTRY(position.lots);
    final gainLossTRY =
        currentValueTRY - position.totalCostTRY + dividendTRY;

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
          // Mevduat: fiyat eğrisi yerine vade şeridi (2026-10-02). Vadeli
          // mevduatın değeri vade içinde düzdür; eğri boş/düz kalıyordu.
          if (rep.type == AssetType.mevduat) ...[
            MevduatVadeSeridi(
                temsilci: rep, pay: position.totalQuantity, baz: baz),
            const SizedBox(height: 14),
          ] else if (SparklineService.supports(rep)) ...[
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
              context.l10n.lastMonth,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
            const SizedBox(height: 14),
          ],
          // Tam ad — satırda yalnızca kod (THYAO) gösterilen varlıklar için.
          // Kırpma yok: burada yer var, isim tam okunmalı.
          // Ad koddan farksızsa ("TAM ADI: SAHOL") satır bilgi vermez.
          if (rep.showTicker &&
              rep.name.trim().toUpperCase() !=
                  (rep.displayTicker ?? '').toUpperCase()) ...[
            _DetailItem(
                label: context.l10n.assetFullName, value: rep.name, isText: true),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: context.l10n.firstPurchase,
                  value: firstBuyDate != null
                      ? DateFormat('d MMM yyyy', context.l10n.localeName)
                          .format(firstBuyDate)
                      : '—',
                ),
              ),
              Expanded(
                child: birimsiz
                    ? toplamMaliyet
                    : _DetailItem(
                        label: context.l10n.quantity,
                        value: qtyDisplay,
                      ),
              ),
            ],
          ),
          if (!birimsiz) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: context.l10n.avgCost,
                  value: avgCostStr,
                ),
              ),
              Expanded(child: toplamMaliyet),
            ],
          ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  label: context.l10n.currentValue,
                  value: tryFmt2.format(currentValueTRY),
                  emphasize: true,
                ),
              ),
              // Temettü VARSA ikinci kolona girer — yoksa satır tek kolon
              // kalır (boş bir "₺0" yazmak "temettü almadım" bilgisini
              // gürültüye çevirirdi).
              //
              // ## Neden burada (kullanıcı isteği, 2026-09-23)
              // Üst kart portföy GENELİ temettüyü "Bunun temettüsü" satırıyla
              // açıklıyor ama POZİSYON bazında bu bilgi hiçbir yerde yoktu:
              // "bu hisseden ne temettü aldım" sorusunun cevabı yalnizca
              // hareket geçmişini elle toplayarak bulunabiliyordu.
              //
              // `totalDividendTRY` HAM lot'lardan okur (`position.totalDividend`
              // DEĞİL): ikincisi alım para biriminde ve `aggregatePositions`
              // yoluyla gelir. Buradaki diğer tutarlar TRY olduğu için aynı
              // ölçekte olmalı — yoksa USD bir hissede temettü satırı
              // diğerleriyle kıyaslanamaz.
              //
              // Bu satırın toplamı üst karttaki `state.totalDividend` ile
              // TİKEL olarak tutar: ikisi de aynı fonksiyondan beslenir.
              if (dividendTRY.abs() >= 0.005)
                Expanded(
                  child: _DetailItem(
                    label: context.l10n.dividendReceived,
                    value: tryFmt2.format(dividendTRY),
                  ),
                ),
            ],
          ),
          if (position.lots.length > 1) ...[
            const SizedBox(height: 10),
            Text(
              context.l10n.lotSummary(buyLots.length, position.lots.where((l) => l.isSell).length),
              style: context.t.bodySmall?.copyWith(
                  color: context.c.text36, fontWeight: FontWeight.w500),
            ),
          ],
          FonKarnesiSatiri(tur: rep.type, ticker: rep.ticker),
          _NotlarBolumu(lotlar: position.lots),
        ],
      ),
    );
  }
}

/// Açılır paneldeki "NOTLAR" — pozisyonun işlemlerine yazılmış notlar.
///
/// Kullanıcı isteği (2026-09-29): "not bilgisi Portföy sayfasında da yer
/// almalı; kart açıldığında orada olmalı." Kapalı kartta işaret YOK: satır
/// zaten ad + alarm zili + miktar + tutar + kâr taşıyor; not "göze batmasın
/// ama kaybolmasın" isteğinin kapalı kart karşılığı açılır panelin kendisi.
///
/// Not yoksa bölüm hiç çizilmez (boş bir "Not yok" başlığı her kartta
/// gürültü olurdu). En yeni [_enFazla] not; fazlası Tüm Hareketler'e
/// yönlendirilir — panel bir defter değil, pozisyonun özeti.
///
/// Her not dokununca hareket satırıyla AYNI not sayfasını açar: notu
/// gördüğü yerde düzeltebilsin, hareketlere gitmesin.
class _NotlarBolumu extends ConsumerWidget {
  const _NotlarBolumu({required this.lotlar});

  final List<Asset> lotlar;

  static const _enFazla = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notlar = notluIslemler(lotlar);
    if (notlar.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ustHarf(l10n.notesSection, l10n),
            style: context.t.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.c.text36,
            ),
          ),
          for (final n in notlar.take(_enFazla))
            SandikTappable(
              semanticLabel: l10n.txOpenNoteWithNote(hareketTurEtiketi(l10n, n.islem)),
              onTap: () =>
                  showIslemNotuSheet(context, ref, asset: n.islem, not: n.not),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hareket satırındaki not işaretiyle aynı ikon.
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.notes_rounded,
                          size: 14, color: context.c.text36),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.not,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodyMedium?.copyWith(
                                color: context.c.text90, height: 1.35),
                          ),
                          const SizedBox(height: SandikSpace.xxs),
                          // Hangi işleme ait: çok lot'lu pozisyonda "hangi
                          // alışın notu" sorusunun cevabı.
                          Text(
                            '${hareketTurEtiketi(l10n, n.islem)} · '
                            '${fmtTarihSaat(n.islem.addedDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall
                                ?.copyWith(color: context.c.text36),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (notlar.length > _enFazla)
            Text(
              l10n.moreNotesCount(notlar.length - _enFazla),
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
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
          // Düz `toUpperCase` Türkçe'de "MIKTAR", "ORT. MALIYET" veriyordu
          // (bulgu #8); `ustHarf` dile göre i→İ çevirir, İngilizce'ye
          // dokunmaz.
          ustHarf(label, context.l10n),
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

  /// Sıralama seçenekleri — `static const` DEĞİL: etiketler dile bağlı (3.20),
  /// sözlük ise `context` ister.
  static List<(_SortOrder, String, String)> _options(AppLocalizations l) => [
        (_SortOrder.valueDesc, l.sortMarketValue, l.sortHighToLow),
        (_SortOrder.valueAsc, l.sortMarketValue, l.sortLowToHigh),
        (_SortOrder.gainDesc, l.sortGainTry, l.sortHighestFirst),
        (_SortOrder.gainAsc, l.sortGainTry, l.sortLowestFirst),
        (_SortOrder.gainPctDesc, l.sortGainPct, l.sortHighestFirst),
        (_SortOrder.gainPctAsc, l.sortGainPct, l.sortLowestFirst),
      ];

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: SandikTouch.minSize,
      padding: EdgeInsets.zero,
      onPressed: () => showSandikSheet<void>(
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
          semanticLabel: context.l10n.sortAssetsSemantics,
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
              context.l10n.sortCriterion,
              style: context.t.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: context.c.text58,
              ),
            ),
          ),
          Divider(color: context.c.hairline, height: 1),
          ..._SortButton._options(context.l10n).map((opt) {
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

/// Portföy satırının alt metni: miktar · tür.
///
/// Sözleşmeli türlerde miktar anlam taşımaz (2026-10-01 emülatör testi):
/// mevduatın "250.000 birim"i iç hesabın payıdır, BES'in "318.850,44 pay"ı
/// da üç ayrı fon satırının hangi sözleşmeye ait olduğunu söylemez. Mevduat
/// yalnız türünü, BES kurumunu ve katkı tipini yazar
/// ("Anadolu Hayat · Devlet katkısı").
String _satirAltMetni(BuildContext context, Asset a) {
  final l10n = context.l10n;
  final tur = a.type.labelOf(l10n);
  if (a.type == AssetType.mevduat) return tur;
  if (a.type == AssetType.bes) {
    final kurum = a.besKurumu;
    final tip = a.subCategory == BesAltKategori.devletKatkisi
        ? l10n.pensionGov
        : tur;
    return kurum == null ? tip : '$kurum · $tip';
  }
  final miktar = fmtNum(a.quantity,
      digits: a.quantity == a.quantity.truncateToDouble() ? 0 : 2);
  return a.unitIsPrefix
      ? '${a.unitLabel}$miktar · $tur'
      : '$miktar ${a.unitLabel} · $tur';
}
