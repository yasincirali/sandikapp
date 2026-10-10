import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_xray_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/fon_dagilimi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import '../utils/tr_format.dart';
import 'premium_kilit_karti.dart';

/// "Fonun içinde ne var" — Fon X-Ray kartı (Premium, 2026-10-10).
///
/// Varlık ekranında fon ve BES fonunda, fon karnesinin hemen altında: karne
/// "getirisi kategorisinde nerede", bu kart "parası nerede duruyor" sorusunu
/// yanıtlar. Hesap `fon_dagilimi.dart`'ta (saf), veri `fon_xray_provider`'da;
/// bu dosya yalnız çizer.
///
/// ## Ne zaman ne çizilir
///   · Premium özellikleri görünmüyor (paywall kapalı, admin değil) → HİÇ.
///     Canlıdaki kullanıcı bugün hiçbir şey görmez.
///   · Varlık fon/BES değil ya da fon kodu yok → hiç.
///   · Kilitli (paywall açık, Premium değil) → sayısız kilit kartı; veri
///     okunmaz bile (RLS zaten vermez, istek boşa gitmesin).
///   · Açık + veri yok (TEFAS'ta dağılım yayımlamayan fon) → hiç. Yükleme
///     için iskelet yok: kart ek bilgidir (fon karnesi kararı).
///   · Açık + veri → yığılmış çubuk + kova listesi + "TEFAS · tarih".
///     Bayrak `fon_xray_kalem` açık ve beş kontrolden geçmiş KAP raporu
///     varsa altında ilk 10 kalem ve "KAP · ay sonu".
///
/// ## Uydurma yok
/// Yüzdeler kaynaktan; kova yalnız toplar. Toplam 100'den sapıyorsa kart
/// bunu cümleyle söyler, farkı hiçbir dilime eklemez.
class FonDagilimiKarti extends ConsumerWidget {
  const FonDagilimiKarti({
    super.key,
    required this.tur,
    required this.ticker,
    this.dis = const EdgeInsets.only(bottom: SandikSpace.lg),
  });

  final AssetType tur;
  final String ticker;

  /// Kart çizildiğinde çevresine bırakılan boşluk; çizilmezse boşluk da yok.
  final EdgeInsetsGeometry dis;

  /// Kartta en çok kaç kalem (Katman A).
  static const kalemSayisi = 10;

  /// Bu varlıkta kart (kilitli ya da dolu) çizilecek mi — katmanlı varlık
  /// ekranı analiz satırını buna göre açar. Kartın kendi `build`'iyle AYNI
  /// koşul (bkz. `_analizKatmanlari` notu).
  static bool cizilir(WidgetRef ref, AssetType tur, String ticker) {
    if (!ref.watch(fonXrayGorunurProvider)) return false;
    final kod = fonKoduOf(tur: tur, ticker: ticker);
    if (kod == null) return false;
    if (ref.watch(premiumKilitliProvider)) return true;
    return ref.watch(fonDagilimiProvider(kod)).valueOrNull != null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(fonXrayGorunurProvider)) return const SizedBox.shrink();
    final kod = fonKoduOf(tur: tur, ticker: ticker);
    if (kod == null) return const SizedBox.shrink();
    final l = context.l10n;

    if (ref.watch(premiumKilitliProvider)) {
      return Padding(
        padding: dis,
        child: PremiumKilitKarti(
          ikon: Icons.donut_large_rounded,
          baslik: l.xrKilitBaslik,
          govde: l.xrKilitGovde,
          kilitMetni: l.xrKilitSatir,
          kaynak: 'fon_xray',
        ),
      );
    }

    final dag = ref.watch(fonDagilimiProvider(kod)).valueOrNull;
    if (dag == null) return const SizedBox.shrink();
    final kalemler = ref.watch(fonKalemleriProvider(kod)).valueOrNull;
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final kovalar = dag.kovalar;

    return Padding(
      padding: dis,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SandikSectionHeader(title: l.xrKartBaslikUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                XrayCubugu(
                  paylar: [for (final k in kovalar) (k.kova, k.yuzde)],
                ),
                const SizedBox(height: SandikSpace.smd),
                for (final k in kovalar)
                  XrayKovaSatiri(
                    kova: k.kova,
                    deger: fmtPct(k.yuzde),
                  ),
                if (dag.toplamSapiyor) ...[
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    l.xrToplamSapiyor(fmtPct(dag.toplam)),
                    style: context.t.bodySmall?.copyWith(color: c.text58),
                  ),
                ],
                const SizedBox(height: SandikSpace.sm),
                Text(
                  l.xrKaynakTefas(
                      DateFormat('d MMMM y', dil).format(dag.tarih)),
                  style: context.t.bodySmall?.copyWith(color: c.text36),
                ),
                if (kalemler != null) ...[
                  const SizedBox(height: SandikSpace.smd),
                  Divider(height: 1, thickness: 1, color: c.hairline),
                  const SizedBox(height: SandikSpace.smd),
                  _Kalemler(kalemler: kalemler),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Katman A: fonun ilk [FonDagilimiKarti.kalemSayisi] kalemi.
class _Kalemler extends StatelessWidget {
  const _Kalemler({required this.kalemler});

  final FonKalemleri kalemler;

  Future<void> _ac(BuildContext context, String adres) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(adres),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Tarayıcı yok: aşağıdaki uyarı yeter (KapBaglantisi kararı).
      ok = false;
    }
    if (!ok && context.mounted) {
      sandikSnack(context, context.l10n.kapLinkFailed,
          kind: SandikSnackKind.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final dil = Localizations.localeOf(context).toString();
    final ilk = kalemler.ilk(FonDagilimiKarti.kalemSayisi);
    final adres = kalemler.kaynakUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.xrKalemlerBaslik(ilk.length),
          style: context.t.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, color: c.text90),
        ),
        const SizedBox(height: SandikSpace.sm),
        for (final k in ilk)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    k.etiket == k.ad ? k.ad : '${k.etiket} · ${k.ad}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.bodyMedium?.copyWith(color: c.text90),
                  ),
                ),
                const SizedBox(width: SandikSpace.sm),
                Text(
                  fmtPct(k.agirlik),
                  style: context.t.bodyMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        const SizedBox(height: SandikSpace.sm),
        Text(
          l.xrKaynakKap(DateFormat('MMMM y', dil).format(kalemler.donem)),
          style: context.t.bodySmall?.copyWith(color: c.text36),
        ),
        if (adres != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _ac(context, adres),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(l.xrKapAc),
            ),
          ),
      ],
    );
  }
}

/// Kova adı (çevrilmiş).
String xrayKovaAdi(AppLocalizations l, XrayKova k) => switch (k) {
      XrayKova.bistHisse => l.xrKovaBistHisse,
      XrayKova.yabanciHisse => l.xrKovaYabanciHisse,
      XrayKova.devletBorclanma => l.xrKovaDevlet,
      XrayKova.ozelBorclanma => l.xrKovaOzel,
      XrayKova.dovizBorclanma => l.xrKovaDovizBorc,
      XrayKova.paraPiyasasi => l.xrKovaParaPiyasasi,
      XrayKova.mevduat => l.xrKovaMevduat,
      XrayKova.kiymetliMaden => l.xrKovaMaden,
      XrayKova.fon => l.xrKovaFon,
      XrayKova.gayrimenkulGirisim => l.xrKovaGayrimenkul,
      XrayKova.diger => l.xrKovaDiger,
      XrayKova.etiketsiz => l.xrKovaEtiketsiz,
      XrayKova.doviz => l.xrKovaDoviz,
      XrayKova.kripto => l.xrKovaKripto,
      XrayKova.emtia => l.xrKovaEmtia,
    };

/// Kova rengi. Portföy halkasının tür renkleri (`AssetType.color`) yeniden
/// kullanılır ki "hisse amber, altın altın sarısı, fon mavi" iki yüzeyde
/// aynı okunsun; aynı ailenin alt kovaları alfa ile ayrılır. Etiketsiz
/// sınıf ve X-Ray dışı nötr gri — bilinmeyen renkli görünmesin.
Color xrayKovaRengi(XrayKova k, SandikPalette c) => switch (k) {
      XrayKova.bistHisse => AssetType.hisse.color,
      XrayKova.yabanciHisse => AssetType.hisse.color.withValues(alpha: 0.55),
      XrayKova.devletBorclanma => AssetType.eurobond.color,
      XrayKova.ozelBorclanma =>
        AssetType.eurobond.color.withValues(alpha: 0.65),
      XrayKova.dovizBorclanma =>
        AssetType.eurobond.color.withValues(alpha: 0.4),
      XrayKova.paraPiyasasi => AssetType.fon.color,
      XrayKova.mevduat => AssetType.mevduat.color,
      XrayKova.kiymetliMaden => AssetType.altin.color,
      XrayKova.fon => AssetType.fon.color.withValues(alpha: 0.5),
      XrayKova.gayrimenkulGirisim =>
        AssetType.emtia.color.withValues(alpha: 0.6),
      XrayKova.diger => AssetType.diger.color,
      XrayKova.etiketsiz => c.text20,
      XrayKova.doviz => AssetType.doviz.color,
      XrayKova.kripto => AssetType.kripto.color,
      XrayKova.emtia => AssetType.emtia.color,
    };

/// Yığılmış yatay çubuk. [paylar] (kova, pay) — pay herhangi bir birimde
/// (yüzde ya da TL); genişlik payların toplamına göre. [disi] verilirse
/// sonda nötr bir "X-Ray dışı" dilimi. Negatif pay (borçlanma/repo)
/// çubukta çizilmez, listede yazar.
class XrayCubugu extends StatelessWidget {
  const XrayCubugu({super.key, required this.paylar, this.disi = 0});

  final List<(XrayKova, double)> paylar;
  final double disi;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final dilimler = <(Color, double)>[
      for (final (k, v) in paylar)
        if (v > 0) (xrayKovaRengi(k, c), v),
      if (disi > 0) (c.text20.withValues(alpha: 0.5), disi),
    ];
    final toplam = dilimler.fold(0.0, (t, d) => t + d.$2);
    return Semantics(
      label: [
        for (final (k, v) in paylar)
          if (v > 0) xrayKovaAdi(l, k),
      ].join(', '),
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: SandikRadius.smAll,
          child: SizedBox(
            height: SandikSpace.smd,
            child: toplam <= 0
                ? ColoredBox(color: c.hairline)
                : Row(
                    children: [
                      for (final (renk, v) in dilimler)
                        Expanded(
                          // Binde birlik çözünürlük; çok küçük dilim de
                          // en az bir birim yer tutar (görünür kalsın).
                          flex: (v / toplam * 1000).round().clamp(1, 1000),
                          child: ColoredBox(color: renk),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Lejant satırı: renk noktası, kova adı, değer (yüzde ya da tutar) ve
/// isteğe bağlı ikinci değer.
class XrayKovaSatiri extends StatelessWidget {
  const XrayKovaSatiri({
    super.key,
    required this.kova,
    required this.deger,
    this.ikinci,
    this.ad,
    this.renk,
  });

  final XrayKova? kova;
  final String deger;
  final String? ikinci;

  /// [kova] yoksa (X-Ray dışı) ad ve renk çağırandan.
  final String? ad;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l10n;
    final k = kova;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: SandikSpace.sm,
            height: SandikSpace.sm,
            decoration: BoxDecoration(
              color: renk ?? (k == null ? c.text20 : xrayKovaRengi(k, c)),
              borderRadius: SandikRadius.smAll,
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              ad ?? (k == null ? '' : xrayKovaAdi(l, k)),
              style: context.t.bodyMedium?.copyWith(color: c.text90),
            ),
          ),
          if (ikinci != null) ...[
            Text(ikinci!,
                style: context.t.bodySmall?.copyWith(color: c.text58)),
            const SizedBox(width: SandikSpace.sm),
          ],
          Text(
            deger,
            style: context.t.bodyMedium
                ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
