import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../providers/premium_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/abonelik_yonetimi.dart';
import '../theme/sandik.dart';

/// Profil'de Premium hakkı satırı (S14-A, 2026-10-05): ne tür hak, ne zaman
/// yenilenir/biter, ve iki eylem.
///
/// - "Yönet" yalnız mağaza aboneliğinde: iptal/plan değişikliği mağazanın
///   kendi sayfasında yapılır (Apple/Google kuralı); uygulama aracı olamaz.
///   iOS'ta o sayfa uygulama içinde açılır (`AbonelikYonetimi`, 2026-10-23).
/// - "Satın alımları geri yükle" hakları sunucudan yeniden okur. Abonelik
///   durumu RevenueCat webhook'uyla sunucuya yazılır (0116); başka cihazda
///   alınmış abonelik de böylece görünür.
class PremiumAbonelikSatiri extends ConsumerWidget {
  const PremiumAbonelikSatiri({super.key, required this.hak});

  final PremiumHakki hak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.c;
    final t = context.t;
    final tarihBicimi =
        DateFormat('d MMMM y', Localizations.localeOf(context).toString());
    final baslik = hak.hediye
        ? l10n.prmAbonelikHediye
        : hak.yillik
            ? l10n.prmAbonelikYillik
            : l10n.prmAbonelikAylik;
    final bitis =
        hak.bitis == null ? null : tarihBicimi.format(hak.bitis!.toLocal());
    final magaza = switch (hak.magaza) {
      'app_store' || 'APP_STORE' => 'App Store',
      'play_store' || 'PLAY_STORE' => 'Google Play',
      _ => null,
    };
    // Hediyede kalan gün de yazılır ve son günlerde "devam et" düğmesi
    // çıkar: bitiş sessiz olmasın (paywall incelemesi, 2026-10-20).
    final kalan = hak.hediye ? hak.kalanGun(DateTime.now()) : null;
    final String? alt;
    if (bitis == null) {
      alt = null;
    } else if (hak.kaynak == 'revenuecat' &&
        !hak.iptalEdildi &&
        magaza != null) {
      alt = l10n.prmYenileme(bitis, magaza);
    } else if (kalan != null) {
      alt = l10n.prmHediyeKalan(bitis, kalan);
    } else {
      alt = l10n.prmBitis(bitis);
    }
    final sonGunler = kalan != null && kalan <= hediyeSonGunlerEsigi;

    return SandikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: c.amberText),
              const SizedBox(width: SandikSpace.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(baslik,
                        style: t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: c.text90)),
                    if (alt != null)
                      Text(alt, style: t.bodySmall?.copyWith(color: c.text58)),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: SandikSpace.xs,
            children: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                onPressed: () => ref.invalidate(premiumHaklariProvider),
                child: Text(l10n.prmGeriYukle),
              ),
              if (hak.kaynak == 'revenuecat')
                TextButton(
                  style: TextButton.styleFrom(minimumSize: SandikTouch.minSize),
                  onPressed: AbonelikYonetimi.ac,
                  child: Text(l10n.prmYonet),
                ),
              if (sonGunler)
                FilledButton.tonal(
                  style:
                      FilledButton.styleFrom(minimumSize: SandikTouch.minSize),
                  onPressed: () =>
                      PaywallScreen.show(context, source: 'hediye_bitiyor'),
                  child: Text(l10n.prmHediyeDevam),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
