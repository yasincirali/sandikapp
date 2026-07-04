import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        Colors,
        Form,
        FormState,
        GestureDetector,
        GlobalKey,
        Icons,
        Material,
        TextFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

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
    try {
      await ref.read(authProvider.notifier).login(
            email: _emailCtrl.text,
            password: _passCtrl.text,
            rememberMe: _rememberMe,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
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
      backgroundColor: Sandik.background,
      child: SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
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
                          SandikLogo(size: 110),
                          const SizedBox(height: 16),
                          Text(
                            'sandık',
                            style: GoogleFonts.dmSans(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.02 * 32,
                              color: Sandik.gold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hazineni birlikte büyüt.',
                            style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text58),
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
                      style: GoogleFonts.dmSans(color: Sandik.text90),
                      decoration: Sandik.inputDecoration(
                        '',
                        labelText: 'E-posta',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.email_outlined, color: Sandik.text36, size: 20),
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
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                      style: GoogleFonts.dmSans(color: Sandik.text90),
                      decoration: Sandik.inputDecoration(
                        '',
                        labelText: 'Şifre',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.lock_outline, color: Sandik.text36, size: 20),
                        ),
                        suffixIcon: GestureDetector(
                          onTap: () => setState(() => _obscure = !_obscure),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: Sandik.text36,
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
                          onChanged: (v) => setState(() => _rememberMe = v),
                          animationDuration: const Duration(milliseconds: 400),
                          animationCurve: Curves.easeInOutCubic,
                          height: 28,
                          spacing: 4,
                          indicatorSize: const Size(22, double.infinity),
                          wrapperBuilder: (context, global, child) {
                            final t = global.position.clamp(0.0, 1.0);
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Color.lerp(
                                  Colors.white.withValues(alpha: 0.07),
                                  Sandik.amber.withValues(alpha: 0.88),
                                  t,
                                ),
                                border: Border.all(
                                  color: Color.lerp(
                                    Colors.white.withValues(alpha: 0.15),
                                    Sandik.amber,
                                    t,
                                  )!,
                                  width: 1.2,
                                ),
                                boxShadow: t > 0.05
                                    ? [
                                        BoxShadow(
                                          color: Sandik.amber.withValues(alpha: t * 0.4),
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
                                  Colors.white.withValues(alpha: 0.55),
                                  Sandik.dark,
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
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: Sandik.text58,
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
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: Sandik.amber,
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
                              ? Sandik.amber.withValues(alpha: 0.45)
                              : Sandik.amber.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Sandik.amber.withValues(alpha: 0.60),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Sandik.amber.withValues(alpha: 0.30),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Sandik.dark,
                                ),
                              )
                            : Text(
                                'Giriş Yap',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Sandik.dark,
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
                        style: GoogleFonts.dmSans(color: Sandik.amber),
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
    );
  }
}
