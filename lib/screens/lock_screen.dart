import 'package:flutter/material.dart';

import '../services/biometric_lock_service.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../l10n/l10n.dart';

/// Kilit ekranı — biyometrik kilit açıkken öne dönüşte ve soğuk açılışta.
///
/// İçerik GÖSTERMEZ: arkadaki portföy bu ekranın altında değil, hiç
/// kurulmamış durumda (`_AuthGate` kilit açılana kadar ana ekranı
/// oluşturmaz). Aksi halde uygulama değiştirici karesi ya da bir an için
/// görünen tutar kilidi anlamsız kılardı.
///
/// Açılışta doğrulama KENDİLİĞİNDEN istenir; kullanıcı iptal ederse
/// düğmeyle tekrar dener. Kilidi KAPATMANIN yeri Ayarlar ve oraya kilit
/// açılmadan gidilemez; bu bilinçli.
///
/// **Çıkış yapmak ayrı bir şeydir ve serbesttir** (2026-09-23). Zaman aşımı
/// artık `logout()` değil kilit uyguladığından (bkz. `main.dart`), kullanıcı
/// kendi oturumuna geri dönüyor — başka bir hesaba geçmenin ekrandan bir
/// yolu kalmamıştı. Tek çare Face ID ile girip Profil'den çıkmaktı; Face ID
/// başka birinin telefonunda ya da çalışmıyorken bu hiç mümkün değildi.
/// Çıkış kilidi AÇMAZ: oturumu siler ve giriş ekranına döner — yani
/// korumayı zayıflatmaz, yalnızca kullanıcıyı kendi cihazında mahsur
/// bırakmaz.
///
/// **Tek istisna: cihazda doğrulanacak bir şey kalmadıysa**
/// ([BiyometrikSonuc.kullanilamaz]). Kullanıcı kilidi açtıktan SONRA
/// telefonunun ekran kilidini kaldırırsa sistem artık kimseyi
/// doğrulayamıyor; "tekrar dene" sonsuza kadar aynı sonucu verir ve
/// kullanıcı kendi portföyünden kalıcı olarak dışarıda kalırdı (tek çare
/// uygulamayı silip kurmak). O durumda — ve YALNIZCA o durumda — kilidi
/// kapatıp devam etme seçeneği gösterilir: cihaz kimseyi doğrulayamadığı
/// için kilit zaten koruma sağlamıyor.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onKilidiKapat,
    required this.onCikisYap,
  });

  final VoidCallback onUnlocked;

  /// Cihaz doğrulama yapamaz hâldeyken kullanıcının seçtiği çıkış:
  /// biyometrik kilit tercihini kapatıp içeri al.
  final VoidCallback onKilidiKapat;

  /// Oturumu kapat ve giriş ekranına dön — başka hesaba geçmenin yolu.
  /// Kilidi AÇMAZ; sınır aynı yerde durur.
  final VoidCallback onCikisYap;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  /// Son denemenin sonucu — `null` ise henüz denenmedi.
  BiyometrikSonuc? _sonSonuc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _sonSonuc = null;
    });
    // `try/finally` YAPISAL koruma: `_busy` her yoldan düşer. Eskiden
    // `await`ten sonra düz `setState` vardı ve servis fırlattığında o satır
    // hiç çalışmıyordu — ekran "Doğrulanıyor…"da donuyor, düğme bir daha
    // etkinleşmiyordu (üretim çökmesi 2026-09-19'un asıl kullanıcı etkisi).
    // Servis artık fırlatmıyor; yine de sözleşmeye değil yapıya güveniyoruz.
    try {
      final sonuc = await BiometricLockService.instance.authenticate();
      if (!mounted) return;
      setState(() => _sonSonuc = sonuc);
      if (sonuc.basariliMi) widget.onUnlocked();
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'LockScreen.tryUnlock');
      if (mounted) setState(() => _sonSonuc = BiyometrikSonuc.hata);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Çıkış ONAY ister: kilit ekranında kullanıcı doğrulamayı beklerken
  /// yanlışlıkla dokunabilir ve oturumu kaybetmek (özellikle sosyal girişte)
  /// geri alınması zahmetli bir adımdır.
  Future<void> _cikisiOnayla() async {
    final l = context.l10n;
    final onay = await showSandikConfirm(
      context: context,
      title: l.lockSwitchAccountTitle,
      message: l.lockSwitchAccountBody,
      confirmLabel: l.lockSwitchAccountTitle,
      cancelLabel: l.cancel,
    );
    if (onay && mounted) widget.onCikisYap();
  }

  /// Duruma göre alt başlık. İptal ile "cihazda kilit yok" aynı cümleyi
  /// paylaşmaz: ikincisinde tekrar denemenin bir anlamı yok.
  String _durumMetni(BuildContext context) {
    switch (_sonSonuc) {
      case null:
      case BiyometrikSonuc.iptal:
        return context.l10n.lockPrompt;
      case BiyometrikSonuc.kullanilamaz:
        return context.l10n.lockNoDeviceCredential;
      case BiyometrikSonuc.reddedildi:
      case BiyometrikSonuc.hata:
      case BiyometrikSonuc.basarili:
        return context.l10n.lockFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: c.amberFill.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.amberFill.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      size: 34, color: c.amberText),
                ),
                const SizedBox(height: SandikSpace.lg),
                Text(
                  context.l10n.lockTitle,
                  textAlign: TextAlign.center,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.text90,
                  ),
                ),
                const SizedBox(height: SandikSpace.sm),
                Text(
                  _durumMetni(context),
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium?.copyWith(color: c.text58),
                ),
                const SizedBox(height: SandikSpace.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _tryUnlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: Text(_busy ? context.l10n.lockVerifying : context.l10n.unlock),
                  ),
                ),
                // Yalnızca cihaz doğrulama YAPAMAZ hâldeyken: tekrar
                // denemenin sonucu değişmez, kullanıcı içeri giremez.
                if (_sonSonuc == BiyometrikSonuc.kullanilamaz) ...[
                  const SizedBox(height: SandikSpace.sm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _busy ? null : widget.onKilidiKapat,
                      child: Text(context.l10n.lockDisableAndContinue),
                    ),
                  ),
                ],
                // HER ZAMAN görünür: bu kilidi açmaz, oturumu kapatır.
                // Kilit ekranı kullanıcıyı KENDİ hesabına döndürdüğü için
                // başka hesaba geçmenin tek yolu buydu; Face ID çalışmayan
                // ya da başkasına ait bir cihazda hiç yolu yoktu.
                const SizedBox(height: SandikSpace.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy ? null : _cikisiOnayla,
                    child: Text(context.l10n.lockSwitchAccount),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
