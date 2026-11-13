import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/kapanis_ozeti.dart';
import '../providers/preferences_provider.dart'
    show balanceHiddenProvider, premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../providers/sattiklarin_provider.dart';
import '../theme/sandik.dart';
import '../utils/money_format.dart';
import '../utils/tr_format.dart';
import 'kapanis_ozeti_sheet.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// Portföy listesinin sonundaki "Sattıkların (n)" satırı (Premium,
/// 2026-11-12).
///
/// ## Neden
/// Kapanış özeti "Tümünü sat"ın ardından bir kez açılıyordu; kapatılan
/// pozisyonun kârına sonradan bakmanın yolu yoktu (satır listeden düşüyor,
/// cevap ancak yıl sonu raporunda). Bu satır o özete geri dönüş yolu.
///
/// ## Görünürlük (başa baş satırı deseni, `basa_bas_satiri.dart`)
/// - Premium özellikleri görünmüyorsa (paywall kapalı ve admin değil)
///   satır yok: canlı kullanıcı paywall kapalıyken bugünkü listeyi birebir
///   görür.
/// - Kapanmış pozisyon yoksa satır yok: boş bir listeye çağırmayız.
/// - `premiumKilitliProvider` → [KilitSatiri] (kaynak `sattiklarin` →
///   paywall rapor kartı: gerçekleşen kâr yıllık raporun sorusu).
/// - Açıksa satır listeyi alt sayfada açar ([showSattiklarin]).
class SattiklarinSatiri extends ConsumerWidget {
  const SattiklarinSatiri({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final liste = ref.watch(sattiklarinProvider);
    if (liste.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final c = context.c;
    final Widget satir = ref.watch(premiumKilitliProvider)
        ? KilitSatiri(
            metin: l.sattiklarinKilitli,
            kaynak: 'sattiklarin',
            ozellik: 'sattiklarin',
            kilitEtiketi: l.goalDateLockedLabel,
          )
        : SandikTappable(
            key: const ValueKey('sattiklarin_satiri'),
            onTap: () => showSattiklarin(context, ref),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: SandikTouch.min),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.sattiklarinSatir(liste.length),
                      style: context.t.bodyMedium?.copyWith(
                        color: c.text90,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: SandikSpace.lgs,
                    color: c.text58,
                  ),
                ],
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.sm),
      child: satir,
    );
  }
}

/// Liste sayfasını açar; satıra dokunulursa sayfa KAPANDIKTAN sonra o
/// pozisyonun kapanış özeti açılır (iki katman modal olmasın,
/// `showKapanisOzeti` ile aynı gerekçe). Paylaş kuralı özette aynen: yalnız
/// kazançta, yalnız yüzde. Değerlendirme istemi sorulmaz (eski kapanış
/// "mutlu an" değil).
Future<void> showSattiklarin(BuildContext context, WidgetRef ref) =>
    showSattiklarinListesi(
      context,
      tutarGizli: () => ref.read(balanceHiddenProvider),
    );

/// [showSattiklarin]'in `WidgetRef` istemeyen hâli. Satın alma sonrası
/// sayfa listeyi paywall kapandıktan SONRA açar; o an paywall'ın `ref`'i
/// ölmüştür, gizli tutar tercihi kapsayıcıdan okunur.
Future<void> showSattiklarinListesi(
  BuildContext context, {
  required bool Function() tutarGizli,
}) async {
  final l = context.l10n;
  final secim = await showSandikSheet<KapanmisPozisyon>(
    context: context,
    baslik: l.sattiklarinBaslik,
    altMetin: l.sattiklarinAltMetin,
    builder: (_) => const SattiklarinSayfasi(),
  );
  if (secim == null || !context.mounted) return;
  await showKapanisOzeti(
    context,
    secim.ozet,
    tutarGizli: tutarGizli(),
    degerlendirme: false,
  );
}

/// Kapanmış pozisyonların listesi: başta tek özet satırı (gerçekleşen
/// toplam), altında ad, tutma süresi, gerçekleşen kâr/zarar.
class SattiklarinSayfasi extends ConsumerWidget {
  const SattiklarinSayfasi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(sattiklarinProvider);
    final toplam = ref.watch(sattiklarinToplamiProvider);
    final gizli = ref.watch(balanceHiddenProvider);
    final h = SandikSpace.screenH(context);
    return SafeArea(
      top: false,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.lg),
        itemCount: liste.length + 1,
        itemBuilder: (context, i) => i == 0
            ? _SattiklarinOzetSatiri(toplam: toplam, tutarGizli: gizli)
            : _SattiginSatir(
                kapanmis: liste[i - 1],
                tutarGizli: gizli,
                onTap: () => Navigator.pop(context, liste[i - 1]),
              ),
      ),
    );
  }
}

/// Toplam tutar metni: "+₺1.200"; bakiye gizliyken satırlarla aynı maske.
/// Hiçbir pozisyonun maliyeti bilinmiyorsa `null` (toplam yazılmaz).
String? sattiklarinToplamTutari(
  SattiklarinToplami t, {
  required bool tutarGizli,
}) {
  final kar = t.karTry;
  if (kar == null) return null;
  if (tutarGizli) return const BazPara.lira().gizliTutar;
  return '${kar > 0 ? '+' : ''}${fmtTRY(kar)}';
}

/// "Gerçekleşen toplam +₺X · 7 pozisyon" ve gerekirse dipnot.
///
/// ## Kararlar (2026-11-13)
/// - Sayı toplama GİREN pozisyonlardır (maliyeti bilinen): "7 pozisyon"
///   tutarın kaçının toplamı olduğunu söyler; girmeyenler dipnotta ayrıca
///   sayılır, iki sayı birbirini yalanlamaz.
/// - Dipnot varken satırlardaki tek tek "Maliyet bilinmiyor" yazısı
///   görünmez (aynı bilgi bir kez); satır listede kalır, sonucu boş.
///   Ekran okuyucu satır cümlesinde yine söyler: dipnotu satırla
///   eşleştiremez.
/// - Hepsi bilinmiyorsa toplam satırı yok, yalnız dipnot (₺0 "başa baş"
///   demek olurdu).
/// - Renk yön için ek ipucu; anlam işarette (+/−) ve cümlede.
/// - Bakiye gizliyken ekran okuyucu maskeyi değil "gizli" cümlesini okur.
class _SattiklarinOzetSatiri extends StatelessWidget {
  const _SattiklarinOzetSatiri({
    required this.toplam,
    required this.tutarGizli,
  });

  final SattiklarinToplami toplam;
  final bool tutarGizli;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final tutar = sattiklarinToplamTutari(toplam, tutarGizli: tutarGizli);
    final kar = toplam.karTry ?? 0;
    final renk =
        tutarGizli || kar == 0 ? c.text90 : (kar > 0 ? c.gain : c.loss);
    return Padding(
      padding: const EdgeInsets.only(bottom: SandikSpace.sm),
      child: Column(
        key: const ValueKey('sattiklarin_ozet'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tutar != null)
            Semantics(
              label: tutarGizli
                  ? l.sattiklarinToplamGizliA11y(toplam.bilinen)
                  : l.sattiklarinToplamA11y(tutar, toplam.bilinen),
              container: true,
              excludeSemantics: true,
              child: Text(
                l.sattiklarinToplam(tutar, toplam.bilinen),
                style: context.t.bodyMedium?.copyWith(
                  color: renk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (toplam.bilinmeyen > 0) ...[
            if (tutar != null) const SizedBox(height: SandikSpace.xxs),
            Text(
              l.sattiklarinDipnot(toplam.bilinmeyen),
              key: const ValueKey('sattiklarin_dipnot'),
              style: context.t.bodySmall?.copyWith(color: c.text58),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sonuç metni: "+₺1.200 · +%12,0"; bakiye gizliyken tutar maskeli, yüzde
/// görünür (yüzde tutar sızdırmaz; kapanış özetiyle aynı kural). Maliyet
/// bilinmiyorsa `null`.
String? sattiginSonucu(KapanisOzeti o, {required bool tutarGizli}) {
  final kar = o.karTry;
  final pct = o.karPct;
  if (kar == null || pct == null) return null;
  final tutar = tutarGizli
      ? const BazPara.lira().gizliTutar
      : '${kar > 0 ? '+' : ''}${fmtTRY(kar)}';
  return '$tutar · ${fmtPctIsaretli(pct, digits: 1)}';
}

class _SattiginSatir extends StatelessWidget {
  const _SattiginSatir({
    required this.kapanmis,
    required this.tutarGizli,
    required this.onTap,
  });

  final KapanmisPozisyon kapanmis;
  final bool tutarGizli;
  final VoidCallback onTap;

  /// Bu ölçeğin üstünde sonuç adın altına iner (Portföy liste başlığıyla
  /// aynı eşik): iki sütunda 2× yazıda ad tek harfe sıkışıyordu.
  static const double _ikiSutunMetinOlcegi = 1.3;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final o = kapanmis.ozet;
    final sure = l.sattiklarinTuttun(kapanisSureMetni(l, o));
    final sonuc = sattiginSonucu(o, tutarGizli: tutarGizli);
    final kar = o.karTry ?? 0;
    // Anlam renkte değil yalnız: tutar ve yüzde işaretli (+/−) (HIG renk
    // körlüğü). Maliyet bilinmiyorsa sonuç boş: sayfanın başındaki dipnot
    // bunu bir kez söyler (2026-11-13); ekran okuyucu cümlesi aşağıda.
    final Widget sonucMetni = sonuc == null
        ? const SizedBox.shrink()
        : Text(
            sonuc,
            style: context.t.numSmall.copyWith(
              color: kar >= 0 ? c.gain : c.loss,
              fontWeight: FontWeight.w600,
            ),
          );
    final adSure = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          o.ad,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.t.bodyMedium?.copyWith(
            color: c.text90,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SandikSpace.xxs),
        Text(sure, style: context.t.bodySmall?.copyWith(color: c.text58)),
      ],
    );
    final dar =
        MediaQuery.textScalerOf(context).scale(1) > _ikiSutunMetinOlcegi;
    final icerik = dar
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              adSure,
              const SizedBox(height: SandikSpace.xs),
              sonucMetni,
            ],
          )
        : Row(
            children: [
              Expanded(child: adSure),
              const SizedBox(width: SandikSpace.sm),
              sonucMetni,
            ],
          );
    return SandikTappable(
      key: ValueKey('sattigin_${kapanmis.anahtar}'),
      onTap: onTap,
      // Ekran okuyucu tek cümle okur: ad, süre, sonuç (maskeli tutar dahil).
      semanticLabel: [
        o.ad,
        sure,
        if (sonuc != null)
          '${l.yrGerceklesen} $sonuc'
        else
          l.sattiklarinMaliyetYok,
      ].join(', '),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                Expanded(child: icerik),
                const SizedBox(width: SandikSpace.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: SandikSpace.lgs,
                  color: c.text58,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
