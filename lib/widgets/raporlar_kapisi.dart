import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../demo/demo_modu.dart';
import '../l10n/l10n.dart';
import '../providers/fon_akisi_provider.dart' show balinaRadariAcikProvider;
import '../providers/raporlar_provider.dart';
import '../screens/aylik_rapor_screen.dart';
import '../screens/hafta_ozeti_screen.dart';
import '../screens/recap_screen.dart';
import '../screens/siralama_screen.dart' show yarisGirisEkrani;
import '../services/recap_service.dart';
import '../theme/sandik.dart';

/// Performans başlığındaki "Raporlar" kapısı (bayrak `raporlar_kapisi`,
/// sadeleştirme 2 S6).
///
/// ## Neden (S6)
/// Uygulamanın dört "geriye bak" yüzeyi dört ayrı yerden açılıyordu:
/// Haftanın özeti ana ekran şeridinden / fon kartından / bildirimden,
/// Aylık rapor yalnızca Haftanın özeti ekranının İÇİNDEN, Yıl özeti
/// yalnızca Profil afişinden ve yılda 16 gün, Sıralama ise Performans
/// başlığındaki kupadan. Kullanıcı "raporum nerede" diye aradığında tek
/// cevap yoktu. Kapı kupanın yerine geçer (aynı 44pt kabuk, aynı yer) ve
/// dördünü tek listede toplar. Eski girişler kalkmaz — kapı ek bir yol.
///
/// ## Satır kuralı
/// Bir satır yalnızca o rapor BUGÜN başka bir yerden açılabiliyorsa görünür
/// (koşullar `raporlar_provider.dart` ve [yilOzetiProvider] notlarında);
/// kapı yeni bir erişim icat etmez. Hiç satır yoksa düğme de yok. Demoda
/// düğme hiç çizilmez: kupa da demoda yoktu (yarış sunucu havuzudur) ve
/// öteki üç rapor da sunucu notlarından/anlık görüntülerden okunur.
class RaporlarDugmesi extends ConsumerWidget {
  const RaporlarDugmesi({super.key, required this.siralamaAcik});

  /// Sıralama satırı — kupanın bugünkü koşuluyla AYNI (çağıran hesaplar:
  /// küresel yarış açık ya da opt-in + aktif ortak).
  final bool siralamaAcik;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DemoModu.aktif) return const SizedBox.shrink();
    final hafta = ref.watch(balinaRadariAcikProvider);
    final yil = ref.watch(yilOzetiProvider).valueOrNull;
    // Aylık rapor haftanın özetinin alt kümesi (aynı bayrak): ayrıca
    // sorulmaz, düğmenin görünürlüğünü değiştirmez.
    if (!siralamaAcik && !hafta && yil == null) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return Semantics(
      button: true,
      label: l.s6Raporlar,
      child: ExcludeSemantics(
        child: CupertinoButton(
          minimumSize: SandikTouch.minSize,
          padding: EdgeInsets.zero,
          onPressed: () =>
              raporlarSayfasiniAc(context, siralamaAcik: siralamaAcik),
          // Kupayla aynı kabuk (44pt kutu, `chip` dekoru) — üst çubuk
          // düğmeleri her ekranda aynı (kullanıcı bildirimi 2026-09-28).
          child: Container(
            width: SandikTouch.min,
            height: SandikTouch.min,
            decoration: context.chip(selected: false),
            child: Center(
              child: Icon(Icons.assessment_rounded,
                  size: 20, color: context.c.amberText),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raporlar listesini alt sayfada açar. Satıra dokununca sayfa kapanır ve
/// rapor [context] (çağıranın ekranı) üstüne itilir — sayfanın kendi
/// bağlamı kapanınca geçersizdir.
Future<void> raporlarSayfasiniAc(BuildContext context,
    {required bool siralamaAcik}) {
  return showSandikSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.surface1,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (sayfaCtx) => _RaporlarSayfasi(
      siralamaAcik: siralamaAcik,
      ac: (rota) {
        Navigator.of(sayfaCtx).pop();
        rota(context);
      },
    ),
  );
}

class _RaporlarSayfasi extends ConsumerWidget {
  const _RaporlarSayfasi({required this.siralamaAcik, required this.ac});

  final bool siralamaAcik;
  final void Function(void Function(BuildContext ekran) rota) ac;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.c;
    final hafta = ref.watch(balinaRadariAcikProvider);
    final aylik = ref.watch(aylikRaporDonemiProvider);
    final yil = ref.watch(yilOzetiProvider).valueOrNull;
    final dil = Localizations.localeOf(context).toString();

    final satirlar = <Widget>[
      if (hafta)
        _RaporSatiri(
          ikon: Icons.radar_rounded,
          baslik: l.weekTitle,
          alt: l.s6HaftaOzetiAlt,
          onTap: () => ac((ekran) => pushGuarded(ekran,
              adaptiveRoute<void>(builder: (_) => const HaftaOzetiScreen()))),
        ),
      if (aylik != null)
        _RaporSatiri(
          ikon: Icons.summarize_rounded,
          baslik: l.s6AylikRapor,
          alt: l.anzAylikBaslik(DateFormat('MMMM y', dil).format(aylik)),
          onTap: () => ac((ekran) => pushGuarded(ekran,
              adaptiveRoute<void>(
                  builder: (_) => AylikRaporScreen(donem: aylik)))),
        ),
      if (yil != null)
        _RaporSatiri(
          ikon: Icons.auto_stories_rounded,
          baslik: l.s6YilOzeti,
          alt: l.recapReady(RecapService.yearFor(DateTime.now())),
          // `RecapScreen.show` afişle aynı yol: analitik + değerlendirme
          // istemi orada.
          onTap: () => ac((ekran) => RecapScreen.show(
              ekran, yil, RecapService.yearFor(DateTime.now()))),
        ),
      if (siralamaAcik)
        _RaporSatiri(
          ikon: Icons.emoji_events_rounded,
          baslik: l.s6Siralama,
          alt: l.s6SiralamaAlt,
          // Kupayla aynı hedef: Sıralama › Ortaklarım.
          onTap: () => ac((ekran) => pushGuarded(ekran,
              adaptiveRoute<void>(builder: (_) => yarisGirisEkrani()))),
        ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.sm, SandikSpace.screenH(context), SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(
              l.s6Raporlar,
              style: context.t.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, color: c.text90),
            ),
            const SizedBox(height: SandikSpace.sm),
            for (var i = 0; i < satirlar.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
              satirlar[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _RaporSatiri extends StatelessWidget {
  const _RaporSatiri({
    required this.ikon,
    required this.baslik,
    required this.alt,
    required this.onTap,
  });

  final IconData ikon;
  final String baslik;
  final String alt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SandikTappable(
      onTap: onTap,
      semanticLabel: baslik,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SandikSpace.smd),
          child: Row(
            children: [
              Icon(ikon, color: c.amberText, size: SandikSpace.lgs),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      baslik,
                      style: context.t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: c.text90),
                    ),
                    const SizedBox(height: SandikSpace.xxs),
                    Text(
                      alt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall?.copyWith(color: c.text58),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.text36),
            ],
          ),
        ),
      ),
    );
  }
}
