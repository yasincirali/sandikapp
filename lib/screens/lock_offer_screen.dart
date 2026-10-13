import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/biometric_lock_service.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';

/// Biyometrik kilit TEKLİFİ — kullanıcı başına bir kez, giriş sonrası.
///
/// **Neden var (kullanıcı kararı, 2026-09-23).** Kilidi KAPALI olan
/// kullanıcıda 10 dakikalık zaman aşımı `logout()` uyguluyor; bu üç şeyi
/// birden götürüyor: oturum, push token'ı (`RemotePushService.stop()`
/// satırı sunucudan siler) ve dolayısıyla fiyat alarmlarıyla günlük özet.
/// Kilit AÇIKSA hiçbiri olmuyor — yalnızca perde iniyor.
///
/// Yani kilit burada bir kısıt değil, üç şeyi birden koruyan ayar. Ama
/// varsayılan olarak açık gelemez: biyometrik doğrulama kullanıcının
/// rızasını ister ve cihazda biyometri tanımlı olmayabilir. Çözüm, kararı
/// görünür kılmak — teklifi gerekçesiyle göstermek.
///
/// **Neden zaman aşımı ANINDA sorulmuyor.** O an kullanıcı zaten
/// kaybetmiştir (çıkış yapılmış, bildirimler susmuş); teklif ancak bir
/// sonraki sefere yarar. Girişten hemen sonra sormak kaybı hiç
/// yaşatmamayı hedefler.
///
/// **Neden turda değil.** Tur öğreticidir, atlanabilir ve tekrar
/// izlenebilir; kalıcı bir güvenlik tercihi oradan açtırılamaz. Ayrıca
/// tur bu ekranın gösterildiği anda henüz bitmemiş olabilir.
///
/// Ret DAYATILMAZ ve tekrarlanmaz: `biometricLockOfferedProvider` kabul
/// de ret de olsa işaretlenir. Kilidi sonradan kapatan kullanıcıya teklif
/// yeniden çıkmaz — verdiği kararı geri almaya çalışmak olurdu.
class LockOfferScreen extends StatefulWidget {
  const LockOfferScreen({
    super.key,
    required this.yontem,
    required this.onKabul,
    required this.onRet,
  });

  /// Cihazın kilit yöntemi — yalnızca başlık, düğme ve ikon buna göre
  /// yazılır (Android'de "Face ID" demek yanlıştı). Çağıran, cihazda
  /// kilit YOKSA bu ekranı hiç göstermez (`kilitYontemiProvider`).
  final KilitYontemi yontem;

  /// Doğrulama BAŞARILI olduktan sonra çağrılır — tercihi açan taraf
  /// çağırandır. Ekran yalnızca doğrulamayı yürütür.
  final VoidCallback onKabul;

  /// "Şimdi değil" ya da cihaz desteklemiyor.
  final VoidCallback onRet;

  @override
  State<LockOfferScreen> createState() => _LockOfferScreenState();
}

class _LockOfferScreenState extends State<LockOfferScreen> {
  bool _busy = false;

  /// Ayarlar'daki açma akışıyla AYNI kural: önce cihaz destekliyor mu,
  /// sonra bir kez doğrula. Doğrulamadan tercihi açmak kullanıcıyı
  /// açamayacağı bir kilit ekranına düşürürdü.
  Future<void> _kabulEt() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final svc = BiometricLockService.instance;
      if (!await svc.available) {
        if (!mounted) return;
        sandikSnack(context, context.l10n.noBiometricOnDevice,
            kind: SandikSnackKind.warning);
        widget.onRet();
        return;
      }
      if (!mounted) return;
      final istem = context.l10n.biometricPrompt;
      final sonuc = await svc.authenticate(reason: istem);
      if (!mounted) return;
      if (!sonuc.basariliMi) {
        if (sonuc == BiyometrikSonuc.kullanilamaz) {
          sandikSnack(context, context.l10n.noBiometricOnDevice,
              kind: SandikSnackKind.warning);
          widget.onRet();
        }
        // İptal ettiyse ekranda kalsın — fikrini değiştirebilir.
        return;
      }
      widget.onKabul();
    } catch (e, st) {
      // `LockScreen`in üretim çökmesiyle (2026-09-19) AYNI ders: servis
      // "asla fırlatmaz" diyor, ama ekran buna GÜVENMEZ. Yakalanmazsa
      // istisna yukarı kaçar ve kullanıcı teklif ekranında takılı kalır.
      CrashReporter.report(e, st, reason: 'LockOfferScreen.kabulEt');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData get _ikon => switch (widget.yontem) {
        KilitYontemi.faceId => Icons.face_rounded,
        KilitYontemi.touchId ||
        KilitYontemi.biyometrik =>
          Icons.fingerprint_rounded,
        KilitYontemi.ekranKilidi => Icons.lock_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final yontem = widget.yontem.name;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.xl, vertical: SandikSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: c.amberFill.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: c.amberFill.withValues(alpha: 0.35)),
                      ),
                      child: Icon(_ikon, size: 32, color: c.amberText),
                    ),
                    const SizedBox(height: SandikSpace.lg),
                    Text(
                      l.lockOfferTitle(yontem),
                      style: context.t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.text90,
                      ),
                    ),
                    const SizedBox(height: SandikSpace.sm),
                    Text(
                      l.lockOfferBody,
                      style: context.t.bodyMedium?.copyWith(color: c.text58),
                    ),
                    const SizedBox(height: SandikSpace.xl),
                    // Sıra ÖNEMLİ: kullanıcının kaybettiği şeyler önce
                    // (oturum, bildirim), mahremiyet sonra. Kilit çoğu
                    // kullanıcıya "engel" gibi görünür; ilk iki madde
                    // onun aslında bir kolaylık olduğunu söyler.
                    _Fayda(
                      ikon: Icons.lock_clock_rounded,
                      baslik: l.lockOfferBenefitStay,
                      govde: l.lockOfferBenefitStayBody,
                    ),
                    const SizedBox(height: SandikSpace.md),
                    _Fayda(
                      ikon: Icons.notifications_active_outlined,
                      baslik: l.lockOfferBenefitPush,
                      govde: l.lockOfferBenefitPushBody,
                    ),
                    const SizedBox(height: SandikSpace.md),
                    _Fayda(
                      ikon: Icons.visibility_off_outlined,
                      baslik: l.lockOfferBenefitPrivacy,
                      govde: l.lockOfferBenefitPrivacyBody,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.xl, 0, SandikSpace.xl, SandikSpace.lg),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _kabulEt,
                      icon: Icon(_ikon),
                      label: Text(l.lockOfferAccept(yontem)),
                    ),
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _busy ? null : widget.onRet,
                      child: Text(l.lockOfferDecline),
                    ),
                  ),
                  Text(
                    l.lockOfferLater,
                    textAlign: TextAlign.center,
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek fayda satırı — ikon + başlık + gerekçe.
class _Fayda extends StatelessWidget {
  const _Fayda({
    required this.ikon,
    required this.baslik,
    required this.govde,
  });

  final IconData ikon;
  final String baslik;
  final String govde;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ikon, size: 20, color: c.amberText),
        const SizedBox(width: SandikSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                baslik,
                style: context.t.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.text90,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                govde,
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
