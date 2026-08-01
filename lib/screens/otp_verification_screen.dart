import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../widgets/custom_loading_indicator.dart';

/// Register (veya login) sonrası email doğrulama ekranı.
///
/// 6 haneli OTP input + "Doğrula" + timer + "Kodu yeniden gönder".
/// Timer expire olunca kutular disable, sadece "Yeni kod iste" gösterilir.
/// Yeni kod istendiğinde kutular yeniden açılır.
class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  bool _submitting = false;
  bool _resending = false;
  int _cooldown = 0;
  int _expiry = 0; // kod geçerlilik süresi (saniye). 0 = expire.
  Timer? _cooldownTimer;
  Timer? _expiryTimer;

  // Supabase OTP default TTL: 1 saat. UX için 10 dk göster — expire olsa
  // bile kullanıcı yeni kod isteyip devam edebilir.
  // ÖNEMLI: Bu değer Supabase → Auth → Providers → Email → "Email OTP
  // expiration" ile birebir aynı olmalı. Uyumsuzsa: bizim UI hâlâ
  // "kod geçerli" gösterirken Supabase kodu reddeder, kullanıcı için
  // kafa karıştırıcı olur. Supabase'de 600 sn (10 dk) ayarlıysa buraya
  // dokunma; değiştirirsen iki tarafı birden değiştir.
  static const _otpValiditySeconds = 600; // 10 dk
  static const _resendCooldownSeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
    _startCooldown();
    _startExpiry();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = _resendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _cooldown = _cooldown - 1;
        if (_cooldown <= 0) _cooldownTimer?.cancel();
      });
    });
  }

  void _startExpiry() {
    _expiry = _otpValiditySeconds;
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _expiry = _expiry - 1;
        if (_expiry <= 0) {
          _expiryTimer?.cancel();
          // Kod expire olunca kutuları temizle → görsel olarak "artık geçerli
          // değil" durumu belli olsun.
          for (final c in _controllers) {
            c.clear();
          }
        }
      });
    });
  }

  String get _code => _controllers.map((c) => c.text).join();
  bool get _isExpired => _expiry <= 0;
  bool get _isBusy => _submitting || _resending;

  String _formatMmSs(int seconds) {
    if (seconds < 0) seconds = 0;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submit() async {
    if (_isExpired) {
      // Race koruması: 6. haneyi girer girmez auto-submit tetiklenir, ama
      // arada expiry saati bitmiş olabilir. Backend'e çürük kod göndermek
      // yerine kullanıcıya "yeni kod iste" mesajı ver.
      showAppError(context, 'Kodun süresi doldu. Yeni kod iste.');
      return;
    }
    final code = _code;
    if (code.length != 6) {
      showAppError(context, 'Lütfen 6 haneli kodu tam olarak girin.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await AuthService.instance.verifyRegistrationOtp(
        email: widget.email,
        token: code,
      );
      ref.invalidate(authProvider);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 && !_isExpired) return;
    setState(() => _resending = true);
    try {
      await AuthService.instance.resendRegistrationOtp(widget.email);
      if (!mounted) return;
      // Yeni kod alındı: cooldown + expiry sıfırlan, kutular tekrar aktif.
      _startCooldown();
      _startExpiry();
      _focusNodes.first.requestFocus();
      showAppSuccess(
        context,
        title: 'Kod gönderildi',
        message: 'Yeni 6 haneli kod e-postana gönderildi.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_isBusy && (_cooldown <= 0 || _isExpired);
    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Sandik.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Sandik.text90, size: 20),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _iconBadge(),
              const SizedBox(height: 28),
              Text(
                'E-postanı doğrula',
                textAlign: TextAlign.center,
                style: context.t.headlineLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              _emailIntro(),
              const SizedBox(height: 32),
              _otpRow(),
              const SizedBox(height: 20),
              _expiryChip(),
              const SizedBox(height: 20),
              _primaryButton(),
              const SizedBox(height: 16),
              _resendRow(canResend: canResend),
              const SizedBox(height: 24),
              _footerHint(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge() {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Sandik.gold, Sandik.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Sandik.amber.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.mark_email_read_rounded,
          color: Colors.black87,
          size: 36,
        ),
      ),
    );
  }

  Widget _emailIntro() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: context.t.titleMedium?.copyWith(
          color: Sandik.text58,
          height: 1.5,
        ),
        children: [
          const TextSpan(text: '6 haneli kodu\n'),
          TextSpan(
            text: widget.email,
            style: context.t.titleMedium?.copyWith(
              color: Sandik.amber,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const TextSpan(text: '\nadresine gönderdik.'),
        ],
      ),
    );
  }

  Widget _otpRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => _otpCell(i)),
    );
  }

  Widget _otpCell(int index) {
    final filled = _controllers[index].text.isNotEmpty;
    final enabled = !_submitting && !_isExpired;
    return SizedBox(
      width: 46,
      height: 58,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        maxLength: 1,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        autofocus: index == 0,
        enabled: enabled,
        cursorColor: Sandik.amber,
        style: context.t.numLarge.copyWith(
          color: enabled ? Colors.white : Sandik.text36,
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: Sandik.surface1,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            borderSide: BorderSide(
              color: filled
                  ? Sandik.amber
                  : Colors.white.withValues(alpha: 0.08),
              width: filled ? 1.5 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            borderSide: const BorderSide(color: Sandik.amber, width: 1.8),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (v) {
          setState(() {});
          if (v.length == 1 && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (v.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (_code.length == 6 && !_submitting) {
            _submit();
          }
        },
      ),
    );
  }

  Widget _expiryChip() {
    if (_isExpired) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Sandik.loss.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: Sandik.loss.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Sandik.loss, size: 14),
              const SizedBox(width: 6),
              Text(
                'Kodun süresi doldu',
                style: context.t.titleSmall?.copyWith(
                  color: Sandik.loss,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded,
              color: Sandik.text58, size: 14),
          const SizedBox(width: 6),
          Text(
            'Kod ${_formatMmSs(_expiry)} sonra geçersiz olur',
            style: context.t.titleSmall?.copyWith(
              color: Sandik.text58,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton() {
    // Kod expired ise ana buton "Yeni kod iste"ye dönüşür.
    if (_isExpired) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: _isBusy ? null : _resend,
          style: FilledButton.styleFrom(
            backgroundColor: Sandik.amber,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Sandik.amber.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
          ),
          icon: _resending
              ? const CustomLoadingIndicator(size: 18)
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _resending ? 'Gönderiliyor…' : 'Yeni Kod İste',
            style: context.t.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: Sandik.amber,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Sandik.amber.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
        ),
        child: _submitting
            ? const CustomLoadingIndicator(size: 22)
            : Text(
                'Doğrula',
                style: context.t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _resendRow({required bool canResend}) {
    // Kod expired iken ana buton zaten "Yeni Kod İste" — burada tekrar
    // göstermeyelim, kullanıcıyı ikiye bölmesin.
    if (_isExpired) return const SizedBox.shrink();
    // Cooldown devam ediyorsa: "Yeniden gönder (43s)" gri. Bittiyse
    // tıklanabilir amber. Bu Twitter/WhatsApp/Google auth ile aynı desen.
    final showCountdown = _cooldown > 0 && !_resending;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Kodu almadın mı? ',
          style: context.t.bodyMedium?.copyWith(
            color: Sandik.text58,
          ),
        ),
        GestureDetector(
          onTap: canResend ? _resend : null,
          behavior: HitTestBehavior.opaque,
          child: Text(
            _resending
                ? 'Gönderiliyor…'
                : showCountdown
                    ? 'Yeniden gönder (${_cooldown}s)'
                    : 'Yeniden gönder',
            style: context.t.bodyMedium?.copyWith(
              color: canResend ? Sandik.amber : Sandik.text36,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footerHint() {
    return Center(
      child: Text(
        'Yanlış e-posta mı girdin? Geri dönüp tekrar deneyebilirsin.',
        textAlign: TextAlign.center,
        style: context.t.bodySmall?.copyWith(
          color: Sandik.text36,
          height: 1.4,
        ),
      ),
    );
  }
}
