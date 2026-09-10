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
    ),
    _DemoStep(
      icon: Icons.add_circle_rounded,
      title: depositsOn ? 'Varlık ve mevduat ekleyin' : 'Varlık ekleyin',
      body: depositsOn
          ? 'Sağ alttaki + butonuyla varlık ekleyin; ayrıca vadeli mevduatlarınızı '
              'faiz oranı ve vade tarihiyle birlikte kayıt altına alabilirsiniz.'
          : 'Sağ alttaki + butonuyla portföyüne yeni varlık ekleyin. Alış tarihi, '
              'miktar ve maliyeti girin; anlık değer ve kâr/zarar otomatik hesaplanır.',
    ),
    const _DemoStep(
      icon: Icons.bolt_rounded,
      title: 'Hızlı ve toplu giriş',
      body: 'Varlık ekle ekranındaki ⚡ ile "100 dolar", "10 gram altın 4500 lira", '
          '"GARAN 500 adet" gibi cümleleri tek seferde birden fazla varlığa dönüştürün. '
          'Sepet ile birden çok işlemi tek onayda kaydedebilirsiniz.',
    ),
    const _DemoStep(
      icon: Icons.insights_rounded,
      title: 'Performans ve grafikler',
      body: 'Toplam getiri grafiği, kâr/zarar dökümü, varlık kırılımı ve tarihsel '
          'performansınızı Portföy sekmesindeki grafik ikonundan görün.',
    ),
    const _DemoStep(
      icon: Icons.notifications_active_rounded,
      title: 'Teknik sinyaller',
      body: 'Portföyünüz her gün otomatik olarak analiz edilir. Al/sat sinyalleri '
          've önemli fiyat hareketleri bildirim olarak gelir. Ayarlardan hangi '
          'sinyalleri almak istediğinizi seçebilirsiniz.',
    ),
    const _DemoStep(
      icon: Icons.people_rounded,
      title: 'Ortakla paylaşın',
      body: 'Profil sekmesinden davet kodu üretip eşinize veya iş ortağınıza gönderin. '
          'Onaylandığında portföyleri tek bir ekranda birlikte takip edersiniz.',
    ),
    const _DemoStep(
      icon: Icons.workspace_premium_rounded,
      title: 'Sınırsız Sandık Premium',
      // "Reklamsız deneyim" ifadesi KALDIRILDI: uygulamada reklam YOK
      // (ne SDK ne de gizlilik politikasında bir reklam maddesi var).
      // Ücretsiz planın reklamlı olduğunu ima etmek hem yanlış hem de
      // gizlilik politikasıyla çelişiyordu. Metin paywall ekranıyla
      // aynı özellikleri sayıyor.
      body: 'Ücretsiz plan belirli sayıda varlık ile sınırlıdır. Premium ile '
          'sınırsız varlık, gelişmiş göstergeler ve günde iki sinyal analizi '
          'elde edersiniz. Profil > Premium sekmesinden inceleyebilirsiniz.',
    ),
  ];
  }

  bool get _isLast => _step == _steps.length - 1;

  /// Sayfa geçişleri — parmakla KAYDIRILABİLİR olmalı.
  ///
  /// Eski sürüm yalnızca "İleri" butonuyla ilerliyordu. Tanıtım ekranı
  /// gören herkesin ilk refleksi kaydırmaktır; hiçbir şey olmayınca ekran
  /// donmuş gibi hissettiriyordu. Ayrıca geri dönüş yoktu: bir adımı
  /// hızlı geçen kullanıcı okuduğuna geri dönemiyordu.
  late final PageController _pages = PageController();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: SandikMotion.surface);
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _pages.dispose();
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
    await _pages.nextPage(
      duration: SandikMotion.surfaceOf(context),
      curve: SandikMotion.enter,
    );
  }

  Future<void> _skip() async {
    AnalyticsService.instance.logOnboardingSkipped(_step);
    await OnboardingScreen.markCompleted(widget.userId);
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    // ── Zemin TEMADAN gelir ─────────────────────────────────────────────
    //
    // Eskiden `Colors.black.withValues(alpha: 0.82)` kullanılıyordu. Bu
    // ekran bir overlay DEĞİL, tam sayfadır (bkz. `main.dart` — açılış
    // akışında `MainNavigationScreen` yerine döner); yarı saydam siyahın
    // altında gösterilecek bir şey yok. Sonuç: açık temada bile kapkara
    // bir sayfa ve üstünde açık renkli bir kart — uygulamanın geri
    // kalanıyla hiç uyuşmayan, "bozuk" görünen bir giriş.
    return Scaffold(
      backgroundColor: context.c.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst çubuk: geri + atla ───────────────────────────────────
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  // Geri, yalnızca dönülecek bir adım varken yer kaplar.
                  if (_step > 0)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(44, 44),
                      onPressed: () => _pages.previousPage(
                        duration: SandikMotion.surfaceOf(context),
                        curve: SandikMotion.enter,
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: context.c.text58),
                    )
                  else
                    const SizedBox(width: 16),
                  const Spacer(),
                  CupertinoButton(
                    // HIG 44pt: metin 14pt olduğu için sıfır padding'de
                    // hedef ~18pt'ye düşüyordu.
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(44, 44),
                    onPressed: _skip,
                    child: Text(
                      'Atla',
                      style: context.t.titleMedium?.copyWith(
                        color: context.c.text58,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Adımlar ──────────────────────────────────────────────────
            //
            // Her adım KENDİ İÇİNDE kaydırılabilir. Eski sürüm `Spacer` +
            // sabit yükseklikli bir `Column` kullanıyordu: 100pt ikon +
            // 36 + balon + 32 + noktalar + 28 + 52pt buton + %6 boşluk.
            // Küçük bir telefonda ya da sistem yazı tipi büyütülmüşken
            // (erişilebilirlik ayarı) bu yığın ekrana sığmıyor ve
            // RenderFlex taşma çizgileri çıkıyordu.
            Expanded(
              // Beliriş animasyonu SAYFA BAŞINA DEĞİL, ekran açılışına
              // aittir. Sayfa başına yapılırsa `PageView` bir sonraki
              // sayfayı önden kurduğu için kullanıcı parmağını sürerken
              // opak gelen sayfa, `onPageChanged` anında sıfırlanıp
              // yeniden belirir — kaydırma sırasında görünür bir titreme.
              // Sayfalar arası geçişi zaten kaydırmanın kendisi anlatıyor.
              child: FadeTransition(
                opacity: _fade,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _step = i),
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
            ),

            // ── Adım noktaları ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: SandikSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final active = i == _step;
                  return AnimatedContainer(
                    duration: SandikMotion.stateOf(context),
                    curve: SandikMotion.enter,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? context.c.amberText : context.c.text36,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                    ),
                  );
                }),
              ),
            ),

            // ── İleri / Başla butonu ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  28, SandikSpace.lgs, 28, SandikSpace.lg),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: _next,
                  padding: EdgeInsets.zero,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.c.amberFill,
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: context.c.amberFill.withValues(alpha: 0.28),
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
                        color: context.c.onAmber,
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

/// Tek bir tanıtım adımı — ikon + başlık + açıklama.
///
/// Kendi içinde kaydırılabilir (`SingleChildScrollView`): uzun metin,
/// büyük sistem yazı tipi ya da kısa ekranlarda taşma yerine kaydırma
/// olur. `ConstrainedBox` + `IntrinsicHeight` yerine basit bir
/// `Center`: içerik sığıyorsa ortalanır, sığmıyorsa kaydırılır.
class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _DemoStep step;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // İkon spotlight — ortada.
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.c.amberFill.withValues(alpha: 0.12),
              border: Border.all(
                color: context.c.amberFill.withValues(alpha: 0.40),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.c.amberFill.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(step.icon, size: 48, color: context.c.amberText),
          ),
        ),
        const SizedBox(height: SandikSpace.xl),
        // Balon — başlık + açıklama.
        Container(
          padding: const EdgeInsets.all(SandikSpace.lg),
          decoration: BoxDecoration(
            color: context.c.surface1,
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(color: context.c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: context.t.headlineMedium?.copyWith(
                  color: context.c.text90,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step.body,
                style: context.t.titleMedium?.copyWith(
                  color: context.c.text58,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: 28, vertical: SandikSpace.lg),
      child: Center(child: content),
    );
  }
}

class _DemoStep {
  final IconData icon;
  final String title;
  final String body;
  const _DemoStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}
