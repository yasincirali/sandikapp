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
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'gorunum_cipi.dart';
import 'sandik_async_button.dart';
import 'sandik_segment.dart';

/// "Ortağın neyi görsün?" — sahibin bir ortağa hangi portföylerini
/// gösterdiğini seçtiği alt sayfa (0135).
///
/// ## Neden Hepsi / Seçtiklerim + anahtar listesi
/// İki ayrı karar var ve ikisi de görünür olmalı: (1) bugünkü portföyler
/// arasından hangileri, (2) YARIN açılacak portföy ne olsun. "Hepsi" ikinci
/// soruya "görünsün" der (bugünkü davranış, satır yazılmazsa da bu);
/// "Seçtiklerim" "gizli başlasın" der. Tek bir anahtar listesi (2) yi
/// söylemezdi ve kullanıcı yeni "Kendi birikimim" portföyünü ortağına
/// istemeden açabilirdi. Segment 2 seçenek (`SandikSegment`), portföyler
/// `Switch.adaptive` (tasarım dili: açma/kapama).
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

  void _anahtar(String? portfoyId, bool acik) {
    setState(() {
      if (portfoyId == null) {
        _secim = _secim.kopya(ana: acik);
      } else {
        final s = {..._secim.portfoyIdler};
        acik ? s.add(portfoyId) : s.remove(portfoyId);
        _secim = _secim.kopya(portfoyIdler: s);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ad = GorunumCipi.ilkAd(widget.ortak.displayName);
    final liste =
        ref.watch(portfoylerProvider).valueOrNull ?? const <Portfoy>[];
    final ozet = ref.watch(portfoyOzetleriProvider);
    final baz = ref.watch(gosterimBazParaProvider);
    final hp = SandikSpace.screenH(context);
    final hicbiri = !_secim.tumu &&
        _secim.gorunenSayisi([for (final p in liste) p.id]) == 0;

    Widget satir(String? id, String baslik) => _PortfoySatiri(
          key: ValueKey('ortak-paylasim-${id ?? 'ana'}'),
          ad: baslik,
          deger: baz.fmt(ozet[id]?.deger ?? 0),
          acik: _secim.gorur(id),
          etkin: !_secim.tumu,
          onChanged: (v) => _anahtar(id, v),
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, SandikSpace.md, hp, SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(
              l.ortakGorurBaslik(ad),
              style: context.t.titleLarge?.copyWith(
                  color: context.c.text90, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              l.ortakGorurAciklama(ad),
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            const SizedBox(height: SandikSpace.md),
            SandikSegment(
              adet: 2,
              secili: _secim.tumu ? 0 : 1,
              onSec: (i) => setState(() => _secim = _secim.kopya(tumu: i == 0)),
              oge: (_, i, __) =>
                  Text(i == 0 ? l.ortakGorurHepsi : l.ortakGorurSecilenler),
            ),
            const SizedBox(height: SandikSpace.xs),
            Text(
              _secim.tumu
                  ? l.ortakGorurHepsiAciklama
                  : l.ortakGorurSeciliAciklama,
              style: context.t.bodySmall?.copyWith(color: context.c.text36),
            ),
            const SizedBox(height: SandikSpace.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    satir(null, l.portfoyAnaUzun),
                    for (final p in liste) satir(p.id, p.ad),
                  ],
                ),
              ),
            ),
            if (hicbiri) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(
                l.ortakGorurHicbiri(ad),
                style:
                    context.t.bodySmall?.copyWith(color: context.c.amberText),
              ),
            ],
            const SizedBox(height: SandikSpace.md),
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
                          tumu: _secim.tumu,
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
}

class _PortfoySatiri extends StatelessWidget {
  const _PortfoySatiri({
    super.key,
    required this.ad,
    required this.deger,
    required this.acik,
    required this.etkin,
    required this.onChanged,
  });

  final String ad;
  final String deger;
  final bool acik;

  /// "Hepsi"de anahtarlar bilgi amaçlı (hepsi açık) ve dokunulmaz.
  final bool etkin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: etkin ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SandikSpace.xxs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad,
                      style: context.t.titleSmall?.copyWith(
                          color: context.c.text90,
                          fontWeight: FontWeight.w600)),
                  Text(deger,
                      style: context.t.bodySmall
                          ?.copyWith(color: context.c.text58)),
                ],
              ),
            ),
            Semantics(
              label: ad,
              child: Switch.adaptive(
                value: acik,
                activeTrackColor: context.c.amberText,
                onChanged: etkin ? onChanged : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ortak kartındaki "Görebildiği portföyler · Hepsi ›" satırı. Seçim
/// sunulmuyorsa (bayrak, portföy ya da ortak yok) hiç yer kaplamaz.
class OrtakPaylasimSatiri extends ConsumerWidget {
  const OrtakPaylasimSatiri({super.key, required this.ortak});

  final AppUser ortak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ortakPaylasimSecimiVarProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final paylasim = ref.watch(benimPaylasimimProvider(ortak.id));
    final liste = ref.watch(portfoylerProvider).valueOrNull ?? const [];
    final deger = paylasim == null
        ? ''
        : paylasim.tumu
            ? l.ortakGorurHepsi
            : l.ortakGorurSayi(
                paylasim.gorunenSayisi([for (final p in liste) p.id]),
                liste.length + 1);
    return Padding(
        padding: const EdgeInsets.only(top: SandikSpace.sm),
        child: SandikTappable(
          key: ValueKey('ortak-paylasim-satiri-${ortak.id}'),
          onTap: () => showOrtakPaylasimSayfasi(context, ortak: ortak),
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
                Icon(Icons.chevron_right_rounded, color: context.c.text36),
              ],
            ),
          ),
        ));
  }
}
