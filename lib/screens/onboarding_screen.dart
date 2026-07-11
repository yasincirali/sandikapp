import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';

/// Yeni kullanıcılara gösterilen interaktif demo.
/// Her adım gerçek uygulama üzerinde bir spotlight + açıklama balonu gösterir.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String userId;

  const OnboardingScreen({super.key, required this.onComplete, required this.userId});

  /// Onboarding'in tamamlanıp tamamlanmadığını Supabase profil'inden okur.
  /// Böylece kullanıcı uygulamayı silip yeniden yüklese bile durum kaybolmaz.
  /// Sorgu başarısız olursa "gösterildi" say (agresif yeniden-göstermeyi önle).
  static Future<bool> isCompleted(String userId) async {
    try {
      final profile = await SupabaseService.instance.getProfile(userId);
      return profile?.onboardingCompleted ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markCompleted(String userId) async {
    try {
      await SupabaseService.instance.markOnboardingCompleted(userId);
    } catch (_) {}
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _anim;
  late Animation<double> _fade;

  static const _steps = [
    _DemoStep(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Portföyünüze hoş geldiniz',
      body: 'Sandık; hisse, fon, döviz ve altın varlıklarınızı tek ekranda toplar. '
          'Fiyatlar otomatik güncellenir.',
      align: _BalloonAlign.center,
    ),
    _DemoStep(
      icon: Icons.add_circle_rounded,
      title: 'Varlık ekleyin',
      body: 'Sağ alttaki + butonuna dokunarak yeni varlık ekleyebilirsiniz. '
          'Mikrofon ikonuyla "100 dolar" veya "10 gram altın" yazarak hızlı toplu giriş de yapabilirsiniz.',
      align: _BalloonAlign.bottom,
    ),
    _DemoStep(
      icon: Icons.show_chart_rounded,
      title: 'Performansı takip edin',
      body: 'Portföy sekmesindeki grafik ikonundan toplam getiri grafiğinizi, '
          'kâr/zarar detaylarını ve teknik sinyalleri görüntüleyebilirsiniz.',
      align: _BalloonAlign.top,
    ),
    _DemoStep(
      icon: Icons.people_rounded,
      title: 'Ortakla paylaşın',
      body: 'Profil sekmesinden "Kod Üret" butonuyla bir davet kodu oluşturun '
          've bu kodu eşinize veya iş ortağınıza gönderin.',
      align: _BalloonAlign.top,
    ),
    _DemoStep(
      icon: Icons.bolt_rounded,
      title: 'Hızlı giriş',
      body: 'Varlık ekle ekranındaki ⚡ simgesine dokunun ve her satıra bir varlık yazın:\n'
          '"100 dolar\n10 gram altın 4500 lira\nGARAN 500 adet"\n'
          'Hepsi tek seferde eklenir.',
      align: _BalloonAlign.center,
    ),
  ];

  bool get _isLast => _step == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_isLast) {
      AnalyticsService.instance.logOnboardingCompleted();
      await OnboardingScreen.markCompleted(widget.userId);
      if (mounted) widget.onComplete();
      return;
    }
    await _anim.reverse();
    if (mounted) {
      setState(() => _step++);
      _anim.forward();
    }
  }

  Future<void> _skip() async {
    AnalyticsService.instance.logOnboardingSkipped(_step);
    await OnboardingScreen.markCompleted(widget.userId);
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.82),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Atla butonu ──────────────────────────────────────────────
            Positioned(
              top: 8,
              right: 16,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _skip,
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

            // ── İçerik ───────────────────────────────────────────────────
            FadeTransition(
              opacity: _fade,
              child: Column(
                children: [
                  const Spacer(),

                  // İkon spotlight
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Sandik.amber.withValues(alpha: 0.12),
                      border: Border.all(
                        color: Sandik.amber.withValues(alpha: 0.40),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Sandik.amber.withValues(alpha: 0.25),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(step.icon, size: 48, color: Sandik.amber),
                  ),

                  const SizedBox(height: 36),

                  // Balon — başlık + açıklama
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Sandik.surface1,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step.body,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              color: Sandik.text58,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Adım noktaları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (i) {
                      final active = i == _step;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? Sandik.amber : Sandik.text36,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 28),

                  // İleri / Başla butonu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
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
                            _isLast ? 'Sandığımı Aç' : 'İleri',
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

                  SizedBox(height: size.height * 0.06),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BalloonAlign { top, center, bottom }

class _DemoStep {
  final IconData icon;
  final String title;
  final String body;
  final _BalloonAlign align;
  const _DemoStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.align,
  });
}
