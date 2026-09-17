import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/destek.dart';
import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/review_prompt_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';

enum _Secim { degerlendir, sonra, sorun }

/// Mağaza değerlendirme istemi — "sandık'ı seviyor musun?"
///
/// **Ton kuralı** (`MilestoneSheet` ile aynı): fintech tonunda, tek soru,
/// üç seçenek. Yalvarma dili ("lütfen 5 yıldız") ve emoji yok; mağaza
/// kuralları da bunu yasaklar, marka da istemez.
///
/// **Üç yol, üçü de kapatılabilir:**
/// - *Evet, değerlendir* → sistem puan kartı (`in_app_review`), yoksa
///   mağaza sayfası. Bir daha sorulmaz.
/// - *Sonra* → 30 gün sonra bir sonraki mutlu anda tekrar; toplam üç kez.
/// - *Bir sorun var* → destek e-postası açılır, 90 gün puan sorulmaz.
///   Bu yol ön sorunun asıl gerekçesidir: memnun olmayan kullanıcıyı
///   mağazaya değil bize yönlendirir. Sorunu duymadan puan istemek,
///   şikâyetin mağazada herkese açık yazılması demektir.
///
/// **Karar bu widget'ta DEĞİL**: ne zaman ve kime sorulacağı
/// `degerlendirmeSorulsunMu` saf fonksiyonunda (bkz. `review_prompt_test`).
/// Buradaki [belkiGoster] yalnızca kapıyı sorar ve seçimi servise iletir.
class ReviewPromptSheet extends StatelessWidget {
  const ReviewPromptSheet({super.key});

  /// Bir "mutlu an" yaşandı — koşullar uygunsa istemi göster.
  ///
  /// Tetikleyen yüzeyin portföy durumunu taşıması gerekmez; kâr/zarar
  /// kapısı için `portfolioProvider` buradan okunur. Böylece yeni bir
  /// tetikleyici eklemek tek satırdır ve kapı mantığı tek yerde kalır.
  static Future<void> belkiGoster(BuildContext context, ReviewAni an) async {
    final svc = ReviewPromptService.instance;
    final state = ProviderScope.containerOf(context, listen: false)
        .read(portfolioProvider)
        .valueOrNull;
    if (state == null) return;
    if (!await svc.sorulsunMu(an, state)) return;
    if (!context.mounted) return;

    await svc.gosterildi(an);
    if (!context.mounted) {
      svc.kapandi();
      return;
    }

    // Ön soru kapalıysa (Remote Config) doğrudan sistem kartı.
    if (!svc.onSoruAcik) {
      await svc.degerlendir(an, source: 'direct');
      svc.kapandi();
      return;
    }

    final secim = await showModalBottomSheet<_Secim>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ReviewPromptSheet(),
    );
    svc.kapandi();

    switch (secim) {
      case _Secim.degerlendir:
        await svc.degerlendir(an, source: 'sheet');
      case _Secim.sorun:
        await svc.sorunBildirildi(an);
        if (context.mounted) await _destekMaili(context);
      case _Secim.sonra:
      case null:
        // Dışarı dokunarak kapatmak da "sonra"dır: kullanıcı karar vermedi,
        // reddetmedi. Aynı erteleme aralığı uygulanır.
        await svc.ertelendi(an);
    }
  }

  /// "Bir sorun var" → destek e-postası. Ayarlar'daki "Bize ulaş" ile aynı
  /// adres ve imza; sorun buradan gelince konu satırı istemi belirtir ki
  /// hangi kanaldan geldiğini bilelim.
  static Future<void> _destekMaili(BuildContext context) async {
    final email = ProviderScope.containerOf(context, listen: false)
            .read(authProvider)
            .valueOrNull
            ?.email ??
        '';
    final imza = email.isNotEmpty ? '\n\n---\nKullanıcı: $email' : '';
    final uri = Uri(
      scheme: 'mailto',
      path: kDestekEposta,
      query: [
        'subject=${Uri.encodeComponent('sandık — bir sorun var')}',
        'body=${Uri.encodeComponent(imza)}',
      ].join('&'),
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'review feedback mail');
    }
    if (!ok && context.mounted) {
      sandikSnack(
        context,
        context.l10n.mailAppFailed(kDestekEposta),
        kind: SandikSnackKind.warning,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: SandikRadius.sheetTop,
      ),
      padding: EdgeInsets.fromLTRB(
        SandikSpace.lg,
        SandikSpace.smd,
        SandikSpace.lg,
        SandikSpace.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text20,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: SandikSpace.lg),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.amberFill.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.star_rounded, size: 28, color: c.amberText),
            ),
          ),
          const SizedBox(height: SandikSpace.md),
          Text(
            l10n.reviewPromptTitle,
            textAlign: TextAlign.center,
            style: context.t.headlineMedium?.copyWith(color: c.text90),
          ),
          const SizedBox(height: SandikSpace.sm),
          Text(
            l10n.reviewPromptBody,
            textAlign: TextAlign.center,
            style: context.t.bodyLarge?.copyWith(color: c.text58),
          ),
          const SizedBox(height: SandikSpace.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.amberFill,
              foregroundColor: c.onAmber,
              padding: const EdgeInsets.symmetric(vertical: SandikSpace.md2),
            ),
            onPressed: () => Navigator.of(context).pop(_Secim.degerlendir),
            child: Text(l10n.reviewPromptYes),
          ),
          const SizedBox(height: SandikSpace.sm),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(_Secim.sonra),
                  child: Text(
                    l10n.reviewPromptLater,
                    style: context.t.labelLarge?.copyWith(color: c.text58),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(_Secim.sorun),
                  child: Text(
                    l10n.reviewPromptIssue,
                    style: context.t.labelLarge?.copyWith(color: c.text58),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
