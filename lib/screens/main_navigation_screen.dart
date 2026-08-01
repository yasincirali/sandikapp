import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/sandik.dart';
import 'home_screen.dart';
import 'charts_screen.dart';
import 'portfolio_performance_screen.dart';
import 'profile_screen.dart';
import 'add_asset_screen.dart';
import '../providers/portfolio_provider.dart';
import '../services/notification_service.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // İlk açılışta fiyatları yükle
    Future.microtask(() {
      if (mounted) ref.read(portfolioProvider.notifier).refreshPrices();
    });
    // UE1: Bildirim iznini onboarding sonrasına ertele — uygulama açılır açılmaz değil
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) NotificationService.instance.requestPermission();
    });
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const ChartsScreen(),
    const SizedBox.shrink(),
    const PortfolioPerformanceScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == 2) {
      _showAddAsset();
      return;
    }
    if (index == 0 && _currentIndex != 0) {
      ref.read(portfolioProvider.notifier).refreshPrices();
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _showAddAsset() async {
    // fullscreenDialog: iOS'ta alttan-yukarı modal geçiş + "kapat" semantiği —
    // varlık ekleme bir görev akışı, hiyerarşik gezinme değil.
    // pushGuarded: FAB'a hızlı iki dokunuş iki AddAssetScreen açmasın.
    await pushGuarded(
      context,
      adaptiveRoute(
        builder: (_) => const AddAssetScreen(),
        fullscreenDialog: true,
      ),
    );
    if (mounted) ref.read(portfolioProvider.notifier).refreshPrices();
  }

  Future<void> _confirmExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ClipRRect(
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.lg),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            title: const Text('Uygulamadan Çık', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Uygulamadan çıkmak istiyor musunuz?',
              style: TextStyle(color: Sandik.text58),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç', style: TextStyle(color: Sandik.text36)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Sandik.loss),
                child: const Text('Çık'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm == true) {
      // Uygulamayı kapat
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop();
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
        backgroundColor: Sandik.background,
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
          ),
          child: SizedBox(
            // 60pt içerik — her sekme 44pt HIG minimumunun üzerinde kalır
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.home_rounded, 'Ana'),
                _navItem(1, Icons.donut_large_rounded, 'Portföy'),
                _buildFab(),
                _navItem(3, Icons.show_chart_rounded, 'Performans'),
                _navItem(4, Icons.person_rounded, 'Profil'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? Sandik.amber : Sandik.text36;

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
                duration: const Duration(milliseconds: 200),
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
    );
  }

  Widget _buildFab() {
    return Expanded(
      child: SandikTappable(
        onTap: _showAddAsset,
        // Ana eylem — basılınca biraz daha belirgin küçülsün.
        scale: 0.92,
        semanticLabel: 'Varlık ekle',
        child: Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Sandik.amber,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Sandik.amber.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Sandik.dark, size: 36),
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
