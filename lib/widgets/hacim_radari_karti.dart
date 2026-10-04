import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_akisi_provider.dart';
import '../services/hisse_hacmi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Hacim radarı kartı (Balina B2, 2026-10-04) — BIST hissesinin para hacmi.
///
/// Hesap `hisse_hacmi.dart`'ta (saf), veri `hisseHacmiProvider`'da, kural
/// sunucuda (`_shared/hacim.ts`); bu dosya yalnızca çizer.
///
/// ## Ne zaman HİÇ çizilmez
/// Bayrak (`balina_radari_acik`) kapalı, varlık BIST hissesi değil, veri
/// yok / bayat / okunamadı. Para akışı kartıyla aynı karar ve aynı bayrak.
///
/// ## Dil — fon kartından FARKLI ve bilinçli
/// Fonda pay adedi değiştiği için "para girdi/çıktı" ölçülebilir. Hissede
/// ölçülemez: her işlemin bir alıcısı ve bir satıcısı vardır. Bu yüzden
/// kart "giriş/çıkış" demez, çubuklar yeşil/kırmızı DEĞİL nötrdür; yön
/// yalnız o günün fiyat değişimi olarak yazılır. "Balina" denmez.
class HacimRadariKarti extends ConsumerWidget {
  const HacimRadariKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final sembol = bistSembolu(tur: tur, ticker: ticker);
    if (sembol == null) return const SizedBox.shrink();
    final ozet = ref.watch(hisseHacmiProvider(sembol)).valueOrNull;
    if (ozet == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final olayGunleri = {for (final o in ozet.olaylar) o.tarih};

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.volTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.volLastDay(gunAy.format(ozet.sonGun.tarih)),
                    style: t.bodyMedium?.copyWith(color: c.text58)),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  fmtTRYCompact(ozet.sonGun.paraHacmi),
                  style: t.numMedium.copyWith(color: c.text90),
                ),
                if (ozet.kat != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    l10n.volVsAverage(fmtNum(ozet.kat!, digits: 1)),
                    style: t.bodySmall?.copyWith(
                        color: c.text58, fontWeight: FontWeight.w600),
                  ),
                ],
                if (ozet.fiyatDegisim != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    l10n.volPriceSameDay(
                        fmtPctIsaretli(ozet.fiyatDegisim! * 100, digits: 1)),
                    style: t.bodySmall?.copyWith(color: c.text58),
                  ),
                ],
                const SizedBox(height: SandikSpace.md),
                Semantics(
                  label: l10n.volChartSemantics(
                      fmtTRYCompact(ozet.sonGun.paraHacmi)),
                  child: ExcludeSemantics(
                    child: _GunCubuklari(
                        gunler: ozet.gunler, vurgulu: olayGunleri),
                  ),
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.volChartCaption,
                    style: t.bodySmall?.copyWith(color: c.text36)),
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.volExplain,
                    style: t.bodySmall?.copyWith(color: c.text58)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.smd),
                  child: Divider(height: 1, thickness: 1, color: c.hairline),
                ),
                Text(
                  l10n.volEventsTitle,
                  style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: c.text90),
                ),
                const SizedBox(height: SandikSpace.sm),
                if (ozet.olaylar.isEmpty)
                  Text(l10n.volNoEvents,
                      style: t.bodySmall?.copyWith(color: c.text58))
                else
                  for (var i = 0; i < ozet.olaylar.length; i++) ...[
                    if (i > 0) const SizedBox(height: SandikSpace.smd),
                    _OlaySatiri(olay: ozet.olaylar[i], gunAy: gunAy),
                  ],
                const SizedBox(height: SandikSpace.md),
                Text(
                  l10n.volFootnote(gunAy.format(ozet.sonGun.tarih)),
                  style: t.bodySmall?.copyWith(color: c.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Günlük para hacmi çubukları. Renk NÖTR (hacim yön taşımaz); olağandışı
/// günler ve son gün koyu, diğerleri soluk.
class _GunCubuklari extends StatelessWidget {
  const _GunCubuklari({required this.gunler, required this.vurgulu});

  final List<HacimGunu> gunler;
  final Set<DateTime> vurgulu;

  static const double _boy = 64;
  static const double _enKisa = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var enBuyuk = 0.0;
    for (final g in gunler) {
      enBuyuk = math.max(enBuyuk, g.paraHacmi);
    }
    return SizedBox(
      height: _boy,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < gunler.length; i++) ...[
            if (i > 0) const SizedBox(width: SandikSpace.xxs),
            Expanded(
              child: Container(
                height: enBuyuk <= 0
                    ? _enKisa
                    : math.max(_enKisa, gunler[i].paraHacmi / enBuyuk * _boy),
                decoration: BoxDecoration(
                  color: vurgulu.contains(gunler[i].tarih) ||
                          i == gunler.length - 1
                      ? c.text90
                      : c.text20,
                  borderRadius: BorderRadius.circular(SandikSpace.xxs),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OlaySatiri extends StatelessWidget {
  const _OlaySatiri(
      {required this.olay, required this.gunAy, this.kripto = false});

  final HacimOlayi olay;
  final DateFormat gunAy;

  /// Kripto olayında tutar USDT'dir ve kanıta alıcı payı eklenir.
  final bool kripto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.volEventTitle(gunAy.format(olay.tarih)),
          style: t.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: c.text90),
        ),
        const SizedBox(height: SandikSpace.xxs),
        Text(
          kripto && olay.aliciPayi != null
              ? l10n.cryEventEvidence(
                  kisaDolar(olay.paraHacmi),
                  fmtNum(olay.ortalamaKati, digits: 1),
                  fmtPctIsaretli(olay.fiyatDegisim * 100, digits: 1),
                  fmtPct(olay.aliciPayi! * 100, digits: 1),
                )
              : l10n.volEventEvidence(
                  kripto
                      ? kisaDolar(olay.paraHacmi)
                      : fmtTRYCompact(olay.paraHacmi),
                  fmtNum(olay.ortalamaKati, digits: 1),
                  fmtPctIsaretli(olay.fiyatDegisim * 100, digits: 1),
                ),
          style: t.bodySmall?.copyWith(color: c.text58),
        ),
      ],
    );
  }
}

/// BIST hissesinin sunucudaki anahtarı (`THYAO.IS`); değilse null. Yabancı
/// hisse kapsam dışı — para hacmi TL olmazdı (sunucu da toplamıyor).
String? bistSembolu({required AssetType tur, required String ticker}) {
  if (tur != AssetType.hisse) return null;
  final t = ticker.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{2,10}\.IS$').hasMatch(t) ? t : null;
}

/// Kısa dolar tutarı (`$2,62Mr`, `$243,00M`) — TL kısaltmasıyla aynı kural,
/// yalnız simge farklı. Kripto hacmi USDT'dir; TL'ye çevrilmez.
String kisaDolar(double v) => fmtTRYCompact(v).replaceFirst('₺', r'$');

/// Uygulamadaki kripto ticker'ı ('KRIPTO:BTC'); değilse null. USDT'nin
/// kendisinin USDT paritesi yoktur.
String? kriptoTickeri({required AssetType tur, required String ticker}) {
  if (tur != AssetType.kripto) return null;
  final t = ticker.trim().toUpperCase();
  if (!RegExp(r'^KRIPTO:[A-Z0-9]{2,15}$').hasMatch(t)) return null;
  return t == 'KRIPTO:USDT' ? null : t;
}

/// Alıcı baskısı kartı (Balina B3, 2026-10-05) — coinin Binance USDT
/// paritesindeki günlük hacmi ve alıcı payı.
///
/// Hacim radarıyla aynı iskelet ve aynı bayrak; iki farkı var: tutarlar
/// USDT'dir ("$"), ve hissede ölçülemeyen ALICI PAYI burada ölçülür (Binance
/// her mumda piyasa emriyle alan tarafın hacmini verir). Pay %50 çevresinde
/// dolaşır; kart onu 7 günlük ortalamasıyla birlikte yazar, "giriş/çıkış"
/// demez. Kaynak yalnız Binance — kart bunu açıkça söyler.
class KriptoBaskiKarti extends ConsumerWidget {
  const KriptoBaskiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;
  final EdgeInsetsGeometry dis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(balinaRadariAcikProvider)) return const SizedBox.shrink();
    final anahtar = kriptoTickeri(tur: tur, ticker: ticker);
    if (anahtar == null) return const SizedBox.shrink();
    final ozet = ref.watch(kriptoBaskiProvider(anahtar)).valueOrNull;
    if (ozet == null || ozet.aliciPayi == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final gunAy =
        DateFormat('d MMM', Localizations.localeOf(context).toString());
    final olayGunleri = {for (final o in ozet.olaylar) o.tarih};

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l10n.cryTitleUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.cryShareLabel(gunAy.format(ozet.sonGun.tarih)),
                    style: t.bodyMedium?.copyWith(color: c.text58)),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  fmtPct(ozet.aliciPayi! * 100, digits: 1),
                  style: t.numMedium.copyWith(color: c.text90),
                ),
                if (ozet.aliciPayi7 != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(
                    l10n.cryShareAvg(fmtPct(ozet.aliciPayi7! * 100, digits: 1)),
                    style: t.bodySmall?.copyWith(
                        color: c.text58, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.cryExplain,
                    style: t.bodySmall?.copyWith(color: c.text58)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.smd),
                  child: Divider(height: 1, thickness: 1, color: c.hairline),
                ),
                Text(l10n.cryVolumeLabel(kisaDolar(ozet.sonGun.paraHacmi)),
                    style: t.bodyMedium?.copyWith(color: c.text90)),
                if (ozet.kat != null) ...[
                  const SizedBox(height: SandikSpace.xxs),
                  Text(l10n.volVsAverage(fmtNum(ozet.kat!, digits: 1)),
                      style: t.bodySmall?.copyWith(color: c.text58)),
                ],
                const SizedBox(height: SandikSpace.smd),
                Semantics(
                  label: l10n
                      .cryChartSemantics(kisaDolar(ozet.sonGun.paraHacmi)),
                  child: ExcludeSemantics(
                    child: _GunCubuklari(
                        gunler: ozet.gunler, vurgulu: olayGunleri),
                  ),
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(l10n.cryChartCaption,
                    style: t.bodySmall?.copyWith(color: c.text36)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.smd),
                  child: Divider(height: 1, thickness: 1, color: c.hairline),
                ),
                Text(
                  l10n.volEventsTitle,
                  style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: c.text90),
                ),
                const SizedBox(height: SandikSpace.sm),
                if (ozet.olaylar.isEmpty)
                  Text(l10n.volNoEvents,
                      style: t.bodySmall?.copyWith(color: c.text58))
                else
                  for (var i = 0; i < ozet.olaylar.length; i++) ...[
                    if (i > 0) const SizedBox(height: SandikSpace.smd),
                    _OlaySatiri(
                        olay: ozet.olaylar[i], gunAy: gunAy, kripto: true),
                  ],
                const SizedBox(height: SandikSpace.md),
                Text(
                  l10n.cryFootnote(gunAy.format(ozet.sonGun.tarih)),
                  style: t.bodySmall?.copyWith(color: c.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
