import 'dart:math' as math;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/gorunum_kapsami.dart';
import '../models/portfoy.dart';
import '../models/position.dart';
import '../providers/portfoy_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../widgets/kripto_gecikme_etiketi.dart';
import '../widgets/sandik_app_bar.dart';
import '../utils/chart_line_width.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import '../utils/dot_thinning.dart';
import '../utils/islem_isaretleri.dart';
import '../utils/spot_lookup.dart';
import '../services/bist_hisse_katalogu.dart';
import '../services/history_service.dart';
import '../services/period_summary_service.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../widgets/disclaimer_widget.dart';
import '../widgets/fiyat_grafigi.dart' show donemUclariX;
import '../widgets/zoomable_chart.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/preferences_provider.dart';
import '../widgets/transaction_segment.dart';
import 'signal_settings_screen.dart';
import '../models/signal_alert.dart';
import '../providers/signal_provider.dart';
import '../providers/sinyal_varligi_provider.dart';
import '../utils/friendly_error.dart';
import '../services/tefas_service.dart';
import '../services/tazelik_ritmi.dart';
import '../widgets/custom_loading_indicator.dart';
import '../providers/price_alert_provider.dart';
import '../widgets/alarm_kur_sheet.dart';
import '../widgets/alarm_seridi.dart';
import '../models/varlik_kimligi.dart';
import '../services/crash_reporter.dart';
import '../services/varlik_istatistik.dart';
import '../widgets/donem_istatistik.dart';
import '../widgets/sandik_skeleton.dart';
import '../widgets/donem_secici.dart';
import '../widgets/varlik_iskeleti.dart';
import '../widgets/varlik_ozeti.dart';
import '../widgets/grafik_stili.dart';
import '../utils/acilis_kapisi.dart';
import '../utils/chart_axis.dart';
import '../widgets/takip_yildizi.dart';
import '../widgets/fon_karnesi_karti.dart';
import '../widgets/fon_dagilimi_karti.dart';
import '../widgets/para_akisi_karti.dart';
import '../widgets/sinyal_kilit_karti.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/hacim_radari_karti.dart';
import '../widgets/sandik_acilir.dart';
import '../providers/fon_karnesi_provider.dart'
    show fonKarnesiAcikProvider, fonKarnesiProvider;
import '../providers/fon_akisi_provider.dart'
    show
        balinaRadariAcikProvider,
        fonAkisiProvider,
        hisseHacmiProvider,
        kriptoBaskiProvider;
import '../providers/analiz_provider.dart'
    show notAnahtari, varlikNotOzetiProvider;
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/radar_okuma.dart' show kriptoOkunusu;
import '../services/remote_config_service.dart';
import '../widgets/analiz_notu_kutusu.dart';
import '../widgets/kap_baglantisi.dart';
import '../widgets/temettu_gecmisi_karti.dart';
import '../widgets/masraf_karti.dart';
import '../widgets/eurobond_karti.dart';
import '../services/varlik_masraflari.dart';
import '../widgets/sozlesme_karti.dart';
import '../providers/sozlesme_provider.dart';
import '../providers/secili_donem_provider.dart';
import '../services/sozlesme_deposu.dart';
import '../widgets/pozisyon_islemleri.dart';
import 'comparison_screen.dart';
import 'paywall_screen.dart';
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../utils/hareketli_ortalama.dart';
import '../utils/mum_turetici.dart' show Mum, mumlariGrafikUzayinda;
import '../models/ohlc.dart';
import '../widgets/sandik_segment.dart';
import '../services/mum_verisi.dart';

part 'asset_detail/eylemler.dart';
part 'asset_detail/sinyal_widgetlari.dart';
part 'asset_detail/seritler.dart';
part 'asset_detail/karsilastirma_secici.dart';
part 'asset_detail/ozet.dart';
part 'asset_detail/katmanlar.dart';
part 'asset_detail/grafik_katmanlari.dart';

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

  /// Portföy satırından gelen başlık uçuşunun etiketi (yol haritası 2.14,
  /// bayrak `varlik_hero_gecisi`). Satır verir; ekran kendisi uydurmaz.
  final Object? heroEtiketi;

  const AssetDetailScreen({
    super.key,
    required this.asset,
    this.showBackButton = false,
    this.lots,
    this.initialScrollOffset = 0,
    this.initialPeriodDays,
    this.heroEtiketi,
  });

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  /// Fiyat kaynağının anladığı sembol; yoksa alarm kurulamaz.
  // Mevduat ve BES'e fiyat alarmı kurulmaz: mevduatın "fiyatı" sözleşmenin
  // tahakkukudur, BES fonu da katılımcının alıp sattığı bir menkul değil
  // (2026-10-01 emülatör testi: ikisinde de alarm zili duruyordu).
  String? get _alarmSembolu => widget.asset.type.sozlesmeli
      ? null
      : alarmSembolu(widget.asset.ticker, widget.asset.subCategory);

  late int _selectedPeriodIdx;

  /// Açılış kapısı açıldı mı — seçili dönem, öteki dönemler ve sinyal
  /// serisi geldi (ya da `acilisSiniri` doldu). Bir kez `true` olur; dönem
  /// değişimi ve nabız tazelemesi ekranı yeniden iskelete DÖNDÜRMEZ.
  bool _acildi = false;
  late Future<Map<int, double>> _historyFuture;
  late ScrollController _scrollController;
  // Compare mode: seçili karşılaştırma varlığı (kullanıcının portföyünden).
  // null = compare kapalı. Bu varlığın history serisi ana varlıkla aynı
  // periyotta fetch edilir, ilk nokta 100 kabul edilip % normalize edilir.
  Asset? _compareAsset;
  Future<Map<int, double>>? _compareHistoryFuture;

  /// Grafikte gezinen imlecin (fiyat, tarih) etiketi; başlıktaki büyük
  /// fiyat bunu dinler (bayrak `goz_alici`, varlık sayfasıyla aynı).
  final _imlec = ValueNotifier<(String, String)?>(null);

  /// Periyot sekmeleri. `days: 0` → GÜN İÇİ (5 dakikalık çözünürlük).
  ///
  /// Etiketler portföy performans ekranıyla AYNI: iki ekran aynı soruyu
  /// soruyor, farklı kelimelerle sormamalı. Ayrıca beş uzun etiket
  /// ("HAFTALIK", "6 AYLIK"…) 360pt genişlikte yan yana sığmıyordu.
  ///
  /// 5Y (A tasarımı, 2026-09-28): varlık sayfasıyla aynı dönem kümesi —
  /// "bu varlık uzun vadede ne yaptı" portföydeki varlık için de sorulur.
  /// Haftalık katman zaten 5 yıllık seri çeker (`yahooRange: 5y`), ek istek
  /// yok. Dönem penceresi takvimden (`_donemBaslangici`).
  ///
  /// 3A ve tek kaynak (2026-09-28): liste uygulamanın tek dönem kümesinden
  /// ([SummaryPeriod]) türetilir; 3A Karşılaştır'da vardı, burada yoktu.
  /// 3A'nın dönem başı da takvimden (`_donemBaslangici` → `ucAy`).
  static final List<({String label, int days})> _allPeriods = [
    for (final p in SummaryPeriod.values) (label: p.label, days: p.days),
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

  /// [_periods]'un [SummaryPeriod] karşılığı — aynı süzgeç, aynı sıra.
  /// Ortak dönem (`donem_hafizasi`) ham indeksle değil dönem DEĞERİYLE
  /// eşlenir: GÜNLÜK'süz listede indeksler bir kayıktır.
  List<SummaryPeriod> get _donemler => [
        for (final p in SummaryPeriod.values)
          if (!p.intraday || _gunIciDestekli) p,
      ];

  /// Ortak dönemin bu ekrandaki indeksi; yoksa en yakın dönemin.
  int _ortakDonemIdx(SummaryPeriod d) =>
      _donemler.indexOf(gosterilebilirDonem(d, _donemler));

  /// Alttaki teknik gösterge panelinin konumu.
  ///
  /// Üstteki sinyal şeridi yalnızca ÖZET verir (yön + kaç gösterge + güven).
  /// "Hangi gösterge ne diyor" sorusunun cevabı sayfanın dibindeki panelde;
  /// kullanıcı şeride dokununca oraya kaydırılır. Aksi halde özet, cevabı
  /// olmayan bir merak uyandırırdı.
  final GlobalKey _sinyalPaneliKey = GlobalKey();

  /// Teknik sinyal yüzeyleri (kart + gösterge paneli) çizilsin mi?
  /// Yatırımcı seviyesi Başlangıç ise ya da paywall açıkken Premium değilse
  /// hayır — bkz. `sinyalYuzeyiProvider`.
  bool get _sinyalYuzeyleri =>
      ref.watch(sinyalYuzeyiProvider) == SinyalYuzeyi.acik &&
      // Mevduatın piyasa serisi yok; eğrisi sözleşmenin tahakkukudur ve
      // teknik sinyal anlamsızdır (sunucu da analiz etmez, ANALYZABLE).
      // BES de öyle (2026-10-01 emülatör testi): katılımcı fonu alıp
      // satamaz, yalnız dağılımı değiştirir; devlet katkısı fonunda o da
      // yok. AL/SAT göstergesi orada yanıltıcıdır.
      !widget.asset.type.sozlesmeli;

  /// Sinyal Premium'da (paywall açık, Premium değil): panelin yerine tek
  /// kilit kartı. Sözleşmeli türlerde sinyal hiç olmadığı için kilit de yok.
  bool get _sinyalKilidi =>
      ref.watch(sinyalYuzeyiProvider) == SinyalYuzeyi.kilitli &&
      !widget.asset.type.sozlesmeli;

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

  /// Dönem (gün) → birim seri, dönem başı ve istatistik — çip getirileri,
  /// başlık ve istatistik ızgarası buradan okur (bkz. `asset_detail/ozet.dart`).
  final Map<int, Map<int, double>> _donemSerileri = {};
  final Map<int, double?> _donemIlk = {};
  final Map<int, DonemIstatistigi?> _donemIstatistikleri = {};
  DateTime? _gunIciSeansOnbellek;

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
    // `donem_hafizasi` (Sadeleştirme 2): HAFTALIK varsayılanı yerine
    // uygulamanın ortak dönemi. Çağıranın isteği (bildirim → GÜNLÜK) yine
    // önce gelir ve ortak döneme yazılır. Ortak dönem burada yoksa (elle
    // fiyatlanan varlıkta GÜNLÜK) en yakını gösterilir, ortak değer kalır.
    if (donemHafizasiAcik) {
      final istekIdx = istenen == null
          ? -1
          : _periods.indexWhere((p) => p.days == istenen);
      if (istekIdx >= 0) {
        // Sağlayıcı kurulum sırasında değiştirilemez; kareden sonra yazılır.
        Future.microtask(() {
          if (mounted) {
            ref.read(seciliDonemProvider.notifier).state = _donemler[istekIdx];
          }
        });
      } else {
        _selectedPeriodIdx = _ortakDonemIdx(ref.read(seciliDonemProvider));
      }
    }
    _historyFuture = _loadHistory(_periods[_selectedPeriodIdx].days);
    // Öteki dönemler seçiliyi beklemeden, paralel (çip getirileri).
    final digerleri = _digerDonemleriYukle();
    CrashReporter.arkaPlan(digerleri, reason: 'AssetDetail.digerDonemler');
    // Açılış kapısı (kullanıcı kararı 2026-09-28, `acilis_kapisi.dart`):
    // ekran parça parça değil, hepsi gelince BİRLİKTE dolar. Sinyal şeridi
    // ve paneli aynı sembol serisini okur; burada aynı anda istenir,
    // `HistoryService` önbelleği onlara ağa çıkmadan verir.
    final sinyalSerisi =
        ref.read(sinyalYuzeyiProvider) == SinyalYuzeyi.acik &&
                widget.asset.ticker.trim().isNotEmpty
            ? HistoryService.instance.getSymbolHistory(widget.asset.ticker,
                periodDays: kSinyalPenceresiGun)
            : null;
    CrashReporter.arkaPlan(
      acilisKapisi([
        _historyFuture,
        digerleri,
        if (sinyalSerisi != null) sinyalSerisi,
      ]).then<void>((_) async {
        if (!mounted) return;
        await rotaGecisiniBekle(context);
        if (mounted) setState(() => _acildi = true);
      }),
      reason: 'AssetDetail.acilis',
    );
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialScrollOffset);
    _nabziBirak = TazelikRitmi.nabiz.dinle(_nabizGeldi);
  }

  /// Seçili dönemin BAŞLANGICI — Performans ekranıyla AYNI pencere.
  ///
  /// Eskiden `now − gün` idi (gün ortasından başlayan, "1A" = 30 gün).
  /// Performans ise takvimden ve gün başından sayıyor (`PeriodSummaryService
  /// .pencere`: "1A" = bir önceki ayın aynı günü, 00:00). İki ekran farklı
  /// dönem başı kullanınca aynı "1A" farklı iki fiyattan ölçülüyordu ve
  /// kullanıcının istediği eşitlik (varlık ekranı ↔ Performans › tür filtresi,
  /// 2026-09-23) tanım gereği sağlanamıyordu.
  static DateTime _donemBaslangici(int days, DateTime now) {
    for (final p in SummaryPeriod.values) {
      if (!p.intraday && p.days == days) {
        return PeriodSummaryService.pencere(p, now).start;
      }
    }
    return dayKey(now.subtract(Duration(days: days)));
  }

  /// [a]'nın BİRİM fiyat serisi (1 gram / 1 adet / 1 pay, TL) — seçili
  /// dönem için, Performans ekranıyla AYNI motor ve çözünürlükten.
  ///
  /// Motor: gün içi → `...HourlyBreakdown` (Performans GÜNLÜK), diğerleri →
  /// `...BreakdownAtResolution` + `pickForSpan` (Performans'ın
  /// `ZoomDataController`'ı). Eskiden bu ekran `getPortfolioHistory(days)`
  /// kullanıyordu: farklı tarih kapısı (gün/saate YUVARLANMIŞ `addedDate`)
  /// ve farklı son-nokta kuralı. Aynı ürün iki ekranda iki motordan
  /// geçince uçlar da ayrışıyordu.
  Future<PortfolioHistoryBreakdown> _donemSerisi(List<Asset> defter, int days) {
    if (days == 0) {
      // Tur beklemesi çağıranda (`_loadHistory`), defter kurulmadan önce.
      return HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown(defter, 24);
    }
    final now = DateTime.now();
    final from = _donemBaslangici(days, now);
    return HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: defter,
      from: from,
      to: now,
      tier: ResolutionTierMeta.pickForSpan(
          now.difference(from).inMinutes / (60.0 * 24.0)),
    );
  }

  /// Son başlatılan yüklemenin sırası — geç dönen ESKİ bir dönemin sonucu
  /// yenisinin alanlarını ezmesin (hızlı sekme değişimi).
  int _yuklemeSirasi = 0;

  /// Dönemin BİRİM fiyat serisini yükler (grafik, yüzde VE kazanç tutarı).
  ///
  /// ## Neden birim seri (kullanıcı kararı, 2026-09-23)
  /// *"Portföyden varlığa girildiğinde zaman aralığına göre 1 gram ya da bir
  /// lot varlığın grafiğini göstermeli; diğer alanlarda da kazanç
  /// hesaplanarak yazılmalı."*
  ///
  /// Grafik ve yüzde ÜRÜNÜ anlatır (alım/satım onları oynatamaz), tutar
  /// SAHİBİ anlatır: `PeriodSummaryService.birimPiyasaEtkisi` bu seriyle
  /// lot miktarlarından hesaplar.
  ///
  /// **Pozisyon serisi artık çekilmiyor** (emülatörde ölçüldü, aynı gün).
  /// İlk sürüm tutarı motorun pozisyon serisinden alıyordu; bugün açılan
  /// 100 gr gramda **−₺619.300** yazdı — motor alım saatini 5 dk'lık kovaya
  /// yuvarlıyor, katkı sınırı ham damgayı kullanıyordu; alım hem tabanda hem
  /// katkıda sayıldı.
  Future<Map<int, double>> _loadHistory(int days) async {
    final sira = ++_yuklemeSirasi;
    // CANLI görünüm: motor gün içi serinin ucunu (ve altında gün başını)
    // lot'un `currentPrice`'ından kurar; ekran açıldığı andaki kopya
    // (`widget.asset`) her nabızda bir tur daha bayatlardı.
    //
    // Süren fiyat turu `_canli` OKUNMADAN önce beklenir (2026-09-24):
    // bildirimden soğuk açılan ekran açılış turunun ortasına düşer ve
    // `_canli` o anki (DB'den gelen) fiyatı taşır. `_canli` provider'ı
    // doğrudan okuduğu için kare beklemeye gerek yok — gerekçe
    // `TazelikRitmi.turuBekle`.
    await ref
        .read(portfolioProvider.notifier)
        .fiyatTurunuBekle(enFazla: TazelikRitmi.gunIciSeriOmru);
    if (!mounted) return const {};
    final birim =
        await _donemSerisi([FiyatKaynagi.birimVarlik(_canli.asset)], days);
    if (mounted && sira == _yuklemeSirasi) {
      if (days == 0) _gunIciBaslangic = birim.seansGunu;
      if (birim.total.isNotEmpty) _lastHistory = birim.total;
    }
    // Dönem önbelleği sıradan bağımsız: geç dönen eski dönemin serisi de
    // KENDİ çipine yazılır, seçili dönemi ezmez.
    if (mounted) {
      _guncelle(() => _donemKaydet(days, birim.total, birim.seansGunu));
    }
    return birim.total;
  }

  /// Kazanç tutarının lot defteri — birleşik varlık DEĞİL, gerçek lot'lar.
  ///
  /// `widget.asset` bir POZİSYON görünümüdür (`Position.asDisplayAsset`):
  /// `quantity` bugünkü TOPLAM, `addedDate` İLK alım. Onunla hesaplanan
  /// kazanç, bugün alınan lot'u dönemin tamamında varmış gibi sayar ve
  /// alımı piyasa hareketi sanır (ölçüldü 2026-09-23: 10 gram varken 10
  /// gram daha alınınca −%0,78'lik gün −%50 görünüyordu). Lot listesi yoksa
  /// birleşik varlığa düşülür — uydurma yok.
  List<Asset> get _seriDefteri {
    final canli = _canli;
    final lots = canli.lots;
    if (lots.isEmpty) return [canli.asset];
    final gecerli = [for (final l in lots) if (!l.isDeleted) l];
    return gecerli.isEmpty ? [canli.asset] : gecerli;
  }

  /// Varlığın CANLI pozisyon görünümü: güncel defterden, güncel fiyatla.
  ///
  /// ## Neden (kullanıcı isteği, 2026-09-24)
  /// *"Anasayfa günlük, varlık günlük performans, Performans günlük'te
  /// grafik ve özet kısmı her varlık tipi için birbirleriyle aynı kaynaktan
  /// tutarlı değerleri göstermeli. Ve senkron şekilde yenilenmeliler."*
  ///
  /// `widget.asset` açılış anında kurulmuş bir KOPYADIR
  /// (`Position.asDisplayAsset` yeni bir `Asset` döner). `refreshPrices`
  /// fiyatı defterdeki lot'lara yazar, bu kopyaya değil: ekran açık
  /// kaldıkça ana sayfa ve Performans yeni fiyatla ilerlerken burada
  /// değer, yüzde ve grafiğin ucu açılış anının fiyatında DONUYORDU.
  ///
  /// Sahibin lot'ları defterden (kendi) ya da ortak listesinden süzülür —
  /// `userId` ile, çünkü iki sahibin aynı ürünü aynı pozisyon anahtarını
  /// taşır. Pozisyon artık yoksa (hepsi satıldı/silindi) açılış görünümü
  /// kalır; uydurma yok. Kaynak listeler değişmedikçe yeniden kurulmaz.
  ({Asset asset, List<Asset> lots, bool acik}) get _canli {
    final pState = ref.read(portfolioProvider).valueOrNull;
    final ortaklar = ref.read(allPartnerAssetsProvider).valueOrNull;
    final kendi = pState?.assets;
    if (_canliOnbellek != null &&
        identical(kendi, _canliKendi) &&
        identical(ortaklar, _canliOrtaklar)) {
      return _canliOnbellek!;
    }
    final sahip = widget.asset.userId;
    var sahipLotlari = <Asset>[
      for (final a in kendi ?? const <Asset>[])
        if (a.userId == sahip) a,
      for (final lots in (ortaklar ?? const <String, List<Asset>>{}).values)
        for (final a in lots)
          if (a.userId == sahip) a,
    ];
    // Çoklu portföy (0133): ekran bir PORTFÖYÜN pozisyonundan açıldıysa
    // (görünüm karışık değil) canlı pozisyon da o portföyün lotlarından
    // kurulur — yoksa "Emeklilik"teki ASELS'e girip Al/Sat'a basan kullanıcı
    // bütün portföylerin havuzunu görür ve satış yanlış maliyetle yazılırdı.
    // Yalnız KENDİ lotlarında (ortağın portföy kimliği bu kullanıcıda
    // anlamsız) ve bayrak açıkken; kapalıyken bu blok hiç koşmaz.
    if (RemoteConfigService.instance.cokluPortfoy &&
        !widget.asset.portfoyKarisik &&
        sahip == pState?.ownerId) {
      final bilinen = {
        for (final p in ref.read(portfoylerProvider).valueOrNull ??
            const <Portfoy>[])
          p.id,
      };
      final hedef = lotunPortfoyu(widget.asset, bilinen);
      sahipLotlari = [
        for (final a in sahipLotlari)
          if (lotunPortfoyu(a, bilinen) == hedef) a,
      ];
    }
    final p = _positionOf(sahipLotlari);
    // `acik`: sahibin bu üründe BUGÜN açık pozisyonu var mı
    // (`aggregatePositions` kapanmışı döndürmez, CLAUDE.md "Kapanmış
    // pozisyon"). İşlem çubuğu buna bakar — Portföy listesi de yalnız açık
    // pozisyonu satır yapar, kaydırma yalnız orada vardır.
    final sonuc = p == null
        ? (asset: widget.asset, lots: widget.lots ?? [widget.asset], acik: false)
        : (asset: p.asDisplayAsset(), lots: p.lots, acik: true);
    _canliKendi = kendi;
    _canliOrtaklar = ortaklar;
    _canliOnbellek = sonuc;
    return sonuc;
  }

  ({Asset asset, List<Asset> lots, bool acik})? _canliOnbellek;
  List<Asset>? _canliKendi;
  Map<String, List<Asset>>? _canliOrtaklar;

  /// Ortak nabzın dinleyicisini kaldıran işlev (bkz. [_nabizGeldi]).
  VoidCallback? _nabziBirak;

  /// Ortak nabız — ana sayfa Bugün kartı ve Performans ile AYNI tick.
  ///
  /// Bu ekran nabzı hiç dinlemiyordu: GÜNLÜK seri açılışta bir kez
  /// çekiliyor ve öyle kalıyordu. Nabız fiyat turunu dinleyicilerden ÖNCE
  /// bitirir (`TazelikNabzi.fiyatTuruBagla`), yani seri burada o turun
  /// fiyatıyla çekilir — diğer yüzeylerle aynı anın verisi.
  ///
  /// Sessiz tazeleme: yeni seri gelene kadar eskisi çizili kalır ve
  /// future ancak sonuç ELDEYKEN değiştirilir (`SynchronousFuture`);
  /// aksi halde her 30 sn'de yükleme çubuğu yanıp sönerdi. Başarısız ya
  /// da boş çekim eldekini EZMEZ.
  Future<void> _nabizGeldi() async {
    if (!mounted || !_gunIciMi) return;
    final Map<int, double> seri;
    final yukleme = _loadHistory(0);
    final sira = _yuklemeSirasi;
    try {
      seri = await yukleme;
    } catch (_) {
      return; // eldeki seri kalır; ağ hatası bir sonraki nabızda denenir
    }
    if (!mounted || sira != _yuklemeSirasi || !_gunIciMi) return;
    if (seri.length < 2) return;
    _guncelle(() => _historyFuture = SynchronousFuture(seri));
  }

  @override
  void dispose() {
    _imlec.dispose();
    _nabziBirak?.call();
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
  ///
  /// **Karşılaştırma da BİRİM seridir** (2026-09-23). Portföyden seçilen
  /// varlık eskiden olduğu gibi (birleşik pozisyon) çekiliyordu: dönem
  /// içinde alınmışsa çizgisi alım anında başlıyor ya da sıçrıyordu —
  /// yüzde normalizasyonu miktar değişimini fiyat hareketi gibi okuyordu.
  /// Ana seriyle aynı motor ve pencereden gelir ki iki çizgi aynı soruyu
  /// ("ürün ne yaptı") yanıtlasın.
  Future<Map<int, double>> _karsilastirmaSerisi(Asset asset, int days) async {
    final birim = FiyatKaynagi.birimVarlik(asset);
    if (days != 0) {
      return (await _donemSerisi([birim], days)).total;
    }
    // Ana serinin future'ı ŞİMDİ yakalanır: `_selectPeriod` ikisini aynı
    // `setState` içinde başlatıyor ve alan sonra değişebilir.
    final anaSeri = _historyFuture;
    final b = await _donemSerisi([birim], 0);
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

  /// `setState` sarmalayıcısı — part dosyalarındaki extension'lar için.
  ///
  /// Ekran 3.800 satırdı; sinyal widget'ları, şeritler, karşılaştırma seçici
  /// ve eylemler `asset_detail/` altındaki part dosyalarına bölündü (aynı
  /// kütüphane, private erişim aynen). `setState` `@protected` olduğu için
  /// extension içinden çağrılamaz; bu ince sarmalayıcı tek geçiş noktasıdır.
  void _guncelle(VoidCallback fn) => setState(fn);

  /// EMA ısınma serisi (dönem öncesi çubuklar) ve hangi dönem için istendiği
  /// — `asset_detail/grafik_katmanlari.dart`.
  ({int gun, Map<int, double> seri})? _emaOnSeri;
  int? _emaOnSeriGun;

  /// Mumun GÜNLÜK seri kaynağı (grafik haftalık çizerken) — aynı dosya.
  ({int gun, Map<int, double> seri})? _mumSerisi;
  int? _mumSerisiGun;

  /// Gerçek mumlar (OHLC, aralık seçicisi) ve hangi istek için geldikleri
  /// — aynı dosya. [_ohlcIstenen] aynı isteği ikinci kez başlatmamak için.
  ({MumAraligi aralik, int basMs, List<OhlcBar> barlar})? _ohlc;
  String? _ohlcIstenen;

  @override
  Widget build(BuildContext context) {
    // Baz para birimi BİR KEZ burada okunur: alt widget'lara parametre
    // gider. Yalnızca DEĞER tutarları (PnL, dönem değişimi) çevrilir;
    // grafiğin ekseni/ipucu kote FİYATTIR ve ₺ kalır. "Bakiyeyi gizle"
    // açıksa bu DEĞER tutarları maskelenir (`gosterimBazParaProvider`,
    // bulgu #3); fiyat bakiye değildir, açık kalır.
    final baz = ref.watch(gosterimBazParaProvider);
    // `donem_hafizasi`: ortak dönem başka yüzeyde (üstte açılan Karşılaştır
    // ya da varlık sayfası) değişirse bu ekran da geçer.
    if (donemHafizasiAcik) {
      ref.listen<SummaryPeriod>(seciliDonemProvider, (_, yeni) {
        final idx = _ortakDonemIdx(yeni);
        if (idx != _selectedPeriodIdx) _selectPeriod(idx);
      });
    }
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
    //   · Diğer dönemler Performans ekranıyla AYNI pencerede başlar
    //     (takvim + gün başı, bkz. `_donemBaslangici`).
    final startDate = isIntraday
        ? (_gunIciBaslangic ??
            dayKey(endDate))
        : _donemBaslangici(period.days, endDate);
    // Kesirli gün — saatlik veride son X gün sınırında değil, gerçek
    // anlarında olmalı. Yoksa nokta grafiğin ortasında yalnız kalır.
    final maxX = isIntraday
        ? 1.0
        : endDate.difference(startDate).inMinutes / (60.0 * 24.0);

    // Logic moved inside FutureBuilder

    // Ortak lot'ları değişince ekran yeniden kurulsun: ortağın varlığı
    // açıksa `_canli` onları `ref.read` ile okur, tetikleyici bu izlemedir.
    //
    // Ölü kod temizliği (Sadeleştirme 2, madde 11, 2026-10-04): burada bir
    // de "Ben / ortak / Tümü" sekmesi (`OrtakSecici`, `_view`) ve üst
    // çubukta "Sil" menüsü vardı; ikisi de `!showBackButton` koşuluyla
    // çiziliyordu ama ekranı açan HER yol (Ana, Portföy, `pozisyonuAc`,
    // bildirim) `showBackButton: true` verir — hiç görünmüyorlardı. Silme
    // Portföy kartının kaydırmasında; ortak görünümü Portföy'ün kendi
    // seçicisinde.
    ref.watch(allPartnerAssetsProvider);
    final pState = ref.watch(portfolioProvider).valueOrNull;
    // Mevduat dönemi eklenince seri yeniden üretilir (bkz.
    // `_sozlesmeSerileriniTazele`). Varlık sayfa ömrü boyunca değişmez,
    // dinleyici koşulu sabittir.
    final sozlesmeId = widget.asset.sozlesmeId;
    if (sozlesmeId != null && widget.asset.type == AssetType.mevduat) {
      ref.listen(sozlesmeProvider, (onceki, sonraki) {
        final a = onceki?.valueOrNull?.donemleri(sozlesmeId).length;
        final b = sonraki.valueOrNull?.donemleri(sozlesmeId).length;
        if (a != null && b != null && a != b) _sozlesmeSerileriniTazele();
      });
    }

    final currentUserId = ref.watch(authProvider).valueOrNull?.id;
    final isOwnAsset = currentUserId != null && widget.asset.userId == currentUserId;
    final pnl = _pnlOzeti(pState);
    // Katmanlı düzen (S4, `varlik_detay_katmanli`): grafiğin altı
    // `asset_detail/katmanlar.dart`'ta. Kapalıyken aşağıdaki eski yığın
    // birebir.
    final katmanli = RemoteConfigService.instance.varlikDetayKatmanli;

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        // Başlık artık gövdede (kısa etiket + ad · tür, varlık sayfasıyla
        // aynı); üst çubukta ikinci kez yazılmaz.
        transparent: true,
        showBack: widget.showBackButton,
        actions: [
          TakipYildizi(kimlik: _kimlik),
          // Fiyat alarmı BURADAN kurulur (2026-09-14): alarm varlığa aittir,
          // Ayarlar'daki liste yalnızca gösterir. Sembolü olmayan (manuel
          // fiyatlı) varlıkta zil yok — sunucu fiyatını izleyemez.
          //
          // Tek giriş noktası burası (2026-09-18): sinyal kartının altındaki
          // "Alarm kur" butonu kaldırıldı, aynı eylem iki yerde duruyordu.
          // Zil DURUM taşır: aktif alarm varsa dolu ikon + amber — kullanıcı
          // ekrana girer girmez "bu varlıkta alarmım var" der.
          if (_alarmSembolu != null)
            IconButton(
              tooltip: context.l10n.setPriceAlert,
              icon: ref
                      .watch(symbolAlertsProvider(_alarmSembolu!))
                      .any((a) => a.isActive)
                  ? Icon(Icons.notifications_active_rounded,
                      color: context.c.amberText)
                  : Icon(Icons.add_alert_outlined, color: context.c.text90),
              onPressed: () => alarmKurAkisi(
                context,
                ref,
                sabit: AlarmAdayi(
                    _alarmSembolu!, widget.asset.name, _canli.asset.currentPrice),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _islemCubugu(isOwnAsset),
      body: SafeArea(
        child: RefreshIndicator.adaptive(
      color: context.c.amberText,
      onRefresh: () => ref.read(portfolioProvider.notifier).refreshPrices(force: true),
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
          controller: _scrollController,
          child: Padding(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 12, SandikSpace.screenH(context), 24),
            child: Column(
              children: [
                // Başlık + güncel fiyat + pozisyon satırı (A tasarımı).
                Align(alignment: Alignment.centerLeft, child: _baslik()),
                const SizedBox(height: SandikSpace.md),
                // Başlık yerelden gelir, hemen yazılır; geri kalan her şey
                // açılış kapısı açılınca BİRLİKTE (bkz. `_acildi`).
                if (!_acildi)
                  const VarlikIskeleti()
                else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _fiyatBlogu(pnl, baz),
                ),
                const SizedBox(height: SandikSpace.md),
                // Sinyal özeti fiyatın hemen altında — dokununca aşağıdaki
                // panele kaydırır (kullanıcı: "işlevi güzel").
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
                // Katmanlı düzende kart "Analiz" bölümüne, gösterge
                // panelinin yanına taşınır (`_analizKatmanlari`).
                if (_sinyalYuzeyleri && !katmanli)
                  AssetSignalCard(
                    asset: widget.asset,
                    onTap: _sinyalPaneline,
                  ),
                if (_sinyalYuzeyleri)
                  SinyalVarlikSeridi(asset: widget.asset),
                // Kurulu alarmlar (boşken hiç çizilmez; alt boşluğunu kendi
                // taşır — bkz. AlarmSeridi).
                if (_alarmSembolu != null)
                  AlarmSeridi(
                    sembol: _alarmSembolu!,
                    ad: widget.asset.name,
                    guncelFiyat: _canli.asset.currentPrice,
                  ),
                const SizedBox(height: SandikSpace.sm),
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
                        height: GrafikStili.kartYuksekligi,
                        child: waiting
                            ? const SandikSkeletonChart(
                                height: GrafikStili.kartYuksekligi)
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
                    // Canlı görünüm — `_pnlOzeti` (asset_detail/ozet.dart):
                    // başlıktaki satır, PnL şeridi ve uç rengi aynı sayılar.
                    final currentUnitTRY = pnl.currentUnitTRY;

                    // Compare mode devrede mi? Öncelikli — log-scale ile
                    // aynı anda anlamlı değil (biri % biri log), compare
                    // aktifken log ignore edilir.
                    final compareOn = _compareAsset != null;
                    final logOnPref = ref.watch(chartLogScaleProvider);
                    // Araçlar gizliyse (sade Başlangıç) önceden açılmış
                    // MA20/LOG kapatılamaz hâlde kalmasın: etkisiz sayılır.
                    final araclar =
                        ref.watch(seviyeGorunurlukProvider).grafikAraclari;
                    final logOn = compareOn || !araclar ? false : logOnPref;
                    // Göz alıcılık (bayrak `goz_alici`): büyük fiyat imleci
                    // izler. Karşılaştırmada YOK — çizgi % ölçeğinde, başlık
                    // ise birim fiyat; % değeri fiyat yerine yazılırsa
                    // "₺" başlığında "+%12" okunurdu. Mevduatta başlık birim
                    // değil pozisyon değeri, seri onu çizmiyor.
                    final imlecAcik = RemoteConfigService.instance.gozAlici &&
                        !compareOn &&
                        widget.asset.type != AssetType.mevduat;

                    final rawSegments = _convertHistoryToSegments(
                        historyMap, startDate, endDate,
                        currentUnitPriceOverride: currentUnitTRY);

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
                      if (logOn) return log10Fiyat(y);
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
                    final ma20On = araclar && ref.watch(chartMA20Provider);
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
                    // EMA50 / EMA200 ve mum — Premium katmanlar
                    // (`asset_detail/grafik_katmanlari.dart`). Görünmüyorsa
                    // ya da kilitliyse hiçbiri çizilmez; eski grafik birebir.
                    // Karşılaştırmada mum yok (çizgi % ölçeğinde, iki seri
                    // aynı eksende kıyaslanır); EMA da yok — ikinci serinin
                    // ortalaması çizilmediği için yalnız birine ait olurdu.
                    final katmanAcik = araclar &&
                        _katmanlarGorunur &&
                        !_katmanlarKilitli;
                    final mumOn = katmanAcik &&
                        !compareOn &&
                        ref.watch(chartCandleProvider);
                    final ema50On = katmanAcik &&
                        !compareOn &&
                        ref.watch(chartEma50Provider);
                    final ema200On = katmanAcik &&
                        !compareOn &&
                        ref.watch(chartEma200Provider);
                    final hamAktif = rawSegments
                        .firstWhere(
                          (s) => !s.piyasaKapali && s.spots.isNotEmpty,
                          orElse: () => rawActiveForBase,
                        )
                        .spots;
                    final seciliGun = _periods[_selectedPeriodIdx].days;
                    if (ema50On || ema200On) _emaOnSeriniIste(seciliGun);
                    if (mumOn) _mumSerisiniIste(seciliGun);
                    // Gerçek mumlar (aralık seçicisi, 2026-10-10). Gelene
                    // kadar ya da bu dönemde geçerli aralık yoksa aşağıdaki
                    // türetilmiş mum çizilir.
                    final mumAr = mumOn
                        ? _mumAraligi(isIntraday, startDate, endDate)
                        : null;
                    final ohlcAr = mumAr?.aralik;
                    final ohlcBarlar = ohlcAr == null
                        ? null
                        : _ohlcBarlari(ohlcAr, isIntraday, startDate,
                            endDate, currentUnitTRY);
                    final ohlcMumlar = (ohlcAr == null || ohlcBarlar == null)
                        ? const <Mum>[]
                        : _ohlcMumlari(ohlcBarlar, ohlcAr, startDate);
                    final mumHam = mumOn
                        ? _mumNoktalari(seciliGun, startDate, endDate,
                                currentUnitTRY) ??
                            hamAktif
                        : hamAktif;
                    final emaCizgileri = (ema50On || ema200On)
                        ? _emaCizgileri(
                            hamSeri: hamAktif,
                            onSeri: _emaOnNoktalari(seciliGun, startDate),
                            toY: toY,
                            ema50: ema50On,
                            ema200: ema200On,
                          )
                        : const <({List<FlSpot> spots, Color renk})>[];
                    final anchorY = anchorSpot?.y ?? 0.0;

                    // İşlem işaretleri — GERÇEK işlem anında, ÇİZGİNİN
                    // ÜZERİNDE; gerçek işlem fiyatı crosshair'da yazılır
                    // (gerekçe ve karar geçmişi `islemIsaretleri`).
                    final activeLots = _canli.lots;
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
                    final islemler = primarySpots.isEmpty
                        ? const <IslemIsareti>[]
                        : islemIsaretleri(
                            lotlar: activeLots,
                            eksenBasi: startDate,
                            ilkX: primarySpots.first.x,
                            sonX: primarySpots.last.x,
                          );
                    // Varlık ekranının çizgisi TEK segmenttir
                    // (`_convertHistoryToSegments`, eylemler.dart) ve
                    // işaretler onun X aralığına kırpılır (`ilkX`/`sonX`),
                    // yani değer her zaman vardır. Spot'lar `toY` uzayında.
                    final islemSpots = [
                      for (final t in islemler)
                        FlSpot(t.x, cizgiDegeri(primarySpots, t.x)!),
                    ];

                    // Y sınırlarını görünür X aralığındaki spot'lara göre
                    // hesaplayan closure — zoom sırasında yeniden çağrılır.
                    // Fiyat bandı Performans ile AYNI kuraldan (`gorunurYBandi`,
                    // grafik stili kararı 2026-09-28): eskiden bu ekran bandı
                    // dönem başına ortalayıp %35 pay bırakıyordu; çizgi kartın
                    // ortasında ince bir şeride sıkışıyor ve iki ekran aynı
                    // seriyi farklı ölçekte çiziyordu. Karşılaştırma ve
                    // işlem işaretleri de banda girer (`extraSpots`).
                    // Asgari bant %2: fiyat grafiği (varlık sayfasıyla
                    // aynı); Performans'ın %8'i portföy DEĞERİ içindir ve
                    // tek hissenin haftalık hareketini düzleştirirdi.
                    ({double minY, double maxY, double interval}) computeY(
                        double viewMinX, double viewMaxX,
                        {List<FlSpot>? extraSpots}) {
                      double minY = double.infinity;
                      double maxY = -double.infinity;
                      double top = 0;
                      int adet = 0;
                      void kat(FlSpot spot) {
                        if (spot.x < viewMinX || spot.x > viewMaxX) return;
                        if (spot.y > maxY) maxY = spot.y;
                        if (spot.y < minY) minY = spot.y;
                        top += spot.y;
                        adet++;
                      }
                      for (final seg in segments) {
                        seg.spots.forEach(kat);
                      }
                      extraSpots?.forEach(kat);
                      if (adet == 0) {
                        final y = anchorY > 0 ? anchorY : 1.0;
                        minY = y;
                        maxY = y;
                        top = y;
                        adet = 1;
                      }
                      return gorunurYBandi(
                        dataMinY: minY,
                        dataMaxY: maxY,
                        avgY: top / adet,
                        asgariBantOrani: isIntraday
                            ? gunIciAsgariBantOrani
                            : (compareOn || logOn ? 0.0 : 0.02),
                        // LOG bandı (log10 biriminde) — eskiden ₺ için olan
                        // 1'lik taban bütün bir onluk demekti; mum ve EMA
                        // düz çizgiye eziliyordu. Şimdilik yalnız Premium
                        // katmanları gören hesapta (paywall_enabled/admin):
                        // ücretsiz LOG kullanıcısının ekranı birebir kalır.
                        asgariAralik: logOn && _katmanlarGorunur ? 1e-3 : 1.0,
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
                        // PnL şeridi ve dönem değişimi satırı grafiğin
                        // ALTINDAKİ pozisyon bölümüne taşındı (A tasarımı,
                        // 2026-09-28); ikisi de artık seri beklemeden durur.
                        //
                        // Dönem seçici grafiğin ÜSTÜNDE — Performans ve
                        // varlık sayfasıyla aynı sıra (kullanıcı kararı
                        // 2026-09-28: altındayken GÜNLÜK ↔ diğer geçişinde
                        // grafik boyu değişince seçici zıplıyordu; gerekçe
                        // `portfolio_performance/kartlar.dart`). Getiri
                        // satırı çipin altında kalır — veri kaybı yok.
                        _donemCipleri(pnl.currentUnitTRY),
                        const SizedBox(height: SandikSpace.sm),
                        // Grafik overlay chip'leri (MA20 vb.). Basit toggle.
                        // Sade Başlangıç'ta (`seviye_anketi`) gizli.
                        if (araclar)
                          Builder(builder: (_) {
                            final ma20Cip = _OverlayChip(
                              label: 'MA20',
                              active: ma20On,
                              onTap: () {
                                ref
                                    .read(chartMA20Provider.notifier)
                                    .set(!ma20On);
                              },
                            );
                            final logCip = _OverlayChip(
                              label: 'LOG',
                              active: logOn,
                              onTap: () {
                                ref
                                    .read(chartLogScaleProvider.notifier)
                                    .set(!logOn);
                              },
                            );
                            // Tam ekran çipi KALDIRILDI (kullanıcı kararı,
                            // 2026-09-17): "çok da bir avantajı yok gibi,
                            // ilerde talep edilirse yaparız." Geçmiş
                            // uygulama ve yön davranışı git geçmişinde
                            // (ea7bc0a).
                            if (!_katmanlarGorunur) {
                              // Premium katmanlar görünmüyor: satır BİREBİR
                              // eskisi (canlıdaki kullanıcı etkilenmez).
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ma20Cip,
                                  const SizedBox(width: 6),
                                  logCip,
                                ],
                              );
                            }
                            // Beş çip 375pt'ye tek satırda sığmıyor (Wrap
                            // LOG'u tek başına alta düşürüyordu). İki
                            // anlamlı satır: üstte GÖRÜNÜM (mum, ölçek),
                            // altta ORTALAMALAR (MA20, EMA50, EMA200).
                            final k = _katmanCipleri(
                              mumOn: mumOn,
                              ema50On: ema50On,
                              ema200On: ema200On,
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    k.mum,
                                    const SizedBox(width: 6),
                                    logCip,
                                  ],
                                ),
                                // Satır arası boşluk yok: çiplerin 44pt
                                // dokunma payı (HIG, 2026-10-10) zaten
                                // aralık bırakıyor.
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ma20Cip,
                                    const SizedBox(width: 6),
                                    k.ema50,
                                    const SizedBox(width: 6),
                                    k.ema200,
                                  ],
                                ),
                                // Mum açıkken aralık seçicisi (1 dk … ay).
                                if (mumAr != null &&
                                    mumAr.aralik != null &&
                                    mumAr.gecerli.length >= 2)
                                  _aralikSecici(
                                    aralik: mumAr.aralik!,
                                    gecerli: mumAr.gecerli,
                                  ),
                              ],
                            );
                          }),
                        const SizedBox(height: 8),
                        // Karşılaştırma gün içinde de açık — seri
                        // `_karsilastirmaSerisi` ile ana varlıkla aynı
                        // 5 dakikalık ızgaradan gelir.
                        _CompareStrip(
                          // Çip etiketi başlıkla aynı kısa etiket: ham sembol
                          // `MEVDUAT:<uuid>` / `THYAO.IS` yazıyordu.
                          primaryTicker: _kimlik.kisaEtiket,
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
                              duration: SandikMotion.stateOf(context),
                              curve: SandikMotion.enter,
                              child: Container(
                          // Kart Performans'la AYNI (ortak grafik stili).
                          height: GrafikStili.kartYuksekligi,
                          decoration: GrafikStili.kart(context),
                          padding: GrafikStili.kartDolgusu,
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
                            // Adaylar işlem işaretlerinin X'leri (işlem anı).
                            final dotCandidates = [
                              for (final t in islemler) t.x,
                            ];
                            return ZoomableChart(
                            semanticLabel: context.l10n
                                .chartAssetSemantics(_kimlik.kisaEtiket),
                            fullMinX: focusMin,
                            fullMaxX: focusMax,
                            height: GrafikStili.grafikYuksekligi,
                            plotPaddingRight: GrafikStili.yEkseniGenisligi,
                            builder: (viewMinX, viewMaxX) {
                              final yBounds = computeY(
                                viewMinX,
                                viewMaxX,
                                // İşaretler de Y aralığına girer. Artık
                                // çizginin üstündeler (2026-09-24), yani
                                // aralığı genişletmezler; güvence olarak
                                // kalır.
                                // EMA de banda girer: uzun ortalama fiyatın
                                // çok altında/üstünde kalabilir; banda
                                // girmezse açılan çizgi kartın dışında kalır
                                // ve "EMA200 çalışmıyor" diye okunur.
                                extraSpots: [
                                  ...?compareBar?.spots,
                                  ...islemSpots,
                                  for (final e in emaCizgileri) ...e.spots,
                                  ..._ohlcUclari(ohlcMumlar, toY),
                                ],
                              );
                              final viewMinY = yBounds.minY;
                              final viewMaxY = yBounds.maxY;
                              final yInterval = yBounds.interval;
                              // Komşu iki Y etiketinin GERÇEK değer farkı —
                              // log ölçekte en dar aralık en alttadır. Etiket
                              // hanesi buna göre seçilir: `fmtTRYCompact`
                              // "₺1 | ₺1" yazıyordu (2026-09-29 emülatör
                              // testi #7; adım etiketin hassasiyetinden
                              // küçüktü).
                              final yEtiketAdimi =
                                  (fromY(viewMinY + yInterval) - fromY(viewMinY))
                                      .abs();
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
                          // Izgara, eksen ayracı ve eksen yazısı ortak
                          // grafik stilinden (Performans stili, 2026-09-28).
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: yInterval,
                            getDrawingHorizontalLine: (_) =>
                                GrafikStili.izgara(context),
                          ),
                          borderData: GrafikStili.eksenAyraci(context),
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
                                reservedSize: GrafikStili.yEkseniGenisligi,
                                interval: yInterval,
                                getTitlesWidget: (value, meta) {
                                  if (value == meta.min ||
                                      value == meta.max) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = compareOn
                                      ? fmtPctIsaretli(value - 100,
                                          digits: eksenOndaligi(yInterval,
                                              enAz: 1, enCok: 3))
                                      : fmtTRYAxis(
                                          fromY(value), yEtiketAdimi);
                                  return GrafikStili.yEtiketi(label,
                                      stil: GrafikStili.eksenYazisi(context));
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
                                  // Ekran genişliğine sığmayan ara
                                  // etiketler atlanır (`xEtiketiAtlanir`,
                                  // TestFlight bulgusu 2026-10-10).
                                  final xStil =
                                      GrafikStili.eksenYazisi(context);
                                  if (xEtiketiAtlanir(value,
                                      aralik: meta.max - meta.min,
                                      tickAraligi: meta.appliedInterval,
                                      eksenPx: meta.parentAxisSize,
                                      etiketPx: GrafikStili.xEtiketAraligi(
                                        isIntraday
                                            ? '20:48'
                                            : zamanEtiketiOrnegi(
                                                spanGun: span,
                                                gunIci: false),
                                        stil: xStil,
                                        olcek:
                                            MediaQuery.textScalerOf(context),
                                      ))) {
                                    return const SizedBox.shrink();
                                  }
                                  final date = startDate.add(Duration(
                                      minutes:
                                          (value * 60 * 24).round()));
                                  // Gün içi sekmesinde tek bir gün çizilir;
                                  // her etikette aynı tarihi tekrarlamak
                                  // 74pt'lik etiketi kırpar ve okunması
                                  // gereken SAATİ gölgeler. Diğer dönemler
                                  // ortak `zamanEtiketi`nden: bu ekran aynı
                                  // kuralın kopyasını taşıyordu ve yıl
                                  // düzeltmesini ("Oca '26", 2026-09-29
                                  // emülatör testi #21) kaçırırdı.
                                  final label = isIntraday
                                      ? DateFormat('HH:mm', 'tr_TR')
                                          .format(date)
                                      : zamanEtiketi(date,
                                          spanGun: span, gunIci: false);
                                  // Sabit genişlik + ortalama: taşan metin
                                  // ellipsis olur, komşu etiketle çakışmaz.
                                  return GrafikStili.xEtiketi(label,
                                      stil: xStil);
                                },
                              ),
                            ),
                          ),
                          // Performans stili (2026-09-28): dönem başı
                          // YATAY kesikli çizgi + etiketi (tarih ve değer
                          // birlikte — eskiden tarih ayrı bir DİKEY
                          // işaretteydi, Performans'ta 2026-09-12'de
                          // kaldırılan desen); "ŞİMDİ" dikey işareti
                          // Performans'taki gibi gün içi DIŞINDA.
                          // Çapa ALIŞ FİYATI DEĞİL, dönemin ilk birim
                          // fiyatıdır (2026-09-23); alış→bugün pozisyon
                          // bölümünde ayrıca durur. Değer HAM fiyattır
                          // (`normBase`): LOG ve karşılaştırmada çizginin
                          // Y'si dönüştürülmüş olsa da etiket fiyatı yazar.
                          extraLinesData: anchorSpot != null
                              ? ExtraLinesData(
                                  horizontalLines: [
                                    GrafikStili.donemBasi(
                                      context,
                                      anchorY,
                                      etiket: GrafikStili.donemBasiEtiketi(
                                        context,
                                        an: startDate.add(Duration(
                                            minutes: (anchorSpot.x * 1440)
                                                .round())),
                                        deger:
                                            '${fixedFormatter(2).format(normBase)} ₺',
                                        gunIci: isIntraday,
                                      ),
                                    ),
                                  ],
                                  verticalLines: [
                                    if (lastSpot != null && !isIntraday)
                                      GrafikStili.simdiCizgisi(
                                          context, lastSpot.x),
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
                            for (final e in emaCizgileri) _emaCubugu(e),
                            // Mum: aktif (açık piyasa) çizginin yerine;
                            // kapalı piyasa kesikli çizgisi aynen kalır.
                            if (mumOn && ohlcMumlar.isNotEmpty)
                              ..._ohlcCubuklari(
                                mumlar: ohlcMumlar,
                                toY: toY,
                                viewMinX: viewMinX,
                                viewMaxX: viewMaxX,
                                genislik: (MediaQuery.of(context).size.width -
                                        60 -
                                        40)
                                    .clamp(120.0, 2000.0),
                              )
                            else if (mumOn)
                              ..._mumCubuklari(
                                hamSeri: mumHam,
                                startDate: startDate,
                                toY: toY,
                                viewMinX: viewMinX,
                                viewMaxX: viewMaxX,
                                genislik: (MediaQuery.of(context).size.width -
                                        60 -
                                        40)
                                    .clamp(120.0, 2000.0),
                              ),
                            ...segments
                              .where((seg) => !mumOn || seg.piyasaKapali)
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
                                        // Yalnızca "şimdi" noktası
                                        // (Performans stili). Dönem başı
                                        // noktası YOK: "orada alım yapılmış"
                                        // gibi okunuyordu (Performans,
                                        // 2026-09-12); tarihi ve değeri
                                        // dönem başı çizgisinin etiketinde.
                                        // İşlem noktaları ayrı katmanda.
                                        return lastSpot != null &&
                                            spot.x == lastSpot.x &&
                                            spot.y == lastSpot.y;
                                      },
                                      getDotPainter: (spot, percent,
                                              barData, index) =>
                                          GrafikStili.simdiNoktasi(context,
                                              piyasaKapali: segments
                                                  .any((s) => s.piyasaKapali)),
                                    ),
                                    belowBarData: seg.piyasaKapali
                                        ? BarAreaData(show: false)
                                        : GrafikStili.dolgu(context),
                                  );
                              }),
                            // İşlem işaretleri — gerçek an × çizgi üstü
                            // (bkz. `islemler`). Çizgisi yok: kalınlık 0 +
                            // tam saydam renk (0 kalınlık tek başına kıl
                            // çizgi çizer).
                            if (islemSpots.isNotEmpty)
                              LineChartBarData(
                                spots: islemSpots,
                                isCurved: false,
                                barWidth: 0,
                                color: context.c.gain.withValues(alpha: 0),
                                belowBarData: BarAreaData(show: false),
                                dotData: FlDotData(
                                  show: true,
                                  checkToShowDot: (spot, _) =>
                                      dotThinner.shows(spot.x),
                                  getDotPainter: (spot, _, __, i) {
                                    // Ortadaki işlem noktaları uçlardan
                                    // (5.5px) belirgin biçimde küçük — yoğun
                                    // işlem yapılan dönemde grafik boncuk
                                    // dizisine dönüşmesin.
                                    final satis = islemler[i].satis;
                                    return FlDotCirclePainter(
                                      radius: 3.5,
                                      color: satis
                                          ? context.c.loss
                                          : context.c.gain,
                                      strokeColor: context.c.text90,
                                      strokeWidth: 1.2,
                                    );
                                  },
                                ),
                              ),
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
                                // Passive + active segmentler anchor noktasında
                                // aynı (x, y) spot'unu paylaşır → aynı tooltip
                                // iki kere görünür. Yakın olanları filtrele.
                                final seen = <String>{};
                                return touchedSpots.map<LineTooltipItem?>((spot) {
                                  final key =
                                      '${spot.x.toStringAsFixed(2)}|${spot.y.toStringAsFixed(2)}';
                                  if (!seen.add(key)) return null;
                                  // Dakika hassasiyeti — `days: x.toInt()`
                                  // saati atıyordu (crosshair ile aynı kural).
                                  final date = startDate.add(Duration(
                                      minutes: (spot.x * 1440).round()));
                                  final dateLabel = fmtTarihSaat(date);
                                  final tipText = compareOn
                                      ? fmtPctIsaretli(spot.y - 100)
                                      : _birimBicimi(currentUnitTRY)
                                          .format(fromY(spot.y));
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
                              // Gerçek mumda imleç mumun ORTASINA oturur
                              // (TradingView): başlık o mumun kapanışını,
                              // satır dört fiyatını yazar.
                              if (_imlectekiMum(ohlcMumlar, x) case final m?) {
                                return m.merkezX;
                              }
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return x;
                              final clamped =
                                  x.clamp(spots.first.x, spots.last.x);
                              // Sıralı seri → ikili arama. Parmak her
                              // kaydığında çağrılıyor (bkz. nearestSpotIndex).
                              return spots[nearestSpotIndex(spots, clamped)].x;
                            },
                            imlecEtiketi: imlecAcik ? _imlec : null,
                            // Başlıktaki biçimle (varlığın hane sayısı) —
                            // grafik etiketi iki hanede kalır.
                            imlecEtiketiBuilder: imlecAcik
                                ? (x) {
                                    if (_imlectekiMum(ohlcMumlar, x)
                                        case final m?) {
                                      return (
                                        _birimBicimi(currentUnitTRY)
                                            .format(m.kapanis),
                                        _mumZamani(m, startDate, isIntraday),
                                      );
                                    }
                                    final spots = activeSeg.spots;
                                    if (spots.isEmpty) return null;
                                    final snapped =
                                        spots[nearestSpotIndex(spots, x)];
                                    final date = startDate.add(Duration(
                                        minutes: (snapped.x * 1440).round()));
                                    return (
                                      _birimBicimi(currentUnitTRY)
                                          .format(fromY(snapped.y)),
                                      isIntraday
                                          ? DateFormat('d MMM · HH:mm', 'tr_TR')
                                              .format(date)
                                          : fmtTarihSaat(date),
                                    );
                                  }
                                : null,
                            // Dönemin zirvesi ve dibinde hafif titreşim (log
                            // ölçek tekdüze: uçlar aynı noktalar).
                            titresimNoktalari: imlecAcik
                                ? donemUclariX(activeSeg.spots)
                                : const {},
                            crosshairLabelBuilder: (x) {
                              if (_imlectekiMum(ohlcMumlar, x) case final m?) {
                                return (
                                  tryFormatter(digits: 2).format(m.kapanis),
                                  _mumZamani(m, startDate, isIntraday),
                                );
                              }
                              // x zaten snap edildi — spot'u bul.
                              final spots = activeSeg.spots;
                              if (spots.isEmpty) return null;
                              final snapped =
                                  spots[nearestSpotIndex(spots, x)];
                              final date = startDate.add(Duration(
                                  minutes:
                                      (snapped.x * 1440).round()));
                              final title = compareOn
                                  ? fmtPctIsaretli(snapped.y - 100)
                                  : tryFormatter(digits: 2)
                                      .format(fromY(snapped.y));
                              // Gün içinde okunacak bilgi SAATTİR; tarih
                              // zaten sekmenin kendisinden belli.
                              //
                              // Diğer dönemlerde de SAAT yazılır — saatlik
                              // çubukta (1H) ve "şimdi" noktasında. Kullanıcı
                              // isteği (2026-09-24): "grafik üzerinde
                              // gezinirken hangi saatteyim görmeliyim."
                              // Günlük/haftalık çubuk 00:00'a oturur; orada
                              // `fmtTarihSaat` yalnızca tarih yazar.
                              final subtitle = isIntraday
                                  ? DateFormat('d MMM · HH:mm', 'tr_TR')
                                      .format(date)
                                  : fmtTarihSaat(date);
                              return (title, subtitle);
                            },
                            // Crosshair bir işlemin çubuğuna gelince işlemin
                            // KENDİ zamanı ve fiyatı yazılır — çizginin o
                            // andaki değeri alış fiyatı değildir (bkz.
                            // `islemler`). Eşleşme "en yakın nokta" ile:
                            // işaretin yanına gelen nokta onu gösterir.
                            // Gerçek mumda imlecin altındaki mumun dört fiyatı
                            // da yazılır (TradingView'in A/Y/D/K satırı).
                            crosshairDetailsBuilder: islemler.isEmpty &&
                                    ohlcMumlar.isEmpty
                                ? null
                                : (x) {
                                    final mum =
                                        _imlectekiMum(ohlcMumlar, x);
                                    final spots = activeSeg.spots;
                                    if (spots.isEmpty) {
                                      return [
                                        if (mum != null)
                                          _ohlcSatiri(mum, currentUnitTRY),
                                      ];
                                    }
                                    final i = nearestSpotIndex(spots, x);
                                    // İşlemin birim fiyatı da ekrandaki
                                    // birim fiyatla aynı hassasiyette.
                                    final fiyatFmt =
                                        _birimBicimi(currentUnitTRY);
                                    return [
                                      if (mum != null)
                                        _ohlcSatiri(mum, currentUnitTRY),
                                      for (final t in islemler)
                                        if (nearestSpotIndex(spots, t.x) == i)
                                          (
                                            (t.satis
                                                ? context.l10n.chartTxSell
                                                : context.l10n.chartTxBuy)(
                                              isIntraday
                                                  ? DateFormat('HH:mm', 'tr_TR')
                                                      .format(t.lot.addedDate)
                                                  : fmtTarihSaat(
                                                      t.lot.addedDate),
                                              fiyatFmt.format(t.birim),
                                            ),
                                            t.satis
                                                ? context.c.loss
                                                : context.c.gain,
                                          ),
                                    ];
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
                const SizedBox(height: SandikSpace.lg),
                if (katmanli)
                  ..._katmanliGovde(
                    baz: baz,
                    pnl: pnl,
                    isOwnAsset: isOwnAsset,
                    pState: pState,
                    // Eski kartın satırları, kabuksuz — "Ayrıntı"da açılır.
                    // Argümanlar aşağıdaki eski kartla aynı.
                    ayrinti: _PozisyonKarti(
                      kabuksuz: true,
                      baz: baz,
                      pnl: pnl,
                      miktarMetni: widget.asset.miktarMetni(
                          _canli.asset.quantity,
                          (v, d) => fmtNum(v, digits: d)),
                      birimEtiketi: widget.asset.unitLabel,
                      birimBicim: _birimBicimi(pnl.currentUnitTRY),
                      birimGizli: widget.asset.type == AssetType.mevduat,
                      donemEtiketi: donemEtiketi(
                          context.l10n, _periods[_selectedPeriodIdx].label),
                      donem: _donemDegisimi(period.days, startDate, endDate,
                          pnl.currentUnitTRY),
                    ),
                  )
                else ...[
                // ── Pozisyon ── (A tasarımı): grafiğin altında, tek kart.
                //
                // 2026-09-28 (kullanıcı): "kaçtan aldığım, toplam kâr/zarar
                // ve dönem içindeki kâr/zarar KESİNLİKLE olmalı; okunaklı,
                // basit ibarelerle." Aynı sayılar zaten vardı ama üç ayrı
                // kabukta ve sıkışık dilde: "ALIŞ / LOT → BUGÜN / LOT" oku,
                // bir rozette üst üste üç minik sayı, ayrı bir "1H DEĞİŞİM"
                // şeridi. Şimdi tek kart, her satır "etiket · değer"
                // (`_PozisyonKarti`); sayılar yine `_pnlOzeti` ve
                // `_donemDegisimi`'nden — hesap değişmedi, yalnızca dil.
                SandikSectionHeader(title: context.l10n.adPositionUpper),
                const SizedBox(height: SandikSpace.sm),
                _PozisyonKarti(
                  baz: baz,
                  pnl: pnl,
                  miktarMetni: widget.asset.miktarMetni(
                      _canli.asset.quantity, (v, d) => fmtNum(v, digits: d)),
                  birimEtiketi: widget.asset.unitLabel,
                  birimBicim: _birimBicimi(pnl.currentUnitTRY),
                  birimGizli: widget.asset.type == AssetType.mevduat,
                  donemEtiketi: donemEtiketi(
                      context.l10n, _periods[_selectedPeriodIdx].label),
                  // Seçili dönemin serisi gelmeden `null`: satır "—" yazar,
                  // eski dönemin rakamı yeni dönemin etiketiyle yazılmaz.
                  donem: _donemDegisimi(period.days, startDate, endDate,
                      pnl.currentUnitTRY),
                ),
                _eurobondKarti(),
                const SizedBox(height: SandikSpace.lg),
                ..._istatistikler(pnl.currentUnitTRY),
                _fonKarnesi(),
                _fonDagilimi(),
                _paraAkisi(),
                _hacimRadari(),
                _kriptoBaski(),
                _analizNotu(),
                if (isOwnAsset) _sozlesmeKarti(),
                if (isOwnAsset && pState != null) _temettuKarti(pState),
                if (isOwnAsset &&
                    pState != null &&
                    RemoteConfigService.instance.varlikMasraflari)
                  _masrafKarti(pState),
                _kapBaglantisi(),
                if (_sinyalYuzeyleri) ...[
                  const SizedBox(height: 24),
                  TechnicalSignalPanel.forAsset(widget.asset,
                      key: _sinyalPaneliKey, detayli: true),
                  // AL/SAT sinyali gösteren her yüzey yasal ibareyi de
                  // taşır (varlık sayfasıyla aynı). Sayfadaki TEK ibare
                  // budur — panel kendi içinde basmaz (#20: üç kez
                  // tekrarlanıyordu).
                  const SizedBox(height: SandikSpace.sm),
                  const DisclaimerWidget(),
                ] else if (_sinyalKilidi) ...[
                  const SizedBox(height: 24),
                  const SinyalKilitKarti(),
                ],
                ], // eski yığın (katmanlı değil)
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

