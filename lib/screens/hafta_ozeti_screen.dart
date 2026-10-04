import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../services/fon_akisi.dart';
import '../theme/sandik.dart';
import '../widgets/para_akisi_karti.dart' show isaretliTutar;
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import 'asset_detail_screen.dart';

/// "Haftanın özeti" (Balina B4, 2026-10-04) — tuttuğun fonların son hafta
/// para akışı tek listede.
///
/// ## Neden var
/// Haftalık bildirim "DOV fonunda büyük para çıkışı oldu" der; kullanıcı
/// dokununca O cümlenin karşılığını görmeli. Fon fon gezmek yerine hepsi tek
/// ekranda, ayrıntı için satıra dokununca fonun kendi sayfası (kart orada).
///
/// ## Ne göstermez
/// Portföyün haftalık yüzdesi burada YOK: o rakam Performans › Özet'te ve
/// tek kaynağı orası. İkinci bir yerde hesaplamak iki sayının çelişmesi
/// demek olurdu. Haber de yok — lisanslı kaynağımız yok.
///
/// Satır sayıları `fonAkisiProvider`'dan: fon sayfasındaki kartla aynı.
class HaftaOzetiScreen extends ConsumerWidget {
  const HaftaOzetiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final liste = ref.watch(haftaOzetiProvider);

    return Scaffold(
      appBar: SandikAppBar(title: l10n.weekTitle),
      body: liste.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(SandikSpace.md),
          child: SandikSkeletonList(rows: 3),
        ),
        // Provider hata fırlatmaz (alt provider null döner); yine de düşerse
        // boş durumla aynı ekran — ham hata gösterilmez.
        error: (_, __) => _Bos(metin: l10n.weekEmptyNoData),
        data: (fonlar) {
          if (fonlar.isEmpty) return _Bos(metin: l10n.weekEmptyNoData);
          return ListView(
            padding: const EdgeInsets.fromLTRB(SandikSpace.md, SandikSpace.md,
                SandikSpace.md, SandikSpace.xl),
            children: [
              Text(l10n.weekIntro,
                  style: t.bodyMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.md),
              SandikSectionHeader(title: l10n.weekFundsUpper),
              const SizedBox(height: SandikSpace.sm),
              SandikCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < fonlar.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, thickness: 1, color: c.hairline),
                      _FonSatiri(fon: fonlar[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: SandikSpace.md),
              Text(l10n.weekFootnote,
                  style: t.bodySmall?.copyWith(color: c.text36)),
            ],
          );
        },
      ),
    );
  }
}

class _Bos extends StatelessWidget {
  const _Bos({required this.metin});
  final String metin;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SandikSpace.lg),
          child: Text(
            metin,
            textAlign: TextAlign.center,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
        ),
      );
}

class _FonSatiri extends StatelessWidget {
  const _FonSatiri({required this.fon});

  final FonHaftasi fon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final ozet = fon.ozet;
    final varlik = fon.pozisyon.representative;
    final net = ozet.sonHaftaNet;
    final renk = net > 0
        ? c.gain
        : net < 0
            ? c.loss
            : c.text90;
    final olay = sonHaftaOlayi(ozet);
    final kod = varlik.displayTicker ?? varlik.ticker;

    return InkWell(
      onTap: () => pushGuarded(
        context,
        adaptiveRoute<void>(
          builder: (_) => AssetDetailScreen(
            asset: fon.pozisyon.asDisplayAsset(),
            showBackButton: true,
            lots: fon.pozisyon.lots,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    kod,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  isaretliTutar(net),
                  style: t.numSmall
                      .copyWith(fontWeight: FontWeight.w700, color: renk),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.xxs),
            // Fon adı uzun olabilir; kesilmez, alt satıra iner.
            Text(varlik.name,
                style: t.bodySmall?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.xxs),
            Text(
              l10n.weekRowRange(
                net > 0
                    ? l10n.weekRowIn
                    : net < 0
                        ? l10n.weekRowOut
                        : l10n.weekRowFlat,
                l10n.flowRange(gunAy.format(ozet.sonHaftaIlkGun),
                    gunAy.format(ozet.veriTarihi)),
              ),
              style: t.bodySmall?.copyWith(color: c.text58),
            ),
            if (olay != null) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(
                olay.giris ? l10n.weekRowBigIn : l10n.weekRowBigOut,
                style: t.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: olay.giris ? c.gain : c.loss),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
