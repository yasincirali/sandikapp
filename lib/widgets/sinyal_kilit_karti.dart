import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'premium_kilit_karti.dart';

/// Sinyal bildirimlerinin ve Premium göstergelerin kilidi (yasin,
/// 2026-10-10: "en yaygın 3 tanesi ücretsiz gösterilmeli, ancak kalanları ve
/// custom gösterge bununla push bildirimi feature'ı premium olmalı").
///
/// Paywall açıkken Premium olmayan kullanıcıda Sinyal Ayarları'nın
/// bildirim bölümünün YERİNE çizilir (karar `sinyalBildirimiKilitliProvider`).
/// Panelin kendisi ücretsizde açık; bu kart yalnız neyin ekleneceğini somut
/// söyler — beş gösterge, periyot ayarı ve her varlıkta bildirim.
class SinyalKilitKarti extends StatelessWidget {
  const SinyalKilitKarti({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumKilitKarti(
      ikon: Icons.insights_rounded,
      baslik: l.sgnKilitBaslik,
      govde: l.sgnKilitGovde,
      kilitMetni: l.sgnKilitSatir,
      kaynak: 'sinyal_kilit',
    );
  }
}
