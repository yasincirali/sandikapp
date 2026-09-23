import 'dart:async';
import '../services/price_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        LinearProgressIndicator,
        Icons,
        TextStyle,
        RefreshIndicator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/base_currency_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/chart_line_width.dart';
import '../utils/chart_axis.dart';
import '../utils/mum_turetici.dart';
import '../models/yatirimci_seviyesi.dart';
import '../utils/piyasa_kapali_etiketi.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/spot_lookup.dart';
import '../widgets/share_card.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';
import '../services/analytics_service.dart';
import '../services/daily_summary.dart';
import '../services/history_service.dart';
import '../services/inflation_service.dart';
import '../services/tazelik_ritmi.dart';
import '../services/real_return_service.dart';
import '../services/leaderboard_service.dart';
import '../services/contribution_history_service.dart';
import '../services/insight_metrics_service.dart';
import '../services/period_summary_service.dart';
import '../services/recap_service.dart';
import '../services/xirr_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/period_summary_view.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/zoomable_chart.dart';
import '../models/grafik_tipi.dart';
import '../widgets/transaction_segment.dart';
import '../widgets/grafik_tipi_secici.dart';
import '../providers/preferences_provider.dart'
    show leaderboardOptInProvider, yatirimciSeviyesiProvider;
import 'leaderboard_screen.dart';
import '../widgets/kapsam_kisi_secici.dart';
import '../widgets/zoom_data_controller.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/tour_anchor.dart';

part 'portfolio_performance/grafik_kabi.dart';
part 'portfolio_performance/seriler.dart';
part 'portfolio_performance/kontroller.dart';
part 'portfolio_performance/kartlar.dart';
part 'portfolio_performance/yardimci_widgetlar.dart';
part 'portfolio_performance/tur_dokumu_karti.dart';
part 'portfolio_performance/ozet_yan_veri.dart';

class PortfolioPerformanceScreen extends ConsumerStatefulWidget {
  final String? initialView;
  final AssetType? initialTypeFilter;

  final double initialScrollOffset;

  /// Geri butonu gösterilsin mi.
  ///
  /// Bu ekran İKİ şekilde kullanılıyor: alt menüde sekme olarak (geri
  /// butonu olmamalı, gidilecek yer yok) ve Portföy ekranından push edilerek
  /// (geri butonu ŞART, aksi halde kullanıcı ekranda kilitli kalır —
  /// yalnızca sistem geri hareketiyle çıkabilir).
  ///
  /// Aynı bayrak çıkış butonunu da gizler: push edilmiş bir alt sayfada
  /// "Çıkış Yap" beklenmeyen ve tehlikeli bir eylemdir.
  final bool showBackButton;

  /// Açılışta Özet sekmesi seçili gelsin mi.
  ///
  /// Ana ekrandaki "Bu hafta" kartı buradan derin bağlanıyor: kullanıcı
  /// kartı görüp tıkladığında aynı rakamın geldiği yere düşmeli, Grafik
  /// sekmesine değil.
  final bool initialOzet;

  /// Açılışta seçili dönem — `_periods` dizisindeki indeks.
  ///
  /// `SummaryPeriod.fromIndex` ile aynı eşleme. Sınır dışı değer
  /// kırpılıyor, atılmıyor: derin bağlantı bozuk bir indeksle gelse de
  /// ekran açılmalı.
  final int? initialPeriodIdx;

  const PortfolioPerformanceScreen({
    super.key,
    this.initialView = '',
    this.initialTypeFilter,
    this.initialScrollOffset = 0,
    this.showBackButton = false,
    this.initialOzet = false,
    this.initialPeriodIdx,
  });

  /// Uygulama DIŞI yüzeyden (ana ekran widget'ı, Canlı Etkinlik) gelen
  /// "GÜNLÜK görünümü aç" isteği.
  ///
  /// [initialPeriodIdx] bu işi GÖREMEZ: sekmeler `IndexedStack` içinde
  /// yaşıyor, ekran bir kez kurulduktan sonra `widget.initialPeriodIdx`
  /// bir daha okunmaz. Kullanıcı ekranı 1Y'de bırakıp kilit ekranındaki
  /// GÜNLÜK rakamına dokunduğunda 1Y kartına düşüyordu.
  ///
  /// `null` = bekleyen istek yok. Tüketen taraf `null`'a çeker; aksi halde
  /// ekran her yeniden kurulduğunda (tema/dil değişimi, hot restart) eski
  /// dokunuş yeniden uygulanır ve kullanıcının seçtiği dönem geri alınır.
  /// Aynı kanal deseni `MainNavigationScreen.sekmeIstegi` ile birebir.
  static final gunlukIstegi = ValueNotifier<bool?>(null);

  /// Dönem başlangıcı — takvim ayına göre.
  ///
  /// Kullanıcı isteği (2026-09-12): "1 aylık grafik bir önceki ay aynı
  /// günden başlamalı, 6 ayda da 6 ay önce aynı günden."
  ///
  /// Ayın son günleri özel: 31 Mart'tan bir ay geri 31 Şubat olmaz.
  /// `DateTime(2026, 2, 31)` Dart'ta sessizce 3 Mart'a TAŞAR — yani ileri
  /// bir tarihe. Bu yüzden hedef ayın gün sayısına kırpılıyor.
  @visibleForTesting
  static DateTime donemBaslangici(DateTime bitis, int ayGeri) {
    final toplamAy = bitis.year * 12 + (bitis.month - 1) - ayGeri;
    final yil = toplamAy ~/ 12;
    final ay = toplamAy % 12 + 1;
    // Hedef ayın son günü: bir sonraki ayın 0. günü.
    final ayinSonGunu = DateTime(yil, ay + 1, 0).day;
    final gun = bitis.day <= ayinSonGunu ? bitis.day : ayinSonGunu;
    return DateTime(yil, ay, gun, bitis.hour, bitis.minute, bitis.second);
  }

  @override
  ConsumerState<PortfolioPerformanceScreen> createState() =>
      _PortfolioPerformanceScreenState();
}

class _PortfolioPerformanceScreenState
    extends ConsumerState<PortfolioPerformanceScreen> {

  /// Kapsam paneli açık mı? (kim / hangi tür / hangi mod)
  ///
  /// Kapalı başlar: üç denetim de seyrek kullanılıyor ve ilk açılışta
  /// grafiğe ayrılan dikey alanı yemeleri için bir sebep yok. Seçili kapsam
  /// panel kapalıyken de çipin üstünde yazılı (bkz. `_buildScopeBar`).
  bool _kapsamAcik = false;

  int _selectedPeriodIdx = 0; // Günlük (intraday)
  late String? _view;
  late AssetType? _typeFilter;
  // Grafik modu: false = gerçek geçmiş (alım/satışlara göre),
  //             true  = simülasyon (bugünkü net pozisyon tüm dönem boyunca).
  bool _simulate = false;

  /// Yüzey sekmesi: false = Grafik, true = Özet.
  ///
  /// Dönem seçici (`_selectedPeriodIdx`) İKİ SEKME ARASINDA PAYLAŞILIR —
  /// kullanıcı Grafik'te 6A seçip Özet'e geçince aynı pencereyi görür.
  /// Sekme başına ayrı bir dönem tutmak, aynı ekranda iki farklı "şu anki
  /// dönem" kavramı yaratırdı.
  bool _ozetSekmesi = false;
  // Intraday sekmesi seçiliyken şimdiki zaman marker'ının X ekseni üstünde
  // ilerlemesi için periyodik tick. Her 60 sn'de bir setState çağırıyor.
  /// Ortak nabız dinleyicisini kaldırma işlevi (bkz. `TazelikRitmi.nabiz`).
  VoidCallback? _nabziBirak;

  // Zoom-aware veri controller'ı. Chart viewport değiştikçe uygun
  // ResolutionTier'da veri yükler, debounce ile spam engeller.
  ZoomDataController? _zoomController;
  // Controller'ın hangi (view, tip, periyot, simülasyon, asset-hash) için
  // kurulduğunu takip et — bunlar değişince yeni controller kurulur.
  String? _zoomKey;

  // Ana grafik + volume subchart aynı X viewport'unu paylaşsın diye
  // ortak controller. Grafiğin fullMinX/fullMaxX'i period değiştikçe
  // güncellenir; ZoomableChart & ZoomableBarChart bunu dinler.
  ChartViewport? _viewport;
  String? _viewportKey;

  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _typeFilter = widget.initialTypeFilter;
    _ozetSekmesi = widget.initialOzet;
    // Sınır dışı indeks KIRPILIR, atılmaz: bozuk bir derin bağlantı
    // ekranı hiç açılmaz hale getirmemeli.
    if (widget.initialPeriodIdx != null) {
      _selectedPeriodIdx =
          widget.initialPeriodIdx!.clamp(0, _periods.length - 1);
    }
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
    // Dönem derin bağlantıyla GÜNLÜK dışına ayarlanmış olabilir; tick
    // kararı seçili dönemden sonra verilmeli.
    _startIntradayTickIfNeeded();

    // Dış yüzey dokunuşu. Soğuk açılışta istek bu ekran KURULMADAN önce
    // yazılmış olur (sekme isteği de öyle), o yüzden dinleyiciyi bağlamakla
    // yetinmeyip mevcut değeri bir kez okuyoruz.
    PortfolioPerformanceScreen.gunlukIstegi.addListener(_gunlukIstegiGeldi);
    if (PortfolioPerformanceScreen.gunlukIstegi.value != null) {
      Future.microtask(_gunlukIstegiGeldi);
    }
  }

  /// Widget / Canlı Etkinlik dokunuşunu UYGULAR: ekranı o yüzeyin anlattığı
  /// kapsama geri getirir.
  ///
  /// Dönemden fazlası sıfırlanıyor çünkü kilit ekranı TEK bir şeyi anlatır:
  /// kullanıcının KENDİ portföyü, tüm türler, gerçek (simülasyon değil)
  /// defter, bugün. Ortak sekmesinde ya da "yalnızca Fon" filtresinde
  /// bırakılmış bir ekran, aynı dokunuştan sonra kilit ekranından FARKLI
  /// bir toplam gösterirdi.
  ///
  /// Özet sekmesi de kapatılır: dokunuşun vaadi grafiktir (kilit ekranında
  /// görülen eğrinin büyüğü), tablo değil.
  void _gunlukIstegiGeldi() {
    if (PortfolioPerformanceScreen.gunlukIstegi.value == null) return;
    // `mounted` kontrolü TÜKETMEDEN önce: sökülmüş bir state isteği yutarsa
    // dokunuş sessizce kaybolur.
    if (!mounted) return;
    PortfolioPerformanceScreen.gunlukIstegi.value = null;

    _guncelle(() {
      _selectedPeriodIdx = 0; // GÜNLÜK
      _ozetSekmesi = false;
      _simulate = false;
      _view = ''; // yalnızca kendi portföyü — kilit ekranıyla aynı kapsam
      _typeFilter = null;
      // Gün içi future'ı bilerek düşür: dokunuş "şu anki hâlini göster"
      // demek, önbellekteki kareyi değil. Tohum da atılır — kapsam ve tür
      // burada DEĞİŞİYOR, başka bir defterin karesi gösterilmemeli
      // (bkz. `_gunIciTohumuAt`).
      _intradayKey = null;
      _gunIciTohumuAt();
    });
    _startIntradayTickIfNeeded();
  }

  @override
  void dispose() {
    // Dinleyici STATİK bir `ValueNotifier`'a bağlı: kaldırılmazsa ekran
    // yeniden kurulduğunda üst üste birikir ve tek dokunuş birden çok kez
    // işlenir (aynı gerekçe `MainNavigationScreen.dispose`).
    PortfolioPerformanceScreen.gunlukIstegi.removeListener(_gunlukIstegiGeldi);
    _nabziBirak?.call();
    _zoomController?.dispose();
    _viewport?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Intraday future'ı memoize et. `FutureBuilder`'a build içinde doğrudan
  // `getPortfolioHistoryHourly(...)` verilmesi her rebuild'de (tip çipi,
  // ortak sekmesi, 30 sn'lik tick) YENİ bir future üretiyordu; FutureBuilder
  // yeni future'ı waiting sayıp grafiği söküyordu. Aynı varlık kümesi için
  // aynı future yeniden kullanılır.
  // Dağılımı da taşır: gün içi sekmesinde tür dökümü kartı bu future'dan
  // beslenir. Eskiden yalnızca toplam seri (`Map<int,double>`) çekiliyordu ve
  // kart bu sekmede HİÇ görünmüyordu.
  Future<PortfolioHistoryBreakdown>? _intradayFuture;
  String? _intradayKey;
  // Son başarılı intraday sonucu. Future yenilendiğinde (30 sn'lik tick veya
  // varlık kümesi değişimi) snapshot bir kare boyunca null olur; bu alan
  // sayesinde grafik o karede boşalmaz.
  PortfolioHistoryBreakdown? _lastIntradayData;

  /// [_lastIntradayData]'nın AİT OLDUĞU varlık kümesi (`_intradayHistory`
  /// anahtarıyla aynı).
  ///
  /// **Neden damga (kullanıcı bildirimi, 2026-09-22):** "performans özet
  /// ekranı açıldığı an başka değerlerle doluyor, 1 sn sonrasında doğru
  /// değerler setleniyor."
  ///
  /// `_lastIntradayData` hangi kapsama ait olduğunu TAŞIMIYORDU. Kullanıcı
  /// Ben → Birlikte'ye geçtiğinde yeni future bir kare boyunca `waiting`
  /// oluyor, `snapshot.data` null geliyor ve dal ÖNCEKİ kapsamın verisine
  /// düşüyordu. `hasData: data != null` o veriyi TAZE sayıyor, iskelet
  /// kapısı açılmıyor ve Özet bir saniye boyunca BAŞKA bir defterin
  /// rakamlarını gösteriyordu.
  ///
  /// Damga ile fark edilir: anahtar tutmuyorsa veri `stale`'dir — grafik
  /// onu soluk bir ara kare olarak çizmeye devam eder (spinner'dan iyi),
  /// Özet ise sayı basmaz, iskelet gösterir. İki yüzeyin ihtiyacı farklı:
  /// bir çizginin eski hâli bilgi taşır, yanlış bir RAKAM taşımaz.
  String? _lastIntradayKey;

  // days=0 && intraday=true → günlük (24 saat, 5 dk çözünürlük).
  /// [ayGeri] dolu ise dönem başı TAKVİMDEN hesaplanır: "1 ay" 30 gün
  /// değil, bir önceki ayın AYNI günüdür.
  ///
  /// Sabit gün sayısı kullanıcının kurduğu cümleyle uyuşmuyordu: 31 günlük
  /// aylarda "1A" bir gün eksik, Şubat'ta iki-üç gün fazla pencere
  /// gösteriyordu. [days] yine taşınıyor çünkü veri katmanı (çözünürlük
  /// merdiveni, önbellek anahtarı) gün cinsinden çalışıyor — takvim
  /// başlangıcı `donemBaslangici` ile hesaplanıp gün farkına çevriliyor.
  static const List<({String label, int days, int? ayGeri, bool intraday})>
      _periods = [
    (label: 'GÜNLÜK', days: 0, ayGeri: null, intraday: true),
    (label: '1H', days: 7, ayGeri: null, intraday: false),
    (label: '1A', days: 30, ayGeri: 1, intraday: false),
    (label: '6A', days: 180, ayGeri: 6, intraday: false),
    (label: '1Y', days: 365, ayGeri: 12, intraday: false),
  ];

  // ── Logic ──────────────────────────────────────────────────────────────────

  // Nakit akışı kuralı (`_flowOf`) buradaydı; 2026-09-23'te kaldırıldı.
  // Tek kaynak `PeriodSummaryService.flowOf` / `netInflow` — dönem kartı,
  // Özet ve varlık ekranı "piyasa etkisi"ni aynı fonksiyondan okur
  // (`PeriodSummaryService.piyasaEtkisi`). Üstteki "seriyi arındır" notu da
  // ölüydü: arındırma 2026-08-31 kararıyla kaldırılmıştı.

  // ── Build ──────────────────────────────────────────────────────────────────

  /// `setState` sarmalayıcısı — part dosyalarındaki extension'lar için.
  ///
  /// Ekran 4.600 satırdı; gövde `portfolio_performance/` altındaki part
  /// dosyalarına extension olarak bölündü (aynı kütüphane, private erişim
  /// aynen). `setState` `@protected` olduğu için extension içinden çağrılamaz;
  /// bu ince sarmalayıcı tek geçiş noktasıdır.
  void _guncelle(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final pStateAsync = ref.watch(portfolioProvider);
    final partnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final activePartners = ref.watch(activePartnersProvider);

    final endDate = DateTime.now();
    final isIntraday = _periods[_selectedPeriodIdx].intraday;
    // Intraday modda X ekseni bugünün 00:00'ından başlar.
    // Dönem başı: aylık pencerelerde TAKVİMDEN, diğerlerinde gün sayısıyla.
    //
    // "1A" 30 gün değil, bir önceki ayın aynı günü (kullanıcı isteği
    // 2026-09-12). Haftalık pencere gün sayısıyla kalıyor — "1 hafta"
    // zaten tam olarak 7 gündür, takvim ayı gibi değişken değil.
    final donem = _periods[_selectedPeriodIdx];
    // Dönem başı GÜN BAŞINA çekilir.
    //
    // `endDate` şu an (örn. 22:29) ve ondan gün çıkarınca başlangıç da
    // gün ortasında kalıyordu. Veri kovaları ise gün başına normalize
    // ediliyor → ilk nokta `startDate`'ten ÖNCE düşüp X'i NEGATİF
    // yapıyordu (ölçüldü: −0,02 gün). Eksen 0'dan başladığı için o nokta
    // kırpılıyor ve çizgi grafiğin solundan değil içeriden başlıyordu
    // (kullanıcı bildirimi 2026-09-12, 1H sekmesi).
    //
    // Gün başına çekmek ekseni kovalarla hizalıyor; tüm dönemler aynı
    // davranıyor.
    final hamBaslangic = isIntraday
        ? dayKey(endDate)
        : (donem.ayGeri != null
            ? PortfolioPerformanceScreen.donemBaslangici(endDate, donem.ayGeri!)
            : endDate.subtract(Duration(days: donem.days)));
    final startDate = isIntraday
        ? hamBaslangic
        : dayKey(hamBaslangic);

    return DefaultTextStyle(
      style: sandikFont(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              // Başlık çubuğu 2026-09-15'te iki kez inceldi: 20/12 →
              // screenH/8, sonra dikey 8 → 4 ("biraz daha inceltilebilir").
              // Yükseklik artık 44pt'lik ikon hedefleri + 8 = 52pt; daha
              // azı ikonların dokunma hedefini keser. `fontSize: 22` yerine
              // tema ölçeği. Kazanılan alan doğrudan grafiğe gidiyor.
              Padding(
                padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                    SandikSpace.xs, SandikSpace.screenH(context), SandikSpace.xs),
                child: Row(
                  children: [
                    if (widget.showBackButton) ...[
                      // 44pt dokunma hedefi (HIG minimumu).
                      SizedBox(
                        width: SandikTouch.min,
                        height: SandikTouch.min,
                        child: CupertinoButton(
                          minimumSize: SandikTouch.minSize,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          onPressed: () => Navigator.pop(context),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 20, color: context.c.text90),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        context.l10n.performanceTitle,
                        // Tek satır, kenarda solar: sarmalasa başlık çubuğu
                        // uzardı, üç noktayla kesilse "Performan…" olurdu.
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: context.t.headlineMedium
                            ?.copyWith(color: context.c.text90),
                      ),
                    ),
                    // Kişi seçimi 2026-09-15'te bir süre buradaydı (çip,
                    // sonra avatar şeridi); kullanıcı: "o kadar yukarıda
                    // olması doğru olmadı, aşağıya gelmeli". Artık kontrol
                    // yığınının ilk satırında (`KapsamKisiSecici`).
                    // Yarış bir GEZİNME girişi, grafik aracı değil: eskiden
                    // grafik araç satırında duruyordu ve o satırın tamamı
                    // kaldırıldı. Yeri üst çubuk.
                    if (ref.watch(leaderboardOptInProvider) &&
                        activePartners.isNotEmpty) ...[
                      Semantics(
                        button: true,
                        label: context.l10n.raceTitle,
                        child: ExcludeSemantics(
                          child: CupertinoButton(
                            minimumSize: SandikTouch.minSize,
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.push(
                              context,
                              adaptiveRoute<void>(
                                  builder: (_) => const LeaderboardScreen()),
                            ),
                            child: Icon(Icons.emoji_events_rounded,
                                size: 20, color: context.c.amberText),
                          ),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.xs2),
                    ],
                    // Çıkış yalnızca sekme modunda. Push edilmiş alt sayfada
                    // beklenmeyen bir eylem olurdu.
                    if (!widget.showBackButton)
                      SandikLogoutButton(
                        onPressed: () => confirmAndLogout(context, ref),
                      ),
                  ],
                ),
              ),
              // ── Body ────────────────────────────────────────────────────
              Expanded(
                child: pStateAsync.when(
                  loading: () => const SandikLoadingScreen(),
                  error: (e, _) => SandikErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(portfolioProvider)),
                  data: (pState) => partnerAssetsAsync.when(
                    loading: () => const SandikLoadingScreen(),
                    error: (e, _) => SandikErrorView(
                        error: e,
                        onRetry: () => ref.invalidate(portfolioProvider)),
                    data: (partnerMap) {
                      // Filter assets based on view
                      // Sahiplik sınırı korunmalı — bkz. aggregatePositionsByOwner.
                      // `targetAssets` ham ledger olarak akmaya devam eder
                      // (HistoryService buy/sell tarihlerini kendisi yorumlar),
                      // ancak aggregate edilirken sahipler ayrı tutulur.
                      final List<List<Asset>> ownerLots;
                      if (_view == '') {
                        ownerLots = [pState.assets];
                      } else if (_view != null) {
                        ownerLots = [partnerMap[_view] ?? const []];
                      } else {
                        ownerLots = [pState.assets, ...partnerMap.values];
                      }
                      List<Asset> targetAssets = [
                        for (final l in ownerLots) ...l
                      ];
                      // deleteLog'u çıkar (buy row zaten silinmiş, sadece
                      // transaction kaydı). Buy + sell birlikte gider —
                      // HistoryService her gün için buy addedDate <= dayTs
                      // ve sell addedDate <= dayTs kurallarıyla o gün geçerli
                      // net miktarı hesaplar. Böylece grafik hem alınmadan
                      // önceki günlerde 0 gösterir hem de satış günü sonrası
                      // net miktara oturur.
                      // Filtreler hem düz listeye hem sahip gruplarına AYNI
                      // şekilde uygulanmalı; aksi halde grafik ile özet farklı
                      // varlık kümelerini gösterir.
                      // `isActive`: mezar taşları VE yumuşak silinmiş lot'lar
                      // grafiğe girmez — silinen varlık hiç olmamış sayılır.
                      bool keep(Asset a) =>
                          a.isActive &&
                          (_typeFilter == null || a.type == _typeFilter);

                      targetAssets = targetAssets.where(keep).toList();
                      final filteredOwnerLots = [
                        for (final lots in ownerLots) lots.where(keep).toList(),
                      ];

                      // "Bu türden portföyümde VAR MI?" sorusunun tek
                      // doğru cevabı net pozisyondur, ham satır sayısı
                      // değil: temettü satırı miktara girmez, satılıp
                      // bitmiş pozisyonun alım/satım satırları ise geçmişte
                      // durur. `aggregatePositions` ikisini de düşürür —
                      // portföy toplamları da aynı kaynaktan okur, yani boş
                      // durum mesajı ekranın geri kalanıyla aynı şeyi söyler.
                      final holdsSelectedType =
                          aggregatePositionsByOwner(filteredOwnerLots)
                              .isNotEmpty;

                      // Simülasyon modu: bugünün net pozisyonlarını
                      // tüm dönem boyunca sabit tut — "şu anki portföyümü o
                      // zaman elimde tutsaydım" senaryosunu HistoryService'e
                      // net display-asset listesi olarak ver.
                      final chartAssets = _simulate
                          ? aggregatePositionsByOwner(filteredOwnerLots)
                              .map((p) => p.asDisplayAsset())
                              .toList()
                          : targetAssets;

                      // Filtre: yalnızca fiyat serisi alınabilen varlıklar
                      // geçer. Aksi halde HistoryService tüm seriyi
                      // boşaltabiliyor (tek price-less varlık tüm günü
                      // götürebiliyordu).
                      //
                      // Kural `FiyatKaynagi.seriyeGirer`'de — burada bir
                      // KOPYASI vardı ve Bugün kartı o elemeyi hiç
                      // yapmıyordu: aynı defterden iki farklı seri çıkıyor,
                      // "Ben" kapsamında bile iki yüzey farklı kâr/zarar
                      // gösteriyordu (kullanıcı bildirimi 2026-09-22).
                      const isRenderable = FiyatKaynagi.seriyeGirer;

                      final chartAssetsRenderable = [
                        for (final a in chartAssets)
                          if (isRenderable(a)) a
                      ];
                      final filteredOwnerLotsRenderable = [
                        for (final lots in filteredOwnerLots)
                          [
                            for (final a in lots)
                              if (isRenderable(a)) a
                          ]
                      ];

                      // TradingView "auto range": kullanıcı seçilen periyot
                      // içinde hiç varlığı yoksa (örn. 1Y seçtiği ama 3 gün
                      // önce başladı), chart ilk alım tarihinden itibaren
                      // çizilir. History fetch'i de bu daraltılmış aralıkta
                      // yapmalıyız — aksi halde controller 1Y'lik boş veri
                      // fetch edip görselde tek nokta gibi gösterir.
                      //
                      // Simülasyonda UYGULANMAZ: o mod "bugünkü net pozisyonu
                      // tüm dönem boyunca tutsaydım" senaryosudur — pozisyon
                      // her gün var sayılır, ilk alım tarihi alakasızdır.
                      // Aralığı ona daraltmak, 1A seçiliyken grafiği ilk alım
                      // tarihinden başlatıyordu (gerçek tab doğru çalışırken).
                      DateTime effectiveStart = startDate;
                      if (!isIntraday && !_simulate) {
                        final buys =
                            chartAssetsRenderable.where((a) => a.isBuy);
                        if (buys.isNotEmpty) {
                          final firstBuy = buys
                              .map((a) => a.addedDate)
                              .reduce((a, b) => a.isBefore(b) ? a : b);
                          if (firstBuy.isAfter(startDate)) {
                            effectiveStart = DateTime(
                                firstBuy.year, firstBuy.month, firstBuy.day);
                          }
                        }
                      }

                      // Intraday hâlâ eski hourly servisini kullanır (5 dk
                      // grid, ayrı optimize logic). Diğer periyotlar zoom-aware
                      // ZoomDataController üstünden gider.
                      if (!isIntraday) {
                        _ensureController(
                          chartAssets: chartAssetsRenderable,
                          from: effectiveStart,
                          to: endDate,
                          intraday: false,
                        );
                      }

                      // ÖNEMLİ: Aşağıdaki her iki dalda da `_buildChartWithData`
                      // KOŞULSUZ çağrılır. Filtre kontrolleri (ortak sekmesi,
                      // varlık tipi çipleri, periyot toggle'ı) o metodun içinde
                      // yaşıyor; erken `return CustomLoadingView()` yapılırsa
                      // tüm filtreler ağaçtan düşüyor ve kullanıcı yükleme
                      // bitene kadar hiçbir filtreye dokunamıyordu. Artık
                      // yükleme göstergesi yalnızca grafik alanını kaplar.
                      if (isIntraday) {
                        // Intraday için tek seferlik future — 5dk grid ve
                        // dakikalık tick zaten var. Future `_intradayFuture`
                        // içinde memoize edilir; aksi halde her setState
                        // (tip/ortak filtresi, 30sn tick) yeni bir fetch
                        // başlatıp grafiği baştan yüklemeye sokuyordu.
                        // Bu karede beklenen veri kümesi — tohumun AİT
                        // OLDUĞU küme ile karşılaştırılır (`_lastIntradayKey`).
                        final intradayKey =
                            chartAssetsRenderable.map((a) => a.id).join(',');
                        return FutureBuilder<PortfolioHistoryBreakdown>(
                          // `key` ŞART — kök neden buydu (2026-09-22,
                          // emülatör logu ile ölçüldü).
                          //
                          // `FutureBuilder` future'ı değiştiğinde
                          // `connectionState`'i `waiting`e çeker ama
                          // **`snapshot.data`'yı KORUR** (Flutter'ın
                          // belgelenmiş davranışı: yeni future çözülene
                          // kadar eski sonuç elde tutulur). Ölçülen log:
                          //
                          //   view=<ortak> waiting=true  nokta=195 tohumKey=yok
                          //   view=<ortak> waiting=false nokta=195 tohumKey=var
                          //
                          // Yani `waiting` karesinde bile 195 noktalı bir
                          // seri vardı ve o ÖNCEKİ kapsamın sonucuydu —
                          // `hasData` true çıkıyor, iskelet kapısı
                          // açılmıyor, Özet bir an başka birinin
                          // rakamlarını gösteriyordu.
                          //
                          // Tohumu atmak (`_gunIciTohumuAt`) bunu
                          // çözmedi çünkü veri tohumdan DEĞİL, builder'ın
                          // kendi eski snapshot'ından geliyordu.
                          //
                          // `ValueKey` kümeyi değiştirdiğimizde builder'ı
                          // YENİDEN KURAR: state sıfırlanır, `snapshot.data`
                          // null başlar, `hasData` false olur ve Özet
                          // iskelete düşer. Zoom yolunun filtre değişince
                          // yeni controller kurmasının birebir karşılığı —
                          // "sadece günlükte hatalı" bu yüzdendi.
                          key: ValueKey(intradayKey),
                          future: _intradayHistory(chartAssetsRenderable),
                          builder: (context, snapshot) {
                            final loading = snapshot.connectionState ==
                                ConnectionState.waiting;
                            // Tazeleme sırasında son başarılı seriye düş —
                            // 30 sn'lik tick her seferinde grafiği spinner'a
                            // çevirmesin.
                            // Tohum YALNIZCA aynı kümeye aitse kullanılır.
                            //
                            // **Neden (kullanıcı bildirimi 2026-09-22, üç
                            // turdur kapanmayan bulgu):** kapsam değişince
                            // (Ben → ortak → Birlikte) yeni future bir kare
                            // `waiting` oluyor ve `snapshot.data` null
                            // geliyordu. Dal o karede ÖNCEKİ defterin
                            // verisine düşüyor, `hasData` true çıkıyor ve
                            // Özet bir an BAŞKA birinin rakamlarını
                            // gösteriyordu.
                            //
                            // Damgayı "stale işaretle ama yine de kullan"
                            // diye kurmak yetmedi: Özet için tek doğru
                            // davranış o veriyi HİÇ kullanmamak. Grafik
                            // zaten `waiting` ile kendi ara karesini
                            // yönetiyor.
                            final tohum = _lastIntradayKey == intradayKey
                                ? _lastIntradayData
                                : null;
                            final data = snapshot.data ?? tohum;
                            // X ekseni ÇİZİLEN günün 00:00'ına kurulur —
                            // bugün olmak zorunda değil. Hafta sonu ve
                            // tatilde son seans (ör. Cuma) çizilir; eksen
                            // bugüne kurulsaydı o seansın noktaları bugünün
                            // slotlarına yayılıp düz çizgi üretirdi.
                            return _buildChartWithData(
                              data?.total ?? const {},
                              targetAssets,
                              filteredOwnerLotsRenderable,
                              chartAssetsRenderable,
                              data?.seansGunu ?? startDate,
                              endDate,
                              isIntraday,
                              pState,
                              activePartners,
                              waiting: loading,
                              // NOKTA SAYISINA bak, nesnenin varlığına
                              // değil (2026-09-22). `getPortfolioHistory…`
                              // ağ boşa çıktığında BOŞ ama null OLMAYAN bir
                              // breakdown döndürüyor; `data != null` onu
                              // "veri var" sayıyor, iskelet kapısı hiç
                              // açılmıyor ve Özet boş/eski rakamla
                              // çiziliyordu. Zoom dalı bunu baştan beri
                              // `historyMap.isNotEmpty` ile doğru yapıyor —
                              // iki dal ayrışmıştı.
                              hasData: (data?.total.isNotEmpty ?? false),
                              holdsSelectedType: holdsSelectedType,
                              // Future sonuçlandıysa beklenecek bir şey
                              // kalmadı: veri hâlâ yoksa spinner değil,
                              // "alınamadı" durumu gösterilmeli.
                              settled: snapshot.connectionState ==
                                  ConnectionState.done,
                              // Tür dökümü artık gün içinde de beslenir.
                              breakdown: data ??
                                  const PortfolioHistoryBreakdown.empty(),
                            );
                          },
                        );
                      }

                      final controller = _zoomController;
                      return ListenableBuilder(
                        listenable: controller ?? ValueNotifier<int>(0),
                        builder: (context, _) {
                          final historyMap = controller?.data ?? const {};
                          final waiting = controller?.loading ?? false;
                          final stale = controller?.stale ?? false;
                          // İlk istek sonuçlandı mı. Boş sonuç + sonuçlanmış
                          // istek = beklenecek veri yok.
                          final settled = controller?.settled ?? false;
                          // Tohum veri başka bir filtreye ait: toplamı bu
                          // filtreye ait dağılımla eşleşmez. Bayatken dökümü
                          // hiç gösterme — yanlış bir kırılım göstermektense
                          // boş bırakmak doğru.
                          final breakdown = stale
                              ? const PortfolioHistoryBreakdown.empty()
                              : (controller?.breakdown ??
                                  const PortfolioHistoryBreakdown.empty());
                          return _buildChartWithData(
                            historyMap,
                            targetAssets,
                            filteredOwnerLotsRenderable,
                            chartAssetsRenderable,
                            effectiveStart,
                            endDate,
                            isIntraday,
                            pState,
                            activePartners,
                            waiting: waiting,
                            holdsSelectedType: holdsSelectedType,
                            // Tohum veri de "gösterilebilir" sayılır: aynı
                            // varlıkların bir önceki penceresidir, spinner'dan
                            // çok daha iyi bir ara kare. `stale` ile soluk
                            // çizilir ve sayısal özetler gizlenir — kullanıcı
                            // eski rakamları yeni periyodun rakamı sanmasın.
                            // Spinner SADECE hiç veri yokken (ilk açılış).
                            hasData: historyMap.isNotEmpty,
                            stale: stale,
                            settled: settled,
                            breakdown: breakdown,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// TRY değeri için okunabilir kısa etiket (₺1,2M / ₺450K / ₺900) — baz
  /// birimde (Faz 3.2). Seri TRY kalır, yalnızca etiket çevrilir.
  String _fmtY(double val) => ref.read(bazParaProvider).compact(val);

  /// Seçili periyodun değişim özeti — grafiğin hemen üstünde.
  ///
  /// Değişim = son değer − ilk değer (ham fark). Grafikteki iki uçla birebir
  /// tutarlıdır: kullanıcı çizginin başladığı ve bittiği yeri görüp aradaki
  /// farkı burada okur.
  ///
  /// Uyarı satırı: gerçek modda dönem içinde net para girişi varsa ham fark
  /// getiriden yüksek çıkar (yatırılan para da farka dahildir). Rakamı
  /// değiştirmeyip altına net giriş tutarını yazıyoruz — kullanıcı farkın
  /// ne kadarının kendi parası olduğunu görebilsin.
  /// Üst kartın okuduğu dönem başı/sonu değeri — `null` ise çizilecek yok.
  ///
  /// Tür dökümü kartı da BUNU kullanır: iki kart aynı iki sayıdan beslenmezse
  /// satırların toplamı üst rakamı tutmaz (bkz. `_TypeBreakdownCard`).
  /// Grafiğin çizdiği serinin DÖNEM İÇİNDEKİ ilk ve son değeri.
  ///
  /// ## Neden pencere filtresi ŞART (kullanıcı bildirimi, 2026-09-23)
  /// Ekran görüntüsü: aynı dönem (16→23 Eyl), aynı kapsam, İKİ FARKLI
  /// rakam — Özet "piyasa +₺46.143", Grafik "piyasa ₺142.461".
  ///
  /// İkisi de kendi içinde tutarlıydı (bileşenler toplandığında "Şimdi"yi
  /// veriyordu) ama FARKLI bir "dönem başı" kullanıyorlardı. Ters
  /// mühendislikle ölçüldü:
  ///
  ///   Özet  tabanı = ₺2.354.650
  ///   Grafik tabanı = ₺2.258.332   (₺96.318 daha DÜŞÜK)
  ///
  /// Sebep: `PeriodSummaryService.uclar` seriyi `fromMs` ile KİRPAR
  /// (dönem penceresi), bu metot ise `spots.first`'ı olduğu gibi alıyordu.
  /// Seri çekme penceresi dönem penceresinden GENİŞ olabiliyor (günlük
  /// çözünürlükte kenar noktalar, `clipToPeriod` son VERİ noktasına
  /// çapalanır) ve o fazladan noktalar tabanı geriye çekiyordu.
  ///
  /// Artık iki yüzey AYNI pencereyi uyguluyor. `v <= 0` elemesi de
  /// eklendi — `uclar` ile birebir aynı kural (borsa açılmadan önceki boş
  /// slot dönem başı sanılırsa getiri sonsuza giderdi).
  ///
  /// [start]/[end] verilmezse eski davranış (tüm seri) korunur — çağıran
  /// pencereyi bilmiyorsa kırpma uydurmaktansa kırpmamak doğrudur.
  ///
  /// `firstX` tabanın ÖLÇÜLDÜĞÜ noktadır (eksen birimi: gün içinde dakika,
  /// diğer dönemlerde gün). Dönem kartı katkıyı o andan SONRASI için sayar
  /// — `PeriodSummaryService.piyasaEtkisi` ile aynı kural (2026-09-23).
  ({double first, double last, double firstX})? _periodEndpoints(
    List<TransactionSegment> segments, {
    DateTime? start,
  }) {
    if (segments.isEmpty) return null;
    // Y değerleri en kalın (aktif) segmentten okunur — passive segment
    // alım öncesi 0 çizgisidir, değişime karışmamalı.
    final primary =
        segments.reduce((a, b) => (a.thickness >= b.thickness) ? a : b);
    if (primary.spots.length < 2) return null;

    // **YALNIZCA ALT sınır uygulanır — üst sınır YOK.**
    //
    // İlk sürümde üst sınır da vardı (`end`) ve CANLI UÇ NOKTASINI
    // eliyordu: `end` build anında `DateTime.now()` ile alınıyor, canlı
    // uç ise segment kurulurken yine `DateTime.now()` ile — yani birkaç
    // milisaniye SONRA. `s.x > ustX` o tek nokta için doğru çıkıyor ve
    // yeşil nokta düşüyordu.
    //
    // Sonuç ekranda (kullanıcı bildirimi 2026-09-23, ekran görüntüsüyle):
    // grafik YÜKSELİŞLE bitiyor (₺2,57M → ₺2,58M) ama kart **−₺5.875**
    // diyordu — çünkü `last` yeşil nokta değil, ondan önceki DİP
    // noktasıydı.
    //
    // Üst sınıra zaten GEREK YOK: `_convertHistoryToSegments` gelecek
    // slotları hiç çizmiyor (`if (ts > nowMs) break`). Spot listesi
    // doğası gereği "şimdi"de biter. Alt sınır ise GEREKLİ: seri çekme
    // penceresi dönem penceresinden geniş olabiliyor ve fazladan noktalar
    // tabanı geriye çekiyordu (ölçüldü: ₺96.318 fark).
    //
    // Kullanıcının kuralı (2026-09-23): *"grafik başı ve sonundaki fark
    // neyse o olmalı."* Çizilen ilk ve son nokta — başka bir şey değil.
    final double? altX = (start != null)
        ? 0.0 // `start` X ekseninin sıfırıdır
        : null;

    double? first;
    double? last;
    double firstX = 0;
    for (final s in primary.spots) {
      if (altX != null && s.x < altX) continue;
      if (s.y <= 0) continue; // `uclar` ile AYNI kural
      if (first == null) {
        first = s.y;
        firstX = s.x;
      }
      last = s.y;
    }
    if (first == null || last == null) return null;
    return (first: first, last: last, firstX: firstX);
  }

  // ── Alım günü dot'ları: viewport'tan bağımsız, cache'lenir ──────────────
  // Hangi spot X'lerinin bir alım gününe denk geldiği yalnızca segment'lere,
  // varlık listesine ve grafik başlangıcına bağlıdır — zoom/pan ile
  // DEĞİŞMEZ. Eskiden bu her `buildData` çağrısında (yani her pinch/pan
  // karesinde) yeniden hesaplanıyordu: spot × varlık iç içe döngüsü, her
  // çift için `start.add(Duration(...))` ile DateTime üretimi. 365 nokta ve
  // 20 varlıkta kare başına 7.300 DateTime allocation demekti.
  Set<double>? _buyDayKeysCache;
  String? _buyDayKeysCacheKey;

}

// ── Tür bazlı kâr/zarar dökümü ───────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────

