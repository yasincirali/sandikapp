import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/altin_gram_ozeti.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// "Toplam 42,6 gr · 24 ayar karşılığı 39,10 gr": Portföy Altın grubunun
/// tek satırı (liste başlığının altı ve büyük halkada Altın dilimi).
///
/// ## Kararlar (Ar-Ge 7 Kas 18:06 #1)
/// - Özet yoksa (portföyde gram altın yok, yalnız ons) hiçbir şey çizilmez;
///   "ons hariç" diye açıklama da yazılmaz.
/// - Bakiye gizliyken satır da gizlenir: gram tutar değil ama servet ipucu.
/// - Büyük yazıda kesilmez, satıra kırılır (maxLines yok); 3,1× ve 320 pt
///   `altin_gram_satiri_test`'te kilitli.
/// - Ekran okuyucu "gr" kısaltmasını harf harf okumasın diye ayrı etiket.
class AltinGramSatiri extends StatelessWidget {
  const AltinGramSatiri({
    super.key,
    required this.ozet,
    required this.gizli,
    this.textAlign = TextAlign.start,
  });

  final AltinGramOzeti? ozet;
  final bool gizli;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final o = ozet;
    if (o == null || gizli) return const SizedBox.shrink();
    final l = context.l10n;
    final gram = fmtGram(o.gram);
    final has = fmtGram(o.has);
    return Semantics(
      container: true,
      label: l.pfAltinGramSemantik(gram, has),
      child: ExcludeSemantics(
        child: Text(
          l.pfAltinGramSatiri(gram, has),
          textAlign: textAlign,
          style: context.t.bodySmall?.copyWith(color: context.c.text58),
        ),
      ),
    );
  }
}
