import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../main.dart' show appNavigatorKey;
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
      // Şifre alanına odaklan
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
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
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
      return;
    }
    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.hasError) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.error.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } else if (authState.valueOrNull != null) {
      // Login başarılı — stack'i temizle, AuthGate MainNavigationScreen'e geçer
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Sandik.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 56),

                  // ── Logo + wordmark ──────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        const SandikLogo(size: 52, color: Sandik.amber),
                        const SizedBox(height: 16),
                        Text(
                          'sandık',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.02 * 32,
                            color: Sandik.gold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Hazineni birlikte büyüt.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Sandik.text58,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // ── E-posta ─────────────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.inter(color: Sandik.text90),
                    decoration: InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: const Icon(Icons.email_outlined,
                          color: Sandik.text36, size: 20),
                      labelStyle: GoogleFonts.inter(color: Sandik.text36),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@'))
                            ? 'Geçerli e-posta girin'
                            : null,
                  ),
                  const SizedBox(height: 14),

                  // ── Şifre ────────────────────────────────────────────────
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: GoogleFonts.inter(color: Sandik.text90),
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: Sandik.text36, size: 20),
                      labelStyle: GoogleFonts.inter(color: Sandik.text36),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Sandik.text36,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'En az 6 karakter' : null,
                  ),
                  const SizedBox(height: 28),

                  // ── Giriş butonu ─────────────────────────────────────────
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Sandik.dark),
                          )
                        : Text(
                            'Giriş Yap',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                  const SizedBox(height: 14),

                  // ── Kayıt ol ─────────────────────────────────────────────
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(
                      'Hesabınız yok mu? Kayıt olun',
                      style: GoogleFonts.inter(color: Sandik.amber),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
