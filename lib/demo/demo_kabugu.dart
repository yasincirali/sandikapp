import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../screens/home_screen.dart';
import '../screens/main_navigation_screen.dart' show MainNavigationScreen;
import '../screens/portfolio_performance_screen.dart';
import '../screens/portfolio_screen.dart';
import '../screens/register_screen.dart';
import '../services/analytics_service.dart';
import '../services/crash_reporter.dart';
import '../services/daily_summary.dart' show IntradaySeriesCache;
import '../services/tazelik_ritmi.dart';
import '../theme/sandik.dart';
import 'demo_modu.dart';
import 'demo_saglayicilar.dart';

/// Demo kabuğu nasıl kapandı — giriş ekranı buna göre davranır.
enum DemoCikisi {
  /// "Hesap oluştur" — giriş ekranı kayıt ekranını açar.
  hesapOlustur,

  /// "Zaten hesabım var" — giriş ekranında kalınır.
  girisYap,
}

/// Giriş ekranındaki "Önce bir göz at" düğmesinin işi — tek giriş noktası.
///
/// Kabuk kayıtla kapanırsa kayıt ekranı GİRİŞ ekranının üstüne açılır:
/// kullanıcı kayıttan vazgeçerse giriş ekranına döner, demoya değil. Demo
/// bellekte yaşar; kapanınca biter (yeniden açılış taze başlar).
Future<void> demoyuAc(BuildContext context) async {
  unawaited(AnalyticsService.instance.logDemoOpened());
  final cikis = await pushGuarded<DemoCikisi>(
    context,
    adaptiveRoute<DemoCikisi>(
      builder: (_) => const DemoKabugu(),
      fullscreenDialog: true,
    ),
  );
  if (cikis != DemoCikisi.hesapOlustur || !context.mounted) return;
  // `pushGuarded` DEĞİL: bu bir dokunuş değil, kabuğun kapanışının devamı.
  // Çift dokunma penceresi (350 ms) son itmeyi — demonun kendisini — sayar;
  // kabukta hızla "Hesap oluştur"a basan kullanıcıda kayıt ekranı sessizce
  // açılmazdı.
  await Navigator.of(context).push<void>(
    adaptiveRoute<void>(builder: (_) => const RegisterScreen()),
  );
}

/// "Örnek portföyle dene" (F1) — hesapsız, sunucusuz vitrin.
///
/// ## Yapı (ADR-1)
/// - **Kendi `ProviderContainer`'ı (ebeveynsiz).** Gerekçe
///   `demoOverrides`'ın notunda: türev sağlayıcılar kök kapsamda kurulup
///   oturumsuz kökü görürdü. Container kabukla doğar, kabukla ölür —
///   demo verisi gerçek oturumun hiçbir sağlayıcısına sızamaz; kökteki
///   dinleyiciler (`_AuthGate`: ana ekran widget'ı, Live Activity,
///   kilometre taşı, push izni, tanıtım turu, yenilikler) demo defterini
///   HİÇ görmez, çünkü başka bir container'ı dinliyorlar.
/// - **Kendi `Navigator`'ı.** Varlık ekranı gibi itilen sayfalar demo
///   kapsamının İÇİNDE kalmalı; kök navigator'a itilen sayfa kök
///   container'ı okurdu. Üstteki "Örnek portföy" şeridi de böylece her
///   sayfada görünür kalır.
/// - **Mevcut ekranlar olduğu gibi.** Ana / Portföy / Performans gerçek
///   widget'lar; demo yalnızca veriyi ve yan etkileri değiştirir.
class DemoKabugu extends StatefulWidget {
  const DemoKabugu({super.key, this.ekOverrides = const []});

  /// Testin demo sağlayıcılarının ÜSTÜNE koyduğu değişiklikler.
  @visibleForTesting
  final List<Override> ekOverrides;

  @override
  State<DemoKabugu> createState() => _DemoKabuguState();
}

class _DemoKabuguState extends State<DemoKabugu> {
  late final ProviderContainer _container;
  final _navKey = GlobalKey<NavigatorState>();
  final _sekmelerKey = GlobalKey<_DemoSekmeleriState>();

  VoidCallback? _yazmaBagi;
  VoidCallback? _fiyatTuruBagi;
  ProviderSubscription<AsyncValue<AppUser?>>? _kokOturum;
  bool _sayfaAcik = false;
  bool _kapaniyor = false;

  @override
  void initState() {
    super.initState();
    // Bayrak container'dan ÖNCE: ilk kare kurulurken servis kapıları
    // (`InflationService`, tercih yazımı…) demoyu zaten görmeli.
    DemoModu.ac();
    _container = ProviderContainer(
      overrides: [...demoOverrides(), ...widget.ekOverrides],
    );
    _yazmaBagi = DemoModu.yazmaDinleyicisiniBagla(_yazmaGirisimi);

    // Nabzın fiyat turu — gerçek uygulamada `MainNavigationScreen` bağlar;
    // demo açıkken o ekran ağaçta yok (giriş ekranındayız), bağ boştur.
    // Tur demo defterini tazeler; sunucuya yazmaz (bkz.
    // `DemoPortfolioNotifier.refreshPrices`).
    _fiyatTuruBagi = TazelikRitmi.nabiz.fiyatTuruBagla(() async {
      if (!mounted) return;
      await _container
          .read(portfolioProvider.notifier)
          .refreshPrices(nabiz: true);
    });

    // Mevcut ekranlar sekme değiştirmek için bu statik kanala yazıyor
    // (ör. ana ekrandaki bir bildirim "Portföy sekmesine geç"). Demo
    // açıkken `MainNavigationScreen` yok; istek tüketilmezse kanalda kalır
    // ve kullanıcı gerçek hesapla girdiğinde ESKİ istek uygulanırdı.
    MainNavigationScreen.sekmeIstegi.addListener(_sekmeIstegi);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Demo açıkken gerçek bir oturum doğarsa (ör. e-postadaki bağlantı ile
    // giriş) demo kapanır: kökteki uygulama o kullanıcıyla çalışmaya
    // başlar ve demonun sunucu kapısı onun isteklerini de düşürürdü.
    if (_kokOturum != null) return;
    final ProviderContainer kok;
    try {
      kok = ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return; // Kök kapsam yok (izole test) — izlenecek oturum da yok.
    }
    _kokOturum = kok.listen<AsyncValue<AppUser?>>(authProvider, (_, next) {
      if (next.valueOrNull != null) _kapat(DemoCikisi.girisYap);
    });
  }

  @override
  void dispose() {
    MainNavigationScreen.sekmeIstegi.removeListener(_sekmeIstegi);
    _kokOturum?.close();
    _yazmaBagi?.call();
    _fiyatTuruBagi?.call();
    _container.dispose();
    // Gün içi seri önbelleği süreç boyu yaşayan bir singleton; demo
    // defterinin serisi sahip damgasıyla ayrılıyor ama gerçek oturum
    // açılmadan düşürmek en temizi (çıkışta da aynısı yapılır).
    IntradaySeriesCache.instance.clear();
    DemoModu.kapat();
    super.dispose();
  }

  void _sekmeIstegi() {
    final hedef = MainNavigationScreen.sekmeIstegi.value;
    if (hedef == null) return;
    MainNavigationScreen.sekmeIstegi.value = null;
    switch (hedef) {
      case 0 || 1:
        _sekmelerKey.currentState?.sekmeyeGec(hedef);
      case MainNavigationScreen.performansSekmesi:
        _sekmelerKey.currentState?.sekmeyeGec(_DemoSekmeleriState.performans);
      case 2:
        DemoModu.yazmaKapisi('varlik_ekle');
      default:
        _sekmelerKey.currentState?.sekmeyeGec(_DemoSekmeleriState.hesap);
    }
  }

  /// Yazma girişimi → "Kaydetmek için hesap oluştur" sayfası.
  void _yazmaGirisimi(String neden) {
    if (_sayfaAcik || _kapaniyor || !mounted) return;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    _sayfaAcik = true;
    CrashReporter.arkaPlan(
      showModalBottomSheet<bool>(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const _KayitSayfasi(),
      ).then<void>((hesap) {
        _sayfaAcik = false;
        if (hesap == true) _hesapOlustur(neden);
      }),
      reason: 'DemoKabugu.yazmaGirisimi',
    );
  }

  void _hesapOlustur(String kaynak) {
    unawaited(AnalyticsService.instance.logDemoConverted(from: kaynak));
    _kapat(DemoCikisi.hesapOlustur);
  }

  void _kapat(DemoCikisi cikis) {
    if (_kapaniyor || !mounted) return;
    _kapaniyor = true;
    Navigator.of(context).pop(cikis);
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: Scaffold(
        backgroundColor: context.c.background,
        body: Column(
          children: [
            _OrnekSeridi(
              onHesapOlustur: () => _hesapOlustur('serit'),
              onKapat: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              // Şerit durum çubuğu boşluğunu zaten aldı; alttaki ekranlar
              // kendi `SafeArea`'larıyla ikinci kez almasın.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: NavigatorPopHandler(
                  onPopWithResult: (_) => _navKey.currentState?.maybePop(),
                  child: Navigator(
                    key: _navKey,
                    onGenerateInitialRoutes: (_, __) => [
                      adaptiveRoute<void>(
                        builder: (_) => _DemoSekmeleri(
                          key: _sekmelerKey,
                          onHesapOlustur: () => _hesapOlustur('sekme'),
                          onGirisYap: () => _kapat(DemoCikisi.girisYap),
                        ),
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
  }
}

/// Her sayfanın üstündeki kalıcı şerit: burası örnek, çıkış ve hesap.
class _OrnekSeridi extends StatelessWidget {
  const _OrnekSeridi({required this.onHesapOlustur, required this.onKapat});

  final VoidCallback onHesapOlustur;
  final VoidCallback onKapat;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    return Material(
      color: c.surface2,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.xs, SandikSpace.xs, SandikSpace.md, SandikSpace.xs),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.demoExit,
                onPressed: onKapat,
                icon: Icon(Icons.close_rounded, color: c.text58),
              ),
              const SizedBox(width: SandikSpace.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.demoBannerTitle,
                      style: context.t.titleSmall?.copyWith(
                        color: c.amberText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      l10n.demoBannerSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SandikSpace.sm),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.amberFill,
                  foregroundColor: c.onAmber,
                  minimumSize: SandikTouch.minSize,
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.md),
                ),
                onPressed: onHesapOlustur,
                child: Text(l10n.demoCreateAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ana / Portföy / Performans + "Hesap oluştur" sekmesi.
///
/// `MainNavigationScreen` KULLANILMAZ: o ekran açılışta fiyat turunu,
/// bildirim izni istemini (`NotificationService.requestPermission`) ve
/// varlık ekleme düğmesini taşıyor; üçü de demoda olmaması gereken şeyler.
/// Sekme davranışı onunla aynı: ekranlar ağaçta kalır (durum korunur),
/// hiç açılmamış sekme kurulmaz, geçiş anlıktır.
class _DemoSekmeleri extends StatefulWidget {
  const _DemoSekmeleri({
    super.key,
    required this.onHesapOlustur,
    required this.onGirisYap,
  });

  final VoidCallback onHesapOlustur;
  final VoidCallback onGirisYap;

  @override
  State<_DemoSekmeleri> createState() => _DemoSekmeleriState();
}

class _DemoSekmeleriState extends State<_DemoSekmeleri> {
  static const performans = 2;
  static const hesap = 3;

  int _index = 0;
  final Set<int> _gorulen = {0};

  void sekmeyeGec(int i) {
    if (i == _index) return;
    SandikHaptic.selection.perform();
    setState(() {
      _index = i;
      _gorulen.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sayfalar = <Widget>[
      const HomeScreen(),
      const PortfolioScreen(),
      const PortfolioPerformanceScreen(),
      _HesapSekmesi(
        onHesapOlustur: widget.onHesapOlustur,
        onGirisYap: widget.onGirisYap,
      ),
    ];
    return Scaffold(
      backgroundColor: context.c.background,
      body: Stack(
        children: [
          for (var i = 0; i < sayfalar.length; i++)
            if (_gorulen.contains(i))
              Offstage(
                offstage: i != _index,
                child: TickerMode(
                  enabled: i == _index,
                  child: ExcludeSemantics(
                    excluding: i != _index,
                    child: sayfalar[i],
                  ),
                ),
              ),
        ],
      ),
      bottomNavigationBar: _altMenu(context),
    );
  }

  Widget _altMenu(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
          bottom: bottomInset > 0 ? bottomInset : SandikSpace.smd),
      decoration: BoxDecoration(
        color: context.c.overlay,
        border: Border(top: BorderSide(color: context.c.hairline)),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _oge(0, Icons.home_rounded, l10n.tabHome),
            _oge(1, Icons.donut_large_rounded, l10n.tabPortfolio),
            _oge(performans, Icons.show_chart_rounded, l10n.tabPerformance),
            _oge(hesap, Icons.person_add_alt_1_rounded, l10n.demoCreateAccount,
                vurgulu: true),
          ],
        ),
      ),
    );
  }

  Widget _oge(int i, IconData ikon, String etiket, {bool vurgulu = false}) {
    final secili = i == _index;
    final renk = secili || vurgulu ? context.c.amberText : context.c.text36;
    return Expanded(
      child: Semantics(
        button: true,
        selected: secili,
        label: etiket,
        child: GestureDetector(
          key: ValueKey('demo-sekme-$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => sekmeyeGec(i),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ikon, color: renk, size: 26),
                const SizedBox(height: SandikSpace.xs),
                Text(
                  etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelMedium!.copyWith(
                    letterSpacing: 0,
                    fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                    color: renk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profil sekmesinin yerindeki kart: demo burada biter, hesap başlar.
class _HesapSekmesi extends StatelessWidget {
  const _HesapSekmesi({required this.onHesapOlustur, required this.onGirisYap});

  final VoidCallback onHesapOlustur;
  final VoidCallback onGirisYap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SandikSpace.lg),
          child: SandikCard(
            elevated: true,
            padding: const EdgeInsets.all(SandikSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1_rounded,
                    size: 40, color: c.amberText),
                const SizedBox(height: SandikSpace.md),
                Text(
                  l10n.demoAccountCardTitle,
                  style: context.t.headlineSmall?.copyWith(color: c.text90),
                ),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  l10n.demoAccountCardBody,
                  style: context.t.bodyLarge?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.lg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.amberFill,
                    foregroundColor: c.onAmber,
                    minimumSize: SandikTouch.minSize,
                    padding:
                        const EdgeInsets.symmetric(vertical: SandikSpace.md2),
                  ),
                  onPressed: onHesapOlustur,
                  child: Text(l10n.demoCreateAccount),
                ),
                const SizedBox(height: SandikSpace.sm),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: c.amberText,
                    minimumSize: SandikTouch.minSize,
                  ),
                  onPressed: onGirisYap,
                  child: Text(l10n.demoAccountCardSignIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yazma girişiminde açılan sayfa. `true` = hesap oluştur.
class _KayitSayfasi extends StatelessWidget {
  const _KayitSayfasi();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      padding: EdgeInsets.fromLTRB(
        SandikSpace.lg,
        SandikSpace.smd,
        SandikSpace.lg,
        SandikSpace.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text20,
                borderRadius: BorderRadius.circular(SandikSpace.xxs),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.lgs),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 22, color: c.amberText),
              const SizedBox(width: SandikSpace.sm2),
              Expanded(
                child: Text(
                  l10n.demoSaveSheetTitle,
                  style: context.t.headlineSmall?.copyWith(color: c.text90),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            l10n.demoSaveSheetBody,
            style: context.t.bodyLarge?.copyWith(color: c.text58),
          ),
          const SizedBox(height: SandikSpace.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.amberFill,
              foregroundColor: c.onAmber,
              minimumSize: SandikTouch.minSize,
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.md2),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.demoCreateAccount),
          ),
          const SizedBox(height: SandikSpace.sm),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: c.text58,
              minimumSize: SandikTouch.minSize,
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.demoSaveSheetContinue),
          ),
        ],
      ),
    );
  }
}
