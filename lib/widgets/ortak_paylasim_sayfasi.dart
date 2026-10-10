import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/ortak_paylasimi.dart';
import '../models/portfoy.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../providers/ortak_paylasimi_provider.dart';
import '../providers/portfoy_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'gorunum_cipi.dart';
import 'sandik_async_button.dart';

/// "Ortağın neyi görsün?" — sahibin bir ortağa hangi portföylerini
/// gösterdiğini seçtiği alt sayfa (0135).
///
/// ## Neden yalnız anahtar listesi (segment yok)
/// İlk sürümde üstte "Hepsi / Seçtiklerim" segmenti vardı; anahtarlar
/// "Hepsi"de sönük ve dokunulmazdı. yasin 2026-10-10: "tab tasarımı yerine
/// direkt bir switch" — kullanıcı önce sekme değiştirmek zorunda kalmadan
/// portföyü doğrudan açıp kapatır. Sunucu sözleşmesi (0135) aynı kalır:
/// HEPSİ açıksa `tumu = true` yazılır (yarın açılacak portföy de görünür,
/// eski "Hepsi"); biri kapalıysa `tumu = false` (yeni portföy gizli başlar,
/// eski "Seçtiklerim"). Bu ikinci kural altta tek cümleyle söylenir ki
/// kullanıcı yeni "Kendi birikimim" portföyünü istemeden açmasın.
/// Anahtarlar `Switch.adaptive` (tasarım dili: açma/kapama).
///
/// Kayıt düğmeyle tek istek (`SandikAsyncButton`); her anahtar ayrı istek
/// atsaydı yarım seçim bir an ortağa gidebilirdi.
Future<void> showOrtakPaylasimSayfasi(
  BuildContext context, {
  required AppUser ortak,
}) {
  return showSandikSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
    ),
    builder: (_) => OrtakPaylasimIcerik(ortak: ortak),
  );
}

/// Sayfanın gövdesi — açık sınıf: görsel önizleme testi sayfasız çizer.
class OrtakPaylasimIcerik extends ConsumerStatefulWidget {
  const OrtakPaylasimIcerik({super.key, required this.ortak});

  final AppUser ortak;

  @override
  ConsumerState<OrtakPaylasimIcerik> createState() =>
      _OrtakPaylasimIcerikState();
}

class _OrtakPaylasimIcerikState extends ConsumerState<OrtakPaylasimIcerik> {
  late OrtakPaylasimi _secim;

  @override
  void initState() {
    super.initState();
    final mevcut = ref.read(benimPaylasimimProvider(widget.ortak.id));
    _secim =
        mevcut ?? OrtakPaylasimi.hepsi(sahipId: '', ortakId: widget.ortak.id);
    // "Hepsi"den "Seçtiklerim"e geçen kullanıcı boş bir listeyle
    // başlamasın: bugün gördüğü her şey açık gelir, kapatacağını kapatır.
    if (_secim.tumu) {
      final liste = ref.read(portfoylerProvider).valueOrNull ?? const [];
      _secim =
          _secim.kopya(ana: true, portfoyIdler: {for (final p in liste) p.id});
    }
  }

  /// Anahtar her zaman açık seçim kümesini düzenler; `tumu` kayıtta
  /// kümeden türetilir ([_hepsiAcik]).
  void _anahtar(String? portfoyId, bool acik) {
    setState(() {
      if (portfoyId == null) {
        _secim = _secim.kopya(tumu: false, ana: acik);
      } else {
        final s = {..._secim.portfoyIdler};
        acik ? s.add(portfoyId) : s.remove(portfoyId);
        _secim = _secim.kopya(tumu: false, portfoyIdler: s);
      }
    });
  }

  /// Bütün portföyler (Ana dahil) açık mı — öyleyse kayıt "Hepsi"dir.
  static bool _hepsiAcik(OrtakPaylasimi s, List<Portfoy> liste) =>
      s.tumu || (s.ana && liste.every((p) => s.portfoyIdler.contains(p.id)));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ad = GorunumCipi.ilkAd(widget.ortak.displayName);
    final liste =
        ref.watch(portfoylerProvider).valueOrNull ?? const <Portfoy>[];
    final ozet = ref.watch(portfoyOzetleriProvider);
    final baz = ref.watch(gosterimBazParaProvider);
    final hp = SandikSpace.screenH(context);
    final kimlikler = <String?>[null, for (final p in liste) p.id];
    final hepsi = _hepsiAcik(_secim, liste);
    final hicbiri = !_secim.tumu &&
        _secim.gorunenSayisi([for (final p in liste) p.id]) == 0;
    double deger(String? id) => ozet[id]?.deger ?? 0;
    final gorunen = [
      for (final id in kimlikler)
        if (_secim.gorur(id)) id,
    ];

    Widget satir(String? id, String baslik) => _PortfoySatiri(
          key: ValueKey('ortak-paylasim-${id ?? 'ana'}'),
          ad: baslik,
          ana: id == null,
          deger: baz.fmt(deger(id)),
          acik: _secim.gorur(id),
          onChanged: (v) => _anahtar(id, v),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Row(
              children: [
                GorunumCipi.avatar(context, widget.ortak, boy: 40),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Text(
                    l.ortakGorurBaslik(ad),
                    style: context.t.titleLarge?.copyWith(
                        color: context.c.text90, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SandikSpace.sm),
            Text(
              l.ortakGorurAciklama(ad),
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            _Onizleme(
              baslik: l.ortakGorurOnizleme(ad),
              toplam: gorunen.fold(0.0, (t, id) => t + deger(id)),
              bicim: baz.fmt,
              sayi: hicbiri
                  ? l.ortakGorurHicbiriKisa
                  : hepsi
                      ? l.ortakGorurHepsi
                      : l.ortakGorurSayi(gorunen.length, kimlikler.length),
              dilimler: [
                for (final id in kimlikler)
                  (pay: deger(id), acik: _secim.gorur(id)),
              ],
            ),
            const SizedBox(height: SandikSpace.md),
            SandikCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: SandikSpace.md, vertical: SandikSpace.xs),
              child: Column(
                children: [
                  for (final (i, id) in kimlikler.indexed) ...[
                    if (i > 0) Divider(height: 1, color: context.c.hairline),
                    satir(
                        id,
                        id == null
                            ? (ref.watch(anaPortfoyAdiProvider) ??
                                l.portfoyAnaUzun)
                            : _ad(liste, id)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              l.ortakGorurYeniAciklama,
              style: context.t.bodySmall?.copyWith(color: context.c.text58),
            ),
            if (hicbiri) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(
                l.ortakGorurHicbiri(ad),
                style:
                    context.t.bodySmall?.copyWith(color: context.c.amberText),
              ),
            ],
            const SizedBox(height: SandikSpace.lg),
            SandikAsyncButton(
              key: const ValueKey('ortak-paylasim-kaydet'),
              onPressed: () async {
                try {
                  final uid = ref.read(authProvider).valueOrNull?.id;
                  if (uid == null) return;
                  await ref.read(ortakPaylasimlariProvider.notifier).kaydet(
                        OrtakPaylasimi(
                          sahipId: uid,
                          ortakId: widget.ortak.id,
                          tumu: hepsi,
                          ana: _secim.ana,
                          portfoyIdler: _secim.portfoyIdler,
                        ),
                      );
                } catch (e, st) {
                  CrashReporter.report(e, st, reason: 'ortakPaylasim.kaydet');
                  if (context.mounted) {
                    sandikSnackError(context, e,
                        prefix: l.ortakGorurKaydedilemedi);
                  }
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }

  static String _ad(List<Portfoy> liste, String id) {
    for (final p in liste) {
      if (p.id == id) return p.ad;
    }
    return id;
  }
}

/// "Ayşe görecek" önizlemesi: seçimin SONUCU, kaydetmeden önce. Toplam
/// akarak değişir; çubuk her portföyün payını gösterir, gizlenen dilim
/// söner. Kullanıcı anahtarı çevirdiğinde "ne değişti"yi okumadan görür.
class _Onizleme extends StatelessWidget {
  const _Onizleme({
    required this.baslik,
    required this.toplam,
    required this.bicim,
    required this.sayi,
    required this.dilimler,
  });

  final String baslik;
  final double toplam;
  final String Function(double) bicim;
  final String sayi;
  final List<({double pay, bool acik})> dilimler;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hepsi = dilimler.fold(0.0, (t, d) => t + d.pay);
    return SandikCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(baslik,
                    style: context.t.labelMedium?.copyWith(
                        color: c.text58, fontWeight: FontWeight.w600)),
              ),
              Text(sayi,
                  style: context.t.labelMedium?.copyWith(
                      color: c.amberText, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: SandikSpace.xs),
          TweenAnimationBuilder<double>(
            tween: Tween(end: toplam),
            duration: SandikMotion.flowOf(context),
            curve: SandikMotion.glide,
            builder: (context, v, _) => Text(
              bicim(v),
              style: context.t.headlineSmall
                  ?.copyWith(color: c.text90, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: SandikSpace.smd),
          ClipRRect(
            borderRadius: BorderRadius.circular(SandikRadius.sm),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final (i, d) in dilimler.indexed)
                    if (hepsi <= 0 || d.pay > 0)
                      Expanded(
                        flex: hepsi <= 0
                            ? 1
                            : (d.pay / hepsi * 1000).round().clamp(1, 1000),
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: i == 0 ? 0 : SandikSpace.xxs),
                          child: AnimatedContainer(
                            duration: SandikMotion.stateOf(context),
                            curve: SandikMotion.enter,
                            color: d.acik ? c.amberFill : c.text20,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfoySatiri extends StatelessWidget {
  const _PortfoySatiri({
    super.key,
    required this.ad,
    required this.ana,
    required this.deger,
    required this.acik,
    required this.onChanged,
  });

  final String ad;
  final bool ana;
  final String deger;
  final bool acik;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Bütün satır anahtarı çevirir: iOS anahtarı 31 pt yüksekliğinde,
    // satır ≥44 pt dokunma alanı verir (HIG). Ekran okuyucu satırı tek
    // anahtar olarak duyar (MergeSemantics: ad + açık/kapalı).
    return MergeSemantics(
      child: SandikTappable(
        onTap: () => onChanged(!acik),
        scale: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SandikSpace.sm),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.enter,
                  width: 36,
                  height: 36,
                  decoration:
                      context.chip(selected: acik, radius: SandikRadius.sm),
                  child: Icon(
                    ana ? Icons.home_outlined : Icons.folder_outlined,
                    size: 20,
                    color: acik ? c.amberText : c.text36,
                  ),
                ),
                const SizedBox(width: SandikSpace.smd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ad,
                          style: context.t.titleSmall?.copyWith(
                              color: c.text90, fontWeight: FontWeight.w600)),
                      Text(deger,
                          style:
                              context.t.bodySmall?.copyWith(color: c.text58)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: acik,
                  activeTrackColor: c.amberText,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ortak kartındaki "Görebildiği portföyler · Hepsi ›" satırı. Seçim
/// sunulmuyorsa (bayrak, portföy ya da ortak yok) hiç yer kaplamaz.
class OrtakPaylasimSatiri extends ConsumerWidget {
  const OrtakPaylasimSatiri(
      {super.key, required this.ortak, this.ustBosluk = true});

  final AppUser ortak;

  /// Profil kartında satır kartın altına eklenir (üst boşluk); Portföyler
  /// ekranında kendi kartının içinde, ad satırının hemen altında.
  final bool ustBosluk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ortakPaylasimSecimiVarProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final paylasim = ref.watch(benimPaylasimimProvider(ortak.id));
    final kilitli = ref.watch(portfoyPremiumKilitliProvider);
    final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
    final deger = paylasim == null
        ? ''
        : paylasim.tumu
            ? l.ortakGorurHepsi
            : l.ortakGorurSayi(
                paylasim.gorunenSayisi([for (final p in liste) p.id]),
                liste.length + 1);
    return Padding(
        padding: EdgeInsets.only(top: ustBosluk ? SandikSpace.sm : 0),
        child: SandikTappable(
          key: ValueKey('ortak-paylasim-satiri-${ortak.id}'),
          // Değiştirmek Premium (paywall açıkken); görmek serbest — mevcut
          // seçim kilitliyken de sunucuda geçerli.
          onTap: () => kilitli
              ? PaywallScreen.show(context, source: 'ortak_paylasim')
              : showOrtakPaylasimSayfasi(context, ortak: ortak),
          semanticLabel: '${l.ortakGorurSatir}: $deger',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SandikTouch.min),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined,
                    size: 18, color: context.c.text58),
                const SizedBox(width: SandikSpace.sm),
                Expanded(
                  child: Text(l.ortakGorurSatir,
                      style: context.t.bodyMedium
                          ?.copyWith(color: context.c.text58)),
                ),
                Text(deger,
                    style: context.t.bodyMedium?.copyWith(
                        color: paylasim?.kisitli == true
                            ? context.c.amberText
                            : context.c.text90,
                        fontWeight: FontWeight.w600)),
                Icon(
                    kilitli
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right_rounded,
                    color: context.c.text36),
              ],
            ),
          ),
        ));
  }
}
