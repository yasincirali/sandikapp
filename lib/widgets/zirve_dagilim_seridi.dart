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

  /// Pay değişince dilimler kayarak geçsin mi (ekran: evet; kart: hayır,
  /// kart dönemle birlikte zaten yeniden kurulur).
  final bool canlandir;

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
    final dilimler = ZirveKiyas.sirali(pay);
    if (dilimler.isEmpty) {
      return Container(
        height: yukseklik,
        decoration: BoxDecoration(
          color: context.c.overlay,
          borderRadius: BorderRadius.circular(SandikRadius.sm),
        ),
      );
    }
    final etiketler =
        enFazlaEtiket == null ? dilimler : dilimler.take(enFazlaEtiket!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SandikRadius.sm),
          child: SizedBox(
            height: yukseklik,
            child: Row(
              children: [
                // Dilim genişliği `flex` ile oransal; flex kendisi canlanmaz,
                // rengin geçişi `AnimatedContainer`dan gelir. Yeterli: dönem
                // değişince şerit yeniden kurulur, kullanıcı "kayma" değil
                // "yenilenme" görür; hareketi azalt açıkken süre sıfır.
                for (final d in dilimler)
                  Flexible(
                    flex: (d.pay * 100).round().clamp(1, 100000),
                    child: AnimatedContainer(
                      duration: SandikMotion.of(context,
                          canlandir ? SandikMotion.surface : Duration.zero),
                      curve: SandikMotion.move,
                      margin: const EdgeInsets.only(right: 1.5),
                      color: renk(context, d.tur),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SandikSpace.xs2),
        Wrap(
          spacing: SandikSpace.smd,
          runSpacing: SandikSpace.xs,
          children: [
            for (final d in etiketler)
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
