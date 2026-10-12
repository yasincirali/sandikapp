import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/portfoy_grubu.dart';
import '../services/tur_filtre_ozeti.dart';
import '../theme/sandik.dart';

/// Performans › Filtre alt sayfasının kategori seçimi (bayrak `goz_alici`).
///
/// ## Karar (kullanıcı, 2026-10-10 — tasarım tuvalinde "D · Sade çipler")
/// Önceki turlar: sayılı/paylı döşemeler, halka, renkli kartlar ve 3×3
/// ikonlu kare ızgara (PR #140). Kullanıcı: "fazla detay ve karmaşıklığı
/// artırdı; filtre mantığının üstüne çıkmamalı ama fonksiyonel ve anlaşılır,
/// net olmalı." Seçilen hâl:
///   · Yalnız ad: sayı, yüzde, tutar, ikon YOK — filtre ne süzdüğünü söyler,
///     portföyü anlatmaz (o iş Portföy sekmesinin halkasında).
///   · Elde OLAN türler en önde (Tümü'den sonra), değeri büyükten küçüğe;
///     kullanıcının seçeceği şey ilk satırda.
///   · Elde OLMAYAN türler listenin SONUNDA, PASİF: soluk, dokunulmaz
///     ("portföyde olmayanlar pasif şekilde çip listenin sonunda yer
///     alsın"). Boş grafiğe giden seçim baştan kapalı.
///   · Seçili çip amber dolgu + onay işareti; renk tek başına bilgi taşımaz.
///
/// İstisna: seçili tür elde değilse (eski seçim, satılmış pozisyon) çip
/// pasif DEĞİL ve seçili görünür — görünmeyen ya da kaldırılamayan bir
/// filtre olmasın.
///
/// Anahtar [PortfoyGrubu] (yasin 2026-10-10: "varlık filtresi olan her
/// yere portföydeki filtreleri koymalıyız"): Portföy halkasının kümesi,
/// hisse ayrımı açıkken "BIST Hisse" / "ABD Hisse". Aynı bileşen
/// Performans › Filtre ve Portföy hareketleri › Filtrele'de.
class TurFiltreCipleri extends StatelessWidget {
  const TurFiltreCipleri({
    super.key,
    required this.secili,
    required this.ozet,
    required this.turlar,
    required this.onSec,
    this.siraOzeti,
  });

  final PortfoyGrubu? secili;
  final TurFiltreOzeti ozet;

  /// Çip SIRASININ hesaplandığı özet; boşsa [ozet]. Pasiflik yine [ozet]ten.
  ///
  /// yasin 2026-10-12 (TestFlight): "filtreler değiştikçe hoplayıp zıplıyor,
  /// yer değiştiriyor; sabit kalmalı." Sıra seçili kişinin/portföyün
  /// özetinden kurulunca Kişi ya da Portföy değişince çipler yer
  /// değiştiriyordu. Çağıran buraya kapsamdan BAĞIMSIZ (herkesin, tüm
  /// portföylerin) özetini verir: sıra sayfa açıkken sabit kalır, seçili
  /// kapsamda olmayan tür yerinde pasifleşir. Hiç kimsede olmayanlar yine
  /// sonda ("olmayanlar pasif şekilde listenin sonunda" kuralı korunur).
  final TurFiltreOzeti? siraOzeti;

  /// Gösterilecek türler (bayrakla kapalı tür çağıranda elenir).
  final List<PortfoyGrubu> turlar;
  final ValueChanged<PortfoyGrubu?> onSec;

  /// Çip sırası: elde olanlar değeri büyükten küçüğe (eşitse adet, sonra
  /// enum sırası), ardından elde olmayanlar enum sırasıyla. Saf — test eder.
  static ({List<PortfoyGrubu> eldeki, List<PortfoyGrubu> olmayan}) sirala(
      List<PortfoyGrubu> turlar, TurFiltreOzeti ozet) {
    final eldeki = [
      for (final t in turlar)
        if ((ozet.adet[t] ?? 0) > 0) t,
    ]..sort((a, b) {
        final d = (ozet.deger[b] ?? 0).compareTo(ozet.deger[a] ?? 0);
        if (d != 0) return d;
        final n = (ozet.adet[b] ?? 0).compareTo(ozet.adet[a] ?? 0);
        if (n != 0) return n;
        return turlar.indexOf(a).compareTo(turlar.indexOf(b));
      });
    final olmayan = [
      for (final t in turlar)
        if ((ozet.adet[t] ?? 0) == 0) t,
    ];
    return (eldeki: eldeki, olmayan: olmayan);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = sirala(turlar, siraOzeti ?? ozet);
    bool elde(PortfoyGrubu t) => (ozet.adet[t] ?? 0) > 0;
    SandikFiltreCipi cip(PortfoyGrubu t) => elde(t)
        ? SandikFiltreCipi(
            ad: t.labelOf(l),
            secili: secili == t,
            onTap: () => onSec(t),
          )
        : SandikFiltreCipi(
            ad: t.labelOf(l),
            secili: secili == t,
            // Pasif — seçiliyse kaldırılabilsin diye etkin kalır.
            onTap: secili == t ? () => onSec(t) : null,
            pasifEtiket: secili == t ? null : l.s2FiltreYok,
          );
    return Wrap(
      spacing: SandikSpace.sm,
      runSpacing: SandikSpace.sm,
      children: [
        SandikFiltreCipi(
          ad: l.allTypes,
          secili: secili == null,
          onTap: () => onSec(null),
        ),
        for (final t in s.eldeki) cip(t),
        for (final t in s.olmayan) cip(t),
      ],
    );
  }
}

/// Süzme çipi — uygulamanın TEK filtre çipi (seçici denetimi 2026-10-12).
///
/// Kural (`docs/TASARIM_DILI.md` §4): mod değiştirmek kayan segment
/// ([SandikSegment]), liste süzmek bu çip, çoklu aç/kapa grafik çipi.
/// Önceden aynı "süz" işi üç ayrı görünümle (köşe 14/20/22, dolgu üç ton)
/// yapılıyordu; kullanıcı neyin süzgeç neyin mod olduğunu şekilden
/// çıkaramıyordu.
///
/// Tam yuvarlak, 44 pt; seçiliyken amber dolgu + onay işareti (renk tek
/// başına bilgi taşımaz). [ikon] seçili değilken başta durur, seçilince
/// yerini onay işaretine bırakır.
class SandikFiltreCipi extends StatelessWidget {
  const SandikFiltreCipi({
    super.key,
    required this.ad,
    required this.secili,
    required this.onTap,
    this.pasifEtiket,
    this.ikon,
    this.ikonRengi,
  });

  final String ad;
  final bool secili;
  final VoidCallback? onTap;

  /// Doluysa çip pasif (portföyde yok); ekran okuyucuya "Fon, yok" denir.
  final String? pasifEtiket;

  /// Seçili değilken başta duran ikon (ör. tür ikonu).
  final IconData? ikon;
  final Color? ikonRengi;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pasif = pasifEtiket != null;
    // Sabit genişlik (yasin 2026-10-12: "filtreler hoplayıp zıplıyor"):
    // seçilince onay işareti ve kalın yazı çipi genişletiyor, `Wrap` satırı
    // yeniden kırıp komşu çipleri kaydırıyordu. Artık iki hâl aynı eni
    // tutar: baştaki ikon yuvası her zaman ayrılır (ikonsuz seçili olmayan
    // çipte yuva iki yana bölünür, yazı ortada kalır) ve yazı kalınlığı
    // seçimle değişmez — seçim dolgu, renk ve onay işaretiyle okunur.
    final basIkon = secili ? Icons.check_rounded : ikon;
    final renk = secili
        ? c.onAmber
        : pasif
            ? c.text36
            : c.text90;
    const yuva = 16.0 + SandikSpace.xs2;
    final yazi = Flexible(
      child: Text(
        ad,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.t.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600, color: renk),
      ),
    );
    final icerik = Row(
      mainAxisSize: MainAxisSize.min,
      children: basIkon != null
          ? [
              Icon(basIkon,
                  size: 16, color: secili ? renk : (ikonRengi ?? c.text58)),
              const SizedBox(width: SandikSpace.xs2),
              yazi,
            ]
          : [
              const SizedBox(width: yuva / 2),
              yazi,
              const SizedBox(width: yuva / 2),
            ],
    );

    final cip = AnimatedContainer(
      duration: SandikMotion.stateOf(context),
      curve: SandikMotion.enter,
      constraints: const BoxConstraints(minHeight: SandikTouch.min),
      padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
      decoration: BoxDecoration(
        // Pasif çip dolgusuz: yalnız çerçeve, zemin sayfanın kendisi.
        color: secili
            ? c.amberFill
            : pasif
                ? null
                : c.surface2,
        borderRadius: BorderRadius.circular(SandikTouch.min / 2),
        border: Border.all(color: secili ? c.amberFill : c.hairline),
      ),
      child: icerik,
    );
    if (pasif) {
      return Semantics(
        label: '$ad, $pasifEtiket',
        button: true,
        enabled: false,
        excludeSemantics: true,
        child: cip,
      );
    }
    return SandikTappable(
      onTap: onTap,
      selected: secili,
      semanticLabel: ad,
      // Etiket zaten [ad]; çipin kendi metni ikinci kez okunmasın
      // ("Tümü, Tümü").
      child: ExcludeSemantics(child: cip),
    );
  }
}
