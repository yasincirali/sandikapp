import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/delete_asset_dialog.dart';
import '../utils/chart_line_width.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/spot_lookup.dart';
import '../widgets/modern_tab_selector.dart';
import '../services/history_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/zoomable_chart.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/preferences_provider.dart';
import '../widgets/fullscreen_chart_route.dart';
import '../widgets/chart_fullscreen_chip.dart';
import '../widgets/transaction_segment.dart';
import 'signal_settings_screen.dart';
import '../models/signal_alert.dart';
import '../providers/signal_provider.dart';
import '../models/asset_categories.dart';
import '../services/tefas_service.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/alarm_kur_sheet.dart';
import '../widgets/alarm_seridi.dart';

part 'asset_detail/eylemler.dart';
part 'asset_detail/sinyal_widgetlari.dart';
part 'asset_detail/seritler.dart';
part 'asset_detail/karsilastirma_secici.dart';

// ── Models ───────────────────────────────────────────────────────────────────

// ── Teknik Sinyal Paneli ─────────────────────────────────────────────────────

// ── Kayıtlı sinyal rozeti ────────────────────────────────────────────────────

// ── Sinyal dağılımı: oran çubuğu + gruplu gösterge listesi ───────────────────

// ─────────────────────────────────────────────────────────────────────────────

// ── Widget ───────────────────────────────────────────────────────────────────

class AssetDetailScreen extends ConsumerStatefulWidget {
  final Asset asset;
  final bool showBackButton;
  /// Aggregate edilmiş pozisyonun tüm lot'ları (buy + sell). Grafik üstünde
  /// işlem marker'ları çizmek için kullanılır. Boş bırakılırsa sadece
  /// [asset]'in kendisi tek buy olarak varsayılır.
  final List<Asset>? lots;
  /// Landscape fullscreen'de açılınca grafik hemen görünsün diye body
  /// başlangıçta bu offset kadar aşağı kayar. Kullanıcı yukarı swipe ile
  /// header'a döner.
  final double initialScrollOffset;

  /// Açılışta seçili olacak periyot (`_allPeriods[].days`). null → varsayılan.
  ///
  /// **Neden gerekli:** fiyat alarmı bildirimine dokunan kullanıcı TEK BİR
  /// SEANSI sorar ("altın hedefi geçti, bugün ne oldu?"), trendi değil.
  /// Varsayılan sekme (1H) o soruyu cevaplamıyordu ve kullanıcı her seferinde
  /// elle GÜNLÜK'e geçiyordu.
  ///
  /// Desteklenmeyen bir değer (örn. elle fiyatlanan varlıkta `days: 0`)
  /// sessizce YOK SAYILIR ve varsayılan seçilir — bkz. `_gunIciDestekli`.
  final int? initialPeriodDays;

  /// Yalnızca dönem seçici + grafik; çubuk, sekmeler, şeritler ve grafik
  /// altı yok. Tam ekran route'u bununla açar (bkz. `FullscreenChartRoute`
  /// — eski `initialScrollOffset: 240` yolu tüm sayfayı kaydırarak
  /// basıyordu, yatayda "izlenebilir" değildi).
  final bool sadeceGrafik;

  const AssetDetailScreen({
    super.key,
    required this.asset,
    this.showBackButton = false,
    this.lots,
    this.initialScrollOffset = 0,
    this.initialPeriodDays,
    this.sadeceGrafik = false,
  });

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  /// Fiyat kaynağının anladığı sembol; yoksa alarm kurulamaz.
  String? get _alarmSembolu =>
      alarmSembolu(widget.asset.ticker, widget.asset.subCategory);

  late int _selectedPeriodIdx;
  String? _view = ''; // '' = Ben (Default), null = Tümü, uuid = Ortak
  late Future<Map<int, double>> _historyFuture;
  late ScrollController _scrollController;
  // Compare mode: seçili karşılaştırma varlığı (kullanıcının portföyünden).
  // null = compare kapalı. Bu varlığın history serisi ana varlıkla aynı
  // periyotta fetch edilir, ilk nokta 100 kabul edilip % normalize edilir.
  Asset? _compareAsset;
  Future<Map<int, double>>? _compareHistoryFuture;

  /// Periyot sekmeleri. `days: 0` → GÜN İÇİ (5 dakikalık çözünürlük).
  ///
  /// Etiketler portföy performans ekranıyla AYNI: iki ekran aynı soruyu
  /// soruyor, farklı kelimelerle sormamalı. Ayrıca beş uzun etiket
  /// ("HAFTALIK", "6 AYLIK"…) 360pt genişlikte yan yana sığmıyordu.
  static const List<({String label, int days})> _allPeriods = [
    (label: 'GÜNLÜK', days: 0),
    (label: '1H', days: 7),
    (label: '1A', days: 30),
    (label: '6A', days: 180),
    (label: '1Y', days: 365),
  ];

  /// Bu varlık için gün içi fiyat verisi ANLAMLI mı?
  ///
  /// Elle fiyatlanan varlıkların ("Ev", "Araba") bir
  /// piyasa serisi yoktur; onlarda GÜNLÜK sekmesi kullanıcıya boş ya da
  /// dümdüz bir grafik gösterir ve sekmeyi açmanın hiçbir karşılığı olmaz.
  ///
  /// Fon DAHİLDİR: TEFAS gün içi NAV yayınlamasa da seri, gün içinde bir
  /// basamak olarak fonun günlük NAV değişimini taşır
  /// (bkz. `HistoryService.gunIciFonBirimFiyati`).
  bool get _gunIciDestekli =>
      !widget.asset.isManualPrice &&
      widget.asset.type != AssetType.diger;

  List<({String label, int days})> get _periods =>
      _gunIciDestekli ? _allPeriods : _allPeriods.sublist(1);

  /// Alttaki teknik gösterge panelinin konumu.
  ///
  /// Üstteki sinyal şeridi yalnızca ÖZET verir (yön + kaç gösterge + güven).
  /// "Hangi gösterge ne diyor" sorusunun cevabı sayfanın dibindeki panelde;
  /// kullanıcı şeride dokununca oraya kaydırılır. Aksi halde özet, cevabı
  /// olmayan bir merak uyandırırdı.
  final GlobalKey _sinyalPaneliKey = GlobalKey();

  /// Teknik sinyal yüzeyleri (kart + gösterge paneli) çizilsin mi?
  /// Yatırımcı seviyesi Başlangıç ise hayır — bkz. `seviyeGorunurlugu`.
  /// Tam ekranda (`sadeceGrafik`) da hayır: orada yalnızca grafik var.
  bool get _sinyalYuzeyleri =>
      !widget.sadeceGrafik &&
      seviyeGorunurlugu(ref.watch(yatirimciSeviyesiProvider)).teknikSinyaller;

  /// Gün içi serinin çizildiği günün 00:00'ı.
  ///
  /// Bugün olmak ZORUNDA değil: piyasa kapalıyken (hafta sonu, tatil,
  /// açılıştan önce) servis SON SEANSI döndürür. Seri geldiğinde
  /// buradan okunur; X ekseni ve saat etiketleri o güne oturur.
  DateTime? _gunIciBaslangic;

  // Son başarılı history sonucu. Periyot değiştiğinde FutureBuilder yeni
  // future'ı "waiting" sayar ve snapshot.data null olur; bu alan olmadan
  // grafik + altındaki tüm kontroller (compare, MA20/LOG, fullscreen) o
  // sürede ağaçtan düşüyordu. Artık eski seri yerinde kalır, sadece grafik
  // alanı "yükleniyor" hissi verir ve filtreler tıklanabilir kalır.
  Map<int, double>? _lastHistory;

  @override
  void initState() {
    super.initState();
    // Varsayılan sekme HAFTALIK olarak KALIR.
    //
    // GÜNLÜK sekmesi listeye eklendi ama varsayılan yapılmadı: varlık
    // detayına giren kullanıcı çoğunlukla trendi arıyor, tek seansı değil.
    // Gün içi görünüm bir tıkla, hep aynı yerde (en solda) duruyor.
    _selectedPeriodIdx = _gunIciDestekli ? 1 : 0;

    // Çağıran özel bir periyot istediyse (fiyat alarmı bildirimi → GÜNLÜK)
    // onu seç. `indexWhere` -1 dönerse istek DESTEKLENMİYOR demektir
    // (elle fiyatlanan varlıkta gün içi yok) ve varsayılan korunur —
    // sessizce düşmesi kasıtlı: bildirim yine de doğru varlığı açmalı.
    final istenen = widget.initialPeriodDays;
    if (istenen != null) {
      final idx = _periods.indexWhere((p) => p.days == istenen);
      if (idx >= 0) _selectedPeriodIdx = idx;
    }
    _historyFuture = _loadHistory(_periods[_selectedPeriodIdx].days);
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
  }

  /// History fetch + son başarılı sonucu sakla.
  ///
  /// [days] 0 ise GÜN İÇİ seri istenir: 24 saat, 5 dakikalık slotlar.
  /// Gün içi yolu ayrı bir servistir (`...HourlyBreakdown`) ve çizilen
  /// günü de bildirir — X ekseni ona göre kurulur.
  Future<Map<int, double>> _loadHistory(int days) {
    if (days == 0) {
      return HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([widget.asset], 24)
          .then((b) {
        if (mounted) {
          _gunIciBaslangic = b.seansGunu;
          if (b.total.isNotEmpty) _lastHistory = b.total;
        }
        return b.total;
      });
    }
    return HistoryService.instance
        .getPortfolioHistory([widget.asset], days)
      ..then((v) {
        if (mounted && v.isNotEmpty) _lastHistory = v;
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Karşılaştırma varlığının serisi — periyoda göre doğru yoldan.
  ///
  /// Gün içi (`days == 0`) eskiden KAPALIYDI: seri `getPortfolioHistory`
  /// ile çekiliyordu ve o çağrı 0 günlük bir pencere isterdi. Şimdi ana
  /// varlıkla AYNI servisten (`...HourlyBreakdown`) gelir; iki seri de 5
  /// dakikalık ızgarada, ikisi de kendi ilk noktasına göre yüzdeye
  /// normalize edilir — yani gün içi karşılaştırma "açılıştan bu yana %
  /// değişim"dir. Slotları örtüşmeyen çiftlerde (BIST 10-18 ile 7/24 döviz)
  /// her seri kendi açılışından başlar; bu, diğer periyotlarda da geçerli
  /// olan sözleşmenin aynısı (her seri kendi ilk noktasına göre).
  ///
  /// Tek tuzak: piyasa kapalıyken iki varlığın ÇİZİLEN GÜNÜ farklı olabilir
  /// (hisse Cuma seansını, döviz bugünü döndürür). Eksen ana varlığın
  /// gününe kurulu; başka güne ait noktalar ya `x < 0` ile atlanır ya da
  /// sağa taşardı. O durumda seri BOŞ döner ve kullanıcıya söylenir —
  /// yanlış güne ait bir çizgi çizmekten iyidir.
  Future<Map<int, double>> _karsilastirmaSerisi(Asset asset, int days) async {
    if (days != 0) {
      return HistoryService.instance.getPortfolioHistory([asset], days);
    }
    // Ana serinin future'ı ŞİMDİ yakalanır: `_selectPeriod` ikisini aynı
    // `setState` içinde başlatıyor ve alan sonra değişebilir.
    final anaSeri = _historyFuture;
    final b = await HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown([asset], 24);
    // `_gunIciBaslangic` ANA seri çözülünce yazılıyor. Karşılaştırma önce
    // dönerse alan ya boş (ilk seçim) ya da önceki seansın günü olur —
    // ikisinde de kapı yanlış karar verir ve başka güne ait noktalar
    // eksene sızar. Bu yüzden önce ana seri beklenir.
    try {
      await anaSeri;
    } catch (_) {
      // Ana seri düştüyse karşılaştırmayı da çizmeyiz: eksen zaten yok.
      return const <int, double>{};
    }
    {
      final anaGun = _gunIciBaslangic;
      if (anaGun != null && b.seansGunu != null && b.seansGunu != anaGun) {
        if (mounted) {
          sandikSnack(
            context,
            '${asset.ticker} için gün içi verisi farklı bir seans gününe ait; '
            'karşılaştırma bu sekmede çizilemedi.',
            kind: SandikSnackKind.warning,
          );
        }
        return const <int, double>{};
      }
    }
    return b.total;
  }

  /// Seçili sekme gün içi mi?
  bool get _gunIciMi => _periods[_selectedPeriodIdx].days == 0;

  /// Bir sahibin lot'ları arasından BU ekranın varlığına karşılık gelen
  /// pozisyonu döndürür — yoksa `null`.
  ///
  /// **Neden `firstWhere` değil.** Burada eskiden `assets.where(...).first`
  /// vardı ve sahibin YALNIZCA İLK lot'unu alıyordu. Kendi tarafımızda
  /// `widget.asset` `aggregatePositions`'tan gelen bir pozisyon temsilcisidir
  /// (ağırlıklı ortalama maliyet, toplam miktar); ortak tarafında ise tek bir
  /// lot'tu. Aynı değişken, iki farklı anlam → aynı üründe iki farklı
  /// kâr/zarar. Ortak birden çok kez alım yaptıysa oranı yalnızca bir
  /// alımına göre hesaplanıyordu.
  ///
  /// `aggregatePositions` sahip başına AYRI çağrılır: farklı sahiplerin
  /// lot'ları asla tek havuzda toplanmaz (bkz. `aggregatePositionsByOwner`
  /// açıklaması) — aksi halde iki kişinin aynı hissesi tek pozisyonda
  /// birleşir ve toplam değer tek kişinin fiyatıyla hesaplanırdı.
  Position? _positionOf(List<Asset> ownerLots) {
    final hedef = positionKey(widget.asset);
    for (final p in aggregatePositions(ownerLots)) {
      if (p.key == hedef) return p;
    }
    return null;
  }

  double get _currentQuantity {
    if (_view == '') return widget.asset.quantity;

    final allAssetsMap = ref.read(allPartnerAssetsProvider).valueOrNull ?? {};

    if (_view != null) {
      return _positionOf(allAssetsMap[_view] ?? [])?.totalQuantity ?? 0;
    }

    // Tümü
    double total = widget.asset.quantity;
    final activePartners = ref.read(activePartnersProvider);
    for (final p in activePartners) {
      total += _positionOf(allAssetsMap[p.id] ?? [])?.totalQuantity ?? 0;
    }
    return total;
  }

  /// `setState` sarmalayıcısı — part dosyalarındaki extension'lar için.
  ///
  /// Ekran 3.800 satırdı; sinyal widget'ları, şeritler, karşılaştırma seçici
  /// ve eylemler `asset_detail/` altındaki part dosyalarına bölündü (aynı
  /// kütüphane, private erişim aynen). `setState` `@protected` olduğu için
  /// extension içinden çağrılamaz; bu ince sarmalayıcı tek geçiş noktasıdır.
  void _guncelle(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    // Baz para birimi BİR KEZ burada okunur: alt widget'lara parametre
    // gider. Yalnızca DEĞER tutarları (PnL, dönem değişimi) çevrilir;
    // grafiğin ekseni/ipucu kote FİYATTIR ve ₺ kalır.
    final baz = ref.watch(bazParaProvider);
    // Tam ekranda grafik ekranı doldurur (dönem satırı + dolgular düşülür);
    // normal ekranda sabit 400. Yatayda 400 sabit kalsaydı 360pt'lik ekranda
    // kaydırma gerekirdi — "büyütme" küçültürdü.
    final grafikYuksekligi = widget.sadeceGrafik
        ? (MediaQuery.sizeOf(context).height -
                MediaQuery.viewPaddingOf(context).vertical -
                150)
            .clamp(220.0, 900.0)
        : 400.0;
    final endDate = DateTime.now();
    final period = _periods[_selectedPeriodIdx];
    final isIntraday = period.days == 0;
    // GÜNLÜK sekmesinde eksen ÇİZİLEN GÜNÜN 00:00'ında başlar ve tam gün
    // (24 saat) boyunca uzanır.
    //
    // İki karar da bilinçli:
    //   · 00:00: kullanıcı isteği — "GÜNLÜK seçildiğinde 00:00'dan
    //     başlayarak gözükmeli" (2026-09-10). Ekseni ilk fiyat noktasında
    //     başlatmak, sabah 09:00'da bakınca başka, öğlen bakınca başka bir
    //     zaman ölçeği gösterirdi.
    //   · Çizilen gün bugün OLMAYABİLİR: piyasa kapalıyken servis son
    //     seansı döndürür (`seansGunu`). Ekseni `now`'a kurmak hafta sonu
    //     Cuma seansını grafiğin dışına atardı.
    final startDate = isIntraday
        ? (_gunIciBaslangic ??
            dayKey(endDate))
        : endDate.subtract(Duration(days: period.days));
    // Kesirli gün — saatlik veride son X gün sınırında değil, gerçek
    // anlarında olmalı. Yoksa nokta grafiğin ortasında yalnız kalır.
    final maxX = isIntraday
        ? 1.0
        : endDate.difference(startDate).inMinutes / (60.0 * 24.0);

    // Logic moved inside FutureBuilder

    final activePartners = ref.watch(activePartnersProvider);
    final allPartnerAssetsAsync = ref.watch(allPartnerAssetsProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;
    final isOwnAsset = currentUserId != null && widget.asset.userId == currentUserId;

    return Scaffold(
      backgroundColor: context.c.background,
      // Tam ekranda çubuk yok — route kendi kapat düğmesini koyar.
      appBar: widget.sadeceGrafik
          ? null
          : SandikAppBar(
        title: context.l10n.assetPerformanceSemantics(widget.asset.name),
        transparent: true,
        showBack: widget.showBackButton,
        actions: [
          // Fiyat alarmı BURADAN kurulur (2026-09-14): alarm varlığa aittir,
          // Ayarlar'daki liste yalnızca gösterir. Sembolü olmayan (manuel
          // fiyatlı) varlıkta zil yok — sunucu fiyatını izleyemez.
          if (_alarmSembolu != null)
            IconButton(
              tooltip: context.l10n.setPriceAlert,
              icon: Icon(Icons.add_alert_outlined, color: context.c.text90),
              onPressed: () => alarmKurAkisi(
                context,
                ref,
                sabit: AlarmAdayi(
                    _alarmSembolu!, widget.asset.name, widget.asset.currentPrice),
              ),
            ),
          if (isOwnAsset && !widget.showBackButton)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: context.c.text90),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SandikRadius.md)),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: context.c.danger, size: 20),
                      const SizedBox(width: 10),
                      Text('Sil',
                          style: TextStyle(color: context.c.danger)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
      color: context.c.amberText,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(force: true),
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
          controller: _scrollController,
          child: Padding(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 24),
            child: Column(
              children: [
                if (!widget.showBackButton && !widget.sadeceGrafik)
                  allPartnerAssetsAsync.maybeWhen(
                    data: (allAssetsMap) {
                      // Sekme yalnızca bu ürüne SAHİP ortaklar için çıkar.
                      // Eşleşme `ticker` ile değil `positionKey` ile yapılır:
                      // altın türleri (Gram/Çeyrek/Reşat) `subCategory` ile
                      // ayrışır ve ticker eşleşmesi farklı türleri aynı sayardı.
                      final matchingPartners = <AppUser>[
                        for (final p in activePartners)
                          if (_positionOf(allAssetsMap[p.id] ?? []) != null) p,
                      ];

                      if (matchingPartners.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        children: [
                          ModernTabSelector(
                            partners: matchingPartners,
                            selectedId: _view,
                            onChanged: (v) => setState(() => _view = v),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                // Sinyal özeti EN ÜSTTE.
                //
                // Şerit ÖNCE canlı göstergeleri okur, kayıtlı bildirimi
                // beklemez. İlk sürümde yalnızca `signal_notifications`
                // satırı varsa çiziliyordu; o satır ancak bir sinyal güven
                // eşiğini geçtiğinde VE öncekinden farklı olduğunda yazılır,
                // yani çoğu varlıkta çoğu zaman hiç yoktu ve sinyal bilgisi
                // pratikte yalnızca sayfanın dibindeki panelde kalıyordu
                // (kullanıcı bildirimi 2026-09-10: "sinyaller varlık
                // performansta gözükmeli").
                //
                // Kayıtlı bildirim varsa şeridin ikinci satırında durur —
                // "şu an ne diyor" ile "bana ne bildirilmişti" farklı
                // sorulardır.
                // Sinyal kartı ve aşağıdaki gösterge paneli Başlangıç
                // seviyesinde GİZLİ (`seviyeGorunurlugu`): AL/SAT göstergesi
                // yorumlanmadan okunduğunda yanıltıcıdır. Varsayılan Orta.
                if (_sinyalYuzeyleri)
                  AssetSignalCard(
                    asset: widget.asset,
                    onTap: _sinyalPaneline,
                  ),
                if (_alarmSembolu != null && !widget.sadeceGrafik) ...[
                  AlarmSeridi(
                    sembol: _alarmSembolu!,
                    ad: widget.asset.name,
                    guncelFiyat: widget.asset.currentPrice,
                  ),
                  const SizedBox(height: SandikSpace.smd),
                ],
                _buildPeriodToggle(),
                const SizedBox(height: 24),
                FutureBuilder<Map<int, double>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final waiting =
                        snapshot.connectionState == ConnectionState.waiting;
                    // Periyot değişiminde eski seriye düş — böylece bu
                    // FutureBuilder'ın altındaki compare/MA20/LOG kontrolleri
                    // ve özet şeritleri ağaçta kalır. Hiç veri yoksa (ilk
                    // açılış) yalnızca grafik alanı spinner gösterir.
                    // Bayat seri ÖNCEKİ periyoda ait. Yeni periyot daha darsa
                    // aralık dışı noktalar negatif X'e düşüp ekseni kaydırırdı
                    // — bu yüzden seçili pencereye kırpılır.
                    Map<int, double>? fallback;
                    if (snapshot.data == null && _lastHistory != null) {
                      final fromMs = startDate.millisecondsSinceEpoch;
                      final toMs = endDate.millisecondsSinceEpoch;
                      final clipped = <int, double>{
                        for (final e in _lastHistory!.entries)
                          if (e.key >= fromMs && e.key <= toMs) e.key: e.value,
                      };
                      if (clipped.length >= 2) fallback = clipped;
                    }
                    final data = snapshot.data ?? fallback;
                    final isStale = snapshot.data == null && data != null;
                    // BOŞ seri de "veri yok" demektir.
                    //
                    // `getPortfolioHistoryHourlyBreakdown` başarısız
                    // çekimde `null` değil BOŞ MAP döndürüyor. `data == null`
                    // kontrolü bunu yakalamıyordu: ekran "veri var" sanıp
                    // eksenleri ve "AÇILIŞ" etiketini çiziyor, ama çizgi
                    // olmuyordu. Kullanıcı bunu hata sanıyordu — oysa
                    // çekim hâlâ sürüyordu (bildirim 2026-09-13).
                    //
                    // İki nokta altı: `fl_chart` çizgi çizemez, eksen
                    // tek başına yanıltıcıdır.
                    if (data == null || data.length < 2) {
                      // Çekim SÜRÜYORSA spinner; BİTTİ ve hâlâ boşsa
                      // dürüst bir mesaj. Sonsuz spinner, veri hiç
                      // gelmeyecekken bile "birazdan gelir" der.
                      return SizedBox(
                        height: grafikYuksekligi,
                        child: waiting
                            ? const CustomLoadingView()
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(SandikSpace.lg),
                                  child: Text(
                                    context.l10n.priceHistoryFailed,
                                    textAlign: TextAlign.center,
                                    style: context.t.bodyMedium
                                        ?.copyWith(color: context.c.text58),
                                  ),
                                ),
                              ),
                      );
                    }

                    final historyMap = data;

                    // ── PnL: KART İLE BİREBİR AYNI FORMÜL ───────────────────
                    // Grafiğin son noktasını da bu canlı değerle sabitliyoruz
                    // (aşağıdaki `currentUnitPriceOverride`) — böylece grafik
                    // bitiş noktası ve chip her zaman aynı sayıyı gösterir.
                    final asset = widget.asset;
                    final qty = asset.quantity;
                    final anchorUnitTRY =
                        asset.purchasePrice * asset.purchaseFxRate;
                    final currentValueTRY = pState != null
                        ? pState.toTRY(asset.totalValue, asset.currency)
                        : asset.totalValue;
                    final currentUnitTRY = qty > 0 ? currentValueTRY / qty : 0.0;

                    // Compare mode devrede mi? Öncelikli — log-scale ile
                    // aynı anda anlamlı değil (biri % biri log), compare
                    // aktifken log ignore edilir.
                    final compareOn = _compareAsset != null;
                    final logOnPref = ref.watch(chartLogScaleProvider);
                    final logOn = compareOn ? false : logOnPref;

                    final rawSegments = _convertHistoryToSegments(
                        historyMap, startDate, endDate,
                        currentUnitPriceOverride: currentUnitTRY,
                        intraday: isIntraday);

                    // Normalize base: aktif segmentin ilk noktası. Bunun
                    // altında ana varlığın Y'leri (y / base) * 100 → % olur.
                    final rawActiveForBase = rawSegments.firstWhere(
                      (s) => !s.piyasaKapali && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final normBase = rawActiveForBase.spots.isNotEmpty
                        ? rawActiveForBase.spots.first.y
                        : 1.0;

                    // Y ekseni transform: compare → % normalize; log → log10;
                    // default → identity. `fromY` label/tooltip'te ters
                    // çeviren fonksiyon (compare'de gösterim değişik: "+%12.4"
                    // formatı için ayrıca handle edilir).
                    double toY(double y) {
                      if (compareOn) return (y / (normBase.abs() < 1e-9 ? 1 : normBase)) * 100.0;
                      if (logOn) return math.log(y < 1e-6 ? 1e-6 : y) / math.ln10;
                      return y;
                    }
                    double fromY(double v) {
                      if (compareOn) return v; // % zaten, ters çevirme yok
                      if (logOn) return math.pow(10, v).toDouble();
                      return v;
                    }

                    final segments = (compareOn || logOn)
                        ? rawSegments
                            .map((s) => TransactionSegment(
                                  spots: s.spots
                                      .map((sp) =>
                                          FlSpot(sp.x, toY(sp.y)))
                                      .toList(),
                                  lineColor: s.lineColor,
                                  areaGradientStart: s.areaGradientStart,
                                  areaGradientEnd: s.areaGradientEnd,
                                  thickness: s.thickness,
                                  piyasaKapali: s.piyasaKapali,
                                ))
                            .toList()
                        : rawSegments;

                    // Aktif segmenti bul (kesikli olmayan, yani alım sonrası)
                    final activeSeg = segments.firstWhere(
                      (s) => !s.piyasaKapali && s.spots.isNotEmpty,
                      orElse: () => TransactionSegment(
                        spots: const [],
                        lineColor: context.c.amberText,
                        areaGradientStart: Colors.transparent,
                        areaGradientEnd: Colors.transparent,
                        thickness: 3.5,
                      ),
                    );
                    final anchorSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.first : null;
                    final lastSpot =
                        activeSeg.spots.isNotEmpty ? activeSeg.spots.last : null;

                    // Compare mode: ikinci varlığın history'sini alt bir
                    // FutureBuilder ile fetch ediyoruz. Veri hazır olunca
                    // ilk noktası 100 kabul edilip (val/first)*100 normalize.

                    // MA20 overlay: aktif segmentin fiyat serisi üzerinden
                    // hesaplanır. İlk 19 nokta NaN olur (yetersiz veri) →
                    // atlanır. Kullanıcı chip ile açıp kapatır.
                    final ma20On = ref.watch(chartMA20Provider);
                    List<FlSpot>? ma20Spots;
                    if (ma20On && activeSeg.spots.length >= 20) {
                      // MA20 her zaman ham fiyat serisinden hesaplanır;
                      // sonra grafiğe koyulurken log domain'e alınır.
                      final rawActive = rawSegments.firstWhere(
                        (s) => !s.piyasaKapali && s.spots.isNotEmpty,
                        orElse: () => TransactionSegment(
                          spots: const [],
                          lineColor: context.c.amberText,
                          areaGradientStart: Colors.transparent,
                          areaGradientEnd: Colors.transparent,
                          thickness: 3.5,
                        ),
                      );
                      final prices =
                          rawActive.spots.map((s) => s.y).toList();
                      final sma = TechnicalAnalysisService.smaSeries(
                          prices, 20);
                      ma20Spots = <FlSpot>[];
                      for (int i = 0; i < sma.length; i++) {
                        if (sma[i].isNaN) continue;
                        ma20Spots
                            .add(FlSpot(rawActive.spots[i].x, toY(sma[i])));
                      }
                    }
                    // Seçili periyodun değişimi — HAM fiyat serisinden.
                    double? periodChangeTRY;
                    double? periodChangePct;
                    {
                      // DÖNEM DEĞİŞİMİ SAHİPTEN BAĞIMSIZ OLMALI.
                      //
                      // Bu yüzde "bu üründe bu dönemde ne oldu" sorusunu
                      // yanıtlar; "ben ne kadar kazandım" sorusunu DEĞİL.
                      // Dolayısıyla iki ortak aynı ürüne aynı dönemde
                      // baktığında AYNI yüzdeyi görmelidir — alım tarihleri
                      // farklı olsa bile.
                      //
                      // `rawActiveSeg` bu iş için KULLANILAMAZ, çünkü
                      // `_convertHistoryToSegments` onu sahibe göre bozar:
                      //   · seri sahibin alım gününde kesilir (`isBefore`
                      //     kontrolü) → 6 ay önce alan ile 3 ay önce alan
                      //     farklı noktadan başlar,
                      //   · ilk nokta piyasa fiyatı yerine sahibin ORTALAMA
                      //     MALİYETİ ile değiştirilir (anchor).
                      // İkisi birleşince bölen (`f`) sahibin maliyeti olur ve
                      // yüzde kişiye göre değişir; hatta biri kârda diğeri
                      // zararda görünür. Kullanıcı bunu altında yakaladı.
                      //
                      // Ham `historyMap` ise saf piyasa serisidir: sahibin
                      // alım tarihinden ve maliyetinden etkilenmez.
                      final sortedTs = historyMap.keys.toList()..sort();
                      if (sortedTs.length >= 2) {
                        // `historyMap` toplam pozisyon değeri taşır; birim
                        // fiyata inmek için miktara bölünür. Oran alındığı
                        // için bölen sadeleşir — yüzde miktardan bağımsızdır.
                        final divisor = qty > 0 ? qty : 1.0;
                        final f = historyMap[sortedTs.first]! / divisor;
                        final l = historyMap[sortedTs.last]! / divisor;
                        // Tutar ise sahibe özgüdür: aynı yüzde hareketi,
                        // elde tutulan miktara göre farklı TL eder.
                        periodChangeTRY = (l - f) * qty;
                        if (f > 0) periodChangePct = ((l - f) / f) * 100;
                      }
                    }

                    final anchorY = anchorSpot?.y ?? 0.0;
                    final totalCostTRY = asset.totalCostTRY;
                    final totalPnlTRY = currentValueTRY - totalCostTRY;
                    final pnlPct = totalCostTRY > 0
                        ? (totalPnlTRY / totalCostTRY) * 100
                        : 0.0;
                    final gainPositive = totalPnlTRY >= 0;
                    final endpointColor =
                        gainPositive ? context.c.gain : context.c.loss;

                    // Lot marker'ları için: gün-hassasiyetli tarih → (isSell) map.
                    // Aynı güne birden fazla işlem düşerse buy önceliklidir
                    // (ek alım genelde daha anlamlı sinyal).
                    // `isDeleteLog` tek başına yetmiyordu: yumuşak silinmiş
                    // lot'lar (deletedAt != null) ve TEMETTÜ satırları da
                    // nokta üretiyordu. Temettü bir alım/satım değil ve
                    // miktara hiç dokunmaz — noktası olmamalı. `isActive`
                    // mezar taşı + yumuşak silmeyi birlikte eler.
                    //
                    // Anahtar GERÇEK spot X'i (kesirli gün), tam sayı gün
                    // DEĞİL. Eskiden `spot.x.toInt()` ile tam gün eşleşmesi
                    // aranıyordu ve 6A/1Y'de noktalar kayboluyordu: o
                    // periyotlarda veri `ResolutionTier.weekly` gelir ve her
                    // nokta haftanın PAZARTESİSİNE snap edilir, dolayısıyla
                    // çarşamba yapılan bir işlemin gün anahtarı hiçbir spot'a
                    // denk gelmiyordu. Artık her işlem, içine düştüğü bar'a
                    // (`coveringSpotIndex`) bağlanıyor.
                    final Map<double, bool> lotDayIsSell = {};
                    final activeLots = widget.lots ?? [widget.asset];
                    final startMidnight = DateTime(
                        startDate.year, startDate.month, startDate.day);
                    final primarySpots = segments
                        .firstWhere((s) => !s.piyasaKapali && s.spots.isNotEmpty,
                            orElse: () => TransactionSegment(
                                  spots: const [],
                                  lineColor: context.c.amberText,
                                  areaGradientStart: Colors.transparent,
                                  areaGradientEnd: Colors.transparent,
                                  thickness: 3.5,
                                ))
                        .spots;
                    for (final lot in activeLots) {
                      if (!lot.isActive) continue;
                      if (!lot.isBuy && !lot.isSell) continue;
                      // GÜN İÇİNDE saat KIRPILMAZ. Diğer periyotlarda bir
                      // günün çözünürlüğü zaten bir noktadır ve işlemi gece
                      // yarısına çekmek doğrudur; gün içi seride ise 14:00'te
                      // yapılan bir alımın noktası 00:00'a düşer ve grafikteki
                      // sıçramayla hiç örtüşmezdi.
                      final d = isIntraday
                          ? lot.addedDate
                          : DateTime(lot.addedDate.year, lot.addedDate.month,
                              lot.addedDate.day);
                      if (d.isBefore(startMidnight)) continue;
                      final txX =
                          d.difference(startMidnight).inMinutes / (60.0 * 24.0);
                      final i = coveringSpotIndex(primarySpots, txX);
                      if (i < 0) continue;
                      final key = primarySpots[i].x;
                      final isSell = lot.isSell;
                      // Buy varsa buy kalsın (override etme)
                      if (lotDayIsSell.containsKey(key) &&
                          !lotDayIsSell[key]!) {
                        continue;
                      }
                      lotDayIsSell[key] = isSell;
                    }

                    // Y sınırlarını görünür X aralığındaki spot'lara göre
                    // hesaplayan closure — zoom sırasında yeniden çağrılır.
                    ({double minY, double maxY}) computeY(
                        double viewMinX, double viewMaxX,
                        {List<FlSpot>? extraSpots}) {
                      double minY = double.infinity;
                      double maxY = -double.infinity;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      // Compare barı da Y aralığına dahil edilsin ki
                      // 2. varlığın çizgisi grafik dışına düşmesin.
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          if (spot.y > maxY) maxY = spot.y;
                          if (spot.y < minY) minY = spot.y;
                        }
                      }
                      if (minY == double.infinity) minY = 0;
                      if (maxY == -double.infinity) maxY = 1000;

                      // Compare modda anchor 100 (normalize base). Aksi
                      // halde anchorY (ham ilk noktanın normalize hali).
                      final center = compareOn
                          ? 100.0
                          : (anchorY > 0 ? anchorY : (minY + maxY) / 2);
                      double maxAbsDev = 0;
                      for (final seg in segments) {
                        for (final spot in seg.spots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      if (extraSpots != null) {
                        for (final spot in extraSpots) {
                          if (spot.x < viewMinX || spot.x > viewMaxX) continue;
                          final dev = (spot.y - center).abs();
                          if (dev > maxAbsDev) maxAbsDev = dev;
                        }
                      }
                      // Asgari yarı-bant. Eksen yalnızca veriye göre
                      // ölçeklenirse yatay giden bir fiyatın kuruşluk
                      // dalgalanması tuvale yayılır ve olmayan bir "çöküş"
                      // çizilir; taban bunu keser.
                      //
                      // GÜN İÇİNDE taban DARDIR: bir hissenin günlük
                      // hareketi tipik olarak ±%0,5–2'dir ve %1'lik yarı-bant
                      // (yani %2'lik tam bant) o hareketi grafiğin onda
                      // birine sıkıştırıp çizgiyi DÜMDÜZ gösterir. Portföy
                      // performans ekranı aynı dersi `gunIciAsgariBantOrani`
                      // ile öğrenmişti (tam bant %0,5) — burada da yarısı,
                      // yani %0,25 yarı-bant kullanılır.
                      //
                      // Mutlak 1 TL tabanı gün içinde UYGULANMAZ: birim
                      // fiyatı 10 TL olan bir fonda ±1 TL, ±%10'luk bir
                      // bant demektir ve fonun gerçek günlük değişimini
                      // (binde birkaç) yine görünmez kılardı.
                      final oransalTaban =
                          center * (isIntraday ? 0.0025 : 0.01);
                      final minDev = isIntraday
                          ? (oransalTaban > 0 ? oransalTaban : 1.0)
                          : oransalTaban.clamp(1.0, double.infinity);
                      final halfRange =
                          maxAbsDev < minDev ? minDev : maxAbsDev;
                      final yPad = halfRange * 0.35;
                      final rawMaxY = center + halfRange + yPad;
                      // Compare modda negatif % olabilir (varlık düşmüş) —
                      // 0'a clamp'lemeyelim; ham hesabı bırak.
                      final rawMinY = compareOn
                          ? (center - halfRange - yPad)
                          : (center - halfRange - yPad)
                              .clamp(0, double.infinity)
                              .toDouble();
                      // TradingView tarzı nice-round Y bound: label'lar temiz
                      // yuvarlak sayılar olsun ve grid çizgilerine denk gelsin.
                      final rawInterval = (rawMaxY - rawMinY) / 4;
                      if (rawInterval <= 0) {
                        return (
                          minY: rawMinY.toDouble(),
                          maxY: rawMaxY.toDouble()
                        );
                      }
                      final niceInterval = _niceRound(rawInterval);
                      final niceMin = compareOn
                          ? (rawMinY / niceInterval).floor() * niceInterval
                          : ((rawMinY / niceInterval).floor() *
                                  niceInterval)
                              .clamp(0.0, double.infinity);
                      final niceMax =
                          (rawMaxY / niceInterval).ceil() * niceInterval;
                      return (
                        minY: niceMin.toDouble(),
                        maxY: niceMax.toDouble()
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Yeni periyot yüklenirken ince bar — eski grafik
                        // ekranda kalır, kontroller tıklanabilir.
                        if (waiting)
                          SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: context.c.amberFill,
                            ),
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          _PnlSummaryStrip(
                            baz: baz,
                            anchorUnitPrice: anchorUnitTRY,
                            currentUnitPrice: currentUnitTRY,
                            pnlPct: pnlPct,
                            totalPnl: totalPnlTRY,
                            unitLabel: widget.asset.unitLabel,
                            isPositive: gainPositive,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: SandikSpace.sm),
                        // Seçili periyodun değişimi — üstteki strip alış→bugün
                        // toplam PnL'i gösterir, bu satır "bu dönemde ne oldu"
                        // sorusunu yanıtlar. İkisi farklı sorular.
                        // Bayat seride GİZLENİR: rakam hâlâ eski periyoda ait
                        // olurdu ama etiket yeni periyodu yazardı — yanıltıcı.
                        // (Üstteki strip periyottan bağımsız, o kalır.)
                        if (periodChangeTRY != null && !isStale)
                          _PeriodChangeRow(
                            baz: baz,
                            label: _periods[_selectedPeriodIdx].label,
                            changeTRY: periodChangeTRY,
                            changePct: periodChangePct,
                          ),
                        if (anchorSpot != null && lastSpot != null)
                          const SizedBox(height: 12),
                        // Grafik overlay chip'leri (MA20 vb.). Basit toggle.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _OverlayChip(
                              label: 'MA20',
                              active: ma20On,
                              onTap: () {
                                ref
                                    .read(chartMA20Provider.notifier)
                                    .set(!ma20On);
                              },
                            ),
                            const SizedBox(width: 6),
                            _OverlayChip(
                              label: 'LOG',
                              active: logOn,
                              onTap: () {
                                ref
                                    .read(chartLogScaleProvider.notifier)
                                    .set(!logOn);
                              },
                            ),
                            const SizedBox(width: 6),
                            // Tam ekranda ikinci bir tam ekran yok.
                            if (!widget.sadeceGrafik)
                            ChartFullscreenChip(
                              onTap: () {
                                FullscreenChartRoute.open(
                                  context,
                                  title: widget.asset.name,
                                  builder: (_) => AssetDetailScreen(
                                    asset: widget.asset,
                                    lots: widget.lots,
                                    showBackButton: false,
                                    // Yalnızca dönem seçici + grafik
                                    // (bkz. FullscreenChartRoute).
                                    sadeceGrafik: true,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Karşılaştırma gün içinde de açık — seri
                        // `_karsilastirmaSerisi` ile ana varlıkla aynı
                        // 5 dakikalık ızgaradan gelir.
                        _CompareStrip(
                          primaryTicker: widget.asset.ticker,
                          compare: _compareAsset,
                          onAddPressed: _openComparePicker,
                          onClearPressed: () {
                            setState(() {
                              _compareAsset = null;
                              _compareHistoryFuture = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<Map<int, double>>(
                          future: _compareHistoryFuture,
                          builder: (context, compareSnap) {
                            // Compare barı — snapshot hazır olduğunda
                            // normalize edilip LineChartBarData olur.
                            LineChartBarData? compareBar;
                            if (compareOn &&
                                compareSnap.hasData &&
                                compareSnap.data!.isNotEmpty) {
                              final entries = compareSnap.data!.entries
                                  .toList()
                                ..sort((a, b) => a.key.compareTo(b.key));
                              final firstY = entries.first.value;
                              if (firstY.abs() > 1e-9) {
                                final spots = <FlSpot>[];
                                for (final e in entries) {
                                  final ts = e.key;
                                  final date = DateTime
                                      .fromMillisecondsSinceEpoch(ts);
                                  final x = date
                                          .difference(startDate)
                                          .inMinutes /
                                      (60.0 * 24.0);
                                  if (x < 0) continue;
                                  spots.add(FlSpot(
                                      x, (e.value / firstY) * 100.0));
                                }
                                if (spots.length >= 2) {
                                  compareBar = LineChartBarData(
                                    spots: spots,
                                    isCurved: false,
                                    color: _kCompareColor,
                                    barWidth: 1.6,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData:
                                        BarAreaData(show: false),
                                  );
                                }
                              }
                            }
                            // Bayat seri soluk çizilir — spinner yerine
                            // bağlam sunar, ama "bu henüz yeni periyodun
                            // verisi değil" hissini korur.
                            return AnimatedOpacity(
                              opacity: isStale ? 0.35 : 1.0,
                              duration: SandikMotion.of(context, const Duration(milliseconds: 160)),
                              curve: SandikMotion.enter,
                              child: Container(
                          height: grafikYuksekligi,
                          decoration: BoxDecoration(
                            color: context.c.surface1,
                            borderRadius: BorderRadius.circular(SandikRadius.md),
                            border: Border.all(
                                color: context.c.overlay),
                          ),
                          padding: const EdgeInsets.only(
                              top: 36, right: 16, left: 8, bottom: 16),
                          child: Builder(builder: (_) {
                            // Aktif segment (alış → bugün) tüm dönemin
                            // %25'inden azsa viewport'u aktif segmentin
                            // etrafına daralt — kullanıcı yıllık seçse
                            // bile 2 gün önce aldığı varlık için grafik
                            // dolgun görünsün, dikey çubuk gibi değil.
                            // Sağa daha fazla pay (~%8) → son nokta ve
                            // "ŞİMDİ" etiketi x-tick'lerle çakışmasın.
                            double focusMin = -maxX * 0.03;
                            double focusMax = maxX * 1.08;
                            // GÜNLÜK sekmesinde daraltma YOK: gün bir
                            // TAKVİM GÜNÜDÜR. Bugün 14:00'te alınan bir
                            // varlık için ekseni alım anının etrafına
                            // daraltmak, aynı sekmeye her bakışta farklı
                            // bir zaman ölçeği gösterirdi — hareket gün
                            // içindeki YERİYLE birlikte okunmalı.
                            if (!isIntraday &&
                                anchorSpot != null &&
                                lastSpot != null) {
                              final firstX = anchorSpot.x;
                              final lastX = lastSpot.x;
                              final activeSpan = lastX - firstX;
                              if (activeSpan < maxX * 0.25) {
                                final pad = activeSpan < 1.0
                                    ? 1.0
                                    : activeSpan * 0.8;
                                focusMin = (firstX - pad).clamp(-maxX * 0.03, maxX);
                                // Sağa fazladan %25 pay → son nokta
                                // grafiğin sağ kenarında değil, biraz
                                // içeride kalsın ki "şimdi" etiketi ve
                                // dot rahat okunsun.
                                focusMax = (lastX + pad * 1.25)
                                    .clamp(focusMin + 0.5, maxX * 1.08);
                              }
                            }
                            // Seyreltme adayları viewport'a bağlı DEĞİL —
                            // yalnızca segment'lere ve lot günlerine bağlı.
                            // Builder içinde bırakılırsa her pinch/pan
                            // karesinde expand+map+where zinciri baştan
                            // kurulurdu. Bir kez hesapla.
                            // Anahtarlar zaten gerçek spot X'leri — doğrudan
                            // aday listesi olarak kullanılabilir.
                            final dotCandidates =
                                lotDayIsSell.keys.toList(growable: false);
                            return ZoomableChart(
                            fullMinX: focusMin,
                            fullMaxX: focusMax,
                            height: grafikYuksekligi - 36 - 16,
                            plotPaddingRight: 60,
                            builder: (viewMinX, viewMaxX) {
                              final yBounds = computeY(
                                viewMinX,
                                viewMaxX,
                                extraSpots: compareBar?.spots,
                              );
                              final viewMinY = yBounds.minY;
                              final viewMaxY = yBounds.maxY;
                              // Lot marker'ları piksel bazlı seyreltmeden
                              // geçer — arka arkaya alım yapılan günlerde
                              // dot'lar üst üste binip yığın gibi
                              // görünüyordu. Zoom'da viewport daralınca
                              // gizlenenler tek tek ortaya çıkar.
                              // Adaylar gerçek spot X'leridir: `spot.x`
                              // kesirli gün (dakika/1440), gün anahtarı ise
                              // `spot.x.toInt()`. Gün anahtarını doğrudan
                              // aday yaparsak hiçbir spot'a eşleşmez.
                              final dotThinner = DotThinner.build(
                                candidates: dotCandidates,
                                viewMinX: viewMinX,
                                viewMaxX: viewMaxX,
                                plotWidthPx: (MediaQuery.of(context)
                                            .size
                                            .width -
                                        60 -
                                        40)
                                    .clamp(120.0, 2000.0),
                                // Nokta çapı küçüldü (r=3 + 1.2 halka) →
                                // ayrım eşiği de düşebilir: daha az nokta
                                // gizlenir, üst üste binme yine olmaz.
                                minSeparationPx: 11,
                                // Uç noktalara (r=5.5) yakın işlemler kalıcı
                                // olarak gizlenmesin — bkz. DotThinner.
                                anchorSeparationPx: 8,
                                alwaysKeep: {
                                  if (anchorSpot != null) anchorSpot.x,
                                  if (lastSpot != null) lastSpot.x,
                                },
                              );
                              return LineChartData(
                          minX: viewMinX,
                          maxX: viewMaxX,
                          minY: viewMinY,
                          maxY: viewMaxY,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: (viewMaxY - viewMinY) > 0
                                ? _niceRound(
                                    (viewMaxY - viewMinY) / 4)
                                : 50000,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: context.c.overlay,
                              strokeWidth: 1,
                            ),
                          ),
                          // TradingView paritesi: plot area sağ kenarına
                          // ince Y-ekseni ayraç çizgisi — Y bandı görsel
                          // olarak plot area'dan ayrılsın.
                          borderData: FlBorderData(
                            show: true,
                            border: Border(
                              right: BorderSide(
                                color: context.c.overlay,
                                width: 1,
                              ),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            // Y ekseni SAĞDA (TradingView convention).
                            // leftTitles kapalı. rightTitles nice-round
                            // interval ile temiz sayılar (100K/200K/...).
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                interval: (viewMaxY - viewMinY) > 0
                                    ? _niceRound(
                                        (viewMaxY - viewMinY) / 4)
                                    : 50000,
                                getTitlesWidget: (value, meta) {
                                  if (value == meta.min ||
                                      value == meta.max) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = compareOn
                                      ? '${(value - 100).toStringAsFixed(1)}%'
                                      : fmtTRYCompact(fromY(value));
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.left,
                                      // Eksen etiketi — tabular figür, tik
                                      // değerleri değişince kaymasın.
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
                            // X ekseni: dinamik format (span'a göre yıl/saat
                            // ekle), nice-round interval.
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: (viewMaxX - viewMinX) > 0
                                    ? _niceRound(
                                        (viewMaxX - viewMinX) / 5)
                                    : 1,
                                getTitlesWidget: (value, meta) {
                                  final span =
                                      (meta.max - meta.min).abs();
                                  // Etiket tick'in üzerinde ortalanır; kenara
                                  // çok yakın tick'in etiketi plot alanının
                                  // dışına taşar. Zoom'da interval sınırlara
                                  // denk gelmediği için min/max eşitliği
                                  // yetmiyor — %6 kenar payı bırak.
                                  final edge = span * 0.06;
                                  if (value <= meta.min + edge ||
                                      value >= meta.max - edge) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = startDate.add(Duration(
                                      minutes:
                                          (value * 60 * 24).round()));
                                  final showYearOnly = span > 400;
                                  final showTime = span < 3;
                                  final showYear = !showYearOnly &&
                                      date.year != DateTime.now().year;
                                  // Gün içi sekmesinde tek bir gün çizilir;
                                  // her etikette aynı tarihi tekrarlamak
                                  // 74pt'lik etiketi kırpar ve okunması
                                  // gereken SAATİ gölgeler.
                                  final label = isIntraday
                                      ? DateFormat('HH:mm', 'tr_TR')
                                          .format(date)
                                      : showYearOnly
                                          ? DateFormat('MMM yy', 'tr_TR')
                                              .format(date)
                                          : showTime
                                              ? DateFormat('d MMM HH:mm',
                                                      'tr_TR')
                                                  .format(date)
                                              : DateFormat(
                                                      showYear
                                                          ? 'd MMM yy'
                                                          : 'd MMM',
                                                      'tr_TR')
                                                  .format(date);
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(top: 10),
                                    // Sabit genişlik + ortalama: taşan metin
                                    // ellipsis olur, komşu etiketle çakışmaz.
                                    child: SizedBox(
                                      width: 74,
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        // Eksen etiketi — tabular figür, tik
                                        // değerleri değişince kaymasın.
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
                          extraLinesData: anchorSpot != null
                              ? ExtraLinesData(
                                  horizontalLines: [
                                    HorizontalLine(
                                      y: anchorY,
                                      color: context.c.text36,
                                      strokeWidth: 1,
                                      dashArray: const [4, 4],
                                      label: HorizontalLineLabel(
                                        show: true,
                                        alignment: Alignment.topLeft,
                                        padding: const EdgeInsets.only(
                                            left: 8, bottom: 2),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w800,
                                          color: context.c.text90
                                              .withValues(alpha: 0.75),
                                        ),
                                        // Gün içinde çapa ALIŞ FİYATI DEĞİL,
                                        // günün ilk noktasıdır (bkz.
                                        // `_convertHistoryToSegments`
                                        // `intraday`). Etiketi "ALIŞ"
                                        // bırakmak doğrudan yanlış bilgi
                                        // olurdu.
                                        labelResolver: (_) =>
                                            '${isIntraday ? 'AÇILIŞ' : 'ALIŞ'}  ${fixedFormatter(2).format(anchorY)} ₺',
                                      ),
                                    ),
                                  ],
                                  verticalLines: [
                                    // Başlangıç (alış) X'i — tarih etiketli
                                    // dashed vertical marker.
                                    VerticalLine(
                                      x: anchorSpot.x,
                                      color: context.c.amberText
                                          .withValues(alpha: 0.4),
                                      strokeWidth: 1.2,
                                      dashArray: const [4, 4],
                                      label: VerticalLineLabel(
                                        show: true,
                                        alignment: Alignment.topRight,
                                        padding: const EdgeInsets.only(
                                            bottom: 8, left: 6),
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          fontWeight: FontWeight.w700,
                                          color: context.c.amberText,
                                        ),
                                        labelResolver: (_) {
                                          final buyDate = startDate.add(
                                              Duration(
                                                  minutes:
                                                      (anchorSpot.x * 1440)
                                                          .round()));
                                          if (isIntraday) {
                                            return 'AÇILIŞ ${DateFormat('HH:mm', 'tr_TR').format(buyDate)}';
                                          }
                                          return 'ALIŞ ${DateFormat('d MMM', 'tr_TR').format(buyDate)}';
                                        },
                                      ),
                                    ),
                                    // Bitiş (bugün) X'i — "ŞİMDİ" etiketi
                                    // ile net görünsün.
                                    if (lastSpot != null)
                                      VerticalLine(
                                        x: lastSpot.x,
                                        color: endpointColor
                                            .withValues(alpha: 0.55),
                                        strokeWidth: 1.2,
                                        dashArray: const [4, 4],
                                        label: VerticalLineLabel(
                                          show: true,
                                          alignment: Alignment.topLeft,
                                          padding: const EdgeInsets.only(
                                              bottom: 8, right: 6),
                                          style: context.t.labelMedium?.copyWith(
                                            letterSpacing: 0,
                                            fontWeight: FontWeight.w700,
                                            color: endpointColor,
                                          ),
                                          labelResolver: (_) => 'ŞİMDİ',
                                        ),
                                      ),
                                  ],
                                )
                              : const ExtraLinesData(),
                          lineBarsData: <LineChartBarData>[
                            if (ma20Spots != null && ma20Spots.length >= 2)
                              LineChartBarData(
                                spots: ma20Spots,
                                isCurved: false,
                                color: context.c.text58,
                                barWidth: 1.4,
                                isStrokeCapRound: true,
                                dashArray: const [3, 3],
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            if (compareBar != null) compareBar,
                            ...segments
                              .map((seg) {
                                // Trading estetiği: dönem uzadıkça ince
                                // çizgi, kısa dönemde biraz belirgin.
                                // Merdiven `chart_line_width.dart`'ta —
                                // takip/karşılaştır grafiği de aynı
                                // fonksiyonu çağırır.
                                final periodDays = _periods[_selectedPeriodIdx].days;
                                final baseWidth =
                                    donemCizgiKalinligi(periodDays);
                                final effective = seg.piyasaKapali ? seg.thickness : baseWidth;
                                return LineChartBarData(
                                    spots: seg.spots,
                                    isCurved: false,
                                    color: seg.lineColor,
                                    barWidth: effective,
                                    isStrokeCapRound: true,
                                    dashArray: seg.piyasaKapali ? const [4, 4] : null,
                                    dotData: FlDotData(
                                      show: !seg.piyasaKapali,
                                      checkToShowDot: (spot, barData) {
                                        if (seg.piyasaKapali) return false;
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return true;
                                        }
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return true;
                                        }
                                        if (!lotDayIsSell.containsKey(spot.x)) {
                                          return false;
                                        }
                                        return dotThinner.shows(spot.x);
                                      },
                                      getDotPainter:
                                          (spot, percent, barData, index) {
                                        // Alış: beyaz halkalı amber (ince).
                                        if (anchorSpot != null &&
                                            spot.x == anchorSpot.x &&
                                            spot.y == anchorSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: context.c.amberText,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 2,
                                          );
                                        }
                                        // Son (şimdi): kar/zarar rengi.
                                        if (lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y) {
                                          return FlDotCirclePainter(
                                            radius: 5.5,
                                            color: endpointColor,
                                            strokeColor: context.c.text90
                                                .withValues(alpha: 0.85),
                                            strokeWidth: 1.5,
                                          );
                                        }
                                        // Ek alım / satış marker'ları
                                        final isSell = lotDayIsSell[spot.x];
                                        if (isSell != null) {
                                          // Ortadaki işlem noktaları uçlardan
                                          // (5.5px) belirgin biçimde küçük —
                                          // yoğun işlem yapılan dönemde çizgi
                                          // boncuk dizisine dönüşmesin. Halka
                                          // da inceltildi: küçük yarıçapta 2px
                                          // kenar içi boş gösteriyordu.
                                          return FlDotCirclePainter(
                                            radius: 3.0,
                                            color: isSell
                                                ? context.c.loss
                                                : context.c.gain,
                                            strokeColor: context.c.text90,
                                            strokeWidth: 1.2,
                                          );
                                        }
                                        return FlDotCirclePainter(
                                          radius: 3.0,
                                          color: context.c.amberText,
                                          strokeColor: context.c.background,
                                          strokeWidth: 1.5,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        colors: seg.piyasaKapali
                                            ? [
                                                seg.areaGradientStart,
                                                seg.areaGradientEnd,
                                              ]
                                            : [
                                                context.c.amberText
                                                    .withValues(alpha: 0.22),
                                                context.c.amberText
                                                    .withValues(alpha: 0.06),
                                                Colors.transparent,
                                              ],
                                        stops: seg.piyasaKapali
                                            ? null
                                            : const [0.0, 0.5, 1.0],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  );
                              }),
                          ],
                          // Built-in tooltip kapalı — crosshair TEK KAYNAK.
                          // fl_chart tooltip'i ile ZoomableChart crosshair'ı
                          // paralel çalışınca X hesabı farklı olup değerler
                          // uyumsuz görünüyordu.
                          lineTouchData: LineTouchData(
                            enabled: false,
                            handleBuiltInTouches: false,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  context.c.surface1.withValues(alpha: 0.95),
                              tooltipRoundedRadius: 10,
                              tooltipPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (touchedSpots) {
                                final valueFmt = fixedFormatter(3);
                                // Passive + active segmentler anchor noktasında
                                // aynı (x, y) spot'unu paylaşır → aynı tooltip
                                // iki kere görünür. Yakın olanları filtrele.
                                final seen = <String>{};
                                return touchedSpots.map<LineTooltipItem?>((spot) {
                                  final key =
                                      '${spot.x.toStringAsFixed(2)}|${spot.y.toStringAsFixed(2)}';
                                  if (!seen.add(key)) return null;
                                  final date = startDate
                                      .add(Duration(days: spot.x.toInt()));
                                  final dateLabel = DateFormat('d MMM', 'tr_TR')
                                      .format(date);
                                  final tipText = compareOn
                                      ? '${(spot.y - 100).toStringAsFixed(2)}%'
                                      : '${valueFmt.format(fromY(spot.y))} ₺';
                                  return LineTooltipItem(
                                    tipText,
                                    context.t.numSmall.copyWith(
                                      color: context.c.text90,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '\n$dateLabel',
                                        style: context.t.labelMedium?.copyWith(
                                          letterSpacing: 0,
                                          color: context.c.text58,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        );
                            },
                            crosshairSnapX: (x) {
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return x;
                              final clamped =
                                  x.clamp(spots.first.x, spots.last.x);
                              // Sıralı seri → ikili arama. Parmak her
                              // kaydığında çağrılıyor (bkz. nearestSpotIndex).
                              return spots[nearestSpotIndex(spots, clamped)].x;
                            },
                            crosshairLabelBuilder: (x) {
                              // x zaten snap edildi — spot'u bul.
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return null;
                              final snapped =
                                  spots[nearestSpotIndex(spots, x)];
                              final date = startDate.add(Duration(
                                  minutes:
                                      (snapped.x * 1440).round()));
                              final title = compareOn
                                  ? '${(snapped.y - 100).toStringAsFixed(2)}%'
                                  : tryFormatter(digits: 2)
                                      .format(fromY(snapped.y));
                              // Gün içinde okunacak bilgi SAATTİR; tarih
                              // zaten sekmenin kendisinden belli.
                              final subtitle = DateFormat(
                                      isIntraday
                                          ? 'd MMM · HH:mm'
                                          : 'd MMM yyyy',
                                      'tr_TR')
                                  .format(date);
                              return (title, subtitle);
                            },
                          );
                          }),
                        ),
                            ); // AnimatedOpacity (bayat seri solukluğu)
                          },
                        ),
                      ],
                    );
                  },
                ),
                // Tam ekranda grafik altı yok (bkz. FullscreenChartRoute).
                if (!widget.sadeceGrafik) ...[
                const SizedBox(height: 24),
                // Miktar Bilgisi
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.c.overlay,
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(color: context.c.hairline),
                  ),
                  // Etiket + değer yan yana; ikisi de sınırsızdı ve büyük
                  // miktarlarda satır taşıyordu (105px). Etiket kırpılabilir,
                  // değer ise FittedBox ile küçülerek sığar — rakam kırpmak
                  // yanlış okumaya yol açar.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          context.l10n.totalQuantityUpper,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelLarge?.copyWith(
                              color: context.c.amberText,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            // `unitLabel`, ham `unitType` DEĞİL.
                            //
                            // `unitType` bir DB sabitidir ('piece', 'gram',
                            // 'ounce') ve ekrana basılmak için değildir;
                            // kullanıcı "15.603,00 piece" görüyordu.
                            // `unitLabel` türe göre Türkçe karşılığını verir:
                            // hisse/fon → "lot", gram altın → "gr", çeyrek →
                            // "adet", döviz → para sembolü ($, €).
                            //
                            // `unitIsPrefix`: döviz sembolü ÖNE gelir
                            // ("$100"), diğerleri sona ("15.603,00 lot").
                            widget.asset.miktarMetni(_currentQuantity,
                                (v, d) => fmtNum(v, digits: d)),
                            maxLines: 1,
                            style: context.t.numLarge.copyWith(
                                color: context.c.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_sinyalYuzeyleri) ...[
                  const SizedBox(height: 24),
                  TechnicalSignalPanel.forAsset(widget.asset,
                      key: _sinyalPaneliKey, detayli: true),
                ],
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

// ── PnL özet strip'i (alış → şimdi + değişim) ────────────────────────────────

// ─── Compare mode UI ─────────────────────────────────────────────────────────

