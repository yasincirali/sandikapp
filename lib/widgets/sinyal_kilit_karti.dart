import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'premium_kilit_karti.dart';

/// Teknik sinyallerin Premium kilidi (yasin, 2026-10-10: "varlık gösterge
/// sinyali özelliği tamamen premiuma geçsin").
///
/// Paywall açıkken Premium olmayan kullanıcıda gösterge panelinin, sinyal
/// kartının ve tek varlık şeridinin YERİNE çizilir (karar
/// `sinyalYuzeyiProvider`'da). Neyin kilitli olduğunu somut söyler — sekiz
/// gösterge ve her varlıkta bildirim — ve paywall'u açar. Özelliği
/// tümden gizlemek yerine kilit: görünmeyen şeyin satış anı olmaz.
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
