import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/elde_tutma.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// "2 yıl 3 aydır tutuyorsun · yıllık ortalama +%31,2" (Ar-Ge 7 Kas 20:30
/// #6, Premium). Varlık ekranında pozisyon satırının ("Pozisyonun +₺X")
/// hemen altında: o satır alıştan bugüne toplamı, bu satır aynı sürenin
/// yıllık karşılığını söyler.
///
/// Dönem seçiciye bağlı DEĞİL: görevde "Tümü döneminde" deniyordu ama
/// varlık ekranında "Tümü" dönemi yok (en uzun 5Y). Üstündeki pozisyon
/// satırı gibi alıştan bugüne ölçer; dönem değişince oynamaz.
///
/// Kilit deseni temettü verimi satırıyla aynı (#309, `TemettuGecmisiKarti`):
/// paywall açıkken herkes satırın varlığını görür, ücretsizde sayı yerine
/// [KilitSatiri] (kaynak `yillik_getiri`); paywall kapalıyken yalnız admin.
/// Kilit satırı da ancak hesaplanmış bir sayı varken çıkar.
///
/// Kilitli satır yarı açıktır (2026-11-12): süre kullanıcının KENDİ
/// defterinden (ilk alış günü) ücretsiz okunur, yalnız yıllık oran kilitli
/// ("5 yıl 2 aydır tutuyorsun · yıllık ortalaman Premium'da"). Süre ile
/// oran aynı [EldeTutma]'dan gelir; satır ancak o hesaplanmışken kurulur,
/// yani süresiz bir "eski sabit cümle" yolu yok. Oran açılmaz: kilidin
/// sattığı şey o.
///
/// Yön işaretle de yazılır (`fmtPctIsaretli`): renk tek başına anlam
/// taşımaz. Bakiye gizliyken yüzde açık kalır (oran büyüklüğü ele vermez).
class EldeTutmaSatiri extends ConsumerWidget {
  const EldeTutmaSatiri({super.key, required this.ozet});

  final EldeTutma ozet;

  /// "2 yıl 3 ay" / "2 yıl".
  static String sure(AppLocalizations l, EldeTutma e) => e.ay == 0
      ? l.eldeTutmaSureYil('${e.yil}')
      : l.eldeTutmaSureYilAy('${e.yil}', '${e.ay}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(premiumOzellikleriGorunurProvider)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final Widget icerik;
    if (ref.watch(premiumKilitliProvider)) {
      icerik = KilitSatiri(
        metin: l.eldeTutmaKilitli(sure(l, ozet)),
        kaynak: 'yillik_getiri',
        ozellik: 'yillik_getiri',
        kilitEtiketi: l.goalDateLockedLabel,
      );
    } else {
      final duz = ozet.yillikPct.abs() < 0.05;
      final pct = duz
          ? fmtPct(0, digits: 1)
          : fmtPctIsaretli(ozet.yillikPct, digits: 1);
      final renk = duz
          ? context.c.text58
          : (ozet.yillikPct > 0 ? context.c.gain : context.c.loss);
      final s = sure(l, ozet);
      icerik = Semantics(
        label: l.eldeTutmaA11y(s, pct),
        excludeSemantics: true,
        child: Text(
          l.eldeTutmaSatiri(s, pct),
          style: context.t.bodySmall?.copyWith(color: renk),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      child: icerik,
    );
  }
}
