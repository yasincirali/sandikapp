import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../services/radar_okuma.dart';
import '../theme/sandik.dart';

/// Radar kartlarının ortak parçaları (Balina F1 tamamlama, 2026-10-05).
///
/// Kullanıcı kararı: açıklama paragrafı yerine deneyim (bkz.
/// `radar_okuma.dart` başı). Dört kart ve üç ayrıntı ekranı aynı parçaları
/// kullanır ki kullanıcı deseni bir kez öğrensin:
///   · [OlcekCubugu] — sakin / hareketli / çok hareketli,
///   · [TerimMetni] — altı noktalı terim, dokununca bir cümlelik tanım,
///   · [radarKocunuGoster] — bir kerelik üç adım,
///   · [RadarKaynakSatiri] — kaynak · tarih · "tavsiye değildir", tek satır.
///
/// Renk yön bildirmez: ölçek nötrdür (hacim yön taşımaz; fon kartında yön
/// zaten sayının renginde).

/// Dokunulabilir terimler. Tanımlar iki .arb'da, tek yerde.
enum RadarTerim {
  netAkis,
  buyukluk,
  ayristirma,
  yatirimci,
  sira,
  buyukHareket,
  olcek,
  hacim,
  kat,
  olagandisi,
  aliciPayi,
  netAlim,
}

extension RadarTerimMetni on RadarTerim {
  (String, String) metin(AppLocalizations l) => switch (this) {
        RadarTerim.netAkis => (l.rdrTerimNetAkis, l.rdrTerimNetAkisTanim),
        RadarTerim.buyukluk => (l.rdrTerimBuyukluk, l.rdrTerimBuyuklukTanim),
        RadarTerim.ayristirma => (
            l.rdrTerimAyristirma,
            l.rdrTerimAyristirmaTanim
          ),
        RadarTerim.yatirimci => (l.rdrTerimYatirimci, l.rdrTerimYatirimciTanim),
        RadarTerim.sira => (l.rdrTerimSira, l.rdrTerimSiraTanim),
        RadarTerim.buyukHareket => (
            l.rdrTerimBuyukHareket,
            l.rdrTerimBuyukHareketTanim
          ),
        RadarTerim.olcek => (l.rdrTerimOlcek, l.rdrTerimOlcekTanim),
        RadarTerim.hacim => (l.rdrTerimHacim, l.rdrTerimHacimTanim),
        RadarTerim.kat => (l.rdrTerimKat, l.rdrTerimKatTanim),
        RadarTerim.olagandisi => (
            l.rdrTerimOlagandisi,
            l.rdrTerimOlagandisiTanim
          ),
        RadarTerim.aliciPayi => (l.rdrTerimAliciPayi, l.rdrTerimAliciPayiTanim),
        RadarTerim.netAlim => (l.rdrTerimNetAlim, l.rdrTerimNetAlimTanim),
      };
}

/// Terimin alt sayfası: başlık, bir paragraf tanım ve (verildiyse) bu
/// varlıktan bir örnek — "TTE'de: +₺412,00M". Örnek, tanımı soyut
/// bırakmamak için: kullanıcı kendi ekranındaki sayıyla bağ kurar.
Future<void> terimSayfasiniAc(BuildContext context, RadarTerim terim,
    {String? ornek}) {
  final l = context.l10n;
  final (baslik, tanim) = terim.metin(l);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(ctx), SandikSpace.md,
            SandikSpace.screenH(ctx), SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(baslik,
                style: ctx.t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: ctx.c.text90)),
            const SizedBox(height: SandikSpace.sm),
            Text(tanim, style: ctx.t.bodyMedium?.copyWith(color: ctx.c.text58)),
            if (ornek != null) ...[
              const SizedBox(height: SandikSpace.smd),
              Container(
                padding: const EdgeInsets.all(SandikSpace.smd),
                decoration: BoxDecoration(
                  color: ctx.c.surface1,
                  borderRadius: SandikRadius.smAll,
                ),
                child: Text(l.rdrTerimOrnek(ornek),
                    style: ctx.t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: ctx.c.text90)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Altı noktalı, dokunulabilir terim. Dokunma alanı metnin kendisinden
/// büyük: `InkWell` en az 44pt yüksekliğinde bir kutuya sarılır.
class TerimMetni extends StatelessWidget {
  const TerimMetni({
    super.key,
    required this.terim,
    required this.metin,
    this.ornek,
    this.stil,
  });

  final RadarTerim terim;
  final String metin;
  final String? ornek;
  final TextStyle? stil;

  @override
  Widget build(BuildContext context) {
    final temel =
        stil ?? context.t.bodySmall?.copyWith(color: context.c.text58);
    return Semantics(
      button: true,
      hint: terim.metin(context.l10n).$1,
      child: InkWell(
        onTap: () => terimSayfasiniAc(context, terim, ornek: ornek),
        borderRadius: SandikRadius.smAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text(
              metin,
              style: temel?.copyWith(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: temel.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Üç kademeli ölçek. Etkin kademe dolu, diğerleri soluk; altında üç etiket.
/// Renk nötr (`text90`/`text20`): ölçek yön değil şiddet söyler.
class OlcekCubugu extends StatelessWidget {
  const OlcekCubugu({super.key, required this.kademe});

  final Kademe kademe;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final etiketler = [l.rdrKademeSakin, l.rdrKademeHareketli, l.rdrKademeCok];
    return Semantics(
      label: l.rdrOlcekSemantics(etiketler[kademe.index]),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: SandikSpace.xs),
                  Expanded(
                    child: Container(
                      height: SandikSpace.xs2,
                      decoration: BoxDecoration(
                        color: i <= kademe.index ? c.text90 : c.text20,
                        borderRadius: BorderRadius.circular(SandikSpace.xs),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: SandikSpace.xs),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Text(
                      etiketler[i],
                      textAlign: i == 0
                          ? TextAlign.start
                          : i == 1
                              ? TextAlign.center
                              : TextAlign.end,
                      style: context.t.labelSmall?.copyWith(
                        color: i == kademe.index ? c.text90 : c.text36,
                        fontWeight: i == kademe.index ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Hareketli hafta" / "Çok hareketli gün".
String kademeEtiketi(AppLocalizations l, Kademe k, {required bool hafta}) =>
    switch ((k, hafta)) {
      (Kademe.sakin, true) => l.rdrHaftaSakin,
      (Kademe.hareketli, true) => l.rdrHaftaHareketli,
      (Kademe.cokHareketli, true) => l.rdrHaftaCok,
      (Kademe.sakin, false) => l.rdrGunSakin,
      (Kademe.hareketli, false) => l.rdrGunHareketli,
      (Kademe.cokHareketli, false) => l.rdrGunCok,
    };

/// Kaynak · tarih · tavsiye değildir — her ekranda bir kez, en altta.
class RadarKaynakSatiri extends StatelessWidget {
  const RadarKaynakSatiri(
      {super.key, required this.kaynak, required this.tarih});

  final String kaynak;
  final String tarih;

  @override
  Widget build(BuildContext context) => Text(
        context.l10n.rdrKaynakSatiri(kaynak, tarih),
        style: context.t.bodySmall?.copyWith(color: context.c.text36),
      );
}

/// Kartın sağ altındaki "Ayrıntı ›".
class AyrintiBaglantisi extends StatelessWidget {
  const AyrintiBaglantisi({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.rdrAyrinti),
            const Icon(Icons.chevron_right_rounded, size: SandikSpace.lgs),
          ],
        ),
      );
}

/// Etiket çipi ("Büyük giriş", "Sakin"). Yön rengi yalnız giriş/çıkışta.
class RozetCipi extends StatelessWidget {
  const RozetCipi({super.key, required this.metin, this.renk});

  final String metin;

  /// `null` = nötr.
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final r = renk ?? context.c.text58;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SandikSpace.sm, vertical: SandikSpace.xxs),
      decoration: BoxDecoration(
        color: r.withValues(alpha: 0.14),
        borderRadius: SandikRadius.smAll,
      ),
      child: Text(metin,
          style: context.t.labelSmall
              ?.copyWith(color: r, fontWeight: FontWeight.w700)),
    );
  }
}

/// "Nasıl okunur" gezintisi. [zorla] değilse yalnız bir kez (kişiye özel);
/// ayrıntı ekranının başlığındaki "?" her zaman yeniden açar.
Future<void> radarKocunuGoster(BuildContext context, WidgetRef ref,
    {bool zorla = false}) async {
  if (!zorla && ref.read(radarKocuGorulduProvider)) return;
  await ref.read(radarKocuGorulduProvider.notifier).set(true);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.c.surface2,
    shape: const RoundedRectangleBorder(borderRadius: SandikRadius.sheetTop),
    builder: (_) => const _Koc(),
  );
}

class _Koc extends StatefulWidget {
  const _Koc();

  @override
  State<_Koc> createState() => _KocState();
}

class _KocState extends State<_Koc> {
  var _adim = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.c;
    final metinler = [l.rdrKoc1, l.rdrKoc2, l.rdrKoc3];
    final son = _adim == metinler.length - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SandikSpace.screenH(context),
            SandikSpace.md, SandikSpace.screenH(context), SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SandikTutamac()),
            const SizedBox(height: SandikSpace.md),
            Text(l.rdrNasilOkunur.toUpperCase(),
                style: context.t.labelLarge?.copyWith(
                    color: c.text58,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: SandikSpace.xs),
            Text(l.rdrKocAdim('${_adim + 1}'),
                style: context.t.bodySmall?.copyWith(color: c.text36)),
            const SizedBox(height: SandikSpace.smd),
            Text(metinler[_adim],
                style: context.t.titleMedium?.copyWith(color: c.text90)),
            const SizedBox(height: SandikSpace.md),
            // Örnek: adımın anlattığı parça, gerçek bileşenle.
            if (_adim == 1) const OlcekCubugu(kademe: Kademe.hareketli),
            if (_adim == 2)
              Text(
                l.rdrTerimNetAkis,
                style: context.t.bodyMedium?.copyWith(
                  color: c.text90,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
              ),
            const SizedBox(height: SandikSpace.lg),
            FilledButton(
              onPressed: () =>
                  son ? Navigator.of(context).pop() : setState(() => _adim++),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(SandikTouch.min)),
              child: Text(son ? l.rdrAnladim : l.rdrIleri),
            ),
          ],
        ),
      ),
    );
  }
}
