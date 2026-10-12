import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../providers/fon_xray_provider.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../services/portfoy_xray.dart';
import '../services/fon_dagilimi.dart' show XrayKova;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import '../widgets/fon_dagilimi_karti.dart';
import '../widgets/premium_kilit_karti.dart';
import '../widgets/sandik_app_bar.dart';
import '../widgets/sandik_bos_durum.dart';
import '../widgets/sandik_error_view.dart';
import '../widgets/sandik_skeleton.dart';

/// Portföy X-Ray (Premium, yasin 2026-10-10): bugünkü portföyün, fonların
/// içi açılarak, varlık sınıflarına gerçek dağılımı.
///
/// Performans › Raporlar kapısından açılır (Yıllık rapor ve Temettü tahmini
/// gibi; görünürlük `premiumOzellikleriGorunur`). Kural ve gerekçe saf
/// `portfoy_xray.dart`'ta; ekran yalnız çizer.
///
/// Her sayının yanında kaynak ve tarih: fon dağılımı "TEFAS · tarih", kalem
/// örtüşmesi "KAP · ay sonu", doğrudan varlıklar bugünkü fiyat. Kapsanmayan
/// pay "X-Ray dışı" satırı olarak kalır; diğer dilimlere dağıtılmaz.
///
/// ## Tasarım B: görünen ve gerçek (yasin 2026-10-12, "önerini uygula")
/// X-Ray'in tek değeri "sandığın ile gerçeğin farkı". Üst kart iki çubuğu
/// alt alta koyar: listede gördüğün türler (fon fon olarak) ve fonların içi
/// açılınca çıkan sınıflar. Altında hesaplanmış en çok iki cümle
/// ("Hisse payın %24 görünüyor, fonlarınla birlikte %47,8"). Sınıf
/// satırına dokununca o paranın hangi fondan / pozisyondan geldiği alt
/// sayfada açılır; kaynakların toplamı satırdaki tutardır. Fon yoksa iki
/// görünüm aynı şeydir: karşılaştırma ve cümle çizilmez. Premium ekranı
/// (mağazada kapalı), bu yüzden bayraksız.
class PortfoyXrayScreen extends ConsumerWidget {
  const PortfoyXrayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return Scaffold(
        appBar: SandikAppBar(title: l.xrEkranBaslik),
        body: PremiumKilitGovdesi(
          kart: PremiumKilitKarti(
            ikon: Icons.donut_large_rounded,
            baslik: l.xrEkranBaslik,
            govde: l.xrEkranKilitGovde,
            kilitMetni: l.xrEkranKilitSatir,
            kaynak: 'portfoy_xray',
          ),
        ),
      );
    }
    final xray = ref.watch(portfoyXrayProvider);
    return Scaffold(
      appBar: SandikAppBar(title: l.xrEkranBaslik),
      body: xray.when(
        loading: () => const SandikSkeletonList(rows: 4),
        error: (e, _) => SandikErrorView(
            error: e, onRetry: () => ref.invalidate(xrayFonVerisiProvider)),
        data: (x) => x.bos
            ? SandikBosDurum(metin: l.xrBos, alt: l.xrBosAlt)
            : _Govde(x: x),
      ),
    );
  }
}

class _Govde extends StatelessWidget {
  const _Govde({required this.x});

  final PortfoyXray x;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final h = SandikSpace.screenH(context);
    final dil = Localizations.localeOf(context).toString();
    final kovalar = x.siraliKovalar;
    final gorunen = x.siraliGorunen;
    final icgoruler = x.icgoruler;
    final notStili = context.t.bodySmall?.copyWith(color: c.text58);
    final kaynakStili = context.t.bodySmall?.copyWith(color: c.text36);
    final enBuyuk = kovalar.isEmpty ? 0.0 : kovalar.first.value;
    final cubukEtiketi =
        context.t.bodySmall?.copyWith(color: c.text58);
    final cubukBasligi = context.t.labelLarge
        ?.copyWith(color: c.text90, fontWeight: FontWeight.w600);
    final sinifSayisi = kovalar.length + (x.xrayDisi > 0 ? 1 : 0);

    Widget cubukUstu(String baslik, String sag) => Padding(
          padding: const EdgeInsets.only(bottom: SandikSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(baslik, style: cubukBasligi)),
              Text(sag, style: cubukEtiketi),
            ],
          ),
        );

    return ListView(
      padding: EdgeInsets.fromLTRB(h, SandikSpace.sm, h, SandikSpace.xl),
      children: [
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.xrToplamEtiket,
                  style: context.t.bodyMedium?.copyWith(color: c.text58)),
              const SizedBox(height: SandikSpace.xs),
              Text(fmtTRY(x.toplam),
                  style: context.t.numLarge
                      .copyWith(fontWeight: FontWeight.w800, color: c.text90)),
              const SizedBox(height: SandikSpace.md),
              if (x.fonVar) ...[
                cubukUstu(l.xrTuttuklarin, l.xrTurSayisi(gorunen.length)),
                _TurCubugu(paylar: gorunen),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                  child: Icon(Icons.south_rounded,
                      size: SandikSpace.md, color: c.text36),
                ),
                cubukUstu(l.xrIcAcilinca, l.xrSinifSayisi(sinifSayisi)),
              ],
              XrayCubugu(
                paylar: [for (final e in kovalar) (e.key, e.value)],
                disi: x.xrayDisi,
              ),
            ],
          ),
        ),
        for (final i in icgoruler) ...[
          const SizedBox(height: SandikSpace.sm),
          _IcgoruKarti(i: i),
        ],
        const SizedBox(height: SandikSpace.lg),
        SandikSectionHeader(title: l.xrDagilimUpper),
        const SizedBox(height: SandikSpace.sm),
        SandikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in kovalar)
                _SinifSatiri(
                  x: x,
                  kova: e.key,
                  ad: xrayKovaAdi(l, e.key),
                  renk: xrayKovaRengi(e.key, c),
                  tutar: e.value,
                  oran: enBuyuk > 0 ? e.value / enBuyuk : 0,
                ),
              if (x.xrayDisi > 0) ...[
                Divider(
                    height: SandikSpace.md, thickness: 1, color: c.hairline),
                _SinifSatiri(
                  x: x,
                  kova: null,
                  ad: l.xrDisi,
                  renk: c.text20.withValues(alpha: 0.5),
                  tutar: x.xrayDisi,
                  oran: enBuyuk > 0 ? x.xrayDisi / enBuyuk : 0,
                ),
                const SizedBox(height: SandikSpace.xs),
                Text(l.xrDisiAciklama, style: notStili),
                if (x.xrayDisiFonlar.isNotEmpty) ...[
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    l.xrDisiFonlar(
                        x.xrayDisiFonlar.map((f) => f.kod ?? f.ad).join(', ')),
                    style: notStili,
                  ),
                ],
              ],
            ],
          ),
        ),
        if (x.ortusmeler.isNotEmpty) ...[
          const SizedBox(height: SandikSpace.lg),
          SandikSectionHeader(title: l.xrOrtusmeUpper),
          const SizedBox(height: SandikSpace.sm),
          SandikCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.xrOrtusmeAciklama, style: notStili),
                const SizedBox(height: SandikSpace.sm),
                for (final o in x.ortusmeler) _OrtusmeSatiri(o: o),
                if (x.kalemDonemi != null) ...[
                  const SizedBox(height: SandikSpace.sm),
                  Text(
                    l.xrKaynakKalemler(
                        DateFormat('MMMM y', dil).format(x.kalemDonemi!)),
                    style: kaynakStili,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: SandikSpace.lg),
        if (x.fonTarihleri case (final eski, final yeni)) ...[
          Text(l.xrKaynakFonlar(_aralik(dil, eski, yeni)), style: kaynakStili),
          const SizedBox(height: SandikSpace.xs),
        ],
        Text(l.xrKaynakDogrudan, style: kaynakStili),
      ],
    );
  }

  /// Tek gün ya da "3 Eki - 9 Ekim 2026" (fonlar farklı günlerde
  /// güncellenmiş olabilir; en eskisi de söylenir).
  static String _aralik(String dil, DateTime eski, DateTime yeni) {
    final tam = DateFormat('d MMMM y', dil);
    if (eski == yeni) return tam.format(yeni);
    return '${DateFormat('d MMM', dil).format(eski)} - ${tam.format(yeni)}';
  }
}

/// "Tuttukların" çubuğu: kullanıcının listesinde gördüğü türler, Portföy'deki
/// tür renkleriyle (fon fon olarak). Gerçek dağılım çubuğuyla aynı ölçü.
class _TurCubugu extends StatelessWidget {
  const _TurCubugu({required this.paylar});

  final List<MapEntry<AssetType, double>> paylar;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final toplam = paylar.fold(0.0, (t, e) => t + e.value);
    return Semantics(
      label: [for (final e in paylar) e.key.labelOf(l)].join(', '),
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: SandikRadius.smAll,
          child: SizedBox(
            height: SandikSpace.smd,
            child: Row(
              // Boş ColoredBox en küçük boya iner: dilimler yüksekliği almazsa
              // çubuk görünmez (X-Ray ekranında çizilmiyordu, 2026-10-12).
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in paylar)
                  Expanded(
                    flex: (e.value / toplam * 1000).round().clamp(1, 1000),
                    child: ColoredBox(color: e.key.color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IcgoruKarti extends StatelessWidget {
  const _IcgoruKarti({required this.i});

  final XrayIcgoru i;

  static String _ad(AppLocalizations l, XrayIcgoruTuru t) => switch (t) {
        XrayIcgoruTuru.hisse => l.xrIcgoruHisse,
        XrayIcgoruTuru.altin => l.xrIcgoruAltin,
        XrayIcgoruTuru.doviz => l.xrIcgoruDoviz,
        XrayIcgoruTuru.faiz => l.xrIcgoruFaiz,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    return SandikCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.trending_up_rounded,
                size: SandikSpace.lg, color: c.amberText),
          ),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: Text(
              l.xrIcgoru(_ad(l, i.tur), fmtPct(i.gorunenPay, digits: 1),
                  fmtPct(i.gercekPay, digits: 1)),
              style: context.t.bodyMedium?.copyWith(color: c.text90),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gerçek dağılım satırı: ad, yüzde · tutar, en büyük sınıfa göre çubuk.
/// Dokununca o sınıfın kaynakları alt sayfada (fon, doğrudan pozisyon).
class _SinifSatiri extends StatelessWidget {
  const _SinifSatiri({
    required this.x,
    required this.kova,
    required this.ad,
    required this.renk,
    required this.tutar,
    required this.oran,
  });

  final PortfoyXray x;
  final XrayKova? kova;
  final String ad;
  final Color renk;
  final double tutar;

  /// En büyük sınıfa göre 0–1.
  final double oran;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final pay = fmtPct(x.pay(tutar), digits: 1);
    return SandikTappable(
      semanticLabel: l.xrSinifEtiket(ad, pay, fmtTRY(tutar)),
      onTap: () {
        SandikHaptic.selection.perform();
        showSandikSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _KaynakSayfasi(
              x: x, kova: kova, ad: ad, renk: renk, tutar: tutar),
        );
      },
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(ad,
                          style: context.t.bodyMedium
                              ?.copyWith(color: c.text90)),
                    ),
                    Text('$pay · ${fmtTRY(tutar)}',
                        style: context.t.bodySmall
                            ?.copyWith(color: c.text58)),
                    const SizedBox(width: SandikSpace.xs),
                    Icon(Icons.chevron_right_rounded,
                        size: SandikSpace.lg, color: c.text36),
                  ],
                ),
                const SizedBox(height: SandikSpace.xs),
                _Ray(oran: oran, renk: renk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ray extends StatelessWidget {
  const _Ray({required this.oran, required this.renk});

  final double oran;
  final Color renk;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: SandikRadius.smAll,
        child: SizedBox(
          height: SandikSpace.xs,
          child: ColoredBox(
            color: context.c.hairline,
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: oran.clamp(0.0, 1.0),
              child: ColoredBox(color: renk),
            ),
          ),
        ),
      );
}

/// Bir sınıfın kaynakları: hangi fondan, hangi doğrudan pozisyondan; toplamı
/// satırdaki tutar.
class _KaynakSayfasi extends StatelessWidget {
  const _KaynakSayfasi({
    required this.x,
    required this.kova,
    required this.ad,
    required this.renk,
    required this.tutar,
  });

  final PortfoyXray x;
  final XrayKova? kova;
  final String ad;
  final Color renk;
  final double tutar;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final kaynaklar = x.kaynaklariSirali(kova);
    final enBuyuk = kaynaklar.isEmpty ? 0.0 : kaynaklar.first.value;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.lg, 0, SandikSpace.lg, SandikSpace.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(ad,
                      style: context.t.titleMedium?.copyWith(
                          color: c.text90, fontWeight: FontWeight.w700)),
                ),
                Text(
                    '${fmtPct(x.pay(tutar), digits: 1)} · ${fmtTRY(tutar)}',
                    style: context.t.bodySmall?.copyWith(color: c.text58)),
              ],
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(l.xrKaynakBaslik,
                style: context.t.bodySmall?.copyWith(color: c.text36)),
            const SizedBox(height: SandikSpace.sm),
            for (final e in kaynaklar)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.bodyMedium
                                  ?.copyWith(color: c.text90)),
                        ),
                        const SizedBox(width: SandikSpace.sm),
                        Text(fmtTRY(e.value),
                            style: context.t.bodyMedium?.copyWith(
                                color: c.text90, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: SandikSpace.xs),
                    _Ray(
                        oran: enBuyuk > 0 ? e.value / enBuyuk : 0,
                        renk: renk),
                  ],
                ),
              ),
            const SizedBox(height: SandikSpace.sm),
            Text(l.xrKaynakNot,
                style: context.t.bodySmall?.copyWith(color: c.text36)),
          ],
        ),
      ),
    );
  }
}

class _OrtusmeSatiri extends StatelessWidget {
  const _OrtusmeSatiri({required this.o});

  final Ortusme o;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final kaynaklar = [...o.fonlar, if (o.dogrudan) l.xrDogrudan].join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SandikSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.kod == o.ad ? o.kod : '${o.kod} · ${o.ad}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium
                      ?.copyWith(color: c.text90, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: SandikSpace.xxs),
                Text(
                  '${l.xrOrtusmeKaynak(o.kaynakSayisi)}: $kaynaklar',
                  style: context.t.bodySmall?.copyWith(color: c.text58),
                ),
              ],
            ),
          ),
          const SizedBox(width: SandikSpace.sm),
          Text(fmtTRY(o.tutar),
              style: context.t.bodyMedium
                  ?.copyWith(color: c.text90, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
