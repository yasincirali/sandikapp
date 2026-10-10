part of '../paywall_screen.dart';

// ── Kart desteli paywall (bayrak `paywall_deste`, yasin 2026-10-08) ───────
//
// Son hâl prototipi: https://claude.ai/artifact/Fwm1QWqhox792DBk32HEPJ.
// Amber sandık başlığı, sonsuz kart destesi, Yıllık/Aylık sekmesi, büyük
// fiyat, varsa deneme zaman çizelgesi, iki güven satırı ve yapışkan düğme.
// Bayrak kapalıyken eski paywall birebir çizilir (`_PaywallScreenState.build`).
//
// Kurallar (müşteri gözüyle analiz, 2026-10-08):
//  - Deste kullanıcının DOKUNDUĞU kilidin kartıyla açılır ([desteSirasi]);
//    neden burada olduğunu ilk kart söyler.
//  - Kartlardaki sınırlar Remote Config'ten okunur; uygulamada gerçekten
//    kilitli olmayan bir şey kart olmaz (radar kartları `balinaRadariAcik`,
//    ekstre kartı `ekstreAiEsleme` açıkken). Bkz. `_FeatureList` uyarısı.
//  - Ödenecek tutar ekrandaki en büyük metindir; deneme yalnız mağaza bir
//    deneme döndürdüyse gösterilir ve hatırlatma vaat edilmez (gönderen
//    bir servis yok).

/// Destedeki Premium kartları, varsayılan sırasıyla.
///
/// Sıra (2026-10-10, olgun Premium seti): araştırmada para ödenen işler
/// önde — sınır, rapor/vergi, temettü — sonra alışkanlık ve analiz.
/// Fon X-Ray (2026-10-10) temettünün hemen ardında: o da "param gerçekte
/// ne yapıyor" sorusunun ücretli cevabı (getquin/Parqet'te ücretli).
enum PaywallKarti {
  varlik,
  rapor,
  temettu,
  xray,
  sinyal,
  // Mum + EMA50/EMA200 (#150, 2026-10-10): sinyalin yanında — ikisi de
  // "fiyat nereye gidiyor" sorusunun teknik cevabı.
  grafik,
  karsilastir,
  ortak,
  // Çoklu portföy (0133): yalnız `coklu_portfoy` açıkken destede.
  portfoy,
  // Çoklu hesap (0137): bir cihazda birden çok hesap; yalnız `coklu_hesap`
  // açıkken destede.
  hesap,
  akis,
  hacim,
  not,
  ekstre
}

/// Saf: paywall'u açan kaynağın kartı. Bilinmeyen kaynak (profil bandı,
/// ayarlar…) null.
PaywallKarti? kaynaktanKart(String source) {
  if (source.startsWith('asset_limit') ||
      source == 'bulk_add_asset_limit' ||
      source == 'watchlist_limit') {
    return PaywallKarti.varlik;
  }
  if (source.startsWith('signal_') ||
      source == 'sinyal_varlik' ||
      source == 'sinyal_kilit') {
    return PaywallKarti.sinyal;
  }
  return switch (source) {
    'yillik_rapor' ||
    'portfoy_disa_aktar' ||
    'masraf_dokumu' =>
      PaywallKarti.rapor,
    'temettu_tahmini' => PaywallKarti.temettu,
    'fon_xray' || 'portfoy_xray' => PaywallKarti.xray,
    'aylik_rapor' => PaywallKarti.not,
    'grafik_mum' || 'grafik_ema' => PaywallKarti.grafik,
    'compare_series' => PaywallKarti.karsilastir,
    'coklu_hesap' => PaywallKarti.hesap,
    'partner_limit' => PaywallKarti.ortak,
    // Kısmi aktarım ve ortağın göreceği portföyü seçmek de çoklu portföyün
    // Premium yarısı (#148); kart aynı.
    'portfoy_limit' ||
    'portfoy_kismi_aktar' ||
    'ortak_paylasim' =>
      PaywallKarti.portfoy,
    'para_akisi_karti' => PaywallKarti.akis,
    'hacim_radari' || 'kripto_baski' => PaywallKarti.hacim,
    'analiz_notu' => PaywallKarti.not,
    'ekstre_ai' => PaywallKarti.ekstre,
    _ => null,
  };
}

/// Saf: destenin kart sırası. Açık olmayan özelliğin kartı çıkar; kaynağın
/// kartı (destede varsa) başa alınır, gerisi varsayılan sırada.
List<PaywallKarti> desteSirasi(
  String source, {
  required bool radar,
  required bool ekstreAi,
  // Varsayılan kapalı: bayrak açılmadan satılmaz (açılmamış şey satılmaz).
  bool portfoy = false,
  bool hesap = false,
}) {
  final acik = [
    for (final k in PaywallKarti.values)
      if (switch (k) {
        PaywallKarti.akis || PaywallKarti.hacim || PaywallKarti.not => radar,
        PaywallKarti.ekstre => ekstreAi,
        PaywallKarti.portfoy => portfoy,
        PaywallKarti.hesap => hesap,
        _ => true,
      })
        k,
  ];
  final bas = kaynaktanKart(source);
  if (bas == null || !acik.contains(bas)) return acik;
  return [bas, ...acik.where((k) => k != bas)];
}

/// Kart renkleri. Kartlar marka yüzeyleridir; iki temada da aynı görünür
/// (prototipteki koyu yeşil / amber / krem / orta yeşil). Değerler paletten
/// gelir, ham renk yazılmaz.
class _KartRengi {
  const _KartRengi(this.zemin, this.metin, this.vurgu, this.soluk);

  final Color zemin;
  final Color metin;
  final Color vurgu;

  /// Grafiklerde vurgulanmayan çubuk / çizgi.
  final Color soluk;

  static const _d = SandikPalette.dark;
  static const _a = SandikPalette.light;

  static final koyu = _KartRengi(
      _d.surface2, _d.text90, _d.gold, _d.text90.withValues(alpha: 0.28));
  static final amber = _KartRengi(
      _d.amberFill, _d.onAmber, _d.onAmber, _d.onAmber.withValues(alpha: 0.2));
  static final krem = _KartRengi(
      _a.surface2, _a.text90, _a.amberText, _a.text90.withValues(alpha: 0.22));
  // Krem kart açık temada zeminle aynı tonda kayboluyordu; beyaz yüzey.
  // Orta yeşil üstünde beyaz metin 5,37:1 (`onStatus` gerekçesi).
  static final yesil = _KartRengi(
      _a.gain, _a.onStatus, _d.gold, _a.onStatus.withValues(alpha: 0.22));
}

class _DesteGovdesi extends StatefulWidget {
  const _DesteGovdesi({
    required this.source,
    required this.yillik,
    required this.onPlan,
    required this.fiyatYillik,
    required this.fiyatAylik,
    required this.aylikKarsiligi,
    required this.oran,
    required this.yillikDeneme,
    required this.aylikDeneme,
    required this.android,
    required this.busy,
    required this.onSatinAl,
    required this.onGeriYukle,
  });

  final String source;
  final bool yillik;
  final ValueChanged<bool> onPlan;

  /// Ham fiyat metinleri ('399,99 ₺'); birim ekini burası koyar.
  final String fiyatYillik;
  final String fiyatAylik;

  /// Yıllık planın aylık karşılığı (mağaza `pricePerMonthString`); yoksa
  /// satır kısalır, hesaplanıp uydurulmaz.
  final String? aylikKarsiligi;
  final int? oran;
  final int? yillikDeneme;
  final int? aylikDeneme;
  final bool android;
  final bool busy;
  final Future<void> Function() onSatinAl;
  final Future<void> Function() onGeriYukle;

  @override
  State<_DesteGovdesi> createState() => _DesteGovdesiState();
}

class _DesteGovdesiState extends State<_DesteGovdesi> {
  List<DesteKarti>? _kartlar;
  Locale? _dil;

  /// Kartlar bir kez kurulur (plan sekmesi değişince deste yeniden
  /// kurulmasın: kabuklar `RepaintBoundary`'de önbellekte kalır). Dil
  /// değişirse yeniden.
  List<DesteKarti> _desteKartlari(BuildContext context) {
    final dil = Localizations.maybeLocaleOf(context);
    if (_kartlar != null && dil == _dil) return _kartlar!;
    _dil = dil;
    final rc = RemoteConfigService.instance;
    final sira = desteSirasi(widget.source,
        radar: rc.balinaRadariAcik,
        ekstreAi: rc.ekstreAiEsleme,
        portfoy: rc.cokluPortfoy,
        hesap: rc.cokluHesap);
    return _kartlar = [for (final k in sira) _kart(context, k)];
  }

  DesteKarti _kart(BuildContext context, PaywallKarti k) {
    final l = context.l10n;
    final rc = RemoteConfigService.instance;
    final (renk, etiket, baslik, rozet, gorsel, ucretsiz, premium) =
        switch (k) {
      PaywallKarti.varlik => (
          _KartRengi.koyu,
          l.pwdVarlikEtiket,
          l.pwdVarlikBaslik(rc.freeAssetLimit),
          null,
          _VarlikGorseli(sinir: rc.freeAssetLimit, renk: _KartRengi.koyu),
          l.pwdVarlikUcretsiz(rc.freeAssetLimit, rc.paywallWatchlistLimit),
          l.prmSinirsiz,
        ),
      PaywallKarti.rapor => (
          _KartRengi.krem,
          l.pwdRaporEtiket,
          l.pwdRaporBaslik,
          'PDF · Excel',
          _BelgeGorseli(renk: _KartRengi.krem),
          null,
          l.pwdRaporPremium,
        ),
      PaywallKarti.temettu => (
          _KartRengi.yesil,
          l.pwdTemettuEtiket,
          l.pwdTemettuBaslik,
          null,
          _Cubuklar(
              degerler: const [8, 18, 8, 64, 8, 8, 22, 8, 40, 8, 30, 92],
              vurgulu: 1,
              aralik: SandikSpace.xs,
              renk: _KartRengi.yesil),
          null,
          l.pwdTemettuPremium,
        ),
      // Fon X-Ray bütünüyle Premium: ücretsiz satırı yok.
      PaywallKarti.xray => (
          _KartRengi.koyu,
          l.pwdXrayEtiket,
          l.pwdXrayBaslik,
          null,
          _YiginGorseli(renk: _KartRengi.koyu),
          null,
          l.pwdXrayPremium,
        ),
      // Sinyal paywall açıkken bütünüyle Premium (2026-10-10): ücretsiz
      // satırı yok.
      PaywallKarti.sinyal => (
          _KartRengi.amber,
          l.pwdSinyalEtiket,
          l.pwdSinyalBaslik,
          l.pwdSinyalRozet,
          _SaatGorseli(renk: _KartRengi.amber),
          null,
          l.pwdSinyalPremium,
        ),
      // Grafik katmanları bütünüyle Premium: ücretsiz satırı yok (çizgi
      // grafik ücretsizde aynen kalır, yalnız katmanlar kilitli).
      PaywallKarti.grafik => (
          _KartRengi.koyu,
          l.pwdGrafikEtiket,
          l.pwdGrafikBaslik,
          'EMA50 · EMA200',
          const _MumGorseli(),
          null,
          l.pwdGrafikPremium,
        ),
      PaywallKarti.karsilastir => (
          _KartRengi.krem,
          l.pwdKarsEtiket,
          l.pwdKarsBaslik,
          l.pwdKarsRozet(_ucretsizSeri, kKarsilastirmaEnFazla),
          _CizgiGorseli(renk: _KartRengi.krem),
          l.pwdSeri(_ucretsizSeri),
          l.pwdSeri(kKarsilastirmaEnFazla),
        ),
      PaywallKarti.ortak => (
          _KartRengi.yesil,
          l.pwdOrtakEtiket,
          l.pwdOrtakBaslik,
          null,
          _OrtakGorseli(renk: _KartRengi.yesil),
          l.pwdOrtakSayi(rc.freePartnerLimit),
          l.prmSinirsiz,
        ),
      // Çoklu portföy: ücretsizde 1 (Ana), Premium sınırsız
      // (`portfoyLimitProvider`).
      PaywallKarti.portfoy => (
          _KartRengi.koyu,
          l.pwdPortfoyEtiket,
          l.pwdPortfoyBaslik,
          null,
          _Cubuklar(
              degerler: const [34, 58, 82, 46],
              vurgulu: 1,
              aralik: SandikSpace.sm,
              renk: _KartRengi.koyu),
          l.pwdPortfoySayi(1),
          l.pwdPortfoyPremium,
        ),
      // Çoklu hesap: ücretsizde tek hesap, Premium'da ek hesap ve geçiş
      // (`hesapEklemeKilitliProvider`). Geçiş ücretsizde de çalışır —
      // eklenmiş hesaba dönebilmek kilitlenmez; satılan ŞEY eklemedir.
      PaywallKarti.hesap => (
          _KartRengi.krem,
          l.pwdHesapEtiket,
          l.pwdHesapBaslik,
          null,
          _OrtakGorseli(renk: _KartRengi.krem),
          l.pwdHesapUcretsiz,
          l.pwdHesapPremium,
        ),
      PaywallKarti.akis => (
          _KartRengi.amber,
          l.pwdAkisEtiket,
          l.pwdAkisBaslik,
          null,
          _Cubuklar(
              degerler: const [40, 62, 30, 74, 55, 82, 66, 96],
              vurgulu: 1,
              aralik: SandikSpace.xs2,
              renk: _KartRengi.amber),
          l.prmAkisUcretsiz,
          l.prmAkisPremium,
        ),
      PaywallKarti.hacim => (
          _KartRengi.koyu,
          l.pwdHacimEtiket,
          l.pwdHacimBaslik,
          null,
          _Cubuklar(degerler: const [
            22, 30, 26, 35, 28, 24, 31, 27, 33, 29, //
            25, 30, 28, 26, 34, 27, 30, 29, 88, 64,
          ], vurgulu: 2, aralik: SandikSpace.xs, renk: _KartRengi.koyu),
          l.prmHacimUcretsiz,
          l.prmHacimPremium,
        ),
      PaywallKarti.not => (
          _KartRengi.krem,
          l.pwdNotEtiket,
          l.pwdNotBaslik,
          null,
          const _NotGorseli(),
          l.prmNotUcretsiz,
          l.prmNotPremium,
        ),
      PaywallKarti.ekstre => (
          _KartRengi.yesil,
          l.pwdEkstreEtiket,
          l.pwdEkstreBaslik,
          null,
          _EkstreGorseli(renk: _KartRengi.yesil),
          null,
          l.pwdEkstrePremium,
        ),
    };
    return DesteKarti(
      zemin: renk.zemin,
      semantik: '$etiket. $baslik',
      child: _KartIcerik(
        renk: renk,
        etiket: etiket,
        rozet: rozet,
        baslik: baslik,
        gorsel: gorsel,
        ucretsiz: ucretsiz == null ? null : l.pwdUcretsiz(ucretsiz),
        premium: l.pwdPremium(premium),
      ),
    );
  }

  int get _ucretsizSeri => RemoteConfigService.instance.freeCompareSeries
      .clamp(1, kKarsilastirmaEnFazla);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final yillik = widget.yillik;
    final deneme = yillik ? widget.yillikDeneme : widget.aylikDeneme;
    final fiyat = yillik
        ? l.pwFiyatYillik(widget.fiyatYillik)
        : l.pwFiyatAylik(widget.fiyatAylik);
    final alt = switch ((yillik, deneme)) {
      (true, final int d) => l.pwdYillikDenemeAlt(d, widget.fiyatYillik),
      (false, final int d) => l.pwdAylikDenemeAlt(d, widget.fiyatAylik),
      (true, null) => widget.aylikKarsiligi == null
          ? l.pwdYillikAltSade
          : l.pwdYillikAlt(widget.aylikKarsiligi!),
      (false, null) => l.pwdAylikAlt,
    };
    final yan = SandikSpace.lgs;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesteBaslik(
                    onGeriYukle: widget.busy ? null : widget.onGeriYukle),
                const SizedBox(height: SandikSpace.lg),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: yan),
                  child: KartDestesi(
                    kartlar: _desteKartlari(context),
                    oncekiEtiketi: l.pwdOnceki,
                    sonrakiEtiketi: l.pwdSonraki,
                    ipucu: l.pwdIpucu,
                  ),
                ),
                const SizedBox(height: SandikSpace.lgs),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: yan),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PlanSekmeleri(yillik: yillik, onPlan: widget.onPlan),
                      const SizedBox(height: SandikSpace.md2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              fiyat,
                              style: t.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: c.gold,
                                letterSpacing: -0.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                          if (yillik && widget.oran != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: SandikSpace.sm,
                                  vertical: SandikSpace.xxs),
                              decoration: BoxDecoration(
                                color: c.gain,
                                borderRadius:
                                    BorderRadius.circular(SandikRadius.sm),
                              ),
                              child: Text(
                                l.prmYillikTasarruf('${widget.oran}'),
                                style: t.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                    color: c.onStatus),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: SandikSpace.xs),
                      Text(alt,
                          style: t.bodySmall
                              ?.copyWith(color: c.text58, height: 1.4)),
                      if (deneme != null) ...[
                        const SizedBox(height: SandikSpace.md2),
                        _DenemeCizelgesi(gun: deneme),
                      ],
                      const SizedBox(height: SandikSpace.md2),
                      _GuvenSatiri(metin: l.pwdGuvenTakip),
                      const SizedBox(height: SandikSpace.sm),
                      _GuvenSatiri(metin: l.pwdGuvenIptal),
                      const SizedBox(height: SandikSpace.lgs),
                      // Mağaza kuralı: yenileme/iptal, varsa deneme koşulu,
                      // Koşullar + Gizlilik bağlantıları satın alma ekranında.
                      Text(
                        [
                          widget.android
                              ? l.pwKosulAndroid
                              : l.subscriptionTerms,
                          if (deneme != null) l.pwDenemeKosul(deneme),
                        ].join(' '),
                        style:
                            t.bodySmall?.copyWith(color: c.text36, height: 1.5),
                      ),
                      const SizedBox(height: SandikSpace.sm),
                      Wrap(
                        spacing: SandikSpace.md,
                        children: [
                          _BelgeBaglantisi(
                              metin: l.termsOfUse, belge: YasalBelge.kosullar),
                          _BelgeBaglantisi(
                              metin: l.privacyPolicy,
                              belge: YasalBelge.gizlilik),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              busy: widget.busy,
              etiket: deneme != null
                  ? l.pwDenemeDugme(deneme)
                  : (yillik ? l.pwdYillikAboneOl : l.pwdAylikAboneOl),
              onSubscribe: widget.onSatinAl,
              onRestore: widget.onGeriYukle,
              // Geri yükle başlıkta; altta ikinci kez durmaz.
              geriYukleGoster: false,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Başlık: amber panel, kapat + geri yükle, slogan ve sandık ─────────────

class _DesteBaslik extends StatelessWidget {
  const _DesteBaslik({required this.onGeriYukle});

  final Future<void> Function()? onGeriYukle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    final ust = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.amberFill,
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(SandikSpace.xl)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            SandikSpace.sm, ust + SandikSpace.sm, SandikSpace.sm, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: Icon(Icons.close_rounded, color: c.onAmber),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: onGeriYukle,
                      style: TextButton.styleFrom(foregroundColor: c.onAmber),
                      child: Text(l.restorePurchase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                              color: c.onAmber, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: SandikSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: SandikSpace.lgs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.sandikPremiumUpper,
                              style: t.labelMedium?.copyWith(
                                  color: c.onAmber,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4)),
                          const SizedBox(height: SandikSpace.xs2),
                          Text(l.pwdSlogan,
                              style: t.headlineLarge?.copyWith(
                                  color: c.onAmber,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                  letterSpacing: -0.6)),
                        ],
                      ),
                    ),
                  ),
                  // Ortak çizim (`sandik_cizimi.dart`); paywall'daki ilk
                  // hâli birebir: amber zemin, açılarak gelir, dokununca
                  // açılır/kapanır.
                  const SandikCizimi(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan sekmesi, deneme çizelgesi, güven satırı ──────────────────────────

class _PlanSekmeleri extends StatelessWidget {
  const _PlanSekmeleri({required this.yillik, required this.onPlan});

  final bool yillik;
  final ValueChanged<bool> onPlan;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    Widget sekme(String metin, bool secili, bool deger) => Expanded(
          child: Semantics(
            button: true,
            selected: secili,
            child: SandikBasma(
              onTap: () => onPlan(deger),
              olcek: 0.98,
              child: AnimatedContainer(
                duration: SandikMotion.stateOf(context),
                curve: SandikMotion.enter,
                height: SandikTouch.min,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      secili ? c.amberFill : c.amberFill.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(SandikSpace.sm2),
                ),
                child: Text(metin,
                    style: context.t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: secili ? c.onAmber : c.text58)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(SandikSpace.xs),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          sekme(l.planYearly, yillik, true),
          const SizedBox(width: SandikSpace.xs),
          sekme(l.planMonthly, !yillik, false),
        ],
      ),
    );
  }
}

/// Deneme zaman çizelgesi: bugün her şey açık, N. gün ilk ödeme. Yalnız
/// mağaza bir deneme döndürdüyse çizilir. "Hatırlatırız" satırı bilerek
/// yok: hatırlatmayı gönderen bir servis olmadan vaat edilmez.
class _DenemeCizelgesi extends StatelessWidget {
  const _DenemeCizelgesi({required this.gun});

  final int gun;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final l = context.l10n;
    Widget hucre(String ust, String alt) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SandikSpace.smd, vertical: SandikSpace.sm2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ust,
                    style: t.labelMedium?.copyWith(
                        color: c.amberText, fontWeight: FontWeight.w800)),
                const SizedBox(height: SandikSpace.xxs),
                Text(alt,
                    style: t.bodyMedium?.copyWith(
                        color: c.text90, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: c.hairline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hucre(l.pwdBugun, l.pwdHerSeyAcik),
            VerticalDivider(width: 1, thickness: 1, color: c.hairline),
            hucre(l.pwdGun(gun), l.pwdIlkOdeme),
          ],
        ),
      ),
    );
  }
}

class _GuvenSatiri extends StatelessWidget {
  const _GuvenSatiri({required this.metin});

  final String metin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_rounded, size: 18, color: context.c.gain),
        const SizedBox(width: SandikSpace.sm2),
        Expanded(
          child: Text(metin,
              style: context.t.bodyMedium?.copyWith(color: context.c.text90)),
        ),
      ],
    );
  }
}

// ── Kart içeriği ve görselleri ────────────────────────────────────────────

class _KartIcerik extends StatelessWidget {
  const _KartIcerik({
    required this.renk,
    required this.etiket,
    required this.rozet,
    required this.baslik,
    required this.gorsel,
    required this.ucretsiz,
    required this.premium,
  });

  final _KartRengi renk;
  final String etiket;
  final String? rozet;
  final String baslik;
  final Widget gorsel;
  final String? ucretsiz;
  final String premium;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final kucuk = t.bodySmall
        ?.copyWith(color: renk.metin, fontWeight: FontWeight.w700, height: 1.3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(etiket,
                  style: t.labelMedium?.copyWith(
                      color: renk.vurgu,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ),
            if (rozet != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
                decoration: BoxDecoration(
                  color: renk.metin.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Text(rozet!,
                    style: t.labelMedium?.copyWith(
                        color: renk.metin, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: SandikSpace.smd),
        Text(baslik,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: t.headlineMedium?.copyWith(
                color: renk.metin,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.3)),
        const SizedBox(height: SandikSpace.smd),
        Expanded(
          child: LayoutBuilder(
            builder: (context, k) => Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: math.min(k.maxHeight, 100),
                width: double.infinity,
                child: gorsel,
              ),
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.smd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ucretsiz != null)
              Expanded(
                child: Text(ucretsiz!,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: kucuk),
              ),
            const SizedBox(width: SandikSpace.sm2),
            Expanded(
              child: Text(premium,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kucuk?.copyWith(color: renk.vurgu)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Çubuk grafik (temsilî; veri değil). Son [vurgulu] çubuk vurgulanır.
class _Cubuklar extends StatelessWidget {
  const _Cubuklar({
    required this.degerler,
    required this.vurgulu,
    required this.aralik,
    required this.renk,
  });

  final List<double> degerler;
  final int vurgulu;
  final double aralik;
  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, k) {
      final h = k.maxHeight.isFinite ? k.maxHeight : 100.0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < degerler.length; i++) ...[
            if (i > 0) SizedBox(width: aralik),
            Expanded(
              child: Container(
                height: h * degerler[i] / 100,
                decoration: BoxDecoration(
                  color:
                      i >= degerler.length - vurgulu ? renk.vurgu : renk.soluk,
                  borderRadius: BorderRadius.circular(SandikSpace.xs),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _VarlikGorseli extends StatelessWidget {
  const _VarlikGorseli({required this.sinir, required this.renk});

  final int sinir;
  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    final stil = context.t.bodyMedium
        ?.copyWith(color: renk.metin, fontWeight: FontWeight.w700);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          children: [
            Expanded(child: Text(context.l10n.pwdVarlikCubuk, style: stil)),
            Text('$sinir / $sinir', style: stil?.copyWith(color: renk.vurgu)),
          ],
        ),
        const SizedBox(height: SandikSpace.sm),
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: renk.vurgu,
            borderRadius: BorderRadius.circular(SandikSpace.xs2),
          ),
        ),
      ],
    );
  }
}

/// Saat çubukları: seçtiğin iki saat (11 ve 15) yüksek.
class _SaatGorseli extends StatelessWidget {
  const _SaatGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    final stil = context.t.labelSmall
        ?.copyWith(color: renk.metin, fontWeight: FontWeight.w700);
    return LayoutBuilder(builder: (context, k) {
      final h = (k.maxHeight.isFinite ? k.maxHeight : 100.0) - 18;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var s = 10; s <= 18; s++) ...[
            if (s > 10) const SizedBox(width: SandikSpace.xs),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: math.max(0, h * (s == 11 || s == 15 ? 0.8 : 0.3)),
                    decoration: BoxDecoration(
                      color: s == 11 || s == 15 ? renk.vurgu : renk.soluk,
                      borderRadius: BorderRadius.circular(SandikSpace.xs),
                    ),
                  ),
                  const SizedBox(height: SandikSpace.xxs),
                  Text('$s', style: stil, maxLines: 1),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Karşılaştırma çizgileri (temsilî): iki seçili seri koyu, kilitli iki
/// seri soluk.
class _CizgiGorseli extends StatelessWidget {
  const _CizgiGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _CizgiBoyasi(
          ana: SandikPalette.light.gain,
          ikinci: SandikPalette.dark.amberFill,
          soluk: renk.soluk,
        ),
      );
}

class _CizgiBoyasi extends CustomPainter {
  const _CizgiBoyasi(
      {required this.ana, required this.ikinci, required this.soluk});

  final Color ana;
  final Color ikinci;
  final Color soluk;

  static const _seriler = [
    [80.0, 72, 60, 64, 40, 34, 20],
    [85.0, 80, 78, 66, 62, 50, 44],
    [90.0, 88, 82, 84, 74, 70, 66],
    [70.0, 74, 76, 72, 78, 74, 80],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var s = 0; s < _seriler.length; s++) {
      final noktalar = _seriler[s];
      final yol = Path();
      for (var i = 0; i < noktalar.length; i++) {
        final x = size.width * i / (noktalar.length - 1);
        final y = size.height * noktalar[i] / 100;
        i == 0 ? yol.moveTo(x, y) : yol.lineTo(x, y);
      }
      canvas.drawPath(
        yol,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = switch (s) { 0 => ana, 1 => ikinci, _ => soluk },
      );
    }
  }

  @override
  bool shouldRepaint(_CizgiBoyasi old) =>
      old.ana != ana || old.ikinci != ikinci || old.soluk != soluk;
}

/// Mum grafik + iki EMA (temsilî): yükselen mum yeşil, düşen kırmızı;
/// EMA50 yeşil, EMA200 kırmızı çizgi — uygulamadaki grafikle aynı renk
/// anlamı (`grafik_katmanlari.dart`). Koyu kartta okunsun diye koyu palet.
class _MumGorseli extends StatelessWidget {
  const _MumGorseli();

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _MumBoyasi(
          artis: SandikPalette.dark.gain,
          dusus: SandikPalette.dark.loss,
        ),
      );
}

class _MumBoyasi extends CustomPainter {
  const _MumBoyasi({required this.artis, required this.dusus});

  final Color artis;
  final Color dusus;

  // (açılış, kapanış, en yüksek, en düşük); 0 üst, 100 alt.
  static const _mumlar = [
    (88.0, 70.0, 62.0, 96.0),
    (70.0, 80.0, 64.0, 90.0),
    (80.0, 58.0, 50.0, 84.0),
    (58.0, 66.0, 52.0, 76.0),
    (66.0, 42.0, 34.0, 70.0),
    (42.0, 50.0, 36.0, 60.0),
    (50.0, 30.0, 22.0, 54.0),
    (30.0, 38.0, 24.0, 46.0),
    (38.0, 12.0, 4.0, 42.0),
  ];
  static const _ema50 = <double>[86, 80, 74, 68, 60, 54, 46, 40, 30];
  static const _ema200 = <double>[96, 93, 89, 85, 81, 77, 72, 68, 63];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _mumlar.length;
    final adim = size.width / n;
    double y(double v) => size.height * v / 100;
    double x(int i) => adim * (i + 0.5);

    for (final (seri, renk) in [(_ema200, dusus), (_ema50, artis)]) {
      final yol = Path();
      for (var i = 0; i < seri.length; i++) {
        i == 0 ? yol.moveTo(x(i), y(seri[i])) : yol.lineTo(x(i), y(seri[i]));
      }
      canvas.drawPath(
        yol,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = renk.withValues(alpha: 0.75),
      );
    }

    for (var i = 0; i < n; i++) {
      final (ac, kap, yuk, dus) = _mumlar[i];
      // Ekran koordinatı ters: kapanış yukarıdaysa (küçük sayı) yükseliş.
      final renk = kap < ac ? artis : dusus;
      final boya = Paint()..color = renk;
      canvas.drawLine(
        Offset(x(i), y(yuk)),
        Offset(x(i), y(dus)),
        boya..strokeWidth = 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x(i) - adim * 0.28, y(ac < kap ? ac : kap),
              x(i) + adim * 0.28, y(ac < kap ? kap : ac)),
          const Radius.circular(2),
        ),
        boya,
      );
    }
  }

  @override
  bool shouldRepaint(_MumBoyasi old) =>
      old.artis != artis || old.dusus != dusus;
}

class _OrtakGorseli extends StatelessWidget {
  const _OrtakGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    final zeminler = [
      renk.vurgu,
      renk.metin,
      renk.metin.withValues(alpha: 0.18),
      renk.metin.withValues(alpha: 0.18),
    ];
    final ikonlar = [
      SandikPalette.dark.onAmber,
      SandikPalette.dark.onAmber,
      renk.metin,
      renk.metin,
    ];
    return Align(
      alignment: Alignment.bottomLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              Align(
                widthFactor: i == 3 ? 1 : 0.78,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(zeminler[i], renk.zemin),
                    shape: BoxShape.circle,
                    border: Border.all(color: renk.zemin, width: 3),
                  ),
                  child:
                      Icon(Icons.person_rounded, color: ikonlar[i], size: 28),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotGorseli extends StatelessWidget {
  const _NotGorseli();

  @override
  Widget build(BuildContext context) {
    const a = SandikPalette.light;
    final l = context.l10n;
    final stil = context.t.bodyMedium?.copyWith(height: 1.45, color: a.text90);
    return Container(
      padding: const EdgeInsets.all(SandikSpace.md2),
      decoration: BoxDecoration(
        color: a.background,
        borderRadius: BorderRadius.circular(SandikRadius.md),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: l.pwdNotIlk,
              style: stil?.copyWith(fontWeight: FontWeight.w600)),
          TextSpan(
              text: l.pwdNotDevam,
              style: stil?.copyWith(color: a.text90.withValues(alpha: 0.3))),
        ]),
        overflow: TextOverflow.fade,
      ),
    );
  }
}

/// Yıllık rapor kartı: üç satırlık belge — sol etiket, sağ tutar sütunu.
class _BelgeGorseli extends StatelessWidget {
  const _BelgeGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    Widget cubuk(double oran, Color c) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: oran,
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(SandikSpace.xs),
            ),
          ),
        );
    Widget satir(double sol, double sag) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
          child: Row(
            children: [
              Expanded(flex: 3, child: cubuk(sol, renk.soluk)),
              const SizedBox(width: SandikSpace.sm2),
              Expanded(flex: 2, child: cubuk(sag, renk.vurgu)),
            ],
          ),
        );
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [satir(0.9, 0.7), satir(0.6, 0.5), satir(0.8, 0.9)],
    );
  }
}

/// Fon X-Ray kartı: üç yığılmış çubuk (iki fonun içi ve portföyün
/// toplamı). Oranlar temsilîdir, gerçek veri değil — öteki kart
/// görselleri gibi yalnız biçimi anlatır.
class _YiginGorseli extends StatelessWidget {
  const _YiginGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    final tonlar = [
      renk.vurgu,
      renk.vurgu.withValues(alpha: 0.6),
      renk.vurgu.withValues(alpha: 0.3),
      renk.soluk,
    ];
    Widget satir(List<int> paylar) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SandikSpace.xs),
            child: SizedBox(
              height: SandikSpace.smd,
              child: Row(
                children: [
                  for (var i = 0; i < paylar.length; i++)
                    Expanded(
                      flex: paylar[i],
                      child: ColoredBox(color: tonlar[i % tonlar.length]),
                    ),
                ],
              ),
            ),
          ),
        );
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        satir(const [62, 18, 12, 8]),
        satir(const [20, 45, 25, 10]),
        satir(const [38, 30, 20, 12]),
      ],
    );
  }
}

class _EkstreGorseli extends StatelessWidget {
  const _EkstreGorseli({required this.renk});

  final _KartRengi renk;

  @override
  Widget build(BuildContext context) {
    Widget satir(double oran, bool tamam) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
          child: Row(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: oran,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: renk.soluk,
                      borderRadius: BorderRadius.circular(SandikSpace.xs),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SandikSpace.sm2),
              Icon(tamam ? Icons.check_circle_rounded : Icons.auto_awesome,
                  size: 18, color: renk.vurgu),
            ],
          ),
        );
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [satir(0.9, true), satir(0.7, true), satir(0.8, false)],
    );
  }
}
