import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart' show premiumKilitliProvider;
import '../providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'para_akisi_karti.dart' show KilitSatiri;

/// Panel bu satırın yuvasını kursun mu: sayı var (pozisyon zararda) VE
/// Premium özellikleri görünür. Paywall kapalıyken canlı kullanıcı satırı
/// hiç görmez (Premium varsayılanı, 2026-11-11).
bool basaBasSatiriCizilir(WidgetRef ref, double? oran) =>
    oran != null && ref.watch(premiumOzellikleriGorunurProvider);

/// "Başa baş için %25 yükselmeli" — Portföy kart panelinde zarardaki
/// pozisyonun satırı (Ar-Ge 2026-11-11 #1 + #4, Premium).
///
/// Hesap [basaBasIcinGerekenYukselis]'te (model katmanı); bu widget yalnız
/// yazar. Çağıran satırı ancak sayı varken (pozisyon zararda) ve Premium
/// özellikleri görünürken kurar — kârdaki pozisyona "Premium'da başa baş
/// hesabın var" demek boş vaat olurdu (kur ayrışması satırıyla aynı desen).
///
/// ## Görünürlük (kur ayrışması / geçmiş fiyatlar deseni)
/// - [basaBasSatiriCizilir] false → çağıran yuvayı hiç kurmaz (paywall
///   kapalı ve admin değil, ya da zararda değil). Karar çağıranda çünkü
///   panel satırın yokluğunda yerleşimi değiştirir (temettü sola kayar,
///   satır aralığı da gider); boş bir `Expanded` 12 pt'lik delik bırakırdı.
/// - `premiumKilitliProvider` → [KilitSatiri] (kaynak `basa_bas` → paywall
///   X-Ray kartı: aynı "param gerçekte ne durumda" sorusu).
/// - Açıksa panelin öteki satırları gibi etiket + değer.
///
/// ## Anlam renkte değil cümlede (HIG renk körlüğü)
/// Değer zarar kırmızısıyla boyanmaz: "zarardasın" bilgisi kartın başında
/// zaten işaretli tutarla var; bu satır bir hedef söyler, uyarı değil.
/// Etiket ve değer alt alta okununca tek cümledir ("Başa baş için" /
/// "%25 yükselmeli"); ekran okuyucu da tek cümle okur.
class BasaBasSatiri extends ConsumerWidget {
  const BasaBasSatiri({super.key, required this.oran});

  /// Gereken yükseliş, yüzde (25.0 = %25). Pozitif; çağıran `null`da kurmaz.
  final double oran;

  /// Hane sayısı büyüklüğe göre: %25 ile %143 tam sayı okunur, küçük
  /// zararda ondalık anlam taşır (%0,4 ile %0 aynı şey değil).
  static String oranMetni(double oran) =>
      fmtPct(oran, digits: oran < 1 ? 2 : (oran < 10 ? 1 : 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (ref.watch(premiumKilitliProvider)) {
      return KilitSatiri(
        metin: l.basaBasKilitli,
        kaynak: 'basa_bas',
        ozellik: 'basa_bas',
        kilitEtiketi: l.goalDateLockedLabel,
      );
    }
    final c = context.c;
    final metin = oranMetni(oran);
    return Semantics(
      container: true,
      label: l.basaBasCumle(metin),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panelin `_DetailItem` diliyle aynı iki kat; ağırlık tavanı w600
          // (unslop, 2026-11-05) — komşu etiketler w700'den bu tavana iner.
          Text(
            l.basaBasIcin,
            style: context.t.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600, color: c.text36),
          ),
          const SizedBox(height: SandikSpace.xs),
          Text(
            l.basaBasYukselmeli(metin),
            style: context.t.numSmall
                .copyWith(fontWeight: FontWeight.w600, color: c.text90),
          ),
        ],
      ),
    );
  }
}
