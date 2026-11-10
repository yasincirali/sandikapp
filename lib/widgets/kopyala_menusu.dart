import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import '../utils/sandik_snack.dart';
import 'sandik_baglam_menusu.dart';

/// Varlık kodu ve fiyatına uzun bas → "Kodu kopyala" / "Fiyatı kopyala"
/// (ücretsiz, 2026-11-10).
///
/// ## Neden görünür öğe yok
/// Kopyalama ikinci derece bir iş (kodu başka uygulamada aramak, fiyatı
/// mesaja yapıştırmak); başlığa düğme eklemek A düzeninin sade üst kısmını
/// bozardı. iOS'ta metne uzun basıp kopyalamak sistem alışkanlığı; burada
/// aynı jest, ama `SelectableText` yerine menü: seçim tutamaçları büyük
/// fiyatın dönen hanelerini (`ParaMetni`) ve başlık uçuşunu (`Hero`) bozar.
/// Ekran okuyucu jesti `onLongPressHint` ile duyurulur ve aynı eylemi
/// çalıştırır.
///
/// ## Menü bileşeni
/// `showSandikAcilirMenu` (öğeye bağlı açılır menü, HIG pull-down / Material
/// açılır menü): tek modal, 44 pt satırlar, hareketi azaltta animasyonsuz.
///
/// ## Kopyalanan metin
/// Fiyat, ekranda yazılan metnin TA KENDİSİ ([fiyat]; çağıran büyük fiyatı
/// biçimlediği dizgeyi verir): "₺312,40" görüp "312.4" yapıştırmak şaşırtır.
/// Fiyat bilinmiyorsa ("—") satır menüye girmez.
class KopyalaUzunBasma extends StatelessWidget {
  const KopyalaUzunBasma({
    super.key,
    required this.kod,
    required this.child,
    this.fiyat,
  });

  final String kod;

  /// Ekrandaki biçimiyle fiyat; `null` → yalnız kod kopyalanır.
  final String? fiyat;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Menü bu öğenin kutusuna bağlanır (`showSandikAcilirMenu` konumu
    // verilen bağlamın çizim kutusundan ölçer).
    void ac() => _menuAc(context);
    return Semantics(
      onLongPressHint: context.l10n.kopyalaIpucu,
      onLongPress: ac,
      child: GestureDetector(onLongPress: ac, child: child),
    );
  }

  void _menuAc(BuildContext oge) {
    final l = oge.l10n;
    final f = fiyat;
    showSandikAcilirMenu(oge, eylemler: [
      SandikBaglamEylemi(
        etiket: l.kopyalaKod,
        ikon: Icons.copy_rounded,
        anahtar: const ValueKey('kopyalaKod'),
        onSec: () => _kopyala(oge, kod),
      ),
      if (f != null && f.isNotEmpty && f != '—')
        SandikBaglamEylemi(
          etiket: l.kopyalaFiyat,
          ikon: Icons.content_copy_outlined,
          anahtar: const ValueKey('kopyalaFiyat'),
          onSec: () => _kopyala(oge, f),
        ),
    ]);
  }

  Future<void> _kopyala(BuildContext oge, String metin) async {
    await Clipboard.setData(ClipboardData(text: metin));
    // Seçim tonu: sık, kalıcı sonucu olmayan küçük eylem (`SandikHaptic`).
    SandikHaptic.selection.perform();
    if (!oge.mounted) return;
    sandikSnack(oge, oge.l10n.kopyalandi);
  }
}
