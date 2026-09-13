import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, LinearProgressIndicator, Icons, TextStyle, Material, InkWell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../utils/chart_line_width.dart';
import '../utils/chart_axis.dart';
import '../utils/piyasa_kapali_etiketi.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/spot_lookup.dart';
import '../widgets/modern_tab_selector.dart';
import '../widgets/sandik_error_view.dart';
import '../services/analytics_service.dart';
import '../services/daily_summary.dart';
import '../services/history_service.dart';
import '../services/inflation_service.dart';
import '../services/leaderboard_service.dart';
import '../services/period_summary_service.dart';
import '../services/recap_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/period_summary_view.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/h_scroll_with_fade.dart';
import '../widgets/zoomable_chart.dart';
import '../models/grafik_tipi.dart';
import '../widgets/fullscreen_chart_route.dart';
import '../widgets/grafik_tipi_secici.dart';
import '../providers/preferences_provider.dart' show leaderboardOptInProvider;
import 'leaderboard_screen.dart';
import '../widgets/zoom_data_controller.dart';
import '../widgets/custom_loading_indicator.dart';

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
  Timer? _intradayTick;

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
  }

  @override
  void dispose() {
    _intradayTick?.cancel();
    _zoomController?.dispose();
    _viewport?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Grafik viewport'unu period/asset key değişince yenile.
  /// Aynı key + aynı minX/maxX → controller aynı kalır (kullanıcı zoom'unu
  /// kaybetmez). fullRange değiştiyse controller'ı reset et.
  ChartViewport _ensureViewport({
    required String key,
    required double fullMinX,
    required double fullMaxX,
  }) {
    if (_viewportKey != key || _viewport == null) {
      _viewport?.dispose();
      _viewport = ChartViewport(fullMinX: fullMinX, fullMaxX: fullMaxX);
      _viewportKey = key;
    } else if (_viewport!.fullMinX != fullMinX ||
        _viewport!.fullMaxX != fullMaxX) {
      _viewport!.updateFullRange(fullMinX, fullMaxX);
    }
    return _viewport!;
  }

  /// Chart assets/period/simülasyon değiştiğinde controller'ı yeniden kur.
  /// Aynı key gelirse mevcut controller korunur — kullanıcı zoom yaptığı
  /// yerden çalışmaya devam eder.
  void _ensureController({
    required List<Asset> chartAssets,
    required DateTime from,
    required DateTime to,
    required bool intraday,
  }) {
    final key = '${_view ?? "all"}|${_typeFilter?.name ?? "*"}'
        '|$_selectedPeriodIdx|$_simulate|${chartAssets.length}'
        '|${chartAssets.map((a) => a.id).join(",")}';
    if (_zoomKey == key && _zoomController != null) return;
    // Eski controller'ı HEMEN dispose etme. Yeni controller'ın verisi boş
    // başlar; dispose edersek "veri yok + loading" durumu oluşur ve ekran
    // tam sayfa spinner'a düşer — kullanıcı filtre değiştirdiğinde grafiğin
    // (ve altındaki filtre butonlarının) kaybolmasının sebebi buydu.
    // Bunun yerine eski veriyi tohum olarak yeni controller'a veriyoruz:
    // yeni seri gelene kadar soluk haliyle ekranda kalır.
    final previous = _zoomController;
    // Tohum, ÖNCEKİ pencereye ait zaman damgaları içerir. Yeni pencere daha
    // darsa (örn. 1Y → 1A) dışarıda kalan noktalar `startDate`'ten önceye
    // düşer ve grafikte NEGATİF X'e çizilirdi — eksen kayar, çizgi sola
    // taşardı. Bu yüzden tohumu yeni aralığa kırpıyoruz; kalan noktalar
    // doğru X'e oturur, yenisi gelene kadar geçerli bir önizleme olur.
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final rawSeed = previous?.data ?? const <int, double>{};
    final seed = <int, double>{
      for (final e in rawSeed.entries)
        if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
    };
    _zoomKey = key;
    _zoomController = ZoomDataController(
      assets: chartAssets,
      initialFrom: from,
      initialTo: to,
      simulate: _simulate,
      // İki noktadan az kalırsa çizilecek bir şey yok — boş geç ki
      // "veri var" sanılıp bozuk bir çizgi gösterilmesin.
      seedData: seed.length >= 2 ? seed : const {},
    );
    previous?.dispose();
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

  Future<PortfolioHistoryBreakdown> _intradayHistory(List<Asset> chartAssets) {
    final key = chartAssets.map((a) => a.id).join(',');
    if (_intradayKey == key && _intradayFuture != null) return _intradayFuture!;
    _intradayKey = key;
    _intradayFuture = HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown(chartAssets, 24)
      ..then((v) {
        if (mounted && v.total.isNotEmpty) _lastIntradayData = v;
      });
    return _intradayFuture!;
  }

  void _startIntradayTickIfNeeded() {
    _intradayTick?.cancel();
    if (_periods[_selectedPeriodIdx].intraday) {
      // 30 sn'de bir canlı fiyat çek — son noktanın Y değeri anlık portföy
      // toplamına oturur. refreshPrices bir sonraki portfolio state'ini
      // provider üzerinden yayar, ekran otomatik yeniden build olur.
      _intradayTick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        ref.read(portfolioProvider.notifier).refreshPrices();
        setState(() {
          // Memoize edilen intraday future'ı bilerek düşür — tick'in amacı
          // zaten seriyi tazelemek. Yeni future yüklenirken eski veri
          // `hasData` sayesinde ekranda kalır, spinner'a düşülmez.
          _intradayKey = null;
        });
      });
    }
  }

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

  /// Seriyi para giriş/çıkışından arındırır.
  ///
  /// Ham seri PORTFÖY DEĞERİNİ çizer: kullanıcı 170.000 TL'lik alım yaptığında
  /// çizgi o anda dikey bir duvar gibi zıplar. Bu zıplama bir kazanç değil,
  /// sadece hesaba giren paradır — ama grafikte kazançtan ayırt edilemez.
  /// Değişim kartı zaten net akıştan arındırılmış rakamı gösterdiği için
  /// (bkz. `_buildPeriodChangeCard`) grafik arındırılmazsa ikisi çelişir:
  /// kart "+907 TL" derken çizgi 170.000'lik sıçrama gösterir.
  ///
  /// Yöntem: her noktadan, O ANA KADAR biriken net akış çıkarılır. Böylece
  /// alım anındaki basamak düzleşir, geriye yalnızca fiyat hareketi kalır.
  /// Serinin başlangıç seviyesi korunur — kullanıcı "portföyüm neydi"
  /// bağlamını kaybetmesin.
  ///
  /// Silinen varlıklar hiç var olmamış sayılır: `deleteLog` atlanır (orijinal
  /// lot zaten DB'den silinmiştir).
  /// Bir varlık satırının nakit akışına katkısı (TRY).
  ///
  /// Alım para GİRİŞİ (+), satış ÇIKIŞI (−). Satışta maliyet değil ele geçen
  /// tutar kullanılır — kârla satılan pozisyonda ikisi farklıdır ve fark
  /// yanlışlıkla "piyasa etkisi" sayılırdı. Temettü ve `deleteLog` akışa
  /// girmez (silinen varlık hiç var olmamış sayılır).
  static double _flowOf(Asset a) {
    // `isActive` hem mezar taşını hem yumuşak silinmiş lot'u eler.
    if (!a.isActive) return 0;
    if (a.isBuy) return a.totalCostTRY;
    if (a.isSell) return -a.sellProceedsTRY;
    return 0;
  }

  List<TransactionSegment> _convertHistoryToSegments(
    Map<int, double> history,
    List<Asset> allAssets,
    DateTime startDate,
    DateTime endDate, {
    double? currentTotalOverride,
    bool simulate = false,
    bool intraday = false,
    int? piyasaKapaliBaslangicTs,
  }) {
    if (history.isEmpty || allAssets.isEmpty) return [];

    // Intraday (günlük): X ekseni = 00:00'dan itibaren dakika. Aktif segment
    // tek parça — bugünün başından şu ana kadar tüm noktalar aynı sarı çizgi
    // üstünde gider. Şimdi'den sonraki (gelecek) slotları göstermeyiz.
    if (intraday) {
      final sortedTs = history.keys.toList()..sort();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // "Şimdi" bu eksende VAR MI?
      //
      // Eskiden koşul "çizilen gün bugün mü" idi: piyasa kapalıyken seri
      // son seansa ait olduğu için canlı uç noktası eklenemiyordu.
      //
      // Kuyruk geldikten sonra bu artık doğru değil — seri son seanstan
      // BUGÜNE uzanıyor (`gunIciSagUc`), yani "şimdi" eksenin içinde.
      // Koşulu gün eşitliğine bağlı bırakmak, hafta sonunda son noktayı
      // canlı değere sabitlemeyi engelliyordu. Kullanıcı isteği
      // (2026-09-12): "şu an noktasında izlenen anın değeri gösterilmeli."
      //
      // Ölçüt artık takvim değil GEOMETRİ: "şimdi" eksenin sağ ucunda mı?
      final nowMinutesX = (nowMs - startDate.millisecondsSinceEpoch) / 60000.0;
      final simdiEksendeVar = nowMinutesX >= 0;
      final spots = <FlSpot>[];
      for (final ts in sortedTs) {
        if (ts > nowMs) break;
        final y = history[ts] ?? 0;
        // 0 dönen slotlar (borsa saatleri dışı ilk slotlar) atlanır; kullanıcı
        // ilk fiyat oluşan noktadan itibaren çizgiyi görür.
        if (y <= 0) continue;
        final minutes = (ts - startDate.millisecondsSinceEpoch) / 60000.0;
        spots.add(FlSpot(minutes, y));
      }
      // Şu an'ı canlı toplamla sabitle — grafiğin son noktası "şu andaki
      // portföy değeri" olur.
      //
      // Kapalı kuyruk kaldırıldıktan sonra (2026-09-12) bu koşul sadeleşti:
      // serinin ucu HER ZAMAN canlı toplama sabitlenir. Kullanıcı isteği:
      // "güncel değer ne ise o şekilde göstersin."
      if (simdiEksendeVar &&
          currentTotalOverride != null &&
          currentTotalOverride > 0) {
        if (spots.isNotEmpty && (nowMinutesX - spots.last.x).abs() < 5) {
          spots[spots.length - 1] = FlSpot(nowMinutesX, currentTotalOverride);
        } else {
          spots.add(FlSpot(nowMinutesX, currentTotalOverride));
        }
      } else if (simdiEksendeVar && spots.isNotEmpty) {
        // Canlı toplam kullanılmıyor (ya yok ya da piyasa kapalı): son
        // ÇİZİLEN değer "şimdi"ye taşınır. Kuyruk böylece DÜZ kalır.
        final sonY = spots.last.y;
        if ((nowMinutesX - spots.last.x).abs() >= 5) {
          spots.add(FlSpot(nowMinutesX, sonY));
        }
      }
      if (spots.length < 2) return [];

      // ── Piyasa kapalı kuyruğu ayrı segment ────────────────────────────
      //
      // Hafta sonu serisi Cuma kapanışını bugüne kadar taşıyor. O kuyruk
      // gerçek işlem DEĞİL; tek fiyatın yayılması. Tek segment olarak
      // çizilseydi sarı çizgi düz devam eder ve "fiyat oynamadı" diye
      // okunurdu — oysa borsa kapalıydı.
      //
      // Kuyruk nötr renk + kesikli desenle ayrılıyor (bkz.
      // `TransactionSegment.piyasaKapali`).
      if (piyasaKapaliBaslangicTs != null) {
        final sinirX =
            (piyasaKapaliBaslangicTs - startDate.millisecondsSinceEpoch) /
                60000.0;
        final seans = [
          for (final s in spots)
            if (s.x <= sinirX) s
        ];
        final kapali = [
          for (final s in spots)
            if (s.x >= sinirX) s
        ];

        // İki segment de çizilebiliyorsa böl. Aksi halde (kuyruk tek
        // noktaysa ya da seans boşsa) bölmek kopuk çizgi üretirdi —
        // tek parça bırakmak daha doğru.
        if (seans.length >= 2 && kapali.length >= 2) {
          return [
            TransactionSegment(
              spots: seans,
              lineColor: context.c.amberText,
              areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
              areaGradientEnd: Colors.transparent,
              thickness: 3.5,
            ),
            TransactionSegment(
              spots: kapali,
              // Nötr ton: kuyruk bir kazanç/kayıp anlatmıyor.
              lineColor: context.c.text36,
              // Alan doldurulmaz — dolgu "bu bölge de birikim" derdi.
              areaGradientStart: Colors.transparent,
              areaGradientEnd: Colors.transparent,
              thickness: 2.5,
              piyasaKapali: true,
            ),
          ];
        }
      }

      return [
        TransactionSegment(
          spots: spots,
          lineColor: context.c.amberText,
          areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
          areaGradientEnd: Colors.transparent,
          thickness: 3.5,
        ),
      ];
    }

    final segments = <TransactionSegment>[];
    // Simülasyon modu: tüm dönem tek aktif segment (sarı çizgi). Anchor
    // yok, passive segment yok; her nokta "o gün bugünkü net pozisyon
    // tutulsaydı" değeri.
    if (simulate) {
      final sortedTs = history.keys.toList()..sort();
      final spots = <FlSpot>[];
      for (final ts in sortedTs) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        // Saatlik veri için kesirli gün (24 → 1.0 gün). inDays saati keser
        // ve tüm saatler aynı X'e düşerdi → grafik zigzag olurdu.
        final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
        spots.add(FlSpot(x, history[ts]!));
      }
      // Son spot ŞU ANA taşınır (gerçek seride olduğu gibi — bkz. aşağıdaki
      // aktif segment dalı). Yalnızca Y güncellenirse "ŞİMDİ" çizgisi son
      // kovanın gün başına düşer ve bir önceki güne bitişik görünür.
      if (currentTotalOverride != null && currentTotalOverride > 0) {
        final nowX = endDate.difference(startDate).inMinutes / (60.0 * 24.0);
        if (spots.isNotEmpty) {
          final last = spots.last;
          final yeniX = nowX > last.x ? nowX : last.x;
          spots[spots.length - 1] = FlSpot(yeniX, currentTotalOverride);
        } else {
          spots.add(FlSpot(nowX, currentTotalOverride));
        }
      }
      if (spots.length < 2) return [];
      segments.add(TransactionSegment(
        spots: spots,
        lineColor: context.c.amberText,
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
      return segments;
    }

    // Aktif segment başlangıcı = ilk BUY lot tarihi. Sell/deleteLog dahil
    // edilirse edge case'lerde yanlış tarih seçilebilir; buy yoksa segment
    // zaten çizilmeyecek.
    final buyLots = allAssets.where((a) => a.isBuy && a.isActive).toList();
    if (buyLots.isEmpty) return [];
    final firstAssetDate =
        buyLots.map((a) => a.addedDate).reduce((a, b) => a.isBefore(b) ? a : b);

    // Normalize firstAssetDate to midnight for comparison
    final firstAssetMidnight =
        dayKey(firstAssetDate);

    final sortedTs = history.keys.toList()..sort();

    // Sadece aktif segment (ilk alımdan bugüne). TradingView tarzı: ilk
    // noktanın Y değeri o günün gerçek piyasa değeri (history[ts]). Alım
    // maliyeti tarihsel Y'yi bastırıp yapay atlama üretmez.
    final activeSpots = <FlSpot>[];

    for (final ts in sortedTs) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(firstAssetMidnight)) continue;
      final x = date.difference(startDate).inMinutes / (60.0 * 24.0);
      final y = history[ts]!;
      activeSpots.add(FlSpot(x, y));
    }

    // Son noktayı, kullanıcının şu an ekranda gördüğü toplam mal varlığı
    // değerine sabitle. X ekseni kesirli gün cinsinden (saatlik veride
    // 1 saat = 1/24 gün). Basit strateji: son spot'un Y değerini canlı
    // toplama override et — X'i değiştirme, böylece grafik zigzag/kırık
    // olmaz. Nokta yoksa endDate'in tam anına yeni bir spot ekle.
    if (currentTotalOverride != null && currentTotalOverride > 0) {
      final nowX = endDate.difference(startDate).inMinutes / (60.0 * 24.0);
      if (activeSpots.isNotEmpty) {
        final last = activeSpots.last;
        // Son nokta ŞU ANA taşınır — yalnızca Y'yi güncellemek yetmiyordu.
        //
        // Günlük seride son kova GÜN BAŞINA normalize ediliyor (12 Eylül
        // 00:00). X'e dokunulmayınca "ŞİMDİ" dikey çizgisi o gece yarısına
        // düşüyor ve 11 Eylül'e bitişik duruyordu: kullanıcı tüm
        // dönemlerde "şu an" noktasında 11 Eylül görüyordu
        // (bildirim 2026-09-12).
        //
        // Sıçrama riski yok: X yalnızca İLERİ taşınıyor ve Y aynı kalıyor,
        // yani son segment gün başından şu ana yatay uzar.
        final yeniX = nowX > last.x ? nowX : last.x;
        activeSpots[activeSpots.length - 1] =
            FlSpot(yeniX, currentTotalOverride);
      } else {
        activeSpots.add(FlSpot(nowX, currentTotalOverride));
      }
    }

    if (activeSpots.isNotEmpty) {
      segments.add(TransactionSegment(
        spots: activeSpots,
        lineColor: context.c.amberText,
        areaGradientStart: context.c.amberFill.withValues(alpha: 0.12),
        areaGradientEnd: Colors.transparent,
        thickness: 3.5,
      ));
    }

    return segments;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
      style: GoogleFonts.dmSans(
          color: context.c.text90, decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    if (widget.showBackButton) ...[
                      // 44pt dokunma hedefi (HIG minimumu).
                      SizedBox(
                        width: 36,
                        height: 44,
                        child: CupertinoButton(
                          minimumSize: Size.zero,
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
                        'Performans',
                        style: context.t.headlineLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.c.text90),
                      ),
                    ),
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

                      // Filtre: grafik çizimi için yalnızca fiyat serisi
                      // alınabilir/ya da canlı fiyatı olan varlıkları geçir.
                      // Aksi halde HistoryService tüm seriyi boşaltabiliyor
                      // (tek price-less varlık tüm günü götürebiliyordu).
                      bool isRenderable(Asset a) {
                        if (a.quantity == 0) return false;
                        if (a.currentPrice > 0) return true;
                        switch (a.type) {
                          case AssetType.altin:
                            return true;
                          case AssetType.hisse:
                          case AssetType.emtia:
                            return a.ticker.trim().isNotEmpty;
                          case AssetType.doviz:
                            return a.ticker.trim().isNotEmpty;
                          case AssetType.fon:
                            return a.ticker.trim().isNotEmpty &&
                                !a.isManualPrice;
                          default:
                            return false;
                        }
                      }

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
                        return FutureBuilder<PortfolioHistoryBreakdown>(
                          future: _intradayHistory(chartAssetsRenderable),
                          builder: (context, snapshot) {
                            final loading = snapshot.connectionState ==
                                ConnectionState.waiting;
                            // Tazeleme sırasında son başarılı seriye düş —
                            // 30 sn'lik tick her seferinde grafiği spinner'a
                            // çevirmesin.
                            final data = snapshot.data ?? _lastIntradayData;
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
                              hasData: data != null,
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

  /// Chart + wrap widget'ları — hem intraday hem controller-based data için.
  ///
  /// [waiting] yeni veri yükleniyor (üstte ince progress bar).
  /// [hasData] çizilebilir bir seri var mı. False iken SADECE grafik alanı
  /// spinner'a döner; ortak sekmesi, tip çipleri ve periyot toggle'ı ekranda
  /// ve tıklanabilir kalır. Bu metod her durumda çağrılmalıdır — çağıranın
  /// erken return etmesi filtreleri de siler.
  /// [stale] eldeki seri bir ÖNCEKİ periyoda/filtreye ait mi. Grafik soluk
  /// çizilir ve sayısal özet kartı gizlenir: eski rakamlar yeni periyodun
  /// rakamı sanılmasın. Spinner yerine soluk grafik göstermek periyot
  /// değişiminde çok daha akıcı hissettiriyor.
  /// [settled] veri isteği sonuçlandı mı (başarı ya da hata farketmez).
  /// `!hasData && settled` → beklenecek bir şey yok; spinner yerine
  /// "alınamadı" durumu çizilir.
  /// Bar tipi: her noktayı tabandan yukarı uzanan dikey çubuk yapar.
  ///
  /// Çubuk yüksekliği görünür Y tabanından (`tabanY`) noktanın değerine
  /// kadar. Mutlak sıfırdan başlamak yanlış olurdu: portföy 2,5 milyon
  /// TL'de gezinirken çubukların tamamı ekranı doldurur ve aralarındaki
  /// fark görünmez olurdu.
  ///
  /// Yoğun serilerde çubuklar birbirine girer; nokta sayısı eşiği aşınca
  /// eşit aralıklarla seyreltilir. Seyreltme ilk ve son noktayı HER ZAMAN
  /// korur — dönem uçları grafiğin okunmasında çapa.
  List<LineChartBarData> _cubukSegmentleri(
    BuildContext context,
    List<TransactionSegment> segments,
    double tabanY,
  ) {
    const maksCubuk = 60;
    final out = <LineChartBarData>[];

    for (final seg in segments) {
      if (seg.spots.isEmpty) continue;

      final adim = (seg.spots.length / maksCubuk).ceil().clamp(1, 1 << 30);
      final secilen = <FlSpot>[];
      for (var i = 0; i < seg.spots.length; i += adim) {
        secilen.add(seg.spots[i]);
      }
      // Son nokta ("şimdi") seyreltmeye kurban gitmemeli.
      if (secilen.isEmpty || secilen.last.x != seg.spots.last.x) {
        secilen.add(seg.spots.last);
      }

      for (final s in secilen) {
        out.add(LineChartBarData(
          spots: [FlSpot(s.x, tabanY), FlSpot(s.x, s.y)],
          isCurved: false,
          color: seg.piyasaKapali ? context.c.text36 : seg.lineColor,
          barWidth: 2.0,
          dashArray: seg.piyasaKapali ? const [3, 3] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ));
      }
    }
    return out;
  }

  /// Baseline tipi için dikey gradyan: taban ÜSTÜ kazanç, ALTI kayıp.
  ///
  /// `fl_chart` bir çizgiyi iki renge bölemiyor. Çözüm, çizginin kapladığı
  /// Y aralığında tabanın nereye düştüğünü oran olarak hesaplayıp
  /// gradyan stop'unu tam oraya koymak. İki stop AYNI noktada olduğu için
  /// geçiş yumuşamaz — keskin bir sınır oluşur.
  ///
  /// Taban aralığın dışındaysa (çizgi tamamen tabanın üstünde ya da
  /// altında) tek renk döner; yoksa `stops` sıralaması bozulur ve
  /// `fl_chart` assert atar.
  LinearGradient _baselineGradient(
    BuildContext context,
    List<FlSpot> spots,
    double tabanY,
  ) {
    final kazanc = context.c.gain;
    final kayip = context.c.loss;

    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    // Düz çizgi ya da bozuk aralık: bölmeye gerek yok.
    if (!minY.isFinite || !maxY.isFinite || (maxY - minY).abs() < 1e-9) {
      final renk = spots.isNotEmpty && spots.last.y >= tabanY ? kazanc : kayip;
      return LinearGradient(colors: [renk, renk]);
    }

    if (tabanY >= maxY) {
      return LinearGradient(colors: [kayip, kayip]);
    }
    if (tabanY <= minY) {
      return LinearGradient(colors: [kazanc, kazanc]);
    }

    // Gradyan yukarıdan aşağı akar: 0.0 = maxY, 1.0 = minY.
    final oran = ((maxY - tabanY) / (maxY - minY)).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [kazanc, kazanc, kayip, kayip],
      stops: [0.0, oran, oran, 1.0],
    );
  }

  Widget _buildChartWithData(
    Map<int, double> historyMap,
    List<Asset> targetAssets,
    List<List<Asset>> ownerLots,
    List<Asset> chartAssets,
    DateTime startDate,
    DateTime endDate,
    bool isIntraday,
    PortfolioState pState,
    List<AppUser> activePartners, {
    required bool waiting,
    required bool hasData,

    /// Seçili türde NET pozisyon var mı (satılıp bitmişler ve temettü gibi
    /// miktarsız satırlar hariç). Boş durumun "hiç yok" ile "var ama
    /// çizilemiyor" ayrımı buna dayanır.
    required bool holdsSelectedType,
    bool stale = false,
    bool settled = false,

    /// `historyMap` ile AYNI istekten gelen tür/pozisyon dağılımı — tür dökümü
    /// kartını besler. Her iki veri yolu da doldurur: diğer periyotlar
    /// `getPortfolioHistoryBreakdownAtResolution`, gün içi ise
    /// `getPortfolioHistoryHourlyBreakdown`.
    PortfolioHistoryBreakdown breakdown =
        const PortfolioHistoryBreakdown.empty(),
  }) {
    // Ana ekranla birebir aynı TRY hesabı: targetAssets grafik için ham buy
    // lot'ları içeriyor (satılan miktarı geçmişte düşürmemek için). Ancak
    // GÜNCEL toplam net pozisyondan gelmeli — aggregate ile sell'leri düşüp
    // asDisplayAsset.totalValue'yu topla.
    // Sahipler ayrı aggregate edilir — havuzlanırsa aynı hisseye sahip iki
    // ortak tek pozisyona düşer ve toplam, tekil sekmelerin toplamını tutmaz.
    final currentTotal = ownerScopedTotalValue(ownerLots, toTRY: pState.toTRY);

    // TradingView "auto range" davranışı: kullanıcı seçilen periyot içinde
    // hiç varlığı yoksa (örn. 1Y seçtiği ama 3 gün önce başladı), chart
    // ilk alım tarihinden itibaren çizilir. Böylece kısa geçmişli portföyde
    // grafik boş değil, sıkışık şekilde ilk alıştan bugüne yayılır.
    //
    // Simülasyonda UYGULANMAZ — yukarıdaki fetch tarafıyla aynı gerekçe:
    // sabit pozisyon senaryosunda ilk alım tarihi aralığı daraltmamalı.
    // İki taraf aynı koşulu kullanmalı, aksi halde fetch penceresi ile
    // çizim penceresi ayrışır ve X ekseni kayar.
    DateTime effectiveStart = startDate;
    if (!isIntraday && !_simulate) {
      final buys = chartAssets.where((a) => a.isBuy);
      if (buys.isNotEmpty) {
        final firstBuy = buys
            .map((a) => a.addedDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        // Sadece ilk alım, seçili periyot başlangıcından SONRAYSA
        // startDate'i geç kaydır. Aksi halde tam periyodu göster.
        if (firstBuy.isAfter(startDate)) {
          effectiveStart =
              dayKey(firstBuy);
        }
      }
    }

    // Grafik HAM portföy değerini çizer — arındırma YAPILMAZ.
    //
    // Bir ara seri para giriş/çıkışından arındırılıyordu (alım anındaki dikey
    // sıçrama düzleşsin diye). Kullanıcı kararı: sıçramalar KALSIN. Gerekçesi
    // sağlam — çizgi "portföyümde şu an ne kadar var" sorusunun cevabıdır ve
    // alım/satış anındaki basamak gerçek bir olayı temsil eder. Ayrıca o
    // noktalarda zaten lot dot'u + tooltip var ("Alım +₺X" / "Satış −₺Y"),
    // yani sıçramanın sebebi grafiğin üstünde okunabiliyor.
    //
    // Yanıltıcı olan grafik değil, DEĞİŞİM KARTIYDI: o hâlâ net akıştan
    // arındırılmış rakamı gösterir (bkz. `_buildPeriodChangeCard`), böylece
    // "portföyüm ne kazandı?" sorusu doğru cevaplanır.
    // Gün içi X ekseni ÇİZİLEN GÜNÜN 00:00'ından başlar — bugünün değil.
    //
    // Piyasa kapalıyken seri son seanstan (Cuma) bugüne uzanıyor
    // (`gunIciSagUc`). Eksen bugünün 00:00'ına kurulursa Cuma noktaları
    // NEGATİF X'e düşer ve `fl_chart` onları çizim alanının dışında bırakır:
    // grafik boş ya da yarım görünür. Kullanıcı bildirimi 2026-09-12:
    // "hâlâ grafiklerde 12 Eylül datalarını göremiyorum."
    //
    // `seansGunu` breakdown'dan geliyor ve tam ekran grafiği (satır ~699)
    // bunu zaten kullanıyordu; ana grafik kullanmıyordu — iki yüzey
    // ayrışmıştı.
    final cizimBaslangici =
        isIntraday ? (breakdown.seansGunu ?? effectiveStart) : effectiveStart;

    final segments = _convertHistoryToSegments(
        historyMap, chartAssets, cizimBaslangici, endDate,
        currentTotalOverride: currentTotal,
        simulate: _simulate,
        intraday: isIntraday,
        // Hafta sonu kuyruğu: kapanıştan sonrası gri + kesikli çizilir.
        piyasaKapaliBaslangicTs: breakdown.piyasaKapaliBaslangicTs);

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        if (activePartners.isNotEmpty) ...[
          ModernTabSelector(
            partners: activePartners,
            selectedId: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 12),
        ],
        HScrollWithFade(
          child: Row(
            children: [
              _typeChip(null, 'Tümü'),
              for (final t in RemoteConfigService.instance.visibleAssetTypes)
                _typeChip(t, t.label),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Sekme anahtarı dönem seçicinin ÜSTÜNDE: dönem ikisi için de
        // geçerli, sekme ise hangi sunumu gördüğünü belirler. Tersi sırada
        // dönem seçici sekmeye aitmiş gibi okunuyordu.
        _buildSurfaceToggle(),
        const SizedBox(height: 12),
        _buildPeriodToggle(),
        // Simülasyon anahtarı yalnızca GRAFİK sekmesinde anlamlı: Özet
        // gerçek nakit akışını ayırmak için var ve simülasyon tam olarak o
        // akışı yok sayıyor. İkisini birleştirmek "katkın ₺0" yazan bir
        // köprü üretirdi.
        if (!isIntraday && !_ozetSekmesi) ...[
          const SizedBox(height: 12),
          _buildModeToggle(),
        ],
        const SizedBox(height: 24),
        // ── ÖZET sekmesi ──────────────────────────────────────────────────
        //
        // Erken `return` YOK: filtre denetimleri (ortak sekmeleri, tür
        // çipleri, dönem seçici) ağaçta KALMALI, yoksa kullanıcı Özet'e
        // geçtiğinde dönemini değiştiremez hale gelir. Aynı gerekçe
        // `_buildChartWithData`'nın koşulsuz çağrılmasının da sebebi.
        if (_ozetSekmesi) ...[
          _buildOzetSekmesi(
            breakdown: breakdown,
            targetAssets: targetAssets,
            intraday: isIntraday,
            seansBaslangici: cizimBaslangici,
          ),
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ] else ...[
          // "Yeni çözünürlükte veri yükleniyor" göstergesi — zoom sırasında
          // eski veri ekranda kalır, üstte ince bir bar akıcı hisi verir.
          if (waiting)
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: context.c.amberFill,
              ),
            ),
          Row(
            // `spaceBetween` + `Spacer` YOK: bu satır yatay kaydırılabilir
            // bir bağlamda çiziliyor ve `Spacer` sonsuz genişlik isteyip
            // RenderFlex'i 98.674px taşırıyordu (ölçüldü — boş durum metni
            // hiç render edilmiyordu).
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Grafik tipi seçici — gün içi sekmesinde de geçerli.
              const GrafikTipiSecici(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ref.watch(leaderboardOptInProvider) &&
                      activePartners.isNotEmpty) ...[
                    _LeaderboardChip(
                      onTap: () => Navigator.push(
                        context,
                        adaptiveRoute(
                            builder: (_) => const LeaderboardScreen()),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _PortfolioFullscreenChip(
                    onTap: () {
                      FullscreenChartRoute.open(
                        context,
                        title: 'Portföy Performans',
                        builder: (_) => PortfolioPerformanceScreen(
                          initialView: _view,
                          initialTypeFilter: _typeFilter,
                          // Landscape'te grafik hemen görünsün diye header'ları
                          // aşağı kaydır. Yukarı swipe ile tab/filtre/period gelir.
                          initialScrollOffset: 220,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Akıcı geçiş tasarımı ────────────────────────────────────────
          // `LineChart` bir ImplicitlyAnimatedWidget: yeni `LineChartData`
          // verildiğinde eski veriden yenisine kendi lerp'liyor (150ms).
          // Ama bu ancak widget AĞAÇTA KALIRSA çalışır. Grafiği spinner ile
          // değiştirmek (veya sarmalayıcı yapıyı değiştirmek) State'i yok
          // eder, tween sıfırlanır ve geçiş "0'dan yeniden çizim" gibi
          // görünür. Bu yüzden:
          //   • Grafik konteyneri HER ZAMAN aynı konumda kalır.
          //   • Özet kartı bayatken gizlenmez — yerini korusun diye
          //     opaklığı düşer (layout zıplaması da olmaz).
          //   • Spinner yalnızca hiç veri yokken (ilk açılış) görünür.
          AnimatedOpacity(
            opacity: stale ? 0.45 : 1.0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: _buildPeriodChangeCard(
              segments,
              // Segmentlerle AYNI başlangıç: X ekseni bu tarihe göre
              // yorumlanıyor, ayrışırsa kart yanlış günü anlatır.
              cizimBaslangici,
              endDate,
              targetAssets,
              intraday: isIntraday,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          // Grafik alanı üç hâlden birinde: boş durum, yükleme, grafik.
          //
          // "Boş durum" ayrımı ŞART: seçili tür portföyde yoksa (ya da türün
          // fiyat geçmişi hiç izlenmiyorsa) `HistoryService` boş varlık
          // listesine boş seri döndürür — veri ASLA gelmez. Eskiden bu da
          // `!hasData` sayılıp spinner çiziliyordu ve sonsuza kadar dönüyordu;
          // kullanıcı yüklenmeyi bekliyor sanıyordu.
          //
          // Yükseklik `minHeight` ile kurulur, SABİT değil: grafik alanı kadar
          // yer tutsun ama büyük metin ölçeğinde (AX5) içerik taşmasın.
          if (_chartEmptyState(holdsSelectedType, chartAssets)
              case final empty?)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: empty,
            )
          else if (!hasData && settled)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: _ChartPlaceholder(
                icon: Icons.cloud_off_rounded,
                title: 'Grafik verisi alınamadı',
                message: 'Fiyat geçmişi şu an getirilemedi. '
                    'Bağlantını kontrol edip tekrar deneyebilirsin.',
                onRetry: _retryChartData,
              ),
            )
          else if (!hasData)
            const SizedBox(height: 300, child: CustomLoadingView())
          else
            AnimatedOpacity(
              opacity: stale ? 0.45 : 1.0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              // Grafik tipi değişince YENİDEN çizilmeli. Notifier widget
              // ağacının dışında yaşıyor (oturum durumu), bu yüzden
              // dinleyici burada kuruluyor — `setState` yerine bu, yalnızca
              // grafiği yeniler, tüm sayfayı değil.
              child: ValueListenableBuilder<GrafikTipi>(
                valueListenable: grafikTipiNotifier,
                builder: (context, _, __) => _buildChartContainer(
                    segments, cizimBaslangici, endDate, chartAssets,
                    intraday: isIntraday, allTargetAssets: targetAssets),
              ),
            ),
          // Gün içi verisi HİÇ alınamayan türler için açık uyarı.
          //
          // Bu türler grafikte son bilinen fiyatla sabit çizilir; uyarı
          // olmadan kullanıcı düz çizgiyi "piyasa durgun" diye okur ve
          // uygulamanın bozuk olup olmadığını anlayamaz ("altın değeri mi
          // alınamıyor acaba" — 2026-09-07). Fon/mevduat gibi gün içi fiyatı
          // ZATEN olmayan türler bu listeye girmez, yoksa uyarı kalıcı
          // gürültüye dönerdi.
          if (isIntraday && breakdown.gunIciVerisiYokTurler.isNotEmpty) ...[
            const SizedBox(height: SandikSpace.sm),
            _GunIciVeriYokNotu(turler: breakdown.gunIciVerisiYokTurler),
          ],
          const SizedBox(height: 24),
          // Tür bazlı kâr/zarar dökümü — seçili dönem ve sekmeye göre.
          //
          // Üst kartla AYNI iki sayıdan (`_periodEndpoints`) ve AYNI istekten
          // gelen dağılımdan beslenir; satırların toplamı bu yüzden üst rakamı
          // tutar. Endpoint yoksa üst kart da çizilmiyordur — döküm de çıkmaz.
          if (_periodEndpoints(segments) case final ep?)
            _TypeBreakdownCard(
              breakdown: breakdown,
              totalFirst: ep.first,
              totalLast: ep.last,
              ownerLots: ownerLots,
              start: cizimBaslangici,
              end: endDate,
              simulate: _simulate,
            ),
          // NOT: Portföy sinyal paneli KALDIRILDI (kullanıcı kararı,
          // 2026-08-31). Teknik sinyaller yalnızca varlık detay/performans
          // ekranında gösterilir. Bu panel senkron çalıştığı için gerçek fiyat
          // geçmişi çekemiyordu; uydurma seriye düşmesi engellendikten sonra
          // (bkz. `analyze(..., allowSimulation)`) zaten kalıcı olarak
          // "sinyal yok" gösteriyordu — yer kaplayan ölü bir yüzeydi.
          const SizedBox(height: 12),
          const DisclaimerWidget(),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// Grafik alanında spinner yerine gösterilecek boş durum — yoksa null.
  ///
  /// Üçü de "veri hiç gelmeyecek" hâli ve üçü de eskiden sonsuz spinner
  /// üretiyordu:
  ///   • portföy tamamen boş (yeni kullanıcı, "Tümü" seçili),
  ///   • seçili türde varlık yok (kullanıcının şikâyet ettiği durum),
  ///   • varlık var ama türün fiyat geçmişi izlenmiyor — mevduat, "Diğer"
  ///     ve elle fiyatlanan fonlar `isRenderable` elemesine takılır, geriye
  ///     çizilecek tek bir varlık kalmaz.
  ///
  /// [holdsSelectedType] NET pozisyona bakar, ham satıra DEĞİL. Ayrım bir
  /// kez ham satırlara dayandırılmıştı ve yanlış mesaj veriyordu: temettü
  /// satırı (miktarsız) ya da satılıp bitmiş bir pozisyon türde "varlık
  /// var" saydırıp, çizilecek bir şey olmadığı için ekranı "grafik verisi
  /// yok"a düşürüyordu — oysa kullanıcının o türden hiçbir şeyi yoktu.
  /// [chartAssets] ise çizilebilir varlıklar; boş olması şart, aksi halde
  /// grafik zaten çizilir.
  Widget? _chartEmptyState(bool holdsSelectedType, List<Asset> chartAssets) {
    if (chartAssets.isNotEmpty) return null;
    final type = _typeFilter;

    if (!holdsSelectedType) {
      return _ChartPlaceholder(
        icon: type?.icon ?? Icons.inbox_rounded,
        iconColor: type?.color,
        title: type == null
            ? 'Henüz varlığın yok'
            : 'Portföyünde ${type.label.toLowerCase()} yok',
        message: type == null
            ? 'Varlık ekledikçe portföyünün performansı burada grafiğe '
                'dönüşecek.'
            : 'Bu türden bir varlık eklediğinde performansı burada '
                'görünecek. Başka bir tür seçebilirsin.',
      );
    }

    // Varlık var ama hiçbirinin fiyat serisi yok (mevduat, "Diğer", elle
    // fiyatlanan fon). Değerleri portföy toplamına dahildir — kullanıcı
    // "varlığım kayboldu" diye okumasın diye bunu açıkça söylüyoruz.
    return _ChartPlaceholder(
      icon: Icons.timeline_rounded,
      iconColor: type?.color,
      title: 'Grafik verisi yok',
      message: type == null
          ? 'Portföyündeki varlıkların fiyat geçmişi izlenmiyor; değerleri '
              'toplamda görünür ama zaman grafiği çizilemiyor.'
          : '${type.label} için fiyat geçmişi izlenmiyor. Değeri portföy '
              'toplamına dahil, ama zaman grafiği çizilemiyor.',
    );
  }

  /// "Veri alınamadı" durumundaki tekrar dene. Her iki veri yolunu da
  /// sıfırlar: gün içi memoize edilmiş future'ı ve zoom controller'ı.
  void _retryChartData() {
    setState(() {
      _intradayKey = null;
      _intradayFuture = null;
    });
    _zoomController?.reload();
  }

  Widget _typeChip(AssetType? type, String label) {
    final selected = _typeFilter == type;
    final color = type?.color ?? context.c.amberText;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: () => setState(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: SandikMotion.stateOf(context),
          curve: SandikMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.15) : context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: selected ? color : context.c.overlay,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: context.t.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? color : context.c.text58,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_periods.length, (i) {
          final isSelected = _selectedPeriodIdx == i;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() => _selectedPeriodIdx = i);
                _startIntradayTickIfNeeded();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    _periods[i].label,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSelected ? context.c.amberText : context.c.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Özet sekmesinin gövdesi.
  ///
  /// Hesap `PeriodSummaryService.compute`'ta — burada yalnızca girdiler
  /// toplanır. Servis saf olduğu için `now` ve `breakdown` dışarıdan
  /// veriliyor ve testler ağsız koşabiliyor.
  ///
  /// **GÜNLÜK dönemde `DailySummary.from()` DELEGE edilir.** Widget, Live
  /// Activity, üst kart ve bu sekme aynı rakamı göstermek zorunda
  /// (bkz. `daily_summary.dart` "Değişmezler"); ikinci bir günlük hesap
  /// kurmak o değişmezi sessizce kırardı.
  Widget _buildOzetSekmesi({
    required PortfolioHistoryBreakdown breakdown,
    required List<Asset> targetAssets,
    required bool intraday,
    required DateTime seansBaslangici,
  }) {
    final period = SummaryPeriod.fromIndex(_selectedPeriodIdx);
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final now = DateTime.now();

    // GÜNLÜK'te ortak katmanın özeti hazırlanır. `seansGunu` breakdown'dan
    // gelir: piyasa kapalıyken çizilen seans BUGÜN DEĞİLDİR ve pencere de
    // o güne kurulmalı (hafta sonu → Cuma).
    DailySummary? gunluk;
    if (intraday && pState != null) {
      gunluk = DailySummary.from(
        state: pState,
        series: breakdown.total,
        now: now,
        seansGunu: breakdown.seansGunu ?? seansBaslangici,
      );
    }

    final summary = PeriodSummaryService.compute(
      period: period,
      assets: targetAssets,
      breakdown: breakdown,
      now: now,
      gunlukOzet: gunluk,
      // `_positionLabel` ham `positionKey`'i insan-okunur hale getirir;
      // yoksa ekranda "altin|sub:çeyrek|TRY" görünürdü.
      etiket: (k) =>
          _positionLabel(k, breakdown.positionType[k] ?? AssetType.diger),
    );

    // Tür dağılımı canlı portföyden — karakter etiketi için.
    final valueByType = <AssetType, double>{};
    if (pState != null) {
      for (final a in targetAssets.where((a) => a.isBuy && a.isActive)) {
        valueByType[a.type] =
            (valueByType[a.type] ?? 0) + pState.toTRY(a.totalValue, a.currency);
      }
    }

    // En sabırlı varlık — 1Y bloğu.
    Asset? enEski;
    for (final a in targetAssets.where((a) => a.isBuy && a.isActive)) {
      if (enEski == null || a.addedDate.isBefore(enEski.addedDate)) enEski = a;
    }

    return _OzetYanVeri(
      period: period,
      summary: summary,
      assets: targetAssets,
      // Karakter/sabır yalnızca 1Y'de gösterilir; başka dönemde
      // hesaplanmış olsa da view onları çizmez.
      karakter: period == SummaryPeriod.birYil
          ? RecapService.characterFor(valueByType)
          : null,
      enSabirli: period == SummaryPeriod.birYil && enEski != null
          ? RecapAsset(enEski.name, 0)
          : null,
      enSabirliGun: period == SummaryPeriod.birYil && enEski != null
          ? now.difference(enEski.addedDate).inDays
          : null,
    );
  }

  /// Grafik | Özet yüzey anahtarı.
  ///
  /// `_buildModeToggle` ile aynı kabuk (44px, surface1, SandikRadius.md) —
  /// iki anahtar yan yana durabildiği için aynı görünmek zorundalar, yoksa
  /// kullanıcı ikisini farklı sınıf denetimler sanır.
  ///
  /// Dönem seçici DEĞİŞMEZ: `_selectedPeriodIdx` iki sekmede paylaşılıyor.
  Widget _buildSurfaceToggle() {
    const options = [
      (label: 'Grafik', ozet: false),
      (label: 'Özet', ozet: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = _ozetSekmesi == o.ozet;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () {
                if (_ozetSekmesi == o.ozet) return;
                setState(() => _ozetSekmesi = o.ozet);
                if (o.ozet) {
                  AnalyticsService.instance.logPeriodSummaryViewed(
                    period: SummaryPeriod.fromIndex(_selectedPeriodIdx).name,
                  );
                }
              },
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: selected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Center(
                  child: Text(
                    o.label,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? context.c.amberText : context.c.text36,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Gerçek geçmiş / Simülasyon toggle'ı.
  /// - Gerçek: her günün o günkü net miktarına göre değer (alım/satışlar
  ///   tarihlerine göre).
  /// - Simülasyon: bugünkü net portföy tüm dönem boyunca elde tutulmuş gibi.
  Widget _buildModeToggle() {
    const options = [
      (label: 'Gerçek', sim: false),
      (label: 'Simülasyon', sim: true),
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md)),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = _simulate == o.sim;
          return Expanded(
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _simulate = o.sim),
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: selected ? context.c.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      o.label,
                      style: context.t.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color:
                            selected ? context.c.amberText : context.c.text36,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showModeInfoSheet(forSim: o.sim),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: selected
                              ? context.c.amberFill.withValues(alpha: 0.85)
                              : context.c.text36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showModeInfoSheet({required bool forSim}) {
    final title = forSim ? 'Simülasyon Modu' : 'Gerçek Mod';
    final body = forSim
        ? 'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş '
            'olsaydın grafik nasıl görünürdü — geçmişteki alım/satış '
            'kararlarını yok sayar, sadece güncel pozisyonun fiyat '
            'değişimini gösterir.'
        : 'Her günün grafikteki değeri, o gün elinde olan net miktara '
            'göre hesaplanır. Bir noktaya dokununca o günkü portföy değeri '
            've varsa alım / satış tutarları görünür — böylece grafiğin '
            'neden yükseldiğini veya düştüğünü net görebilirsin.';

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => DefaultTextStyle(
        style: GoogleFonts.dmSans(
            color: context.c.text90, decoration: TextDecoration.none),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.c.overlay,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: context.c.amberText),
                    const SizedBox(width: 8),
                    Text(title,
                        style: context.t.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.c.text90,
                            decoration: TextDecoration.none)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: context.t.bodyMedium?.copyWith(
                      color: context.c.text58,
                      height: 1.5,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// TRY değeri için okunabilir kısa etiket (₺1,2M / ₺450K / ₺900)
  String _fmtY(double val) => fmtTRYCompact(val);

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
  ({double first, double last})? _periodEndpoints(
      List<TransactionSegment> segments) {
    if (segments.isEmpty) return null;
    // Y değerleri en kalın (aktif) segmentten okunur — passive segment
    // alım öncesi 0 çizgisidir, değişime karışmamalı.
    final primary =
        segments.reduce((a, b) => (a.thickness >= b.thickness) ? a : b);
    if (primary.spots.length < 2) return null;
    return (first: primary.spots.first.y, last: primary.spots.last.y);
  }

  Widget _buildPeriodChangeCard(
    List<TransactionSegment> segments,
    DateTime start,
    DateTime end,
    List<Asset> targetAssets, {
    required bool intraday,
  }) {
    final ep = _periodEndpoints(segments);
    if (ep == null) return const SizedBox.shrink();

    final firstY = ep.first;
    final lastY = ep.last;

    // Grafik HAM portföy değerini çizer (sıçramalar bilinçli — bkz. çizim
    // tarafındaki not), dolayısıyla uçtan uca fark yatırılan parayı da
    // içerir. Kart bunu ham göstermez.
    final grossChange = lastY - firstY;

    // ── Dönem içi net akış ───────────────────────────────────────────────
    //
    // Silinen varlıklar HİÇ VAR OLMAMIŞ sayılır: `deleteLog` atlanır ve
    // orijinal lot zaten DB'den silinmiştir (bkz. `deleteAsset`).
    double netInflow = 0;
    if (!_simulate) {
      final startMs =
          dayKey(start).millisecondsSinceEpoch;
      final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
          .millisecondsSinceEpoch;
      for (final a in targetAssets) {
        final ms = a.addedDate.millisecondsSinceEpoch;
        if (ms < startMs || ms > endMs) continue;
        netInflow += _flowOf(a);
      }
    }

    // ── Ana rakam: BİRİKİM değişimi — (son − ilk) / ilk ──────────────────
    //
    // Kart, grafiğin ucundan ucuna olan HAM farkı gösterir; alımlar düşülmez.
    // Yani "portföyüm ne kazandı" değil, **"birikimim ne kadar büyüdü"**
    // sorusunu yanıtlar. Dönem içinde alım yapıldıysa bu rakam simülasyon
    // sekmesinden belirgin biçimde YÜKSEK çıkar — aradaki fark yatırılan
    // paradır ve kullanıcı bunu görmek ister (kullanıcı kararı, 2026-08-31).
    //
    // Formül iki sekmede de aynıdır; fark girdide:
    //   • Gerçek     → miktar alım anında artar, seri basamak yapar
    //   • Simülasyon → bugünkü net pozisyon sabit, basamak yok
    //
    // ⚠️ Bu rakam KAZANÇ DEĞİLDİR. Düz seyreden bir fona 100.000 TL
    // yatırıldığında kart +%100 yazar. Bu yüzden başlık "birikim" der ve
    // aşağıdaki not satırı, ne kadarının alımdan geldiğini AÇIKÇA söyler.
    // Etiket olmadan bu rakam "kazandım" diye okunurdu.
    final change = grossChange;

    // Yüzde tabanı dönem başı değerdir — (son − ilk) / ilk.
    // `netInflow` tabana EKLENMEZ: eklenirse alımın etkisi payda üzerinden
    // geri sönümlenir ve "birikim büyüdü" bilgisi kaybolurdu.
    final pctBase = firstY;
    final pct = pctBase > 0 ? (change / pctBase) * 100 : null;
    final positive = change >= 0;

    // Yuvarlanmış tutar ve yüzde ikisi de sıfırsa nötr renk — yeşil göstermek
    // "kazanç var" yanılgısı yaratır. _PeriodChangeRow ile aynı kural.
    final isFlat = change.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
    final color = isFlat
        ? context.c.text36
        : (positive ? context.c.gain : context.c.loss);

    final tryFmt =
        tryFormatter(digits: 0);
    final periodLabel = _periods[_selectedPeriodIdx].label;
    // Yıl, iki uç FARKLI yıla düşüyorsa yazılır.
    //
    // Sabit `d MMM` biçimi 1Y periyodunda "31 Ağu → 31 Ağu" üretiyordu:
    // aralık doğruydu (2025 → 2026) ama yıl gizlendiği için aynı güne
    // bakılıyormuş gibi görünüyordu. Kısa periyotlarda yıl gereksiz
    // gürültüdür, o yüzden koşullu.
    final dateFmt = DateFormat(
      start.year == end.year ? 'd MMM' : 'd MMM y',
      'tr_TR',
    );
    // Başlık "birikim" der: rakam alımları İÇERİR, dolayısıyla saf getiri
    // değildir. Simülasyonda miktar sabit olduğu için orada birikim etkisi
    // yoktur ve etiket sade kalır.
    // Gün içi kart BUGÜNÜ anlatmayabilir: piyasa kapalıyken grafik son
    // seansı çizer (bkz. `PortfolioHistoryBreakdown.seansGunu`). Başlık
    // "Bugünkü" derken Cuma'nın rakamını göstermek düpedüz yanlış bilgidir.
    final simdi = DateTime.now();
    final gunIciBugun = start.year == simdi.year &&
        start.month == simdi.month &&
        start.day == simdi.day;
    // Piyasa kapalı kuyruğu çizilmiş mi? Ayrı bir parametre GEÇİRMİYORUZ:
    // segmentler zaten bu kartın girdisi ve kuyruk orada işaretli. İkinci
    // bir yoldan sormak, iki kaynağın ayrışması demekti.
    final kapaliKuyruk = segments.any((s) => s.piyasaKapali);

    // Gün içi başlık, çizilen günü söyler. Kuyruk varsa aralık yazılır
    // ("11 Eyl → bugün"): eksen artık tek gün değil, kullanıcı isteği
    // gereği hafta sonunu da kapsıyor (2026-09-12).
    final gunIciBaslik = gunIciBugun
        ? 'Bugünkü birikim değişimi'
        : kapaliKuyruk
            ? '${DateFormat('d MMM', 'tr_TR').format(start)} → bugün'
            : '${DateFormat('d MMMM', 'tr_TR').format(start)} birikim değişimi';

    final title = intraday
        ? gunIciBaslik
        : _simulate
            ? '$periodLabel değişim · simülasyon'
            : '$periodLabel birikim değişimi';

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 14),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık "1A birikim değişimi · simülasyon" gibi uzayabiliyor;
          // 320pt'de tek satıra sığmalı (taşma testi bunu kovalıyor).
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.t.titleSmall?.copyWith(color: context.c.text58),
                ),
              ),
              // "PİYASA KAPALI" rozeti — grafikteki gri kesikli kuyruğun
              // ne olduğunu SÖZLE de anlatır. Desen tek başına yeterli
              // değil: kullanıcı düz çizgiyi "fiyat oynamadı" diye
              // okuyabilir, oysa borsa kapalıydı.
              if (kapaliKuyruk) ...[
                const SizedBox(width: SandikSpace.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.c.text36.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                  ),
                  child: Text(
                    // Metin portföydeki TÜRLERE göre daralır: mevduat
                    // faizi hafta sonu da işler, ona "piyasa kapalı"
                    // demek yanlış bilgidir (bkz. `piyasaKapaliEtiketi`).
                    piyasaKapaliEtiketiVarliklardan(targetAssets),
                    maxLines: 1,
                    style: context.t.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: context.c.text36,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tutar — bloğun ana bilgisi, en büyük tipografi.
              // FittedBox: milyonluk portföyde dar ekranda taşmasın,
              // punto düşsün ama satır kırılmasın.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isFlat
                        ? 'Değişim yok'
                        : '${positive ? '+' : '−'}${tryFmt.format(change.abs())}',
                    maxLines: 1,
                    style: context.t.numMedium.copyWith(color: color),
                  ),
                ),
              ),
              if (pct != null && !isFlat) ...[
                const SizedBox(width: SandikSpace.sm),
                // Yüzde rozeti — yön ikonu renge ek bir sinyal taşır,
                // renk körlüğünde de okunur.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: SandikRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        positive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        fmtPct(pct.abs(), digits: 2),
                        style: context.t.numSmall.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            intraday
                ? (gunIciBugun
                    ? 'Bugün'
                    : '${dateFmt.format(start)} · son seans')
                : '${dateFmt.format(start)} → ${dateFmt.format(end)}',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
          // Ana rakam artık alımları İÇERİYOR. Not satırı bu yüzden ters
          // yöne çalışır: kullanıcı "+%100 kazandım" sanmasın diye ne
          // kadarının yatırılan paradan, ne kadarının piyasadan geldiğini
          // ayırır. Etiket tek başına yetmez — sayının kaynağı yazılmalı.
          if (netInflow.abs() > 0.5) ...[
            const SizedBox(height: SandikSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: context.c.text36),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    netInflow > 0
                        ? 'Bu dönemde ${tryFmt.format(netInflow)} tutarında alım '
                            'yapıldı ve yukarıdaki rakam bunu İÇERİR. '
                            'Yalnızca piyasa hareketi: '
                            '${tryFmt.format(grossChange - netInflow)}.'
                        : 'Bu dönemde ${tryFmt.format(netInflow.abs())} tutarında '
                            'satış yapıldı ve yukarıdaki rakam bunu İÇERİR. '
                            'Yalnızca piyasa hareketi: '
                            '${tryFmt.format(grossChange - netInflow)}.',
                    style:
                        context.t.bodySmall?.copyWith(color: context.c.text36),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

  Set<double> _buyDayKeys(
      List<TransactionSegment> segments, List<Asset> assets, DateTime start,
      {required bool intraday}) {
    // Cache anahtarı: başlangıç + varlık kimlikleri + segment imzası.
    // Segment imzası nokta SAYISI ile yetinmemeli — periyot/veri değişince
    // sayı aynı kalıp X aralığı kayabilir (örn. 30 günlük iki farklı
    // pencere). İlk/son X de anahtara giriyor ki bayat cache dönmesin.
    //
    // `id` tek başına yetmez: yumuşak silme `isActive`'i çevirir ama id'yi
    // değiştirmez — anahtar sabit kalır ve silinen lot'un noktası cache'ten
    // dönmeye devam ederdi. Aşağıdaki filtre alanları anahtara giriyor.
    // `intraday` anahtara GİRER: aynı segment kümesi için gün içi mod saati
    // korur, diğer modlar gece yarısına kırpar. Anahtarda olmasaydı sekme
    // değişince bayat X'ler dönerdi.
    final sig = StringBuffer()
      ..write(intraday ? 'i|' : 'd|')
      ..write(start.millisecondsSinceEpoch)
      ..write('|')
      ..write(assets
          .map((a) =>
              '${a.id}:${a.isActive ? 1 : 0}${a.isBuy ? 'b' : a.isSell ? 's' : 'x'}')
          .join(','));
    for (final s in segments) {
      sig
        ..write('|')
        ..write(s.spots.length);
      if (s.spots.isNotEmpty) {
        sig
          ..write(':')
          ..write(s.spots.first.x)
          ..write('-')
          ..write(s.spots.last.x);
      }
    }
    final key = sig.toString();
    if (_buyDayKeysCacheKey == key && _buyDayKeysCache != null) {
      return _buyDayKeysCache!;
    }

    // Varlıkların alım günlerini bir kez "gün damgası" set'ine indir; sonra
    // her spot için O(1) lookup. İç içe `assets.any(...)` taraması gitti.
    //
    // FİLTRE ŞART: bu set noktanın çizilip çizilmeyeceğine karar veriyor,
    // dolayısıyla tooltip/crosshair'in "o gün işlem var mı" testiyle AYNI
    // kümeden beslenmeli (bkz. `crosshairDetailsBuilder`). Filtresiz haliyle
    // temettü kayıtları (ne buy ne sell), deleteLog mezar taşları ve yumuşak
    // silinmiş lot'lar da nokta üretiyordu: grafikte nokta görünüyor, ama
    // basınca "Alım/Satış" satırı çıkmıyordu.
    // İşlem günlerini grafiğin X birimine (kesirli gün) çevir.
    final startMidnight = dayKey(start);
    final txXs = <double>[];
    for (final a in assets) {
      if (!a.isActive) continue;
      if (!a.isBuy && !a.isSell) continue;
      final d = a.addedDate;
      // Gün içi ("GÜNLÜK") seride SAAT KORUNUR.
      //
      // Burada eskiden koşulsuz `dayKey(d)` vardı —
      // işlemin saati kırpılıp gece yarısına çekiliyordu. Günlük/haftalık
      // seride bu doğrudur (bar zaten güne snap edilir), ama gün içi seride
      // 5 dakikalık slotlarla çalışılır: 14:00'te yapılan alım 00:00'a
      // düşünce grafiğin görünür aralığının DIŞINA çıkıyor ve nokta hiç
      // doğmuyordu. Sıçramanın ölçek yüzünden görünmediği durumda
      // (tüm portföy görünümü) geriye hiçbir işaret kalmıyordu.
      final anchor = intraday ? d : dayKey(d);
      txXs.add(anchor.difference(startMidnight).inMinutes / (60.0 * 24.0));
    }

    // ── İşlemi KAPSAYAN spot'a bağla, tam gün eşleşmesi ARAMA ──────────────
    //
    // Eski hâli `spot.günü == işlem.günü` eşitliği arıyordu ve 6A/1Y'de
    // noktaların kaybolmasının sebebi buydu: o periyotlarda veri
    // `ResolutionTier.weekly` gelir ve her nokta haftanın PAZARTESİSİNE snap
    // edilir (bkz. `ResolutionTierMeta.normalizeTs`). Çarşamba yapılan alımın
    // günü hiçbir spot'a eşit olmadığı için aday bile üretilmiyordu — yani
    // seyreltme değil, noktanın kendisi hiç doğmuyordu. Aynı sorun 1H'de
    // saatlik snap yüzünden hafta sonu/kapanış sonrası işlemlerde çıkıyordu.
    //
    // Artık her işlem, X'i kendisine eşit veya kendisinden küçük olan son
    // spot'a (içine düştüğü bar'a) bağlanır.
    final keys = <double>{};
    for (final seg in segments) {
      if (seg.thickness <= 2.0) continue;
      final spots = seg.spots;
      if (spots.isEmpty) continue;
      for (final txX in txXs) {
        final i = coveringSpotIndex(spots, txX);
        // -1: işlem serinin başlangıcından önce — o nokta grafikte yok.
        if (i < 0) continue;
        keys.add(spots[i].x);
      }
    }

    _buyDayKeysCacheKey = key;
    _buyDayKeysCache = keys;
    return keys;
  }

  Widget _buildChartContainer(List<TransactionSegment> segments, DateTime start,
      DateTime end, List<Asset> assets,
      {bool intraday = false, List<Asset>? allTargetAssets}) {
    if (segments.isEmpty) {
      return Container(
        height: 280,
        decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg)),
        child: Center(
            child: Text('Veri yok', style: TextStyle(color: context.c.text36))),
      );
    }

    // İşlem kaynağı — TEK TANIM. Hem nokta çizimi (`_buyDayKeys`) hem
    // crosshair detayları bunu kullanır. İkisi ayrı listelerden beslendiğinde
    // "grafikte nokta var ama basınca alım/satım yazmıyor" tutarsızlığı
    // çıkıyordu: nokta `chartAssets`'ten, tooltip `allTargetAssets`'ten
    // geliyordu ve simülasyonda `chartAssets` sentetik `addedDate` taşır.
    final txAssets = allTargetAssets ?? assets;

    // Y ekseni scale'i — SADECE en kalın segmentin (aktif sarı çizgi)
    // değerlerine göre hesaplanır. Passive segment (alım öncesi 0 çizgisi)
    // Y aralığına dahil edilirse min hep 0'a çekilir ve aktif değerler
    // ezik görünür. Bu yüzden en kalın segmenti "ana" kabul edip diğerleri
    // clipData ile alta düşer.
    final primarySeg =
        segments.reduce((a, b) => (a.thickness >= b.thickness) ? a : b);

    // ── Crosshair'in tarayacağı noktalar ────────────────────────────────
    //
    // `primarySeg` Y ekseni için doğru kaynak (en kalın = ana çizgi) ama
    // DOKUNMA için yanlış: piyasa kapalı kuyruğu ayrı ve daha ince bir
    // segment olduğundan (bkz. `TransactionSegment.piyasaKapali`) oraya
    // düşmüyor. Sonuç: kullanıcı uzun bastığında crosshair kapanışta
    // duruyor, hafta sonu/tatil bölgesinde tarih ve değer okunamıyordu
    // (kullanıcı bildirimi 2026-09-12).
    //
    // Dokunma tüm çizilmiş noktaları görmeli. Segmentler zaten X'e göre
    // sıralı üretiliyor; sınırda tek nokta çakışabildiği için birleştirme
    // sonrası tekilleştiriliyor — `nearestSpotIndex` ikili arama yapıyor
    // ve sıralı+tekil dizi bekliyor.
    final List<FlSpot> crosshairSpots;
    if (segments.length == 1) {
      crosshairSpots = primarySeg.spots;
    } else {
      final birlesik = [for (final s in segments) ...s.spots]
        ..sort((a, b) => a.x.compareTo(b.x));
      crosshairSpots = [
        for (var i = 0; i < birlesik.length; i++)
          if (i == 0 || birlesik[i].x != birlesik[i - 1].x) birlesik[i],
      ];
    }

    // Görünür X aralığındaki spot'lara göre Y sınırlarını hesapla. Zoom
    // sırasında X daraldıkça Y ekseni otomatik yeniden fit olur — kullanıcı
    // dar bir zaman diliminde küçük dalgalanmayı okuyabilir.
    ({double minY, double maxY, double interval}) computeY(
        double viewMinX, double viewMaxX) {
      double minY = double.infinity;
      double maxY = -double.infinity;
      double sumY = 0;
      int countY = 0;
      for (final spot in primarySeg.spots) {
        if (spot.x < viewMinX || spot.x > viewMaxX) continue;
        if (spot.y > maxY) maxY = spot.y;
        if (spot.y < minY) minY = spot.y;
        sumY += spot.y;
        countY++;
      }
      if (minY == double.infinity) minY = 0;
      if (maxY == -double.infinity) maxY = 1000;
      final avgY = countY > 0 ? sumY / countY : (minY + maxY) / 2;
      // Bandın cebri `chart_axis.dart`'ta — saf ve testli.
      //
      // Asgari bant oranı gün içinde ÇOK DARDIR (%0,5). Bir portföyün
      // günlük hareketi tipik olarak ±%0,5–2'dir; buradaki eski %8'lik
      // taban o hareketi grafik yüksekliğinin onda birine sıkıştırıyor ve
      // seans boyunca gerçek dalgalanma varken çizgi DÜMDÜZ görünüyordu
      // (kullanıcı bildirimi 2026-09-07: "yüksek precision ile göstermesi
      // gerekirdi"). Widget/Live Activity grafiği aynı dersi daha önce
      // öğrenmiş ve %0,5'e inmişti; artık iki yüzey tek sabitten besleniyor.
      //
      // Uzun periyotlarda %8 nadiren bağlayıcıdır (bir ay zaten daha çok
      // oynar) — orada dokunulmadı.
      return gorunurYBandi(
        dataMinY: minY,
        dataMaxY: maxY,
        avgY: avgY,
        asgariBantOrani: intraday ? gunIciAsgariBantOrani : 0.08,
      );
    }

    // Serinin son noktasının gün başından uzaklığı (dakika). Bugünü
    // çizerken bu zaten "şimdi"ye eşittir; geçmiş seansta kapanış anıdır.
    // TÜM segmentlerin en sağdaki noktası — `primarySeg` DEĞİL.
    //
    // `primarySeg` "en kalın segment" olarak seçiliyor ve bu SEANS
    // segmentidir (3.5); piyasa kapalı kuyruğu daha ince (2.5) olduğu
    // için dışarıda kalıyordu. Sonuç: "ŞİMDİ" dikey çizgisi ve son nokta
    // işaretçisi kapanışta duruyor, kuyruk boyunca uzanmıyordu
    // (kullanıcı bildirimi 2026-09-12, ekran görüntüsüyle).
    //
    // Kuyruk varsa en sağdaki nokta ONUN son noktasıdır — yani "şimdi".
    final gunIciSonNoktaDk = !intraday
        ? 0.0
        : segments
            .expand((s) => s.spots)
            .fold<double>(0.0, (m, s) => s.x > m ? s.x : m);

    // X ekseni — aktif segment çok sıkışıksa (örn. tek gün alım + bugün)
    // viewport'u aktif segment başlangıcından biraz öncesine daralt.
    // Böylece "12 Tem'de aldım, bugün 13" senaryosu tüm 1H window'da
    // dikey çubuk gibi değil, geniş bir eğri gibi görünür. AYRICA
    // başlangıç ve bitiş noktaları hep viewport'un içinde kalmalı —
    // dot çizim yarıçapı (~6px) sınırda clip'lenmesin diye her iki
    // uca minimum yarım günlük pay bırakılır.
    double fullMaxX;
    if (intraday) {
      // Şimdi noktasını viewport'un sağında **hep içeride** tut ki her
      // tick'te güncellenirken görünsün. Nokta viewport'un yaklaşık
      // %82'sinde olacak şekilde fullMaxX'i genişletiyoruz. Alt sınır
      // 1440 (tam gün) — sabahın ilk saatlerinde grafiğin çok dar
      // görünmesini engeller.
      // Kural `chart_axis.dart`'ta — takip listesi grafiği de aynı
      // fonksiyondan besleniyor. İki ekran aynı günü aynı ölçekte çizmeli;
      // kopyalandığında biri düzelirken öteki geride kalıyordu.
      //
      // Referans nokta `DateTime.now()` DEĞİL, serinin SON NOKTASIDIR:
      // çizilen gün bugün olmayabilir (hafta sonu/tatilde son seans
      // çizilir) ve o durumda "şu anki saat" bu eksende bir yere karşılık
      // gelmez — 1440'ı aşan bir sağ uç üretip seansı sola ezerdi.
      fullMaxX = gunIciEksenSonuDk(gunIciSonNoktaDk);
    } else {
      // Kesirli gün — saatlik veride son X ~6.83, integer olsa 7 kalırdı
      // ve son nokta grafiğin sağında boşta kalırdı.
      fullMaxX = (end.difference(start).inMinutes / (60.0 * 24.0))
          .clamp(1.0, double.infinity);
    }
    // Eksenin sol ucu VERİNİN başladığı yer — sabit 0 değil.
    //
    // `startDate` ile ilk veri noktası nadiren çakışır: dönem başı takvim
    // gününe çekiliyor ama seri o gün borsanın açıldığı saatte başlıyor,
    // ayrıca hafta sonu/tatilde ilk kova günler sonraya düşebiliyor.
    // Eksen 0'dan başlayınca soldaki o fark BOŞ bir şerit olarak kalıyor
    // ve çizgi grafiğin başından değil içeriden başlıyor görünüyordu
    // (kullanıcı bildirimi 2026-09-12, 1H sekmesi — ölçüldü: ilk nokta
    // X = 0,917, yani neredeyse bir gün içeride).
    //
    // Çözüm: ekseni veriye oturt. Sağ uç zaten son noktada bitiyor.
    final veriXs = primarySeg.spots.map((s) => s.x);
    final ilkVeriX =
        veriXs.isEmpty ? 0.0 : veriXs.reduce((a, b) => a < b ? a : b);
    double minX = intraday ? 0.0 : ilkVeriX;
    double maxX = fullMaxX;
    final activeSpotXs = primarySeg.spots.map((s) => s.x).toList()..sort();
    if (activeSpotXs.isNotEmpty && !intraday) {
      final firstActiveX = activeSpotXs.first;
      final lastActiveX = activeSpotXs.last;
      final activeSpan = lastActiveX - firstActiveX;
      final fullSpan = fullMaxX;
      // Aktif segment tüm periyodun %25'inden azsa viewport'u daralt.
      if (activeSpan < fullSpan * 0.25) {
        // İlk & son noktanın iki tarafına eşit ve cömert bağlam bırak
        // (en az 1 gün, en çok aktif span kadar). Böylece başlangıç
        // ve bitiş noktaları grafiğin ortasında değil, kenardan güvenli
        // bir mesafede görünür.
        final pad = (activeSpan.clamp(1.0, double.infinity)) * 0.8;
        minX = (firstActiveX - pad).clamp(0.0, fullMaxX);
        // clamp(lower, upper) kuralı: lower <= upper olmalı. Aktif segment
        // fullMaxX'e yakınsa "minX + 1" fullMaxX'i geçebilir → crash. O yüzden
        // önce üst sınırı belirle, sonra minX + 1'i onunla clamp'la.
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + pad).clamp(lower, upper);
      }
      // Son güvenlik payı: dot yarıçapı viewport sınırında clip olmasın.
      // Toplam aralığın %3'ü kadar minimum pay bırak.
      final safety = ((maxX - minX) * 0.03).clamp(0.15, double.infinity);
      if (firstActiveX - minX < safety) {
        minX = (firstActiveX - safety).clamp(0.0, fullMaxX);
      }
      if (maxX - lastActiveX < safety) {
        final upper = fullMaxX;
        final lower = (minX + 1).clamp(0.0, upper);
        maxX = (lastActiveX + safety).clamp(lower, upper);
      }
      // Son bir güvenlik: minX ile maxX çakışmışsa hafifçe aç.
      if (maxX <= minX) {
        maxX = (minX + 1).clamp(0.0, fullMaxX);
        if (maxX <= minX) minX = (maxX - 1).clamp(0.0, fullMaxX);
      }
    }

    // Zoom durumunda tekrar üretilen LineChartData'yı bir closure'a al.
    // ZoomableChart pinch/pan sırasında minX/maxX değiştirdikçe bu builder
    // yeniden çağrılır; Y ekseni görünür pencereye göre re-fit olur.
    LineChartData buildData(double viewMinX, double viewMaxX) {
      final y = computeY(viewMinX, viewMaxX);
      final double viewMinY = y.minY;
      final double viewMaxY = y.maxY;
      final double yInterval = y.interval;
      // X ekseni için uygun aralık. Intraday'de 4 saatlik (240 dk) etiketler
      // → 00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00 gibi.
      // Gün içi eksende adım, ETİKET UZUNLUĞUNA göre açılır.
      //
      // Sabit 240 dk (4 saat) tek günlük eksende doğruydu: etiket "04:00"
      // gibi kısa. Ama piyasa kapalıyken eksen birden çok günü kapsıyor ve
      // etiket "11 Eyl 04:00"a uzuyor (bkz. `zamanEtiketi`) — aynı adımda
      // yan yana altı etiket ÜST ÜSTE BİNİYORDU (kullanıcı bildirimi
      // 2026-09-12, ekran görüntüsüyle).
      //
      // Çok günlü eksende adım gün sayısıyla ölçekleniyor: eksen ne kadar
      // uzarsa etiketler o kadar seyrekleşir, sayıları sabit kalır.
      final gunIciSpanGun = (viewMaxX - viewMinX).abs() / 1440.0;
      final xInterval = intraday
          ? (gunIciSpanGun > 1
              // Çok günlü eksende etiket "11 Eyl 04:00"a uzuyor (~88px).
              // Hedef ÜÇ etiket: ölçüldü, 5 etiket ~330px genişlikte
              // sığmıyordu ve yan yana yapışıyordu (kullanıcı bildirimi
              // 2026-09-12, iki tur üst üste).
              //
              // 3 saatin katına yuvarlanıyor: tick'ler hem yuvarlak
              // saatlere düşsün hem de kaba adımlarda 09:00/12:00 gibi
              // okunur değerler çıksın.
              ? (((viewMaxX - viewMinX).abs() / 3 / 180).ceilToDouble() * 180)
                  .clamp(gunIciEksenAdimiDk, double.infinity)
              : gunIciEksenAdimiDk)
          : yuvarlakAdim((viewMaxX - viewMinX) / 5).clamp(1.0, double.infinity);

      // Alım dot'ları için piksel bazlı seyreltme. Arka arkaya yapılan
      // alımlarda noktalar birkaç piksel arayla düşüp üst üste biniyor ve
      // tek bir yığın gibi görünüyordu. Aynı X uzayında minimum 16px mesafe
      // şartı koyuyoruz; zoom yapıldıkça viewport daralır, noktalar açılır
      // ve gizlenenler tek tek ortaya çıkar.
      // Simülasyonda işlem noktası YOKTUR (miktar tüm dönem sabit sayılır,
      // "o gün alım yapıldı" bilgisi o modelde anlamsız). Gün içi seride ise
      // noktalar GÖSTERİLİR: sıçrama tüm portföy ölçeğinde görünmediğinde
      // işlemin izini taşıyan tek şey odur.
      final DotThinner dotThinner = _simulate
          ? DotThinner.build(
              candidates: const [],
              viewMinX: viewMinX,
              viewMaxX: viewMaxX,
            )
          : () {
              return DotThinner.build(
                // `buyDayKeys` viewport'a bağlı DEĞİL — zoom/pan her karede
                // yeniden hesaplanması saf israftı (spot × varlık döngüsü +
                // her çift için DateTime aritmetiği). Artık segment/varlık
                // kümesi başına bir kez hesaplanıp cache'leniyor.
                //
                // Kaynak liste crosshair ile AYNI olmalı (`txAssets`), aksi
                // halde nokta bir kümeden, tooltip başka kümeden beslenir ve
                // "noktası var ama işlemi yok" tutarsızlığı doğar.
                candidates:
                    _buyDayKeys(segments, txAssets, start, intraday: intraday),
                viewMinX: viewMinX,
                viewMaxX: viewMaxX,
                // Grafik genişliği ~ekran - sağ Y rezervi (60px).
                plotWidthPx: (MediaQuery.of(context).size.width - 60 - 40)
                    .clamp(120.0, 2000.0),
                // Nokta çapı 8.5px'ten ~7.2px'e indi (r=3 + 1.2 halka), bu
                // yüzden ayrım eşiği de 16'dan 11'e çekilebiliyor: daha az
                // nokta gizlenir, üst üste binme yine olmaz.
                minSeparationPx: 11,
                // Uç noktalara yakın işlemler kalıcı olarak gizlenmesin —
                // "şimdi" dot'u r=6 olduğu için 8px yeter (bkz. DotThinner).
                anchorSeparationPx: 8,
                // İlk ve son nokta her zaman görünür (anchor / "şimdi").
                alwaysKeep: {
                  primarySeg.spots.first.x,
                  primarySeg.spots.last.x,
                },
              );
            }();

      // Seçili grafik tipi — oturum boyunca yaşar (bkz. `grafikTipiNotifier`).
      // `ValueListenableBuilder` dışarıda: burada okumak yeterli çünkü
      // seçim değiştiğinde builder tüm grafiği yeniden kuruyor.
      final tip = grafikTipiNotifier.value;

      return LineChartData(
        minX: viewMinX,
        maxX: viewMaxX,
        minY: viewMinY,
        maxY: viewMaxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: intraday,
          verticalInterval: intraday ? gunIciEksenAdimiDk : null,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.c.overlay,
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: context.c.overlay,
            strokeWidth: 1,
          ),
        ),
        // Sağ Y ekseni band'ı görsel olarak plot area'dan ayrılsın diye
        // sadece sağ kenara ince dikey çizgi. TradingView'de plot | Y ayrık.
        borderData: FlBorderData(
          show: true,
          border: Border(
            right: BorderSide(
              color: context.c.overlay,
              width: 1,
            ),
          ),
        ),
        extraLinesData: intraday
            // Gün içi grafikte dikey "ŞİMDİ" çizgisi KALDIRILDI
            // (kullanıcı isteği 2026-09-12): X ekseni etiketleriyle
            // çakışıyordu ve bilgi zaten iki yerde daha var — serinin
            // ucundaki nokta (piyasa kapalıyken gri) ve üstteki kartın
            // "11 Eyl → bugün · PİYASA KAPALI" başlığı.
            ? const ExtraLinesData(verticalLines: [])
            : ExtraLinesData(
                verticalLines: primarySeg.spots.isEmpty
                    ? const []
                    : [
                        // Dönem başı için dikey kesikli işaret KALDIRILDI
                        // (kullanıcı isteği 2026-09-12): "başlangıcın
                        // dikine kesikli çizgilerle gösterilmesini
                        // istemiyorum, tüm grafikler aynı deneyimi
                        // sunmalı."
                        //
                        // Dönem başı bilgisi kaybolmadı — üstteki değişim
                        // kartı "5 Eyl → 12 Eyl" aralığını zaten yazıyor
                        // ve X ekseninin ilk etiketi de aynı tarihi
                        // gösteriyor.
                        // Son nokta (bugün / şimdi) için dashed marker.
                        // Etiket çizginin SOLUNA (grafik içine) yaslanır.
                        VerticalLine(
                          x: primarySeg.spots.last.x,
                          color: context.c.gain.withValues(alpha: 0.55),
                          strokeWidth: 1.2,
                          dashArray: const [4, 4],
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topLeft,
                            padding: const EdgeInsets.only(bottom: 8, right: 6),
                            style: context.t.labelMedium?.copyWith(
                              letterSpacing: 0,
                              fontWeight: FontWeight.w700,
                              color: context.c.gain,
                            ),
                            labelResolver: (_) => 'ŞİMDİ',
                          ),
                        ),
                      ],
              ),
        titlesData: FlTitlesData(
          show: true,
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // TradingView tarzı: fiyat scale SAĞDA, tarih ekseni ALTTA ayrı bant.
          // leftTitles kapatıldı, rightTitles dolduruldu. Rezerv alanları
          // grafik alanına girmesin diye cömert (Y sağda 60, X altta 40).
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              interval: yInterval,
              getTitlesWidget: (val, meta) {
                if (val == meta.min || val == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    _fmtY(val),
                    textAlign: TextAlign.left,
                    style: context.t.numSmall.copyWith(
                      color: context.c.text58,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: xInterval,
              getTitlesWidget: (val, meta) {
                // Etiket tick'in ÜZERİNDE ortalanır; kenara çok yakın bir
                // tick'in etiketi plot alanının dışına taşar. Zoom'da
                // interval artık sınırlara denk gelmediği için `val ==
                // meta.min/max` kontrolü yetmiyordu — bunun yerine viewport
                // genişliğinin %6'sı kadar bir kenar payı bırakıyoruz.
                final span = (meta.max - meta.min).abs();
                final edge = span * 0.06;
                if (val <= meta.min + edge || val >= meta.max - edge) {
                  return const SizedBox.shrink();
                }
                // Dinamik format — dar viewport'ta gün+ay, geniş
                // viewport'ta (365+ gün) sadece "MMM yy". Çok dar (<3 gün)
                // görünümde saat de göster.
                // Biçim kuralı `chart_axis.dart`'ta — takip listesi grafiği
                // de aynı fonksiyonu çağırır.
                //
                // Gün içi etiket eskiden dakikadan elle kuruluyor ve saat
                // `clamp(0, 23)` ile sıkıştırılıyordu: eksen günü aştığında
                // (19:41'den sonra, bkz. `gunIciEksenSonuDk`) gece yarısı
                // tick'i "00:00" yerine "23:00" yazıyor, yani var olmayan bir
                // saati işaretliyordu.
                final label = zamanEtiketi(
                  intraday
                      ? start.add(Duration(minutes: val.round()))
                      : start.add(Duration(minutes: (val * 24 * 60).round())),
                  // `spanGun` adı GÜN demek ama gün içi eksende X
                  // DAKİKA cinsinden. Dönüştürülmezse eşik karşılaştırması
                  // saçmalar: 1 günlük eksen 1440 "gün" gibi okunur.
                  spanGun: intraday
                      ? (meta.max - meta.min).abs() / 1440.0
                      : (meta.max - meta.min).abs(),
                  gunIci: intraday,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  // Sabit genişlik + ortalama: fl_chart etiketi tick'te
                  // ortalar, taşan metin ellipsis olur ve komşu etiketle
                  // çakışmaz.
                  //
                  // Genişlik etiketin EN UZUN hâline göre: çok günlü gün
                  // içi eksende "11 Eyl 04:00" yazılıyor ve 74px'e
                  // sığmayıp kırpılıyordu.
                  child: SizedBox(
                    width: intraday && (meta.max - meta.min).abs() > 1440
                        ? 88
                        : 74,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: context.t.numSmall.copyWith(
                        color: context.c.text58,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // ── Bar tipi: her nokta için dikey çubuk ──────────────────
        //
        // `fl_chart`'ın `BarChart`'ı kullanılamıyor: orada X data-space
        // değil GRUP indeksi, yani zoom/pan ve tarih ekseni bozulurdu.
        // Bunun yerine her nokta iki spot'lu ayrı bir `LineChartBarData`
        // olarak çiziliyor — aynı teknik ekranın karşılaştırma bölümünde
        // de kullanılıyor.
        //
        // Yoğun serilerde (169 nokta) çubuklar birbirine girmesin diye
        // seyreltiliyor; sınır grafiğin okunabilir kaldığı yoğunluk.
        lineBarsData: tip == GrafikTipi.bar
            ? _cubukSegmentleri(context, segments, viewMinY)
            : segments.map((seg) {
                final isActive = seg.thickness > 2.0;
                // Nokta yoğunluğu arttıkça çizgi inceltilir — intraday ve haftalık
                // (saatlik) yüzlerce nokta içerir, kalın çizgi zigzag'i yutar.
                // Trading uygulamalarındaki gibi ince ve okunaklı bir hat için:
                //
                // Merdivenin kendisi `chart_line_width.dart`'ta: takip/karşılaştır
                // grafiği de AYNI fonksiyonu çağırıyor. Kopyalanmış üç merdiven,
                // iki ekranın aynı dönemi farklı kalınlıkta çizmesinin sebebiydi.
                //
                // Gün içi sekmesi `days: 0` taşır; fonksiyon `<= 1` dalında zaten
                // gün içi kalınlığını verir, ayrıca `intraday` sormaya gerek yok.
                final periodDays = _periods[_selectedPeriodIdx].days;
                final activeBarWidth = donemCizgiKalinligi(periodDays);
                final effectiveBarWidth =
                    isActive ? activeBarWidth : seg.thickness;
                // İlk/son X'i closure dışında bir kez oku. Bu callback'ler
                // fl_chart tarafından NOKTA BAŞINA çağrılıyor; içeride
                // `seg.spots.first`/`.last` demek her nokta için tekrar
                // erişim + karşılaştırma demekti.
                final firstX =
                    seg.spots.isEmpty ? double.nan : seg.spots.first.x;
                final lastX = seg.spots.isEmpty ? double.nan : seg.spots.last.x;

                // ── Baseline: dönem başına göre kazanç/kayıp rengi ─────────
                //
                // `fl_chart` tek bir çizgiyi iki renge bölemiyor; renk geçişi
                // gradyan stop'larıyla kuruluyor. Taban, dönemin İLK değeri:
                // "bugün nerede başladım, şimdi neredeyim" sorusu bu.
                //
                // Kapalı kuyruk bu boyamanın DIŞINDA — orası nötr kalmalı.
                final tabanY = seg.spots.isEmpty ? 0.0 : seg.spots.first.y;
                final baselineAktif =
                    tip == GrafikTipi.baseline && !seg.piyasaKapali && isActive;

                return LineChartBarData(
                  spots: seg.spots,
                  isCurved: false,
                  color: baselineAktif ? null : seg.lineColor,
                  // Baseline'da renk gradyanla veriliyor; `color` ile birlikte
                  // kullanılamaz (fl_chart ikisini birden kabul etmez).
                  gradient: baselineAktif
                      ? _baselineGradient(context, seg.spots, tabanY)
                      : null,
                  // Bar tipinde çizgi GİZLİ: çubuklar ayrı katmanda çiziliyor
                  // ve üstüne bir de çizgi binmesi grafiği okunamaz yapardı.
                  barWidth: tip == GrafikTipi.bar ? 0.0 : effectiveBarWidth,
                  // Piyasa kapalıyken taşınan fiyat KESİKLİ çizilir. Rengi
                  // `lineColor` zaten nötr geliyor (bkz. `_convertHistoryToSegments`);
                  // desen, renk körlüğünde de ayırt edilebilsin diye ikinci bir
                  // sinyal olarak ekleniyor.
                  dashArray: seg.piyasaKapali ? const [4, 4] : null,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, barData) {
                      if (!isActive) return false;
                      // Simülasyonda nokta yok — sadece süreklilik çizgisi.
                      if (_simulate) return false;
                      // Intraday: sadece ilk ve son noktada dot göster (5 dk
                      // aralıklı yüzlerce nokta olduğu için hepsini işaretlemek
                      // grafiği bulanıklaştırır).
                      if (intraday) {
                        // "Şimdi" noktası her zaman görünür.
                        if (spot.x == lastX) return true;
                        // Gün içi İŞLEM noktaları da görünür.
                        //
                        // Sebep: sıçramanın görünürlüğü mutlak tutara değil ORANA
                        // bağlı. Tüm portföy görünümünde küçük bir alım Y ekseninde
                        // kaybolur (500.000 TL'nin %1'i düz görünür), tür filtresi
                        // uygulanınca aynı alım belirgin basamak olur. Nokta,
                        // sıçrama görünmediğinde bile "burada işlem yapıldı"
                        // bilgisini taşır ve tooltip'e bağlanır.
                        return dotThinner.shows(spot.x);
                      }
                      // İlk/son nokta her zaman görünür; alım dot'ları ise
                      // piksel bazlı seyreltmeden geçer (bkz. `dotThinner`) —
                      // yoğun alım günlerinde üst üste binip yığın oluşmasın.
                      if (spot.x == firstX || spot.x == lastX) {
                        return true;
                      }
                      return dotThinner.shows(spot.x);
                    },
                    getDotPainter: (spot, percent, barData, index) {
                      final isFirst = spot.x == firstX;
                      final isLast = spot.x == lastX;
                      // Intraday'de sadece "şimdi" noktasını canlı bir amber
                      // dot ile göster — trading uygulaması hissiyatı için
                      // ince halka ile.
                      if (intraday && isLast) {
                        // "Şu an" noktası.
                        //
                        // Piyasa KAPALIYKEN gri: o noktada canlı bir fiyat yok,
                        // son kapanış taşınıyor. Yeşil bırakmak "şu anda işlem
                        // görüyor" derdi (kullanıcı isteği 2026-09-12: "şu an
                        // noktası piyasa kapalı andaysa gri şekilde kesikli
                        // çizginin ucunda konumlanmalı").
                        final kapali = seg.piyasaKapali;
                        return FlDotCirclePainter(
                          radius: 5.0,
                          color: kapali ? context.c.text36 : context.c.gain,
                          strokeColor: context.c.text90,
                          strokeWidth: 1.6,
                        );
                      }
                      // Başlangıç dot'u kaldırıldı — "orada alım yapılmış" gibi
                      // yanıltıcı görünüyordu. Başlangıç zaten dashed marker +
                      // label ile işaretli. Son nokta (şimdi) canlı vurgusu için
                      // büyük yeşil dot ile kalır.
                      if (isFirst) {
                        return FlDotCirclePainter(
                          radius: 0,
                          color: Colors.transparent,
                          strokeWidth: 0,
                        );
                      }
                      if (isLast) {
                        return FlDotCirclePainter(
                          radius: 6.0,
                          color: context.c.gain,
                          strokeColor: context.c.text90,
                          strokeWidth: 2.5,
                        );
                      }
                      // Ortadaki işlem noktaları — "şimdi" noktasından belirgin
                      // şekilde küçük. Önceki 4.5px + 2px halka (toplam ~8.5px çap)
                      // yoğun alım yapılan aylarda çizgiyi boncuk dizisine
                      // çeviriyordu. Halka da inceltildi: küçük yarıçapta 2px'lik
                      // kenar dolgunun yarısını yiyip noktayı içi boş gösteriyordu.
                      return FlDotCirclePainter(
                        radius: 3.0,
                        color: context.c.amberText,
                        strokeColor: context.c.text90,
                        strokeWidth: 1.2,
                      );
                    },
                  ),
                  // ── Dolgu: grafik TİPİNE göre ───────────────────────────
                  //
                  // `line`      → dolgu yok, yalnızca çizgi.
                  // `mountain`  → gradyan dolgu (eski varsayılan görünüm).
                  // `baseline`  → dönem başına göre üstü kazanç / altı kayıp.
                  // `bar`       → çizgi gizli, çubuklar ayrı katmanda.
                  //
                  // Kapalı kuyruk HER TİPTE dolgusuz: o bölge birikim değil,
                  // taşınan son fiyat (bkz. `TransactionSegment.piyasaKapali`).
                  belowBarData: (tip == GrafikTipi.mountain &&
                          !seg.piyasaKapali)
                      ? BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: intraday
                                ? [
                                    context.c.amberFill.withValues(alpha: 0.22),
                                    context.c.amberFill.withValues(alpha: 0.06),
                                    Colors.transparent,
                                  ]
                                : [seg.areaGradientStart, Colors.transparent],
                            stops: intraday ? const [0.0, 0.5, 1.0] : null,
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        )
                      : BarAreaData(show: false),
                );
              }).toList(),
        // fl_chart'ın built-in touch'ı kapalı — crosshair TEK KAYNAK.
        // Kullanıcı uzun bastığında `ZoomableChart` snap edilmiş X'te dikey
        // çizgi + pill (fiyat/tarih/getiri/hareketler) gösterir. Tooltip ve
        // crosshair paralel çalışınca X hesabı farklı olup değerler
        // uyumsuz görünüyordu — tek kaynağa çektik.
        //
        // `enabled: false` de şart: `handleBuiltInTouches` yalnızca tooltip'i
        // kapatır, dokunma işleme katmanı açık kalır. `performance_screen`
        // ikisini birden veriyordu, burası vermiyordu — aynı jest iki ekranda
        // farklı davranıyordu.
        lineTouchData: LineTouchData(
          enabled: false,
          handleBuiltInTouches: false,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.c.surface2,
            tooltipRoundedRadius: 10,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            getTooltipItems: (spots) {
              final tryFmt0 = tryFormatter(digits: 0);
              // Primary segmentteki ilk ve son x — anchor / bugün tespiti.
              final firstX = primarySeg.spots.first.x;
              final lastX = primarySeg.spots.last.x;
              final firstY = primarySeg.spots.first.y;
              final lastY = primarySeg.spots.last.y;

              return spots.map((s) {
                // Non-intraday: s.x kesirli gün → dakika cinsinden ekle.
                // `.toInt()` kullanılırsa saat/dakika kısmı düşer ve tooltip
                // etiketi yakınlardaki tarihe kayıyor.
                final date = intraday
                    ? start.add(Duration(minutes: s.x.toInt()))
                    : start.add(Duration(minutes: (s.x * 24 * 60).round()));
                final isFirst = s.x == firstX;
                final isLast = s.x == lastX;

                // O gün YAPILAN alım/satım hareketleri (Gerçek modda).
                double dayBuyTRY = 0, daySellTRY = 0;
                // İlk noktadan (anchor) bugüne kadar KÜMÜLATİF hareketler.
                double cumBuyTRY = 0, cumSellTRY = 0;
                if (!_simulate && !intraday) {
                  final spotDayMs = dayKey(date)
                      .millisecondsSinceEpoch;
                  for (final a in assets) {
                    if (!a.isActive) continue;
                    final aDay = DateTime(a.addedDate.year, a.addedDate.month,
                            a.addedDate.day)
                        .millisecondsSinceEpoch;
                    final onSameDay = aDay == spotDayMs;
                    final onOrBefore = aDay <= spotDayMs;
                    if (a.isBuy) {
                      if (onSameDay) dayBuyTRY += a.totalCostTRY;
                      if (onOrBefore) cumBuyTRY += a.totalCostTRY;
                    } else if (a.isSell) {
                      if (onSameDay) daySellTRY += a.totalCostTRY;
                      if (onOrBefore) cumSellTRY += a.totalCostTRY;
                    }
                  }
                }

                final dayNet = dayBuyTRY - daySellTRY;
                final hasActivity = dayBuyTRY > 0 || daySellTRY > 0;

                // Anchor'a göre net getiri (bugüne kadarki maliyet vs
                // portföy değeri). Sadece son nokta için göster.
                final gainVsAnchor = lastY - firstY;

                final children = <TextSpan>[
                  TextSpan(
                    text: tryFmt0.format(s.y),
                    style: context.t.numSmall.copyWith(
                      color: context.c.gold,
                      fontSize: 15,
                    ),
                  ),
                ];

                // Bugün (son nokta) → getiri
                if (isLast && !_simulate && gainVsAnchor.abs() > 0.5) {
                  final positive = gainVsAnchor >= 0;
                  children.add(TextSpan(
                    text:
                        '\nGetiri ${positive ? '+' : '−'}${tryFmt0.format(gainVsAnchor.abs())}',
                    style: context.t.numSmall.copyWith(
                      color: positive ? context.c.gain : context.c.loss,
                      fontSize: 11,
                    ),
                  ));
                }

                // O gün yapılan hareketler
                if (hasActivity) {
                  if (dayBuyTRY > 0) {
                    children.add(TextSpan(
                      text: '\nAlım  +${tryFmt0.format(dayBuyTRY)}',
                      style: context.t.numSmall.copyWith(
                        color: context.c.gain,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ));
                  }
                  if (daySellTRY > 0) {
                    children.add(TextSpan(
                      text: '\nSatış −${tryFmt0.format(daySellTRY)}',
                      style: context.t.numSmall.copyWith(
                        color: context.c.loss,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ));
                  }
                  if (dayBuyTRY > 0 && daySellTRY > 0) {
                    children.add(TextSpan(
                      text:
                          '\nNet ${dayNet >= 0 ? '+' : '−'}${tryFmt0.format(dayNet.abs())}',
                      style: context.t.numSmall.copyWith(
                        color: context.signColor(dayNet),
                        fontSize: 11,
                      ),
                    ));
                  }
                }

                // İlk nokta (anchor) — birikmiş yatırım toplamı bilgisi
                // (bu döneme kadar tüm buy - sell). Kullanıcı "grafik
                // buradan başlıyor, ne kadar para koydum?" sorusuna
                // cevap alsın.
                if (isFirst && !_simulate && cumBuyTRY > 0) {
                  final cumNet = cumBuyTRY - cumSellTRY;
                  children.add(TextSpan(
                    text: '\nToplam yatırım ${tryFmt0.format(cumNet)}',
                    style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0,
                      color: context.c.text58,
                    ),
                  ));
                }

                final headerLabel = intraday
                    ? DateFormat('HH:mm', 'tr_TR').format(date)
                    : DateFormat('d MMM yyyy', 'tr_TR').format(date);
                return LineTooltipItem(
                  '$headerLabel\n',
                  context.t.bodySmall!.copyWith(
                      color: context.c.text58, fontWeight: FontWeight.w500),
                  children: children,
                );
              }).toList();
            },
          ),
        ),
      );
    }

    // Volume subchart için sync viewport. Aynı controller ZoomableChart ve
    // ZoomableBarChart tarafından paylaşılır → üstte pinch/pan yapılınca
    // alt panel de aynı X aralığına oturur.
    final viewport = _ensureViewport(
      key:
          '${_zoomKey ?? "n/a"}|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$intraday',
      fullMinX: minX,
      fullMaxX: maxX,
    );

    // Volume verisi: gün-bazlı buy/sell TRY. Intraday'de bar chart mantıklı
    // değil (gün içi işlem yoğunluğu farklı bir metrik) → sadece intraday
    // olmayan periyotlarda çizilir.
    final volumeBars = intraday
        ? const <_VolumeBar>[]
        : _computeVolumeBars(allTargetAssets ?? const [], start);
    final showVolume = volumeBars.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 20, 16, 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Column(
        children: [
          ZoomableChart(
            fullMinX: minX,
            fullMaxX: maxX,
            height: 360 - 32,
            builder: buildData,
            viewportController: viewport,
            // Sağdaki Y ekseni rezervi (rightTitles.reservedSize ile aynı).
            // Crosshair bu alana **girmez** — plot area net sınırlı.
            plotPaddingRight: 60,
            onViewportChanged: intraday
                ? null
                : (viewMinX, viewMaxX) {
                    final controller = _zoomController;
                    if (controller == null) return;
                    final from =
                        start.add(Duration(minutes: (viewMinX * 1440).round()));
                    final to =
                        start.add(Duration(minutes: (viewMaxX * 1440).round()));
                    controller.updateViewport(from, to);
                  },
            crosshairSnapX: (x) {
              // Kuyruk dahil TÜM noktalar: piyasa kapalı bölgesinde de
              // crosshair kaymalı (bkz. `crosshairSpots`).
              final spots = crosshairSpots;
              if (spots.isEmpty) return x;
              final clamped = x.clamp(spots.first.x, spots.last.x);
              // Spot'lar X'e göre sıralı → ikili arama (bkz. nearestSpotIndex).
              // Bu callback parmak her kaydığında çağrılıyor.
              return spots[nearestSpotIndex(spots, clamped)].x;
            },
            crosshairLabelBuilder: (x) {
              // x zaten crosshairSnapX ile snap edildi — burada eşleşen spot'u bul.
              // Kaynak `crosshairSnapX` ile AYNI olmalı: farklı listelerde
              // arayınca snap edilen X ile gösterilen değer ayrışırdı.
              final spots = crosshairSpots;
              if (spots.isEmpty) return null;
              final snapped = spots[nearestSpotIndex(spots, x)];
              final date = intraday
                  ? dayKey(start)
                      .add(Duration(minutes: snapped.x.round()))
                  : start.add(Duration(minutes: (snapped.x * 1440).round()));
              final title = fmtTRY(snapped.y);
              // Gün içi etiket normalde yalnızca saat yazar — tek gün
              // çizildiği için tarih gereksiz gürültüydü. Ama piyasa
              // kapalıyken seri BİRDEN ÇOK günü kapsıyor (Cuma→Pazar) ve
              // saat tek başına "Cmt 14:00" ile "Cuma 14:00"ı ayırt
              // ettirmez. Kullanıcı isteği (2026-09-12): "grafik
              // detaylarını gün ve tarih bilgisiyle görebilmeliyim."
              final cokGunlu = intraday && segments.any((s) => s.piyasaKapali);
              final subtitle = intraday
                  ? (cokGunlu
                      ? DateFormat('d MMM · HH:mm', 'tr_TR').format(date)
                      : DateFormat('HH:mm', 'tr_TR').format(date))
                  : DateFormat('d MMM yyyy', 'tr_TR').format(date);
              return (title, subtitle);
            },
            crosshairDetailsBuilder: (x) {
              // Snap edilmiş spot'u bul (crosshairSnapX zaten uyguladı).
              // Kaynak diğer iki callback ile AYNI liste olmalı.
              final spots = crosshairSpots;
              if (spots.isEmpty || _simulate || intraday) return const [];
              // Diğer crosshair callback'leriyle aynı ikili arama.
              final snapped = spots[nearestSpotIndex(spots, x)];
              final tryFmt0 = tryFormatter(digits: 0);
              final firstY = spots.first.y;
              final gain = snapped.y - firstY;
              final date =
                  start.add(Duration(minutes: (snapped.x * 1440).round()));
              final spotDayMs = dayKey(date)
                  .millisecondsSinceEpoch;
              double dayBuy = 0, daySell = 0;
              for (final a in txAssets) {
                if (!a.isActive) continue;
                final addMid = DateTime(
                        a.addedDate.year, a.addedDate.month, a.addedDate.day)
                    .millisecondsSinceEpoch;
                if (addMid != spotDayMs) continue;
                if (a.isBuy) dayBuy += a.totalCostTRY;
                if (a.isSell) daySell += a.totalCostTRY;
              }
              final out = <(String, Color)>[];
              if (gain.abs() > 0.5) {
                final positive = gain >= 0;
                out.add((
                  'Getiri ${positive ? '+' : '−'}${tryFmt0.format(gain.abs())}',
                  positive ? context.c.gain : context.c.loss,
                ));
              }
              if (dayBuy > 0) {
                out.add((
                  'Alım +${tryFmt0.format(dayBuy)}',
                  context.c.gain,
                ));
              }
              if (daySell > 0) {
                out.add((
                  'Satış −${tryFmt0.format(daySell)}',
                  context.c.loss,
                ));
              }
              return out;
            },
          ),
          if (showVolume) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Text(
                'İŞLEM HACMİ',
                style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.text58,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 70,
              child: ListenableBuilder(
                listenable: viewport,
                builder: (_, __) {
                  final vp = viewport;
                  final maxY = volumeBars.fold<double>(
                      0, (m, b) => b.total > m ? b.total : m);
                  // Her bar için 2 spot'lu ayrı bir LineChartBarData → dikey
                  // çubuk. fl_chart'ın BarChart'ında X data-space değil, group
                  // index olduğu için sync viewport için LineChart hilesi kullanıyoruz.
                  final chartMaxY = maxY == 0 ? 1.0 : maxY * 1.15;
                  // En küçük çubuk bile görünür kalsın. Tek büyük alım
                  // ölçeği belirlediğinde küçük işlemler 1px'in altına
                  // düşüp "kırıntı" gibi görünüyordu — panelin %6'sı kadar
                  // bir taban yüksekliği veriyoruz. Ölçek yine gerçek: bu
                  // yalnızca ÇİZİM tabanı, `b.total` değeri değişmiyor.
                  final minVisibleY = chartMaxY * 0.06;
                  final bars = <LineChartBarData>[];
                  for (final b in volumeBars) {
                    final buyPositive = b.buy >= b.sell;
                    final color = buyPositive ? context.c.gain : context.c.loss;
                    final drawY = b.total < minVisibleY ? minVisibleY : b.total;
                    bars.add(LineChartBarData(
                      spots: [FlSpot(b.x, 0), FlSpot(b.x, drawY)],
                      isCurved: false,
                      color: color.withValues(alpha: 0.85),
                      barWidth: 3,
                      isStrokeCapRound: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ));
                  }
                  return LineChart(
                    LineChartData(
                      minX: vp.minX,
                      maxX: vp.maxX,
                      minY: 0,
                      maxY: chartMaxY,
                      clipData: const FlClipData.all(),
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      // ⚠️ Ana grafik sağda 60px'i Y-ekseni etiketlerine
                      // ayırıyor (`rightTitles.reservedSize`). Bu panel hiç
                      // rezerv ayırmazsa AYNI X değeri iki panelde farklı
                      // piksele düşer — çubuklar fiyat grafiğine göre sağa
                      // kayar. Etiketleri gizli ama aynı genişlikte bir
                      // rezerv koyarak iki plot area'yı hizalıyoruz.
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 60,
                            // Etiket yok — yalnızca hizalama rezervi.
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      lineBarsData: bars,
                    ),
                    // Ana grafikle aynı motion token'ları — hacim paneli
                    // periyot değişiminde onunla birlikte morf'lansın, kendi
                    // başına (fl_chart varsayılanı 150ms/linear) kaymasın.
                    duration: SandikMotion.state,
                    curve: SandikMotion.enter,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Gün-bazlı buy/sell TRY hacim. X price chart ile aynı gün-fraction
  /// birimde.
  List<_VolumeBar> _computeVolumeBars(List<Asset> assets, DateTime start) {
    // Ana chart'ın X birimi ile birebir aynı: kesirli gün (1 saat = 1/24).
    //
    // ⚠️ `start` bir DUVAR SAATİ damgasıdır (`endDate.subtract(days)`), yani
    // içinde bugünün saati vardır — gece yarısı değildir. İşlem tarihleri ise
    // gece yarısına normalize. İkisinin farkı bu yüzden negatif-kesirli çıkar
    // ve `~/` sıfıra doğru kırptığı için çubuklar bir gün kayıyor, aynı güne
    // düşenler tamamen eleniyordu ("kesik" görünen hacim paneli).
    //
    // Ana grafik bu hatayı yapmıyor: o `date.difference(startDate).inMinutes /
    // (60*24)` ile KESİRLİ gün üretiyor. Hacim paneli de aynı tabana oturmalı,
    // aksi halde iki panel farklı X uzayında çizilir.
    final startMidnight = dayKey(start);
    // Grafiğin X'i `start`'a göre; gece yarısı ile arasındaki kayma sabit.
    final startOffsetDays =
        startMidnight.difference(start).inMinutes / (60.0 * 24.0);

    final Map<int, ({double buy, double sell})> perDay = {};
    for (final a in assets) {
      if (!a.isActive) continue;
      final dayMidnight =
          dayKey(a.addedDate);
      // Gece yarısı ↔ gece yarısı farkı — tam gün, kırpma sorunu yok.
      final dayIdx = dayMidnight.difference(startMidnight).inDays;
      if (dayIdx < 0) continue;
      final prev = perDay[dayIdx] ?? (buy: 0.0, sell: 0.0);
      if (a.isBuy) {
        perDay[dayIdx] = (buy: prev.buy + a.totalCostTRY, sell: prev.sell);
      } else if (a.isSell) {
        perDay[dayIdx] = (buy: prev.buy, sell: prev.sell + a.totalCostTRY);
      }
    }
    final out = <_VolumeBar>[];
    perDay.forEach((day, tot) {
      if (tot.buy + tot.sell <= 0) return;
      // ⚠️ Çubuk GÜN ORTASINA (+0.5) DEĞİL, günün BAŞINA konur.
      //
      // Fiyat serisinin noktaları `ResolutionTier.normalizeTs` ile GECE
      // YARISINA snap edilir (daily tier'da `DateTime(y, m, d)`), X ekseni
      // tarih etiketleri de aynı anlara düşer. Çubuğu gün ortasına koymak
      // onu fiyat noktasından yarım gün sağa kaydırıyordu — ekranda
      // "çubuklar timeline ile örtüşmüyor" görüntüsünün sebebi buydu.
      //
      // `startOffsetDays` gece yarısı tabanını grafiğin `start` tabanına
      // taşır; ikisi birlikte, çubuğu o günün fiyat noktasıyla BİREBİR
      // aynı X'e oturtur.
      out.add(_VolumeBar(
        x: startOffsetDays + day.toDouble(),
        buy: tot.buy,
        sell: tot.sell,
      ));
    });
    return out;
  }
}

class _VolumeBar {
  final double x;
  final double buy;
  final double sell;
  const _VolumeBar({required this.x, required this.buy, required this.sell});
  double get total => buy + sell;
}

// ── Tür bazlı kâr/zarar dökümü ───────────────────────────────────────────────

/// Seçili dönem ve sekmeye göre HER VARLIK TÜRÜNÜN — ve açıldığında o türün
/// içindeki HER ÜRÜNÜN — dönem değişimi.
///
/// ## Değişmez: satırların toplamı üst kartı TUTAR
/// Üstteki değişim kartı portföyün toplamını verir; bu kart onu önce türlere,
/// tür açıldığında ürünlere ayırır. Üç seviye de **aynı seriden** okur:
///
///   üst kart     → `segments` (historyMap → _convertHistoryToSegments)
///   tür satırı   → `breakdown.byType[t]`
///   ürün satırı  → `breakdown.byPosition[k]`
///
/// `HistoryService.getPortfolioHistoryBreakdownAtResolution` üçünü de TEK
/// döngüde üretir, yani `Σ ürün == tür` ve `Σ tür == toplam` yapısal olarak
/// doğrudur.
///
/// **Bug geçmişi (2026-09-01).** Bu kart eskiden tür başına AYRI bir
/// `getPortfolioHistory(assets, periodDays)` çağırıyordu. O yol üst karttan
/// beş noktada ayrışıyordu ve toplamlar hiçbir zaman tutmuyordu:
///   1. üst kartın son noktası canlı toplamla eziliyor (`currentTotalOverride`),
///      dökümde böyle bir override yoktu;
///   2. üst kart seriyi ilk alım gününe kırpıyor (`firstAssetMidnight`),
///      döküm dönem başından başlıyordu;
///   3. üst kart `effectiveStart` penceresini, döküm ham `periodDays`
///      penceresini kullanıyordu;
///   4. mevduat dökümden tamamen çıkarılmıştı ama üst kartın toplamındaydı;
///   5. dönem başı değeri 0 olan tür (dönem içinde ilk kez alınan varlık)
///      sessizce düşürülüyordu.
/// Hepsi tek kökten geliyordu: iki kart iki farklı veri kaynağı kullanıyordu.
/// Çözüm tek kaynağa indirgemek oldu — yamalarla hizalamak değil.
///
/// ## Formül
/// Her seviyede aynı: tutar `son − ilk`, oran `(son − ilk) / ilk`.
///
/// ## Her varlık KENDİ kategorisinde — sentetik satır yok
/// Sentetik bir "Diğer" satırı **kullanılmaz** (kullanıcı kararı, 2026-09-01).
/// İki sebeple:
///   1. `AssetType.diger` zaten gerçek bir kategori ("Diğer", mor). Sentetik
///      bir satıra aynı adı vermek, biri gerçek biri hesap artığı iki satır
///      üretir ve doğrudan yanlış bilgi verirdi.
///   2. Kategorisiz bakiye diye bir şey yok: `mevduat` ve `diger` dahil her
///      varlık `currentPrice` dalından değer alır ve kendi türüne yazılır.
///
/// Üst kartla tür serileri arasındaki küçük fark (üst kartın son noktası
/// canlı toplamla ezilir, seriler ham gelir) gerçek bir kategori değil, aynı
/// varlıkların birkaç dakikalık fiyat farkıdır — `_calibrate` onu türlerin
/// ağırlığınca dağıtır. `Σ satır == üst kart` yine korunur.
/// "Bu türün gün içi verisi alınamadı" notu.
///
/// ## Neden var
/// Gün içi fiyatı çekilemeyen bir varlık grafikte KAYBOLMAZ — son bilinen
/// fiyatıyla gün boyu sabit çizilir (bkz. `assetSeedTRY`). Bu doğru
/// davranış: varlığı grafikten düşürmek portföyü olduğundan küçük
/// gösterirdi. Ama sessiz kaldığında kullanıcı düz çizgiyi "piyasa durgun"
/// diye okuyor ve uygulamanın bozuk olup olmadığını anlayamıyor —
/// kullanıcı bunu doğrudan sordu: "altın değeri mi alınamıyor acaba".
///
/// Not yalnızca gün içi fiyatı OLMASI GEREKEN türler için çıkar; fon
/// (TEFAS gün içi NAV yayınlamaz), vadeli mevduat ve "diğer" için asla.
class _GunIciVeriYokNotu extends StatelessWidget {
  const _GunIciVeriYokNotu({required this.turler});

  final Set<AssetType> turler;

  @override
  Widget build(BuildContext context) {
    // Sıra deterministik olsun — küme sırası tur başına değişebilir ve
    // aynı ekran her build'de farklı okunurdu.
    final adlar = (turler.map((t) => t.label).toList()..sort()).join(', ');
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 12),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: context.c.text58),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$adlar için gün içi fiyat verisi alınamadı. Bu varlıklar '
              'grafikte son bilinen fiyatlarıyla SABİT çizildi — çizginin '
              'düz olması piyasanın durgun olduğu anlamına gelmez.',
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grafik alanının "çizilecek bir şey yok" hâli.
///
/// Spinner bir SÖZDÜR: "bekle, veri geliyor". Gelmeyecekse o söz tutulmaz.
/// Portföyde bulunmayan bir tür seçildiğinde `HistoryService` boş varlık
/// listesine boş seri döndürür; ekran eskiden burada da spinner çizip
/// sonsuza kadar döndürüyordu. Beklenecek bir şey yoksa sebebini söyle.
class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Tür rengi — boş durum bile seçili çipin kimliğini taşısın.
  final Color? iconColor;

  /// Yalnızca "veri alınamadı" hâlinde verilir; gerçek boş durumda tekrar
  /// denenecek bir şey yok.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(SandikSpace.md),
              decoration: BoxDecoration(
                color:
                    (iconColor ?? context.c.amberFill).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, size: 28, color: iconColor ?? context.c.amberText),
            ),
            const SizedBox(height: SandikSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.t.titleMedium?.copyWith(
                color: context.c.text90,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: SandikSpace.md),
              SandikTappable(
                onTap: onRetry,
                haptic: SandikHaptic.medium,
                semanticLabel: 'Tekrar dene',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.lg,
                    vertical: SandikSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: SandikRadius.mdAll,
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    'Tekrar Dene',
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.amberText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeBreakdownCard extends StatefulWidget {
  /// Grafiğin çizdiği seriyle AYNI istekten gelen dağılım.
  final PortfolioHistoryBreakdown breakdown;

  /// Üst kartın gösterdiği dönem başı/sonu değerleri. Döküm bunlara
  /// kalibre edilir — bkz. `_rows`.
  final double totalFirst;
  final double totalLast;

  final List<List<Asset>> ownerLots;
  final DateTime start;
  final DateTime end;
  final bool simulate;

  const _TypeBreakdownCard({
    required this.breakdown,
    required this.totalFirst,
    required this.totalLast,
    required this.ownerLots,
    required this.start,
    required this.end,
    required this.simulate,
  });

  @override
  State<_TypeBreakdownCard> createState() => _TypeBreakdownCardState();
}

/// Tek bir döküm satırı — tür ya da ürün.
class _BreakdownRow {
  final String label;
  final double first;
  final double last;

  /// Dönem içi net alım/satım (TRY). Yalnızca gerçek modda dolar.
  final double flow;

  const _BreakdownRow({
    required this.label,
    required this.first,
    required this.last,
    this.flow = 0,
  });

  double get change => last - first;
  double? get pct => first > 0 ? (change / first) * 100 : null;
}

class _TypeBreakdownCardState extends State<_TypeBreakdownCard> {
  /// Açık tür başlıkları. Varsayılan kapalı — kart uzun olmasın.
  final Set<AssetType> _expanded = {};

  /// Bir serinin dönem başı ve sonu değeri.
  ///
  /// `null` dönerse o seri çizilemez (tek nokta ya da hiç nokta). Üst kartla
  /// aynı kural: iki nokta yoksa değişim tanımsızdır.
  ({double first, double last})? _endpoints(Map<int, double>? series) {
    if (series == null || series.length < 2) return null;
    final ts = series.keys.toList()..sort();
    return (first: series[ts.first]!, last: series[ts.last]!);
  }

  /// Dönem içi net para akışı — tür bazında.
  ///
  /// Not satırı için: kullanıcı "+%100" görünce ne kadarının kendi parası
  /// olduğunu bilmeli. Simülasyonda miktar sabit sayıldığı için akış yoktur.
  Map<AssetType, double> _flowByType() {
    final out = <AssetType, double>{};
    if (widget.simulate) return out;
    final startMs =
        dayKey(widget.start)
            .millisecondsSinceEpoch;
    final endMs =
        DateTime(widget.end.year, widget.end.month, widget.end.day, 23, 59, 59)
            .millisecondsSinceEpoch;
    for (final lots in widget.ownerLots) {
      for (final a in lots) {
        if (!a.isActive) continue;
        final ms = a.addedDate.millisecondsSinceEpoch;
        if (ms < startMs || ms > endMs) continue;
        final f = a.isBuy
            ? a.totalCostTRY
            : a.isSell
                ? -a.sellProceedsTRY
                : 0.0;
        if (f != 0) out[a.type] = (out[a.type] ?? 0) + f;
      }
    }
    return out;
  }

  /// Tür satırları + her türün altındaki ürün satırları.
  ///
  /// ## "Diğer" satırı ve kalibrasyon
  /// Tür serilerinin toplamı üst kartın rakamını genellikle tutar ama HER
  /// ZAMAN değil: üst kart son noktayı canlı toplamla eziyor
  /// (`currentTotalOverride`) ve mevduat gibi fiyat serisi olmayan varlıklar
  /// hiçbir tür serisinde yer almıyor. Aradaki artık **"Diğer"** satırına
  /// yazılır. Böylece satırların toplamı üst kartı **tanım gereği** tutar:
  /// artık ne kadarsa o kadar, sıfırsa satır hiç çıkmaz.
  (
    List<({AssetType type, _BreakdownRow row})>,
    Map<AssetType, List<_BreakdownRow>>
  ) _rows() {
    final flowOf = _flowByType();
    final typeRows = <({AssetType type, _BreakdownRow row})>[];
    final childrenOf = <AssetType, List<_BreakdownRow>>{};

    double sumFirst = 0;
    double sumLast = 0;

    for (final e in widget.breakdown.byType.entries) {
      final ep = _endpoints(e.value);
      if (ep == null) continue;
      sumFirst += ep.first;
      sumLast += ep.last;
      typeRows.add((
        type: e.key,
        row: _BreakdownRow(
          label: e.key.label,
          first: ep.first,
          last: ep.last,
          flow: flowOf[e.key] ?? 0,
        ),
      ));

      // Ürün satırları — aynı türe ait pozisyonlar.
      final kids = <_BreakdownRow>[];
      for (final p in widget.breakdown.byPosition.entries) {
        if (widget.breakdown.positionType[p.key] != e.key) continue;
        final pep = _endpoints(p.value);
        if (pep == null) continue;
        kids.add(_BreakdownRow(
          label: _positionLabel(p.key, e.key),
          first: pep.first,
          last: pep.last,
        ));
      }
      kids.sort((a, b) => b.change.compareTo(a.change));
      if (kids.isNotEmpty) childrenOf[e.key] = kids;
    }

    // ── Artığı ORANSAL dağıt — sahte satır AÇMA ──────────────────────────
    //
    // Tür serilerinin toplamı üst kartı birebir tutmayabilir: üst kartın son
    // noktası canlı toplamla eziliyor (`currentTotalOverride`), tür serileri
    // ise ham seriden geliyor. Aradaki fark gerçek bir kategori DEĞİLDİR —
    // aynı varlıkların bir kaç dakikalık fiyat farkıdır.
    //
    // Eskiden bu artık "Diğer" adlı sentetik bir satıra yazılıyordu. İki
    // sebeple yanlıştı:
    //   1. `AssetType.diger` ZATEN var ("Diğer", mor) — kullanıcının gerçek
    //      bir kategorisi. Aynı adı taşıyan iki satır, biri gerçek biri
    //      hesap artığı, doğrudan yanlış bilgi verirdi.
    //   2. Her varlık zaten bir kategoriye ait; `mevduat` ve `diger` dahil
    //      hepsi `currentPrice` dalından değer alıyor. Kategorisiz bakiye
    //      diye bir şey yok.
    //
    // Doğrusu: artığı türlerin AĞIRLIĞINCA dağıtmak. Böylece
    // `Σ satır == üst kart` korunur ve fazladan kavram uydurulmaz.
    _calibrate(typeRows, childrenOf, sumFirst, sumLast);

    // En çok kazandıran üstte.
    typeRows.sort((a, b) => b.row.change.compareTo(a.row.change));
    return (typeRows, childrenOf);
  }

  /// Tür (ve ürün) satırlarını üst kartın uçlarına oransal olarak kalibre eder.
  ///
  /// Ölçek çarpanı `üstKart / serilerToplamı`. Her satır kendi ağırlığınca pay
  /// alır, dolayısıyla satırların toplamı üst kartı tutar ama satırlar arası
  /// oranlar (yani hangi tür ne kadar kazandırdı) hiç bozulmaz.
  ///
  /// Ürün satırları da AYNI çarpanla ölçeklenir — aksi halde bir tür açıldığında
  /// içindekilerin toplamı başlığı tutmazdı.
  void _calibrate(
    List<({AssetType type, _BreakdownRow row})> rows,
    Map<AssetType, List<_BreakdownRow>> childrenOf,
    double sumFirst,
    double sumLast,
  ) {
    // Sıfıra bölünemez; seri yoksa kalibre edilecek bir şey de yok.
    var kFirst = sumFirst.abs() > 0.01 ? widget.totalFirst / sumFirst : 1.0;
    var kLast = sumLast.abs() > 0.01 ? widget.totalLast / sumLast : 1.0;

    // ⚠️ ÇAPRAZ BULAŞMA SINIRI.
    //
    // Kalibrasyon TEK bir çarpanla çalışır: bir türdeki sapmayı tüm türlere
    // yayar. Küçük artıklarda (üst kart `pState.toTRY` kurlarını, servis
    // kendi kurunu kullanır — binde birkaç fark) bu zararsızdır ve toplamı
    // tutturur. Ama çarpan 1'den belirgin uzaklaşırsa satırlar YALAN söyler:
    // fiyatı hiç değişmemiş bir tür, başka bir tür oynadığı için oynamış
    // görünür. Bu hata gün içi serisinde ölçüldü (fon 25.000 → 16.716) ve
    // orada canlı değerleri tür bazında hesaplayarak kökten çözüldü.
    //
    // Burada kalan artık küçük olmalı; büyükse kalibre ETME. Toplamda birkaç
    // TL sapma göstermek, her satırı yanlış göstermekten iyidir.
    const maxSapma = 0.02; // %2
    if ((kFirst - 1).abs() > maxSapma) kFirst = 1.0;
    if ((kLast - 1).abs() > maxSapma) kLast = 1.0;

    // Çarpan 1'e çok yakınsa dokunma — kayan nokta gürültüsüyle oynamayalım.
    if ((kFirst - 1).abs() < 1e-9 && (kLast - 1).abs() < 1e-9) return;

    _BreakdownRow scaled(_BreakdownRow r) => _BreakdownRow(
          label: r.label,
          first: r.first * kFirst,
          last: r.last * kLast,
          flow: r.flow,
        );

    for (var i = 0; i < rows.length; i++) {
      rows[i] = (type: rows[i].type, row: scaled(rows[i].row));
    }
    for (final e in childrenOf.entries) {
      childrenOf[e.key] = [for (final k in e.value) scaled(k)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final (typeRows, childrenOf) = _rows();
    if (typeRows.isEmpty) return const SizedBox.shrink();

    final tryFmt =
        tryFormatter(digits: 0);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: SandikSpace.md, vertical: 14),
      decoration: context.surfaceCard(radius: SandikRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TÜRE GÖRE DEĞİŞİM',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: context.c.text36,
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          for (final entry in typeRows) ...[
            _typeTile(context, entry.type, entry.row, childrenOf, tryFmt),
            if (entry != typeRows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// Tür satırı — ürünü varsa dokunulabilir ve açılır.
  Widget _typeTile(
    BuildContext context,
    AssetType type,
    _BreakdownRow row,
    Map<AssetType, List<_BreakdownRow>> childrenOf,
    NumberFormat tryFmt,
  ) {
    // Ürünü olan HER tür açılır — döviz, mevduat, "Diğer" dahil (kullanıcı
    // kararı, 2026-09-01).
    //
    // Eskiden eşik `kids.length > 1` idi: tek ürünlü tür açılmıyordu, çünkü
    // "kendi kopyasını göstermek bilgi katmaz" diye düşünülmüştü. Ama bu
    // *tutarlılığı* bozuyordu — Apple'ın "familiarity" ilkesi: aynı görünen
    // şeyler aynı davranmalı. Kullanıcı bir satırın açılıp açılmayacağını
    // önceden kestiremiyordu, üstelik tek ürünlü satır o ürünün ADINI
    // (ör. hangi fon olduğunu) göstermiyordu — bu bilgi kayıptı.
    final kids = childrenOf[type] ?? const <_BreakdownRow>[];
    final canExpand = kids.isNotEmpty;
    final isOpen = _expanded.contains(type);

    final header = _row(
      context,
      tryFmt,
      label: row.label,
      dotColor: type.color,
      value: row.last,
      cost: row.first,
      flow: row.flow,
      // Chevron GİDİLECEK yönü işaret eder (Apple: "hint in the direction of
      // the gesture"). Kapalıyken sağa bakar — "burada devamı var"; açıkken
      // 90° dönüp aşağıyı gösterir, yani içeriğin çıktığı yönü. Ara kareler
      // sonucu telegraflar, körlemesine interpolasyon yapmaz.
      trailing: canExpand
          ? AnimatedRotation(
              turns: isOpen ? 0.25 : 0,
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              child: Icon(Icons.chevron_right_rounded,
                  size: 18,
                  // Açıkken biraz belirginleşir: hangi başlığın açık olduğu
                  // renkten de okunur, yalnızca açıdan değil.
                  color: isOpen ? context.c.text58 : context.c.text36),
            )
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canExpand)
          // `SandikTappable`: basma geri bildirimi (scale), haptic ve
          // `Semantics(button: true)` bir arada. Ham `GestureDetector`
          // bunların HİÇBİRİNİ vermiyordu — dokunulabilir bir satırın
          // dokunulduğunu belli etmemesi ekranın geri kalanıyla da çelişiyordu.
          SandikTappable(
            semanticLabel: isOpen
                ? '${row.label}, açık. Kapatmak için çift dokun.'
                : '${row.label}, kapalı. İçindeki ürünleri görmek için '
                    'çift dokun.',
            onTap: () => setState(() {
              if (!_expanded.remove(type)) _expanded.add(type);
            }),
            // 44pt dokunma hedefi: satır kendi başına ~36pt, dikey 6+6 ile
            // eşiğe çıkar (HIG minimumu). `ConstrainedBox` büyük metin
            // ayarında satır zaten uzadığında fazladan yer kaplamaz.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: header,
              ),
            ),
          )
        else
          header,
        // ── Ürün satırları ────────────────────────────────────────────────
        //
        // **Uzamsal süreklilik (Apple).** "Bir şey nasıl kayboluyorsa oradan
        // geri gelmeli." Ürünler başlığın ALTINDAN doğar: `align: -1.0` ile
        // üst kenardan açılır, düz bir opacity geçişi değil. Kapanırken de
        // aynı yolu izler — çıkış ve giriş simetriktir, yoksa içerik bir
        // yerden gelip başka yere gidiyormuş gibi kopuk hissedilir.
        //
        // `ClipRect` şart: açılırken taşan kısım başlığın üstüne binmesin.
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: isOpen ? 1.0 : 0.0,
            duration: SandikMotion.stateOf(context),
            curve: SandikMotion.enter,
            child: AnimatedOpacity(
              opacity: isOpen ? 1.0 : 0.0,
              // Opaklık boyuttan biraz HIZLI kapanır: kapanırken içerik önce
              // soluklaşır, sonra yer kapanır — ters sırada olsaydı boş bir
              // beyaz alan bir an görünürdü.
              duration: SandikMotion.stateOf(context),
              curve: SandikMotion.enter,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Column(
                  children: [
                    for (final k in kids) ...[
                      _row(
                        context,
                        tryFmt,
                        label: k.label,
                        dotColor: type.color.withValues(alpha: 0.45),
                        value: k.last,
                        cost: k.first,
                        flow: 0,
                        dense: true,
                      ),
                      if (k != kids.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    NumberFormat tryFmt, {
    required String label,
    required Color dotColor,
    required double value,
    required double cost,
    required double flow,
    Widget? trailing,
    bool dense = false,
  }) {
    final pnl = value - cost;
    final pct = cost > 0 ? (pnl / cost) * 100 : null;

    // Yuvarlanmış tutar sıfırsa nötr renk — yeşil "kazanç var" yanılgısı
    // yaratır. Ekranın geri kalanıyla aynı kural.
    final isFlat = pnl.abs().round() == 0 && (pct?.abs() ?? 0) < 0.005;
    final color = isFlat
        ? context.c.text36
        : context.signColor(pnl);

    // Ekran okuyucu için tek parça cümle — `portfolio_summary_widget` ile aynı
    // kalıp. Parçalı okunursa "Altın", "+₺12.500", "%3,20" diye üç kopuk
    // duyuru olur ve yön bilgisi (kazanç mı kayıp mı) YALNIZCA renkte kalırdı;
    // renk tek başına bilgi taşıyamaz. Sayıların işareti görsel tarafta bu
    // rolü üstlenir ("+" / "−"), burada kelimeyle söylüyoruz.
    final semanticLabel = [
      label,
      if (isFlat)
        'değişim yok'
      else ...[
        '${pnl >= 0 ? 'kazanç' : 'kayıp'} ${tryFmt.format(pnl.abs())}',
        if (pct != null) fmtPct(pct.abs(), digits: 2),
      ],
      if (!widget.simulate && flow.abs() > 0.5)
        flow > 0
            ? 'dönem içi alım ${tryFmt.format(flow)}'
            : 'dönem içi satış ${tryFmt.format(flow.abs())}',
    ].join(', ');

    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: _rowVisual(
          context,
          tryFmt,
          label: label,
          dotColor: dotColor,
          flow: flow,
          trailing: trailing,
          dense: dense,
          pnl: pnl,
          pct: pct,
          isFlat: isFlat,
          color: color,
        ),
      ),
    );
  }

  /// Satırın görsel gövdesi — semantik sarmalayıcıdan ayrı tutulur ki
  /// `ExcludeSemantics` altındaki ağaç sade kalsın.
  Widget _rowVisual(
    BuildContext context,
    NumberFormat tryFmt, {
    required String label,
    required Color dotColor,
    required double flow,
    required Widget? trailing,
    required bool dense,
    required double pnl,
    required double? pct,
    required bool isFlat,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tür/ürün rozeti — renk tek başına bilgi taşımaz, etiket her zaman var.
        Container(
          width: dense ? 6 : 8,
          height: dense ? 6 : 8,
          margin: EdgeInsets.only(top: dense ? 6 : 5, right: 8),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dense
                    ? context.t.bodySmall?.copyWith(color: context.c.text58)
                    : context.t.bodyMedium?.copyWith(color: context.c.text90),
              ),
              // Gerçek modda dönem içi işlem varsa belirt. Simülasyonda bu
              // satır hiç çıkmaz — orada miktar sabit sayılır.
              if (!widget.simulate && flow.abs() > 0.5)
                Text(
                  flow > 0
                      ? 'Dönem içi alım ${tryFmt.format(flow)}'
                      : 'Dönem içi satış ${tryFmt.format(flow.abs())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall
                      ?.copyWith(color: context.c.text36, fontSize: 11),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Tutar + yüzde. FittedBox: milyonluk portföyde dar ekranda punto
        // düşsün, satır kırılmasın.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFlat
                      ? '—'
                      : '${pnl >= 0 ? '+' : '−'}${tryFmt.format(pnl.abs())}',
                  maxLines: 1,
                  style: context.t.numSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: dense ? 12 : null),
                ),
                if (pct != null && !isFlat)
                  Text(
                    fmtPct(pct.abs(), digits: 2),
                    maxLines: 1,
                    style: context.t.numSmall.copyWith(
                        color: color.withValues(alpha: 0.85), fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing,
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class TransactionSegment {
  final List<FlSpot> spots;
  final Color lineColor;
  final Color areaGradientStart;
  final Color areaGradientEnd;
  final double thickness;

  /// Bu segment piyasa KAPALIYKEN taşınan son fiyat mı?
  ///
  /// Hafta sonu gün içi grafiği Cuma kapanışını bugüne kadar uzatıyor
  /// (bkz. `HistoryService.gunIciSagUc`). O kuyruk gerçek işlem değildir:
  /// tek bir fiyatın yayılmasıdır. Düz çizgi olarak çizilirse "fiyat hiç
  /// oynamadı" diye okunur — oysa borsa kapalıydı.
  ///
  /// `true` olduğunda çizgi GRİ ve KESİKLİ çizilir, altındaki alan
  /// doldurulmaz. Kullanıcı isteği (2026-09-12): "cmt ve pazar günü için
  /// piyasa kapalı ibaresi olup gri şekilde çizilecek."
  final bool piyasaKapali;

  TransactionSegment(
      {required this.spots,
      required this.lineColor,
      required this.areaGradientStart,
      required this.areaGradientEnd,
      required this.thickness,
      this.piyasaKapali = false});
}

/// Yarış (leaderboard) ekranını açan küçük ikon buton — grafik container
/// üstünde, fullscreen chip'inin solunda. Opt-in ve partner varsa gösterilir.
class _LeaderboardChip extends StatelessWidget {
  final VoidCallback onTap;
  const _LeaderboardChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.amberFill.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border:
                Border.all(color: context.c.amberFill.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded,
                  size: 13, color: context.c.amberText),
              const SizedBox(width: 4),
              Text(
                'YARIŞ',
                style: context.t.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.amberText,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Portfolio ekranı grafik container'ının üstündeki "genişlet" ikon butonu.
class _PortfolioFullscreenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _PortfolioFullscreenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(color: context.c.hairline),
          ),
          child: Icon(
            Icons.fullscreen_rounded,
            size: 16,
            color: context.c.text58,
          ),
        ),
      ),
    );
  }
}

/// `positionKey` insan-okunur etikete çevrilir.
///
/// Anahtar `type|core|currency` biçimindedir (bkz. `positionKey`); `core`
/// altında `sub:` öneki altın/döviz alt kategorisini, `name:` öneki
/// ticker'sız varlığın adını taşır. Ham anahtarı ekrana basmak
/// "altin|sub:çeyrek|TRY" gibi bir şey gösterirdi.
///
/// **Neden üst seviyeye çıktı:** iki yer okuyor — tür dökümü kartı ve Özet
/// sekmesinin en iyi/en zayıf satırları. Kopyalamak bu projede ons→gram
/// formülünü beş yere dağıtan sınıf hatanın aynısıydı.
String _positionLabel(String key, AssetType type) {
  final parts = key.split('|');
  var core = parts.length > 1 ? parts[1] : key;
  if (core.startsWith('sub:')) core = core.substring(4);
  if (core.startsWith('name:')) core = core.substring(5);
  if (core.isEmpty) return type.label;
  // Alt kategoriler küçük harfle saklanır (`positionKey`), ticker'lar büyük.
  // İlk harfi büyüterek "çeyrek" → "Çeyrek" yapıyoruz; ticker'a dokunmaz.
  return core.length > 1
      ? core[0].toUpperCase() + core.substring(1)
      : core.toUpperCase();
}

/// Özet sekmesinin AĞA ÇIKAN yan verilerini toplar: TÜFE ve yüzdelik dilim.
///
/// **Neden ayrı bir StatefulWidget:** ikisi de ağ çağrısı ve ana ekran her
/// `setState`'te (30 sn'lik gün içi tick dahil) yeniden çiziliyor. Çağrılar
/// `_buildOzetSekmesi` içinde yapılsaydı her tick'te tekrar atılırdı. Burada
/// `initState` bir kez ister; dönem değişince `didUpdateWidget` yeniden
/// ister.
///
/// Sessizce başarısız olur: TÜFE tablosu boş doğuyor (`InflationService`
/// "veri yoksa özellik yoktur" diyor) ve yüzdelik dilim k-anonimlik
/// eşiğinin altında null döner. İkisi de null iken özet yine gösterilir —
/// yalnızca o bloklar çizilmez.
class _OzetYanVeri extends ConsumerStatefulWidget {
  final SummaryPeriod period;
  final PeriodSummary summary;
  final PortfolioCharacter? karakter;
  final RecapAsset? enSabirli;
  final int? enSabirliGun;

  /// Uzun pencere bağlamı için gereken varlıklar ve akış kuralı.
  final List<Asset> assets;

  const _OzetYanVeri({
    required this.period,
    required this.summary,
    required this.assets,
    this.karakter,
    this.enSabirli,
    this.enSabirliGun,
  });

  @override
  ConsumerState<_OzetYanVeri> createState() => _OzetYanVeriState();
}

class _OzetYanVeriState extends ConsumerState<_OzetYanVeri> {
  double? _enflasyon;

  /// Kayıp döneminde gösterilen "daha uzun pencere" bağlamı (1Y getirisi).
  ///
  /// "Bu ay ekside. Daha uzun pencerede hâlâ +%31,8." cümlesinin ikinci
  /// yarısı. `RETENTION_STRATEJISI.md` §8 kayıp anında ya SUSMAYI ya BAĞLAM
  /// VERMEYİ şart koşuyor; ekran sustuğunda kullanıcı yalnız bir kırmızı
  /// rakam görür, o yüzden bağlam tercih edildi.
  ///
  /// Ayrı bir istek: ekranın elindeki `breakdown` yalnızca SEÇİLİ dönemi
  /// kapsıyor, 1Y rakamı onun içinde yok. Yalnızca gerçekten gerektiğinde
  /// (kayıptaki kısa dönemde) atılır.
  double? _uzunDonem;
  bool _uzunDonemIstendi = false;

  /// 6A benchmark şeridinin yüzdelik dilimi. `null` iken şerit çizilmez —
  /// bayrak kapalı, opt-in yok, geçmiş yetersiz ya da k-anonimlik eşiği
  /// dolmamış olabilir; dördü de "gösterme" demek.
  ({int percentile, int total})? _dilim;
  bool _dilimIstendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void didUpdateWidget(_OzetYanVeri old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _enflasyon = null;
      // 1Y bağlamı dönemden bağımsız (hep 12 ay geri) ama KAPISI döneme
      // bağlı: yeni dönem kayıptaysa ve önceki değilse istek hiç
      // atılmamıştır, bu yüzden bayrak da sıfırlanır.
      _uzunDonemIstendi = false;
      // Dilim YALNIZCA 6A'da isteniyor; başka bir dönemden 6A'ya
      // geçildiğinde istek hiç atılmamış olur. Bayrağı sıfırlamak o
      // geçişte şeridin görünmesini sağlar. `_dilim`'in kendisi
      // korunuyor: 6A'ya geri dönen kullanıcı aynı rakamı yeniden
      // beklemeden görür (havuz 24 saatlik pencerede zaten sabit).
      _dilimIstendi = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
    }
  }

  Future<void> _yukle() async {
    if (!mounted) return;

    await _yukleUzunDonem();
    await _yukleDilim();

    // GÜNLÜK'te TÜFE sorulmaz: endeks AYLIK yayımlanıyor, bir günlük
    // pencerede enflasyon farkı tanımsız.
    if (widget.period == SummaryPeriod.gunluk) return;

    final enf =
        await InflationService.instance.inflationForPeriod(widget.period.days);
    if (!mounted) return;
    setState(() => _enflasyon = enf);
  }

  /// 6A yüzdelik dilimini çeker — benchmark şeridi için.
  ///
  /// Dört kapı, `PercentileStrip` ile aynı disiplin: dönem 6A olmalı,
  /// Remote Config bayrağı açık olmalı, kullanıcı yarışa opt-in olmalı ve
  /// oturum açmış olmalı. Sunucudaki k-anonimlik eşiği beşinci kapı —
  /// havuz 8 kişiye ulaşmadıysa RPC boş döner ve şerit hiç çizilmez.
  ///
  /// **Snapshot burada yükleniyor.** `get_percentile_bucket` yalnızca son
  /// 24 saatte snapshot atmış kullanıcıları karşılaştırıyor; yüklemeyi
  /// atlarsak kullanıcı kendi havuzunda görünmez ve kendi dilimini asla
  /// göremez (`PercentileStrip` içindeki aynı not).
  ///
  /// 180 kovası migration `0051` ile açıldı; ondan önce RPC bu periyodu
  /// geçersiz sayıp boş dönüyordu.
  Future<void> _yukleDilim() async {
    if (_dilimIstendi) return;
    if (widget.period != SummaryPeriod.altiAy) return;
    _dilimIstendi = true;

    if (!RemoteConfigService.instance.percentileStripEnabled) return;
    if (!ref.read(leaderboardOptInProvider)) return;
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    if (widget.assets.isEmpty) return;

    final pState = ref.read(portfolioProvider).valueOrNull;
    if (pState == null) return;

    try {
      final servis = LeaderboardService.instance;
      const gun = 180;
      final roi = await servis.computeROI(
        assets: widget.assets,
        periodDays: gun,
        currentValueTRY: servis.totalValueTRY(widget.assets, pState.toTRY),
        toTRY: pState.toTRY,
        cacheKey: me.id,
      );
      // Geçmiş yetersiz — karşılaştırma yapılamaz, uydurma bir dilim
      // gösterilmez.
      if (roi == null || !mounted) return;

      await servis.uploadRoiSnapshot(
        userId: me.id,
        periodDays: gun,
        roiPct: roi,
      );
      final data = await servis.fetchPercentile(gun);
      if (!mounted || data == null) return;

      AnalyticsService.instance
          .logPercentileViewed(bucket: data.percentile, periodDays: gun);
      setState(() => _dilim = data);
    } catch (_) {
      // Sessizce vazgeç: şerit ikincil, özet onsuz da tam.
    }
  }

  /// 1Y bağlamını çeker — YALNIZCA gerektiğinde.
  ///
  /// Üç kapı: dönem kayıpta olmalı, dönem 1Y'nin kendisi olmamalı (bir
  /// pencereyi kendisiyle karşılaştırmak bilgi taşımaz) ve daha önce
  /// istenmemiş olmalı. Kapılar olmadan bu istek her sekme geçişinde
  /// atılırdı; oysa cümle ancak kayıpta gösteriliyor.
  Future<void> _yukleUzunDonem() async {
    if (_uzunDonemIstendi) return;
    if (!widget.summary.isNegative) return;
    if (widget.period == SummaryPeriod.birYil) return;
    if (widget.assets.isEmpty) return;
    _uzunDonemIstendi = true;

    try {
      final now = DateTime.now();
      final from = PeriodSummaryService.donemBaslangici(now, 12);
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: widget.assets,
        from: from,
        to: now,
        tier: ResolutionTierMeta.pickForSpan(
            SummaryPeriod.birYil.days.toDouble()),
      );
      if (!mounted) return;

      final yil = PeriodSummaryService.compute(
        period: SummaryPeriod.birYil,
        assets: widget.assets,
        breakdown: bd,
        now: now,
      );
      if (yil.getiriPct == null) return;
      setState(() => _uzunDonem = yil.getiriPct);
    } catch (_) {
      // Sessizce vazgeç: bağlam cümlesi ikincil. Ana rakam ve köprü zaten
      // çizilmiş durumda ve kayıp tonu bağlam olmadan da doğru
      // (`tonCumlesi` uzunDonemPct null iken nötr cümleye düşüyor).
    }
  }

  @override
  Widget build(BuildContext context) {
    // TÜFE farkı burada bağlanır: servis saf ve ağa çıkmıyor, bu yüzden
    // hesabı yapılmış özeti enflasyonla yeniden kurmak yerine yalnızca
    // farkı hesaplayıp view'a veriyoruz.
    final s = widget.summary;
    final tufe = (_enflasyon != null && s.getiriPct != null)
        ? InflationService.spreadPoints(s.getiriPct!, _enflasyon!)
        : null;
    final gosterilen = tufe == null ? s : _tufeIle(s, tufe);

    // Paylaşım metni ENFLASYON BAĞLANDIKTAN SONRAKİ özetten üretilir:
    // `gosterilen` yerine `s` verilirse "enflasyonun X puan önündeyim"
    // satırı metne hiç girmez.
    //
    // Metin null ise (ölçülebilir yüzde yok) buton HİÇ çizilmez: içinde tek
    // bir sayı olmayan bir kart paylaşılmaz.
    final paylasimMetni = PeriodSummaryService.shareText(
      gosterilen,
      karakter: widget.karakter,
    );

    return PeriodSummaryView(
      summary: gosterilen,
      uzunDonemPct: widget.period == SummaryPeriod.birYil ? null : _uzunDonem,
      karakter: widget.karakter,
      enSabirli: widget.enSabirli,
      enSabirliGun: widget.enSabirliGun,
      percentile: _dilim?.percentile,
      percentileKatilimci: _dilim?.total,
      onShare: paylasimMetni == null ? null : () => _paylas(paylasimMetni),
    );
  }

  Future<void> _paylas(String metin) async {
    AnalyticsService.instance.logRecapShared(
      period: widget.period.name,
      channel: 'system_sheet',
    );
    await Share.share(metin,
        subject: 'sandık · ${PeriodSummaryService.donemAdi(widget.period)}');
  }

  /// Özetin TÜFE alanı doldurulmuş kopyası.
  ///
  /// `PeriodSummary` değişmez (`@immutable` disiplini) ve `copyWith`
  /// taşımıyor — tek alan için eklemek yerine burada yeniden kuruluyor.
  PeriodSummary _tufeIle(PeriodSummary s, double tufe) => PeriodSummary(
        period: s.period,
        start: s.start,
        end: s.end,
        baslangicTRY: s.baslangicTRY,
        sonTRY: s.sonTRY,
        katkiTRY: s.katkiTRY,
        piyasaTRY: s.piyasaTRY,
        getiriPct: s.getiriPct,
        enIyi: s.enIyi,
        enZayif: s.enZayif,
        tufeFarki: tufe,
        dagilimBasi: s.dagilimBasi,
        dagilimSonu: s.dagilimSonu,
        sparkline: s.sparkline,
        gunSayimi: s.gunSayimi,
      );
}
