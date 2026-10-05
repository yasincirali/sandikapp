import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart'
    show
        Colors,
        Divider,
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
import '../services/yasal_metin_katalogu.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'legal_doc_screen.dart';
import 'otp_verification_screen.dart';
import '../widgets/custom_loading_indicator.dart';
import '../widgets/social_sign_in_buttons.dart';
import '../widgets/zorunlu_okuma.dart';
import '../l10n/l10n.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  /// Yalnız widget testi: `AuthService.register` yerine çağrılır (Supabase
  /// testte ayağa kalkmaz). Kayıt isteğinde onay alanı olmadığı bununla
  /// kanıtlanır (onay kaydı OTP sonrası `kabulKaydet`; tek onay kutusu
  /// isteği değiştirmedi).
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

  // Belge (onaylansın ya da yalnız okunsun) en az bir kez AÇILDI mı. Yasal
  // onay kaydına (`YasalOnayService`, 0102) kanıt olarak gider; ekranda
  // hiçbir şeyi değiştirmez.
  bool _termsDocOpened = false;
  bool _consentDocOpened = false;
  bool _kvkkDocOpened = false;
  bool _privacyDocOpened = false;

  // Tek onay kutusu (Sadeleştirme 2 madde 1, 2026-10-04): iki kutu tek
  // cümleli tek kutuya indi ama durum yine İKİ bayraktır: kutu
  // `_termsAccepted` ile `_consentAccepted`'ı birlikte açar/kapar. Kapı
  // (`_canSubmit`, `_register`, `_eksikleriGoster`) bu iki bayrağı okur.
  // Remote Config bayrağı `tek_onay_kutusu` ve iki kutulu eski düzen
  // 2026-10-05'te kalktı (avukat görüşü YAPMAN_GEREKENLER "Sadeleştirme 2.
  // parti").
  //
  // Zorunlu okuma (kullanıcı kararı 2026-10-04: "Özeti değil hepsini
  // okutmalıyız. Zorunlu okutup en sonda onaylatarak ilerleyelim."; bayrak
  // `zorunlu_okuma` 2026-10-05'te kalktı). Kutunun üstünde beş metin
  // listelenir —
  // Koşullar, Gizlilik, KVKK Aydınlatma, Açık Rıza Metni ve yatırım
  // uyarısının TAM metni. Her biri sonuna kadar okunup EN SONUNDA
  // onaylanır (`zorunluOkumaAc`); hepsi onaylanmadan kutu işaretlenmez ve
  // "Kayıt ol" ilerlemez.
  //
  // Kutu ayrı kalır, son belgenin onayıyla kendiliğinden işaretlenmez:
  // kutu cümlesi (18+, yurt dışı aktarım AÇIK RIZASI) bir belge onayı değil,
  // kullanıcının kendi beyanıdır. KVKK m.9 açık rızası "özgür iradeyle,
  // açık bir eylemle" verilir; başka bir düğmenin yan etkisi olarak
  // işaretlenen kutu bu eylemi zayıflatırdı. Kutu cümlesi baştan görünür,
  // belgeler bitene kadar kilitlidir ve neden kilitli olduğunu söyler.

  /// Zorunlu okumada sonuna kadar okunup sonunda onaylanan türler.
  final Set<String> _onaylananlar = {};

  /// "Kayıt ol"a ya da kutuya belgeler eksikken basıldı.
  bool _belgeHatasi = false;

  List<ZorunluMetin> _metinler(AppLocalizations l) =>
      ZorunluMetin.liste(l, yatirimUyarisiDahil: true);

  List<ZorunluMetin> _eksikMetinler(AppLocalizations l) => [
        for (final m in _metinler(l))
          if (!_onaylananlar.contains(m.tur)) m,
      ];

  bool get _belgelerTamam => _eksikMetinler(context.l10n).isEmpty;

  late final TapGestureRecognizer _kosullarBaglantisi = TapGestureRecognizer()
    ..onTap = () => _belgeyiOku(YasalBelge.kosullar);
  late final TapGestureRecognizer _kvkkBaglantisi = TapGestureRecognizer()
    ..onTap = () => _belgeyiOku(YasalBelge.kvkk);
  late final TapGestureRecognizer _rizaBaglantisi = TapGestureRecognizer()
    ..onTap = () => _belgeyiOku(YasalBelge.acikRiza);
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
      _belgelerTamam &&
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
    // Zorunlu okuma: hangi metnin okunmadığını adıyla söyle (girdi kuralı
    // istemcide — kullanıcı neyin eksik olduğunu basmadan önce bilir).
    final eksikMetinler = _eksikMetinler(context.l10n);
    if (eksikMetinler.isNotEmpty) {
      return context.l10n.zorunluOkumaEksik(
          eksikMetinler.map((m) => m.adaylar.first).join(', '));
    }
    if (!(_termsAccepted && _consentAccepted)) {
      return context.l10n.tekOnayGerekli;
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
      _belgeHatasi = !_belgelerTamam;
    });
    _formKey.currentState?.validate();
  }

  /// Kutu değişimi — zorunlu okumada belgeler bitmeden kutu işaretlenmez;
  /// dokunuş belge listesini hata durumuna alır (hangi metnin eksik olduğu
  /// orada yazar).
  void _kutuDegistir(VoidCallback degistir) {
    if (!_belgelerTamam) {
      setState(() => _belgeHatasi = true);
      return;
    }
    setState(degistir);
  }

  /// [m]'yi zorunlu okumada açar; sonuna kadar okunup sonunda onaylanırsa
  /// listeye işlenir. "Açıldı" kanıt notu eski bayraklara da yazılır.
  Future<void> _zorunluOku(ZorunluMetin m) async {
    switch (m.tur) {
      case YasalTur.kosullar:
        _termsDocOpened = true;
      case YasalTur.gizlilik:
        _privacyDocOpened = true;
      case YasalTur.kvkk:
        _kvkkDocOpened = true;
      case YasalTur.acikRiza:
        _consentDocOpened = true;
    }
    final sonuc = await zorunluOkumaAc(context, m);
    if (!mounted || sonuc == null) return;
    if (sonuc.onaylandi && sonuc.sonunaKadarOkundu) {
      setState(() {
        _onaylananlar.add(m.tur);
        if (_belgelerTamam) _belgeHatasi = false;
      });
    }
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

  /// Cümle içi belge bağlantısı: belge zorunlu okumada açılır (listedeki
  /// satırla aynı akış). 2026-10-05'e kadar zorunlu okuma kapalıyken
  /// Koşullar ve Açık Rıza "sona kadar oku ve onayla" sayfasıyla
  /// (`LegalDocScreen.confirmMode`), KVKK ve Gizlilik yalnız okunur
  /// açılıyordu; o yollar bayraklarla silindi. Bağlantı geçmişi: Koşullar
  /// bağlantısı 2026-10-04'e kadar "Yasal Koşullar & KVKK Aydınlatma"
  /// başlığıyla YALNIZ Koşulları açıyordu; "açık rıza" bağlantısı 1.1'de
  /// Gizlilik Politikası'nı açıyordu, 1.2'den beri Açık Rıza Metni'ni.
  void _belgeyiOku(YasalBelge b) =>
      _zorunluOku(ZorunluMetin.belge(context.l10n, b));

  Future<void> _register() async {
    final missingTerms = !_termsAccepted;
    final missingConsent = !_consentAccepted;
    final eksikBelge = !_belgelerTamam;
    if (missingTerms || missingConsent || eksikBelge) {
      setState(() {
        _termsError = missingTerms;
        _consentError = missingConsent;
        _belgeHatasi = eksikBelge;
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
      dil: context.l10n.localeName,
      kutuUlkesi: SunucuSecimi.instance.aktifOrNull?.ulke ??
          context.l10n.tekOnayUlkeBilinmiyor,
      belgeDegiskenleri: LegalDocs.yerTutucuDegerleri(),
      kosulBelgesiAcildi: _termsDocOpened,
      rizaBelgesiAcildi: _consentDocOpened,
      kvkkBelgesiAcildi: _kvkkDocOpened,
      gizlilikBelgesiAcildi: _privacyDocOpened,
      sonunaKadarOkunanlar: {..._onaylananlar},
      yatirimUyarisiOnaylandi:
          _onaylananlar.contains(YasalTur.yatirimUyarisi),
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

  /// Zorunlu okumanın metin listesi — kapıdaki listeyle aynı satır
  /// ([YasalBelgeSatiri]). Eksik varken "Kayıt ol"a ya da kutuya basılırsa
  /// çerçeve kırmızıya döner ve eksik metinler adıyla yazılır.
  Widget _belgeListesi(BuildContext context) {
    final l = context.l10n;
    final metinler = _metinler(l);
    final eksik = _eksikMetinler(l);
    final hata = _belgeHatasi && eksik.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: hata ? context.c.loss.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: hata
              ? context.c.loss.withValues(alpha: 0.5)
              : context.c.overlay,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SandikSpace.md, SandikSpace.md,
                SandikSpace.md, SandikSpace.xs),
            child: Text(
              l.zorunluOkumaBelgelerBaslik,
              style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.amberText,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
            child: Text(
              '${l.zorunluOkumaBelgelerAciklama} '
              '${l.zorunluOkumaSayac(metinler.length - eksik.length, metinler.length)}',
              style: context.t.bodySmall?.copyWith(
                color: context.c.text58,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.sm),
          for (var i = 0; i < metinler.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.c.overlay),
            YasalBelgeSatiri(
              adaylar: metinler[i].adaylar,
              surum: l.yasalBelgeSurum(metinler[i].surum),
              tamam: _onaylananlar.contains(metinler[i].tur),
              tamamEtiketi: l.zorunluOkumaOnaylandi,
              onTap: () => _zorunluOku(metinler[i]),
            ),
          ],
          if (hata)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.md, SandikSpace.xs, SandikSpace.md, SandikSpace.md),
              child: Text(
                l.zorunluOkumaEksik(
                    eksik.map((m) => m.adaylar.first).join(', ')),
                style: context.t.bodySmall?.copyWith(color: context.c.loss),
              ),
            ),
        ],
      ),
    );
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

              // ── Zorunlu okuma: önce metinler, sonra kutu ───────────────
              _belgeListesi(context),
              const SizedBox(height: SandikSpace.md2),

              // ── Tek onay ──────────────────────────────────────────────
              // İki eski kutunun cümleleri tek cümlede; belgelere cümle içi
              // bağlantı. İşaretlemek iki onayı birlikte verir. Hata kutunun
              // altında. Belgeler yukarıdaki listede → kutuda ek bağlantı yok
              // (cümle Gizlilik Politikası'nı anmıyor; bağlantı eklemek kutu
              // metnini, dolayısıyla hash'ini değiştirirdi).
              YasalOnayKutusu(
                icon: Icons.gavel_rounded,
                title: context.l10n.tekOnayBaslik,
                versionLabel: 'v$disclaimerVersion',
                // Ülke bağlanılan projeden (köprü sürümü) — bkz.
                // LegalDocs._ulke.
                bodyText: context.l10n.tekOnayAciklama(
                    SunucuSecimi.instance.aktifOrNull?.ulke ??
                        context.l10n.tekOnayUlkeBilinmiyor),
                checkboxLabel: YasalMetinKatalogu.tekKutuCumlesi(context.l10n),
                checkboxSpan: _tekOnayCumlesi(context),
                accepted: _termsAccepted && _consentAccepted,
                docConfirmed: _belgelerTamam,
                kilitNotu: context.l10n.zorunluOkumaKutuKilitli,
                error: _termsError || _consentError,
                errorMessage: context.l10n.tekOnayGerekli,
                onToggle: () => _kutuDegistir(() {
                  final yeni = !(_termsAccepted && _consentAccepted);
                  _termsAccepted = yeni;
                  _consentAccepted = yeni;
                  if (yeni) {
                    _termsError = false;
                    _consentError = false;
                  }
                }),
              ),
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

/// Yasal onay kutusu — başlık + metin + checkbox. Hata durumunda kırmızı
/// border ve hata mesajı gösterir.
///
/// 2026-10-05: kutunun altındaki belge bağlantıları (`linkLabel`,
/// `onShowText`, `ekLinkLabel`, `onEkLink`) ve "(Önce belgeyi oku)" eki
/// silindi — yalnız zorunlu okuma kapalıyken (iki kutulu / bağlantılı
/// düzen) kullanılıyorlardı. Belgeler artık kutunun üstündeki listede.
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
  final bool accepted;
  final bool error;
  final String errorMessage;
  final VoidCallback onToggle;
  /// Kullanıcı belgeyi açıp sonuna kadar okuduysa `true`. Görünüşü
  /// (kilit ikonu, bağlantı etiketi "tekrar aç") etkiler; işaretlemeyi
  /// kutu KİLİTLEMEZ — kilit çağıranın [onToggle]'ındadır (zorunlu okumada
  /// kayıt ekranı belgeler bitmeden kutuyu değiştirmez).
  final bool docConfirmed;

  /// [docConfirmed] `false` iken kutu cümlesinin altında neden kilitli
  /// olduğunu söyleyen satır (zorunlu okuma; cümle hash'lenen metinle aynı
  /// kalır, ek almaz).
  final String kilitNotu;

  const YasalOnayKutusu({
    super.key,
    required this.icon,
    required this.title,
    this.versionLabel,
    required this.bodyText,
    required this.checkboxLabel,
    this.checkboxSpan,
    required this.accepted,
    required this.error,
    required this.errorMessage,
    required this.onToggle,
    this.docConfirmed = true,
    required this.kilitNotu,
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
          const SizedBox(height: 14),
          GestureDetector(
            // 2026-09: "belgeyi açıp sonuna kadar kaydır" zorunluluğu
            // kaldırıldı. Belge bir dokunuş uzakta (bağlantı hemen üstte);
            // kutuyu işaretlemek onay için yeterli. Dört düz kutudan daha
            // yavaş bir ilk kullanım, hukuki bir kazanç sağlamıyordu.
            // 2026-10-04 (bayrak `zorunlu_okuma`) kullanıcı kararıyla geri
            // geldi, bu kez TÜM metinler için ve kilit çağıranın
            // `onToggle`'ında: "Özeti değil hepsini okutmalıyız."
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
                          checkboxLabel,
                          style: context.t.titleSmall?.copyWith(
                            color: error ? context.c.loss : context.c.text58,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (!docConfirmed) ...[
            const SizedBox(height: SandikSpace.xs2),
            Text(
              kilitNotu,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
          ],
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
