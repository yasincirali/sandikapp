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
import '../models/kullanici_adi.dart';
import '../providers/auth_provider.dart';
import '../services/sunucu_secimi.dart';
import '../services/auth_service.dart';
import '../services/kullanici_adi_denetimi.dart';
import '../services/supabase_service.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'legal_doc_screen.dart';
import 'otp_verification_screen.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../l10n/l10n.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  /// Kullanıcı adı benzersizliği FORMDA denetlenir (kullanıcı kararı
  /// 2026-09-28): adını burada veren kullanıcıya giriş kapısı bir daha
  /// sorulmaz. Oturum henüz yok; anonim RPC (0080) kullanılır.
  late final KullaniciAdiDenetimi _adDenetimi;
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
      _adDenetimi.kaydedilebilir &&
      _isValidEmail(_emailCtrl.text) &&
      AuthService.validatePassword(_passCtrl.text) == null &&
      _passCtrl.text == _passConfirmCtrl.text &&
      _termsAccepted &&
      _consentAccepted;

  /// First missing requirement, in the order the user filled the form.
  /// null → form is valid.
  String? _firstMissingRequirement() {
    if (_nameCtrl.text.trim().isEmpty) {
      return context.l10n.registerUsernameMissing;
    }
    if (KullaniciAdi.bicimDenetle(_nameCtrl.text) != null) {
      return context.l10n.kullaniciAdiHataBicim;
    }
    final adRet = _adRetMetni();
    if (adRet != null) return adRet;
    if (!_isValidEmail(_emailCtrl.text)) return context.l10n.registerEmailInvalid;
    final passError = AuthService.validatePassword(_passCtrl.text);
    if (passError != null) return passError;
    if (_passCtrl.text != _passConfirmCtrl.text) {
      return context.l10n.registerPasswordsMismatch;
    }
    if (!_termsAccepted) return context.l10n.termsMustAccept;
    if (!_consentAccepted) {
      return context.l10n.consentMustAccept;
    }
    return null;
  }

  /// Sunucu bu adı reddettiyse kullanıcı dilinde nedeni; yoksa null.
  /// Biçim ayrı ele alınır (anında, ağ yok).
  String? _adRetMetni() {
    final d = _adDenetimi.durum;
    if (d == null ||
        d == KullaniciAdiSonuc.uygun ||
        d == KullaniciAdiSonuc.bicim) {
      return null;
    }
    return switch (d) {
      KullaniciAdiSonuc.uygunsuz => context.l10n.kullaniciAdiHataUygunsuz,
      KullaniciAdiSonuc.ayrilmis => context.l10n.kullaniciAdiHataAyrilmis,
      KullaniciAdiSonuc.alinmis => context.l10n.kullaniciAdiHataAlinmis,
      _ => context.l10n.kullaniciAdiHataBilinmiyor,
    };
  }

  bool _isValidEmail(String v) {
    final parts = v.split('@');
    return parts.length == 2 && parts[0].isNotEmpty && parts[1].contains('.');
  }

  @override
  void initState() {
    super.initState();
    _adDenetimi = KullaniciAdiDenetimi(
      sor: SupabaseService.instance.kullaniciAdiKayittaUygunMu,
    )..addListener(_rebuild);
    _nameCtrl.addListener(() => _adDenetimi.metinDegisti(_nameCtrl.text));
    _nameCtrl.addListener(_rebuild);
    _emailCtrl.addListener(_rebuild);
    _passCtrl.addListener(_rebuild);
    _passConfirmCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _adDenetimi.dispose();
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
    final confirmed = await pushGuarded<bool>(
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
    final confirmed = await pushGuarded<bool>(
      context,
      adaptiveRoute(
        // const değil: `LegalDocs.privacy` verinin ülkesini çalışma anında
        // doldurur (köprü sürümü).
        builder: (_) => LegalDocScreen(
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
      await pushGuarded(
        context,
        adaptiveRoute<void>(
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
      backgroundColor: context.c.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: context.c.background,
        border: null,
        middle: Text(context.l10n.register,
            style: context.t.headlineSmall?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.c.text90)),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: context.c.text58),
        ),
      ),
      child: Material(
        color: context.c.background,
        child: SafeArea(
          // Bkz. login_screen: grup olmadan iOS "şifreyi kaydet?" istemi
          // görünmez ve yeni şifre Keychain'e yazılmaz.
          child: AutofillGroup(
            child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            children: [
              const SizedBox(height: 4),
              Text(
                context.l10n.registerWelcome,
                style: context.t.headlineLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.c.gold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.registerSubtitle,
                style: context.t.bodyMedium?.copyWith(color: context.c.text36),
              ),
              const SizedBox(height: 24),

              // Kullanıcı adı (0079, 2026-09-28) — eskiden "Ad Soyad"dı.
              // Görünen ad artık kullanıcı adıdır (ortak da bunu görür);
              // iki ayrı alan sormak yerine kayıtta doğrudan o istenir.
              // Biçim anında; uygunluk/benzersizlik yazarken anonim RPC ile
              // (0080, 2026-09-28) — eskiden OTP sonrasına kalıyor, alınmış
              // ad giriş kapısında ikinci kez soruluyordu. OTP sonrası
              // kayıt yine sunucuya sorar (yarış: iki kişi aynı anda aynı
              // ad); o nadir durumda kapı yedek olarak kalır.
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                maxLength: KullaniciAdi.enUzun,
                // Klavyede "Return" yerine "İleri" çıkar; 4 alanlı formda
                // her alandan sonra klavyeyi kapatıp elle dokunma zorunluluğu
                // ciddi sürtünmeydi.
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                decoration: context.inputDecoration('',
                    labelText: context.l10n.kullaniciAdiEtiket,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.alternate_email_rounded,
                          color: context.c.text36, size: 20),
                    ),
                    suffixIcon: _adDenetimi.soruluyor
                        ? const Padding(
                            padding: EdgeInsets.all(SandikSpace.md2),
                            child: CustomLoadingIndicator(size: 16),
                          )
                        : null).copyWith(
                  // Sunucu onayladıysa kural yerine yeşil onay; reddettiyse
                  // hata satırı — kullanıcı "Kaydol"a basmadan görür.
                  helperText: _adDenetimi.durum == KullaniciAdiSonuc.uygun
                      ? context.l10n.kullaniciAdiUygun
                      : context.l10n.kullaniciAdiKurallar,
                  helperStyle: _adDenetimi.durum == KullaniciAdiSonuc.uygun
                      ? context.t.bodySmall?.copyWith(color: context.c.gain)
                      : null,
                  helperMaxLines: 2,
                  errorText: _adRetMetni(),
                  counterText: '',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.registerUsernameMissing
                    : (KullaniciAdi.bicimDenetle(v) != null
                        ? context.l10n.kullaniciAdiHataBicim
                        : _adRetMetni()),
              ),
              const SizedBox(height: 14),

              // E-posta
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                onEditingComplete: () {
                  setState(() => _emailTouched = true);
                  FocusScope.of(context).nextFocus();
                },
                onTapOutside: (_) => setState(() => _emailTouched = true),
                decoration: context.inputDecoration('',
                    labelText: context.l10n.email,
                    errorText: (_emailTouched && _emailCtrl.text.isNotEmpty && !_isValidEmail(_emailCtrl.text))
                        ? context.l10n.emailInvalid
                        : null,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.email_outlined,
                          color: context.c.text36, size: 20),
                    )),
                validator: (v) =>
                    (v == null || !_isValidEmail(v)) ? context.l10n.emailInvalid : null,
              ),
              const SizedBox(height: 14),

              // Şifre
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                // `newPassword` (password DEĞİL): iOS'un güçlü şifre önerme
                // ve Keychain'e kaydetme akışını bu tetikler.
                autofillHints: const [AutofillHints.newPassword],
                autocorrect: false,
                enableSuggestions: false,
                style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                decoration: context.inputDecoration('',
                    labelText: context.l10n.password,
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
                    )),
                validator: (v) =>
                    v == null ? context.l10n.passwordRequired : AuthService.validatePassword(v),
              ),
              const SizedBox(height: 14),

              // Şifre tekrar
              TextFormField(
                controller: _passConfirmCtrl,
                obscureText: _obscure,
                // Son alan → "Bitti" ve doğrudan gönderim. Kullanıcı klavyeyi
                // kapatıp butonu aramak zorunda kalmasın.
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                autocorrect: false,
                enableSuggestions: false,
                style: context.t.bodyLarge?.copyWith(color: context.c.text90),
                decoration: context.inputDecoration('',
                    labelText: context.l10n.passwordRepeat,
                    errorText: (_passConfirmCtrl.text.isNotEmpty &&
                            _passConfirmCtrl.text != _passCtrl.text)
                        ? context.l10n.passwordsMismatch
                        : null,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.lock_outline,
                          color: context.c.text36, size: 20),
                    )),
                validator: (v) =>
                    v != _passCtrl.text ? context.l10n.passwordsMismatch : null,
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
                errorMessage: 'Devam etmek için yasal koşulları kabul etmelisin.',
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
                    // Ülke bağlanılan projeden (köprü sürümü) — bkz. LegalDocs._ulke.
                    'Verilerin Supabase (${SunucuSecimi.instance.aktifOrNull?.ulke ?? 'yurt dışı'}) ve Firebase (ABD/Küresel) '
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
                errorMessage: 'Devam etmek için yurt dışı aktarım rızasını '
                    'kabul etmelisin.',
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
                        ? context.c.amberFill.withValues(alpha: 0.45)
                        : context.c.amberFill.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    border: Border.all(
                        color: context.c.amberFill.withValues(alpha: 0.60)),
                    boxShadow: [
                      BoxShadow(
                        color: context.c.amberFill.withValues(alpha: 0.28),
                        blurRadius: 18,
                        spreadRadius: -4,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: isLoading
                      ? const CustomLoadingIndicator(size: 20)
                      : Text(
                          context.l10n.register,
                          style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.c.onAmber),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              // Sosyal girişte OTP adımı yok; e-posta sağlayıcıdan doğrulanmış
              // gelir. Yasal onay kapısı AuthGate'te — bu yolda da sorulur.
              const SocialSignInButtons(),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  context.l10n.haveAccountSignIn,
                  style: context.t.bodyLarge?.copyWith(color: context.c.amberText),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
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
  /// Kullanıcı belgeyi açıp sonuna kadar okuduysa `true`. Yalnızca bağlantı
  /// etiketini ("tekrar aç") etkiler; işaretlemeyi KİLİTLEMEZ.
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
            ? context.c.loss.withValues(alpha: 0.08)
            : context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: error
              ? context.c.loss.withValues(alpha: 0.5)
              : context.c.overlay,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: context.c.amberText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.c.amberText,
                  ),
                ),
              ),
              if (versionLabel != null)
                Text(
                  versionLabel!,
                  style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0, color: context.c.text36),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            bodyText,
            style: context.t.bodySmall?.copyWith(
              color: context.c.text58,
              height: 1.6,
            ),
          ),
          if (onShowText != null && linkLabel != null) ...[
            const SizedBox(height: 6),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: SandikTouch.minSize,
              onPressed: onShowText,
              child: Text(
                linkLabel!,
                style: context.t.bodySmall?.copyWith(
                  color: context.c.amberText,
                  decoration: TextDecoration.underline,
                  decorationColor: context.c.amberText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            // 2026-09: "belgeyi açıp sonuna kadar kaydır" zorunluluğu
            // kaldırıldı. Belge bir dokunuş uzakta (bağlantı hemen üstte);
            // kutuyu işaretlemek onay için yeterli. Dört düz kutudan daha
            // yavaş bir ilk kullanım, hukuki bir kazanç sağlamıyordu.
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: SandikMotion.of(context, const Duration(milliseconds: 150)),
                  curve: SandikMotion.enter,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accepted
                        ? context.c.amberText
                        : (docConfirmed
                            ? Colors.transparent
                            : context.c.overlay),
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                      color: accepted
                          ? context.c.amberText
                          : (error
                              ? context.c.loss
                              : (docConfirmed
                                  ? context.c.text36
                                  : context.c.text36
                                      .withValues(alpha: 0.4))),
                      width: 2,
                    ),
                  ),
                  child: accepted
                      ? Icon(Icons.check_rounded,
                          size: 14, color: context.c.onAmber)
                      : (docConfirmed
                          ? null
                          : Icon(Icons.lock_outline_rounded,
                              size: 12,
                              color: context.c.text36.withValues(alpha: 0.7))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    docConfirmed
                        ? checkboxLabel
                        : '$checkboxLabel\n(Önce belgeyi okuyun)',
                    style: context.t.titleSmall?.copyWith(
                      color: error ? context.c.loss : context.c.text58,
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
              style: context.t.bodySmall?.copyWith(color: context.c.loss),
            ),
          ],
        ],
      ),
    );
  }
}
