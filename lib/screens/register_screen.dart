import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
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
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/kullanici_adi_denetimi.dart';
import '../services/supabase_service.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_config_service.dart';
import '../services/yasal_metin_katalogu.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'legal_doc_screen.dart';
import 'otp_verification_screen.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../l10n/l10n.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  /// Yalnız widget testi: `AuthService.register` yerine çağrılır (Supabase
  /// testte ayağa kalkmaz). Tek onay kutusu bayrağının (`tek_onay_kutusu`)
  /// kayıt isteğini DEĞİŞTİRMEDİĞİ bununla kanıtlanır — iki yolda aynı
  /// argümanlar, onay alanı yok (onay kaydı OTP sonrası `kabulKaydet`).
  @visibleForTesting
  static Future<void> Function({
    required String email,
    required String displayName,
    required String password,
  })? kayitIstegiTesti;

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

  // Belge (onaylansın ya da yalnız okunsun) en az bir kez AÇILDI mı. Yasal
  // onay kaydına (`YasalOnayService`, 0102) kanıt olarak gider; ekranda
  // hiçbir şeyi değiştirmez. Tek kutuda belge yalnız okunur (onay dönüşü
  // yok), "açıldı" bilgisinin tek kaynağı bu.
  bool _termsDocOpened = false;
  bool _consentDocOpened = false;
  bool _kvkkDocOpened = false;
  bool _privacyDocOpened = false;

  /// Tek onay kutusu (Sadeleştirme 2 madde 1, bayrak `tek_onay_kutusu`,
  /// varsayılan KAPALI — hukuki onay bekler). Açıkken iki kutu tek cümleli
  /// tek kutuya iner ama durum yine İKİ bayraktır: kutu `_termsAccepted` ile
  /// `_consentAccepted`'ı birlikte açar/kapar. Kapı (`_canSubmit`,
  /// `_register`, `_eksikleriGoster`) ve OTP sonrası onay kaydı bu iki
  /// bayrağı eskisi gibi okur; kayıt biçimi ve onay sayısı değişmez.
  /// Ekran açılışında bir kez okunur: form doldurulurken Remote Config
  /// yenilenirse kutu sayısı göz önünde değişmesin.
  late final bool _tekOnay = RemoteConfigService.instance.tekOnayKutusu;
  late final TapGestureRecognizer _kosullarBaglantisi = TapGestureRecognizer()
    ..onTap = _openTermsDoc;
  late final TapGestureRecognizer _kvkkBaglantisi = TapGestureRecognizer()
    ..onTap = _openKvkkDoc;
  late final TapGestureRecognizer _rizaBaglantisi = TapGestureRecognizer()
    ..onTap = _openConsentDoc;
  bool _emailTouched = false; // focus kaybedince hata göster
  // "Kayıt ol"a eksik formla basıldı mı? Basıldıysa her alan kendi hatasını
  // gösterir (yalnızca ilk eksik bir uyarıda değil) ve şifre kuralları
  // karşılanmayanı kırmızıyla işaretler (kullanıcı kararı 2026-09-29).
  bool _gonderimDenendi = false;
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
    if (_tekOnay && !(_termsAccepted && _consentAccepted)) {
      return context.l10n.tekOnayGerekli;
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

  // Kural serviste (sunucunun reddedeceği biçim); ekran yalnızca sorar.
  bool _isValidEmail(String v) => AuthService.eMailGecerliMi(v);

  /// Eksik formla basıldığında TÜM alanların hatasını birden aç: tek bir
  /// uyarı yalnız ilk eksiği söylüyordu, kullanıcı düzeltip tekrar basınca
  /// sıradakini öğreniyordu.
  void _eksikleriGoster() {
    setState(() {
      _gonderimDenendi = true;
      _emailTouched = true;
      _termsError = !_termsAccepted;
      _consentError = !_consentAccepted;
    });
    _formKey.currentState?.validate();
  }

  @override
  void initState() {
    super.initState();
    // Kayıt hunisinin ilk adımı (F11). Yalnızca olay; form davranışı aynı.
    AnalyticsService.instance.logSignupStep('form_opened');
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
    _kosullarBaglantisi.dispose();
    _kvkkBaglantisi.dispose();
    _rizaBaglantisi.dispose();
    super.dispose();
  }

  /// Yasal Koşullar belgesini "sona kadar okuyup onaylama" akışıyla aç.
  /// Kullanıcı belgeyi sonuna kadar kaydırıp "Okudum ve onaylıyorum" butonuna
  /// basınca dönüş `true` olur; checkbox otomatik işaretlenir.
  Future<void> _openTermsDoc() async {
    _termsDocOpened = true;
    final confirmed = await pushGuarded<bool>(
      context,
      adaptiveRoute(
        // Tek kutuda belge yalnız okunur: onay kutunun kendisidir; belgeden
        // dönen "onayladım" iki bayraktan yalnız birini açıp kutuyu yarım
        // bırakırdı.
        //
        // Başlık 2026-10-04'e kadar "Yasal Koşullar & KVKK Aydınlatma"ydı
        // ama sayfa YALNIZ Koşulları gösteriyordu; KVKK Aydınlatma Metni
        // kayıt ekranından hiç açılamıyordu. KVKK artık kendi bağlantısıyla
        // açılır ([_openKvkkDoc]).
        builder: (_) => LegalDocScreen(
          title: context.l10n.yasalBelgeKosullar,
          icon: Icons.gavel_rounded,
          blocks: LegalDocs.terms,
          confirmMode: !_tekOnay,
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

  /// KVKK Aydınlatma Metni — yalnız okunur (iki düzende de). Aydınlatma
  /// bir bilgilendirmedir, ayrı bir onay dönüşü yok: kutu cümlesi onu
  /// adıyla anar ve kutuyu işaretlemek "okudum" beyanıdır. Açıldığı bilgisi
  /// onay kaydına kanıt notu olarak gider (`KayitOnayBaglami`).
  Future<void> _openKvkkDoc() async {
    _kvkkDocOpened = true;
    await pushGuarded<void>(
      context,
      adaptiveRoute(
        // const değil: `LegalDocs.kvkk` verinin ülkesini çalışma anında
        // doldurur (köprü sürümü).
        builder: (_) => LegalDocScreen(
          title: context.l10n.yasalBelgeKvkk,
          icon: Icons.privacy_tip_outlined,
          blocks: LegalDocs.kvkk,
        ),
      ),
    );
  }

  /// Gizlilik Politikası — yalnız okunur (iki düzende de). 1.1'de "açık
  /// rıza" bağlantısı bu belgeyi açıyordu; 1.2'de o bağlantı Açık Rıza
  /// Metni'ne geçince Gizlilik kayıt ekranından açılamaz olacaktı. İki
  /// kutulu düzende kutu metni onu adıyla anıyor, Koşullar §1 her düzende
  /// atıf yapıyor → ayrı bir okuma bağlantısı (kutu metnine dokunmaz,
  /// hash'i değiştirmez).
  Future<void> _openPrivacyDoc() async {
    _privacyDocOpened = true;
    await pushGuarded<void>(
      context,
      adaptiveRoute(
        builder: (_) => LegalDocScreen(
          title: context.l10n.yasalBelgeGizlilik,
          icon: Icons.shield_outlined,
          blocks: LegalDocs.privacy,
        ),
      ),
    );
  }

  /// Açık Rıza Metni'ni (yurt dışı veri aktarımı) onay akışıyla aç.
  ///
  /// 1.2 (2026-10-04, "webdekiyle eşleyelim"): web'de 2026-05'ten beri ayrı
  /// bir "Açık Rıza Metni" (`legal/tr/ACIK_RIZA_METNI.md`) vardı ama bu
  /// bağlantı "Açık Rıza: Yurt Dışı Veri Aktarımı" başlığıyla Gizlilik
  /// Politikası'nı açıyordu. Artık açık rıza belgesinin kendisini açar.
  Future<void> _openConsentDoc() async {
    _consentDocOpened = true;
    final confirmed = await pushGuarded<bool>(
      context,
      adaptiveRoute(
        // const değil: `LegalDocs.acikRiza` verinin ülkesini çalışma anında
        // doldurur (köprü sürümü).
        builder: (_) => LegalDocScreen(
          title: context.l10n.yasalBelgeAcikRiza,
          icon: Icons.public_rounded,
          blocks: LegalDocs.acikRiza,
          confirmMode: !_tekOnay,
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
    // Kullanıcının GÖRDÜĞÜ onay metinleri — OTP doğrulanınca (oturum o an
    // açılır) yasal onay kaydı bununla yazılır. `await`'ten önce: context
    // ve ülke gönderim anındaki hâliyle.
    final kayitOnayi = KayitOnayBaglami(
      tekKutu: _tekOnay,
      dil: context.l10n.localeName,
      kutuUlkesi: SunucuSecimi.instance.aktifOrNull?.ulke ??
          (_tekOnay
              ? context.l10n.tekOnayUlkeBilinmiyor
              : KayitKutuMetni.rizaUlkeBilinmiyor),
      belgeDegiskenleri: LegalDocs.yerTutucuDegerleri(),
      kosulBelgesiAcildi: _termsDocOpened,
      rizaBelgesiAcildi: _consentDocOpened,
      kvkkBelgesiAcildi: _kvkkDocOpened,
      gizlilikBelgesiAcildi: _privacyDocOpened,
    );
    try {
      // Confirm-email AÇIK — register signUp() çağırır ama session
      // vermez. Kullanıcı OTP doğrulanmadan authProvider hâlâ null.
      // Sadece AuthService.register çağırıp OtpVerificationScreen'e
      // yönlendiriyoruz. Disclaimer/onboarding OTP sonrasına ertelenir
      // (_AuthGate zaten user != null olduğunda ilgili akışa yönlendirir).
      final testIstegi = RegisterScreen.kayitIstegiTesti;
      if (testIstegi != null) {
        await testIstegi(
          email: emailForOtp,
          displayName: _nameCtrl.text,
          password: _passCtrl.text,
        );
      } else {
        await AuthService.instance.register(
          email: emailForOtp,
          displayName: _nameCtrl.text,
          password: _passCtrl.text,
        );
      }
      // `register` döndüyse sunucu doğrulama kodunu gönderdi (confirm-email
      // açık). `mounted`'tan önce: ekran kapanmış olsa da kod gitti.
      // "Yeni kod iste" tekrar gönderimidir, huniye ayrı adım yazılmaz.
      unawaited(AnalyticsService.instance.logSignupStep('otp_sent'));

      if (!mounted) return;
      await AuthService.instance.saveEmailForLogin(emailForOtp);
      if (!mounted) return;
      // Register success dialog → OTP ekranına push.
      // OTP ekranı verify sonrası authProvider'ı invalidate edip
      // popUntil first yapıyor; _AuthGate devralır.
      await pushGuarded(
        context,
        adaptiveRoute<void>(
          builder: (_) => OtpVerificationScreen(
            email: emailForOtp,
            kayitOnayi: kayitOnayi,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Tek onay cümlesi, üç belge bağlantısı cümlenin İÇİNDE (Koşullar,
  /// KVKK Aydınlatma, açık rıza → Gizlilik). Metin tek l10n anahtarından
  /// gelir (dile göre bağlantıların yeri değişir); yer tutuculara ayraç
  /// verilip bölünür, her ayracın yerine bağlantı girer. 2026-10-04'e kadar
  /// "Yasal Koşulları, KVKK Aydınlatma Metni" TEK bağlantıydı ve yalnız
  /// Koşulları açıyordu; okunan cümle aynı kaldı (hash aynı).
  InlineSpan _tekOnayCumlesi(BuildContext context) {
    const kosulAyraci = '\u0001';
    const kvkkAyraci = '\u0003';
    const rizaAyraci = '\u0002';
    final ham =
        context.l10n.tekOnayCumle(kosulAyraci, kvkkAyraci, rizaAyraci);
    final baglanti = TextStyle(
      color: context.c.amberText,
      decoration: TextDecoration.underline,
      decorationColor: context.c.amberText,
    );
    final parcalar = <InlineSpan>[];
    var i = 0;
    for (final m in RegExp('[$kosulAyraci$kvkkAyraci$rizaAyraci]')
        .allMatches(ham)) {
      if (m.start > i) parcalar.add(TextSpan(text: ham.substring(i, m.start)));
      final (metin, tanima) = switch (m[0]) {
        kosulAyraci => (
            context.l10n.tekOnayKosullarBaglanti,
            _kosullarBaglantisi
          ),
        kvkkAyraci => (context.l10n.tekOnayKvkkBaglanti, _kvkkBaglantisi),
        _ => (context.l10n.tekOnayRizaBaglanti, _rizaBaglantisi),
      };
      parcalar.add(TextSpan(
        text: metin,
        style: baglanti,
        recognizer: tanima,
      ));
      i = m.end;
    }
    if (i < ham.length) parcalar.add(TextSpan(text: ham.substring(i)));
    return TextSpan(children: parcalar);
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
            // İlk denemeden sonra alanlar yazdıkça yeniden denetlenir:
            // düzeltilen alanın hatası kalkar, kalan eksik görünür kalır.
            autovalidateMode: _gonderimDenendi
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
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
                    // Kurallar alanın altındaki canlı listede; burada
                    // yalnız listede olmayan üst sınır (72 bayt) kalır.
                    errorText: AuthService.sifreKurallari(_passCtrl.text)
                            .sinirIcinde
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
                // Kural ihlali listede görünür; validator yalnız alanı
                // kırmızı çerçeveye alır (metni tekrar etmeden).
                validator: (v) {
                  final hata = AuthService.validatePassword(v ?? '');
                  if (hata == null) return null;
                  return AuthService.sifreKurallari(v ?? '').sinirIcinde
                      ? ''
                      : hata;
                },
              ),
              if (_passCtrl.text.isNotEmpty || _gonderimDenendi)
                _SifreKurallariListesi(
                  sifre: _passCtrl.text,
                  eksikleriVurgula: _gonderimDenendi,
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

              if (_tekOnay)
                // ── Tek onay (bayrak `tek_onay_kutusu`) ─────────────────────
                // İki kutunun cümleleri tek cümlede; iki belgeye cümle içi
                // bağlantı. İşaretlemek iki onayı birlikte verir (bkz.
                // `_tekOnay`). Hata kutunun altında, eski desenle.
                YasalOnayKutusu(
                  icon: Icons.gavel_rounded,
                  title: context.l10n.tekOnayBaslik,
                  versionLabel: 'v$disclaimerVersion',
                  // Ülke bağlanılan projeden (köprü sürümü), eski açık rıza
                  // kutusuyla aynı kaynak — bkz. LegalDocs._ulke.
                  bodyText: context.l10n.tekOnayAciklama(
                      SunucuSecimi.instance.aktifOrNull?.ulke ??
                          context.l10n.tekOnayUlkeBilinmiyor),
                  checkboxLabel:
                      YasalMetinKatalogu.tekKutuCumlesi(context.l10n),
                  checkboxSpan: _tekOnayCumlesi(context),
                  // Cümle Gizlilik Politikası'nı anmıyor (cümleye bağlantı
                  // eklemek kutu metnini, dolayısıyla hash'ini değiştirirdi);
                  // okuma bağlantısı kutunun altında.
                  ekLinkLabel: context.l10n.yasalBelgeGizlilik,
                  onEkLink: _openPrivacyDoc,
                  accepted: _termsAccepted && _consentAccepted,
                  error: _termsError || _consentError,
                  errorMessage: context.l10n.tekOnayGerekli,
                  onToggle: () => setState(() {
                    final yeni = !(_termsAccepted && _consentAccepted);
                    _termsAccepted = yeni;
                    _consentAccepted = yeni;
                    if (yeni) {
                      _termsError = false;
                      _consentError = false;
                    }
                  }),
                )
              else ...[
                // ── Yasal Koşullar (birleşik — UC1 fix) ──────────────────────
                // Disclaimer + KVKK aydınlatma + 18+ yaş tek onay altında.
                // Detaylar linkler üzerinden tam metinle ulaşılabilir.
                // Metinler `KayitKutuMetni`'nde (yasal metin kataloğu):
                // gösterilen ile veritabanına hash'lenen aynı sabit.
                YasalOnayKutusu(
                  icon: Icons.gavel_rounded,
                  title: KayitKutuMetni.kosulBaslik,
                  versionLabel: 'v$disclaimerVersion',
                  bodyText: KayitKutuMetni.kosulGovde,
                  checkboxLabel: KayitKutuMetni.kosulCumle,
                  linkLabel: _termsDocConfirmed
                      ? 'Belgeyi tekrar aç'
                      : 'Belgeyi aç ve onayla',
                  // Kutu cümlesi KVKK Aydınlatma Metni'ni adıyla anıyor;
                  // 2026-10-04'e kadar ekrandan açılamıyordu.
                  ekLinkLabel: context.l10n.yasalBelgeKvkk,
                  onEkLink: _openKvkkDoc,
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
                YasalOnayKutusu(
                  icon: Icons.public_rounded,
                  title: KayitKutuMetni.rizaBaslik,
                  // Ülke bağlanılan projeden (köprü sürümü) — bkz. LegalDocs._ulke.
                  bodyText: KayitKutuMetni.rizaGovde(
                      SunucuSecimi.instance.aktifOrNull?.ulke ??
                          KayitKutuMetni.rizaUlkeBilinmiyor),
                  checkboxLabel: KayitKutuMetni.rizaCumle,
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
                  // Kutu metnindeki "Gizlilik Politikası" (bkz. _openPrivacyDoc).
                  ekLinkLabel: context.l10n.yasalBelgeGizlilik,
                  onEkLink: _openPrivacyDoc,
                ),
              ],
              const SizedBox(height: 24),

              // Kayıt Ol butonu — GestureDetector(opaque) instead of
              // CupertinoButton: on iOS release the CupertinoButton was
              // losing the gesture arena to the enclosing Scrollable.
              // Button stays tappable even when incomplete so we can tell
              // the user WHICH requirement is missing.
              SandikBasma(
                behavior: HitTestBehavior.opaque,
                onTap: isLoading
                    ? null
                    : () {
                        final missing = _firstMissingRequirement();
                        if (missing != null) {
                          _eksikleriGoster();
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

/// Şifre kuralları, yazarken canlı: karşılanan yeşil tik, karşılanmayan
/// boş daire; "Kayıt ol"a eksik basıldıktan sonra karşılanmayan kırmızı.
/// Kural kaynağı `AuthService.sifreKurallari` — sunucuya gidecek kuralla
/// aynı, ekranda ayrı bir kopya yok.
class _SifreKurallariListesi extends StatelessWidget {
  final String sifre;
  final bool eksikleriVurgula;

  const _SifreKurallariListesi({
    required this.sifre,
    required this.eksikleriVurgula,
  });

  @override
  Widget build(BuildContext context) {
    final k = AuthService.sifreKurallari(sifre);
    Widget satir(bool tamam, String metin) {
      final renk = tamam
          ? context.c.gain
          : (eksikleriVurgula ? context.c.loss : context.c.text36);
      return Padding(
        padding: const EdgeInsets.only(top: SandikSpace.xs),
        child: Row(
          children: [
            Icon(
              tamam
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: renk,
            ),
            const SizedBox(width: SandikSpace.xs2),
            Expanded(
              child: Text(
                metin,
                style: context.t.bodySmall?.copyWith(color: renk),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(
          left: SandikSpace.smd, top: SandikSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          satir(k.uzunluk, context.l10n.sifreKuralUzunluk),
          satir(k.harf, context.l10n.sifreKuralHarf),
          satir(k.rakam, context.l10n.sifreKuralRakam),
        ],
      ),
    );
  }
}

/// Yasal onay kutusu — başlık + metin + (opsiyonel) tam metin linki + checkbox.
/// Hata durumunda kırmızı border ve hata mesajı gösterir.
///
/// Public (2026-10-04): yeniden onay kapısı (`YasalOnayKapisiScreen`) kayıt
/// kutularını AYNI görünüşle gösterir — Apple/Google ile ilk kez gelen
/// kullanıcı kayıt formundaki taahhütlerin aynısını görür.
class YasalOnayKutusu extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? versionLabel;
  final String bodyText;
  final String checkboxLabel;

  /// Verilirse kutu cümlesi bununla çizilir (cümle içi bağlantılar için);
  /// [checkboxLabel] yine düz metin karşılığıdır (erişilebilirlik etiketi).
  final InlineSpan? checkboxSpan;
  final String? linkLabel;
  final VoidCallback? onShowText;

  /// İkinci belge bağlantısı (Koşullar kutusunda KVKK Aydınlatma Metni).
  final String? ekLinkLabel;
  final VoidCallback? onEkLink;
  final bool accepted;
  final bool error;
  final String errorMessage;
  final VoidCallback onToggle;
  /// Kullanıcı belgeyi açıp sonuna kadar okuduysa `true`. Yalnızca bağlantı
  /// etiketini ("tekrar aç") etkiler; işaretlemeyi KİLİTLEMEZ.
  final bool docConfirmed;

  const YasalOnayKutusu({
    super.key,
    required this.icon,
    required this.title,
    this.versionLabel,
    required this.bodyText,
    required this.checkboxLabel,
    this.checkboxSpan,
    this.linkLabel,
    this.onShowText,
    this.ekLinkLabel,
    this.onEkLink,
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
          if (onEkLink != null && ekLinkLabel != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: SandikTouch.minSize,
              onPressed: onEkLink,
              child: Text(
                ekLinkLabel!,
                style: context.t.bodySmall?.copyWith(
                  color: context.c.amberText,
                  decoration: TextDecoration.underline,
                  decorationColor: context.c.amberText,
                ),
              ),
            ),
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
                  child: checkboxSpan != null
                      ? Text.rich(
                          checkboxSpan!,
                          style: context.t.titleSmall?.copyWith(
                            color: error ? context.c.loss : context.c.text58,
                          ),
                        )
                      : Text(
                          docConfirmed
                              ? checkboxLabel
                              : '$checkboxLabel\n(Önce belgeyi oku)',
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
