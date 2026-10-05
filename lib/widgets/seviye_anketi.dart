import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/preferences_provider.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';

/// Yatırımcı seviyesini üç soruyla belirleyen kompakt anket (2026-10-04).
///
/// İki yerde kullanılır: tanıtım turunun seviye adımı (kart içinde, dar) ve
/// Ayarlar › Görünüm'deki "3 soruyla seviyemi bul" sayfası. Sonuç AYNI
/// tercihe yazılır (`investorLevelIndexProvider`); ikinci bir kaynak yok.
///
/// Soru tek tek gelir: kart küçük, üç soruyu alt alta dizmek turu
/// kaydırmalı yapardı. Cevaba dokunmak bir sonraki soruya geçirir; son
/// cevapta seviye yazılır ve sonuç cümlesi görünür. Puanlama saf fonksiyonda
/// ([seviyeAnketSonucu]) ve testli.
class SeviyeAnketi extends ConsumerStatefulWidget {
  const SeviyeAnketi({super.key, this.onBitti});

  /// Seviye yazıldıktan sonra çağrılır (Ayarlar sayfası kapanmak için).
  final ValueChanged<YatirimciSeviyesi>? onBitti;

  @override
  ConsumerState<SeviyeAnketi> createState() => _SeviyeAnketiState();
}

class _SeviyeAnketiState extends ConsumerState<SeviyeAnketi> {
  final _cevaplar = <int>[];
  YatirimciSeviyesi? _sonuc;

  List<(String, List<String>)> _sorular(BuildContext context) {
    final l = context.l10n;
    return [
      (l.levelSurveyQ1, [l.levelSurveyQ1A0, l.levelSurveyQ1A1, l.levelSurveyQ1A2]),
      (l.levelSurveyQ2, [l.levelSurveyQ2A0, l.levelSurveyQ2A1, l.levelSurveyQ2A2]),
      (l.levelSurveyQ3, [l.levelSurveyQ3A0, l.levelSurveyQ3A1, l.levelSurveyQ3A2]),
    ];
  }

  void _cevapla(int puan) {
    setState(() => _cevaplar.add(puan));
    if (_cevaplar.length < seviyeAnketSoruSayisi) return;
    final s = seviyeAnketSonucu(_cevaplar);
    if (s == null) return;
    ref.read(investorLevelIndexProvider.notifier).set(s.index);
    AnalyticsService.instance.logSignupStep('seviye_anketi_${s.name}');
    setState(() => _sonuc = s);
    widget.onBitti?.call(s);
  }

  void _bastan() => setState(() {
        _cevaplar.clear();
        _sonuc = null;
      });

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    final sonuc = _sonuc;
    if (sonuc != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sonuc.ikon, size: 22, color: p.amberText),
              const SizedBox(width: SandikSpace.sm),
              Expanded(
                child: Text(
                  context.l10n.levelSurveyResult(sonuc.etiket(context)),
                  style: context.t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: p.text90),
                ),
              ),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            '${sonuc.aciklama(context)} '
            '${context.l10n.levelSurveyResultNote}',
            style: context.t.bodySmall?.copyWith(color: p.text58, height: 1.4),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: SandikTouch.minSize,
            onPressed: _bastan,
            child: Text(context.l10n.levelSurveyRetake,
                style: context.t.bodyMedium?.copyWith(color: p.amberText)),
          ),
        ],
      );
    }

    final sorular = _sorular(context);
    final no = _cevaplar.length;
    final (soru, secenekler) = sorular[no];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.levelSurveyProgress(no + 1, sorular.length),
                style: context.t.labelMedium?.copyWith(color: p.text36),
              ),
            ),
            if (no > 0)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: SandikTouch.minSize,
                onPressed: () => setState(_cevaplar.removeLast),
                child: Text(context.l10n.levelSurveyBack,
                    style: context.t.labelLarge?.copyWith(color: p.text58)),
              ),
          ],
        ),
        Text(
          soru,
          style: context.t.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600, color: p.text90),
        ),
        const SizedBox(height: SandikSpace.sm),
        for (var i = 0; i < secenekler.length; i++) ...[
          SandikTappable(
            semanticLabel: secenekler[i],
            onTap: () => _cevapla(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.smd, vertical: SandikSpace.sm),
              decoration: context.surfaceCard(radius: SandikRadius.sm),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      secenekler[i],
                      style: context.t.bodyMedium?.copyWith(color: p.text90),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: p.text36),
                ],
              ),
            ),
          ),
          if (i < secenekler.length - 1)
            const SizedBox(height: SandikSpace.xs2),
        ],
      ],
    );
  }
}

/// Ayarlar › Görünüm'den açılan anket sayfası.
Future<void> seviyeAnketiniAc(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.background,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SandikSpace.lg, SandikSpace.lg, SandikSpace.lg, SandikSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ctx.l10n.levelSurveyIntro,
              style: ctx.t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: ctx.c.text90),
            ),
            const SizedBox(height: SandikSpace.md),
            const SeviyeAnketi(),
          ],
        ),
      ),
    ),
  );
}
