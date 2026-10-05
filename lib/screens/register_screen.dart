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

  // ── Yasal onaylar (okuma sadeleştirme, kullanıcı kararı 2026-10-05) ──────
  // *"Tüm hepsini içinden onaylatmak çok uzun bir process gibi oldu."*
  // 1.3'te beş metnin beşi sonuna kadar okunup sonunda onaylanıyor, kutu
  // ancak ondan sonra açılıyordu. 1.4'ten beri üç ayrı eylem:
  // 1. Açık Rıza Metni — sonuna kadar okunur, rıza metnin SONUNDAKİ
  //    düğmeyle verilir (`zorunluOkumaAc`). Rıza başka beyanla paketlenmez:
  //    kutu cümlesinde açık rıza YOK.
  // 2. Yatırım Uyarısı — tam metni okunup onaylanır (kısa; ekrana sığarsa
  //    düğme baştan açık — aynı bileşen).
  // 3. Tek kutu — Kullanım Koşulları'nın kabulü (sözleşme: tek açık eylem)
  //    + 18+ + Gizlilik Politikası ve KVKK Aydınlatma Metni ile
  //    "bilgilendirildim" (bilgilendirme belgeleri onaylatılmaz; KVKK Kurumu
  //    aydınlatmanın rıza gibi alınmasını önermez). Üç belge listede ve
  //    kutu cümlesinde bağlantıdır, salt okunur açılır.
  // Kutu artık metinlere KİLİTLİ DEĞİL: Koşulların kabulü rızanın okunmasına
  // bağlı değil; üçü birbirinden bağımsız eylemlerdir. "Kayıt ol" üçünü de
  // ister ve eksik olanı adıyla söyler.
  //
  // Geçmiş: UC1 dört kutuyu (yatırım uyarısı, KVKK, 18+, yurt dışı aktarım)
  // ikiye indirdi — bilişsel yük; aktarım açık rızası KVKK m.9(1) gereği
  // ayrı kutuda kaldı. Sadeleştirme 2 (2026-10-04) ikisini tek cümleli tek
  // kutuda birleştirdi (rıza dahil; bayrak `tek_onay_kutusu`). Zorunlu
  // okuma (2026-10-04, bayrak `zorunlu_okuma`) beş metni de okutup kutuyu
  // onlara kilitledi. 2026-10-05: iki bayrak kalktı, ardından bu
  // sadeleştirme — rıza yeniden kutudan ayrıldı, bu kez kendi metninin
  // sonuna.

  /// Kutu işaretli mi (kutu 1.1, `kayit_tek_kutu`).
  bool _kutuIsaretli = false;
  bool _kutuHatasi = false;

  // Bağlantı belgesi en az bir kez AÇILDI mı. Onay kaydına (`belge_acildi`)
  // kanıt notu olarak gider; satırda hafif "Açıldı" izi bırakır.
  bool _termsDocOpened = false;
  bool _kvkkDocOpened = false;
  bool _privacyDocOpened = false;

  /// Sonuna kadar okunup sonunda onaylanan türler (Açık Rıza, uyarı).
  final Set<String> _onaylananlar = {};

  /// "Kayıt ol"a okunması gereken metinler eksikken basıldı.
  bool _belgeHatasi = false;

  /// Sonuna kadar okunacak metinler: Açık Rıza Metni + yatırım uyarısı.
  List<ZorunluMetin> _metinler(AppLocalizations l) =>
      ZorunluMetin.liste(l, yatirimUyarisiDahil: true);

  List<ZorunluMetin> _eksikMetinler(AppLocalizations l) => [
        for (final m in _metinler(l))
          if (!_onaylananlar.contains(m.tur)) m,
      ];

  bool get _belgelerTamam => _eksikMetinler(context.l10n).isEmpty;

  late final YasalKutuBaglantilari _kutuBaglantilari =
      YasalKutuBaglantilari(_belgeyiAc);

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
      _kutuIsaretli;

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
    if (!_kutuIsaretli) return context.l10n.tekOnayGerekli;
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
      _kutuHatasi = !_kutuIsaretli;
      _belgeHatasi = !_belgelerTamam;
    });
    _formKey.currentState?.validate();
  }

  /// Kutu: Koşulların kabulü + 18+ + bilgilendirildim. Metinlere kilitli
  /// değil (bkz. yukarıdaki karar notu).
  void _kutuDegistir() => setState(() {
        _kutuIsaretli = !_kutuIsaretli;
        if (_kutuIsaretli) _kutuHatasi = false;
      });

  /// [m]'yi (Açık Rıza Metni ya da yatırım uyarısı) zorunlu okumada açar;
  /// sonuna kadar okunup sonunda onaylanırsa listeye işlenir.
  Future<void> _zorunluOku(ZorunluMetin m) async {
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
    _kutuBaglantilari.dispose();
    super.dispose();
  }

  /// Bilgilendirme/kabul belgesini (Koşullar, Gizlilik, KVKK) SALT OKUNUR
  /// açar — listedeki satır ve kutu cümlesindeki bağlantı aynı yolu izler.
  /// Okuma şartı ve belge sonu onayı 2026-10-05'te kalktı (1.3'te üçü de
  /// zorunlu okumadaydı). "Açıldı" kanıt notu açılışta konur.
  Future<void> _belgeyiAc(YasalBelge b) async {
    setState(() {
      switch (b) {
        case YasalBelge.kosullar:
          _termsDocOpened = true;
        case YasalBelge.gizlilik:
          _privacyDocOpened = true;
        case YasalBelge.kvkk:
          _kvkkDocOpened = true;
        case YasalBelge.acikRiza:
          break;
      }
    });
    await belgeyiAc(context, b);
  }

  bool _acildi(YasalBelge b) => switch (b) {
        YasalBelge.kosullar => _termsDocOpened,
        YasalBelge.gizlilik => _privacyDocOpened,
        YasalBelge.kvkk => _kvkkDocOpened,
        YasalBelge.acikRiza => false,
      };

  Future<void> _register() async {
    final eksikKutu = !_kutuIsaretli;
    final eksikBelge = !_belgelerTamam;
    if (eksikKutu || eksikBelge) {
      setState(() {
        _kutuHatasi = eksikKutu;
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

  /// Yasal metin listesi — kapıdaki listeyle aynı satır ([YasalBelgeSatiri]).
  /// Sıra Ayarlar ve kapıyla aynı: Koşullar, Gizlilik, KVKK (bağlantı),
  /// Açık Rıza Metni ve Yatırım Uyarısı (sonuna kadar okunur; amber "Sonuna
  /// kadar oku ve onayla" notu). Okunması gerekenler eksikken "Kayıt ol"a
  /// basılırsa çerçeve kırmızıya döner ve eksikler adıyla yazılır.
  Widget _belgeListesi(BuildContext context) {
    final l = context.l10n;
    final metinler = _metinler(l);
    final eksik = _eksikMetinler(l);
    final hata = _belgeHatasi && eksik.isNotEmpty;
    final satirlar = <Widget>[
      for (final b in YasalBelge.kutuylaAlinanlar)
        YasalBelgeSatiri(
          adaylar: ZorunluMetin.belge(l, b).adaylar,
          surum: l.yasalBelgeSurum(b.surum),
          tamam: _acildi(b),
          tamamEtiketi: l.yasalBelgeAcildi,
          onayli: false,
          onTap: () => _belgeyiAc(b),
        ),
      for (final m in metinler)
        YasalBelgeSatiri(
          adaylar: m.adaylar,
          surum: l.yasalBelgeSurum(m.surum),
          tamam: _onaylananlar.contains(m.tur),
          tamamEtiketi: l.zorunluOkumaOnaylandi,
          bekleyenEtiketi: l.zorunluOkumaSatirEtiketi,
          onTap: () => _zorunluOku(m),
        ),
    ];
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
          for (var i = 0; i < satirlar.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.c.overlay),
            satirlar[i],
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

              // ── Yasal metinler: bağlantılar + sonuna kadar okunanlar ───
              _belgeListesi(context),
              const SizedBox(height: SandikSpace.md2),

              // ── Tek onay (kutu 1.1) ──────────────────────────────────
              // Koşulların kabulü + 18+ + Gizlilik/KVKK ile bilgilendirildim;
              // üç belge adı cümle içinde bağlantı (listedekiyle aynı salt
              // okunur açılış). Açık rıza bu kutuda DEĞİL — Açık Rıza
              // Metni'nin sonunda verilir. Hata kutunun altında.
              YasalOnayKutusu(
                icon: Icons.gavel_rounded,
                title: context.l10n.tekOnayBaslik,
                versionLabel: 'v${YasalMetinKatalogu.kutuSurumu}',
                // Ülke bağlanılan projeden (köprü sürümü) — bkz.
                // LegalDocs._ulke.
                bodyText: context.l10n.tekOnayAciklama(
                    SunucuSecimi.instance.aktifOrNull?.ulke ??
                        context.l10n.tekOnayUlkeBilinmiyor),
                checkboxLabel: YasalMetinKatalogu.tekKutuCumlesi(context.l10n),
                checkboxSpan: _kutuBaglantilari.span(context),
                accepted: _kutuIsaretli,
                error: _kutuHatasi,
                errorMessage: context.l10n.tekOnayGerekli,
                onToggle: _kutuDegistir,
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

/// Tek kutunun cümlesindeki üç belge bağlantısı (Kullanım Koşulları,
/// Gizlilik Politikası, KVKK Aydınlatma Metni) — kayıt ekranı ve yeniden
/// onay kapısı AYNI cümleyi aynı bağlantılarla çizer. Metin tek l10n
/// anahtarından gelir (dile göre bağlantıların yeri değişir); yer
/// tutuculara ayraç verilip bölünür, her ayracın yerine bağlantı girer.
/// Okunan düz metin [YasalMetinKatalogu.tekKutuCumlesi] ile harfi harfine
/// aynı (hash'lenen metin). Tanıyıcıların ömrü sahibin `dispose`'unda.
class YasalKutuBaglantilari {
  YasalKutuBaglantilari(this._ac);

  final Future<void> Function(YasalBelge) _ac;

  late final TapGestureRecognizer _kosullar = TapGestureRecognizer()
    ..onTap = () => _ac(YasalBelge.kosullar);
  late final TapGestureRecognizer _gizlilik = TapGestureRecognizer()
    ..onTap = () => _ac(YasalBelge.gizlilik);
  late final TapGestureRecognizer _kvkk = TapGestureRecognizer()
    ..onTap = () => _ac(YasalBelge.kvkk);

  InlineSpan span(BuildContext context) {
    const kosulAyraci = '\u0001';
    const gizlilikAyraci = '\u0002';
    const kvkkAyraci = '\u0003';
    final l = context.l10n;
    final ham = l.tekOnayCumle(kosulAyraci, gizlilikAyraci, kvkkAyraci);
    final baglanti = TextStyle(
      color: context.c.amberText,
      decoration: TextDecoration.underline,
      decorationColor: context.c.amberText,
    );
    final parcalar = <InlineSpan>[];
    var i = 0;
    for (final m in RegExp('[$kosulAyraci$gizlilikAyraci$kvkkAyraci]')
        .allMatches(ham)) {
      if (m.start > i) parcalar.add(TextSpan(text: ham.substring(i, m.start)));
      final (metin, tanima) = switch (m[0]) {
        kosulAyraci => (l.tekOnayKosullarBaglanti, _kosullar),
        gizlilikAyraci => (l.tekOnayGizlilikBaglanti, _gizlilik),
        _ => (l.tekOnayKvkkBaglanti, _kvkk),
      };
      parcalar.add(TextSpan(text: metin, style: baglanti, recognizer: tanima));
      i = m.end;
    }
    if (i < ham.length) parcalar.add(TextSpan(text: ham.substring(i)));
    return TextSpan(children: parcalar);
  }

  void dispose() {
    _kosullar.dispose();
    _gizlilik.dispose();
    _kvkk.dispose();
  }
}

/// Yasal onay kutusu — başlık + metin + checkbox. Hata durumunda kırmızı
/// border ve hata mesajı gösterir.
///
/// 2026-10-05: kutunun altındaki belge bağlantıları (`linkLabel`,
/// `onShowText`, `ekLinkLabel`, `onEkLink`) ve "(Önce belgeyi oku)" eki
/// silindi — yalnız zorunlu okuma kapalıyken (iki kutulu / bağlantılı
/// düzen) kullanılıyorlardı. Aynı gün (okuma sadeleştirme) kilit de kalktı
/// (`docConfirmed`, `kilitNotu`): kutu artık metinlerin okunmasını
/// beklemez — Koşulların kabulü rızanın okunmasından bağımsız bir eylemdir.
///
/// Public (2026-10-04): yeniden onay kapısı (`YasalOnayKapisiScreen`) kayıt
/// kutusunu AYNI görünüşle gösterir — Apple/Google ile ilk kez gelen
/// kullanıcı kayıt formundaki taahhüdün aynısını görür.
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
          // Erişilebilirlik (2026-10-05): kutu kendi çizimimiz; durumunu
          // ekran okuyucuya bildirmezse TalkBack/VoiceOver onu kutu olarak
          // okumaz ve yasal onay sesle verilemez. Cümledeki belge
          // bağlantıları ayrı düğüm olarak kalır (container).
          Semantics(
            container: true,
            checked: accepted,
            onTap: onToggle,
            child: GestureDetector(
              // 2026-09: "belgeyi açıp sonuna kadar kaydır" zorunluluğu
              // kaldırıldı. 2026-10-04 (bayrak `zorunlu_okuma`) TÜM metinler
              // için geri geldi ve kutu metinlere kilitlendi. 2026-10-05
              // (okuma sadeleştirme): sonuna kadar okuma yalnız Açık Rıza
              // Metni'nde ve uyarıda kaldı; kutu kilitsiz.
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
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(SandikRadius.sm),
                      border: Border.all(
                        color: accepted
                            ? context.c.amberText
                            : (error ? context.c.loss : context.c.text36),
                        width: 2,
                      ),
                    ),
                    child: accepted
                        ? Icon(Icons.check_rounded,
                            size: 14, color: context.c.onAmber)
                        : null,
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
