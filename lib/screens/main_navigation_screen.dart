import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/tour_anchor.dart';
import 'home_screen.dart';
import 'portfolio_screen.dart';
import 'portfolio_performance_screen.dart';
import 'profile_screen.dart';
import 'add_asset_screen.dart';
import '../providers/portfolio_provider.dart';
import '../services/notification_service.dart';
import '../services/remote_config_service.dart';
import '../l10n/l10n.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  /// Performans sekmesinin indeksi — [_screens] sırasına bağlı.
  ///
  /// Widget ve Canlı Etkinlik dokunuşu buraya gider (bkz.
  /// `DeepLinkService`). Sabit dışarıdan okunabilir olmalı: hedefi çağıran
  /// tarafta elle `3` yazmak, `_screens` sırası değiştiğinde SESSİZCE
  /// yanlış sekmeye götürürdü.
  ///
  /// Alt menüdeki "Portföy" sekmesi `PortfolioScreen`'dir (indeks 1);
  /// "Performans" sekmesi `PortfolioPerformanceScreen` indeks 3'tedir.
  static const performansSekmesi = 3;

  /// Dışarıdan sekme değiştirme kanalı.
  ///
  /// Neden `ValueNotifier`: dokunuş uygulama AÇIKKEN de gelebilir (sıcak
  /// açılış). O durumda yeni bir ekran push etmek yanlış olur — kullanıcı
  /// zaten uygulamadadır, yalnızca sekme değişmelidir. Provider yerine
  /// bunu seçmenin sebebi, kaynağın (native dokunuş) Riverpod kapsamı
  /// DIŞINDA olması.
  static final sekmeIstegi = ValueNotifier<int?>(null);

  /// Şu an açık olan sekme — dışarıdan OKUNUR (yazılmaz).
  ///
  /// Tanıtım turu "Portföy sekmesine dokun" görevinin yapıldığını buradan
  /// anlar. Provider yerine `ValueNotifier`: tur kök `Overlay`'de yaşar ve
  /// bu ekranın state'ine erişemez; [sekmeIstegi] ile aynı kanal.
  static final aktifSekme = ValueNotifier<int>(0);

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    // Widget / Canlı Etkinlik dokunuşundan gelen sekme isteği.
    //
    // Soğuk açılışta istek bu ekran KURULMADAN önce yazılmış olabilir;
    // o yüzden dinleyiciyi bağlamakla yetinmeyip mevcut değeri de bir kez
    // okuyoruz. Yalnızca dinleseydik, uygulama kapalıyken yapılan dokunuş
    // sessizce kaybolurdu.
    MainNavigationScreen.sekmeIstegi.addListener(_sekmeIstegiGeldi);
    if (MainNavigationScreen.sekmeIstegi.value != null) {
      Future.microtask(_sekmeIstegiGeldi);
    }

    // İlk açılışta fiyatları yükle
    Future.microtask(() {
      if (mounted) ref.read(portfolioProvider.notifier).refreshPrices();
    });
    // UE1: Bildirim iznini onboarding sonrasına ertele — uygulama açılır açılmaz değil
    //
    // `push_prompt_after_first_asset` açıkken bu kol DEVRE DIŞI: izin o zaman
    // ilk varlık eklendikten sonra, bağlamıyla birlikte isteniyor
    // (bkz. main.dart portföy dinleyicisi). İki kol aynı anda çalışırsa
    // kullanıcı izni burada reddeder ve bağlamlı istem hiç gösterilemez —
    // Android izni ikinci kez sormaz.
    if (!RemoteConfigService.instance.pushPromptAfterFirstAsset) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          NotificationService.instance
              .requestPermission(promptContext: 'post_onboarding_delay');
        }
      });
    }
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const PortfolioScreen(),
    const SizedBox.shrink(),
    const PortfolioPerformanceScreen(),
    const ProfileScreen(),
  ];

  @override
  void dispose() {
    // Dinleyici statik bir `ValueNotifier`'a bağlı: kaldırılmazsa ekran
    // yeniden kurulduğunda (tema/dil değişimi, hot restart) üst üste
    // birikir ve tek dokunuş birden çok kez işlenir.
    MainNavigationScreen.sekmeIstegi.removeListener(_sekmeIstegiGeldi);
    super.dispose();
  }

  /// Dışarıdan gelen sekme isteğini uygular.
  ///
  /// İstek TÜKETİLİR (`value = null`): aksi halde ekran her yeniden
  /// kurulduğunda eski dokunuş yeniden uygulanır ve kullanıcı başka bir
  /// sekmeye geçmeye çalışırken geri fırlatılır.
  void _sekmeIstegiGeldi() {
    final hedef = MainNavigationScreen.sekmeIstegi.value;
    if (hedef == null) return;
    MainNavigationScreen.sekmeIstegi.value = null;

    // Aralık dışı değer gelirse yoksay — native taraf yanlış indeks
    // gönderirse uygulama çökmemeli.
    if (hedef < 0 || hedef >= _screens.length) return;
    if (!mounted) return;
    // Orta tuşun sekmesi yok; istek "Varlık Ekle'yi aç" demektir (tanıtım
    // turu "Devam" ile geçildiğinde kullanır).
    if (hedef == 2) {
      _showAddAsset();
      return;
    }
    _sekmeyeGec(hedef);
  }

  void _sekmeyeGec(int i) {
    setState(() => _currentIndex = i);
    MainNavigationScreen.aktifSekme.value = i;
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      // FAB kendi haptic'ini SandikTappable üzerinden verir; burada tekrar
      // tetiklenirse çift titreşim olur.
      _showAddAsset();
      return;
    }
    // Yalnızca sekme gerçekten değişince: aynı sekmeye tekrar dokunmak bir
    // durum değişimi değildir, geri bildirim de vermemeli.
    if (index != _currentIndex) {
      SandikHaptic.selection.perform();
    }
    if (index == 0 && _currentIndex != 0) {
      ref.read(portfolioProvider.notifier).refreshPrices();
    }
    _sekmeyeGec(index);
  }

  /// Portföy sekmesinin indeksi (`_screens` sırasına bağlı).
  static const _portfolioTab = 1;

  Future<void> _showAddAsset() async {
    // fullscreenDialog: iOS'ta alttan-yukarı modal geçiş + "kapat" semantiği —
    // varlık ekleme bir görev akışı, hiyerarşik gezinme değil.
    // pushGuarded: FAB'a hızlı iki dokunuş iki AddAssetScreen açmasın.
    final added = await pushGuarded<bool>(
      context,
      adaptiveRoute(
        builder: (_) => const AddAssetScreen(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;

    // Kayıt başarılıysa Portföy sekmesine geç. Eskiden hiçbir akış sekme
    // değiştirmiyordu; kullanıcı hangi sekmedeyse oraya dönüyordu. Ana
    // sekmedeyken FAB'dan varlık eklemek (tekli ya da toplu) kullanıcıyı
    // Ana'da bırakıyor, eklenen varlık görünmüyordu.
    //
    // Tekli eklemede sorun fark edilmiyordu çünkü kullanıcı çoğunlukla
    // zaten Portföy'de olup FAB'a basıyor. Toplu eklemeye ise Portföy'den
    // girilse bile araya AddAssetScreen giriyor ve akış uzuyor.
    if (added == true) {
      setState(() => _currentIndex = _portfolioTab);
      MainNavigationScreen.aktifSekme.value = _portfolioTab;
    }
    unawaited(ref.read(portfolioProvider.notifier).refreshPrices());
  }

  Future<void> _confirmExit() async {
    final confirm = await showSandikConfirm(
      context: context,
      title: context.l10n.exitAppTitle,
      message: context.l10n.exitAppMessage,
      confirmLabel: context.l10n.exit,
      destructive: true,
    );
    if (confirm) {
      SandikHaptic.heavy.perform();
      // Uygulamayı kapat. `Navigator.of(context).pop()` DEĞİL: kök
      // navigator'da tek route varken pop hiçbir şey yapmıyordu — kullanıcı
      // "Çık"a basıyor, uygulama açık kalıyordu. SystemNavigator.pop()
      // Android'de aktiviteyi kapatır; iOS'ta HIG gereği no-op'tur (iOS'ta
      // zaten sistem geri tuşu olmadığından bu diyalog açılmaz).
      unawaited(SystemNavigator.pop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: context.c.background,
        body: _AnimatedIndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    // iOS Home Indicator / Android gesture bar yüksekliği cihaza göre değişir
    // (iPhone X+ ≈ 34pt, indicator'sız cihazlarda 0). Sabit height yerine
    // içerik yüksekliği + viewPadding.bottom kullanılır; aksi halde bar
    // Dynamic Island'lı cihazlarda indicator'ın altında kalıyordu.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return TourAnchor(
      target: TourTarget.altMenu,
      child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 12),
          decoration: BoxDecoration(
            color: context.c.overlay,
            border: Border(
              top: BorderSide(color: context.c.hairline, width: 1),
            ),
          ),
          child: SizedBox(
            // 60pt içerik — her sekme 44pt HIG minimumunun üzerinde kalır
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.home_rounded, context.l10n.tabHome),
                _navItem(1, Icons.donut_large_rounded, context.l10n.tabPortfolio),
                _buildFab(),
                _navItem(3, Icons.show_chart_rounded, context.l10n.tabPerformance),
                _navItem(4, Icons.person_rounded, context.l10n.tabProfile),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? context.c.amberText : context.c.text36;

    // InkWell yerine opaque GestureDetector: iOS'ta Material ripple dalgası
    // yabancı duruyor. HitTestBehavior.opaque, Column'un boş kalan alanının
    // da dokunmayı yakalamasını sağlar (tam 60pt yükseklikte hedef).
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        child: Semantics(
          button: true,
          selected: isSelected,
          label: label,
          child: TourAnchor(
            target: const [
              TourTarget.sekmeAna,
              TourTarget.sekmePortfoy,
              TourTarget.sekmeEkle,
              TourTarget.sekmePerformans,
              TourTarget.sekmeProfil,
            ][index],
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Aktif sekme ikonu hafifçe büyür — hangi sekmede olduğun
              // rengin yanı sıra boyutla da okunur.
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: SandikSpace.xs),
              AnimatedDefaultTextStyle(
                duration: SandikMotion.state,
                curve: SandikMotion.enter,
                style: context.t.labelMedium!.copyWith(
                  letterSpacing: 0,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(label),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Expanded(
      child: SandikTappable(
        onTap: _showAddAsset,
        // Ana eylem — basılınca biraz daha belirgin küçülsün.
        scale: 0.92,
        // Uygulamanın birincil eylemi: seçim tıkırtısından daha belirgin.
        haptic: SandikHaptic.medium,
        semanticLabel: context.l10n.addAsset,
        child: Center(
          child: TourAnchor(
            target: TourTarget.sekmeEkle,
            child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.c.amberFill,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.c.amberFill.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.add_rounded, color: context.c.onAmber, size: 36),
          ),
          ),
        ),
      ),
    );
  }
}

/// Sekme değişiminde çapraz sönümleme yapan [IndexedStack].
///
/// Neden düz `AnimatedSwitcher` değil: AnimatedSwitcher eski çocuğu ağaçtan
/// söker, bu da her sekme dönüşünde ekranların baştan kurulmasına (scroll
/// pozisyonu sıfırlanması, provider'ların yeniden tetiklenmesi) yol açardı.
/// Burada tüm ekranlar `IndexedStack` gibi ağaçta kalır — yalnızca opaklık
/// animasyonlanır. State koruması aynen sürer.
///
/// Görsel davranış: giden sekme sönerken gelen sekme belirir; ikisi de
/// çizilirken üstteki (gelen) tıklamaları alır, alttaki `IgnorePointer`
/// altındadır — geçiş sırasında yanlış sekmeye dokunma olmaz.
class _AnimatedIndexedStack extends StatefulWidget {
  const _AnimatedIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<_AnimatedIndexedStack> {
  static const _duration = Duration(milliseconds: 260);

  /// Henüz hiç görüntülenmemiş sekmeler inşa edilmez — ilk açılışta beş
  /// ekranın birden kurulması gecikme yaratırdı. IndexedStack'in kendi
  /// davranışı da budur (lazy değil ama görünmeyen çocuk layout almaz),
  /// burada açıkça yönetiyoruz.
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(covariant _AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visited.contains(widget.index)) {
      _visited.add(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Erişilebilirlik: "hareketi azalt" açıkken anında geçiş.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Stack(
      children: List.generate(widget.children.length, (i) {
        final isActive = i == widget.index;

        // Hiç ziyaret edilmemiş sekmeyi inşa etme.
        if (!_visited.contains(i)) {
          return const SizedBox.shrink();
        }

        return AnimatedOpacity(
          opacity: isActive ? 1 : 0,
          duration: reduceMotion ? Duration.zero : _duration,
          curve: Curves.easeOut,
          child: IgnorePointer(
            ignoring: !isActive,
            // Pasif sekmeler ağaçta kalır (state korunur) ama ne çizim
            // maliyeti üretir ne de erişilebilirlik ağacını kirletir.
            child: TickerMode(
              enabled: isActive,
              child: ExcludeSemantics(
                excluding: !isActive,
                child: widget.children[i],
              ),
            ),
          ),
        );
      }),
    );
  }
}
