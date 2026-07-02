import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/sandik.dart';

/// Yeni kullanıcılara gösterilen 3-adım tutorial.
/// Tamamlanınca veya atlanırsa SharedPreferences'taki [doneKey] true set edilir;
/// bir daha gösterilmez.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String userId;

  const OnboardingScreen({super.key, required this.onComplete, required this.userId});

  static String _key(String userId) => 'onboarding_done_v1_$userId';

  /// Bu kullanıcı daha önce onboarding'i tamamladı mı?
  static Future<bool> isCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(userId)) ?? false;
    } catch (_) {
      // SharedPreferences hata verirse atla — onboarding bir kez fazla
      // gösterilebilir ama akışı bloklamaz
      return true;
    }
  }

  static Future<void> markCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(userId), true);
    } catch (_) {}
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.add_circle_outline_rounded,
      title: 'Varlık Ekle',
      body:
          'Hisse, fon, döviz ve altın varlıklarını tek bir yerden ekle. '
          'Fiyatlar otomatik güncellenir; manuel fiyat da girebilirsin.',
    ),
    _OnboardingPageData(
      icon: Icons.show_chart_rounded,
      title: 'Performansını İzle',
      body:
          'Toplam değerin, kâr/zararın ve dağılımın grafik olarak '
          'görüntülenir. Geçmiş performansını günlük olarak takip et.',
    ),
    _OnboardingPageData(
      icon: Icons.people_outline_rounded,
      title: 'Ortakla Paylaş',
      body:
          'Eşin, ailen veya iş ortağınla portföyünü güvenli paylaş. '
          'İstersen istediğin zaman ortaklığı sonlandır.',
    ),
  ];

  bool get _isLastPage => _index == _pages.length - 1;

  Future<void> _finish() async {
    await OnboardingScreen.markCompleted(widget.userId);
    if (!mounted) return;
    widget.onComplete();
  }

  void _next() {
    if (_isLastPage) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sandik.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip butonu
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: _finish,
                  child: Text(
                    'Atla',
                    style: GoogleFonts.dmSans(
                      color: Sandik.text58,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _OnboardingPage(data: _pages[i]),
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Sandik.amber : Sandik.text36,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // İleri / Başla butonu
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: _next,
                  padding: EdgeInsets.zero,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Sandik.amber.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Sandik.amber.withValues(alpha: 0.60),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Sandik.amber.withValues(alpha: 0.28),
                          blurRadius: 18,
                          spreadRadius: -4,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _isLastPage ? 'Sandığımı Aç' : 'İleri',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Sandik.dark,
                      ),
                    ),
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

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Sandik.amber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Sandik.amber.withValues(alpha: 0.35)),
            ),
            child: Icon(data.icon, size: 56, color: Sandik.amber),
          ),
          const SizedBox(height: 36),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Sandik.text90,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: Sandik.text58,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
