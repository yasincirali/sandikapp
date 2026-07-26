import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddAssetScreen()));
    if (mounted) ref.read(portfolioProvider.notifier).refreshPrices();
  }

  Future<void> _confirmExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
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
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 84,
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
          ),
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
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? Sandik.amber : Sandik.text36;

    return Expanded(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Expanded(
      child: GestureDetector(
        onTap: _showAddAsset,
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
