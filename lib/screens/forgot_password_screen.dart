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
        TextFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';

/// Şifremi Unuttum — OTP tabanlı akış.
///
/// Adım 1: kullanıcı email girer → sendPasswordResetOtp
/// Adım 2: kod + yeni şifre girer → verifyPasswordResetOtp
///   → başarılıysa Supabase otomatik login yapar, LoginScreen'e döner.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailCtrl.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordResetOtp(_emailCtrl.text);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _codeSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppError(context, e);
    }
  }

  Future<void> _verifyAndUpdate() async {
    if (!_otpFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.verifyPasswordResetOtp(
        email: _emailCtrl.text,
        otp: _otpCtrl.text,
        newPassword: _passCtrl.text,
      );
      if (!mounted) return;
      await showAppSuccess(
        context,
        title: 'Şifre güncellendi',
        message:
            'Yeni şifrenle giriş yapabilirsin. Şimdi ana ekrana yönlendirileceksin.',
      );
      if (!mounted) return;
      // Supabase verifyOTP başarılıyla session açtı — AuthGate otomatik
      // olarak MainNavigationScreen'e alacak. LoginScreen'i temizleyip
      // kök'e dönmek yeterli.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Sandik.background,
        border: null,
        middle: Text(
          'Şifremi Unuttum',
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Sandik.text90,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: Sandik.text58,
          ),
        ),
      ),
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: _codeSent ? _buildOtpStep() : _buildEmailStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            'Kod göndereceğimiz e-posta adresini gir.',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: Sandik.text58,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _loading ? null : _sendCode(),
            style: GoogleFonts.dmSans(color: Sandik.text90),
            decoration: Sandik.inputDecoration(
              '',
              labelText: 'E-posta',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child:
                    Icon(Icons.email_outlined, color: Sandik.text36, size: 20),
              ),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Geçerli e-posta girin' : null,
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Kod Gönder',
            onTap: _loading ? null : _sendCode,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            '${_emailCtrl.text.trim()} adresine kod gönderdik. '
            'Kodu ve yeni şifreni gir.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: Sandik.text58,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // OTP kodu
          TextFormField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 8,
            style: GoogleFonts.dmSans(
              color: Sandik.text90,
              fontSize: 20,
              letterSpacing: 6,
              fontWeight: FontWeight.w600,
            ),
            decoration: Sandik.inputDecoration(
              '',
              labelText: 'Kod',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.pin_outlined,
                    color: Sandik.text36, size: 20),
              ),
            ),
            validator: (v) => (v == null || v.trim().length < 6)
                ? 'Kod eksik veya geçersiz'
                : null,
          ),
          const SizedBox(height: 14),

          // Yeni şifre
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            style: GoogleFonts.dmSans(color: Sandik.text90),
            decoration: Sandik.inputDecoration(
              '',
              labelText: 'Yeni Şifre',
              errorText: _passCtrl.text.isEmpty
                  ? null
                  : AuthService.validatePassword(_passCtrl.text),
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
              ),
            ),
            validator: (v) => v == null
                ? 'Şifre gerekli'
                : AuthService.validatePassword(v),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Yeni şifre tekrar
          TextFormField(
            controller: _passConfirmCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _loading ? null : _verifyAndUpdate(),
            style: GoogleFonts.dmSans(color: Sandik.text90),
            decoration: Sandik.inputDecoration(
              '',
              labelText: 'Yeni Şifre Tekrar',
              errorText: (_passConfirmCtrl.text.isNotEmpty &&
                      _passConfirmCtrl.text != _passCtrl.text)
                  ? 'Şifreler eşleşmiyor'
                  : null,
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.lock_outline,
                    color: Sandik.text36, size: 20),
              ),
            ),
            validator: (v) =>
                v != _passCtrl.text ? 'Şifreler eşleşmiyor' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          _primaryButton(
            label: 'Şifreyi Güncelle',
            onTap: _loading ? null : _verifyAndUpdate,
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                      _codeSent = false;
                      _otpCtrl.clear();
                      _passCtrl.clear();
                      _passConfirmCtrl.clear();
                    }),
            child: Text(
              'Farklı bir e-posta ile tekrar dene',
              style: GoogleFonts.dmSans(color: Sandik.amber, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: enabled
              ? Sandik.amber.withValues(alpha: 0.92)
              : Sandik.amber.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Sandik.amber.withValues(alpha: 0.60), width: 1),
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
                label,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Sandik.dark,
                ),
              ),
      ),
    );
  }
}
