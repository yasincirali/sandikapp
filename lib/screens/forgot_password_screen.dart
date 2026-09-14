import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        Colors,
        Form,
        FormState,
        GlobalKey,
        Icons,
        Material,
        TextFormField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/custom_loading_indicator.dart';
import '../l10n/l10n.dart';

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
        title: context.l10n.passwordUpdatedTitle,
        message:
            context.l10n.passwordUpdatedMessage,
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
      backgroundColor: context.c.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: context.c.background,
        border: null,
        middle: Text(
          context.l10n.forgotTitle,
          style: context.t.headlineSmall?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.c.text90,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: context.c.text58,
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
            context.l10n.forgotIntro,
            style: context.t.bodyLarge?.copyWith(
              color: context.c.text58,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onFieldSubmitted: (_) => _loading ? null : _sendCode(),
            style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            decoration: context.inputDecoration(
              '',
              labelText: context.l10n.email,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child:
                    Icon(Icons.email_outlined, color: context.c.text36, size: 20),
              ),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? context.l10n.emailInvalid : null,
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: context.l10n.sendCode,
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
            context.l10n.codeSentTo(_emailCtrl.text.trim()),
            style: context.t.titleMedium?.copyWith(
              color: context.c.text58,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // OTP kodu
          TextFormField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            // Klavye üstünde gelen kodu öner — tek alanlı OTP'de bu doğrudan
            // çalışır (çok hücreli OTP ekranından farklı olarak).
            autofillHints: const [AutofillHints.oneTimeCode],
            autocorrect: false,
            maxLength: 8,
            style: context.t.numLarge.copyWith(
              color: context.c.text90,
              fontSize: 20,
              letterSpacing: 6,
              fontWeight: FontWeight.w600,
            ),
            decoration: context.inputDecoration(
              '',
              labelText: context.l10n.code,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.pin_outlined,
                    color: context.c.text36, size: 20),
              ),
            ),
            validator: (v) => (v == null || v.trim().length < 6)
                ? context.l10n.codeInvalid
                : null,
          ),
          const SizedBox(height: 14),

          // Yeni şifre
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            autocorrect: false,
            enableSuggestions: false,
            style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            decoration: context.inputDecoration(
              '',
              labelText: context.l10n.newPassword,
              errorText: _passCtrl.text.isEmpty
                  ? null
                  : AuthService.validatePassword(_passCtrl.text),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.lock_outline,
                    color: context.c.text36, size: 20),
              ),
              suffixIcon: CupertinoButton(
                minimumSize: SandikTouch.minSize,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: () => setState(() => _obscure = !_obscure),
                child: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: context.c.text36,
                  size: 20,
                ),
              ),
            ),
            validator: (v) => v == null
                ? context.l10n.passwordRequired
                : AuthService.validatePassword(v),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Yeni şifre tekrar
          TextFormField(
            controller: _passConfirmCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            autocorrect: false,
            enableSuggestions: false,
            onFieldSubmitted: (_) => _loading ? null : _verifyAndUpdate(),
            style: context.t.bodyLarge?.copyWith(color: context.c.text90),
            decoration: context.inputDecoration(
              '',
              labelText: context.l10n.newPasswordRepeat,
              errorText: (_passConfirmCtrl.text.isNotEmpty &&
                      _passConfirmCtrl.text != _passCtrl.text)
                  ? context.l10n.passwordsMismatch
                  : null,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.lock_outline,
                    color: context.c.text36, size: 20),
              ),
            ),
            validator: (v) =>
                v != _passCtrl.text ? context.l10n.passwordsMismatch : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          _primaryButton(
            label: context.l10n.updatePassword,
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
              context.l10n.tryAnotherEmail,
              style: context.t.bodyMedium?.copyWith(color: context.c.amberText),
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
              ? context.c.amberFill.withValues(alpha: 0.92)
              : context.c.amberFill.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border:
              Border.all(color: context.c.amberFill.withValues(alpha: 0.60), width: 1),
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
                label,
                style: context.t.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.onAmber,
                ),
              ),
      ),
    );
  }
}
