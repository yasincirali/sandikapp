import 'package:flutter/material.dart';

import '../services/share_card_service.dart';
import '../theme/sandik.dart';
import 'sandik_async_button.dart';

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
  }) : onPaylas = null;

  /// Belge hazırlayıp paylaşan (istek atan) düğme: iş sürerken simgenin
  /// yerinde yükleme göstergesi döner, ikinci dokunuş yutulur
  /// (`SandikAsyncTap`; CLAUDE.md "istek atan düğme"). [onPaylas] düğmenin
  /// kendi dikdörtgenini alır: iPad paylaşım penceresinin oku düğmeyi
  /// göstersin (aylık rapor PDF'i, 2026-10-31).
  const SandikPaylasDugmesi.istekli({
    super.key,
    required Future<void> Function(Rect? kaynak) this.onPaylas,
    required this.tooltip,
  }) : onPressed = null;

  final VoidCallback? onPressed;
  final Future<void> Function(Rect? kaynak)? onPaylas;
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
  Widget build(BuildContext context) {
    final istek = onPaylas;
    if (istek == null) return _simge(context);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: SizedBox.square(
        dimension: SandikTouch.min,
        child: SandikAsyncTap(
          semanticLabel: tooltip,
          onTap: () => istek(ShareCardService.originOf(context)),
          child: Center(
            child:
                Icon(Icons.adaptive.share, size: 18, color: context.c.text58),
          ),
        ),
      ),
    );
  }

  Widget _simge(BuildContext context) => IconButton(
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
