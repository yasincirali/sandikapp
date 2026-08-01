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
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'legal_doc_screen.dart';
import 'otp_verification_screen.dart';

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
  // Belge açılıp sona kadar okunup "onaylıyorum" tıklanınca true olur.
  // Bu true olmadan ilgili checkbox'ı tıklayarak işaretleyemez.
  bool _termsDocConfirmed = false;
  bool _consentDocConfirmed = false;
  bool _emailTouched = false; // focus kaybedince hata göster
  bool _submitting = false; // register çağrısı + başarı dialog süresince



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

  /// Yasal Koşullar belgesini "sona kadar okuyup onaylama" akışıyla aç.
  /// Kullanıcı belgeyi sonuna kadar kaydırıp "Okudum ve onaylıyorum" butonuna
  /// basınca dönüş `true` olur; checkbox otomatik işaretlenir.
  Future<void> _openTermsDoc() async {
    final confirmed = await Navigator.push<bool>(
      context,
      adaptiveRoute(
        builder: (_) => const LegalDocScreen(
          title: 'Yasal Koşullar & KVKK Aydınlatma',
          icon: Icons.gavel_rounded,
          blocks: LegalDocs.terms,
          confirmMode: true,
          confirmButtonLabel: 'Okudum ve onaylıyorum',
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _termsDocConfirmed = true;
        _termsAccepted = true;
        _termsError = false;
      });
    }
  }

  /// Açık Rıza (yurt dışı veri aktarımı) belgesini onay akışıyla aç.
  Future<void> _openConsentDoc() async {
    final confirmed = await Navigator.push<bool>(
      context,
      adaptiveRoute(
        builder: (_) => const LegalDocScreen(
          title: 'Açık Rıza — Yurt Dışı Veri Aktarımı',
          icon: Icons.public_rounded,
          blocks: LegalDocs.privacy,
          confirmMode: true,
          confirmButtonLabel: 'Okudum ve açık rıza veriyorum',
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _consentDocConfirmed = true;
        _consentAccepted = true;
        _consentError = false;
      });
    }
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

    setState(() => _submitting = true);
    final emailForOtp = _emailCtrl.text.trim().toLowerCase();
    try {
      // Confirm-email AÇIK — register signUp() çağırır ama session
      // vermez. Kullanıcı OTP doğrulanmadan authProvider hâlâ null.
      // Sadece AuthService.register çağırıp OtpVerificationScreen'e
      // yönlendiriyoruz. Disclaimer/onboarding OTP sonrasına ertelenir
      // (_AuthGate zaten user != null olduğunda ilgili akışa yönlendirir).
      await AuthService.instance.register(
        email: emailForOtp,
        displayName: _nameCtrl.text,
        password: _passCtrl.text,
      );

      if (!mounted) return;
      await AuthService.instance.saveEmailForLogin(emailForOtp);
      if (!mounted) return;
      // Register success dialog → OTP ekranına push.
      // OTP ekranı verify sonrası authProvider'ı invalidate edip
      // popUntil first yapıyor; _AuthGate devralır.
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => OtpVerificationScreen(email: emailForOtp),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // isLoading: register çağrısı devam ediyor VEYA başarı dialog süresince
    // buton devre dışı kalsın.
    final isLoading = ref.watch(authProvider).isLoading || _submitting;

    return CupertinoPageScaffold(
      backgroundColor: Sandik.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Sandik.background,
        border: null,
        middle: Text('Kayıt Ol',
            style: context.t.headlineSmall?.copyWith(
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
                style: context.t.headlineLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Sandik.gold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Birkaç adımda hesabını oluştur.',
                style: context.t.bodyMedium?.copyWith(color: Sandik.text36),
              ),
              const SizedBox(height: 24),

              // Ad Soyad
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: context.t.bodyLarge?.copyWith(color: Sandik.text90),
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
                style: context.t.bodyLarge?.copyWith(color: Sandik.text90),
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
                style: context.t.bodyLarge?.copyWith(color: Sandik.text90),
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
                style: context.t.bodyLarge?.copyWith(color: Sandik.text90),
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
                linkLabel: _termsDocConfirmed
                    ? 'Belgeyi tekrar aç'
                    : 'Belgeyi aç ve onayla',
                accepted: _termsAccepted,
                docConfirmed: _termsDocConfirmed,
                error: _termsError,
                errorMessage: _termsDocConfirmed
                    ? 'Devam etmek için yasal koşulları kabul etmelisin.'
                    : 'Önce belgeyi açıp sona kadar okumalısın.',
                onToggle: () => setState(() {
                  _termsAccepted = !_termsAccepted;
                  if (_termsAccepted) _termsError = false;
                }),
                onShowText: _openTermsDoc,
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
                linkLabel: _consentDocConfirmed
                    ? 'Belgeyi tekrar aç'
                    : 'Belgeyi aç ve onayla',
                accepted: _consentAccepted,
                docConfirmed: _consentDocConfirmed,
                error: _consentError,
                errorMessage: _consentDocConfirmed
                    ? 'Devam etmek için yurt dışı aktarım rızasını '
                        'kabul etmelisin.'
                    : 'Önce belgeyi açıp sona kadar okumalısın.',
                onToggle: () => setState(() {
                  _consentAccepted = !_consentAccepted;
                  if (_consentAccepted) _consentError = false;
                }),
                onShowText: _openConsentDoc,
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
                    borderRadius: BorderRadius.circular(SandikRadius.md),
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
                          style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Sandik.dark),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Zaten hesabınız var mı? Giriş yapın',
                  style: context.t.bodyLarge?.copyWith(color: Sandik.amber),
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
  final VoidCallback? onShowText;
  final bool accepted;
  final bool error;
  final String errorMessage;
  final VoidCallback onToggle;
  /// Kullanıcı bağlı belgeyi açıp sonuna kadar okuyup onayladıysa `true`
  /// olur. `false` iken checkbox tıklamayla değiştirilemez; sadece belgeyi
  /// aç butonu (linkLabel) çalışır.
  final bool docConfirmed;

  const _LegalConsentBox({
    required this.icon,
    required this.title,
    this.versionLabel,
    required this.bodyText,
    required this.checkboxLabel,
    this.linkLabel,
    this.onShowText,
    required this.accepted,
    required this.error,
    required this.errorMessage,
    required this.onToggle,
    this.docConfirmed = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error
            ? Sandik.loss.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(SandikRadius.md),
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
                  style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Sandik.amber,
                  ),
                ),
              ),
              if (versionLabel != null)
                Text(
                  versionLabel!,
                  style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0, color: Sandik.text36),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            bodyText,
            style: context.t.bodySmall?.copyWith(
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
                style: context.t.bodySmall?.copyWith(
                  color: Sandik.amber,
                  decoration: TextDecoration.underline,
                  decorationColor: Sandik.amber,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              if (!docConfirmed) {
                // Belge henüz açılıp onaylanmadı → belgeyi aç.
                onShowText?.call();
                return;
              }
              onToggle();
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accepted
                        ? Sandik.amber
                        : (docConfirmed
                            ? Colors.transparent
                            : Colors.white.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                      color: accepted
                          ? Sandik.amber
                          : (error
                              ? Sandik.loss
                              : (docConfirmed
                                  ? Sandik.text36
                                  : Sandik.text36
                                      .withValues(alpha: 0.4))),
                      width: 2,
                    ),
                  ),
                  child: accepted
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Sandik.dark)
                      : (docConfirmed
                          ? null
                          : Icon(Icons.lock_outline_rounded,
                              size: 12,
                              color: Sandik.text36.withValues(alpha: 0.7))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    docConfirmed
                        ? checkboxLabel
                        : '$checkboxLabel\n(Önce belgeyi okuyun)',
                    style: context.t.titleSmall?.copyWith(
                      color: error ? Sandik.loss : Sandik.text58,
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
              style: context.t.bodySmall?.copyWith(color: Sandik.loss),
            ),
          ],
        ],
      ),
    );
  }
}
