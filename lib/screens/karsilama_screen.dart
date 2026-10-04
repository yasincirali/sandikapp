import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_kabugu.dart';
import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';
import 'register_screen.dart';

/// Girişten ÖNCE uygulamanın ne yaptığını anlatan dört sayfa (2026-10-04).
///
/// Kullanıcı isteği: *"onboarding öncesi müşteri uygulama yetkinliklerini
/// anlamalı."* Eskiden yeni kullanıcı ilk ekranda e-posta/şifre formu
/// görüyordu; uygulamanın neyi takip ettiğini, neden hesap açması
/// gerektiğini kayıttan SONRA, turda öğreniyordu. Sadeleştirme listesinin
/// 1. maddesi: değer görmeden hesap istemek huninin en büyük kaybı.
///
/// ## Kurallar
/// - Bayrak `karsilama_tanitimi` 2026-10-04'te açıldı, 2026-10-05'te kalktı:
///   tanıtım kalıcı.
/// - Cihaz başına bir kez: "Giriş yap"/"Atla" ya da herhangi bir hesapla
///   oturum açılınca `karsilamaGorulduProvider` `true` olur; mevcut
///   kullanıcı çıkış yapınca bu ekranı görmez (`main.dart`).
/// - Kayıt ve demo bu ekranın ÜSTÜNE açılır; vazgeçen kullanıcı tanıtıma
///   döner — giriş formuna düşmez, kararını yeniden verebilir.
/// - Demo düğmesi `demo_mode_enabled` kapalıysa çizilmez; o zaman birincil
///   yol yine "Hesap oluştur".
/// - Sayfalar bilinçli olarak SAYI içermez: fiyat sunucusuna gitmeden
///   gösterilecek her rakam uydurma olurdu (fiyat kaynağı kuralı 3).
class KarsilamaScreen extends ConsumerStatefulWidget {
  const KarsilamaScreen({super.key});

  @override
  ConsumerState<KarsilamaScreen> createState() => _KarsilamaScreenState();
}

class _KarsilamaSayfa {
  final IconData ikon;
  final String baslik;
  final String metin;
  final List<String> etiketler;
  const _KarsilamaSayfa(this.ikon, this.baslik, this.metin, this.etiketler);
}

class _KarsilamaScreenState extends ConsumerState<KarsilamaScreen> {
  final _sayfa = PageController();
  int _aktif = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logSignupStep('karsilama_acildi');
  }

  @override
  void dispose() {
    _sayfa.dispose();
    super.dispose();
  }

  List<_KarsilamaSayfa> _sayfalar(BuildContext context) {
    final l = context.l10n;
    return [
      _KarsilamaSayfa(Icons.account_balance_wallet_outlined, l.welcomeP1Title,
          l.welcomeP1Body, [
        l.welcomeTagStock,
        l.welcomeTagFund,
        l.welcomeTagGold,
        l.welcomeTagFx,
        l.welcomeTagCrypto,
        l.welcomeTagPension,
      ]),
      _KarsilamaSayfa(Icons.insights_outlined, l.welcomeP2Title,
          l.welcomeP2Body, [l.welcomeTagInflation, l.welcomeTagUsd, l.welcomeTagGold]),
      _KarsilamaSayfa(Icons.widgets_outlined, l.welcomeP3Title, l.welcomeP3Body,
          [l.welcomeTagWidget, l.welcomeTagLock, l.welcomeTagBrief]),
      _KarsilamaSayfa(Icons.notifications_active_outlined, l.welcomeP4Title,
          l.welcomeP4Body, [l.welcomeTagAlarm, l.welcomeTagPartner]),
    ];
  }

  /// Giriş formuna geçiş: tanıtım bir daha gösterilmez, kapı giriş
  /// ekranını çizer.
  void _girisFormunaGec(String neden) {
    AnalyticsService.instance.logSignupStep('karsilama_$neden');
    ref.read(karsilamaGorulduProvider.notifier).set(true);
  }

  void _kayitAc() {
    AnalyticsService.instance.logSignupStep('karsilama_kayit');
    pushGuarded(
      context,
      adaptiveRoute<void>(builder: (_) => const RegisterScreen()),
    );
  }

  void _demoAc() {
    AnalyticsService.instance.logSignupStep('karsilama_demo');
    demoyuAc(context);
  }

  @override
  Widget build(BuildContext context) {
    final sayfalar = _sayfalar(context);
    final son = _aktif == sayfalar.length - 1;
    final demoVar = DemoModu.girisDugmesiAcik();
    final sure = SandikMotion.surfaceOf(context);

    return Scaffold(
      backgroundColor: context.c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Üst satır: logo + Atla. "Atla" giriş formuna götürür (hesabı
            // olan kullanıcı tanıtımı okumak zorunda değil).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.md, SandikSpace.sm, SandikSpace.xs, 0),
              child: Row(
                children: [
                  const SandikLogo(size: 28),
                  const SizedBox(width: SandikSpace.sm),
                  Text('sandık',
                      style: context.t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.gold)),
                  const Spacer(),
                  CupertinoButton(
                    onPressed: () => _girisFormunaGec('atla'),
                    child: Text(
                      context.l10n.welcomeSkip,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _sayfa,
                itemCount: sayfalar.length,
                onPageChanged: (i) => setState(() => _aktif = i),
                itemBuilder: (context, i) => _SayfaGovdesi(sayfa: sayfalar[i]),
              ),
            ),
            // Sayfa noktaları — hangi sayfada olduğun ve kaç sayfa kaldığı.
            Semantics(
              label: context.l10n.welcomePageOf(_aktif + 1, sayfalar.length),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < sayfalar.length; i++)
                      AnimatedContainer(
                        duration: SandikMotion.stateOf(context),
                        curve: SandikMotion.enter,
                        margin: const EdgeInsets.symmetric(
                            horizontal: SandikSpace.xxs),
                        width: i == _aktif ? SandikSpace.lgs : SandikSpace.sm,
                        height: SandikSpace.sm,
                        decoration: BoxDecoration(
                          color: i == _aktif
                              ? context.c.amberFill
                              : context.c.text20,
                          borderRadius: SandikRadius.smAll,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SandikSpace.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SandikSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Birincil: son sayfada "Hesap oluştur", öncekilerde
                  // "Devam". Demo varsa ikincil düğme olarak her sayfada
                  // görünür — değeri görmenin en kısa yolu o.
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.c.amberFill,
                      foregroundColor: context.c.onAmber,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: SandikRadius.mdAll),
                    ),
                    onPressed: son
                        ? _kayitAc
                        : () => _sayfa.nextPage(
                            duration: sure, curve: SandikMotion.move),
                    child: Text(
                      son
                          ? context.l10n.welcomeCreateAccount
                          : context.l10n.welcomeNext,
                      style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.c.onAmber),
                    ),
                  ),
                  if (demoVar) ...[
                    const SizedBox(height: SandikSpace.sm2),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.c.amberText,
                        side: BorderSide(color: context.c.hairline),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: SandikRadius.mdAll),
                      ),
                      onPressed: _demoAc,
                      child: Text(
                        context.l10n.welcomeTryDemo,
                        style: context.t.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.c.amberText),
                      ),
                    ),
                  ],
                  CupertinoButton(
                    onPressed: () => _girisFormunaGec('giris'),
                    child: Text(
                      context.l10n.welcomeHaveAccount,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text58),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SandikSpace.sm),
          ],
        ),
      ),
    );
  }
}

class _SayfaGovdesi extends StatelessWidget {
  final _KarsilamaSayfa sayfa;
  const _SayfaGovdesi({required this.sayfa});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, kisit) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: SandikSpace.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kisit.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: context.c.amberFill.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(sayfa.ikon, size: 52, color: context.c.amberText),
              ),
              const SizedBox(height: SandikSpace.xl),
              Text(
                sayfa.baslik,
                textAlign: TextAlign.center,
                style: context.t.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.text90,
                ),
              ),
              const SizedBox(height: SandikSpace.smd),
              Text(
                sayfa.metin,
                textAlign: TextAlign.center,
                style: context.t.bodyLarge?.copyWith(
                  color: context.c.text58,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: SandikSpace.lgs),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: SandikSpace.sm,
                runSpacing: SandikSpace.sm,
                children: [
                  for (final e in sayfa.etiketler)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.smd,
                          vertical: SandikSpace.xs2),
                      decoration: BoxDecoration(
                        color: context.c.surface1,
                        borderRadius: SandikRadius.lgAll,
                        border: Border.all(color: context.c.hairline),
                      ),
                      child: Text(
                        e,
                        style: context.t.labelLarge
                            ?.copyWith(color: context.c.text90),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
