part of '../portfolio_performance_screen.dart';

/// Özet sekmesinin ağa çıkan yan verileri (TÜFE, yüzdelik, sağlık, XIRR) ve
/// pozisyon etiketi. `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
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
String _positionLabel(String key, AssetType type, AppLocalizations l) {
  final parts = key.split('|');
  var core = parts.length > 1 ? parts[1] : key;
  if (core.startsWith('sub:')) core = core.substring(4);
  if (core.startsWith('name:')) core = core.substring(5);
  if (core.isEmpty) return type.labelOf(l);
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
  /// TÜFE ölçümü ve ÖLÇÜLDÜĞÜ pencere.
  ///
  /// Yüzde tek başına tutulmuyor (2026-09-16): ekran nominal getiriyi bu
  /// pencereye hizalamak ZORUNDA, yoksa çıkarma iki farklı zaman dilimini
  /// kıyaslar. Gerekçe `InflationService.pencere` notunda.
  InflationWindow? _tufePencere;

  /// [_tufePencere] ile AYNI aralıkta hesaplanmış nominal getiri.
  ///
  /// `widget.summary.getiriPct` bunun yerine KULLANILAMAZ: o, takvimden
  /// türetilen pencerenin (bugünden geriye) getirisi ve TÜFE penceresiyle
  /// örtüşmüyor — 1A'da hiç kesişmiyordu.
  double? _hizaliNominal;

  /// `inflation_index` tablosu tamamen boş mu? (Kurulum eksik.)
  ///
  /// `_enflasyon == null` ile aynı şey DEĞİL: endeks dolu olup bu dönemin
  /// ucu eksik de olabilir. Ayrımın gerekçesi
  /// `InflationService.isStale` notunda.
  bool _endeksBos = false;

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
  PercentileBucket? _dilim;
  bool _dilimIstendi = false;

  /// Birikim kovalarının çözünürlüğü. Dönem seçicisinden BAĞIMSIZ —
  /// kullanıcı 1Y grafiğine bakarken aylık birikimini görebilmeli.
  ContributionInterval _katkiAralik = ContributionInterval.aylik;

  /// 1Y sağlık metrikleri (düşüş / oynaklık / yoğunlaşma).
  ///
  /// Ayrı bir istek gerektirmiyor: `_yukleUzunDonem` zaten 1Y breakdown'ı
  /// çekiyor ve metrikler o serinin üzerinde hesaplanıyor. İkinci bir ağ
  /// turu atmak aynı veriyi iki kez indirmek olurdu.
  Drawdown? _drawdown;
  double? _volatilite;

  /// Para ağırlıklı yıllık getiri. Saf hesap, ağa çıkmaz.
  double? _xirr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void didUpdateWidget(_OzetYanVeri old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _tufePencere = null;
      _hizaliNominal = null;
      // Endeks boşluğu döneme bağlı değil ama `_yukle` yeniden koşup onu
      // tazeleyecek; arada eski değeri tutmak yanlış kart göstermez
      // (boşsa yine boş çıkar) ama sıfırlamak durumu tek yerde tutuyor.
      _endeksBos = false;
      // 1Y bağlamı dönemden bağımsız (hep 12 ay geri) ama KAPISI döneme
      // bağlı: yeni dönem kayıptaysa ve önceki değilse istek hiç
      // atılmamıştır, bu yüzden bayrak da sıfırlanır.
      _uzunDonemIstendi = false;
      // Sağlık metrikleri 1Y'ye bağlı ve aynı bayrağın arkasında; dönem
      // değişince yeniden hesaplanmaları için temizlenirler. `_uzunDonem`
      // gibi KORUNMAZLAR: 1Y'den çıkıldığında kart zaten çizilmiyor ve
      // eski değeri tutmak, geri dönüldüğünde bayat bir rakam gösterirdi.
      _drawdown = null;
      _volatilite = null;
      _xirr = null;
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

    // Saf hesap önce: ağ turlarını beklemeden çizilebilir.
    _hesaplaXirr();

    await _yukleUzunDonem();
    await _yukleDilim();

    // GÜNLÜK ve 1H'de TÜFE sorulmaz: endeks AYLIK yayımlanıyor.
    //
    // **1H de kapının ARKASINDA (2026-09-16).** Eskiden yalnızca GÜNLÜK
    // eleniyordu ve 1H için `inflationForPeriod(7)` çağrılıyordu;
    // `aySayisi(7)` tabanı 1'e kırptığı için bir HAFTALIK getiri bir AYLIK
    // TÜFE ile kıyaslanan bir sayı üretiliyordu. Kart 1H'de çizilmediği
    // için ekranda görünmüyordu ama paylaşım metni enflasyon bağlanmış
    // özetten üretiliyor: kullanıcı "enflasyonun X puan önündeyim" yazan
    // bir kartı paylaşabiliyordu. Ölçülmemiş bir karşılaştırma, ekranda
    // olmasa da paylaşılmamalı.
    if (widget.period == SummaryPeriod.gunluk ||
        widget.period == SummaryPeriod.birHafta) {
      return;
    }

    // 1A'da pencere BİR AYDIR (son açıklanmış ay), 6A/1Y'de dönemin ayı.
    //
    // Yıllık TÜFE'yi bir aylık pencereye uygulamak portföyü haksız yere
    // kötü gösterirdi: %31,5 yıllık enflasyonu bir ayın getirisinden
    // düşmek o ayı otomatik kayıp yazar.
    //
    // `pencere()` yüzdeyle birlikte UÇLARI da veriyor; nominal getiri
    // birazdan o uçlara hizalanacak.
    final w = await InflationService.instance.pencere(
      widget.period == SummaryPeriod.birAy ? 30 : widget.period.days,
    );

    // Nominal AYNI pencerede yeniden hesaplanır — `widget.summary.getiriPct`
    // takvimden türetilen (bugünden geriye) pencerenin getirisi ve TÜFE
    // penceresiyle örtüşmüyor. Gerekçe `RealReturnService.piyasaGetirisi`
    // notunda; hesap da orada, burada kopyalanmıyor.
    double? nominal;
    if (w != null) {
      try {
        nominal = await RealReturnService.piyasaGetirisi(widget.assets, w);
      } catch (_) {
        // Seri kurulamazsa kart hiç çizilmez: hizasız bir farkı göstermek,
        // hiç göstermemekten kötü.
      }
    }
    final enf = nominal == null ? null : w?.pct;

    // `enf == null` üç sebepten olabilir; ekranın hangisi olduğunu bilmesi
    // gerekiyor:
    //
    //   1. Tablo BOŞ            → sebebi söyle ("veri bekleniyor")
    //   2. Seri DURMUŞ (bayat)  → sebebi söyle — kullanıcı açısından 1 ile
    //      aynı sonuç: reel getiri hesaplanamıyor. Ölçüldü: TÜİK Ocak
    //      2026'da baz yılını değiştirdi, eski seri orada bitti.
    //   3. Tablo taze ama bu DÖNEMİN ucu yok → sessiz kal; kullanıcıya
    //      özel ve zamanla kendiliğinden düzelir.
    //
    // `isStale` 1 ve 2'yi birlikte kapsıyor, bu yüzden tek çağrı yetiyor.
    // Maliyetsiz: aynı 12 saatlik önbelleği okuyor, ağ turu atmıyor.
    final bosMu =
        enf == null ? await InflationService.instance.isStale() : false;

    if (!mounted) return;
    setState(() {
      _tufePencere = enf == null ? null : w;
      _hizaliNominal = enf == null ? null : nominal;
      _endeksBos = bosMu;
    });
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

      unawaited(AnalyticsService.instance
          .logPercentileViewed(bucket: data.percentile, periodDays: gun));
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
  /// 1Y penceresini bir kez çeker ve İKİ tüketiciye dağıtır:
  ///   · kayıp döneminde gösterilen bağlam cümlesi (`_uzunDonem`)
  ///   · portföy sağlığı metrikleri (`_drawdown`, `_volatilite`)
  ///
  /// **Neden tek istek:** ikisi de aynı 1Y serisini istiyor. Ayrı ayrı
  /// çekilseydi aynı veri iki kez inerdi ve `HistoryService`'in çözünürlük
  /// önbelleği bunu gizlerdi — pahalı olan ilk açılış, orada iki tur atmak
  /// görünmez bir yavaşlama olurdu.
  ///
  /// Kapı GENİŞLEDİ: eskiden yalnızca kayıptaki kısa dönemlerde
  /// çağrılıyordu. Sağlık kartı 1Y'de gösterildiği için artık 1Y'nin
  /// kendisi de kapıdan geçmeli; bağlam cümlesinin kendi kapısı aşağıda
  /// ayrıca duruyor.
  Future<void> _yukleUzunDonem() async {
    if (_uzunDonemIstendi) return;
    if (widget.assets.isEmpty) return;

    // Bağlam cümlesi gerekiyor mu? (Eski kapı — 1Y'nin kendisinde bir
    // pencereyi kendisiyle karşılaştırmak bilgi taşımaz.)
    final baglamGerek =
        widget.summary.isNegative && widget.period != SummaryPeriod.birYil;
    // Sağlık kartı YALNIZCA 1Y bloğunda çiziliyor.
    final saglikGerek = widget.period == SummaryPeriod.birYil;
    if (!baglamGerek && !saglikGerek) return;

    _uzunDonemIstendi = true;

    try {
      final now = DateTime.now();
      final from = PeriodSummaryService.donemBaslangici(now, 12);
      final tier =
          ResolutionTierMeta.pickForSpan(SummaryPeriod.birYil.days.toDouble());
      final bd = await HistoryService.instance
          .getPortfolioHistoryBreakdownAtResolution(
        assets: widget.assets,
        from: from,
        to: now,
        tier: tier,
      );
      if (!mounted) return;

      final yil = PeriodSummaryService.compute(
        period: SummaryPeriod.birYil,
        assets: widget.assets,
        breakdown: bd,
        now: now,
      );

      // Oynaklık BAR SÜRESİNE bağlı yıllıklandırılır: 1Y penceresi günlük
      // değil haftalık bar taşıyabiliyor ve sabit bir √252 çarpanı rakamı
      // 2,6 kata kadar şişirirdi (bkz. `InsightMetricsService`).
      final barGun = tier.barSuresi.inMinutes / (60 * 24);

      if (!mounted) return;
      setState(() {
        if (baglamGerek && yil.getiriPct != null) _uzunDonem = yil.getiriPct;
        if (saglikGerek) {
          _drawdown = InsightMetricsService.maxDrawdown(bd.total);
          _volatilite = InsightMetricsService.annualizedVolatility(
            bd.total,
            barSuresiGun: barGun,
          );
        }
      });
    } catch (_) {
      // Sessizce vazgeç: bağlam cümlesi ve sağlık kartı ikincil. Ana rakam
      // ve köprü zaten çizilmiş durumda ve kayıp tonu bağlam olmadan da
      // doğru (`tonCumlesi` uzunDonemPct null iken nötr cümleye düşüyor).
    }
  }

  /// XIRR — saf hesap, ağa çıkmaz.
  ///
  /// 1Y bloğunda gösterilir: yıllıklandırılmış bir oran daha kısa
  /// pencerelerde yanıltıcı olur (`XirrService.minGun` aynı gerekçeyle
  /// 60 günlük bir taban koyuyor).
  void _hesaplaXirr() {
    if (widget.period != SummaryPeriod.birYil) return;
    if (widget.assets.isEmpty) return;

    final pState = ref.read(portfolioProvider).valueOrNull;
    if (pState == null) return;

    // Bugünkü değer: aktif alım lotlarının toplamı. `totalValueTRY` zaten
    // aynı toplamı `aggregatePositions` üzerinden veriyor ve tek kaynak
    // olarak kullanılıyor — burada ikinci bir toplama yazmak, bu projede
    // tekrar eden bir hata sınıfı olurdu.
    final deger =
        LeaderboardService.instance.totalValueTRY(widget.assets, pState.toTRY);
    if (deger <= 0) return;

    final r = XirrService.portfolioXirr(
      assets: widget.assets,
      bugunkuDegerTRY: deger,
      now: DateTime.now(),
    );
    if (r == null || !mounted) return;
    setState(() => _xirr = r);
  }

  @override
  Widget build(BuildContext context) {
    // TÜFE farkı burada bağlanır: servis saf ve ağa çıkmıyor, bu yüzden
    // hesabı yapılmış özeti enflasyonla yeniden kurmak yerine yalnızca
    // farkı hesaplayıp view'a veriyoruz.
    final s = widget.summary;
    final w = _tufePencere;
    final nominal = _hizaliNominal;
    // İkisi de TÜFE penceresinden: biri eksikse kart hiç çizilmez.
    final gosterilen = (w != null && nominal != null) ? _tufeIle(s, w, nominal) : s;

    // Paylaşım metni ENFLASYON BAĞLANDIKTAN SONRAKİ özetten üretilir:
    // `gosterilen` yerine `s` verilirse "enflasyonun X puan önündeyim"
    // satırı metne hiç girmez.
    //
    // Metin null ise (ölçülebilir yüzde yok) buton HİÇ çizilmez: içinde tek
    // bir sayı olmayan bir kart paylaşılmaz.
    //
    // Seviye kapıları paylaşımda da geçerli (`gorunur` aşağıda): ekranda
    // görünmeyen XIRR / düşüş / dilim karta ve metne de girmez — kullanıcı
    // görmediği bir sayıyı paylaşmış olmasın.
    final gorunur = seviyeGorunurlugu(ref.watch(yatirimciSeviyesiProvider));
    final xirrPaylasim = gorunur.xirr ? _xirr : null;
    final paylasimMetni = PeriodSummaryService.shareText(
      gosterilen,
      karakter: widget.karakter,
      xirrPct: xirrPaylasim,
    );

    // Birikim kartı: saf hesap, her build'de yeniden kurulur. Ağa çıkmıyor
    // ve `assets` zaten elde — state'te tutmak, kova aralığı değiştiğinde
    // bayatlama riski eklerdi.
    final katki = ContributionHistoryService.compute(
      widget.assets,
      aralik: _katkiAralik,
      now: DateTime.now(),
      // Altı kova: haftalıkta bir buçuk ay, aylıkta yarım yıl, yıllıkta
      // altı yıl. Çubuklar dar ekranda okunur kalırken trend cümlesinin
      // isteği olan en az üç tam kovayı da rahatça karşılıyor.
      kovaSayisi: 6,
    );

    // Yoğunlaşma bugünkü portföyden — dönem penceresi almaz.
    final pState = ref.watch(portfolioProvider).valueOrNull;
    final yogunlasma = pState == null
        ? null
        : InsightMetricsService.concentration(widget.assets, pState.toTRY);

    // Yatırımcı seviyesi yalnızca GÖRÜNÜRLÜĞÜ değiştirir (bkz.
    // `seviyeGorunurlugu`): Başlangıç'ta sağlık/XIRR/yüzdelik çizilmez,
    // İleri'de ek kart gelir. Hesaplar seviyeden bağımsız yapılır.
    // (`gorunur` yukarıda, paylaşım metninden önce hesaplanıyor.)

    final saglik = widget.period == SummaryPeriod.birYil && gorunur.saglik
        ? SaglikKarti(
            donemEtiketi: 'son 1 yıl',
            drawdown: _drawdown,
            volatilite: _volatilite,
            yogunlasma: yogunlasma,
          )
        : null;

    final ileri = widget.period == SummaryPeriod.birYil && gorunur.ileri
        ? IleriMetrikler.hesapla(
            getiriPct: gosterilen.getiriPct,
            volatilitePct: _volatilite,
            xirrPct: _xirr,
            drawdown: _drawdown,
          )
        : null;

    return PeriodSummaryView(
      baz: ref.watch(bazParaProvider),
      summary: gosterilen,
      uzunDonemPct: widget.period == SummaryPeriod.birYil ? null : _uzunDonem,
      karakter: widget.karakter,
      enSabirli: widget.enSabirli,
      enSabirliGun: widget.enSabirliGun,
      percentile: gorunur.percentile && RemoteConfigService.instance.globalLeaderboardEnabled ? _dilim?.percentile : null,
      percentileKatilimci: gorunur.percentile && RemoteConfigService.instance.globalLeaderboardEnabled ? _dilim?.total : null,
      onShare: paylasimMetni == null
          ? null
          : () => _paylas(
                paylasimMetni,
                gosterilen,
                xirrPct: xirrPaylasim,
                drawdownPct: gorunur.saglik ? _drawdown?.yuzde : null,
                percentile: gorunur.percentile && RemoteConfigService.instance.globalLeaderboardEnabled ? _dilim?.percentile : null,
              ),
      katkiKarti: katki == null
          ? null
          : ContributionKarti(
              baz: ref.watch(bazParaProvider),
              ozet: katki,
              aralik: _katkiAralik,
              onAralik: (a) => setState(() => _katkiAralik = a),
            ),
      // Tek metrik bile yoksa kart çizilmesin — `hasData` o kapıyı
      // widget'ın içinde tutuyor ama boş bir kabuk geçirmenin de anlamı
      // yok, burada da eleniyor.
      saglik: (saglik?.hasData ?? false) ? saglik : null,
      ileriKarti: ileri == null ? null : IleriMetrikKarti(metrikler: ileri),
      xirr: gorunur.xirr ? _xirr : null,
      enflasyonVerisiBekleniyor: _endeksBos,
      // Derinlik bölümü (XIRR, sağlık, ileri metrikler…) ileri seviyede açık
      // gelir, diğerlerinde katlı: özet önce "bu dönem"i anlatsın.
      derinlikAcik:
          ref.watch(yatirimciSeviyesiProvider) == YatirimciSeviyesi.ileri,
    );
  }

  /// Önizlemeli paylaşım (bkz. `showShareSheet`). Kart metinle AYNI
  /// kaynaktan kurulur (`gosterilen`: enflasyon bağlanmış özet) — ikisi
  /// ayrışmasın. Analytics sayfanın içinde, seçilen kanala göre yazılır.
  ///
  /// Kart, ekrandaki özetin TUTARSIZ ölçülerini taşır: yüzdeler, gün
  /// sayıları, varlık adları ve dağılım ORANI. `dagilimSonu` TRY değer
  /// taşır ama kart yalnızca payı çizer (`ShareCardData.dagilim` notu).
  /// XIRR / düşüş / dilim seviye kapısından geçmiş hâliyle gelir.
  Future<void> _paylas(
    String metin,
    PeriodSummary gosterilen, {
    double? xirrPct,
    double? drawdownPct,
    int? percentile,
  }) {
    // Aralık gün-ay-yıl: kart bir GÖRSEL, metindeki "dört haneli sayı tutar
    // sanılır" kaygısı burada yok — aksine "Bu yıl"ın takvim yılı değil son
    // 12 ay olduğunu ancak aralık söyler.
    final f = DateFormat('d MMM yyyy', 'tr_TR');
    return showShareSheet(
      context,
      data: ShareCardData(
        baslik: PeriodSummaryService.donemAdi(widget.period),
        tarihAraligi: context.l10n
            .shareCardRange(f.format(gosterilen.start), f.format(gosterilen.end)),
        degisimPct: gosterilen.getiriPct,
        degisimEtiketi: context.l10n.myMarketReturn,
        karakter: widget.karakter,
        enflasyonPuan: gosterilen.tufeFarki,
        reelGetiriPct: gosterilen.reelGetiriPct,
        enIyi: gosterilen.enIyi,
        enZayif: gosterilen.enZayif,
        gunSayimi: gosterilen.gunSayimi,
        percentile: percentile,
        xirrPct: xirrPct,
        drawdownPct: drawdownPct,
        enSabirli: widget.enSabirli?.name,
        enSabirliGun: widget.enSabirliGun,
        dagilim: gosterilen.dagilimSonu ?? const {},
      ),
      metin: metin,
      subject: 'sandık · ${PeriodSummaryService.donemAdi(widget.period)}',
      analyticsPeriod: widget.period.name,
    );
  }

  /// Özetin enflasyon alanları doldurulmuş kopyası.
  ///
  /// `PeriodSummary` değişmez (`@immutable` disiplini) ve `copyWith`
  /// taşımıyor — tek alan için eklemek yerine burada yeniden kuruluyor.
  ///
  /// **Üç alan birden doldurulur, biri değil.** Puan farkı ve bileşik reel
  /// getiri farklı sayılardır ve kart ikisini de yazıyor; ham TÜFE de
  /// taşınır ki kullanıcı sonucu TÜİK'in açıkladığı rakamla
  /// doğrulayabilsin. Yalnızca farkı geçirmek, kartı bir kara kutuya
  /// çevirirdi.
  ///
  /// Hesap `PeriodSummaryService.compute` içinde de duruyor; burası
  /// enflasyonun AĞDAN sonradan gelmesinin sonucu (servis saf ve ağa
  /// çıkmıyor). Formüller iki yerde de aynı `InflationService`
  /// fonksiyonlarına bakıyor, kopyalanmıyor.
  PeriodSummary _tufeIle(
    PeriodSummary s,
    InflationWindow w,
    double nominal,
  ) {
    final enflasyon = w.pct;
    final reel = InflationService.realReturnPct(nominal, enflasyon);

    return PeriodSummary(
      period: s.period,
      // **Uçlar ÖZETİN kalır, TÜFE penceresininki değil.** Bu kopya
      // yalnızca enflasyon alanlarını ekliyor; `start`/`end` dönem
      // kartının ve paylaşım başlığının tarih aralığı ("son 1 ay") ve o
      // aralık `getiriPct`/köprü ile tutarlı olmak zorunda. TÜFE
      // karşılaştırmasının kendi aralığı [tufeBaslangic]/[tufeBitis]'te
      // ayrı taşınır — iki farklı soru, iki farklı aralık, ikisi de
      // ekranda yazılı.
      start: s.start,
      end: s.end,
      baslangicTRY: s.baslangicTRY,
      sonTRY: s.sonTRY,
      katkiTRY: s.katkiTRY,
      piyasaTRY: s.piyasaTRY,
      getiriPct: s.getiriPct,
      enIyi: s.enIyi,
      enZayif: s.enZayif,
      tufeFarki: InflationService.spreadPoints(nominal, enflasyon),
      tufePct: enflasyon,
      // Karşılaştırmanın KENDİ nominali ve aralığı. `getiriPct` dönem
      // kartının sayısı olarak kalıyor; reel getiri kartı bunu okur.
      tufeNominalPct: nominal,
      tufeBaslangic: w.seriBaslangici,
      tufeBitis: w.seriBitisi,
      // NaN filtresi: −%100 enflasyonda payda sıfırlanıyor ve ekrana
      // "%NaN" basılırdı (servis tarafındaki `_sonluVeyaNull` ile aynı
      // kapı).
      reelGetiriPct: reel.isFinite ? reel : null,
      temettuTRY: s.temettuTRY,
      komisyonTRY: s.komisyonTRY,
      dagilimBasi: s.dagilimBasi,
      dagilimSonu: s.dagilimSonu,
      sparkline: s.sparkline,
      gunSayimi: s.gunSayimi,
    );
  }
}
