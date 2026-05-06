import 'dart:ui' show ImageFilter;
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
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../main.dart' show appNavigatorKey;
import 'disclaimer_acceptance_screen.dart';
import 'main_navigation_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final saved = await AuthService.instance.getSavedEmail();
    if (saved != null && mounted) {
      _emailCtrl.text = saved;
      setState(() {});
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

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Hata'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    final valid = _formKey.currentState!.validate();
    if (!valid) return;
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).login(
            email: _emailCtrl.text,
            password: _passCtrl.text,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _showError(e.toString());
      return;
    }
    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.hasError) {
      setState(() => _loading = false);
      await _showError(authState.error.toString());
    } else if (authState.valueOrNull != null) {
      final userId = authState.valueOrNull!.id;
      final accepted = await DisclaimerService.instance.hasAccepted(userId);
      if (!mounted) return;
      if (accepted) {
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const MainNavigationScreen()),
          (_) => false,
        );
      } else {
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          CupertinoPageRoute(
            builder: (_) => DisclaimerAcceptanceScreen(
              userId: userId,
              onAccepted: () => appNavigatorKey.currentState?.pushAndRemoveUntil(
                CupertinoPageRoute(builder: (_) => const MainNavigationScreen()),
                (_) => false,
              ),
            ),
          ),
          (_) => false,
        );
      }
    }
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: Sandik.glassDecoration(
                                  radius: 22,
                                  tint: Colors.white,
                                  tintOpacity: 0.07,
                                  borderColor: Sandik.amber,
                                  borderOpacity: 0.30,
                                ),
                                child: Center(
                                  child: SandikLogo(size: 60),
                                ),
                              ),
                            ),
                          ),
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
                    const SizedBox(height: 28),

                    // Giriş butonu — amber glass
                    CupertinoButton(
                      onPressed: _loading ? null : _login,
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
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
