import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../demo/demo_modu.dart';
import '../providers/price_alert_notification_provider.dart';
import '../providers/app_notification_provider.dart';
import '../models/app_notification.dart';
import '../models/price_alert_notification.dart';
import '../models/bildirim_akisi.dart';
import '../models/asset.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/portfolio_provider.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/preferences_provider.dart';
import '../providers/signal_provider.dart';
import '../services/notification_service.dart';
import '../services/temettu_gecmisi.dart' show TemettuOnerisi;
import '../services/analytics_service.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/bugun_karti.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../widgets/price_alert_tile.dart';
import '../widgets/app_notification_tile.dart';
import '../widgets/portfolio_summary_widget.dart';
import '../widgets/gorunum_cipi.dart';
import '../utils/tr_iyelik.dart';
import '../widgets/kaydirmali_gecis.dart';
import 'price_alerts_screen.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/transaction_row.dart';
import 'add_asset_screen.dart';
import 'csv_import_screen.dart';
import 'main_navigation_screen.dart' show MainNavigationScreen;
import 'all_transactions_screen.dart';
import 'asset_detail_screen.dart';
import 'portfolio_performance_screen.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/piyasa_seridi.dart';
import 'add_watchlist_screen.dart';
import '../widgets/tour_anchor.dart';
import '../services/islem_notu.dart';
import '../widgets/islem_notu_sheet.dart';
import '../l10n/l10n.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _view = '';
  // Tür filtresi (çipler) ve "Varlık dağılımı" listesi 2026-09-28'de
  // kaldırıldı (kullanıcı kararı): dağılım halkası Portföy sekmesinde,
  // tür filtresi Performans ekranında zaten var; ana sayfa aynı bilgiyi
  // üçüncü kez taşıyordu ve toplam kartıyla hareket listesinin arasını
  // uzatıyordu. Ana sayfadaki toplam/hareketler artık filtresizdir.
  final _scrollCtrl = ScrollController();
  bool _reloading = false;

  /// Varlık arama — takibe alma ekranıyla AYNI ekran (tek arama yüzeyi).
  void _aramayiAc() {
    // Demo (F1): takibe alma bir yazma; arama sayfası oraya çıkıyor.
    if (DemoModu.yazmaKapisi('arama')) return;
    pushGuarded(
      context,
      adaptiveRoute<void>(
        builder: (_) => const AddWatchlistScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    // `refreshPrices` hatayı kendi içinde yakalar; finally yalnızca beklenmeyen
    // bir istisnada döner butonunun sonsuza dek kilitli kalmamasını sağlar
    // (handler sahipsiz: onPressed future'ı beklemiyor).
    try {
      await ref.read(portfolioProvider.notifier).refreshPrices(force: true);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Bugün kartının kapsam etiketi: kendi görünümünde yok; ortakta
  /// "Ayşe'nin bugünü" (Türkçede ilgi eki ünlü uyumuyla, `trIyelik`),
  /// Birlikte'de "Birlikte".
  String? _bugunEtiketi(List<AppUser> partners) {
    final l10n = context.l10n;
    if (_view == '') return null;
    if (_view == null) return l10n.scopeTogether;
    final p = partners.where((p) => p.id == _view).firstOrNull;
    final ad = GorunumCipi.ilkAd(p?.displayName ?? '');
    if (ad.isEmpty) return l10n.scopeTogether;
    final tr = Localizations.localeOf(context).languageCode != 'en';
    return l10n.todayScopeOf(tr ? trIyelik(ad) : ad);
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SignalsBottomSheet(
        onDismiss: (id) => ref.read(signalProvider.notifier).dismiss(id),
        onDelete: (id) => ref.read(signalProvider.notifier).delete(id),
        // Toplu eylemler ÜÇ kaynağı birden kapsar (kullanıcı bildirimi
        // 2026-09-17: "tümünü sil / hepsini temizle çalışmıyor"). Eskiden
        // yalnızca sinyal notifier'ı çağrılıyordu; liste alarm ve genel
        // bildirimlerle harmanlandığı için o satırlar yerinde kalıyor,
        // kullanıcı "çalışmıyor" görüyordu. Tekil silme türüne göre zaten
        // doğru notifier'a gidiyordu — o yüzden çalışıyordu.
        onDismissAll: () => Future.wait([
              ref.read(signalProvider.notifier).dismissAll(),
              ref.read(priceAlertNotificationProvider.notifier).dismissAll(),
              ref.read(appNotificationProvider.notifier).dismissAll(),
            ]),
        onDeleteHistory: () => Future.wait([
              ref.read(signalProvider.notifier).deleteHistory(),
              ref
                  .read(priceAlertNotificationProvider.notifier)
                  .deleteHistory(),
              ref.read(appNotificationProvider.notifier).deleteHistory(),
            ]),
        onDeleteAll: () => Future.wait([
              ref.read(signalProvider.notifier).deleteAll(),
              ref.read(priceAlertNotificationProvider.notifier).deleteAll(),
              ref.read(appNotificationProvider.notifier).deleteAll(),
            ]),
        onTap: (alert) {
          Navigator.pop(context);
          AnalyticsService.instance.logSignalViewed(
            ticker: alert.assetTicker,
            action: alert.signal.name,
          );
          final assets = ref.read(portfolioProvider).valueOrNull?.assets;
          final asset = assets?.where((a) => a.id == alert.assetId).firstOrNull;
          if (asset != null) {
            // Portföy listesiyle AYNI nesne: pozisyon görünümü. Ham lot
            // satış/silinmiş kayıtsa grafik boş kalır (bkz. `pozisyonGorunumu`).
            final gorunum = pozisyonGorunumu(assets!, asset);
            Navigator.push(
              context,
              adaptiveRoute<void>(
                  builder: (_) => AssetDetailScreen(
                        asset: gorunum?.asset ?? asset,
                        lots: gorunum?.lots ?? [asset],
                        showBackButton: true,
                      )),
            );
          }
        },
        onAlarmDismiss: (id) =>
            ref.read(priceAlertNotificationProvider.notifier).dismiss(id),
        onAlarmDelete: (id) =>
            ref.read(priceAlertNotificationProvider.notifier).delete(id),
        onGenelTap: (bildirim) {
          Navigator.pop(context);
          _genelBildirimeGit(bildirim);
        },
        onGenelDismiss: (id) =>
            ref.read(appNotificationProvider.notifier).dismiss(id),
        onGenelDelete: (id) =>
            ref.read(appNotificationProvider.notifier).delete(id),
        onAlarmTap: (bildirim) {
          Navigator.pop(context);
          // Push bildirimiyle AYNI varış yeri: alarmın konusu olan varlık,
          // GÜNLÜK sekmesinde. İki yol (push / liste) aynı yere çıkmalı,
          // aksi halde kullanıcı iki farklı davranış öğrenir.
          //
          // Sembolden varlığa eşleme `alarmSembolu` üstünden yapılır —
          // alarm payload'ı `asset_id` taşımaz (bkz. migration 0065).
          NotificationService.instance.openPriceAlertAsset(
            bildirim.symbol,
            onNotFound: () => NotificationService.instance.showAssetNotFound(),
          );
        },
      ),
    );
  }

  /// Genel bildirime dokunuş — push'a dokunulmuş gibi aynı yere (0066).
  ///
  /// Ortaklık → davet akışı; günlük/haftalık özet → Performans "Özet"
  /// (bildirimin anlattığı rakam orada); takvim hatırlatması → ana ekran
  /// (zaten buradayız, yalnızca liste kapanır).
  void _genelBildirimeGit(AppNotification b) {
    switch (b.type) {
      case AppNotification.partnerInvite:
        final inviteId = b.data['invite_id']?.toString() ?? '';
        if (inviteId.isNotEmpty) {
          NotificationService.instance.openPartnerInvite(inviteId);
        }
      case AppNotification.dailyBrief || AppNotification.weeklySummary:
        Navigator.push(
          context,
          adaptiveRoute<void>(
            builder: (_) => const PortfolioPerformanceScreen(
              showBackButton: true,
              initialOzet: true,
            ),
          ),
        );
      case AppNotification.watchlistMove:
        // Takip listesi Portföy sekmesinin gövdesinde; sekmeye geç yeter.
        MainNavigationScreen.sekmeIstegi.value = 1;
      case AppNotification.inflationDay:
        // TÜFE günü → Özet: reel getiri kartı orada.
        Navigator.push(
          context,
          adaptiveRoute<void>(
            builder: (_) => const PortfolioPerformanceScreen(
              showBackButton: true,
              initialOzet: true,
            ),
          ),
        );
      case AppNotification.monthlySummary:
        // Aylık özet → 1A dönemi; bildirimin anlattığı ay orada.
        Navigator.push(
          context,
          adaptiveRoute<void>(
            builder: (_) => const PortfolioPerformanceScreen(
              showBackButton: true,
              initialOzet: true,
              initialPeriodIdx: 2,
            ),
          ),
        );
      case AppNotification.temettu:
        // Push'la AYNI varış: ön dolu temettü diyaloğu. Veri bozuksa açılmaz.
        final oneri = TemettuOnerisi.fromPush(b.data);
        if (oneri != null) {
          NotificationService.instance.openTemettuOnerisi(oneri);
        }
      case AppNotification.calendarNudge
          when b.data['occasion']?.toString() ==
              NotificationService.yilSonuOccasion:
        // Yıl sonu özeti → Profil (özet afişi orada).
        MainNavigationScreen.sekmeIstegi.value =
            MainNavigationScreen.profilSekmesi;
      default:
        break;
    }
  }

  /// Hareket satırı + işlem notu bağlantısı.
  ///
  /// Not görünürlüğü ve düzenlenebilirlik tek yerden (`islem_notu.dart`);
  /// satır, notu olan ya da not yazılabilen kayıtta dokunulur. Ortağın
  /// notsuz kaydında açılacak bir şey yok — satır eskisi gibi durur.
  Widget _hareketSatiri(
    Asset a,
    List<Asset> defter, {
    required BazPara baz,
    required PortfolioState portfolioState,
    required bool hideBalance,
  }) {
    final not = islemNotu(a, defter);
    final benimId = ref.watch(authProvider).valueOrNull?.id;
    final acilir =
        not != null || islemNotuDuzenlenebilir(a, benimId: benimId);
    return TransactionRow(
      baz: baz,
      asset: a,
      portfolioState: portfolioState,
      hideBalance: hideBalance,
      not: not,
      onTap: acilir
          ? () => showIslemNotuSheet(context, ref, asset: a, not: not)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(portfolioProvider);
    final partners = ref.watch(activePartnersProvider);
    final hasPartners = partners.isNotEmpty;
    // Gizlenen/çıkarılan ortak seçili görünümde KALMASIN: toplam ₺0'a düşer
    // (bkz. `GorunumCipi.gecerli`, 2026-09-28).
    ref.listen(activePartnersProvider, (_, next) {
      final v = GorunumCipi.gecerli(next, _view);
      if (v != _view) setState(() => _view = v);
    });

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
    final baz = ref.watch(bazParaProvider);
    final tryFmt = baz.formatter(digits: 0);
    // Ekran kenarı tek kaynaktan (2026-09-15): 14/20 yerel değeri kenarı
    // diğer sekmelerden farklı kılıyordu — "her ekranda aynı olmalı".
    final hp = SandikSpace.screenH(context);
    final allActivePartners = ref.watch(activePartnersProvider);

    // Ham `assets` transaction ledger'ıdır — buy/sell/deleteLog hepsi karışık.
    // Ana sayfadaki summary, mini card, hareket listesi ve kâr/zarar
    // portföy ekranı ile birebir tutarlı olmalı. Portföy ekranı
    // `aggregatePositions` kullanıyor: sell lot'ları buy qty'sinden düşer,
    // deleteLog skip edilir, totalQty <= 0 pozisyonlar liste dışı kalır.
    // Aynı aggregate'i burada da uyguluyoruz ve `asDisplayAsset()` ile
    // downstream widget'ların beklediği Asset formatına çeviriyoruz.
    // Ortak yardımcı (`models/position.dart`). Aynı bileşim birkaç ekranda
    // elle tekrarlanıyordu; biri güncellenip diğeri kalınca aynı portföy
    // iki ekranda farklı görünüyordu.
    const positionedAssets = gosterilecekVarliklar;

    // Görünüm toplamları — çipin alt sayfası her görünümün toplamını
    // geçmeden gösterir (2026-09-21). Her ortak AYRI indirgenir (aşağıdaki
    // "positionKey sahip taşımaz" gerekçesi), Birlikte = toplamların toplamı.
    Map<String?, double> gorunumToplamlari = const {};
    if (allActivePartners.isNotEmpty) {
      double toplam(List<Asset> assets) {
        var t = 0.0;
        for (final a in positionedAssets(assets)) {
          t += myState.toTRY(a.totalValue, a.currency);
        }
        return t;
      }

      final benim = toplam(myState.assets);
      var birlikte = benim;
      final m = <String?, double>{'': benim};
      for (final p in allActivePartners) {
        final t = toplam(allPartnerAssets[p.id] ?? const []);
        m[p.id] = t;
        birlikte += t;
      }
      m[null] = birlikte;
      gorunumToplamlari = m;
    }

    // Görünüme göre gösterilecek varlıklar ('' Ben, id ortak, null Birlikte).
    // Yardımcı: kaydırma sırasında KOMŞU görünümün kartı da aynı hesapla
    // kurulur (`KaydirmaliGecis.komsu`), iki yol ayrışmasın.
    List<Asset> gorunumVarliklari(String? view) {
      if (view == '') return positionedAssets(myState.assets);
      if (view != null && view.isNotEmpty) {
        return positionedAssets(allPartnerAssets[view] ?? const []);
      }
      return [
        ...positionedAssets(myState.assets),
        for (final list in allPartnerAssets.values) ...positionedAssets(list),
      ];
    }

    final displayedAssets = gorunumVarliklari(_view);

    // "PORTFÖY HAREKETLERİ" listesi aggregate'i KULLANAMAZ.
    //
    // `positionedAssets` her varlığı tek bir sentetik pozisyona indirger:
    // sell lot'ları buy miktarından düşer, temettü ve deleteLog satırları
    // tamamen elenir. Summary için doğru olan bu davranış, hareket
    // listesi için yanlıştı — kullanıcı Al/Sat/Temettü yaptığında listede
    // yeni bir kayıt GÖRÜNMÜYORDU; yalnızca mevcut satırın miktarı değişiyordu.
    //
    // Hareketler ham ledger'dan gelir: her işlem kendi satırıdır.
    // `TransactionRow` dört türü de (Alım/Satım/Temettü/Silindi) kendi ikon,
    // etiket ve tutarıyla çiziyor.
    //
    // Silinen varlığın satırları ana sayfada GÖRÜNMEZ (kullanıcı kararı
    // 2026-09-29). Silme fiziksel değil, `deleted_at` damgasıdır; kayıtlar
    // "Tümünü gör" ekranının "Silinenler" alanında alım ve silinme
    // tarihleriyle durur (`hareketleriAyir`). Eskiden damgalı satırlar ve
    // "Silindi · N kayıt" mezar taşı burada, son üç kaydın arasındaydı:
    // bir silme işlemi ana sayfanın üç satırını birden artık portföyde
    // olmayan şeylere ayırabiliyordu.
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

    // "Ben" mini card'ı — kendi net pozisyon toplamı (satışlar düşülmüş).
    final myBuyTotal = positionedAssets(myState.assets)
        .fold<double>(0, (s, a) => s + myState.toTRY(a.totalValue, a.currency));

    PortfolioState gorunumDurumu(List<Asset> varliklar) => PortfolioState(
          assets: varliklar,
          usdTry: myState.usdTry,
          eurTry: myState.eurTry,
          gbpTry: myState.gbpTry,
          lastUpdated: myState.lastUpdated,
        );
    final displayedState = gorunumDurumu(displayedAssets);

    final bool showRightCard = _view != '';
    String rightLabel = '';
    double rightTotal = 0;
    String rightInitial = 'O';
    final Color rightColor = context.c.gain;

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
        // `positionedAssets` — "Ben" kartıyla AYNI ölçü. Ham `isBuy`
        // toplamı satışları düşmüyordu: ortak bir şey sattığında kart
        // şişik görünüyor, iki kart farklı şey ölçüyordu.
        //
        // Her ortak AYRI indirgenir, lot'lar tek havuzda toplanmaz:
        // `positionKey` sahip taşımaz, birleştirilirse iki ortağın aynı
        // hissesi tek pozisyona karışır ve birinin satışı diğerinin
        // lot'unu düşer.
        for (final assets in allPartnerAssets.values) {
          for (final a in positionedAssets(assets)) {
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
        for (final a in positionedAssets(allPartnerAssets[_view!] ?? const [])) {
          rightTotal += myState.toTRY(a.totalValue, a.currency);
        }
      }
    }

    // Hareket sayısı — "Tümünü Gör" rozeti ve eşiği için. Ledger'dan
    // sayılır; aggregate edilmiş pozisyon sayısı hareket sayısı DEĞİLDİR.
    // Rozet, tam ekranın varsayılan olarak gösterdiği sayıdır (süren
    // hareketler; silinenler orada filtreyle açılır). Eşik silinenleri de
    // kapsar: iki süren hareket + bir silinmiş varlık "Tümünü gör"ü açar,
    // yoksa silinenler filtresine ulaşmanın yolu kalmazdı.
    final hareketler = hareketleriAyir(ledgerAssets);
    final ledgerCount = hareketler.aktif.length;

    // Kendi görünümü + sıfır varlık = ilk kullanım boş durumu. Eskiden
    // özet (₺0), üç şerit, iki kişi kartı, filtre çipleri ve iki boş
    // başlıktan SONRA, listenin en altında bir "İlk varlığını ekle" düğmesi
    // vardı — 27 adımlık turdan çıkan kullanıcı bir duvar sıfır görüyordu.
    final ownView = !(_view != null && _view!.isNotEmpty);
    // Yalnızca "Ben" (`''`). `ownView` Birlikte'yi de içerir (ortak-değil);
    // "kendi defteri mi" sorusu bu ikisini ayırmak zorunda — Bugün kartı
    // Birlikte'de birleşik defteri anlatır.
    final benGorunumu = _view == '';
    // **Boşluk ölçüsü AÇIK POZİSYON, ham satır sayısı DEĞİL** (kullanıcı
    // bildirimi, 2026-09-16).
    //
    // `assets.isEmpty` ham defteri sayıyordu; tamamı satılmış bir portföyde
    // alım ve satım satırları durduğu için "boş değil" çıkıyor ve şeritler
    // çiziliyordu. Ekran kendi içinde çelişiyordu: üstte "TOPLAM NET VARLIK
    // ₺0", hemen altında "enflasyonun 2,64 puan öndesin" ve "bu hafta
    // piyasadan %82,3 artı". Sıfır lirası olan bir portföyün enflasyonu
    // yenmesi diye bir şey yok.
    //
    // `aktifLotlar` bugünkü MÜLKİYETİ soruyor: silinmişleri ve net miktarı
    // sıfıra inmiş pozisyonları birlikte eliyor (bkz. `models/position.dart`).
    // Hareket listesi ham defteri kullanmaya DEVAM eder — geçmiş orada
    // duruyor ve doğrusu da bu.
    final isEmptyOwn = ownView && aktifLotlar(myState.assets).isEmpty;

    return RefreshIndicator.adaptive(
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
            // Yükseklik Performans ekranındaki başlık çubuğuyla BİREBİR:
            // 44pt dokunma hedefi + 2×xs (2026-09-28, "diğer ekranlar
            // Performans'la aynı hizaya"). 66 iken ana sayfa tek başına
            // daha kalın bir üst şerit taşıyordu.
            toolbarHeight: SandikTouch.min + SandikSpace.xs * 2,
            titleSpacing: 0,
            title: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
              child: Row(
                children: [
                  // Başlık bloğu dört sekmede BİREBİR (kullanıcı kararı
                  // 2026-09-28, "hepsi Portföy ekranındaki değerlerle aynı"):
                  // düz metin, `headlineMedium`, ekran kenarından `screenH`,
                  // tek satır/fade. Eski hâli logolu ve çerçeveli bir marka
                  // rozetiydi (amber dolgu, 10/7 dolgu, FittedBox); metin
                  // öteki sekmelerden 14pt içeriden başlıyor, rozet kutusu
                  // başlık satırını farklı okutuyordu. Kelime işareti
                  // ("sandık", altın) marka için yeterli; logo açılışta.
                  Expanded(
                    child: Text(
                      'sandık',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: context.t.headlineMedium?.copyWith(
                        color: context.c.gold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  TourAnchor(
                    target: TourTarget.yenileTusu,
                    child: _HeaderIconButton(
                      onTap: _reload,
                      semanticLabel: context.l10n.refreshPrices,
                      child: _reloading
                          ? const CustomLoadingIndicator(size: 20)
                          : Icon(Icons.refresh_rounded,
                              color: context.c.text58, size: 22),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  const TourAnchor(
                    target: TourTarget.gizleTusu,
                    child: _BalanceToggleButton(),
                  ),
                  const SizedBox(width: SandikSpace.sm),
                  // NOT: Takip listesi düğmesi bilerek BURADA DEĞİL.
                  // Bu satır dört düğmeyle zaten taşıyordu (yukarıdaki
                  // Flexible+FittedBox o taşmanın çaresi). Beşinciyi eklemek
                  // HIG'in "navigation bar'ı düğmeyle doldurma" kuralını
                  // (Severity: High) çiğniyordu. Takip listesi bir VARLIK
                  // LİSTESİDİR; yeri Portföy sekmesinin gövdesi
                  // (`portfolio_screen.dart`), üst bar değil.
                  // Teknik sinyal zili Başlangıç seviyesinde GİZLİ
                  // (`seviyeGorunurlugu`): sinyal, gösterge okumayı bilen
                  // kullanıcıya hitap eder. Varsayılan Orta olduğu için
                  // seçim yapmayan hiç kimse bunu kaybetmez.
                  if (seviyeGorunurlugu(ref.watch(yatirimciSeviyesiProvider))
                      .teknikSinyaller) ...[
                    TourAnchor(
                      target: TourTarget.bildirimCani,
                      child: _SignalBadgeButton(onTap: _scrollToSignals),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                  ],
                  SandikLogoutButton(
                      onPressed: () => confirmAndLogout(context, ref)),
                ],
              ),
            ),
          ),
          // ── Dikey ritim (2026-09-28, "bileşen araları tutarlı olmalı") ──
          // Blok → blok: `SandikSpace.md`. Bölüm başlığı: üstünde `lg`,
          // altında `smd` (hareket satırlarının kendi aralığı da 12 —
          // `TransactionRow` alt 12). Her sliver YALNIZCA üst boşluğunu
          // taşır; alt boşluk yazmaz — böylece iki komşunun payı
          // toplanıp 44pt'lik çukurlar oluşmaz (eski hâl: mini kart alt
          // 20 + başlık üst 24). Koşullu bloklar (Bugün, mini kartlar)
          // gizlenince ritim bozulmaz çünkü her blok kendi üstünü getirir.
          // Offline / price error banner
          if (myState.errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, SandikSpace.sm, hp, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: context.c.amberText, size: 16),
                      const SizedBox(width: SandikSpace.sm),
                      Expanded(
                        child: Text(
                          context.l10n.priceUpdateFailed,
                          style: context.t.titleSmall
                              ?.copyWith(color: context.c.amberText),
                        ),
                      ),
                      SandikTappable(
                        onTap: _reload,
                        semanticLabel: context.l10n.retry,
                        child: Text(
                          context.l10n.retry,
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
          // Piyasa şeridi — dolar/euro/gram altın/BIST 100 (2026-09-20).
          // Portföyden ÖNCE: günlük girişin ilk sorusu "dolar ne oldu".
          //
          // HER görünümde (Ben / ortak / Birlikte) ve KOŞULSUZ (kullanıcı
          // kararı 2026-09-28): piyasa verisi kimin portföyüne bakıldığından
          // bağımsız, "Ara" da öyle. Eskiden `if (ownView)` ile sarılıydı
          // (9a6a9f7'den gerekçesiz devralınan kalıp): ortağa kaydırınca
          // bant kayboluyor, geri dönünce SIFIRDAN kuruluyordu — kotasyon
          // yeniden çekiliyor, akış baştan başlıyordu.
          //
          // `key`: bu sliver'dan önce koşullu bir sliver var (fiyat hatası
          // şeridi). O girip çıktığında bandın indeksi kayar; anahtarsız
          // Flutter aynı indeksteki farklı çocuğu yeni element sayar ve
          // bant yine sıfırlanırdı. Bant kendi ritmi (`TazelikRitmi.nabiz`)
          // dışında yeniden yüklenmez; görünüm değişimi yalnızca yeniden
          // ÇİZER (`KayanBant` fazı ValueNotifier'da, state korunur).
          SliverToBoxAdapter(
            key: const ValueKey('piyasa-seridi'),
            child: TourAnchor(
              target: TourTarget.piyasaSeridi,
              child: PiyasaSeridi(
                // Şerit kartı 44pt kutuda ortalı 36pt (bkz.
                // `piyasa_seridi.dart`); alt 10 + kutu payı 4 = hero karta
                // 14pt (seçenek C).
                //
                // Üst dolgu 0 (2026-09-29): başlık bloğu dört sekmede aynı
                // olmalı — ilk içerik düğme satırının altı + `xs`'ten başlar
                // (`ust_cubuk_dugme_araligi_test`, kullanıcı 2026-09-28:
                // "başlık bloğu dört sekmede aynı, Portföy'deki değerlerle").
                // Eski üst 8 Ana'yı öteki sekmelerden 8pt aşağıda
                // başlatıyordu; başlık→kart görsel boşluğu artık 4 + kutu
                // payı 4 = 8pt.
                padding: EdgeInsets.fromLTRB(hp, 0, hp, SandikSpace.sm2),
                onAra: _aramayiAc,
              ),
            ),
          ),
          // Portfolio summary
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: TourAnchor(
                target: TourTarget.heroKart,
                // Ortak varken kartı sağa/sola kaydırmak sıradaki görünüme
                // geçer (Ben → ortaklar → Birlikte). Çip ve alt sayfa hedefe
                // doğrudan gider; kaydırma "bir sonrakine bak" hareketi.
                // Kart parmağı takip eder, kenarda hedefin adı belirir,
                // bırakınca kayarak geçer (`KaydirmaliGecis`).
                child: KaydirmaliGecis(
                  etkin: allActivePartners.isNotEmpty,
                  ipucu: !ref.watch(kaydirmaIpucuGosterildiProvider),
                  onIpucuGosterildi: () => ref
                      .read(kaydirmaIpucuGosterildiProvider.notifier)
                      .set(true),
                  // Komşu kart: o görünümün toplamı ve çipi, aynı hesapla.
                  // Tür filtresi uygulanmaz — kart "o kişinin toplamı"dır.
                  komsu: (ileri) {
                    final hedef = GorunumCipi.sonraki(allActivePartners, _view,
                        ileri: ileri);
                    return PortfolioSummaryWidget(
                      state: gorunumDurumu(gorunumVarliklari(hedef)),
                      hideBalance: ref.watch(balanceHiddenProvider),
                      baz: baz,
                      trailing: GorunumCipi(
                        partners: allActivePartners,
                        selectedId: hedef,
                        toplamlar: gorunumToplamlari,
                        gizli: ref.watch(balanceHiddenProvider),
                        onChanged: (_) {},
                      ),
                    );
                  },
                  onGecis: (ileri) => setState(() => _view = GorunumCipi.sonraki(
                      allActivePartners, _view,
                      ileri: ileri)),
                  // Sayfa noktaları kartın altında; sürüklerken canlı.
                  altBilgi: (ctx, ilerleme) {
                    final sira = GorunumCipi.sira(allActivePartners);
                    return SayfaNoktalari(
                      sayi: sira.length,
                      secili: sira.indexOf(_view).clamp(0, sira.length - 1),
                      ilerleme: ilerleme,
                    );
                  },
                  child: PortfolioSummaryWidget(
                    state: displayedState,
                    hideBalance: ref.watch(balanceHiddenProvider),
                    baz: baz,
                    // Görünüm değişince toplam vurgusu yakılmaz.
                    vurguKimligi: _view ?? 'birlikte',
                    // Ben / ortak / Birlikte — kartın başlığında (2026-09-21).
                    trailing: allActivePartners.isEmpty
                        ? null
                        : GorunumCipi(
                            partners: allActivePartners,
                            selectedId: _view,
                            toplamlar: gorunumToplamlari,
                            gizli: ref.watch(balanceHiddenProvider),
                            onChanged: (v) => setState(() => _view = v),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (isEmptyOwn)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, SandikSpace.lg, hp, 0),
                child: const _EmptyPortfolioCta(),
              ),
            ),
          // Anonim yüzdelik dilim şeridi.
          //
          // ORTAK görünümünde gizlenir: şerit KULLANICININ kendi dilimini
          // anlatır, ortağın portföyüne bakarken göstermek hangi portföyden
          // bahsedildiğini belirsizleştirir. Kendi kendini kapatan bir
          // widget (bayrak/opt-in/k-anonimlik) olduğu için burada başka
          // koşul yok.
          // Enflasyon ve haftalık piyasa şeritleri SEÇİLİ KAPSAM için
          // hesaplanır (kullanıcı 2026-09-17): "Ortak" sekmesinde ortağın
          // defteri, "Birlikte"de ikisi birlikte. Aynı fonksiyon, aynı
          // canlı kur — ortağın kendi ekranında gördüğü sayıyla birebir
          // aynı çıkar; ikinci bir hesap yolu YOK. Eskiden yalnızca kendi
          // görünümünde çiziliyordu. `key` kapsamı taşır: şeritler seriyi
          // bir kez (initState) kurar, sekme değişince yeniden kurulmalı.
          if (aktifLotlar(ledgerAssets).isNotEmpty)
            // "Bugün" kartı EN ÜSTTE: her gün değişen tek yüzey, sabit
            // bağlamlardan önce gelir.
            //
            // HER görünümde ve SEÇİLİ KAPSAMIN defteriyle (2026-09-21,
            // kullanıcı seçimi "kapsamı izler, başlıkta kimin olduğu yazar").
            // Eskiden yalnızca kendi görünümündeydi ve Birlikte'de de kendi
            // defterini anlatıyordu: toplam kartı birleşik defteri gösterirken
            // Bugün kartı yalnızca senin gününü söylüyordu. Ortak görünümünde
            // kart yerine duran reel getiri ve haftalık şeritleri artık kartın
            // satırları — 2026-09-17 kararı (şeritler kapsamın defterini alır)
            // kartın tamamına uygulandı, ikinci bir hesap yolu yok.
            // Kişisel satırlar (hedef, aylık özet) yalnızca kendi görünümünde
            // (`kisisel`); kartın kimin olduğu başlıkta yazar (`etiket`).
            // Yüzdelik dilim şeridi Profil'de (sosyal karşılaştırma ana
            // ekranın sorusu değil).
            SliverToBoxAdapter(
              child: TourAnchor(
                target: TourTarget.bugunKarti,
                child: BugunKarti(
                  key: ValueKey('bugun-${_view ?? '*'}'),
                  // Kendi görünümünde ham state (sahip damgalı, paylaşımlı
                  // gün içi önbelleği kullanır); kapsamda aynı kurla
                  // kurulmuş kapsam defteri.
                  //
                  // `ownView` DEĞİL, `benGorunumu`: `ownView` "ortak değil"
                  // demektir ve Birlikte'yi (`_view == null`) de kapsar —
                  // kart Birlikte'de yine yalnızca kendi defterini
                  // anlatıyordu (kullanıcı bulgusu 2026-09-21, aynı gün).
                  // Birlikte de bir kapsamdır: birleşik defter, kişisel
                  // satırlar yok, etiket "Birlikte".
                  state: benGorunumu ? myState : gorunumDurumu(ledgerAssets),
                  kisisel: benGorunumu,
                  etiket: _bugunEtiketi(allActivePartners),
                  padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp, 0),
                ),
              ),
            ),
          // Mini cards
          //
          // Ortak yoksa HİÇ çizilmez (kullanıcı kararı 2026-09-29): tek
          // başına "Ben" kartı hemen üstteki toplam kartıyla aynı sayıyı
          // ikinci kez söylüyordu. Kart, iki kişiyi yan yana koymak için var.
          if (!isEmptyOwn && allActivePartners.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp, 0),
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
          // Görünüm seçici (Ben / ortak / Birlikte) 2026-09-21'de toplam
          // kartının başlığına taşındı (`GorunumCipi`); kendi satırı yok.
          // Tür çipleri + "Varlık dağılımı" listesi de 2026-09-28'de
          // kaldırıldı (bkz. sınıf başındaki not) — hareketler doğrudan
          // kişi kartlarının altına gelir.
          // Recent transactions header
          if (!isEmptyOwn)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    hp, SandikSpace.lg, hp, SandikSpace.smd),
                child: SandikSectionHeader(title: context.l10n.portfolioActivity),
              ),
            ),
          // Son hareketler — tek kap (seçenek A "gruplu liste", 2026-09-28).
          //
          // Eskiden her satır kendi kartıydı ve "Tümünü Gör" ayrı bir
          // düğme kartıydı: üç kayıt için dört kutu. Şimdi üç düz satır
          // + saç teli ayraç + kabın son satırı olarak "Tümünü gör", hepsi
          // bir SandikCard içinde (`TransactionRow` başındaki not).
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: Builder(builder: (_) {
                // Liste ham ledger'dan gelir — her Al/Sat/Temettü kaydı
                // ayrı satır. Tür filtresi yok (2026-09-28). Silinenler
                // yok (2026-09-29, yukarıdaki not); sıralı gelir.
                final recentAssets = hareketler.aktif;

                // Boşsa hiçbir şey çizme: kendi defterinde CTA ZATEN özetin
                // hemen altında (_EmptyPortfolioCta); ortak görünümünde
                // "ilk varlığını ekle" demek yanlış olurdu — ortak eklemez.
                if (recentAssets.isEmpty) return const SizedBox.shrink();

                // Ana sayfa yalnızca son 3 kaydı gösterir; tamamı için
                // `AllTransactionsScreen` (filtre + sayfalama). Burada
                // sınırsız büyütmek, log niteliğindeki bu listeyi ana
                // sayfanın altına yığardı.
                final count = recentAssets.length > 3 ? 3 : recentAssets.length;

                final hideBalance = ref.watch(balanceHiddenProvider);
                // Tur hedefi: satırların dokunulabilir olduğunu (işlem notu)
                // satırın kendisi göstermiyor; tur anlatır.
                return TourAnchor(
                  target: TourTarget.hareketler,
                  child: SandikCard(
                  padding: EdgeInsets.zero,
                  radius: SandikRadius.lg,
                  child: Column(
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) const HareketAyraci(),
                        _hareketSatiri(
                          recentAssets[i],
                          ledgerAssets,
                          baz: baz,
                          portfolioState: myState,
                          hideBalance: hideBalance,
                        ),
                      ],
                      // "Tümünü gör" — hareket ekranına götürür. Kabın son
                      // satırı: ayrı bir düğme değil, listenin devamı.
                      //
                      // Sayı ledger'dan okunur, aggregate edilmiş
                      // pozisyonlardan DEĞİL: pozisyon sayısı hareket
                      // sayısını olduğundan az gösterirdi (3 lot + 1 satış
                      // = 1 pozisyon ama 4 hareket).
                      // Eşik: gösterilmeyen süren hareket ya da herhangi
                      // bir silinmiş kayıt (bkz. `ledgerCount` notu).
                      if (ledgerCount > count ||
                          hareketler.silinen.isNotEmpty)
                        SandikTappable(
                          semanticLabel: context.l10n.seeAllTransactions,
                          onTap: () => pushGuarded(
                            context,
                            adaptiveRoute<void>(
                              builder: (_) => AllTransactionsScreen(
                                allPartnerAssets: allPartnerAssets,
                                partners: partners,
                                initialView: _view,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TransactionRow.yatayBosluk,
                              vertical: SandikSpace.smd,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: context.c.hairline),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.l10n.seeAllShort,
                                    style: context.t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: context.c.amberText,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$ledgerCount',
                                  style: context.t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
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
                    ],
                  ),
                  ),
                );
              }),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: SandikSpace.xxl)),
        ],
      ),
    );
  }

  Widget _personMiniCard(
      String name, double total, Color color, ParaBicimi fmt, String initial,
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
              style: context.t.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(name,
              style: context.t.bodySmall?.copyWith(
                  color: context.c.text58, fontWeight: FontWeight.w500)),
          const SizedBox(height: SandikSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hideBalance ? '••••••' : fmt.format(total),
              // cardFontSize dinamik (tutar uzunluğuna göre küçülür), o
              // yüzden boyut override'ı kalıyor; tabular figür tema'dan.
              style: context.t.numSmall
                  .copyWith(fontSize: cardFontSize, color: context.c.text90),
            ),
          ),
        ],
      ),
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

  /// GEÇMİŞİ kalıcı siler (dismiss edilmiş kayıtlar).
  final Future<void> Function() onDeleteHistory;

  /// HEPSİNİ (aktif + geçmiş) kalıcı siler.
  final Future<void> Function() onDeleteAll;

  final void Function(SignalAlert alert) onTap;

  // ── Fiyat alarmı eylemleri (0065) ────────────────────────────────────────
  //
  // Sinyalinkinden AYRI: iki tablo, iki notifier. Aynı callback'e bağlamak
  // kimlikleri karıştırırdı (uuid uzayları ayrı).
  final void Function(PriceAlertNotification bildirim) onAlarmTap;
  final Future<void> Function(String id) onAlarmDismiss;
  final Future<void> Function(String id) onAlarmDelete;

  // ── Genel bildirim eylemleri (0066) ──────────────────────────────────────
  final void Function(AppNotification bildirim) onGenelTap;
  final Future<void> Function(String id) onGenelDismiss;
  final Future<void> Function(String id) onGenelDelete;

  const _SignalsBottomSheet({
    required this.onDismiss,
    required this.onDelete,
    required this.onDismissAll,
    required this.onDeleteHistory,
    required this.onDeleteAll,
    required this.onTap,
    required this.onAlarmTap,
    required this.onAlarmDismiss,
    required this.onAlarmDelete,
    required this.onGenelTap,
    required this.onGenelDismiss,
    required this.onGenelDelete,
  });

  /// Akıştaki bir öğeyi kendi satırına çevirir.
  ///
  /// Tür ayrımı TEK yerde: iki döngü (aktif + geçmiş) aynı yardımcıyı
  /// çağırır, yani yeni bir bildirim türü eklendiğinde dokunulacak tek nokta
  /// burasıdır. Eylemler türe göre AYRI notifier'a gider — iki tablo, iki
  /// uuid uzayı, kimlikler çakışabilir (bkz. `BildirimOgesi.kimlik`).
  Widget _satir(BuildContext context, BildirimOgesi e, {required bool faded}) {
    switch (e) {
      case FiyatAlarmiOgesi(:final bildirim):
        return PriceAlertTile(
          bildirim: bildirim,
          faded: faded,
          onTap: () => onAlarmTap(bildirim),
          // Geçmişte dismiss yok, kalıcı silme var — sinyal tarafıyla
          // aynı sözleşme.
          onDismiss: faded
              ? null
              : _guarded(context, () => onAlarmDismiss(bildirim.id)),
          onDelete: faded
              ? _guarded(context, () => onAlarmDelete(bildirim.id))
              : null,
        );
      case GenelOgesi(:final bildirim):
        return AppNotificationTile(
          bildirim: bildirim,
          faded: faded,
          onTap: () => onGenelTap(bildirim),
          onDismiss: faded
              ? null
              : _guarded(context, () => onGenelDismiss(bildirim.id)),
          onDelete: faded
              ? _guarded(context, () => onGenelDelete(bildirim.id))
              : null,
        );
      case SinyalOgesi(:final alert):
        final id = alert.id;
        return _SignalTile(
          alert: alert,
          faded: faded,
          onTap: () => onTap(alert),
          onDismiss: (!faded && id != null)
              ? _guarded(context, () => onDismiss(id))
              : null,
          onDelete: id != null ? _guarded(context, () => onDelete(id)) : null,
        );
    }
  }

  /// Başarısız silmeyi kullanıcıya SÖYLE.
  ///
  /// Sessiz başarısızlık en kötü seçenek: kullanıcı sildiğini sanır, uygulama
  /// yeniden açılınca kayıt geri gelir ve uygulamaya güveni sarsılır.
  static void _hataGoster(BuildContext context) {
    if (!context.mounted) return;
    sandikSnack(context, context.l10n.signalDeleteFailed,
        kind: SandikSnackKind.error);
  }

  /// Yıkıcı toplu işlemler için onay.
  ///
  /// HIG "forgiveness": geri alınamaz ve çok satırı etkileyen işlem onay ister.
  /// Tekil silmede onay YOKTUR — her dokunuşta diyalog çıkarmak kullanıcıyı
  /// onaya körleştirir ve asıl tehlikeli anda da "Tamam"a basar.
  static Future<bool> _onayAl(
    BuildContext context, {
    required String baslik,
    required String mesaj,
    required String eylem,
  }) async {
    return showSandikConfirm(
      context: context,
      title: baslik,
      message: mesaj,
      confirmLabel: eylem,
      destructive: true,
    );
  }

  /// Kalıcı silmenin KAPSAMINI sorar.
  ///
  /// `true` → hepsi (aktif + geçmiş), `false` → yalnızca geçmiş,
  /// `null` → vazgeçildi.
  ///
  /// Yalnızca aktif sinyal DE varken sorulur. Aktif yoksa iki seçenek aynı
  /// şeyi yapar ve gereksiz bir soru olur (HIG: her karar kullanıcının
  /// dikkatinden harcar).
  ///
  /// Varsayılan yıkıcı olmayan seçenektir: liste sırasında "Yalnızca geçmiş"
  /// önce gelir, "Hepsini sil" en yıkıcı olduğu için kırmızıdır.
  static Future<bool?> _kapsamSor(
    BuildContext context, {
    required int gecmis,
    required int aktif,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.permanentDelete),
        content: Text(
          context.l10n.signalDeleteChoice(gecmis, aktif),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancelShort),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.onlyHistory),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hepsini sil ($gecmis+$aktif)',
                style: TextStyle(color: context.c.loss)),
          ),
        ],
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
    // Fiyat alarmları AYRI tablodan gelir (0065) ve burada tek zaman
    // akışında harmanlanır — ayrılık veri modelinde, birlik sunumda.
    final alarmlar =
        ref.watch(priceAlertNotificationProvider).valueOrNull ?? const [];
    final genel = ref.watch(appNotificationProvider).valueOrNull ?? const [];
    final akis = bildirimAkisi(signals, alarmlar, genel);
    final active = akis.where((e) => !e.dismissEdilmis).toList();
    final history = akis.where((e) => e.dismissEdilmis).toList();
    return DefaultTextStyle(
      style: sandikFont(
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
                padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
                child: Row(
                  children: [
                    Text(
                      // Başlık artık iki türü birden kapsıyor: liste hem
                      // teknik sinyalleri hem fiyat alarmlarını taşıyor.
                      'Bildirimler',
                      style: context.t.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.text90,
                          decoration: TextDecoration.none),
                    ),
                    const SizedBox(width: SandikSpace.sm),
                    if (akis.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.c.amberFill.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                          border: Border.all(
                              color:
                                  context.c.amberFill.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${akis.length}',
                          style: context.t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.amberText,
                              decoration: TextDecoration.none),
                        ),
                      ),
                    const Spacer(),
                    // Alarm LİSTESİ buradan (2026-09-21): alarm bir portföy
                    // aracı, bildirim ayarı değil; Ayarlar › Bildirimler'de
                    // saklıydı. Ayarlar'daki satır da duruyor (kapı olarak).
                    SandikTappable(
                      semanticLabel: context.l10n.myAlarms,
                      onTap: () => pushGuarded(
                        context,
                        adaptiveRoute<void>(
                            builder: (_) => const PriceAlertsScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SandikSpace.sm, vertical: SandikSpace.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_alert_outlined,
                                size: 16, color: context.c.amberText),
                            const SizedBox(width: SandikSpace.xs),
                            Text(
                              context.l10n.myAlarms,
                              style: context.t.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.c.amberText,
                                  decoration: TextDecoration.none),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Aktif sinyal varsa "Temizle" (pasife al). Hepsi zaten
                    // geçmişteyse bu buton anlamsız — orada "Geçmişi Sil"
                    // devreye girer (aşağıda, GEÇMİŞ başlığının yanında).
                    if (active.isNotEmpty)
                      SandikTappable(
                        semanticLabel: context.l10n.clearAllSignals,
                        // Toplu ve geri alınamaz bir işlem: HIG "forgiveness"
                        // ilkesi onay ister. Tek satır silmede onay yok
                        // (aşırıya kaçmamak için), ama "tümü" farklıdır.
                        //
                        // Sheet ARTIK HEMEN KAPANMIYOR: eskiden `Navigator.pop`
                        // silme işleminin sonucunu beklemeden çağrılıyordu ve
                        // hata olsa bile kullanıcı temizlenmiş sanıyordu.
                        onTap: () async {
                          final onay = await _onayAl(
                            context,
                            baslik: context.l10n.clearAllLower,
                            // "Kaldırılacak" DEĞİL "geçmişe taşınacak":
                            // bu işlem kalıcı silmez, kayıtlar GEÇMİŞ
                            // bölümünde durur. Eski metin kullanıcıya
                            // silineceklerini söylüyordu ve bu yüzden
                            // "sildim ama duruyor" hissi doğuyordu.
                            mesaj: context.l10n.clearAllSignalsBody(active.length),
                            eylem: context.l10n.clearVerb,
                          );
                          if (!onay) return;
                          try {
                            await onDismissAll();
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (context.mounted) _hataGoster(context);
                          }
                        },
                        child: Text(
                          context.l10n.clearAllUpper,
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
                  padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8, SandikSpace.screenH(context), 32),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: context.c.gain, size: 22),
                      const SizedBox(width: SandikSpace.md),
                      Text(context.l10n.noActiveSignals,
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
                      padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 0, SandikSpace.screenH(context), 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in active) ...[
                            _satir(context, e, faded: false),
                            const SizedBox(height: SandikSpace.sm),
                          ],
                          if (history.isNotEmpty) ...[
                            const SizedBox(height: SandikSpace.xs),
                            // Başlık + KALICI SİLME.
                            //
                            // "Tümünü Temizle" yalnızca `dismissed_at`
                            // damgalar; kayıtlar burada durmaya devam eder ve
                            // kullanıcı "sildim ama duruyor" diyordu
                            // (kullanıcı isteği, 2026-09-01). Kalıcı silme
                            // eylemi, sildiği şeyin YANINDA durmalı — ayrı bir
                            // menüye gömülürse bulunamaz.
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                              child: Row(
                                children: [
                                  Text(
                                    context.l10n.historyUpper,
                                    style: context.t.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        color: context.c.text58,
                                        decoration: TextDecoration.none),
                                  ),
                                  const Spacer(),
                                  SandikTappable(
                                    semanticLabel:
                                        context.l10n.deleteHistoryCount(history.length),
                                    onTap: () async {
                                      // Aktif sinyal de varsa kullanıcıya
                                      // KAPSAM sorulur: yalnızca geçmiş mi,
                                      // yoksa çanı tamamen boşalt mı.
                                      // Aktif yoksa soru anlamsız — düz onay.
                                      final hepsiniSil = active.isEmpty
                                          ? false
                                          : await _kapsamSor(
                                              context,
                                              gecmis: history.length,
                                              aktif: active.length,
                                            );
                                      if (hepsiniSil == null) return;
                                      if (!context.mounted) return;
                                      if (!hepsiniSil) {
                                        final onay = await _onayAl(
                                          context,
                                          baslik: context.l10n.deleteHistoryTitle,
                                          mesaj: context.l10n.deleteHistoryBody(history.length),
                                          eylem: context.l10n.permanentDeleteUpper,
                                        );
                                        if (!onay) return;
                                      }
                                      try {
                                        if (hepsiniSil) {
                                          await onDeleteAll();
                                        } else {
                                          await onDeleteHistory();
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          _hataGoster(context);
                                        }
                                      }
                                    },
                                    // 44pt dokunma hedefi: metin ~18pt,
                                    // dikey padding ile eşiğe çıkar.
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 12),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete_outline_rounded,
                                              size: 15, color: context.c.loss),
                                          const SizedBox(width: 4),
                                          Text(
                                            context.l10n.deleteHistoryButton,
                                            style: context.t.titleSmall
                                                ?.copyWith(
                                                    color: context.c.loss,
                                                    decoration:
                                                        TextDecoration.none),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final e in history) ...[
                              _satir(context, e, faded: true),
                              const SizedBox(height: SandikSpace.sm),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 0, SandikSpace.screenH(context), 16),
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
    final Color color =
        isBuy ? context.c.gain : (isSell ? context.c.loss : context.c.text58);
    final String label = isBuy ? 'AL' : (isSell ? 'SAT' : context.l10n.signalNeutral);
    final IconData icon = isBuy
        ? Icons.trending_up_rounded
        : (isSell
            ? Icons.trending_down_rounded
            : Icons.horizontal_rule_rounded);
    final int count = isBuy ? alert.buyCount : (isSell ? alert.sellCount : 0);

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
          border: Border.all(
              color: color.withValues(alpha: borderAlpha), width: 1.5),
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
                          color: color.withValues(alpha: 0.18 * alphaFactor),
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
                        ? context.l10n.signalDeletedAt(_formatDate(alert.detectedAt))
                        : context.l10n.signalConfidence(count, fmtPct(alert.confidence, digits: 0)),
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
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: context.c.text36),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
      semanticLabel: hidden ? context.l10n.showBalance : context.l10n.hideBalance,
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
  final String semanticLabel;
  const _HeaderIconButton({
    required this.onTap,
    required this.child,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SandikTappable(
      onTap: onTap,
      semanticLabel: semanticLabel,
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
    // Rozet İKİ türü birden sayar: kullanıcı için çan tek bir yer ve
    // "3 bildirim" dediğinde açtığında üçünü de görmeli. Yalnızca
    // sinyalleri saymak, alarm gelince rozetin kıpırdamaması demekti.
    final count = ref.watch(activeSignalsProvider).length +
        ref.watch(activePriceAlertNotificationsProvider).length +
        ref.watch(activeAppNotificationsProvider).length;

    return SandikTappable(
      onTap: onTap,
      semanticLabel: count > 0 ? '$count yeni bildirim' : 'Bildirimler',
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

/// Boş portföy çağrısı. ("Bu türde varlık yok" dili ana sayfadaki tür
/// filtresiyle birlikte kalktı, 2026-09-28.)
class _EmptyPortfolioCta extends StatelessWidget {
  const _EmptyPortfolioCta();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.savings_outlined, color: context.c.text36, size: 48),
        const SizedBox(height: SandikSpace.md),
        Text(
          context.l10n.noAssetsYet,
          style: context.t.titleLarge?.copyWith(color: context.c.text90),
        ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          context.l10n.noAssetsYetHint,
          textAlign: TextAlign.center,
          style: context.t.bodyMedium?.copyWith(color: context.c.text36),
        ),
        const SizedBox(height: SandikSpace.lg),
        SandikTappable(
          haptic: SandikHaptic.medium,
          semanticLabel: 'Varlık ekle',
          onTap: () => pushGuarded(
            context,
            adaptiveRoute<void>(builder: (_) => const AddAssetScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: context.c.amberFill.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border:
                  Border.all(color: context.c.amberFill.withValues(alpha: 0.5)),
            ),
            // 28pt yatay padding + ikon + etiket dar ekranda
            // sığmıyor. FittedBox içeriği kırpmadan küçültür;
            // düğme metni her cihazda tam okunur.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: context.c.amberText, size: 20),
                  const SizedBox(width: SandikSpace.sm),
                  Text(
                    context.l10n.addFirstAsset,
                    style: context.t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.c.amberText),
                  ),
                ],
              ),
            ),
          ),
        ),
        // İkinci yol: ekstre yapıştır (2026-09-20). Portföyünü ilk kez kuran
        // kullanıcı için en hızlı yol bu; eskiden yalnızca + › Toplu › Yapıştır
        // ile üç dokunuş derindeydi ve ilk 10 dakikada bulunmuyordu. (Eskiden
        // `!filtered` koşuluyla gizlenirdi; tür filtresi 2026-09-28'de
        // kalktı, bu widget artık yalnızca gerçekten boş portföyde çizilir.)
        ...[
          const SizedBox(height: SandikSpace.md),
          TextButton.icon(
            onPressed: () => pushGuarded(
              context,
              adaptiveRoute<bool>(builder: (_) => const CsvImportScreen()),
            ),
            icon: Icon(Icons.content_paste_go_rounded,
                size: 18, color: context.c.text58),
            label: Text(
              context.l10n.pasteFromStatement,
              style: context.t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: context.c.text58),
            ),
          ),
          Text(
            context.l10n.emptyPasteHint,
            textAlign: TextAlign.center,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ],
      ],
    );
  }
}
