import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
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
  bool _isAdmin = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          email: _emailCtrl.text,
          password: _isAdmin ? '' : _passCtrl.text,
        );
    final error = ref.read(authProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: Sandik.loss),
      );
    }
  }

  void _onEmailChanged(String value) {
    final admin = AuthService.instance.isAdmin(value);
    if (admin != _isAdmin) setState(() => _isAdmin = admin);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

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

                  // ── Logo + wordmark ────────────────────────────────────────
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

                  // ── E-posta ────────────────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.inter(color: Sandik.text90),
                    decoration: InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: const Icon(Icons.email_outlined, color: Sandik.text36, size: 20),
                      labelStyle: GoogleFonts.inter(color: Sandik.text36),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Geçerli e-posta girin' : null,
                    onChanged: _onEmailChanged,
                  ),
                  const SizedBox(height: 14),

                  // ── Şifre (admin için gizle) ───────────────────────────────
                  if (!_isAdmin) ...[
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: GoogleFonts.inter(color: Sandik.text90),
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline, color: Sandik.text36, size: 20),
                        labelStyle: GoogleFonts.inter(color: Sandik.text36),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                  ] else
                    const SizedBox(height: 28),

                  // ── Giriş butonu ───────────────────────────────────────────
                  FilledButton(
                    onPressed: isLoading ? null : _login,
                    child: isLoading
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

                  // ── Kayıt ol ───────────────────────────────────────────────
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
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
