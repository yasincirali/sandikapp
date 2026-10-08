import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, FilledButton, Icons, RoundedRectangleBorder;
import '../services/crash_reporter.dart';
import '../services/disclaimer_service.dart';
import '../services/yasal_onay_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_async_button.dart';
import '../widgets/zorunlu_okuma.dart';
import '../l10n/l10n.dart';

/// Varolan kullanıcılar için splash sonrası disclaimer onay ekranı.
/// Geri butonu yok — onaylanmadan uygulama kullanılamaz.
///
/// Zorunlu okuma (2026-10-04; bayrak `zorunlu_okuma` 2026-10-05'te kalktı,
/// davranış kalıcı): metin zaten TAM (`disclaimerText`); kutu ve "Kabul et"
/// metnin sonunda. Kullanıcı sona kaydırana kadar kutu kilitlidir, altta
/// ipucu durur. Metin ekrana sığıyorsa kilit baştan açıktır.
class DisclaimerAcceptanceScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onAccepted;

  const DisclaimerAcceptanceScreen({
    super.key,
    required this.userId,
    required this.onAccepted,
  });

  @override
  State<DisclaimerAcceptanceScreen> createState() =>
      _DisclaimerAcceptanceScreenState();
}

class _DisclaimerAcceptanceScreenState
    extends State<DisclaimerAcceptanceScreen> {
  bool _accepted = false;
  bool _showError = false;

  bool _sonaUlasti = false;
  double _ilerleme = 0;

  bool get _kilitli => !_sonaUlasti;

  /// Liste alt boşluğu: "Kabul et"ten sonra metin yok (bkz.
  /// `OkumaOlcumu.sonaUlasti`).
  static const _altBosluk = SandikSpace.xl;

  Future<void> _confirm() async {
    // Kilit ve gösterge [SandikAsyncButton]'da (eski `_loading`,
    // 2026-10-08).
    if (!_accepted) return;
    // Kayıt hatası olsa bile onayı kabul et — akış kilitlenmez. Hata artık
    // yutulmaz; servis raporlar ve gerçek sürüm/dil/platformu yazar
    // (2026-09-23 denetimi U18).
    final dil = Localizations.localeOf(context).toString();
    await DisclaimerService.instance.kabulKaydet(
      userId: widget.userId,
      locale: dil,
    );
    // Gösterilen yatırım uyarısı metninin onayı (0102). Beklenmez,
    // fırlatmaz; kapı yukarıdaki kayıtta.
    CrashReporter.arkaPlan(
        YasalOnayService.instance.yatirimUyarisiniKaydet(
            locale: dil, sonunaKadarOkundu: _sonaUlasti),
        reason: 'YasalOnayService.yatirim_uyarisi');
    if (mounted) {
      // Düğme `onAccepted` çalışana dek meşgul kalır: eski `_loading` başarıda
      // hiç düşmüyordu, kapı ekranı değiştirene kadar ikinci dokunuş ikinci
      // kaydı atamazdı. `onAccepted` kapıda `setState` yapar; kilit aynı
      // karede açılır ve o kare bu ekranı zaten kaldırır.
      final bitti = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          widget.onAccepted();
        } finally {
          bitti.complete();
        }
      });
      await bitti.future;
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = _liste(context);
    return DefaultTextStyle(
      style: sandikFont(decoration: TextDecoration.none),
      child: CupertinoPageScaffold(
        backgroundColor: context.c.background,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SonaKadarOkumaIzleyici(
                  sonPay: _altBosluk,
                  onSonaUlasti: () => setState(() => _sonaUlasti = true),
                  onIlerleme: (v) => setState(() => _ilerleme = v),
                  child: liste,
                ),
              ),
              if (!_sonaUlasti) OkumaIpucu(ilerleme: _ilerleme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liste(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 28, vertical: _altBosluk);
    final ogeler = <Widget>[
        // Başlık
        Row(
          children: [
            Icon(Icons.gavel_rounded, size: 22, color: context.c.amberText),
            const SizedBox(width: 10),
            // Flexible: başlık büyük yazıda/dar ekranda alt satıra iner;
            // eskiden satır taşıyordu (2026-10-04 taşma testi yakaladı).
            Flexible(
              child: Text(
                context.l10n.disclaimerTitle,
                style: context.t.headlineMedium?.copyWith(
                  color: context.c.amberText,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'v$disclaimerVersion',
              style: context.t.bodySmall?.copyWith(
                color: context.c.text36,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.disclaimerIntro,
          style: context.t.bodyMedium?.copyWith(
            color: context.c.text58,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),

        // Disclaimer kutusu
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.c.overlay,
            borderRadius: BorderRadius.circular(SandikRadius.md),
            border: Border.all(
              color: context.c.overlay,
            ),
          ),
          child: Text(
            disclaimerText,
            style: context.t.titleSmall?.copyWith(
              color: context.c.text58,
              height: 1.7,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Onay checkbox
        SandikBasma(
          // Zorunlu okumada metnin sonuna gelinmeden kutu kilitli.
          onTap: _kilitli
              ? null
              : () => setState(() {
                    _accepted = !_accepted;
                    if (_accepted) _showError = false;
                  }),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _showError
                  ? context.c.loss.withValues(alpha: 0.07)
                  : context.c.overlay,
              borderRadius: BorderRadius.circular(SandikRadius.md),
              border: Border.all(
                color: _showError
                    ? context.c.loss.withValues(alpha: 0.4)
                    : context.c.overlay,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: SandikMotion.of(
                      context, const Duration(milliseconds: 150)),
                  curve: SandikMotion.enter,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _accepted ? context.c.amberText : Colors.transparent,
                    borderRadius: BorderRadius.circular(SandikRadius.sm),
                    border: Border.all(
                      color: _accepted
                          ? context.c.amberText
                          : (_showError ? context.c.loss : context.c.text36),
                      width: 2,
                    ),
                  ),
                  child: _accepted
                      ? Icon(Icons.check_rounded,
                          size: 14, color: context.c.onAmber)
                      : (_kilitli
                          ? Icon(Icons.lock_outline_rounded,
                              size: 12, color: context.c.text36)
                          : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.disclaimerAcceptRow,
                    style: context.t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: _showError ? context.c.loss : context.c.text90,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showError) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.disclaimerMustAccept,
            style: context.t.bodySmall?.copyWith(color: context.c.loss),
          ),
        ],
        const SizedBox(height: 28),

        // Onayla butonu — tek yükleniyor davranışı (2026-10-08):
        // [SandikAsyncButton]; eski cam görünüm (`Container` süslemesi)
        // `style` + dış gölge ile birebir (pasif/meşgul 0.45 dolgu).
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: SandikRadius.mdAll,
            boxShadow: [
              BoxShadow(
                color: context.c.amberFill.withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SandikAsyncButton(
            onPressed: _accepted ? _confirm : null,
            haptic: SandikHaptic.none,
            style: FilledButton.styleFrom(
              backgroundColor: context.c.amberFill.withValues(alpha: 0.92),
              foregroundColor: context.c.onAmber,
              disabledBackgroundColor:
                  context.c.amberFill.withValues(alpha: 0.45),
              disabledForegroundColor: context.c.onAmber,
              textStyle: context.t.bodyLarge,
              side: BorderSide(
                  color: context.c.amberFill.withValues(alpha: 0.60)),
              shape: RoundedRectangleBorder(borderRadius: SandikRadius.mdAll),
            ),
            child: Text(
              context.l10n.accept,
              style: context.t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.onAmber,
              ),
            ),
          ),
        ),
    ];
    // Tek sütun, tembel liste DEĞİL: tembel listenin uzunluğu kurulmamış
    // öğeler için tahmindir, "sona ulaştı" erken yapışabilirdi (bkz.
    // LegalDocScreen zorunlu kip).
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: ogeler,
      ),
    );
  }
}
