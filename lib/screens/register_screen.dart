import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        AlertDialog,
        CircularProgressIndicator,
        Colors,
        Form,
        FormState,
        GlobalKey,
        Icons,
        Material,
        SelectableText,
        TextButton,
        TextFormField,
        showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';

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
  // UC1 fix: 4 ayrı checkbox bilişsel yük yaratıyordu. Disclaimer + KVKK
  // Aydınlatma + 18+ yaş onayı tek bir "yasal koşullar" onayında birleşti.
  // Yurt dışı veri aktarımı KVKK Madde 9(1) zorunluluğu nedeniyle ayrı
  // bir "açık rıza" onayı olarak kalmaya devam ediyor.
  bool _termsAccepted = false;
  bool _termsError = false;
  bool _consentAccepted = false;
  bool _consentError = false;
  bool _emailTouched = false; // focus kaybedince hata göster

  // TODO: Production'da gerçek URL'ler.
  static const _privacyUrl = 'https://sandik.app/privacy';
  static const _termsUrl = 'https://sandik.app/terms';
  static const _kvkkUrl = 'https://sandik.app/legal/kvkk';
  static const _consentUrl = 'https://sandik.app/legal/acik-riza';

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _isValidEmail(_emailCtrl.text) &&
      AuthService.validatePassword(_passCtrl.text) == null &&
      _passCtrl.text == _passConfirmCtrl.text &&
      _termsAccepted &&
      _consentAccepted;

  /// First missing requirement, in the order the user filled the form.
  /// null → form is valid.
  String? _firstMissingRequirement() {
    if (_nameCtrl.text.trim().isEmpty) return 'Ad soyad girin.';
    if (!_isValidEmail(_emailCtrl.text)) return 'Geçerli bir e-posta girin.';
    final passError = AuthService.validatePassword(_passCtrl.text);
    if (passError != null) return passError;
    if (_passCtrl.text != _passConfirmCtrl.text) {
      return 'Şifreler eşleşmiyor.';
    }
    if (!_termsAccepted) return 'Yasal koşulları kabul etmelisin.';
    if (!_consentAccepted) {
      return 'Yurt dışı veri aktarımına açık rıza vermelisin.';
    }
    return null;
  }

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

  /// Birleştirilmiş "Yasal Koşullar" altındaki üç belgeyi tek dialog'da göster.
  void _showLegalLinks() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Sandik.surface2,
        title: const Text('Yasal Belgeler',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aşağıdaki belgeleri inceleyebilirsin:',
              style: TextStyle(color: Sandik.text58, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('Kullanım Koşulları',
                style: TextStyle(color: Sandik.text90, fontSize: 13)),
            SelectableText(_termsUrl,
                style: const TextStyle(color: Sandik.amber, fontSize: 12)),
            const SizedBox(height: 10),
            const Text('KVKK Aydınlatma Metni',
                style: TextStyle(color: Sandik.text90, fontSize: 13)),
            SelectableText(_kvkkUrl,
                style: const TextStyle(color: Sandik.amber, fontSize: 12)),
            const SizedBox(height: 10),
            const Text('Gizlilik Politikası',
                style: TextStyle(color: Sandik.text90, fontSize: 13)),
            SelectableText(_privacyUrl,
                style: const TextStyle(color: Sandik.amber, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat',
                style: TextStyle(color: Sandik.amber)),
          ),
        ],
      ),
    );
  }

  void _showLegalDoc(String title, String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Sandik.surface2,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Belgenin tamamı aşağıdaki adreste yayınlanıyor:',
              style: TextStyle(color: Sandik.text58, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              url,
              style: const TextStyle(color: Sandik.amber, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat',
                style: TextStyle(color: Sandik.amber)),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    final missingTerms = !_termsAccepted;
    final missingConsent = !_consentAccepted;
    if (missingTerms || missingConsent) {
      setState(() {
        _termsError = missingTerms;
        _consentError = missingConsent;
      });
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
      final err = authState.error;
      final msg = err?.toString() ?? '';
      // AuthService "e-posta doğrulama gerekli" durumunu exception ile
      // sinyalize ediyor — bu bir başarı akışı, hata değil. Success
      // dialog gösterip LoginScreen'e email pre-filled dönüyoruz.
      final isPendingConfirmation = msg.contains('doğrulama maili') ||
          msg.contains('E-posta adresinize doğrulama') ||
          msg.contains('Kayıt işlemi tamamlandı');
      if (isPendingConfirmation) {
        await showAppSuccess(
          context,
          title: 'Kayıt başarılı',
          message: msg,
        );
        if (!mounted) return;
        await AuthService.instance.saveEmailForLogin(_emailCtrl.text.trim());
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      showAppError(context, err);
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

    // UA2 fix: popUntil ile LoginScreen'e dönmek AuthGate'in onboarding
    // kontrolünü atlatıyordu (yeni kayıt → user var → AuthGate hemen
    // Main'e gönderiyordu, OnboardingScreen.isCompleted() future'ı
    // ile yarış). Şimdi popUntil yapmıyoruz; AuthGate akışı sürdürür.
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
              const SizedBox(height: 4),
              Text(
                'Sandığına hoş geldin.',
                style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Sandik.gold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Birkaç adımda hesabını oluştur.',
                style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36),
              ),
              const SizedBox(height: 24),

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
                    )),
                validator: (v) =>
                    v == null ? 'Şifre gerekli' : AuthService.validatePassword(v),
              ),
              const SizedBox(height: 14),

              // Şifre tekrar
              TextFormField(
                controller: _passConfirmCtrl,
                obscureText: _obscure,
                style: GoogleFonts.dmSans(color: Sandik.text90),
                decoration: Sandik.inputDecoration('',
                    labelText: 'Şifre Tekrar',
                    errorText: (_passConfirmCtrl.text.isNotEmpty &&
                            _passConfirmCtrl.text != _passCtrl.text)
                        ? 'Şifreler eşleşmiyor'
                        : null,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.lock_outline,
                          color: Sandik.text36, size: 20),
                    )),
                validator: (v) =>
                    v != _passCtrl.text ? 'Şifreler eşleşmiyor' : null,
              ),
              const SizedBox(height: 28),

              // ── Yasal Koşullar (birleşik — UC1 fix) ──────────────────────
              // Disclaimer + KVKK aydınlatma + 18+ yaş tek onay altında.
              // Detaylar linkler üzerinden tam metinle ulaşılabilir.
              _LegalConsentBox(
                icon: Icons.gavel_rounded,
                title: 'Yasal Koşullar',
                versionLabel: 'v$disclaimerVersion',
                bodyText:
                    '• 18 yaşından büyük olduğunu beyan edersin.\n'
                    '• Uygulama yatırım tavsiyesi değildir; gösterilen '
                    'fiyatlar ve teknik analiz bilgi amaçlıdır.\n'
                    '• Kayıt ile Kullanım Koşulları, KVKK Aydınlatma '
                    'Metni ve Gizlilik Politikası\'nı kabul etmiş '
                    'sayılırsın.',
                checkboxLabel:
                    'Yasal Koşulları, KVKK Aydınlatma Metni\'ni ve '
                    '18+ olduğumu kabul ediyorum.',
                linkLabel: 'Belgeleri incele',
                linkUrl: _termsUrl,
                accepted: _termsAccepted,
                error: _termsError,
                errorMessage:
                    'Devam etmek için yasal koşulları kabul etmelisin.',
                onToggle: () => setState(() {
                  _termsAccepted = !_termsAccepted;
                  if (_termsAccepted) _termsError = false;
                }),
                onShowText: () => _showLegalLinks(),
              ),
              const SizedBox(height: 14),

              // ── Açık Rıza — Yurt Dışı Veri Aktarımı (ayrı kalır) ─────────
              // KVKK Madde 9(1) zorunluluğu: açık rıza birleştirilemez.
              _LegalConsentBox(
                icon: Icons.public_rounded,
                title: 'Açık Rıza — Yurt Dışı Veri Aktarımı',
                bodyText:
                    'Verilerin Supabase (ABD) ve Firebase (ABD/Küresel) '
                    'üzerinde saklanacak. KVKK Madde 9(1) gereği açık rıza '
                    'gerekir. İstediğin zaman geri çekebilirsin (hesap silme).',
                checkboxLabel:
                    'Verilerimin yurt dışına aktarılmasına açık rıza '
                    'veriyorum.',
                linkLabel: 'Açık Rıza Metni',
                linkUrl: _consentUrl,
                accepted: _consentAccepted,
                error: _consentError,
                errorMessage:
                    'Devam etmek için yurt dışı aktarım rızasını '
                    'kabul etmelisin.',
                onToggle: () => setState(() {
                  _consentAccepted = !_consentAccepted;
                  if (_consentAccepted) _consentError = false;
                }),
                onShowText: () =>
                    _showLegalDoc('Açık Rıza Metni', _consentUrl),
              ),
              const SizedBox(height: 24),

              // Kayıt Ol butonu — GestureDetector(opaque) instead of
              // CupertinoButton: on iOS release the CupertinoButton was
              // losing the gesture arena to the enclosing Scrollable.
              // Button stays tappable even when incomplete so we can tell
              // the user WHICH requirement is missing.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isLoading
                    ? null
                    : () {
                        final missing = _firstMissingRequirement();
                        if (missing != null) {
                          showAppError(context, AuthException(missing));
                          return;
                        }
                        _register();
                      },
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

/// Yasal onay kutusu — başlık + metin + (opsiyonel) tam metin linki + checkbox.
/// Hata durumunda kırmızı border ve hata mesajı gösterir.
class _LegalConsentBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? versionLabel;
  final String bodyText;
  final String checkboxLabel;
  final String? linkLabel;
  final String? linkUrl;
  final VoidCallback? onShowText;
  final bool accepted;
  final bool error;
  final String errorMessage;
  final VoidCallback onToggle;

  const _LegalConsentBox({
    required this.icon,
    required this.title,
    this.versionLabel,
    required this.bodyText,
    required this.checkboxLabel,
    this.linkLabel,
    this.linkUrl,
    this.onShowText,
    required this.accepted,
    required this.error,
    required this.errorMessage,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error
            ? Sandik.loss.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: error
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
              Icon(icon, size: 16, color: Sandik.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Sandik.amber,
                  ),
                ),
              ),
              if (versionLabel != null)
                Text(
                  versionLabel!,
                  style: GoogleFonts.dmSans(
                      fontSize: 10, color: Sandik.text36),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            bodyText,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: Sandik.text58,
              height: 1.6,
            ),
          ),
          if (onShowText != null && linkLabel != null) ...[
            const SizedBox(height: 6),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onShowText,
              child: Text(
                linkLabel!,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: Sandik.amber,
                  decoration: TextDecoration.underline,
                  decorationColor: Sandik.amber,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accepted ? Sandik.amber : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accepted
                          ? Sandik.amber
                          : (error ? Sandik.loss : Sandik.text36),
                      width: 2,
                    ),
                  ),
                  child: accepted
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Sandik.dark)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    checkboxLabel,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: error ? Sandik.loss : Sandik.text58,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (error) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: Sandik.loss),
            ),
          ],
        ],
      ),
    );
  }
}
