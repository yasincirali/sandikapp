import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/sandik.dart';
import 'sandik_app_bar.dart';
import 'sandik_async_button.dart';
import 'sandik_ikon_gecisi.dart';

/// Listede çoklu seçim — tek bileşen (2026-11-12, Hareketler toplu silme).
///
/// ## Kalıp (iOS Fotoğraflar / Mail düzenleme kipi)
/// Satıra uzun bas → seçim kipi açılır, o satır seçili. Kipte satır başında
/// [SandikSecimIsareti] durur, dokunuş seçimi çevirir; üst çubuk
/// [SandikSecimCubugu] olur: "N seçili", "Sil", "Vazgeç". Geri tuşu/hareketi
/// kipi kapatır (ekran `PopScope` ile tutar), sayfayı değil.
///
/// Alarmlar'da çoklu seçim yoktu (görev "oradaki deseni kullan" diyordu;
/// orada uzun basma bağlam menüsü açar). İlk kullanan Hareketler; ikinci
/// liste buradan alır, kendi işaretini/çubuğunu yazmaz.
///
/// ## Silme onaysız
/// "Sil" soru sormaz (proje kuralı: silmeyi asla zorlaştırma); güvenlik ağı
/// silmeden sonraki "Geri al" snack'ıdır. Sil istek attığı için
/// [SandikAsyncButton] (tek yükleniyor davranışı).

/// Seçim kipinde satır başı işareti: boş halka / dolu onay.
///
/// Durum yalnız renkle verilmez: seçili hâlin İKONU başka (onaylı daire).
/// Ekran okuyucuya satırın kendisi `selected` der; işaret süs, okunmaz.
class SandikSecimIsareti extends StatelessWidget {
  const SandikSecimIsareti({super.key, required this.secili});

  final bool secili;

  /// İşaretin kapladığı genişlik — satır içeriği bu kadar sağa kayar.
  static const double boyut = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: boyut,
        child: SandikIkonGecisi(
          secili
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          renk: secili ? c.amberText : c.text36,
          boyut: boyut,
        ),
      ),
    );
  }
}

/// Seçim kipinin üst çubuğu: "N seçili" · Sil · Vazgeç.
///
/// Geri oku yok: kipten çıkış "Vazgeç" ya da geri tuşu/hareketi (Fotoğraflar
/// gibi vazgeç sağda). [onSil] `null` → Sil pasif (hiç seçim yok).
class SandikSecimCubugu extends StatelessWidget implements PreferredSizeWidget {
  const SandikSecimCubugu({
    super.key,
    required this.sayi,
    required this.onSil,
    required this.onVazgec,
  });

  final int sayi;
  final Future<void> Function()? onSil;
  final VoidCallback onVazgec;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.c;
    return SandikAppBar(
      showBack: false,
      // Sayı değişince ekran okuyucu yeni sayıyı okusun.
      titleWidget: Semantics(
        liveRegion: true,
        child: Text(
          l10n.secimSayisi(sayi),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.t.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: c.text90,
          ),
        ),
      ),
      actions: [
        SandikAsyncButton.kompakt(
          tur: SandikAsyncTur.metin,
          onPressed: onSil,
          style: TextButton.styleFrom(foregroundColor: c.danger),
          child: Text(l10n.delete),
        ),
        TextButton(
          onPressed: onVazgec,
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: SandikSpace.xs),
      ],
    );
  }
}
