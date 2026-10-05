import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/analiz_provider.dart';
import '../providers/hafta_ozeti_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/fon_akisi.dart' show fonHaftaOrani;
import '../services/varlik_analizi.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/para_akisi_karti.dart' show isaretliTutar;
import '../widgets/radar_ortak.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_skeleton.dart';
import 'analiz_notu_screen.dart';
import 'asset_detail_screen.dart';
import 'aylik_rapor_screen.dart';

/// "Haftanın özeti" (Balina B4 2026-10-04; tek liste S6-B + notlar S16-B,
/// 2026-10-05) — tuttuğun her varlığın son haftası, önem sırasıyla.
///
/// ## Neden tek liste
/// Eski ekran fonları ve hacim günlerini iki ayrı bölümde gösteriyordu;
/// kullanıcı "bu hafta neyim kıpırdadı" diye soruyor, varlık türüne göre
/// değil. Başlık tek cümleyle cevaplar ("3 varlığında olağandışı hareket
/// var"), liste önce olağandışıları, sonra hareketlileri, en sonda sakinleri
/// sıralar. Her satırda bir rozet: ne olduğunu kelimeyle söyler, renk yalnız
/// yönü (giriş/çıkış, alıcı/satıcı) taşır.
///
/// ## Notlar burada (S16-B)
/// Yapay zekâ notunun başlığı ilgili satırın altında "Not:" olarak durur;
/// ayrı bir "Notlar" ekranı yok, kullanıcı iki listeyi eşleştirmek zorunda
/// kalmaz. Aylık rapor varsa en üstte tek satır.
///
/// ## Ne göstermez
/// Portföyün haftalık yüzdesi burada YOK: o rakam Performans › Özet'te ve
/// tek kaynağı orası. Haber de yok — lisanslı kaynağımız yok.
///
/// Satır sayıları kartlarla AYNI provider'lardan (`haftaOzetiProvider`).
class HaftaOzetiScreen extends ConsumerWidget {
  const HaftaOzetiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final liste = ref.watch(haftaOzetiProvider);
    final sakinGoster = ref.watch(haftaSakinGosterProvider);

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
        data: (tum) {
          if (tum.isEmpty) return _Bos(metin: l10n.weekEmptyNoData);
          final anahtarlar = [for (final s in tum) s.anahtar];
          final notlar = ref
                  .watch(notOzetleriProvider(notKumesi(anahtarlar, 'haftalik')))
                  .valueOrNull ??
              const <String, AnalizOzeti>{};
          final aylik = ref
                  .watch(notOzetleriProvider(notKumesi(anahtarlar, 'aylik')))
                  .valueOrNull ??
              const <String, AnalizOzeti>{};
          final olagandisi = tum.where((s) => s.rozet.olagandisi).length;
          final satirlar = sakinGoster
              ? tum
              : [
                  for (final s in tum)
                    if (s.rozet != HaftaRozeti.sakin) s
                ];
          return ListView(
            padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
                SandikSpace.md, SandikSpace.screenH(context), SandikSpace.xl),
            children: [
              Text(
                olagandisi > 0
                    ? l10n.rdrHaftaBaslikVar('$olagandisi')
                    : l10n.rdrHaftaBaslikYok,
                style: t.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: c.text90),
              ),
              if (aylik.isNotEmpty) ...[
                const SizedBox(height: SandikSpace.md),
                _AylikRaporSatiri(notlar: aylik),
              ],
              const SizedBox(height: SandikSpace.md),
              if (satirlar.isNotEmpty)
                SandikCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SandikSpace.md, vertical: SandikSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < satirlar.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, thickness: 1, color: c.hairline),
                        _Satir(
                            satir: satirlar[i],
                            not: notlar[satirlar[i].anahtar]),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: SandikSpace.md),
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
          child: Text(
            metin,
            textAlign: TextAlign.center,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58),
          ),
        ),
      );
}

/// Rozet çipi: kelime her zaman, renk yalnız yönde.
class HaftaRozetCipi extends StatelessWidget {
  const HaftaRozetCipi({super.key, required this.rozet});

  final HaftaRozeti rozet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final (metin, renk) = switch (rozet) {
      HaftaRozeti.buyukGiris => (l10n.rdrRozetBuyukGiris, c.gain),
      HaftaRozeti.buyukCikis => (l10n.rdrRozetBuyukCikis, c.loss),
      HaftaRozeti.olagandisiHacim => (l10n.rdrRozetHacim, c.amberText),
      HaftaRozeti.aliciIstekli => (l10n.rdrRozetAlici, c.gain),
      HaftaRozeti.saticiIstekli => (l10n.rdrRozetSatici, c.loss),
      HaftaRozeti.hareketli => (l10n.rdrRozetHareketli, c.text90),
      HaftaRozeti.sakin => (l10n.rdrRozetSakin, null),
    };
    return RozetCipi(metin: metin, renk: renk);
  }
}

class _AylikRaporSatiri extends StatelessWidget {
  const _AylikRaporSatiri({required this.notlar});

  final Map<String, AnalizOzeti> notlar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    // En yeni ay: birden çok ay dönebilir (bayatlık sınırı iki ay).
    final donem = notlar.values
        .map((n) => n.donem)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final ay = DateFormat('MMMM y', Localizations.localeOf(context).toString())
        .format(donem);
    return SandikCard(
      onTap: () => pushGuarded(
        context,
        adaptiveRoute<void>(builder: (_) => AylikRaporScreen(donem: donem)),
      ),
      child: Row(
        children: [
          Icon(Icons.summarize_outlined, color: c.amberText),
          const SizedBox(width: SandikSpace.smd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.anzAylikUpper,
                    style: t.labelSmall?.copyWith(
                        color: c.text58,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
                Text(l10n.rdrAylikRaporSatir(ay),
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, color: c.text90)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.text36),
        ],
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.satir, required this.not});

  final HaftaSatiri satir;
  final AnalizOzeti? not;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final varlik = satir.pozisyon.representative;
    // Kripto sembolü `KRIPTO:BTC` biçiminde saklanır; `displayTicker` öneki
    // atmaz. Notla aynı kısa adı kullan.
    final kod = notKodu(satir.anahtar);
    final not = this.not;

    return InkWell(
      onTap: () => pushGuarded(
        context,
        adaptiveRoute<void>(
          builder: (_) => AssetDetailScreen(
            asset: satir.pozisyon.asDisplayAsset(),
            showBackButton: true,
            lots: satir.pozisyon.lots,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Wrap: büyük yazıda (1,6×) rozet tek başına 255 px tutuyor;
            // dar ekranda kodun yanına sığmazsa alt satıra iner.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: SandikSpace.sm,
              runSpacing: SandikSpace.xxs,
              children: [
                Text(
                  kod,
                  style: t.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: c.text90),
                ),
                HaftaRozetCipi(rozet: satir.rozet),
              ],
            ),
            const SizedBox(height: SandikSpace.xxs),
            // Ad uzun olabilir; kesilmez, alt satıra iner.
            Text(varlik.name, style: t.bodySmall?.copyWith(color: c.text58)),
            const SizedBox(height: SandikSpace.xs),
            for (final cumle in satirCumleleri(context, satir))
              Text(cumle,
                  style: t.bodyMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600)),
            if (not != null) ...[
              const SizedBox(height: SandikSpace.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(l10n.rdrSatirNot(not.baslik),
                        style: t.bodySmall?.copyWith(color: c.text58)),
                  ),
                  TextButton(
                    style:
                        TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                    onPressed: () => pushGuarded(
                      context,
                      adaptiveRoute<void>(
                        builder: (_) => AnalizNotuScreen(
                          ticker: not.ticker,
                          tur: 'haftalik',
                          donem: not.donem,
                          kod: kod,
                          baslik: not.baslik,
                        ),
                      ),
                    ),
                    child: Text(l10n.rdrOku),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satırın sayı cümleleri — kartlarla aynı biçimleyiciler. Fon: net akış ve
/// büyüklüğe oranı; hisse: olağandışı gün (yoksa son gün) katı ve fiyat;
/// kripto: alıcı payı (+ varsa olağandışı hacim günü).
List<String> satirCumleleri(BuildContext context, HaftaSatiri s) {
  final l10n = context.l10n;
  final gunAy = DateFormat('d MMM', Localizations.localeOf(context).toString());
  final fon = s.fon;
  if (fon != null) {
    final net = isaretliTutar(fon.sonHaftaNet);
    final oran = fonHaftaOrani(fon);
    return [
      oran != null
          ? l10n.rdrSatirFon(net, fmtPct(oran.abs() * 100, digits: 1))
          : l10n.rdrSatirFonOransiz(net),
    ];
  }
  final h = s.hacim!;
  final olay = s.hacimOlayi;
  final cumleler = <String>[];
  if (s.tur == HaftaVarlikTuru.kripto && h.aliciPayi != null) {
    // Haftalık listede önce hafta (rozetin dayandığı sayı), sonra son gün.
    final pay = fmtPct(h.aliciPayi! * 100, digits: 1);
    cumleler.add(h.aliciPayi7 == null
        ? l10n.rdrSatirKriptoOrtsuz(pay)
        // Yer tutucu sırası metindeki sıradır: (ort, yuzde).
        : l10n.rdrSatirKripto(fmtPct(h.aliciPayi7! * 100, digits: 1), pay));
  }
  if (olay != null) {
    cumleler.add(l10n.rdrSatirHacim(
        gunAy.format(olay.tarih),
        fmtNum(olay.ortalamaKati, digits: 1),
        fmtPctIsaretli(olay.fiyatDegisim * 100, digits: 1)));
  } else if (s.tur == HaftaVarlikTuru.hisse &&
      h.kat != null &&
      h.fiyatDegisim != null) {
    cumleler.add(l10n.rdrSatirHacim(
        gunAy.format(h.sonGun.tarih),
        fmtNum(h.kat!, digits: 1),
        fmtPctIsaretli(h.fiyatDegisim! * 100, digits: 1)));
  }
  return cumleler;
}
