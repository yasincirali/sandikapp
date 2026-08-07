import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';

/// Yeni kullanıcılara gösterilen interaktif demo.
///
/// Gösterim politikası: yalnızca **hesap başına bir kez** — yeni kayıt olan
/// kullanıcı ilk kez giriş yaptığında gösterilir, sonraki giriş/açılışlarda
/// asla. Karar Supabase profil `onboarding_completed` alanı üzerindendir.
///
/// - Aynı hesapla farklı cihazlarda tekrar gösterilmez (server-truth).
/// - Silinip tekrar yüklenen aynı hesapta gösterilmez.
/// - Yeni kayıt olan başka bir hesap kendi ilk açılışında görür.
///
/// Ek olarak per-user bir cihaz cache'i tutulur (`onboarding_seen_${userId}`)
/// → server yazımı fail etse bile aynı cihazda tekrar açılmaz. Bu, "sürekli
/// gösteriliyor" bug'ını (network hatasında infinite loop) engeller.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final String userId;

  const OnboardingScreen({super.key, required this.onComplete, required this.userId});

  static String _deviceCacheKey(String userId) => 'onboarding_seen_$userId';

  /// Kullanıcı için onboarding daha önce tamamlanmış mı?
  /// Sıra: (1) per-user cihaz cache, (2) Supabase profil flag.
  /// Sorgu başarısız olursa "gösterildi" say — agresif yeniden gösterme
  /// önlenir, kullanıcı kayıt akışını rahatsız eden loop'a girmez.
  static Future<bool> isCompleted(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_deviceCacheKey(userId)) == true) return true;
      final profile = await SupabaseService.instance.getProfile(userId);
      final serverDone = profile?.onboardingCompleted ?? false;
      if (serverDone) {
        await prefs.setBool(_deviceCacheKey(userId), true);
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Onboarding'i tamamla — server flag'ini yaz + per-user cihaz cache'i set
  /// et. Cache önce yazılır; server yazımı başarısız olsa bile aynı cihazda
  /// tekrar açılmaz.
  ///
  /// Debug reinstall / cihaz değişikliği senaryolarında SharedPreferences
  /// silinir ve `isCompleted` server'a bakar → bu yüzden server yazımı
  /// **kritik** ve retry'lı yapılır. update fail ederse (satır yoksa) upsert
  /// fallback'i devreye girer.
  static Future<void> markCompleted(String userId) async {
    // Cache — 3 denemeye kadar tekrar.
    Object? cacheError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_deviceCacheKey(userId), true);
        cacheError = null;
        break;
      } catch (e) {
        cacheError = e;
      }
    }
    if (cacheError != null) {
      debugPrint(
          'OnboardingScreen.markCompleted cache write failed: $cacheError');
    }

    // Server yazımı — reinstall/cihaz değişikliği sonrası true dönebilmek
    // için garanti altına alınmalı. 3 kez retry + exponential backoff.
    Object? serverError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await SupabaseService.instance.markOnboardingCompleted(userId);
        serverError = null;
        break;
      } catch (e) {
        serverError = e;
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    if (serverError != null) {
      debugPrint(
          'OnboardingScreen.markCompleted server write failed: $serverError');
    }
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
    const _DemoStep(
      icon: Icons.bolt_rounded,
      title: 'Hızlı ve toplu giriş',
      body: 'Varlık ekle ekranındaki ⚡ ile "100 dolar", "10 gram altın 4500 lira", '
          '"GARAN 500 adet" gibi cümleleri tek seferde birden fazla varlığa dönüştürün. '
          'Sepet ile birden çok işlemi tek onayda kaydedebilirsiniz.',
      align: _BalloonAlign.center,
    ),
    const _DemoStep(
      icon: Icons.insights_rounded,
      title: 'Performans ve grafikler',
      body: 'Toplam getiri grafiği, kâr/zarar dökümü, varlık kırılımı ve tarihsel '
          'performansınızı Portföy sekmesindeki grafik ikonundan görün.',
      align: _BalloonAlign.top,
    ),
    const _DemoStep(
      icon: Icons.notifications_active_rounded,
      title: 'Teknik sinyaller',
      body: 'Portföyünüz her gün otomatik olarak analiz edilir. Al/sat sinyalleri '
          've önemli fiyat hareketleri bildirim olarak gelir. Ayarlardan hangi '
          'sinyalleri almak istediğinizi seçebilirsiniz.',
      align: _BalloonAlign.top,
    ),
    const _DemoStep(
      icon: Icons.people_rounded,
      title: 'Ortakla paylaşın',
      body: 'Profil sekmesinden davet kodu üretip eşinize veya iş ortağınıza gönderin. '
          'Onaylandığında portföyleri tek bir ekranda birlikte takip edersiniz.',
      align: _BalloonAlign.top,
    ),
    const _DemoStep(
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
                // HIG 44pt: metin 14pt olduğu için sıfır padding'de hedef
                // ~18pt'ye düşüyordu.
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(44, 44),
                onPressed: _skip,
                child: Text(
                  'Atla',
                  style: context.t.titleMedium?.copyWith(
                    color: Sandik.text58,
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
                        borderRadius: BorderRadius.circular(SandikRadius.lg),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: context.t.headlineMedium?.copyWith(
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step.body,
                            style: context.t.titleMedium?.copyWith(
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
                        curve: SandikMotion.enter,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? Sandik.amber : Sandik.text36,
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
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
                            borderRadius: BorderRadius.circular(SandikRadius.md),
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
                            style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
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
