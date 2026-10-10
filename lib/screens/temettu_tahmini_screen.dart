import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/temettu_tahmini_provider.dart';
import '../services/temettu_tahmini.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';

/// Önümüzdeki 12 ayın temettü tahmini (Premium, 2026-10-10).
///
/// Kural `temettu_tahmini.dart`'ta ve ekranda cümleyle yazılı: son 12 ayın
/// gerçekleşmiş temettüsü bugünkü lotunla tekrarlanırsa. Sayılar "tahmini"
/// diye anılır; şirket kararı ya da yeni yıl beklentisi tahmin edilmez.
class TemettuTahminiScreen extends ConsumerWidget {
  const TemettuTahminiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Scaffold(
        appBar: SandikAppBar(title: l.ttBaslik),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.event_repeat_rounded,
            baslik: l.ttBaslik,
            govde: l.ttKilitGovde,
            kilitMetni: l.ttKilitSatir,
            kaynak: 'temettu_tahmini',
          ),
        ),
      );
    }
    final tahmin = ref.watch(temettuTahminiProvider);
    return Scaffold(
      appBar: SandikAppBar(title: l.ttBaslik),
      body: tahmin.when(
        loading: () => const SandikSkeletonList(rows: 4),
        error: (e, _) => SandikErrorView(
            error: e, onRetry: () => ref.invalidate(temettuTahminiProvider)),
        data: (t) => t.bos
            ? SandikBosDurum(metin: l.ttBos, alt: l.ttBosAlt)
            : _Govde(t: t),
      ),
    );
  }
}

class _Govde extends StatelessWidget {
  const _Govde({required this.t});

  final TemettuTahmini t;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final h = SandikSpace.screenH(context);
    final net = t.netTry;
    return ListView(
      padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
      children: [
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.ttToplamEtiket,
                  style: context.t.bodyMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs),
              Text(fmtTRY(net ?? t.brutTry),
                  style: context.t.numLarge
                      .copyWith(fontWeight: FontWeight.w800, color: c.gold)),
              const SizedBox(height: SandikSpace.xxs),
              Text(
                net == null
                    ? l.ttBrutNot
                    : l.ttNetNot(fmtTRY(t.brutTry)),
                style: context.t.bodySmall?.copyWith(color: c.text58),
              ),
              const SizedBox(height: SandikSpace.md),
              _AyCubuklari(aylik: t.aylik),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.ttVarliklarUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            children: [
              for (var i = 0; i < t.satirlar.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.hairline),
                _Satir(s: t.satirlar[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.lg),
        Text(l.ttKural, style: context.t.bodySmall?.copyWith(color: c.text58)),
      ],
    );
  }
}

/// 12 ay, yan yana çubuk. Ölçek en büyük aya göre; boş ay ince taban
/// çizgisi kalır (sıfır yüksekliğinde çubuk "veri yok" ile karışmasın diye
/// taban her ayda çizilir). Ay adı cihaz dilinde, tek harfe kısalmaz.
class _AyCubuklari extends StatelessWidget {
  const _AyCubuklari({required this.aylik});

  final List<double> aylik;

  static const _yukseklik = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final enBuyuk = aylik.fold(0.0, (m, v) => v > m ? v : m);
    return Semantics(
      label: [
        for (var i = 0; i < 12; i++)
          if (aylik[i] > 0)
            '${DateFormat.MMMM(dil).format(DateTime(2000, i + 1))} ${fmtTRY(aylik[i])}',
      ].join(', '),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 12; i++)
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: SandikSpace.xxs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: enBuyuk <= 0
                            ? 2
                            : 2 + (_yukseklik - 2) * aylik[i] / enBuyuk,
                        decoration: BoxDecoration(
                          color: aylik[i] > 0 ? c.amberFill : c.hairline,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(SandikSpace.xs)),
                        ),
                      ),
                      const SizedBox(height: SandikSpace.xs),
                      FittedBox(
                        child: Text(
                          DateFormat.MMM(dil).format(DateTime(2000, i + 1)),
                          style: context.t.labelSmall
                              ?.copyWith(color: c.text58),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.s});

  final TahminSatiri s;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final aylar = s.aylar
        .map((m) => DateFormat.MMM(dil).format(DateTime(2000, m)))
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.ad,
                    style: context.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: c.text90)),
                const SizedBox(height: SandikSpace.xxs),
                Text(l.ttSatirAlt(fmtTRYFiyat(s.brutPay), aylar),
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.smd),
          Text(fmtTRY(s.netTry ?? s.brutTry),
              style: context.t.numSmall
                  .copyWith(fontWeight: FontWeight.w700, color: c.text90)),
        ],
      ),
    );
  }
}
