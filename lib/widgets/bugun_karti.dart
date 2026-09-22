// Ana ekrandaki "Bugün" kartı.
//
// Hesap `services/bugun_service.dart`'ta (saf); burada yalnızca gün içi
// serinin çekimi (kilit ekranı/widget ile ORTAK önbellek — üç yüzey aynı
// rakamı göstermeli), tercihler ve çizim var.
//
// Kendi kapılarını kendi kurar: kendi görünümü + açık pozisyon varken
// çizilir; seri gelmeden de kalan satırları gösterir (boş kart yok).
//
// Düzen (2026-09-21, "almanak"): sol sütunda tarih (büyük gün rakamı),
// sağda günün hareketi; altında `etiket ····· değer` defter satırları, her
// birinin altında kısa açıklama; en altta yaklaşan olay ayak notu. Renk
// yalnızca sayıda, ikon yok — dört eşit ikonlu satır bir menü gibi
// okunuyordu, hiyerarşi yoktu (kullanıcı ekran görüntüsü).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/position.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../screens/portfolio_performance_screen.dart';
import '../services/analytics_service.dart';
import '../services/bist_calendar.dart';
import '../services/bugun_service.dart';
import '../services/crash_reporter.dart';
import '../services/daily_summary.dart';
import '../services/history_service.dart';
import '../services/period_summary_service.dart';
import '../services/real_return_service.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../utils/tr_iyelik.dart';
import 'hedef_sheet.dart';
import 'sandik_skeleton.dart';

class BugunKarti extends ConsumerStatefulWidget {
  const BugunKarti({
    super.key,
    required this.state,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
    this.kisisel = true,
    this.etiket,
  });

  /// Kartın anlattığı defter — seçili kapsamın (2026-09-21).
  ///
  /// Eskiden yalnızca giriş yapan kullanıcının defteri veriliyordu ve kart
  /// Birlikte görünümünde de onu anlatıyordu: toplam kartı birleşik defteri
  /// gösterirken Bugün kartı yalnızca senin gününü söylüyordu (kullanıcı
  /// bulgusu). Şimdi kart hangi görünümdeyse o görünümün defterini alır —
  /// şeritlerin 2026-09-17'den beri yaptığı gibi, tek hesap yolu.
  final PortfolioState state;
  final EdgeInsets padding;

  /// Kendi görünümü mü? Kişisel satırlar (hedef, aylık özet) yalnızca
  /// burada; gün içi seri de yalnızca burada kilit ekranıyla paylaşılan
  /// önbellekten okunur (bkz. `_seriYukle`).
  final bool kisisel;

  /// Kartın başına yazılan kapsam etiketi ("Ayşe'nin bugünü", "Birlikte").
  /// Kendi görünümünde `null`: kartın kimin olduğu sorusu yalnızca başka
  /// bir defter gösterilirken doğar.
  final String? etiket;

  @override
  ConsumerState<BugunKarti> createState() => _BugunKartiState();
}

class _BugunKartiState extends ConsumerState<BugunKarti> {
  Map<int, double>? _seri;
  ReelGetiriSatiri? _reel;
  double? _haftalik;
  bool _istendi = false;

  /// Üç yükleme de sonuçlandı mı (başarı ya da hata fark etmez)?
  /// `false` iken kart iskelet çizer — bkz. [_yukle].
  bool _yuklendi = false;

  /// Tek bir yüklemenin üst sınırı. Biri asılı kalırsa kart bu süreden
  /// sonra elindekiyle çizilir; iskelet sonsuza kadar kalmaz.
  static const _yuklemeSuresi = Duration(seconds: 10);

  /// Gün içi seri bundan eskiyse tazelenir — Performans ekranının tick
  /// periyoduyla AYNI (30 sn). İkisi ayrışırsa aynı kapsamda iki farklı
  /// kâr/zarar görünür (bkz. `_seriYukle`).
  static const _seriTazelikPenceresi = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void didUpdateWidget(BugunKarti oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defter mount'ta boşken sonradan dolduysa (ilk varlık eklendi) yükleme
    // hiç istenmemiştir; şimdi iste. Aksi halde `_yuklendi` false kalır.
    if (!_istendi) _yukle();
  }

  /// Üç yükleme birbirinden bağımsız, PARALEL ve tek seferlik (`_istendi`):
  /// kart her fiyat yenilemesinde yeniden kurulur, ama bu seriler oturumda
  /// bir kez çekilir — eski `RealReturnStrip` / `WeeklySummaryChip` ile aynı
  /// disiplin. Her biri kendi try/catch'inde: biri düşerse diğerleri çizilir.
  ///
  /// **Tek yayın (2026-09-21).** Eskiden her yükleme kendi `setState`'ini
  /// çağırıyordu; satırlar birer birer beliriyor, kart üç kez büyüyordu
  /// ("tek tek load oluyor" — kullanıcı). Şimdi sonuçlar yerelde toplanır
  /// ve kart TEK `setState` ile, tüm veriyle bir kez çizilir; o ana kadar
  /// iskelet durur. Zaman sınırı (`_yuklemeSuresi`) asılı bir çağrının
  /// diğer ikisini rehin almasını önler.
  Future<void> _yukle() async {
    if (_istendi || !mounted || widget.state.assets.isEmpty) return;
    _istendi = true;
    final sonuc = await Future.wait([
      _seriYukle(),
      _reelYukle(),
      _haftalikYukle(),
    ]);
    if (!mounted) return;
    setState(() {
      _seri = sonuc[0] as Map<int, double>?;
      _reel = sonuc[1] as ReelGetiriSatiri?;
      _haftalik = sonuc[2] as double?;
      _yuklendi = true;
    });
  }

  /// Gün içi seri.
  ///
  /// Kendi görünümünde kilit ekranı ve widget'la ORTAK önbellekten gelir
  /// (üç yüzey aynı rakamı göstermeli). Ortak / Birlikte görünümünde o
  /// önbellek KULLANILMAZ: tek yuvalı ve oturumdaki kullanıcıya damgalı;
  /// başka bir defterle doldurmak kilit ekranını yanlış seriyle beslerdi.
  /// Kapsam serisi doğrudan çekilir — aynı servis, aynı hesap, ayrı yuva.
  Future<Map<int, double>?> _seriYukle() async {
    try {
      if (!widget.kisisel) {
        // Seriye YALNIZCA fiyatlanabilir lot'lar girer — Performans
        // ekranıyla AYNI kural (`FiyatKaynagi.seriyeGirer`).
        //
        // Eleme eskiden yalnızca Performans'ta vardı ve orada yerel bir
        // kopyaydı; bu kart ham `activeAssets` gönderiyordu. Aynı defterden
        // iki farklı seri çıkıyor, "Ben" kapsamında bile iki yüzey farklı
        // kâr/zarar gösteriyordu (kullanıcı bildirimi 2026-09-22; ölçüldü:
        // beş lotluk defterde 5'e karşı 2 lot).
        final bd = await HistoryService.instance
            .getPortfolioHistoryHourlyBreakdown(
                widget.state.activeAssets
                    .where(FiyatKaynagi.seriyeGirer)
                    .toList(),
                24)
            .timeout(_yuklemeSuresi);
        return bd.total;
      }
      // Performans ekranı gün içi seriyi 30 sn'de bir tazeliyor
      // (`_startIntradayTickIfNeeded`). Bu kart 5 dk'lık önbellekten
      // okusaydı iki yüzey farklı yaşta serilere bakar ve aynı kapsamda
      // farklı kâr/zarar gösterirdi (kullanıcı bildirimi 2026-09-22).
      //
      // Önbelleğin varsayılanı DEĞİŞMEZ: widget ve Live Activity 5 dk'lık
      // döngüyle hizalı kalır (bkz. `IntradaySeriesCache.minInterval`).
      return await IntradaySeriesCache.instance
          .get(widget.state, azamiYas: _seriTazelikPenceresi)
          .timeout(_yuklemeSuresi);
    } catch (e, st) {
      // Seri gelmezse kart yine çizilir (hareket satırı düşer); ağ hatası
      // kullanıcıya gösterilmez, sessiz kalmasın diye raporlanır.
      CrashReporter.report(e, st, reason: 'BugunKarti.intraday');
      return null;
    }
  }

  /// Yıllık reel getiri — eski `RealReturnStrip` ile AYNI kaynak
  /// (`RealReturnService.yillik`), aynı bayrak. Kapı: bayrak kapalıysa ya da
  /// pencere/seri kurulamıyorsa satır hiç çizilmez (uydurma yok).
  Future<ReelGetiriSatiri?> _reelYukle() async {
    if (!RemoteConfigService.instance.realReturnEnabled) return null;
    try {
      final r = await RealReturnService.yillik(widget.state.assets)
          .timeout(_yuklemeSuresi);
      if (r == null) return null;
      return ReelGetiriSatiri(nominal: r.nominal, inflation: r.inflation);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunKarti.reelGetiri');
      return null;
    }
  }

  /// Geçen haftanın piyasa getirisi — eski `WeeklySummaryChip` ile aynı
  /// hesap (`PeriodSummaryService.compute`, 1H penceresi), aynı bayrak.
  Future<double?> _haftalikYukle() async {
    if (!RemoteConfigService.instance.periodSummaryEnabled) return null;
    try {
      final now = DateTime.now();
      final p = PeriodSummaryService.pencere(SummaryPeriod.birHafta, now);
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
            assets: widget.state.assets,
            from: p.start,
            to: p.end,
            tier: ResolutionTierMeta.pickForSpan(
                SummaryPeriod.birHafta.days.toDouble()),
          )
          .timeout(_yuklemeSuresi);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: widget.state.assets,
        breakdown: bd,
        now: now,
      );
      return s.getiriPct;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'BugunKarti.haftalik');
      return null;
    }
  }

  /// Yükleme bitene kadar kartın yerini tutan iskelet — başlık, üç defter
  /// satırı. Kart tek seferde, tüm veriyle gelir; parça parça büyümez.
  Widget _iskelet(BuildContext context) => Padding(
        padding: widget.padding,
        child: SandikCard(
          padding: const EdgeInsets.fromLTRB(SandikSpace.md, SandikSpace.md2,
              SandikSpace.md, SandikSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SandikSkeleton(width: 56, height: 40),
                  const SizedBox(width: SandikSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SandikSkeleton(width: 120, height: 12),
                        SizedBox(height: SandikSpace.xs),
                        SandikSkeleton(width: 180, height: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SandikSpace.smd),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.xs),
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: SandikSpace.sm),
                  child: Row(
                    children: [
                      SandikSkeleton(width: 96, height: 12),
                      Spacer(),
                      SandikSkeleton(width: 64, height: 12),
                    ],
                  ),
                ),
              const SizedBox(height: SandikSpace.xs),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_yuklendi && widget.state.assets.isNotEmpty) return _iskelet(context);
    final now = DateTime.now();
    final seri = _seri;
    final ozet = seri == null
        ? null
        : DailySummary.from(state: widget.state, series: seri, now: now);
    // Sahiplik sınırı korunur: Birlikte görünümünde `state.assets` ben +
    // ortakların BİRLEŞİK defteridir ve `positionKey` sahip taşımaz — tek
    // havuzda toplanırsa iki kişinin aynı hissesi tek pozisyona düşer,
    // birinin satışı diğerinin lotunu düşer (bkz. `aggregatePositionsByOwner`).
    // Kendi görünümünde tek grup çıkar, hesap aynıdır.
    final sahipler = lotlarSahibeGore(widget.state.assets);
    final pozisyonlar = aggregatePositionsByOwner(
        [for (final lots in sahipler) aktifLotlar(lots)]);
    final veri = BugunService.hesapla(
      karZararlar: [for (final p in pozisyonlar) p.gainLoss],
      toplamDeger: ownerScopedTotalValue(sahipler, toTRY: widget.state.toTRY),
      ozet: ozet,
      hedefTRY: ref.watch(portfolioGoalProvider),
      now: now,
      reel: _reel,
      haftalikGetiriPct: _haftalik,
      kisisel: widget.kisisel,
    );
    if (veri.bos) return const SizedBox.shrink();
    _gosterimiOlc(veri, now);

    final gizli = ref.watch(balanceHiddenProvider);
    final dil = Localizations.localeOf(context).languageCode == 'en'
        ? 'en_US'
        : 'tr_TR';

    // Almanak düzeni (2026-09-21, kullanıcı seçimi "A"): tarih sütunu +
    // günün hareketi başlıkta; geri kalanı etiket ····· değer biçiminde
    // DEFTER satırları; yaklaşan olay kartın ayak notu. Her satırın altında
    // tek satırlık kısa açıklama — "bu ne demek?" sorusu kartta kalmasın.
    //
    // Sıra: reel (sabit) → haftalık (sabit, Pzt–Sal) → dönüşen içgörüler →
    // aylık özet. Olay defterde değil, ayakta (her gün görünür).
    final defter = <BugunSatiri>[
      if (veri.reel != null) veri.reel!,
      if (veri.haftalik != null) veri.haftalik!,
      ...veri.ikincil,
      if (veri.aylik != null) veri.aylik!,
    ];

    return Padding(
      padding: widget.padding,
      child: SandikCard(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.md, SandikSpace.md2, SandikSpace.md, SandikSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kapsam etiketi (seçenek 3, 2026-09-21): görünüm çipi toplam
            // kartında kimde olduğunu söyler ama bu kart ondan aşağıda,
            // kendi başına okunur — "kimin bugünü" sorusu kartta cevaplanır.
            if (widget.etiket != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SandikSpace.sm),
                child: Text(
                  // Türkçe büyük harf: düz `toUpperCase` "AYŞE'NIN" verir.
                  trBuyukHarf(widget.etiket!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(
                    color: context.c.text58,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _Baslik(
              now: now,
              dil: dil,
              birincil: veri.birincil,
              seri: ozet?.sparkline ?? const [],
              gizli: gizli,
            ),
            if (defter.isNotEmpty) ...[
              const SizedBox(height: SandikSpace.smd),
              Divider(height: 1, color: context.c.hairline),
              const SizedBox(height: SandikSpace.xs),
              for (final s in defter) _defterSatiri(s, gizli),
            ],
            if (veri.olay != null)
              _AyakNotu(olay: veri.olay!, dil: dil)
            else
              const SizedBox(height: SandikSpace.xs),
          ],
        ),
      ),
    );
  }

  /// Defter satırı: etiket ····· değer, altında kısa açıklama.
  Widget _defterSatiri(BugunSatiri s, bool gizli) {
    final l10n = context.l10n;
    final c = context.c;
    switch (s) {
      case ReelGetiriSatiri():
        // Eski şeritle aynı hedef: Performans › Özet › 1Y (reel getiri kartı).
        final puan = fmtNum(s.fark.abs(), digits: 1);
        return _DefterSatiri(
          etiket: l10n.todayRealLabel,
          ipucu: l10n.todayRealHint,
          deger: l10n.todayPoints('${s.onde ? '+' : '−'}$puan'),
          renk: s.onde ? c.gain : c.loss,
          onTap: _olcerek(s, () => _ozeteGit(periodIdx: 4)),
        );
      case HaftalikOzetSatiri():
        // Eski çiple aynı hedef: Özet › 1H.
        final pct = fmtPct(s.getiriPct.abs());
        return _DefterSatiri(
          etiket: l10n.todayWeekLabel,
          ipucu: l10n.todayWeekHint,
          deger: '${s.getiriPct >= 0 ? '+' : '−'}$pct',
          renk: s.getiriPct >= 0 ? c.gain : c.loss,
          onTap: _olcerek(s, () => _ozeteGit(periodIdx: 1)),
        );
      case HedefSatiri():
        if (s.belirlenmedi) {
          return _DefterSatiri(
            etiket: l10n.todayGoalLabel,
            ipucu: l10n.todayGoalSetShort,
            deger: l10n.todayGoalAction,
            renk: c.amberText,
            onTap: _olcerek(s, () => showHedefSheet(context, ref)),
          );
        }
        final hedef = gizli ? '••••' : fmtTRYCompact(s.hedefTRY.toDouble());
        if (s.ulasildi) {
          return _DefterSatiri(
            etiket: l10n.todayGoalLabel,
            ipucu: l10n.todayGoalDoneHint(hedef),
            deger: l10n.todayGoalDone,
            renk: c.gain,
            onTap: _olcerek(s, () => showHedefSheet(context, ref)),
          );
        }
        return _DefterSatiri(
          etiket: l10n.todayGoalLabel,
          ipucu: l10n.todayGoalLeftHint(hedef),
          deger: l10n.todayGoalValue(
              (s.oran * 100).floor(), gizli ? '••••' : fmtTRYCompact(s.kalan)),
          renk: c.amberText,
          cubuk: s.oran,
          onTap: _olcerek(s, () => showHedefSheet(context, ref)),
        );
      case YesilOranSatiri():
        return _DefterSatiri(
          etiket: l10n.todayGreenLabel,
          ipucu: l10n.todayGreenHint,
          deger: l10n.todayGreenValue(s.yesil, s.toplam),
          renk: s.yesil * 2 >= s.toplam ? c.gain : c.text90,
        );
      case AylikOzetSatiri():
        return _DefterSatiri(
          etiket: l10n.todayMonthlySummary(DateFormat.MMMM(_dil).format(s.ay)),
          ipucu: l10n.todayMonthlySummaryHint,
          deger: l10n.todayOpenAction,
          renk: c.amberText,
          onTap: _olcerek(
            s,
            () => pushGuarded<void>(
              context,
              adaptiveRoute<void>(
                builder: (_) => const PortfolioPerformanceScreen(
                  showBackButton: true,
                  initialOzet: true,
                  // 1A — geçen ayın özeti; Özet sekmesi TÜFE farkını da taşır.
                  initialPeriodIdx: 2,
                ),
              ),
            ),
          ),
        );
      // Başlıkta ve ayakta çizilirler; defterde yerleri yok.
      case GunlukDegisimSatiri():
      case PiyasaKapaliSatiri():
      case YaklasanOlaySatiri():
        return const SizedBox.shrink();
    }
  }

  String get _dil =>
      Localizations.localeOf(context).languageCode == 'en' ? 'en_US' : 'tr_TR';

  /// Performans › Özet, verilen dönemde (0 GÜNLÜK · 1 1H · 2 1A · 3 6A · 4 1Y).
  void _ozeteGit({required int periodIdx}) => pushGuarded<void>(
        context,
        adaptiveRoute<void>(
          builder: (_) => PortfolioPerformanceScreen(
            showBackButton: true,
            initialOzet: true,
            initialPeriodIdx: periodIdx,
          ),
        ),
      );

  /// Gösterim ölçümü — gün + satır bileşimi başına BİR olay.
  ///
  /// Kart her fiyat yenilemesinde yeniden kurulur; her build'i saymak
  /// "kaç kez görüldü"yü değil "kaç kez çizildi"yi ölçerdi. Anahtar
  /// uygulama ömrü boyunca statik: aynı gün ikinci açılışta tekrar
  /// sayılmaz, ertesi gün sayılır.
  static String? _sonOlculen;

  void _gosterimiOlc(BugunKartiVerisi veri, DateTime now) {
    final turler = [
      if (veri.birincil != null) _tur(veri.birincil!),
      if (veri.reel != null) _tur(veri.reel!),
      if (veri.haftalik != null) _tur(veri.haftalik!),
      for (final s in veri.ikincil) _tur(s),
      if (veri.aylik != null) _tur(veri.aylik!),
      if (veri.olay != null) _tur(veri.olay!),
    ];
    final anahtar = '${dayKey(now)}|${turler.join(',')}';
    if (_sonOlculen == anahtar) return;
    _sonOlculen = anahtar;
    for (final t in turler) {
      unawaited(AnalyticsService.instance.logTodayRowShown(kind: t));
    }
  }

  static String _tur(BugunSatiri s) => switch (s) {
        GunlukDegisimSatiri() => 'degisim',
        PiyasaKapaliSatiri() => 'kapali',
        YesilOranSatiri() => 'yesil',
        HedefSatiri() => s.belirlenmedi ? 'hedef_yok' : 'hedef',
        ReelGetiriSatiri() => 'reel',
        HaftalikOzetSatiri() => 'haftalik',
        YaklasanOlaySatiri() => switch (s.tur) {
            BugunOlayTuru.tuikAciklamasi => 'olay_tuik',
            BugunOlayTuru.bistTatili => 'olay_tatil',
            BugunOlayTuru.aySonu => 'olay_aysonu',
          },
        AylikOzetSatiri() => 'aylik',
      };

  /// Dokunuş ölçümü — satırın kendi eylemini sarar.
  VoidCallback _olcerek(BugunSatiri s, VoidCallback eylem) => () {
        unawaited(AnalyticsService.instance.logTodayRowTapped(kind: _tur(s)));
        eylem();
      };
}

// ── Başlık: tarih sütunu + günün hareketi ────────────────────────────────────

/// Yaprak takvim: sol sütunda büyük gün rakamı, ay ve gün adı; sağda günün
/// hareketi. Tarih kartın "her gün değişir" hissini biçimle verir, metinle
/// değil. Sütun sabit genişlikte; hero sütunu kalan yeri alır ve 320pt'te
/// sparkline'ı bırakır (`LayoutBuilder`).
class _Baslik extends StatelessWidget {
  const _Baslik({
    required this.now,
    required this.dil,
    required this.birincil,
    required this.seri,
    required this.gizli,
  });

  final DateTime now;
  final String dil;
  final BugunSatiri? birincil;
  final List<double> seri;
  final bool gizli;

  static const double _tarihGenisligi = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Sütunun yüksekliği Column içinde sınırsız; `stretch` sonsuz yükseklik
    // ister. Ayırıcı sabit boyda, satır ortalanır.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _tarihGenisligi,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${now.day}',
                style: context.t.displaySmall?.copyWith(
                  color: c.text90,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: SandikSpace.xs),
              // toUpperCase Türkçe "i"yi bozar (PAZARTESI); başlık hâli kalır.
              Text(
                DateFormat.MMMM(dil).format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(
                  color: c.text58,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                DateFormat.EEEE(dil).format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelLarge?.copyWith(color: c.text36),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
          child: SizedBox(
            width: 1,
            height: SandikSpace.xxl,
            child: ColoredBox(color: c.hairline),
          ),
        ),
        Expanded(
          child: _Hero(
              now: now, dil: dil, birincil: birincil, seri: seri, gizli: gizli),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.now,
    required this.dil,
    required this.birincil,
    required this.seri,
    required this.gizli,
  });

  final DateTime now;
  final String dil;
  final BugunSatiri? birincil;
  final List<double> seri;
  final bool gizli;

  /// Sparkline için hero sütununun en az genişliği (pt). Altında sayı ve
  /// yüzde tek başına kalır; 320pt ekranda buraya ~165pt düşüyor.
  static const double _sparklineEsigi = 200;

  String _saat(DateTime gun, int dk) =>
      DateFormat.Hm().format(dayKey(gun).add(Duration(minutes: dk)));

  /// "Pazartesi 10:00 açılır" / "bugün 10:00 açılır".
  String _acilis(AppLocalizations l10n) {
    final acilis = BugunService.sonrakiAcilis(now);
    final ayniGun = dayKey(acilis) == dayKey(now);
    final ne = ayniGun
        ? l10n.todayAt(DateFormat.Hm().format(acilis))
        : '${DateFormat.EEEE(dil).format(acilis)} ${DateFormat.Hm().format(acilis)}';
    return l10n.todayOpensAt(ne);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final s = birincil;

    String buyuk;
    Color renk;
    String? yuzde;
    String alt;
    var seriCiz = false;
    if (s is GunlukDegisimSatiri) {
      final acik = BugunService.seansAcikMi(now);
      if (s.flat) {
        buyuk = gizli ? '••••' : fmtTRY(0);
        renk = c.text58;
        alt = l10n.todayFlat;
      } else {
        buyuk = gizli
            ? '••••'
            : '${s.changeTRY > 0 ? '+' : '−'}${fmtTRY(s.changeTRY.abs())}';
        renk = context.signColor(s.changeTRY);
        yuzde = fmtPct(s.changePct.abs());
        alt = acik
            ? l10n.todaySessionOpen(_saat(
                now,
                BistTakvimi.yarimGunMu(now)
                    ? BistTakvimi.yarimGunKapanisDk
                    : BugunService.seansKapanisDk))
            : '${l10n.todayClosedWord} · ${_acilis(l10n)}';
      }
      seriCiz = !gizli && seri.length >= 2;
    } else if (s is PiyasaKapaliSatiri) {
      buyuk = l10n.todayClosedWord;
      renk = c.text58;
      alt = _acilis(l10n);
    } else {
      // Seans açık, gün içi seri henüz gelmedi: uydurma sayı yok.
      buyuk = '—';
      renk = c.text36;
      alt = l10n.todayLoading;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.todayTitle,
              style: context.t.labelLarge?.copyWith(
                color: c.amberText,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: SandikSpace.sm),
            Expanded(
              child: Text(
                l10n.todayMarketOnly,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.t.labelMedium?.copyWith(color: c.text36),
              ),
            ),
          ],
        ),
        const SizedBox(height: SandikSpace.xs),
        LayoutBuilder(
          builder: (context, k) {
            final sparkOlsun = seriCiz && k.maxWidth >= _sparklineEsigi;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Uzun tutar (−₺2.418.191) dar sütunda küçülür, kırpılmaz.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      buyuk,
                      maxLines: 1,
                      style: context.t.headlineLarge?.copyWith(
                        color: renk,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                if (yuzde != null) ...[
                  const SizedBox(width: SandikSpace.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: SandikSpace.xxs),
                    child: Text(
                      yuzde,
                      style: context.t.bodyMedium?.copyWith(
                        color: c.text58,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (sparkOlsun) ...[
                  const Spacer(),
                  _GunIciCizgi(seri: seri, renk: renk),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: SandikSpace.xxs),
        Text(
          alt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.bodySmall?.copyWith(color: c.text58),
        ),
      ],
    );
  }
}

/// Gün içi eğri — 64×24, tek `drawPath`. Kilit ekranı/widget ile aynı ham
/// seri; burada yalnızca yönü anlatır, eksen yok.
class _GunIciCizgi extends StatelessWidget {
  const _GunIciCizgi({required this.seri, required this.renk});

  final List<double> seri;
  final Color renk;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: const Size(64, 24),
          painter: _GunIciPainter(seri: seri, renk: renk),
        ),
      );
}

class _GunIciPainter extends CustomPainter {
  const _GunIciPainter({required this.seri, required this.renk});

  final List<double> seri;
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    if (seri.length < 2) return;
    var min = seri.first, max = seri.first;
    for (final v in seri) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    // Göreli düz eşik — `DailySummary.isFlat` ile aynı gerekçe: 5 kuruşluk
    // fark tuvale yayılmasın.
    final aralik = max - min;
    final duz = aralik <= max.abs() * 1e-6;
    final yol = Path();
    for (var i = 0; i < seri.length; i++) {
      final x = size.width * i / (seri.length - 1);
      final y = duz
          ? size.height / 2
          : size.height - ((seri[i] - min) / aralik) * (size.height - 2) - 1;
      if (i == 0) {
        yol.moveTo(x, y);
      } else {
        yol.lineTo(x, y);
      }
    }
    final cizgi = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(yol, cizgi);
    final son = yol.computeMetrics().last;
    final uc = son.getTangentForOffset(son.length)?.position;
    if (uc != null) canvas.drawCircle(uc, 2, Paint()..color = renk);
  }

  @override
  bool shouldRepaint(_GunIciPainter old) =>
      old.renk != renk || !identical(old.seri, seri);
}

// ── Defter satırı ────────────────────────────────────────────────────────────

/// `etiket ····· değer ›` ve altında tek satırlık açıklama.
///
/// **Neden ölçüm var:** `Row` içinde `Flexible(etiket)` + `Expanded(kılavuz)`
/// serbest alanı flex oranında böler; etiket payının artığı kılavuza
/// geçmez ve noktalar değere ulaşmaz. Etiket ve değer `TextPainter` ile
/// ölçülür, etikete "değer + ok + en az 24pt kılavuz" dışında kalan yer
/// verilir; dar ekranda önce etiket kısalır (…), değer hiç kırpılmaz.
class _DefterSatiri extends StatelessWidget {
  const _DefterSatiri({
    required this.etiket,
    required this.deger,
    required this.renk,
    this.ipucu,
    this.cubuk,
    this.onTap,
  });

  final String etiket;
  final String? ipucu;
  final String deger;
  final Color renk;

  /// 0..1 ilerleme (hedef) — değerin altında ince çubuk.
  final double? cubuk;
  final VoidCallback? onTap;

  static const double _kilavuzMin = 24;
  static const double _okBoyu = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final etiketStil = context.t.bodyLarge?.copyWith(
      color: c.text90,
      fontWeight: FontWeight.w600,
    );
    final degerStil = context.t.bodyLarge?.copyWith(
      color: renk,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final ust = LayoutBuilder(
      builder: (context, k) {
        final olcek = MediaQuery.textScalerOf(context);
        double genislik(String metin, TextStyle? stil) {
          final tp = TextPainter(
            text: TextSpan(text: metin, style: stil),
            textDirection: Directionality.of(context),
            maxLines: 1,
            textScaler: olcek,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        final okW = onTap == null ? 0.0 : _okBoyu + SandikSpace.xxs;
        final degerW = genislik(deger, degerStil);
        final etiketMax =
            (k.maxWidth - degerW - okW - _kilavuzMin - 2 * SandikSpace.sm)
                .clamp(0.0, k.maxWidth);
        // +1: alt piksel yuvarlaması etiketi gereksiz yere "…"lemesin.
        final etiketW =
            (genislik(etiket, etiketStil) + 1).clamp(0.0, etiketMax);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: etiketW,
              child: Text(
                etiket,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: etiketStil,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    SandikSpace.sm, 0, SandikSpace.sm, SandikSpace.xs),
                child: _NoktaKilavuz(renk: c.text20),
              ),
            ),
            Text(deger, maxLines: 1, softWrap: false, style: degerStil),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: SandikSpace.xxs),
                child: Icon(Icons.chevron_right_rounded,
                    size: _okBoyu, color: c.text36),
              ),
          ],
        );
      },
    );

    final govde = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ust,
            if (ipucu != null)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xxs),
                child: Text(
                  ipucu!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodySmall?.copyWith(color: c.text58),
                ),
              ),
            if (cubuk != null)
              Padding(
                padding: const EdgeInsets.only(top: SandikSpace.xs2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                  child: SizedBox(
                    height: SandikSpace.xs,
                    child: Stack(
                      children: [
                        Container(color: c.surface2),
                        FractionallySizedBox(
                          widthFactor: cubuk!.clamp(0.02, 1.0),
                          child: Container(color: renk),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return govde;
    // Şeffaf Material: mürekkep katmanı ata iskeleye bağlı kalmasın
    // (Performans'taki "No Material widget found" dersi, 2026-09-21).
    return Semantics(
      button: true,
      label: '$etiket, $deger. ${ipucu ?? ''}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: govde,
        ),
      ),
    );
  }
}

/// Noktalı kılavuz — etiket ile değer arasını dolduran nokta dizisi.
class _NoktaKilavuz extends StatelessWidget {
  const _NoktaKilavuz({required this.renk});
  final Color renk;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: SandikSpace.xxs,
        child: CustomPaint(painter: _NoktaPainter(renk)),
      );
}

class _NoktaPainter extends CustomPainter {
  const _NoktaPainter(this.renk);
  final Color renk;

  @override
  void paint(Canvas canvas, Size size) {
    final boya = Paint()..color = renk;
    const adim = 4.0;
    for (var x = 1.0; x < size.width; x += adim) {
      canvas.drawCircle(Offset(x, size.height / 2), 0.8, boya);
    }
  }

  @override
  bool shouldRepaint(_NoktaPainter old) => old.renk != renk;
}

// ── Ayak notu: yaklaşan olay ─────────────────────────────────────────────────

/// "TÜİK enflasyonu · 3 Ekim ······ 13 gün" — kartın altındaki damga.
class _AyakNotu extends StatelessWidget {
  const _AyakNotu({required this.olay, required this.dil});

  final YaklasanOlaySatiri olay;
  final String dil;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    final tarih = DateFormat('d MMMM', dil).format(olay.tarih);
    final ne = switch (olay.tur) {
      BugunOlayTuru.tuikAciklamasi => l10n.todayEventCpiShort(tarih),
      BugunOlayTuru.bistTatili => l10n.todayEventHolidayShort(tarih),
      BugunOlayTuru.aySonu => l10n.todayEventMonthEndShort,
    };
    final kalan = switch (olay.gunKaldi) {
      0 => l10n.todayWordToday,
      1 => l10n.todayWordTomorrow,
      _ => l10n.todayDaysShort(olay.gunKaldi),
    };
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: c.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 14, color: c.text36),
                const SizedBox(width: SandikSpace.xs2),
                Expanded(
                  child: Text(
                    ne,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  kalan,
                  style: context.t.bodySmall?.copyWith(
                    color: c.amberText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
