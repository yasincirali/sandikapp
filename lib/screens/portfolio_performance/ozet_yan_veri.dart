part of '../portfolio_performance_screen.dart';

/// Özet sekmesinin ağa çıkan yan verileri (TÜFE, yüzdelik, sağlık, XIRR) ve
/// pozisyon etiketi. `portfolio_performance_screen.dart`'ın part'ı (2026-09-14).
/// `positionKey` → insan-okunur etiket. Gövde `lib/utils/pozisyon_etiketi.dart`
/// (2026-10-04): Bugün kartının "en çok oynayan"ı da aynı adı yazsın diye
/// ortak dosyaya taşındı; buradaki ad part'ın çağıranları değişmesin diye kaldı.
String _positionLabel(String key, AssetType type, AppLocalizations l,
        {String? ad}) =>
    pozisyonEtiketi(key, type, l, ad: ad);

/// Özet'in ağa çıkan yan verilerinin TEK ölçümü — [_yanVeriYukle] üretir,
/// `_OzetBellek` saklar, `_OzetYanVeriState` çizer.
///
/// **Neden ayrı bir değer (2026-10-02, titreme bulgusu):** bu alanlar
/// eskiden doğrudan State'te yaşıyordu; Özet her yeniden kurulduğunda
/// (dönem/kapsam dokunuşu, Grafik → Özet) sıfırdan doğup kartlar özetten
/// SONRA tek tek beliriyordu. Tek değer olunca bellekten eşzamanlı okunur
/// ve ekran açılmadan arkada ısıtılabilir (`_OzetBellek.isit`).
@immutable
class _YanVeri {
  const _YanVeri({
    this.tufePencere,
    this.hizaliNominal,
    this.hizaliReel,
    this.tufeKoprusu,
    this.endeksBos = false,
    this.uzunDonem,
    this.drawdown,
    this.volatilite,
  });

  /// TÜFE ölçümü ve ÖLÇÜLDÜĞÜ pencere.
  ///
  /// Yüzde tek başına tutulmuyor (2026-09-16): ekran nominal getiriyi bu
  /// pencereye hizalamak ZORUNDA, yoksa çıkarma iki farklı zaman dilimini
  /// kıyaslar. Gerekçe `InflationService.pencere` notunda.
  final InflationWindow? tufePencere;

  /// [tufePencere] ile AYNI aralıkta hesaplanmış nominal getiri.
  ///
  /// `widget.summary.getiriPct` bunun yerine KULLANILAMAZ: o, takvimden
  /// türetilen pencerenin (bugünden geriye) getirisi ve TÜFE penceresiyle
  /// örtüşmüyor — 1A'da hiç kesişmiyordu.
  final double? hizaliNominal;

  /// [hizaliNominal] ile AYNI pencerede reel para ağırlıklı getiri
  /// (`RealReturnService.hizaliGetiri`). Ara ayın endeksi eksikse `null`.
  final double? hizaliReel;

  /// TÜFE penceresinin sonundan BUGÜNE getiri (köprü satırı, D2
  /// 2026-10-01). Reel getiri kartının ölçmediği ama üst kartın içerdiği
  /// süre; `null` ise satır çizilmez. Gerekçe `TufeKoprusu` notunda.
  final TufeKoprusu? tufeKoprusu;

  /// `inflation_index` tablosu tamamen boş mu? (Kurulum eksik.)
  ///
  /// `tufePencere == null` ile aynı şey DEĞİL: endeks dolu olup bu dönemin
  /// ucu eksik de olabilir. Ayrımın gerekçesi `InflationService.isStale`
  /// notunda.
  final bool endeksBos;

  /// Son 12 ayın getirisi — kayıp döneminde gösterilen "daha uzun pencere"
  /// bağlamı. "Bu ay ekside. Daha uzun pencerede hâlâ +%31,8." cümlesinin
  /// ikinci yarısı. `RETENTION_STRATEJISI.md` §8 kayıp anında ya SUSMAYI ya
  /// BAĞLAM VERMEYİ şart koşuyor; ekran sustuğunda kullanıcı yalnız bir
  /// kırmızı rakam görür, o yüzden bağlam tercih edildi.
  ///
  /// Her dönemde ÖLÇÜLÜR ama yalnızca kayıptaki kısa dönemde GÖSTERİLİR
  /// (kapı `_OzetYanVeriState.build`'de). Eskiden yalnız kayıpta
  /// isteniyordu; ısıtma özetin işaretini bilmeden ölçtüğü için kapı
  /// gösterime taşındı. Ek ağ turu yok: 1Y serisi haftalık çözünürlükte,
  /// sembol önbelleğinden gelir.
  final double? uzunDonem;

  /// 1Y sağlık metrikleri (düşüş / oynaklık) — yalnızca 1Y'de ölçülür.
  ///
  /// Ayrı bir istek gerektirmiyor: [uzunDonem] zaten 1Y breakdown'ı
  /// çekiyor ve metrikler o serinin üzerinde hesaplanıyor. İkinci bir ağ
  /// turu atmak aynı veriyi iki kez indirmek olurdu.
  final Drawdown? drawdown;
  final double? volatilite;
}

/// [_YanVeri]'yi ölçer — saf girdilerle, State'e bağlı değil; böylece hem
/// ekran hem arkadaki ısıtma aynı fonksiyonu çağırır (iki kopya hesap yok).
///
/// Sessizce başarısız olur: TÜFE tablosu boş doğuyor (`InflationService`
/// "veri yoksa özellik yoktur" diyor). Alan null iken özet yine gösterilir —
/// yalnızca o bloklar çizilmez.
Future<_YanVeri> _yanVeriYukle({
  required SummaryPeriod period,
  required List<Asset> assets,
  required PortfolioState? pState,
}) async {
  if (assets.isEmpty) return const _YanVeri();

  // Sağ uç CANLI kapsam toplamı — Özet'in rakamıyla aynı uç (bkz.
  // `compute` [canliSon]).
  final canliSon =
      pState == null ? null : DailySummary.kapsamToplami(pState, assets);

  // ── 1Y penceresi: bağlam cümlesi + sağlık metrikleri ──────────────────
  //
  // 1Y penceresini bir kez çeker ve İKİ tüketiciye dağıtır:
  //   · kayıp döneminde gösterilen bağlam cümlesi (`uzunDonem`)
  //   · portföy sağlığı metrikleri (`drawdown`, `volatilite`)
  //
  // **Neden tek istek:** ikisi de aynı 1Y serisini istiyor. Ayrı ayrı
  // çekilseydi aynı veri iki kez inerdi ve `HistoryService`'in çözünürlük
  // önbelleği bunu gizlerdi — pahalı olan ilk açılış, orada iki tur atmak
  // görünmez bir yavaşlama olurdu.
  double? uzunDonem;
  Drawdown? drawdown;
  double? volatilite;
  try {
    final now = DateTime.now();
    final from = PeriodSummaryService.donemBaslangici(now, 12);
    final tier =
        ResolutionTierMeta.pickForSpan(SummaryPeriod.birYil.days.toDouble());
    final bd = await HistoryService.instance
        .getPortfolioHistoryBreakdownAtResolution(
      assets: assets,
      from: from,
      to: now,
      tier: tier,
    );
    final yil = PeriodSummaryService.compute(
      period: SummaryPeriod.birYil,
      assets: assets,
      breakdown: bd,
      now: now,
      // Özet'in 1Y rakamıyla aynı sağ uç (bkz. `compute` [canliSon]).
      canliSon: canliSon,
    );
    uzunDonem = yil.getiriPct;
    // Sağlık kartı YALNIZCA 1Y bloğunda çiziliyor.
    if (period == SummaryPeriod.birYil) {
      // Oynaklık BAR SÜRESİNE bağlı yıllıklandırılır: 1Y penceresi günlük
      // değil haftalık bar taşıyabiliyor ve sabit bir √252 çarpanı rakamı
      // 2,6 kata kadar şişirirdi (bkz. `InsightMetricsService`).
      final barGun = tier.barSuresi.inMinutes / (60 * 24);
      drawdown = InsightMetricsService.maxDrawdown(bd.total);
      // Akıştan arındırılmış (2026-10-01): alım günü "sıçrama"
      // sayılmasın. Düşüş ham kalır (`maxDrawdown` notu).
      volatilite = InsightMetricsService.annualizedVolatility(
        bd.total,
        barSuresiGun: barGun,
        lotlar: assets,
      );
    }
  } catch (_) {
    // Sessizce vazgeç: bağlam cümlesi ve sağlık kartı ikincil. Ana rakam
    // ve köprü zaten çizilmiş durumda ve kayıp tonu bağlam olmadan da
    // doğru (`tonCumlesi` uzunDonemPct null iken nötr cümleye düşüyor).
  }

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
  if (period == SummaryPeriod.gunluk || period == SummaryPeriod.birHafta) {
    return _YanVeri(
        uzunDonem: uzunDonem, drawdown: drawdown, volatilite: volatilite);
  }

  // 1A'da pencere BİR AYDIR (son açıklanmış ay), 6A/1Y'de dönemin ayı.
  //
  // Yıllık TÜFE'yi bir aylık pencereye uygulamak portföyü haksız yere
  // kötü gösterirdi: %31,5 yıllık enflasyonu bir ayın getirisinden
  // düşmek o ayı otomatik kayıp yazar.
  //
  // `pencere()` yüzdeyle birlikte UÇLARI da veriyor; nominal getiri
  // birazdan o uçlara hizalanacak.
  var w = await InflationService.instance.pencere(
    period == SummaryPeriod.birAy ? 30 : period.days,
  );
  // 5Y: endeks beş yıl geriye gitmiyorsa kart HİÇ çizilmiyordu (müşteri
  // testi 2026-10-01). Pencere veri olan en erken aya / ilk alıma çekilir
  // ve kart bunu söyler (`InflationWindow.kisaltildi`).
  if (w == null && period.days > SummaryPeriod.birYil.days) {
    w = await InflationService.instance.pencereKapsayan(
      period.days,
      enErken: PeriodSummaryService.ilkAlimTarihi(assets),
    );
  }

  // Nominal AYNI pencerede yeniden hesaplanır — `widget.summary.getiriPct`
  // takvimden türetilen (bugünden geriye) pencerenin getirisi ve TÜFE
  // penceresiyle örtüşmüyor. Gerekçe `RealReturnService.piyasaGetirisi`
  // notunda; hesap da orada, burada kopyalanmıyor.
  double? nominal;
  double? reelHizali;
  if (w != null) {
    try {
      final g = await RealReturnService.hizaliGetiri(assets, w);
      nominal = g?.nominal;
      reelHizali = g?.reel;
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
  final bosMu = enf == null ? await InflationService.instance.isStale() : false;

  // Köprü satırı: TÜFE penceresinin sonu → BUGÜN. Yalnızca reel kart
  // çizilecekse ölçülür (kartsız bir köprü neyi köprülediğini söyleyemez).
  // Sağ uç canlı kapsam toplamı — üst kartla aynı uç (bkz. `compute`
  // [canliSon]); ölçüm `TufeKoprusu.olc`'ta, burada formül yok.
  TufeKoprusu? kopru;
  if (enf != null && w != null) {
    final pct = await TufeKoprusu.olc(
      assets,
      pencereSonu: w.seriBitisi,
      now: DateTime.now(),
      canliSon: canliSon,
    );
    if (pct != null) {
      kopru = TufeKoprusu(pencereSonu: w.seriBitisi, getiriPct: pct);
    }
  }

  return _YanVeri(
    tufePencere: enf == null ? null : w,
    hizaliNominal: enf == null ? null : nominal,
    hizaliReel: enf == null ? null : reelHizali,
    tufeKoprusu: kopru,
    endeksBos: bosMu,
    uzunDonem: uzunDonem,
    drawdown: drawdown,
    volatilite: volatilite,
  );
}

/// Özet sekmesinin AĞA ÇIKAN yan verilerini çizer: TÜFE, yüzdelik dilim,
/// 1Y bağlamı, sağlık.
///
/// **Neden ayrı bir StatefulWidget:** hepsi ağ çağrısı ve ana ekran her
/// `setState`'te (30 sn'lik gün içi tick dahil) yeniden çiziliyor. Çağrılar
/// `_buildOzetSekmesi` içinde yapılsaydı her tick'te tekrar atılırdı. Burada
/// `initState` bir kez ister; [bellekAnahtari] değişince (dönem, kapsam,
/// defter) `didUpdateWidget` yeniden ister.
///
/// **İlk ölçüm bitene kadar iskelet (2026-10-02, titreme bulgusu):** eskiden
/// özet hemen çiziliyor, TÜFE/köprü/sağlık kartları SONRA belirip alttaki
/// kartları itiyordu — kullanıcı bunu "ekran titriyor" diye gördü. Artık
/// ölçüm bellekte varsa eşzamanlı okunur (bekleme yok); yoksa iskelet
/// durur ve özet tek seferde, tam hâliyle gelir. Ağ yavaşsa iskelet
/// [_azamiBekleme]'den uzun tutulmaz: özet çizilir, kartlar geldiğinde
/// eklenir (iskeletin sonsuza kadar dönmesi titremeden kötüdür).
class _OzetYanVeri extends ConsumerStatefulWidget {
  final SummaryPeriod period;
  final PeriodSummary summary;
  final PortfolioCharacter? karakter;
  final RecapAsset? enSabirli;
  final int? enSabirliGun;

  /// Uzun pencere bağlamı için gereken varlıklar ve akış kuralı.
  final List<Asset> assets;

  /// "Başka yere koysaydın" kartı — `_buildOzetSekmesi` Özet'in girdileriyle
  /// kurar, burası yalnızca view'a taşır. `null` ise çizilmez.
  final Widget? kiyasKarti;

  /// Ekranın Özet belleği ve bu ölçümün oradaki anahtarı (dönem + kapsam +
  /// tür + simülasyon + lot imzası). Bkz. `_OzetBellek`.
  final _OzetBellek bellek;
  final String bellekAnahtari;

  /// İlk ölçüm beklenirken çizilen iskelet — `_OzetSerisi` ile AYNI
  /// (`_ozetIskeleti`), iki bekleme tek ve kesintisiz bir iskelet görünür.
  final Widget iskelet;

  /// Tek akış (`performans_tek_akis`): ana rakam kartı dönem kartında,
  /// tür dökümü NEDEN'in sonunda. Bkz. `PeriodSummaryView.anaRakamGizli`.
  final bool anaRakamGizli;
  final Widget? nedenEki;

  const _OzetYanVeri({
    required this.period,
    required this.summary,
    required this.assets,
    required this.bellek,
    required this.bellekAnahtari,
    required this.iskelet,
    this.kiyasKarti,
    this.karakter,
    this.enSabirli,
    this.enSabirliGun,
    this.anaRakamGizli = false,
    this.nedenEki,
  });

  @override
  ConsumerState<_OzetYanVeri> createState() => _OzetYanVeriState();
}

class _OzetYanVeriState extends ConsumerState<_OzetYanVeri> {
  /// İskeletin azami süresi. Bellek ve ısıtma çoğu dokunuşu beklemesiz
  /// yapar; burası yalnız soğuk ağda devreye girer.
  static const _azamiBekleme = Duration(seconds: 1);

  _YanVeri _veri = const _YanVeri();

  /// İlk ölçüm (ya da bellek) geldi mi / bekleme süresi doldu mu.
  bool _hazir = false;
  Timer? _beklemeSayaci;

  /// Uçuşan ölçümün anahtarı — eski anahtarın geç gelen sonucu yenisinin
  /// üstüne yazılmasın.
  String? _istenen;

  /// 6A benchmark şeridinin yüzdelik dilimi. `null` iken şerit çizilmez —
  /// bayrak kapalı, opt-in yok, geçmiş yetersiz ya da k-anonimlik eşiği
  /// dolmamış olabilir; dördü de "gösterme" demek.
  PercentileBucket? _dilim;
  bool _dilimIstendi = false;

  /// Birikim kovalarının çözünürlüğü. Dönem seçicisinden BAĞIMSIZ —
  /// kullanıcı 1Y grafiğine bakarken aylık birikimini görebilmeli.
  ContributionInterval _katkiAralik = ContributionInterval.aylik;

  /// Para ağırlıklı yıllık getiri. Saf hesap, ağa çıkmaz.
  double? _xirr;

  @override
  void initState() {
    super.initState();
    _anahtarAc();
  }

  @override
  void didUpdateWidget(_OzetYanVeri old) {
    super.didUpdateWidget(old);
    if (old.bellekAnahtari != widget.bellekAnahtari) _anahtarAc();
  }

  @override
  void dispose() {
    _beklemeSayaci?.cancel();
    super.dispose();
  }

  /// Yeni anahtar için durumu kurar: bellekte varsa EŞZAMANLI okunur
  /// (iskelet yok), yoksa iskelet + ölçüm. Bellekteki ölçüm bayatsa yine
  /// gösterilir ve arkada tazelenir.
  ///
  /// Dönem değişince eskiden alanlar tek tek sıfırlanıyordu; artık ölçüm
  /// tek değer ([_YanVeri]) ve anahtara bağlı — başka dönemin TÜFE'si ya da
  /// sağlık metriği yeni döneme taşınamaz.
  void _anahtarAc() {
    final k = widget.bellekAnahtari;
    final bellekte = widget.bellek.yanVeriler.oku(k);
    _veri = bellekte ?? const _YanVeri();
    _beklemeSayaci?.cancel();
    _hazir = bellekte != null;
    if (!_hazir) {
      _beklemeSayaci = Timer(_azamiBekleme, () {
        if (mounted && !_hazir) setState(() => _hazir = true);
      });
    }
    // Saf hesap: ağ turlarını beklemeden.
    _xirr = _xirrHesapla();
    // Dilim YALNIZCA 6A'da isteniyor; başka bir dönemden 6A'ya
    // geçildiğinde istek hiç atılmamış olur. Bayrağı sıfırlamak o
    // geçişte şeridin görünmesini sağlar. Son bilinen dilim bellekten
    // okunur: 6A'ya geri dönen kullanıcı aynı rakamı yeniden beklemeden
    // görür (havuz 24 saatlik pencerede zaten sabit).
    _dilimIstendi = false;
    _dilim = widget.bellek.dilimler[k];
    if (bellekte == null || !widget.bellek.yanVeriler.taze(k)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _yukle(k));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _yukleDilim());
    }
  }

  Future<void> _yukle(String k) async {
    if (!mounted || k != widget.bellekAnahtari) return;
    _istenen = k;
    final assets = widget.assets;
    final period = widget.period;
    final pState = ref.read(portfolioProvider).valueOrNull;
    try {
      final v = await widget.bellek.yanVeriler.yukle(
        k,
        () => _yanVeriYukle(period: period, assets: assets, pState: pState),
      );
      if (!mounted || _istenen != k) return;
      setState(() {
        _veri = v;
        _hazir = true;
      });
    } catch (e, st) {
      // Yan veri ikincil: özet onsuz da tam. Sessiz değil.
      CrashReporter.report(e, st, reason: 'OzetYanVeri.yukle');
      if (mounted && !_hazir) setState(() => _hazir = true);
    }
    _beklemeSayaci?.cancel();
    await _yukleDilim();
  }

  /// 6A yüzdelik dilimini çeker — benchmark şeridi için.
  ///
  /// Dört kapı, `PercentileStrip` ile aynı disiplin: dönem 6A olmalı,
  /// Remote Config bayrağı açık olmalı, kullanıcı yarışa opt-in olmalı ve
  /// oturum açmış olmalı. Sunucudaki k-anonimlik eşiği beşinci kapı —
  /// havuz 8 kişiye ulaşmadıysa RPC boş döner ve şerit hiç çizilmez.
  ///
  /// Bellekten okunan dilim kapılardan biri kapanınca (opt-out, bayrak,
  /// çıkış) düşürülür — ekranda yalnızca hâlâ geçerli bir dilim kalır.
  ///
  /// 180 kovası migration `0051` ile açıldı; ondan önce RPC bu periyodu
  /// geçersiz sayıp boş dönüyordu.
  Future<void> _yukleDilim() async {
    if (!mounted || _dilimIstendi) return;
    if (DemoModu.aktif) return; // Demo sunucuya ROI yüklemez (F1).
    if (widget.period != SummaryPeriod.altiAy) return;
    _dilimIstendi = true;
    final k = widget.bellekAnahtari;

    final me = ref.read(authProvider).valueOrNull;
    if (!RemoteConfigService.instance.percentileStripEnabled ||
        !ref.read(leaderboardOptInProvider) ||
        me == null ||
        widget.assets.isEmpty) {
      widget.bellek.dilimler.remove(k);
      if (_dilim != null) setState(() => _dilim = null);
      return;
    }

    try {
      final servis = LeaderboardService.instance;
      const gun = 180;
      // Anlık görüntüyü cihaz YAZMAZ (0095): cron yarışa katılan herkes için
      // TWR yazar; kendi satırı yoksa RPC boş döner ve dilim gösterilmez.
      final data = await servis.fetchPercentile(gun);
      if (!mounted || data == null) return;

      unawaited(AnalyticsService.instance
          .logPercentileViewed(bucket: data.percentile, periodDays: gun));
      widget.bellek.dilimler[k] = data;
      setState(() => _dilim = data);
    } catch (_) {
      // Sessizce vazgeç: şerit ikincil, özet onsuz da tam.
    }
  }

  /// XIRR — saf hesap, ağa çıkmaz.
  ///
  /// 1Y bloğunda gösterilir: yıllıklandırılmış bir oran daha kısa
  /// pencerelerde yanıltıcı olur (`XirrService.minGun` aynı gerekçeyle
  /// 60 günlük bir taban koyuyor).
  double? _xirrHesapla() {
    if (widget.period != SummaryPeriod.birYil) return null;
    if (widget.assets.isEmpty) return null;

    final pState = ref.read(portfolioProvider).valueOrNull;
    if (pState == null) return null;

    // Bugünkü değer: aktif alım lotlarının toplamı. `totalValueTRY` zaten
    // aynı toplamı `aggregatePositions` üzerinden veriyor ve tek kaynak
    // olarak kullanılıyor — burada ikinci bir toplama yazmak, bu projede
    // tekrar eden bir hata sınıfı olurdu.
    final deger =
        LeaderboardService.instance.totalValueTRY(widget.assets, pState.toTRY);
    if (deger <= 0) return null;

    return XirrService.portfolioXirr(
      assets: widget.assets,
      bugunkuDegerTRY: deger,
      now: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // İlk ölçüm gelmeden özet çizilmez: kartlar sonradan belirip listeyi
    // itmesin (sınıf notu). Bekleme [_azamiBekleme] ile sınırlı.
    if (!_hazir) return widget.iskelet;

    // TÜFE farkı burada bağlanır: servis saf ve ağa çıkmıyor, bu yüzden
    // hesabı yapılmış özeti enflasyonla yeniden kurmak yerine yalnızca
    // farkı hesaplayıp view'a veriyoruz.
    final s = widget.summary;
    final v = _veri;
    final w = v.tufePencere;
    final nominal = v.hizaliNominal;
    // İkisi de TÜFE penceresinden: biri eksikse kart hiç çizilmez.
    final gosterilen = (w != null && nominal != null)
        ? _tufeIle(s, w, nominal, v.hizaliReel)
        : s;

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

    // Aylık birikim serisi (bayrak `birikim_serisi`, kapalı doğar). Saf
    // hesap, aynı defterden; kısa geçmişte (`gosterilir`) çizilmez.
    final seriHam = RemoteConfigService.instance.birikimSerisi
        ? BirikimSerisiService.hesapla(widget.assets, now: DateTime.now())
        : null;
    final seri = (seriHam?.gosterilir ?? false) ? seriHam : null;

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
            drawdown: v.drawdown,
            volatilite: v.volatilite,
            yogunlasma: yogunlasma,
          )
        : null;

    final ileri = widget.period == SummaryPeriod.birYil && gorunur.ileri
        ? IleriMetrikler.hesapla(
            getiriPct: gosterilen.getiriPct,
            volatilitePct: v.volatilite,
            xirrPct: _xirr,
            drawdown: v.drawdown,
          )
        : null;

    return PeriodSummaryView(
      baz: ref.watch(gosterimBazParaProvider),
      summary: gosterilen,
      kiyasKarti: widget.kiyasKarti,
      // Bağlam cümlesi YALNIZCA kayıptaki kısa dönemde: 1Y'nin kendisinde
      // bir pencereyi kendisiyle karşılaştırmak bilgi taşımaz. Ölçüm her
      // dönemde var (`_YanVeri.uzunDonem` notu); kapı burada.
      uzunDonemPct: s.isNegative && widget.period != SummaryPeriod.birYil
          ? v.uzunDonem
          : null,
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
                drawdownPct: gorunur.saglik ? v.drawdown?.yuzde : null,
                percentile: gorunur.percentile && RemoteConfigService.instance.globalLeaderboardEnabled ? _dilim?.percentile : null,
              ),
      katkiKarti: katki == null
          ? null
          : ContributionKarti(
              baz: ref.watch(gosterimBazParaProvider),
              ozet: katki,
              aralik: _katkiAralik,
              onAralik: (a) => setState(() => _katkiAralik = a),
              seri: seri,
              besDahil: seri != null &&
                  widget.assets.any((a) => a.type == AssetType.bes),
            ),
      // Tek metrik bile yoksa kart çizilmesin — `hasData` o kapıyı
      // widget'ın içinde tutuyor ama boş bir kabuk geçirmenin de anlamı
      // yok, burada da eleniyor.
      saglik: (saglik?.hasData ?? false) ? saglik : null,
      ileriKarti: ileri == null ? null : IleriMetrikKarti(metrikler: ileri),
      xirr: gorunur.xirr ? _xirr : null,
      enflasyonVerisiBekleniyor: v.endeksBos,
      tufeKoprusu: v.tufeKoprusu,
      tufePenceresiKisaltildi: w?.kisaltildi ?? false,
      // Derinlik bölümü (XIRR, sağlık, ileri metrikler…) ileri seviyede açık
      // gelir, diğerlerinde katlı: özet önce "bu dönem"i anlatsın.
      derinlikAcik:
          ref.watch(yatirimciSeviyesiProvider) == YatirimciSeviyesi.ileri,
      derinlikGorunur: ref.watch(seviyeGorunurlukProvider).derinlik,
      anaRakamGizli: widget.anaRakamGizli,
      nedenEki: widget.nedenEki,
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
  ///
  /// [reel] servisin REEL PARA AĞIRLIKLI getirisidir (2026-10-01, K4):
  /// burada `(1+n)/(1+e) − 1` ile yeniden türetilmez — o formül yıl içinde
  /// eklenen paraya yılın tamamının enflasyonunu yüklüyordu. Nominal, TÜFE
  /// ve puan farkı aynı kalır.
  PeriodSummary _tufeIle(
    PeriodSummary s,
    InflationWindow w,
    double nominal,
    double? reel,
  ) {
    final enflasyon = w.pct;

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
      ilkAlim: s.ilkAlim,
      baslangicTRY: s.baslangicTRY,
      sonTRY: s.sonTRY,
      katkiTRY: s.katkiTRY,
      piyasaTRY: s.piyasaTRY,
      getiriPct: s.getiriPct,
      yillikGetiriPct: s.yillikGetiriPct,
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
      reelGetiriPct: (reel != null && reel.isFinite) ? reel : null,
      temettuTRY: s.temettuTRY,
      komisyonTRY: s.komisyonTRY,
      dagilimBasi: s.dagilimBasi,
      dagilimSonu: s.dagilimSonu,
      sparkline: s.sparkline,
      gunSayimi: s.gunSayimi,
    );
  }
}
