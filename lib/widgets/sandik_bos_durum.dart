import 'package:flutter/material.dart';

import '../services/remote_config_service.dart';
import '../theme/sandik.dart';
import 'sandik_cizimi.dart';

/// Ortak boş durum: kapalı sandık + tek cümle (+ isteğe bağlı alt satır ve
/// eylem). Bayrak `goz_alici` açıkken boş ekranlar bunu çizer; kapalıyken
/// her ekran kendi eski çizimini korur (karar çağırandadır).
///
/// ## Neden (göz alıcılık C + TASARIM_DILI §6 madde 1, 2026-10-09)
/// Altı ekran boşluğu farklı ikon boyu ve yazıyla çiziyordu; kimi düz gri
/// metin, kimi 64pt gelen kutusu ikonu. Boşluk sandık'ın kendi çizimiyle
/// söylenir: kasa kapalı, içi henüz boş. Hata BOŞ DEĞİLDİR —
/// `SandikErrorView` (yeniden dene) kullanılır; bu bileşen hata için değil.
///
/// Kapak açılmaz, dokunulmaz: boş durumda "oyuncak" dikkati asıl eylemden
/// (ilk varlığı ekle) çalardı.
class SandikBosDurum extends StatelessWidget {
  const SandikBosDurum({
    super.key,
    required this.metin,
    this.alt,
    this.eylem,
  });

  final String metin;
  final String? alt;

  /// Varsa metnin altında (ör. "İlk varlığını ekle" düğmesi).
  final Widget? eylem;

  /// Çizimin boyu: 130pt tasarımın yarısı — boş liste kartında metni
  /// ezmeden karakter olarak okunur.
  static const double olcek = 0.5;

  @override
  Widget build(BuildContext context) {
    final alt = this.alt;
    final eylem = this.eylem;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SandikSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SandikCizimi(
              zemin: SandikZemini.yuzey,
              acik: false,
              dokunulabilir: false,
              olcek: olcek,
            ),
            const SizedBox(height: SandikSpace.md),
            Text(
              metin,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium?.copyWith(color: context.c.text58),
            ),
            if (alt != null) ...[
              const SizedBox(height: SandikSpace.xs),
              Text(
                alt,
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(color: context.c.text36),
              ),
            ],
            if (eylem != null) ...[
              const SizedBox(height: SandikSpace.md),
              eylem,
            ],
          ],
        ),
      ),
    );
  }
}

/// Kendi düzeni olan boş durumlarda (başlık + gövde + düğme) yalnız baştaki
/// ikonun yerini alan kapalı sandık. Bayrak `goz_alici` kapalıyken verilen
/// [ikon] birebir eski boy ve renkle çizilir — ekranın geri kalanı değişmez.
///
/// Yalnız "henüz bir şey yok" boşluğunda kullanılır; süzgeç sonucu boş
/// ("eşleşme yok") ya da silinenler gibi başka anlamlı boşlukta ikon kalır.
class SandikBosIkonu extends StatelessWidget {
  const SandikBosIkonu({
    super.key,
    required this.ikon,
    required this.boyut,
    this.renk,
  });

  final IconData ikon;
  final double boyut;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    if (!RemoteConfigService.instance.gozAlici) {
      return Icon(ikon, size: boyut, color: renk ?? context.c.text36);
    }
    return const SandikCizimi(
      zemin: SandikZemini.yuzey,
      acik: false,
      dokunulabilir: false,
      olcek: SandikBosDurum.olcek,
    );
  }
}
