import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/cihaz_provider.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/crash_reporter.dart';
import '../services/disclaimer_service.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../utils/friendly_error.dart';
import '../widgets/custom_loading_indicator.dart';
import '../l10n/l10n.dart';

/// Kodun ne için istendiği.
enum OtpAmaci {
  /// Kayıt sonrası e-posta doğrulama (Kayıt ekranından push edilir).
  kayit,

  /// Kayıtlı olmayan cihazda giriş (0098). `_AuthGate` kök ekran olarak
  /// gösterir; kodu ekran açılınca kendisi ister, doğrulanınca kapı açılır.
  cihaz,
}

/// Register (veya login) sonrası email doğrulama ekranı.
///
/// 6 haneli OTP input + "Doğrula" + timer + "Kodu yeniden gönder".
/// Timer expire olunca kutular disable, sadece "Yeni kod iste" gösterilir.
/// Yeni kod istendiğinde kutular yeniden açılır.
///
/// Cihaz doğrulama ([OtpAmaci.cihaz]) aynı ekranı kullanır: kod girişi,
/// süre ve yeniden gönderme aynı davranış; değişen yalnız metin, kodun
/// hangi uca gittiği ve "geri"nin anlamı (çıkış — gidilecek önceki ekran yok).
class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;
  final OtpAmaci amac;

  /// Kayıt ekranında gösterilen onay metinleri (yalnız [OtpAmaci.kayit],
  /// `RegisterScreen`'den gelir). Doğrulamadan sonra yasal onay kaydına
  /// gider (`YasalOnayService`, 0102). Null → kayıt
  /// yazılmaz (ör. ekran başka yoldan açıldıysa); akış aynı.
  final KayitOnayBaglami? kayitOnayi;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.amac = OtpAmaci.kayit,
    this.kayitOnayi,
  });

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

  bool get _cihaz => widget.amac == OtpAmaci.cihaz;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
      // Kayıtta kodu sunucu kendisi yolladı; cihaz kapısında kodu bu ekran
      // ister. Hata (ör. az önce gönderildi) gösterilir ama sayaç işler:
      // önceki kod hâlâ geçerli olabilir.
      if (_cihaz && mounted) {
        ref
            .read(cihazKapisiProvider.notifier)
            .kodGonder()
            .catchError((Object e) {
          if (mounted) showAppError(context, e);
        });
      }
    });
    _startCooldown();
    _startExpiry();
  }

  Future<void> _vazgec() => ref.read(authProvider.notifier).logout();

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
      showAppError(context, context.l10n.otpExpired);
      return;
    }
    final code = _code;
    if (code.length != 6) {
      showAppError(context, context.l10n.otpEnterFull);
      return;
    }
    // Onay kaydının dili — `await`'ten ÖNCE okunur (context sonra geçersiz
    // olabilir). U18.
    final etkinDil = Localizations.localeOf(context).toString();
    setState(() => _submitting = true);
    if (_cihaz) {
      try {
        // Başarılıysa kapı `serbest` olur ve `_AuthGate` bu ekranı kaldırır.
        await ref.read(cihazKapisiProvider.notifier).kodDogrula(code);
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
      return;
    }
    try {
      final user = await AuthService.instance.verifyRegistrationOtp(
        email: widget.email,
        token: code,
      );
      // Sorumluluk reddi KAYIT ekranında onaylandıysa OTP sonrası
      // DisclaimerAcceptanceScreen ikinci kez sormasın — aynı oturumda iki
      // kez aynı onay. Kaydı burada düşüyoruz ki _AuthGate kapısı geçsin;
      // hata olursa eski davranış (ekran sorar) yedek olarak kalır.
      //
      // Gerçek sürüm/dil/platform ve hata raporu serviste (2026-09-23
      // denetimi U18); başarısızlık akışı durdurmaz.
      //
      // YALNIZ yatırım uyarısının TAM metni kayıt ekranında okunup
      // onaylandıysa (zorunlu okuma). 2026-10-04'e kadar her kayıtta
      // yazılıyordu; ama kutuda yalnız ÖZET vardı ve kayıt TAM metnin
      // (`disclaimerText`) hash'ini taşıyordu — gösterilmemiş metne onay.
      // Düzeltme: tam metin gösterilmediyse kayıt yazılmaz, `_AuthGate`
      // uyarıyı `DisclaimerAcceptanceScreen`'de tam metniyle sorar
      // (Apple/Google ve eski hesapların zaten geçtiği yol). Kayıt ekranı
      // uyarıyı zorunlu okuttuğu için (bayrak 2026-10-05'te kalktı) e-posta
      // kaydında bu koşul hep doğrudur; kayıt ekranı dışından gelen
      // `kayitOnayi` için korunur.
      final kayitOnayi = widget.kayitOnayi;
      final onayKaydedildi = kayitOnayi != null &&
          kayitOnayi.yatirimUyarisiOnaylandi &&
          await DisclaimerService.instance.kabulKaydet(
            userId: user.id,
            locale: etkinDil,
          );
      // Kayıt kutularının ve andıkları belgelerin onayı (0102). Oturum
      // `verifyRegistrationOtp` ile açıldı; RPC `auth.uid()`'yi buradan
      // okur. Beklenmez ve fırlatmaz: kapı (`disclaimer_acceptances`)
      // yukarıdaki kayda bağlı, bu yalnız ispat kaydı.
      // `userId`: yeniden onay kapısı bu
      // yazımı bekler ve başarıda kapı izini koyar — az önce aynı sürümleri
      // onaylayan yeni kullanıcı kapıyı görmez.
      if (kayitOnayi != null) {
        CrashReporter.arkaPlan(
            YasalOnayService.instance.kayitOnaylariniKaydet(kayitOnayi,
                locale: etkinDil, userId: user.id),
            reason: 'YasalOnayService.kayit');
      }
      // Kayıt hunisi (F11). Yalnızca olay; akış değişmez.
      // - `disclaimer_accepted` yalnız kayıt BAŞARILIYSA: başarısızsa kapı
      //   ekranı yeniden sorar ve olay oradan (main.dart) gider — iki kez
      //   sayılmaz.
      // - `username_set` burada: e-posta kaydında kullanıcı adı formda
      //   seçilir, sunucu tetikleyicisi hesapla birlikte yazar; ayrı bir ad
      //   ekranı yoktur. Olay atlanırsa e-posta yolundaki herkes hunide bu
      //   adımda "düşmüş" görünürdü. Ad ekranı (sosyal giriş / eski hesap)
      //   kendi olayını `KullaniciAdiScreen`'de gönderir.
      unawaited(AnalyticsService.instance.logSignupStep('otp_verified'));
      if (onayKaydedildi) {
        unawaited(
            AnalyticsService.instance.logSignupStep('disclaimer_accepted'));
      }
      unawaited(AnalyticsService.instance.logSignupStep('username_set'));
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
      if (_cihaz) {
        await ref.read(cihazKapisiProvider.notifier).kodGonder();
      } else {
        await AuthService.instance.resendRegistrationOtp(widget.email);
      }
      if (!mounted) return;
      // Yeni kod alındı: cooldown + expiry sıfırlan, kutular tekrar aktif.
      _startCooldown();
      _startExpiry();
      _focusNodes.first.requestFocus();
      unawaited(showAppSuccess(
        context,
        title: context.l10n.otpSentTitle,
        message: context.l10n.otpSentMessage,
      ));
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
      backgroundColor: context.c.background,
      appBar: SandikAppBar(
        onBack: _submitting
            ? null
            : _cihaz
                ? _vazgec
                : () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: SandikSpace.screenH(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _iconBadge(),
              const SizedBox(height: 28),
              Text(
                _cihaz ? context.l10n.cihazOtpBaslik : context.l10n.otpTitle,
                textAlign: TextAlign.center,
                style: context.t.headlineLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: context.c.text90,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              if (_cihaz) ...[
                Text(
                  context.l10n.cihazOtpAciklama,
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium?.copyWith(
                    color: context.c.text58,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _emailIntro(),
              const SizedBox(height: 32),
              _otpRow(),
              const SizedBox(height: 20),
              _expiryChip(),
              const SizedBox(height: 20),
              _primaryButton(),
              const SizedBox(height: 16),
              _resendRow(canResend: canResend),
              // Kod e-postası Outlook'ta Gereksiz'e düştü (emülatör testi,
              // 2026-10-03). Kullanıcı kodu bulamazsa yeni cihazda / kayıtta
              // takılı kalır; gönderen alan adı doğrulanana kadar ipucu şart.
              const SizedBox(height: 8),
              Text(
                context.l10n.otpSpamIpucu,
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(color: context.c.text58),
              ),
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
          gradient: context.c.amberGradient,
          borderRadius: BorderRadius.circular(SandikRadius.lg),
          boxShadow: [
            BoxShadow(
              color: context.c.amberFill.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        // Amber dolgunun üzerine gelen içerik rengi tanımı `onAmber`;
        // sabit `black87` her iki temada da doğru olmuyordu.
        child: Icon(
          _cihaz ? Icons.phonelink_lock_rounded : Icons.mark_email_read_rounded,
          color: context.c.onAmber,
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
          color: context.c.text58,
          height: 1.5,
        ),
        children: [
          TextSpan(text: context.l10n.otpSentPrefix),
          TextSpan(
            text: widget.email,
            style: context.t.titleMedium?.copyWith(
              color: context.c.amberText,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          TextSpan(text: context.l10n.otpSentSuffix),
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
        // `maxLength` YOK: framework girişi 1 karaktere kırpsaydı yapıştırılan
        // 6 haneli kod onChanged'e hiç ulaşmazdı. Uzunluk aşağıda elle
        // yönetiliyor (tek rakam → o hücre, çok rakam → hücrelere dağıt).
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        autofocus: index == 0,
        // SMS/e-posta kodunun klavye üstünde önerilmesi için. Yalnızca İLK
        // hücreye verilir: altı hücrenin hepsine verilirse iOS kodu her
        // hücreye ayrı ayrı doldurmaya çalışır.
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        enabled: enabled,
        cursorColor: context.c.amberText,
        style: context.t.numLarge.copyWith(
          color: enabled ? context.c.text90 : context.c.text36,
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          // Dolgu temadan (`sandikGirisTemasi`) — uygulamadaki diğer
          // alanlarla aynı kural. Kenarlık hücreye özgü kalır (dolu hücre amber).
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            borderSide: BorderSide(
              color: filled ? context.c.amberText : context.c.hairline,
              width: filled ? 1.5 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
            borderSide: BorderSide(color: context.c.amberFill, width: 1.8),
          ),
          // `disabledBorder` temadan (hairline) — doğrulama sürerken kilitli
          // hücreler diğer kilitli alanlarla aynı görünür; kilidi `text36`
          // metin anlatır.
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (v) {
          // Yapıştırma / otomatik doldurma: tek hücreye birden fazla rakam
          // gelirse hepsini hücrelere dağıt. `maxLength: 1` yüzünden eskiden
          // yalnızca ilk hane giriliyordu — kullanıcı kodu kopyalayıp
          // yapıştırdığında kalan 5 haneyi elle yazmak zorundaydı.
          if (v.length > 1) {
            final rakamlar = v.replaceAll(RegExp(r'\D'), '');
            for (var i = 0; i < 6; i++) {
              _controllers[i].text = i < rakamlar.length ? rakamlar[i] : '';
            }
            final sonDolu = rakamlar.length.clamp(0, 5);
            _focusNodes[sonDolu].requestFocus();
            setState(() {});
            if (_code.length == 6 && !_submitting) _submit();
            return;
          }

          // Rakam dışı girişi (ör. klavyeden gelen boşluk) yok say.
          if (v.isNotEmpty && !RegExp(r'^\d$').hasMatch(v)) {
            _controllers[index].text = '';
            setState(() {});
            return;
          }

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
            color: context.c.loss.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SandikRadius.lg),
            border: Border.all(
              color: context.c.loss.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: context.c.loss, size: 14),
              const SizedBox(width: 6),
              Text(
                context.l10n.otpExpiredShort,
                style: context.t.titleSmall?.copyWith(
                  color: context.c.loss,
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
          Icon(Icons.schedule_rounded, color: context.c.text58, size: 14),
          const SizedBox(width: 6),
          // Flexible: dar Android ekranında büyük yazı boyutuyla satır
          // taşıyordu (360 dp, 2026-09-29).
          Flexible(
            child: Text(
              context.l10n.otpExpiresIn(_formatMmSs(_expiry)),
              textAlign: TextAlign.center,
              style: context.t.titleSmall?.copyWith(
                color: context.c.text58,
                fontWeight: FontWeight.w600,
              ),
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
            backgroundColor: context.c.amberFill,
            foregroundColor: context.c.onAmber,
            disabledBackgroundColor:
                context.c.amberFill.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
          ),
          icon: _resending
              ? const CustomLoadingIndicator(size: 18)
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _resending ? context.l10n.sending : context.l10n.requestNewCode,
            // Renk AÇIKÇA `onAmber`: `titleLarge` kendi rengini (`text90`)
            // taşır ve düğmenin `foregroundColor`'ını ezer — koyu temada
            // amber üstüne beyaz yazı 1,87:1 kalıyordu (açık tema
            // denetimi 2026-10-08, `acik_tema_ekran_kontrast_test`).
            // Pasifken (`_isBusy`) eski ton: soluk dolguda koyu yazı
            // okunmazdı.
            style: context.t.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _isBusy ? null : context.c.onAmber,
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
          backgroundColor: context.c.amberFill,
          foregroundColor: context.c.onAmber,
          disabledBackgroundColor: context.c.amberFill.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
        ),
        child: _submitting
            ? const CustomLoadingIndicator(size: 22)
            : Text(
                context.l10n.verify,
                // Renk açıkça `onAmber` — yukarıdaki nota bak.
                style: context.t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.onAmber,
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
    // Wrap: iki parça tek satıra sığmazsa bağlantı alt satıra iner — Row
    // dar ekranda büyük yazıyla taşıyordu (360 dp, 2026-09-29).
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text(
          context.l10n.otpNotReceived,
          style: context.t.bodyMedium?.copyWith(
            color: context.c.text58,
          ),
        ),
        SandikBasma(
          onTap: canResend ? _resend : null,
          behavior: HitTestBehavior.opaque,
          child: Text(
            _resending
                ? context.l10n.sending
                : showCountdown
                    ? context.l10n.resendIn(_cooldown)
                    : context.l10n.resend,
            style: context.t.bodyMedium?.copyWith(
              color: canResend ? context.c.amberText : context.c.text36,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footerHint() {
    if (_cihaz) {
      return Column(
        children: [
          Text(
            context.l10n.cihazOtpIpucu,
            textAlign: TextAlign.center,
            style: context.t.bodySmall?.copyWith(
              color: context.c.text36,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : _vazgec,
            // `amberText`: açık temada amber dolgu krem zeminde okunmuyor
            // (emülatörde görüldü, 2026-10-03); metin tonu kontrastlı.
            style: TextButton.styleFrom(foregroundColor: context.c.amberText),
            child: Text(context.l10n.cihazOtpVazgec),
          ),
        ],
      );
    }
    return Center(
      child: Text(
        context.l10n.otpWrongEmail,
        textAlign: TextAlign.center,
        style: context.t.bodySmall?.copyWith(
          color: context.c.text36,
          height: 1.4,
        ),
      ),
    );
  }
}
