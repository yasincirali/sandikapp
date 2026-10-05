import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/analiz_provider.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../services/varlik_analizi.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import 'analiz_notu_screen.dart';
import 'hafta_ozeti_screen.dart' show HaftaRozetCipi;

/// Aylık rapor (S18-B, 2026-10-05) — tek özet cümlesi + varlık kartları.
///
/// Rapor, tuttuğun her varlığın o ayki yapay zekâ notunun bir araya
/// gelmesidir; ayrı bir "portföy yorumu" üretilmez (portföyün aylık
/// getirisi Performans'ta, tek kaynak orası). Özet cümlesi yalnız sayar:
/// kaç varlığın notu var, kaçında belirgin hareket (rozet ≠ sakin) olmuş.
/// Sıra haftanın özetiyle aynı (rozet önemi), kullanıcı iki ekranı aynı
/// mantıkla okur.
class AylikRaporScreen extends ConsumerWidget {
  const AylikRaporScreen({super.key, required this.donem});

  /// Ayın 1'i.
  final DateTime donem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final ay = DateFormat('MMMM y', Localizations.localeOf(context).toString())
        .format(donem);
    final anahtarlar = ref.watch(tutulanNotAnahtarlariProvider);
    final notlar =
        ref.watch(notOzetleriProvider(notKumesi(anahtarlar, 'aylik')));

    return Scaffold(
      appBar: SandikAppBar(title: l10n.anzAylikBaslik(ay)),
      body: notlar.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(SandikSpace.md),
          child: SandikSkeletonList(rows: 3),
        ),
        error: (_, __) => _Bos(metin: l10n.anzAylikBos),
        data: (m) {
          final buAy = [
            for (final n in m.values)
              if (n.donem == donem) n
          ]..sort((a, b) {
              final ra =
                  (haftaRozetiSunucudan(a.rozet) ?? HaftaRozeti.sakin).index;
              final rb =
                  (haftaRozetiSunucudan(b.rozet) ?? HaftaRozeti.sakin).index;
              return ra != rb ? ra - rb : a.ticker.compareTo(b.ticker);
            });
          if (buAy.isEmpty) return _Bos(metin: l10n.anzAylikBos);
          final hareketli = buAy.where((n) => n.rozet != 'sakin').length;
          final yatay = SandikSpace.screenH(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(
                yatay, SandikSpace.md, yatay, SandikSpace.xl),
            children: [
              Text(
                hareketli > 0
                    ? l10n.anzAylikOzetVar('${buAy.length}', '$hareketli')
                    : l10n.anzAylikOzetYok,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90),
              ),
              const SizedBox(height: SandikSpace.md),
              for (final n in buAy) ...[
                _VarlikKarti(not: n),
                const SizedBox(height: SandikSpace.smd),
              ],
              Text(l10n.rdrHaftaKaynak,
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
          child: Text(metin,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
        ),
      );
}

class _VarlikKarti extends StatelessWidget {
  const _VarlikKarti({required this.not});

  final AnalizOzeti not;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final kod = notKodu(not.ticker);
    final rozet = haftaRozetiSunucudan(not.rozet);
    void ac() => pushGuarded(
          context,
          adaptiveRoute<void>(
            builder: (_) => AnalizNotuScreen(
              ticker: not.ticker,
              tur: 'aylik',
              donem: not.donem,
              kod: kod,
              baslik: not.baslik,
            ),
          ),
        );
    return SandikCard(
      onTap: ac,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kod,
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ),
              if (rozet != null) HaftaRozetCipi(rozet: rozet),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(not.baslik, style: t.bodyMedium?.copyWith(color: c.text90)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
              onPressed: ac,
              child: Text(l10n.anzNotuOku),
            ),
          ),
        ],
      ),
    );
  }
}
