import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../services/disa_aktarim/disa_aktarim_service.dart';
import '../services/portfoy_yorumu_service.dart';
import '../services/share_card_service.dart';
import '../services/yorum_notu.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart' show showAppError;
import 'sandik_async_button.dart';

/// AI yorumunun "Tamamını oku" açılır sayfası (1A, 2026-10-14).
///
/// Önce rakamlar (manşet + gruplu satırlar), sonra konu başlıklı yorum;
/// "PDF olarak paylaş" altta SABİT (uzun yorumda kaybolmaz). PDF düzeni
/// `yorum_notu_pdf.dart`, hangi ölçümün nerede durduğu [YorumNotu].
/// Kart zaten `portfoy_ai_yorumu` bayrağının ve Premium kilidinin
/// arkasında; sayfa ayrıca bayrak istemez (yasin 14 Eki: "ekstra flag
/// eklemeden").
Future<void> showYorumNotu(BuildContext context, YorumNotu notu) =>
    showSandikSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => YorumNotuSayfasi(notu: notu),
    );

class YorumNotuSayfasi extends StatelessWidget {
  const YorumNotuSayfasi({super.key, required this.notu});

  final YorumNotu notu;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final t = context.t;
    final yatay = SandikSpace.screenH(context);
    final y = notu.yorum;
    final gunAy = DateFormat('d MMM y', Localizations.localeOf(context).toString());
    final ust = notu.kapsam == YorumKapsami.varlik
        ? l.pyzNotVarlik
        : l.pyzNotPortfoy;
    final baslik = notu.kapsam == YorumKapsami.varlik && notu.varlikAdi != null
        ? '${notu.varlikAdi} · ${notu.donemAdi}'
        : notu.donemAdi;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: sc,
              padding: EdgeInsets.fromLTRB(yatay, 0, yatay, SandikSpace.lg),
              children: [
                Text(ust.toUpperCase(),
                    style: t.labelSmall?.copyWith(
                        color: c.text58, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                const SizedBox(height: SandikSpace.xxs),
                Text(baslik,
                    style: t.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
                const SizedBox(height: SandikSpace.xxs),
                Text(l.flowRange(gunAy.format(y.baslangic), gunAy.format(y.bitis)),
                    style: t.bodySmall?.copyWith(color: c.text58)),
                if (notu.manset case final m?) ...[
                  const SizedBox(height: SandikSpace.md),
                  _Manset(manset: m, alt: notu.mansetAlt),
                ],
                if (notu.digerleri.isNotEmpty) ...[
                  const SizedBox(height: SandikSpace.md),
                  SandikCard(
                    elevated: true,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < notu.digerleri.length; i++)
                          _Satir(
                            olcum: notu.digerleri[i],
                            sonuncu: i == notu.digerleri.length - 1,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: SandikSpace.lg),
                SandikSectionHeader(title: l.pyzNotDegerlendirme),
                const SizedBox(height: SandikSpace.sm),
                Text(y.baslik,
                    style: t.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700, color: c.text90)),
                for (final m in y.maddeler) ...[
                  const SizedBox(height: SandikSpace.smd),
                  Text.rich(
                    TextSpan(children: [
                      if (m.konu case final k?)
                        TextSpan(
                            text: '$k. ',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: m.metin),
                    ]),
                    style: t.bodyMedium?.copyWith(color: c.text90),
                  ),
                ],
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface1,
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    yatay, SandikSpace.smd, yatay, SandikSpace.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (bctx) => SandikAsyncButton(
                        icon: Icon(Icons.adaptive.share),
                        onPressed: () => _paylas(bctx),
                        child: Text(l.pyzPdfPaylas),
                      ),
                    ),
                    const SizedBox(height: SandikSpace.xs2),
                    Text(l.pyzNotAlt,
                        textAlign: TextAlign.center,
                        style: t.labelSmall?.copyWith(color: c.text36)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _paylas(BuildContext context) async {
    try {
      await DisaAktarimService.instance.yorumNotuPaylas(
        notu,
        kaynak: ShareCardService.originOf(context),
      );
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    }
  }
}

class _Manset extends StatelessWidget {
  const _Manset({required this.manset, required this.alt});

  final YorumOlcumu manset;
  final YorumOlcumu? alt;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(manset.gosterim,
                style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _isaretRengi(context, manset.gosterim),
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              [
                YorumNotu.kisaAd(manset),
                if (alt case final a?) '${YorumNotu.kisaAd(a)} ${a.gosterim}',
              ].join('\n'),
              textAlign: TextAlign.end,
              style: t.bodySmall?.copyWith(color: c.text58),
            ),
          ),
        ],
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.olcum, required this.sonuncu});

  final YorumOlcumu olcum;
  final bool sonuncu;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        padding: const EdgeInsets.symmetric(
            horizontal: SandikSpace.smd, vertical: SandikSpace.sm),
        decoration: sonuncu
            ? null
            : BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(YorumNotu.kisaAd(olcum),
                  style: t.bodySmall?.copyWith(color: c.text58)),
            ),
            const SizedBox(width: SandikSpace.sm),
            // Büyük yazıda (3.1×) değer alt satıra kayar, kesilmez.
            Expanded(
              flex: 2,
              child: Text(olcum.gosterim,
                  textAlign: TextAlign.end,
                  style: t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _isaretRengi(context, olcum.gosterim),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }
}

/// İşaret metinde yazılı (+/−); renk yalnız pekiştirir (renk körlüğü).
Color _isaretRengi(BuildContext context, String gosterim) {
  final c = context.c;
  final s = gosterim.trim();
  if (s.startsWith('+')) return c.gain;
  if (s.startsWith('−') || s.startsWith('-')) return c.loss;
  return c.text90;
}
