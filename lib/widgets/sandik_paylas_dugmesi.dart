import 'dart:math' as math;

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
/// ## Yer (yasin 2026-10-31: "garip bir yerde duruyor; dikkat çekmeyecek,
/// simetri ve ahengi bozmayacak şekilde, tüm uygulamada")
/// Bulunduğu yüzeyin BAŞLIK SATIRININ SON ÖĞESİ, o satırın içinde
/// ([satirSonunda]). Simge satırın ortasına oturur ve sağ kenarı içeriğin
/// sağ kenarıyla aynı çizgidedir: altındaki rozet/tutar hangi çizgide
/// bitiyorsa simge de orada biter (iOS gezinme çubuğundaki düğmelerin
/// kenara yaslanması gibi; [hiza]).
///
/// Eskiden kartın sağ üst köşesine BİNDİRİLİYORDU (`kartKosesi`, sabit
/// `ust` payıyla). Bindirme satırla bağ kurmuyordu: çerçevesiz Performans
/// manşetinde dolgu 4 pt olunca simge başlık satırının değil iki satırın
/// ARASINA düşüyor, 44 pt kutunun ortasında durduğu için de rozetin
/// çizgisinden 9 pt içeride kalıyordu (ekran görüntüsü 31 Eki). Satırın
/// içinde olunca hizayı düzen kurar, el ayarı sabit kalmaz.
///
/// 44 pt kutu satırı uzatır; kart bu payı ([satirPayi]) üst dolgusundan
/// ve başlığın altındaki boşluktan düşerek karşılar ki kart yüksekliği ve
/// yazının yeri değişmesin (dolgu yetmezse fark kadar uzar).
///
/// Paylaşmanın ekranın asıl işi olduğu yerler (yıl özeti hikâyesinin son
/// sayfası, yorum notu PDF sayfası, Ayarlar'daki dışa aktarım satırı)
/// etiketli düğmelerini korur; simge yine bu simgedir.
class SandikPaylasDugmesi extends StatelessWidget {
  const SandikPaylasDugmesi({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.hiza = AlignmentDirectional.centerEnd,
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
    this.hiza = AlignmentDirectional.centerEnd,
  }) : onPressed = null;

  final VoidCallback? onPressed;
  final Future<void> Function(Rect? kaynak)? onPaylas;
  final String tooltip;

  /// Simgenin punto boyu. Kutu [SandikTouch.min]; ikisinin farkının yarısı
  /// [gorunmezPay].
  static const double simgeBoyu = 18;

  /// 44 pt dokunma kutusunun simgeden taşan payı (her yanda).
  static const double gorunmezPay = (SandikTouch.min - simgeBoyu) / 2;

  /// [stil]deki tek satırlık başlığın yanına 44 pt kutu konunca satırın
  /// üstte ve altta ne kadar uzadığı. Kart bu kadarı üst dolgusundan ve
  /// başlığın altındaki boşluktan düşer ki yazı yerinden oynamasın, kart
  /// büyümesin. Ölçü yazı ölçeğiyle (Dynamic Type) birlikte yapılır: yazı
  /// 44 pt'yi aşınca satır zaten o boydadır, pay sıfırdır.
  static double satirPayi(BuildContext context, TextStyle? stil) {
    final tp = TextPainter(
      text: TextSpan(text: 'Ağ', style: stil),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final yukseklik = tp.height;
    tp.dispose();
    return math.max(0, (SandikTouch.min - yukseklik) / 2);
  }

  /// [satir]ın SONUNA [dugme]yi koyar; düğme yoksa satır olduğu gibi döner.
  /// Simge satırın dikey ortasında, sağ kenarı satırın sağ kenarında.
  static Widget satirSonunda({required Widget satir, required Widget? dugme}) {
    if (dugme == null) return satir;
    return Row(
      children: [
        Expanded(child: satir),
        dugme,
      ],
    );
  }

  /// Simgenin 44 pt kutu içindeki yeri. Varsayılan: dikeyde orta, yatayda
  /// SONDA — simgenin kenarı kutunun, dolayısıyla içeriğin kenarına yaslanır
  /// (kutunun boşluğu soldaki metne doğru kalır, kenara taşmaz). Birden çok
  /// satıra sarabilen başlığın yanında `topEnd`: ilk satıra hizalı.
  final AlignmentGeometry hiza;

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
          child: Align(
            alignment: hiza,
            child: Icon(Icons.adaptive.share,
                size: simgeBoyu, color: context.c.text58),
          ),
        ),
      ),
    );
  }

  Widget _simge(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(Icons.adaptive.share),
        iconSize: simgeBoyu,
        color: context.c.text58,
        padding: EdgeInsets.zero,
        alignment: hiza,
        constraints: const BoxConstraints.tightFor(
            width: SandikTouch.min, height: SandikTouch.min),
        // Material'ın 48 dp asgari kutusu (`padded`) kutuyu 44'ten 48'e
        // büyütüyordu; `istekli` hâli 44. İkisi aynı ölçüde olsun ki satır
        // payı ([satirPayi]) doğru çıksın; 44 pt HIG eşiği (48 dp Material
        // eşiği bilerek uygulanmıyor, `hig_ortak_bilesen_test`).
        style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );
}
