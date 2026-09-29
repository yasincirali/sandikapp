import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Tür payı şeridi + altında küçük yüzdeler.
///
/// Zirve kartı, Zirve ekranı ve ayrıntı sayfası aynı şeridi kullanır:
/// kullanıcı bir yerde öğrendiği görseli her yerde tanır. Renkler
/// `AssetType.color`'dan gelir (tür dökümü kartıyla aynı), bilinmeyen tür
/// için nötr `text36`.
///
/// ## Neden sabit tür sırası (2026-09-29)
/// Dilimler büyükten küçüğe değil `AssetType` sırasıyla dizilir. Portföyler
/// arasında geçerken her tür AYNI yerde kalır ve genişliği akarak değişir
/// ("daha göz alıcı ve akışkan" kararı); sıralı dizimde dilimler yer
/// değiştirir, göz hangi rengin nereye gittiğini kaybeder. Alttaki yüzdeler
/// yine büyükten küçüğe — okuma sırası orada.
///
/// Şerit yalnız GÖRSELdir; anlamı üstteki cümle taşır
/// (`ZirveKiyas.dagilimCumlesi`). Bu yüzden burada başlık yok.
class ZirveDagilimSeridi extends StatelessWidget {
  const ZirveDagilimSeridi({
    super.key,
    required this.pay,
    this.yukseklik = 14,
    this.enFazlaEtiket,
    this.canlandir = true,
  });

  /// {tür: yüzde}, toplam ≈ 100.
  final Map<String, double> pay;
  final double yukseklik;

  /// Alt satırda kaç tür yazılsın (null → hepsi). Kart dar, üçle yetinir.
  final int? enFazlaEtiket;

  /// Pay değişince dilimler akarak geçsin mi (ekran: evet; kart ve alt
  /// sayfa: hayır — onlar zaten yeniden kurulur).
  final bool canlandir;

  static const double _ayrac = 1.5;

  /// Sabit dilim sırası: bilinen türler `AssetType` sırasıyla, bilinmeyenler
  /// sonda (ada göre).
  static List<String> _sira(Map<String, double> pay) {
    final bilinen = [for (final t in AssetType.values) t.name];
    final bilinmeyen = pay.keys.where((k) => !bilinen.contains(k)).toList()
      ..sort();
    return [...bilinen, ...bilinmeyen];
  }

  static Color renk(BuildContext context, String tur) {
    for (final t in AssetType.values) {
      if (t.name == tur) return t.color;
    }
    return context.c.text36;
  }

  static String etiket(BuildContext context, String tur) {
    for (final t in AssetType.values) {
      if (t.name == tur) return t.labelOf(context.l10n);
    }
    final ad = ZirveKiyas.turAd(tur);
    return ad.isEmpty ? '—' : ad[0].toUpperCase() + ad.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final etiketler = ZirveKiyas.sirali(pay);
    if (etiketler.isEmpty) {
      return Container(
        height: yukseklik,
        decoration: BoxDecoration(
          color: context.c.overlay,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
      );
    }
    final sira = _sira(pay);
    final toplam = etiketler.fold<double>(0, (s, e) => s + e.pay);
    final gorunen = enFazlaEtiket == null
        ? etiketler
        : etiketler.take(enFazlaEtiket!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: SizedBox(
            height: yukseklik,
            child: LayoutBuilder(
              builder: (context, c) {
                final dolu = sira.where((t) => (pay[t] ?? 0) > 0.5).length;
                final alan = c.maxWidth - _ayrac * (dolu - 1).clamp(0, 99);
                // Görünmeyen türler de ağaçta kalır (genişlik 0): böylece
                // bir tür belirip kaybolurken de akar, sıçramaz.
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in sira)
                        AnimatedContainer(
                          key: ValueKey('serit-$t'),
                          duration: SandikMotion.of(context,
                              canlandir ? SandikMotion.flow : Duration.zero),
                          curve: SandikMotion.glide,
                          width: toplam <= 0
                              ? 0
                              : alan * ((pay[t] ?? 0) > 0.5 ? pay[t]! : 0) /
                                  toplam,
                          margin: EdgeInsets.only(
                              right: (pay[t] ?? 0) > 0.5 ? _ayrac : 0),
                          color: renk(context, t),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.xs2),
        Wrap(
          spacing: SandikSpace.smd,
          runSpacing: SandikSpace.xs,
          children: [
            for (final d in gorunen)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: renk(context, d.tur),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: SandikSpace.xs2),
                  Text(
                    '${etiket(context, d.tur)} %${fmtNum(d.pay, digits: 0)}',
                    style: context.t.labelMedium?.copyWith(
                      letterSpacing: 0,
                      color: context.c.text58,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
