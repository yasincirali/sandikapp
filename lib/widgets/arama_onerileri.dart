import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'tur_filtre_cipleri.dart' show SandikFiltreCipi;

/// "Bunu mu demek istedin?" bölümü: boş arama sonucunun altında yakın
/// kodlar (`yakinOneriler`, müşteri işi 10 Kas).
///
/// Çip yeni bir bileşen değil: uygulamanın tek çipi [SandikFiltreCipi]
/// (44 pt, tam yuvarlak, etiketli). Seçili hâli yok; dokunmak öneriyi
/// normal bir sonuç gibi seçer. Varlık Ekle seçicileri ve genel arama aynı
/// bölümü kullanır, iki yüzeyde iki görünüm olmasın.
class AramaOnerileri extends StatelessWidget {
  const AramaOnerileri({super.key, required this.oneriler});

  /// Kod, ad (ekran okuyucu için) ve dokunuş.
  final List<({String kod, String ad, VoidCallback onTap})> oneriler;

  @override
  Widget build(BuildContext context) {
    if (oneriler.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return Column(
      key: const ValueKey('arama_onerileri'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.aramaOneriBaslik,
            textAlign: TextAlign.center,
            style: context.t.bodyMedium?.copyWith(color: context.c.text58)),
        const SizedBox(height: SandikSpace.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SandikSpace.sm,
          runSpacing: SandikSpace.sm,
          children: [
            for (final o in oneriler)
              SandikFiltreCipi(
                key: ValueKey('arama_onerisi_${o.kod}'),
                ad: o.kod,
                secili: false,
                semantik: l.aramaOneriSemantik(o.kod, o.ad),
                onTap: o.onTap,
              ),
          ],
        ),
      ],
    );
  }
}
