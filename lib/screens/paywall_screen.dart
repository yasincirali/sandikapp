import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../providers/preferences_provider.dart'
    show kKarsilastirmaEnFazla, ortakSiniriDoluProvider;
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/remote_config_service.dart';
import '../services/satin_alma_service.dart';
import '../services/yasal_metin_katalogu.dart' show YasalBelge;
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart' show parseTrNumber;
import '../widgets/kart_destesi.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/sandik_cizimi.dart';
import '../l10n/l10n.dart';
import 'legal_doc_screen.dart' show belgeyiAc;

part 'paywall/paywall_deste.dart';

/// Premium'a geçiş için paywall (RevenueCat, 2026-10-08).
///
/// Satın alma [SatinAlmaService] üzerinden mağazaya gider; başarıda hak
/// `magazaPremiumProvider` + sunucu (`premium_haklari`, webhook) üzerinden
/// gelir. Eskiden [_satinAl] 600 ms bekleyip cihazdaki geliştirici anahtarını
/// açıyordu: parası alınmadan Premium (2026-10-06 bulgusu).
///
/// Fiyat ve deneme süresi MAĞAZADAN okunur (`priceString`, [denemeGunu]);
/// mağaza yanıt vermezse Remote Config fiyatı gösterilir ama deneme vaat
/// edilmez, düğme "Abone ol" der ve dokununca "kullanılamıyor" söylenir.
///
/// Kullanım:
///   PaywallScreen.show(context, source: 'asset_limit_dialog');
/// Yeni ortak eklemeden önce çağrılır: ücretsiz sınır doluysa paywall'u
/// açar ve true döner (çağıran işi bırakır). Üç giriş (kod üret, kod gir,
/// daveti kabul) aynı kararı buradan alır.
bool ortakSiniriPaywalliActi(BuildContext context, WidgetRef ref) {
  if (!ref.read(ortakSiniriDoluProvider)) return false;
  AnalyticsService.instance.logPremiumGateShown(feature: 'partner_limit');
  PaywallScreen.show(context, source: 'partner_limit');
  return true;
}

class PaywallScreen extends ConsumerStatefulWidget {
  final String source;
  const PaywallScreen({super.key, required this.source});

  static Future<bool?> show(BuildContext context, {required String source}) {
    // Güvenlik ağı: master switch kapalıyken paywall açılmasın. UI trigger'lar
    // zaten gate'leniyor ama merkezi bir noktada da tut.
    if (!RemoteConfigService.instance.paywallEnabled) {
      return Future.value(null);
    }
    AnalyticsService.instance.logPremiumUpgradeStarted(source: source);
    return Navigator.of(context).push<bool>(
      adaptiveRoute(
        fullscreenDialog: true,
        builder: (_) => PaywallScreen(source: source),
      ),
    );
  }

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

enum _Plan { monthly, yearly }

/// Yıllık planın aylığa göre tasarrufu, fiyat metinlerinden hesaplanır.
///
/// **Neden:** rozet eskiden sabit '%40' idi; fiyatlar Remote Config'ten
/// geliyor, fiyat değişince rozet yanlış bir indirim vaat ederdi (49₺ ×
/// 12 = 588₺, 349₺ → %40,6 idi; 399₺ ile %32). Yüzde aşağı
/// yuvarlanır (abartmaz); fiyat okunamazsa ya da tasarruf yoksa rozet
/// hiç çıkmaz: uydurma sayı yazılmaz.
///
/// Saf hesap (test edilir): '49₺/ay', '399₺/yıl' → 32. Okunamaz ya da
/// tasarruf 1 puanın altındaysa null. Mağaza teklifi geldiyse
/// [tasarrufOrani] sayısal fiyatla çağrılır.
int? yillikTasarrufOrani(String aylik, String yillik) {
  double? sayi(String m) {
    final e = RegExp(r'\d[\d.,]*').firstMatch(m);
    return e == null ? null : parseTrNumber(e.group(0)!);
  }

  final a = sayi(aylik), y = sayi(yillik);
  if (a == null || y == null) return null;
  return tasarrufOrani(a, y);
}

/// Saf: sayısal fiyatlardan aynı oran. Mağaza fiyatı metinden değil buradan
/// hesaplanır: `priceString` cihaz diline göre biçimlenir ('TRY 49.99'),
/// metinden okumak İngilizce cihazda 100 kat yanlış oran verirdi.
int? tasarrufOrani(double aylik, double yillik) {
  if (aylik <= 0) return null;
  final oran = ((1 - yillik / (aylik * 12)) * 100).floor();
  return oran >= 1 ? oran : null;
}

/// Saf: Remote Config fiyat metninden birim ekini atar ('49₺/ay' → '49₺').
/// Desteli paywall eki kendisi koyar; mağaza fiyatı zaten eksizdir.
String _birimsiz(String rcFiyat) => rcFiyat.split('/').first.trim();

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _Plan _selected = _Plan.yearly;
  bool _busy = false;
  MagazaTeklifi? _teklif;

  @override
  void initState() {
    super.initState();
    CrashReporter.arkaPlan(_teklifiYukle(), reason: 'Paywall teklif');
  }

  Future<void> _teklifiYukle() async {
    final t = await SatinAlmaService.instance.teklif();
    if (mounted && t != null) setState(() => _teklif = t);
  }

  Package? get _seciliPaket =>
      _selected == _Plan.yearly ? _teklif?.yillik : _teklif?.aylik;

  @override
  Widget build(BuildContext context) {
    final rc = RemoteConfigService.instance;
    final l = context.l10n;
    final aylikUrun = _teklif?.aylik?.storeProduct;
    final yillikUrun = _teklif?.yillik?.storeProduct;
    // Mağaza fiyatı varsa o (gerçek tahsil edilecek tutar); yoksa RC metni.
    final priceMonthly = aylikUrun != null
        ? l.pwFiyatAylik(aylikUrun.priceString)
        : rc.premiumPriceMonthly;
    final priceYearly = yillikUrun != null
        ? l.pwFiyatYillik(yillikUrun.priceString)
        : rc.premiumPriceYearly;
    final oran = aylikUrun != null && yillikUrun != null
        ? tasarrufOrani(aylikUrun.price, yillikUrun.price)
        : yillikTasarrufOrani(rc.premiumPriceMonthly, rc.premiumPriceYearly);
    final yillikDeneme = yillikUrun == null ? null : denemeGunu(yillikUrun);
    final aylikDeneme = aylikUrun == null ? null : denemeGunu(aylikUrun);
    final seciliDeneme = _selected == _Plan.yearly ? yillikDeneme : aylikDeneme;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    // Kart desteli tasarım (bayrak `paywall_deste`). Satın alma, geri
    // yükleme ve fiyat/deneme okuması bu State'te kalır; yalnız görünüm
    // değişir. Ham fiyat metni verilir, birim eki (/ay, /yıl) gövdede.
    if (rc.paywallDeste) {
      return _DesteGovdesi(
        source: widget.source,
        yillik: _selected == _Plan.yearly,
        onPlan: (y) =>
            setState(() => _selected = y ? _Plan.yearly : _Plan.monthly),
        fiyatYillik:
            yillikUrun?.priceString ?? _birimsiz(rc.premiumPriceYearly),
        fiyatAylik: aylikUrun?.priceString ?? _birimsiz(rc.premiumPriceMonthly),
        aylikKarsiligi: yillikUrun?.pricePerMonthString,
        oran: oran,
        yillikDeneme: yillikDeneme,
        aylikDeneme: aylikDeneme,
        android: android,
        busy: _busy,
        onSatinAl: _satinAl,
        onGeriYukle: _geriYukle,
      );
    }

    return Scaffold(
      backgroundColor: context.c.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 8,
                  SandikSpace.screenH(context), 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  const _Header(),
                  const SizedBox(height: 28),
                  _HeroCard(),
                  const SizedBox(height: 24),
                  _FeatureList(radar: rc.balinaRadariAcik),
                  if (rc.balinaRadariAcik) ...[
                    const SizedBox(height: 8),
                    _KarsilastirmaTablosu(
                      varlikSiniri: rc.freeAssetLimit,
                      takipSiniri: rc.paywallWatchlistLimit,
                      sinyalTekVarlik: rc.freeSignalAssets > 0,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _PlanCard(
                    plan: _Plan.yearly,
                    title: l.planYearly,
                    price: priceYearly,
                    subtitle: yillikDeneme != null
                        ? l.pwDenemeAltyazi(yillikDeneme)
                        : l.pwYenilenirAltyazi,
                    badgeText:
                        oran == null ? null : l.prmYillikTasarruf('$oran'),
                    selected: _selected == _Plan.yearly,
                    onTap: () => setState(() => _selected = _Plan.yearly),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    plan: _Plan.monthly,
                    title: l.planMonthly,
                    price: priceMonthly,
                    subtitle: aylikDeneme != null
                        ? l.pwDenemeAltyazi(aylikDeneme)
                        : l.planMonthlySubtitle,
                    badgeText: null,
                    selected: _selected == _Plan.monthly,
                    onTap: () => setState(() => _selected = _Plan.monthly),
                  ),
                  const SizedBox(height: 20),
                  // Mağaza kuralı (App Store 3.1.2, Play abonelik politikası):
                  // yenileme/iptal bilgisi, varsa deneme koşulu ve Koşullar +
                  // Gizlilik bağlantıları satın alma ekranında görünür olmalı.
                  Text(
                    [
                      android ? l.pwKosulAndroid : l.subscriptionTerms,
                      if (seciliDeneme != null) l.pwDenemeKosul(seciliDeneme),
                    ].join(' '),
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.text36,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: SandikSpace.sm),
                  Wrap(
                    spacing: SandikSpace.md,
                    children: [
                      _BelgeBaglantisi(
                          metin: l.termsOfUse, belge: YasalBelge.kosullar),
                      _BelgeBaglantisi(
                          metin: l.privacyPolicy, belge: YasalBelge.gizlilik),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(
                busy: _busy,
                etiket: seciliDeneme != null
                    ? l.pwDenemeDugme(seciliDeneme)
                    : l.pwAboneOl,
                onSubscribe: _satinAl,
                onRestore: _geriYukle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _satinAl() async {
    if (_busy) return;
    final paket = _seciliPaket;
    if (paket == null) {
      sandikSnack(context, context.l10n.pwKullanilamaz);
      return;
    }
    setState(() => _busy = true);
    try {
      final sonuc = await SatinAlmaService.instance.satinAl(paket);
      if (!mounted) return;
      switch (sonuc) {
        case SatinAlmaSonucu.basarili:
          unawaited(AnalyticsService.instance.logPremiumUpgradeCompleted(
            plan: _selected == _Plan.yearly ? 'yearly' : 'monthly',
          ));
          await _showSuccessSheet();
          if (!mounted) return;
          Navigator.of(context).pop(true);
        case SatinAlmaSonucu.vazgecti:
          break;
        case SatinAlmaSonucu.beklemede:
          sandikSnack(context, context.l10n.pwBeklemede);
        case SatinAlmaSonucu.hata:
          sandikSnack(context, context.l10n.pwHata);
        case SatinAlmaSonucu.kullanilamaz:
          sandikSnack(context, context.l10n.pwKullanilamaz);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _geriYukle() async {
    if (_busy) return;
    if (!SatinAlmaService.instance.yapilandirildi) {
      sandikSnack(context, context.l10n.pwKullanilamaz);
      return;
    }
    setState(() => _busy = true);
    try {
      final bulundu = await SatinAlmaService.instance.geriYukle();
      if (!mounted) return;
      final l = context.l10n;
      sandikSnack(
        context,
        switch (bulundu) {
          true => l.pwGeriYuklendi,
          false => l.pwGeriYukBulunamadi,
          null => l.pwGeriYukHata,
        },
      );
      if (bulundu == true) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSuccessSheet() {
    return showSandikSheet<void>(
      context: context,
      backgroundColor: context.c.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context), 20,
              SandikSpace.screenH(context), 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SandikTutamac(),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.c.amberFill.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.45),
                      width: 2),
                ),
                child: Icon(Icons.check_rounded,
                    color: context.c.amberText, size: 40),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.premiumUnlocked,
                  style: context.t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: context.c.text90)),
              const SizedBox(height: 8),
              Text(
                context.l10n.premiumUnlockedBody,
                textAlign: TextAlign.center,
                style: context.t.bodyMedium
                    ?.copyWith(color: context.c.text58, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.c.amberFill,
                    foregroundColor: context.c.onAmber,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SandikRadius.md)),
                  ),
                  // Renk açıkça `onAmber` — `text90` düğme rengini ezerdi
                  // (açık tema denetimi 2026-10-08).
                  child: Text(context.l10n.greatWord,
                      style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: context.c.onAmber)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.close_rounded, color: context.c.text90),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const Spacer(),
      ],
    );
  }
}

// ── Hero kart ─────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.c.amberFill.withValues(alpha: 0.18),
            context.c.gold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.amberFill.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.c.amberFill.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
              border:
                  Border.all(color: context.c.amberFill.withValues(alpha: 0.5)),
            ),
            child: Text(
              context.l10n.sandikPremiumUpper,
              style: context.t.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: context.c.amberText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10n.paywallHeadline,
            style: context.t.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: context.c.text90,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.paywallSubhead,
            style: context.t.bodyMedium?.copyWith(
              color: context.c.text58,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature listesi ───────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.radar});

  /// Balina Radarı açık mı: radar ayrıntıları ancak o zaman satılır.
  final bool radar;

  // ⚠️ BURAYA YALNIZCA UYGULAMADA GERÇEKTEN KİLİTLİ OLAN ÖZELLİK YAZILIR.
  // Listede olup ücretsizde de açık olan şey "parası alınıp verilmeyen"
  // vaattir; henüz yazılmamış bir özellik App Store 2.3.1 ihlalidir.
  // Kaldırılanlar (yeniden eklemeden ÖNCE kilidi/implementasyonu yaz):
  //   - "Aylık AI portföy raporu" → hiçbir servis/edge function yok
  //   - "Fiyat alarmları"        → yalnızca bu ekranda geçiyordu
  //   - "Yıllık vergi PDF raporu" → yalnızca bu ekranda geçiyordu
  //   - "5 yıl grafik" (2026-10-08)
  //     → Temmuz planından kalmıştı; ücretsizde de açık, kilitli değil.
  // Günde birden fazla sinyal bildirimi, Karşılaştır'da 5 seri ve birden
  // fazla ortak, kapıları yazılınca (2026-10-08, `sinyalSlotSiniriProvider`,
  // `karsilastirmaSeriSiniriProvider`, `ortakSiniriDoluProvider`) listeye girdi.
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final features = <(IconData, String)>[
      (Icons.all_inclusive_rounded, l.pwOzSinirsiz),
      (Icons.trending_up_rounded, l.pwOzGosterge),
      (Icons.notifications_active_outlined, l.pwOzSiklik),
      (Icons.stacked_line_chart_rounded, l.pwOzKarsilastir),
      (Icons.group_outlined, l.pwOzOrtak),
      if (radar) (Icons.radar_rounded, l.pwOzRadar),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in features) ...[
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.c.amberFill.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SandikRadius.sm),
                ),
                child: Icon(f.$1, color: context.c.amberText, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  f.$2,
                  style: context.t.bodyMedium?.copyWith(
                    color: context.c.text90,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ── Ücretsiz / Premium karşılaştırma (S11-B, 2026-10-05) ─────────────────
//
// "Takip ücretsiz, anlam ücretli" ilkesi tek bakışta: her satırda ücretsizde
// ne kaldığı da yazar — kullanıcı neyi kaybettiğini değil neyi kazanacağını
// görür. Satırlar yalnız radar bayrağı açıkken (özellik uygulamada yokken
// listelenmez; bkz. `_FeatureList` uyarısı).
class _KarsilastirmaTablosu extends StatelessWidget {
  const _KarsilastirmaTablosu({
    required this.varlikSiniri,
    required this.takipSiniri,
    required this.sinyalTekVarlik,
  });

  final int varlikSiniri;

  /// Ücretsiz takip listesi (paywall açıkken 3; 2026-10-08).
  final int takipSiniri;

  /// Sinyal bildirimi ücretsizde tek varlıkta mı (`free_signal_assets`).
  final bool sinyalTekVarlik;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    // Aylık rapor satırı metin değil simge: '✓'/'-' karakterleri DM Sans'ta
    // yok, web'de kutu çiziyordu; ekran okuyucu da "Var/Yok" duysun.
    final satirlar = <(String, String?, String?)>[
      (l.prmSatirVarlik, '$varlikSiniri', l.prmSinirsiz),
      (l.prmSatirTakip, '$takipSiniri', l.prmSinirsiz),
      if (sinyalTekVarlik)
        (l.prmSatirSinyal, l.prmSinyalUcretsiz, l.prmSinyalPremium),
      (l.prmSatirAkis, l.prmAkisUcretsiz, l.prmAkisPremium),
      (l.prmSatirHacim, l.prmHacimUcretsiz, l.prmHacimPremium),
      (l.prmSatirNot, l.prmNotUcretsiz, l.prmNotPremium),
      (l.prmSatirAylik, null, null),
      // Ekstreyi yapay zekâyla okutma (0121): yalnız özellik açıkken
      // satır olur — açılmamış bir şey satılmaz.
      if (RemoteConfigService.instance.ekstreAiEsleme)
        (l.prmSatirEkstreAi, null, null),
    ];
    Widget hucre(String? metin, {required bool premium}) {
      if (metin == null) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Icon(premium ? Icons.check_rounded : Icons.remove_rounded,
              size: 18,
              color: premium ? c.amberText : c.text36,
              semanticLabel: premium ? l.prmVarErisim : l.prmYokErisim),
        );
      }
      return Text(metin,
          style: premium
              ? t.bodySmall
                  ?.copyWith(color: c.text90, fontWeight: FontWeight.w700)
              : t.bodySmall?.copyWith(color: c.text58));
    }

    final baslik = t.labelSmall?.copyWith(
        color: c.text58, fontWeight: FontWeight.w800, letterSpacing: 1.0);
    return SandikCard(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.md, vertical: SandikSpace.sm),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.3),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
              child: Text(l.prmUcretsiz.toUpperCase(), style: baslik),
            ),
            Text(l.prmPremium.toUpperCase(),
                style: baslik?.copyWith(color: c.amberText)),
          ]),
          for (final r in satirlar)
            TableRow(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.hairline))),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
                  child: Text(r.$1,
                      style: t.bodyMedium?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w600)),
                ),
                hucre(r.$2, premium: false),
                hucre(r.$3, premium: true),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Plan kartı ────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final String title;
  final String price;
  final String subtitle;
  final String? badgeText;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.badgeText,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SandikBasma(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SandikMotion.stateOf(context),
        curve: SandikMotion.enter,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? context.c.amberFill.withValues(alpha: 0.12)
              : context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
            color: selected ? context.c.amberText : context.c.overlay,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? context.c.amberText : context.c.text36,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.c.amberFill,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: context.c.text90)),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.c.gain.withValues(alpha: 0.20),
                            borderRadius:
                                BorderRadius.circular(SandikRadius.sm),
                          ),
                          child: Text(
                            badgeText!,
                            style: context.t.labelMedium?.copyWith(
                                letterSpacing: 0,
                                fontWeight: FontWeight.w800,
                                color: context.c.gain),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(price,
                style: context.t.numSmall.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.c.gold)),
          ],
        ),
      ),
    );
  }
}

// ── Alt bar (sticky CTA) ──────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool busy;
  final String etiket;
  final Future<void> Function() onSubscribe;
  final Future<void> Function() onRestore;

  /// Desteli paywall geri yüklemeyi başlıkta gösterir; altta tekrar etmez.
  final bool geriYukleGoster;

  const _BottomBar({
    required this.busy,
    required this.etiket,
    required this.onSubscribe,
    required this.onRestore,
    this.geriYukleGoster = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: context.c.background,
        border: Border(
          top: BorderSide(color: context.c.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tek yükleniyor davranışı (2026-10-08): kilit ve gösterge
            // [SandikAsyncButton]'da. `busy` (ekranın `_busy`'si) yalnız
            // satın alma sürerken "Geri yükle"yi kapatmak için kalır.
            SandikAsyncButton(
              height: 56,
              onPressed: onSubscribe,
              mesgul: busy,
              style: FilledButton.styleFrom(
                backgroundColor: context.c.amberFill,
                foregroundColor: context.c.onAmber,
                disabledBackgroundColor:
                    context.c.amberFill.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md)),
              ),
              child: Text(
                etiket,
                // Renk açıkça `onAmber` — `text90` düğme rengini
                // ezerdi (açık tema denetimi 2026-10-08).
                style: context.t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: context.c.onAmber),
              ),
            ),
            if (geriYukleGoster) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : onRestore,
                child: Text(context.l10n.restorePurchase,
                    style: context.t.titleSmall?.copyWith(
                        color: context.c.text58, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Koşullar / Gizlilik bağlantısı ───────────────────────────────────────

class _BelgeBaglantisi extends StatelessWidget {
  const _BelgeBaglantisi({required this.metin, required this.belge});

  final String metin;
  final YasalBelge belge;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => belgeyiAc(context, belge),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 44),
      ),
      child: Text(
        metin,
        style: context.t.bodySmall?.copyWith(
          color: context.c.text58,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
