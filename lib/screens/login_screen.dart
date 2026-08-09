import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        Form,
        FormState,
        GestureDetector,
        GlobalKey,
        Icons,
        Material,
        TextFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_screen.dart';
import 'register_screen.dart';
import '../widgets/custom_loading_indicator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final saved = await AuthService.instance.getSavedEmail();
    if (saved != null && mounted) {
      _emailCtrl.text = saved;
      setState(() => _rememberMe = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final valid = _formKey.currentState!.validate();
    if (!valid) return;
    setState(() => _loading = true);
    final emailForOtp = _emailCtrl.text.trim().toLowerCase();
    try {
      await ref.read(authProvider.notifier).login(
            email: _emailCtrl.text,
            password: _passCtrl.text,
            rememberMe: _rememberMe,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Confirm-email açık ve doğrulanmamış kullanıcı → OTP ekranına yönlendir.
      // AuthService.login "EMAIL_NOT_CONFIRMED" sentinel exception atar.
      final msg = e.toString();
      if (msg.contains('EMAIL_NOT_CONFIRMED')) {
        // Yeni bir OTP gönderilsin ki kullanıcı elinde taze kod olsun.
        try {
          await AuthService.instance.resendRegistrationOtp(emailForOtp);
        } catch (_) {
          // Rate-limit vb — sessizce yut, kullanıcı OTP ekranında "yeniden
          // gönder" cooldown'ını görecek.
        }
        if (!mounted) return;
        await Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => OtpVerificationScreen(email: emailForOtp),
          ),
        );
        return;
      }
      showAppError(context, e);
      return;
    }
    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.hasError) {
      setState(() => _loading = false);
      showAppError(context, authState.error);
      return;
    }
    // UA1 fix: Manuel yönlendirmeyi sildik. AuthGate (`lib/main.dart`)
    // authProvider değişimini dinleyip disclaimer/onboarding/main
    // akışını kendi başına yönetir. Burada elle pushAndRemoveUntil
    // yapmak onboarding kontrolünü atlatıyordu.
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);

    return CupertinoPageScaffold(
      backgroundColor: context.c.background,
      child: SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              // AutofillGroup ŞART: `autofillHints` tek başına doldurmayı
              // açar ama iOS'un "şifreyi kaydet?" istemini tetiklemez.
              // Grup, alanların tek bir kimlik formu olduğunu sisteme söyler.
              child: AutofillGroup(
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 56),

                    // Logo + wordmark
                    Center(
                      child: Column(
                        children: [
                          const SandikLogo(size: 110),
                          const SizedBox(height: 16),
                          Text(
                            'sandık',
                            style: context.t.displaySmall?.copyWith(
                              color: context.c.gold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hazineni birlikte büyüt.',
                            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),

                    // E-posta
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      // iCloud Keychain / Google şifre yöneticisi bu ipuçlarına
                      // bakar; olmadan otomatik doldurma HİÇ çalışmaz.
                      autofillHints: const [AutofillHints.username],
                      // E-posta'da otomatik düzeltme ve ilk harf büyütme
                      // zararlıdır: "Ali@" → "Ali@" beklenirken sistem
                      // adresi bozabiliyor.
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                      decoration: context.inputDecoration(
                        '',
                        labelText: 'E-posta',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.email_outlined, color: context.c.text36, size: 20),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Geçerli e-posta girin' : null,
                    ),
                    const SizedBox(height: 14),

                    // Şifre
                    TextFormField(
                      controller: _passCtrl,
                      focusNode: _passFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                      style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                      decoration: context.inputDecoration(
                        '',
                        labelText: 'Şifre',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.lock_outline, color: context.c.text36, size: 20),
                        ),
                        suffixIcon: SandikTappable(
                          semanticLabel:
                              _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                          onTap: () => setState(() => _obscure = !_obscure),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: context.c.text36,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'En az 6 karakter' : null,
                    ),
                    const SizedBox(height: 12),

                    // Beni hatırla
                    Row(
                      children: [
                        CustomAnimatedToggleSwitch<bool>(
                          current: _rememberMe,
                          values: const [false, true],
                          onChanged: (v) {
                            SandikHaptic.selection.perform();
                            setState(() => _rememberMe = v);
                          },
                          // 400ms → 180ms: toggle bir buton geri bildirimidir,
                          // 400ms anahtarı ağır hissettiriyordu.
                          animationDuration: SandikMotion.state,
                          // Sürgü ekranda yer değiştiriyor → move.
                          animationCurve: SandikMotion.move,
                          height: 28,
                          spacing: 4,
                          indicatorSize: const Size(22, double.infinity),
                          wrapperBuilder: (context, global, child) {
                            final t = global.position.clamp(0.0, 1.0);
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(SandikRadius.lg),
                                color: Color.lerp(
                                  context.c.overlay,
                                  context.c.amberFill.withValues(alpha: 0.88),
                                  t,
                                ),
                                border: Border.all(
                                  color: Color.lerp(
                                    context.c.overlay,
                                    context.c.amberText,
                                    t,
                                  )!,
                                  width: 1.2,
                                ),
                                boxShadow: t > 0.05
                                    ? [
                                        BoxShadow(
                                          color: context.c.amberFill.withValues(alpha: t * 0.4),
                                          blurRadius: 10,
                                          spreadRadius: -2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: child,
                            );
                          },
                          foregroundIndicatorBuilder: (context, global) {
                            final t = global.position.clamp(0.0, 1.0);
                            return Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.lerp(
                                  context.c.text58,
                                  context.c.onAmber,
                                  t,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 5,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                            );
                          },
                          iconBuilder: (context, local, global) => const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Beni hatırla',
                          style: context.t.titleMedium?.copyWith(
                            color: context.c.text58,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => ForgotPasswordScreen(
                                initialEmail: _emailCtrl.text.trim().isEmpty
                                    ? null
                                    : _emailCtrl.text.trim(),
                              ),
                            ),
                          ),
                          child: Text(
                            'Şifremi unuttum',
                            style: context.t.bodyMedium?.copyWith(
                              color: context.c.amberText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Giriş butonu — amber glass
                    // GestureDetector(opaque) instead of CupertinoButton: on
                    // iOS release the CupertinoButton was losing the gesture
                    // arena to the enclosing Scrollable and never firing.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _loading ? null : _login,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: _loading
                              ? context.c.amberFill.withValues(alpha: 0.45)
                              : context.c.amberFill.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(SandikRadius.md),
                          border: Border.all(
                            color: context.c.amberFill.withValues(alpha: 0.60),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: context.c.amberFill.withValues(alpha: 0.30),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _loading
                            ? const CustomLoadingIndicator(size: 22)
                            : Text(
                                'Giriş Yap',
                                style: context.t.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: context.c.onAmber,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Kayıt ol
                    CupertinoButton(
                      onPressed: () => Navigator.push(
                        context,
                        CupertinoPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: Text(
                        'Hesabınız yok mu? Kayıt olun',
                        style: context.t.bodyLarge?.copyWith(color: context.c.amberText),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
