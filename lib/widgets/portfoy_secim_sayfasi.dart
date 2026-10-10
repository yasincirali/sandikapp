import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../models/asset.dart';
import '../models/gorunum_kapsami.dart';
import '../models/portfoy.dart';
import '../providers/portfoy_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/crash_reporter.dart';
import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'kismi_aktarim_sayfasi.dart';
import 'portfoy_secici.dart';

/// Pozisyon işlemlerinde portföy sorusu (çoklu portföy, 0133).
///
/// ## Neden soru (karışık pozisyon)
/// "Tümü" görünümünde aynı sembol iki portföydeyse satır havuzun
/// ortalamasını gösterir (bugünkü kullanıcı toplamı, değişmez). Satış ya da
/// temettü ise TEK bir portföyün defterine yazılmalı: portföy belirsiz
/// kalırsa satış Ana'ya düşer, Ana'da eksi pozisyon, öbür portföyde fazla
/// miktar kalırdı ("Σ portföy == Tümü" kırılır). Kullanıcıya hangi
/// portföyün pozisyonu olduğu sorulur; işlem o pozisyonun miktarı ve
/// ağırlıklı maliyetiyle yazılır. Lotların hepsi tek portföydeyse soru
/// çıkmaz — davranış bayrak öncesiyle aynı.

/// [varlik] karışıksa kullanıcıya portföyü sorar ve O PORTFÖYÜN pozisyon
/// görünümünü döndürür; karışık değilse [varlik]'ın kendisi (hiçbir şey
/// okunmaz, bayrak kapalıyken bu yol hep böyledir). Vazgeçilirse `null`.
///
/// `WidgetRef` almaz: temettü diyaloğu bildirimden (widget ağacı dışından)
/// da açılır; sağlayıcılar context'in kabından okunur.
Future<Asset?> islemIcinPozisyon(BuildContext context, Asset varlik) async {
  if (!varlik.portfoyKarisik || !RemoteConfigService.instance.cokluPortfoy) {
    return varlik;
  }
  final kap = ProviderScope.containerOf(context, listen: false);
  final defter = kap.read(portfolioProvider).valueOrNull?.assets ?? const [];
  final liste = kap.read(portfoylerProvider).valueOrNull ?? const <Portfoy>[];
  final bilinen = _bilinen(liste);
  final parcalar = portfoyParcalari(defter, varlik, bilinen);
  if (parcalar.isEmpty) return null;
  Asset gorunum(String? id) =>
      parcalar[id]!.asDisplayAsset().copyWithPortfoy(id);
  if (parcalar.length == 1) return gorunum(parcalar.keys.single);

  final l = context.l10n;
  final secim = await _portfoySor(
    context,
    baslik: l.portfoyIslemSec,
    aciklama: l.portfoyIslemSecAciklama,
    secenekler: [
      for (final e in parcalar.entries)
        _Secenek(
          anahtar: e.key ?? PortfoySecimi.ana,
          ad: _ad(liste, l, e.key),
          alt: e.value.asDisplayAsset().miktarMetni(
              e.value.totalQuantity, (v, d) => fmtNum(v, digits: d)),
        ),
    ],
  );
  if (secim == null) return null;
  return gorunum(secim == PortfoySecimi.ana ? null : secim);
}

/// Pozisyonu başka portföye taşır (kaynak karışıksa önce sorar): hedef
/// seçilince miktar sorulur — "Tamamı" bütün pozisyonu geçmişiyle taşır
/// (`PortfolioNotifier.pozisyonuTasi`), "Bir kısmı" Premium ve orantılı
/// böler (`pozisyonuKismiTasi`, 0136).
Future<void> pozisyonuTasiAkisi(
  BuildContext context,
  WidgetRef ref,
  Asset varlik,
) async {
  if (DemoModu.yazmaKapisi('portfoy')) return; // Demo: hesap ister (F1).
  final l = context.l10n;
  final defter = ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
  final liste = ref.read(portfoylerProvider).valueOrNull ?? const <Portfoy>[];
  final bilinen = _bilinen(liste);

  String? kaynak = lotunPortfoyu(varlik, bilinen);
  if (varlik.portfoyKarisik) {
    final parcalar = portfoyParcalari(defter, varlik, bilinen);
    final s = await _portfoySor(
      context,
      baslik: l.portfoyKaynakSec,
      secenekler: [
        for (final e in parcalar.entries)
          _Secenek(
            anahtar: e.key ?? PortfoySecimi.ana,
            ad: _ad(liste, l, e.key),
            alt: e.value.asDisplayAsset().miktarMetni(
                e.value.totalQuantity, (v, d) => fmtNum(v, digits: d)),
          ),
      ],
    );
    if (s == null || !context.mounted) return;
    kaynak = s == PortfoySecimi.ana ? null : s;
  }

  final hedefler = <_Secenek>[
    if (kaynak != null)
      _Secenek(anahtar: PortfoySecimi.ana, ad: l.portfoyAnaUzun),
    for (final p in liste)
      if (p.id != kaynak) _Secenek(anahtar: p.id, ad: p.ad),
  ];
  String? hedef;
  if (hedefler.isEmpty) {
    // Taşınacak başka portföy yok: yeni portföy açılır (sınır kapısıyla).
    final yeni = await yeniPortfoyAkisi(context, ref, sec: false);
    if (yeni == null || !context.mounted) return;
    hedef = yeni.id;
  } else {
    final s = await _portfoySor(
      context,
      baslik: l.portfoyTasiBaslik,
      aciklama: l.portfoyTasiAciklama,
      secenekler: hedefler,
    );
    if (s == null || !context.mounted) return;
    hedef = s == PortfoySecimi.ana ? null : s;
  }

  final lotlar = tasinacakLotlar(defter, varlik, kaynak, bilinen);
  final hedefAdi = hedef == null
      ? l.portfoyAnaUzun
      : _ad(ref.read(portfoylerProvider).valueOrNull ?? liste, l, hedef);

  /// Tamamı (`pozisyonuTasi`) ya da orantılı pay (`pozisyonuKismiTasi`,
  /// Premium, 0136). Başarıda `true`; hata snack'le söylenir.
  Future<bool> tasi(double? oran, String bildiri) async {
    final n = ref.read(portfolioProvider.notifier);
    try {
      oran == null
          ? await n.pozisyonuTasi(lotlar, hedef)
          : await n.pozisyonuKismiTasi(lotlar, oran, hedef);
      if (context.mounted) {
        sandikSnack(context, bildiri, kind: SandikSnackKind.success);
      }
      return true;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'pozisyonuTasiAkisi');
      // Yarım taşıma (bkz. `lotlarinPortfoyunuYaz`) defteri sunucudan
      // tazeler; kısmi aktarım sunucuda tek işlem, yarım kalmaz.
      if (oran == null) ref.invalidate(portfolioProvider);
      if (context.mounted) {
        sandikSnackError(context, e, prefix: l.portfoyTasinamadi);
      }
      return false;
    }
  }

  // Sözleşmeli (BES/mevduat) pozisyon bölünmez: miktar sorulmaz.
  final parca = portfoyParcalari(defter, varlik, bilinen)[kaynak];
  final toplam = parca?.totalQuantity ?? 0;
  if (lotlar.any((a) => a.sozlesmeId != null) || parca == null || toplam <= 0) {
    await tasi(null, l.portfoyTasindi(hedefAdi));
    return;
  }
  if (!context.mounted) return;
  final gorunum = parca.asDisplayAsset();
  await showKismiAktarimSayfasi(
    context,
    gorunum: gorunum,
    toplam: toplam,
    hedefAdi: hedefAdi,
    aktar: (miktar) {
      // Yuvarlama payı: "hepsini" yazan kullanıcı bölme değil taşıma ister.
      if (miktar >= toplam * (1 - 1e-9)) {
        return tasi(null, l.portfoyTasindi(hedefAdi));
      }
      return tasi(
        miktar / toplam,
        l.portfoyAktarildi(
            gorunum.miktarMetni(miktar, (v, d) => fmtNum(v, digits: d)),
            hedefAdi),
      );
    },
  );
}

Set<String> _bilinen(List<Portfoy> liste) => {for (final p in liste) p.id};

/// Portföyün adı; `null` ya da listede olmayan kimlik Ana
/// (`lotunPortfoyu` ile aynı kural).
String _ad(List<Portfoy> liste, AppLocalizations l, String? id) {
  for (final p in liste) {
    if (p.id == id) return p.ad;
  }
  return l.portfoyAnaUzun;
}

class _Secenek {
  const _Secenek({required this.anahtar, required this.ad, this.alt});
  final String anahtar;
  final String ad;
  final String? alt;
}

Future<String?> _portfoySor(
  BuildContext context, {
  required String baslik,
  String? aciklama,
  required List<_Secenek> secenekler,
}) =>
    showSandikSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(SandikSpace.screenH(ctx), SandikSpace.md,
              SandikSpace.screenH(ctx), SandikSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SandikTutamac()),
              const SizedBox(height: SandikSpace.md),
              Text(
                baslik,
                style: ctx.t.titleLarge?.copyWith(
                    color: ctx.c.text90, fontWeight: FontWeight.w700),
              ),
              if (aciklama != null) ...[
                const SizedBox(height: SandikSpace.xs),
                Text(aciklama,
                    style: ctx.t.bodyMedium?.copyWith(color: ctx.c.text58)),
              ],
              const SizedBox(height: SandikSpace.md),
              for (final s in secenekler) ...[
                SandikTappable(
                  key: ValueKey('portfoy-secenek-${s.anahtar}'),
                  onTap: () => Navigator.pop(ctx, s.anahtar),
                  semanticLabel: s.alt == null ? s.ad : '${s.ad}, ${s.alt}',
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: SandikTouch.min),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.md,
                          vertical: SandikSpace.smd),
                      decoration: ctx.chip(selected: false),
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(s.ad,
                                  style: ctx.t.titleSmall?.copyWith(
                                      color: ctx.c.text90,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (s.alt != null) ...[
                              const SizedBox(width: SandikSpace.sm),
                              Text(s.alt!,
                                  style: ctx.t.bodyMedium
                                      ?.copyWith(color: ctx.c.text58)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SandikSpace.sm),
              ],
            ],
          ),
        ),
      ),
    );
