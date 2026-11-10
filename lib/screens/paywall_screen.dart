import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../models/asset.dart' show Asset;
import '../models/asset_type.dart';
import '../models/position.dart' show aktifLotlar;
import '../providers/auth_provider.dart' show partnersProvider;
import '../providers/portfolio_provider.dart' show portfolioProvider;
import '../providers/preferences_provider.dart'
    show kKarsilastirmaEnFazla, ortakSiniriDoluProvider;
import '../providers/signal_provider.dart' show activeSignalsProvider;
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/remote_config_service.dart';
import '../widgets/sandik_segment.dart';
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
        settings: const RouteSettings(name: 'paywall'),
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
  /// Satın alma tamamlandı; `dispose`'daki "kapandı" olayı atılmaz.
  bool _satinAlindi = false;

  @override
  void dispose() {
    if (!_satinAlindi) {
      unawaited(AnalyticsService.instance
          .logPremiumPaywallKapandi(source: widget.source));
    }
    super.dispose();
  }

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
    final aylikUrun = _teklif?.aylik?.storeProduct;
    final yillikUrun = _teklif?.yillik?.storeProduct;
    final oran = aylikUrun != null && yillikUrun != null
        ? tasarrufOrani(aylikUrun.price, yillikUrun.price)
        : yillikTasarrufOrani(rc.premiumPriceMonthly, rc.premiumPriceYearly);
    final yillikDeneme = yillikUrun == null ? null : denemeGunu(yillikUrun);
    final aylikDeneme = aylikUrun == null ? null : denemeGunu(aylikUrun);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    // Tek tasarım: kart destesi (yasin 10 Kas, "Deste her yerde"). Önce
    // `paywall_deste` bayrağına bağlıydı; Remote Config değerleri açılışta
    // arka planda geldiği için aynı cihazda ilk açılış eski listeyi, sonraki
    // desteyi gösteriyordu, mağaza ve inceleme ise yalnız listeyi görecekti.
    // Bayrak artık okunmaz; eski liste görünümü silindi. Satın alma, geri
    // yükleme ve fiyat/deneme okuması bu State'te kalır; ham fiyat metni
    // verilir, birim eki (/ay, /yıl) gövdede.
    // Tetikleyicisiz girişte deste kullanıcının işine göre açılır
    // ([paywallPersona]); sayım bugünkü mülkiyet (`aktifLotlar`).
    final lotlar = aktifLotlar(
        ref.watch(portfolioProvider).valueOrNull?.assets ?? const <Asset>[]);
    final persona = paywallPersona(
      fonSayisi: lotlar.where((a) => a.type == AssetType.fon).length,
      hisseSayisi: lotlar.where((a) => a.type == AssetType.hisse).length,
      sinyalVar: ref.watch(activeSignalsProvider).isNotEmpty,
      ortakVar:
          (ref.watch(partnersProvider).valueOrNull ?? const []).isNotEmpty,
    );
    return _DesteGovdesi(
      source: widget.source,
      persona: persona,
      yillik: _selected == _Plan.yearly,
      onPlan: (y) =>
          setState(() => _selected = y ? _Plan.yearly : _Plan.monthly),
      fiyatYillik: yillikUrun?.priceString ?? _birimsiz(rc.premiumPriceYearly),
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
            source: widget.source,
            deneme: denemeGunu(paket.storeProduct) != null,
          ));
          _satinAlindi = true;
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
                      fontWeight: FontWeight.w600, color: context.c.text90)),
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
                          fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600, color: context.c.onAmber),
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
