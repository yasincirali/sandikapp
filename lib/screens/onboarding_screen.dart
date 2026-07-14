import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';

/// Yeni kullanıcılara gösterilen interaktif demo.
///
/// Gösterim politikası (2026-07): SADECE cihaza uygulamayı ilk defa yükleyen
/// kullanıcılara bir kez gösterilir. Karar cihaz-bazlı SharedPreferences flag'i
/// (`_deviceFlagKey`) üzerinden verilir; kullanıcı hesabı üzerinden değil.
/// - Yeni kayıt olan biri, cihaz daha önce onboarding gördüyse tekrar görmez.
/// - Kullanıcı uygulamayı silip yeniden yüklese bile Supabase profilindeki
///   `onboarding_completed` alanı hâlâ true olduğundan tekrar tetiklenmez
///   (fallback).
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String userId;

  const OnboardingScreen({super.key, required this.onComplete, required this.userId});

  /// Cihaz-bazlı "onboarding gösterildi" bayrağı. Uygulama silinip yeniden
  /// kurulunca sıfırlanır — bu istenen davranış: mağazadan ilk defa indiren
  /// cihazda sadece bir kere göster.
  static const _deviceFlagKey = 'onboarding_shown_on_device_v2';

  /// Onboarding'in bu cihaz için tamamlanıp tamamlanmadığını döner.
  /// Öncelik: cihaz flag'i (SharedPreferences). Cihazda gösterilmediyse
  /// Supabase profilindeki onboarding_completed kontrol edilir; bu alan
  /// true ise (kullanıcı başka bir cihazda görmüş) yine gösterilmez.
  /// Sorgu başarısız olursa "gösterildi" say (agresif yeniden-göstermeyi önle).
  static Future<bool> isCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_deviceFlagKey) == true) return true;
      final profile = await SupabaseService.instance.getProfile(userId);
      final serverDone = profile?.onboardingCompleted ?? false;
      if (serverDone) {
        // Sunucu tarafı tamam görüyor — cihaz flag'ini de yaz ki bir daha
        // ağ sorgusu bile yapılmasın.
        await prefs.setBool(_deviceFlagKey, true);
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_deviceFlagKey, true);
    } catch (_) {}
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

  late final List<_DemoStep> _steps = _buildSteps();

  static List<_DemoStep> _buildSteps() {
    final depositsOn = RemoteConfigService.instance.depositsEnabled;
    return [
    _DemoStep(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Sandığınıza hoş geldiniz',
      body: depositsOn
          ? 'Hisse, fon, döviz, altın, emtia, kripto ve vadeli mevduatlarınızı '
              'tek bir ekranda takip edin. Fiyatlar arka planda otomatik güncellenir.'
          : 'Hisse, fon, döviz, altın ve emtia varlıklarınızı tek bir ekranda '
              'takip edin. Fiyatlar arka planda otomatik güncellenir.',
      align: _BalloonAlign.center,
    ),
    _DemoStep(
      icon: Icons.add_circle_rounded,
      title: depositsOn ? 'Varlık ve mevduat ekleyin' : 'Varlık ekleyin',
      body: depositsOn
          ? 'Sağ alttaki + butonuyla varlık ekleyin; ayrıca vadeli mevduatlarınızı '
              'faiz oranı ve vade tarihiyle birlikte kayıt altına alabilirsiniz.'
          : 'Sağ alttaki + butonuyla portföyüne yeni varlık ekleyin. Alış tarihi, '
              'miktar ve maliyeti girin; anlık değer ve kâr/zarar otomatik hesaplanır.',
      align: _BalloonAlign.bottom,
    ),
    _DemoStep(
      icon: Icons.bolt_rounded,
      title: 'Hızlı ve toplu giriş',
      body: 'Varlık ekle ekranındaki ⚡ ile "100 dolar", "10 gram altın 4500 lira", '
          '"GARAN 500 adet" gibi cümleleri tek seferde birden fazla varlığa dönüştürün. '
          'Sepet ile birden çok işlemi tek onayda kaydedebilirsiniz.',
      align: _BalloonAlign.center,
    ),
    _DemoStep(
      icon: Icons.insights_rounded,
      title: 'Performans ve grafikler',
      body: 'Toplam getiri grafiği, kâr/zarar dökümü, varlık kırılımı ve tarihsel '
          'performansınızı Portföy sekmesindeki grafik ikonundan görün.',
      align: _BalloonAlign.top,
    ),
    _DemoStep(
      icon: Icons.notifications_active_rounded,
      title: 'Teknik sinyaller',
      body: 'Portföyünüz her gün otomatik olarak analiz edilir. Al/sat sinyalleri '
          've önemli fiyat hareketleri bildirim olarak gelir. Ayarlardan hangi '
          'sinyalleri almak istediğinizi seçebilirsiniz.',
      align: _BalloonAlign.top,
    ),
    _DemoStep(
      icon: Icons.people_rounded,
      title: 'Ortakla paylaşın',
      body: 'Profil sekmesinden davet kodu üretip eşinize veya iş ortağınıza gönderin. '
          'Onaylandığında portföyleri tek bir ekranda birlikte takip edersiniz.',
      align: _BalloonAlign.top,
    ),
    _DemoStep(
      icon: Icons.workspace_premium_rounded,
      title: 'Sınırsız Sandık Premium',
      body: 'Ücretsiz plan belirli sayıda varlık ile sınırlıdır. Premium ile '
          'sınırsız varlık, gelişmiş sinyaller ve reklamsız deneyim elde edersiniz. '
          'Profil > Premium sekmesinden inceleyebilirsiniz.',
      align: _BalloonAlign.center,
    ),
  ];
  }

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
