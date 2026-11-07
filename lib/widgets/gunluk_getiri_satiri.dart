import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/money_format.dart';

/// "Son 30 günde günde ortalama ~₺12": para piyasası fonunun varlık
/// ekranında pozisyon satırının altı (müşteri raporu 7 Kas 22:30 #1).
///
/// ## Kararlar
/// - Ücretsiz, kilit yok: sayım, analiz değil (altın gramıyla aynı karar).
/// - Tutar yoksa (`null`: kategori, seri ya da değer bilinmiyor) hiçbir şey
///   çizilmez; açıklama da yazılmaz.
/// - Bakiye gizliyken satır da gizlenir ([AltinGramSatiri] ile aynı):
///   günlük kazanç bakiyeyi ele verir; maskeli "~₺••••" bir şey söylemez.
/// - Tutar baz parayla yazılır (üstündeki "Pozisyonun" satırıyla aynı
///   biçim); renk yok, yön işaretle (eksi nadirdir ama gizlenmez).
/// - Büyük yazıda kesilmez, satıra kırılır (maxLines yok).
/// - Portföy liste satırına konmaz: liste satırı sade kalır.
class GunlukGetiriSatiri extends StatelessWidget {
  const GunlukGetiriSatiri(
      {super.key, required this.tutarTRY, required this.baz});

  final double? tutarTRY;
  final BazPara baz;

  @override
  Widget build(BuildContext context) {
    final t = tutarTRY;
    if (t == null || baz.gizli) return const SizedBox.shrink();
    final tutar = baz.fmt(t);
    return Padding(
      padding: const EdgeInsets.only(top: SandikSpace.xs),
      // Ekran okuyucu "~" işaretini okumaz ya da "tilde" der; etikette
      // "yaklaşık" yazılı.
      child: Semantics(
        label: context.l10n.gunlukGetiriA11y(tutar),
        excludeSemantics: true,
        child: Text(
          context.l10n.gunlukGetiriSatiri(tutar),
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
      ),
    );
  }
}
