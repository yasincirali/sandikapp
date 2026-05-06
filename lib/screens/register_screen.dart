import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        Colors,
        Form,
        FormState,
        GlobalKey,
        Icons,
        Material,
        ScaffoldMessenger,
        SnackBar,
        TextFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _disclaimerAccepted = false;
  bool _disclaimerError = false;
  bool _emailTouched = false; // focus kaybedince hata göster

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _isValidEmail(_emailCtrl.text) &&
      _passCtrl.text.length >= 6 &&
      _passCtrl.text == _passConfirmCtrl.text &&
      _disclaimerAccepted;

  bool _isValidEmail(String v) {
    final parts = v.split('@');
    return parts.length == 2 && parts[0].isNotEmpty && parts[1].contains('.');
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_rebuild);
    _emailCtrl.addListener(_rebuild);
    _passCtrl.addListener(_rebuild);
    _passConfirmCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Disclaimer zorunlu kontrol
    if (!_disclaimerAccepted) {
      setState(() => _disclaimerError = true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authProvider.notifier).register(
          email: _emailCtrl.text,
          displayName: _nameCtrl.text,
          password: _passCtrl.text,
        );

    final authState = ref.read(authProvider);
    if (authState.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(authState.error.toString()),
            backgroundColor: Sandik.loss),
      );
      return;
    }

    // Kayıt başarılı — disclaimer'ı Supabase'e yaz
    final user = authState.valueOrNull;
    if (user != null) {
      try {
        await DisclaimerService.instance.recordAcceptance(
          userId: user.id,
          appVersion: '1.0.0+1',
          platform: Platform.isIOS ? 'ios' : 'android',
          locale: 'tr_TR',
        );
      } catch (_) {
        // Kayıt başarıysa bile devam et — disclaimer kaydı kritik değil
      }
    }

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Sandik.background,
        border: null,
        middle: Text('Kayıt Ol',
            style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Sandik.text58),
        ),
      ),
      child: Material(
        color: Sandik.background,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            children: [
              const SizedBox(height: 8),

              // Ad Soyad
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.dmSans(color: Sandik.text90),
                decoration: Sandik.inputDecoration('',
                    labelText: 'Ad Soyad',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.person_outline,
                          color: Sandik.text36, size: 20),
                    )),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ad soyad girin' : null,
              ),
              const SizedBox(height: 14),

              // E-posta
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.dmSans(color: Sandik.text90),
                onEditingComplete: () {
                  setState(() => _emailTouched = true);
                  FocusScope.of(context).nextFocus();
                },
                onTapOutside: (_) => setState(() => _emailTouched = true),
                decoration: Sandik.inputDecoration('',
                    labelText: 'E-posta',
                    errorText: (_emailTouched && _emailCtrl.text.isNotEmpty && !_isValidEmail(_emailCtrl.text))
                        ? 'Geçerli e-posta girin'
                        : null,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.email_outlined,
                          color: Sandik.text36, size: 20),
                    )),
                validator: (v) =>
                    (v == null || !_isValidEmail(v)) ? 'Geçerli e-posta girin' : null,
              ),
              const SizedBox(height: 14),

              // Şifre
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: GoogleFonts.dmSans(color: Sandik.text90),
                decoration: Sandik.inputDecoration('',
                    labelText: 'Şifre',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.lock_outline,
                          color: Sandik.text36, size: 20),
                    ),
                    suffixIcon: CupertinoButton(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Sandik.text36,
                        size: 20,
                      ),
                    )),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'En az 6 karakter' : null,
              ),
              const SizedBox(height: 14),

              // Şifre tekrar
              TextFormField(
                controller: _passConfirmCtrl,
                obscureText: _obscure,
                style: GoogleFonts.dmSans(color: Sandik.text90),
                decoration: Sandik.inputDecoration('',
                    labelText: 'Şifre Tekrar',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.lock_outline,
                          color: Sandik.text36, size: 20),
                    )),
                validator: (v) =>
                    v != _passCtrl.text ? 'Şifreler eşleşmiyor' : null,
              ),
              const SizedBox(height: 28),

              // ── Yasal Uyarı Onay Kutusu ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _disclaimerError
                      ? Sandik.loss.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _disclaimerError
                        ? Sandik.loss.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.gavel_rounded,
                            size: 16, color: Sandik.amber),
                        const SizedBox(width: 8),
                        Text(
                          'Yasal Uyarı',
                          style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Sandik.amber),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'v$disclaimerVersion',
                          style: GoogleFonts.dmSans(
                              fontSize: 10, color: Sandik.text36),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      disclaimerText,
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: Sandik.text58,
                          height: 1.6),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => setState(() {
                        _disclaimerAccepted = !_disclaimerAccepted;
                        if (_disclaimerAccepted) _disclaimerError = false;
                      }),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _disclaimerAccepted
                                  ? Sandik.amber
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _disclaimerAccepted
                                    ? Sandik.amber
                                    : (_disclaimerError
                                        ? Sandik.loss
                                        : Sandik.text36),
                                width: 2,
                              ),
                            ),
                            child: _disclaimerAccepted
                                ? const Icon(Icons.check_rounded,
                                    size: 14, color: Sandik.dark)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Yukarıdaki yasal uyarıyı okudum ve kabul ediyorum.',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: _disclaimerError
                                    ? Sandik.loss
                                    : Sandik.text58,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_disclaimerError) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Devam etmek için yasal uyarıyı kabul etmelisiniz.',
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: Sandik.loss),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Kayıt Ol butonu
              CupertinoButton(
                onPressed: (isLoading || !_canSubmit) ? null : _register,
                padding: EdgeInsets.zero,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: (isLoading || !_canSubmit)
                        ? Sandik.amber.withValues(alpha: 0.45)
                        : Sandik.amber.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Sandik.amber.withValues(alpha: 0.60)),
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
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Sandik.dark),
                        )
                      : Text(
                          'Kayıt Ol',
                          style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Sandik.dark),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Zaten hesabınız var mı? Giriş yapın',
                  style: GoogleFonts.dmSans(color: Sandik.amber),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
