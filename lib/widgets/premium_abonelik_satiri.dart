import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../providers/premium_provider.dart';
import '../services/crash_reporter.dart';
import '../theme/sandik.dart';

/// Profil'de Premium hakkı satırı (S14-A, 2026-10-05): ne tür hak, ne zaman
/// yenilenir/biter, ve iki eylem.
///
/// - "Yönet" yalnız mağaza aboneliğinde: iptal/plan değişikliği mağazanın
///   kendi sayfasında yapılır (Apple/Google kuralı); uygulama aracı olamaz.
/// - "Satın alımları geri yükle" hakları sunucudan yeniden okur. Abonelik
///   durumu RevenueCat webhook'uyla sunucuya yazılır (0116); başka cihazda
///   alınmış abonelik de böylece görünür.
class PremiumAbonelikSatiri extends ConsumerWidget {
  const PremiumAbonelikSatiri({super.key, required this.hak});

  final PremiumHakki hak;

  static final _yonetAdresi = {
    TargetPlatform.iOS: 'https://apps.apple.com/account/subscriptions',
    TargetPlatform.android:
        'https://play.google.com/store/account/subscriptions',
  };

  Future<void> _yonet() async {
    final adres = _yonetAdresi[defaultTargetPlatform];
    if (adres == null) return;
    try {
      await launchUrl(Uri.parse(adres), mode: LaunchMode.externalApplication);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'PremiumAbonelikSatiri._yonet');
    }
  }

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
    final String? alt;
    if (bitis == null) {
      alt = null;
    } else if (hak.kaynak == 'revenuecat' &&
        !hak.iptalEdildi &&
        magaza != null) {
      alt = l10n.prmYenileme(bitis, magaza);
    } else {
      alt = l10n.prmBitis(bitis);
    }

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
                  onPressed: _yonet,
                  child: Text(l10n.prmYonet),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
