import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Uygulamanın TEK paylaş düğmesi (yasin 2026-10-30: "paylaş butonları
/// dikkat çekici olmasın, tüm uygulamada aynı standartta olmalı").
///
/// ## Standart
///   · İkon `Icons.adaptive.share`: iOS'ta kutudan çıkan ok, Android'de
///     Material'ın üç noktalı simgesi — her platform kendi kalıbını görür
///     (HIG "sistem kalıbı"; Android'de Material karşılığı bozulmaz).
///     Eskiden Profil amber `share_rounded`, kartlar `ios_share` idi.
///   · 18 pt, `text58` gri; dolgu, çerçeve, amber yok. Paylaşım bir yan
///     eylem: kartın sayısıyla yarışmaz. `text36` daha sessiz olurdu ama
///     eylem simgesi için 3:1 kontrastın altına iner.
///   · 44 pt dokunma alanı (HIG), `tooltip` = erişilebilirlik etiketi.
///
/// ## Yer
/// Kartın SAĞ ÜST köşesi, başlık satırının hizasında — kartın içeriğine
/// (hüküm, manşet rakam) değil, kartın kendisine ait olduğu yerde. Kart
/// yüksekliği değişmesin diye [kartKosesi] ile kartın üstüne bindirilir;
/// başlık satırı sağdan [kartKosesiPayi] kadar boşluk bırakır.
///
/// Paylaşmanın ekranın asıl işi olduğu yerler (yıl özeti hikâyesinin son
/// sayfası, yorum notu PDF sayfası, Ayarlar'daki dışa aktarım satırı)
/// etiketli düğmelerini korur; simge yine bu simgedir.
class SandikPaylasDugmesi extends StatelessWidget {
  const SandikPaylasDugmesi({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final String tooltip;

  /// Kart başlık satırının, köşedeki düğmeye bırakacağı sağ boşluk.
  static const double kartKosesiPayi = SandikSpace.lg;

  /// Düğmeyi [kart]ın sağ üst köşesine bindirir. [ust]: düğmenin dikey
  /// merkezi kartın başlık satırına otursun diye üstten uzaklık.
  static Widget kartKosesi({
    required Widget kart,
    required Widget? dugme,
    double ust = 0,
  }) {
    if (dugme == null) return kart;
    return Stack(
      children: [
        kart,
        Positioned(top: ust, right: 0, child: dugme),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(Icons.adaptive.share),
        iconSize: 18,
        color: context.c.text58,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
            width: SandikTouch.min, height: SandikTouch.min),
      );
}
