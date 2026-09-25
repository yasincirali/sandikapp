import 'package:flutter/material.dart';

/// Uygulama geneli klavye kuralı (kullanıcı, 2026-09-25): *"çıkan tüm
/// klavyeler dışa tıklandığında kapatılıp alana geri tıklandığında yeniden
/// gözükebilir olmalı."*
///
/// ## Neden kökte tek widget
/// Flutter'ın varsayılanı dokunmatikte dışarı dokunuşu YOK SAYAR (yalnızca
/// fare/trackpad odağı bırakır). Varlık Ekle bunu alan alan `onTapOutside`
/// ile çözmüştü; 17 ekranda giriş alanı var ve her yeni alana aynı satırı
/// yazmak unutulur. `MaterialApp.builder` Navigator'ı sardığı için alt
/// sayfalar ve diyaloglar dahil her yüzey bu widget'ın altındadır.
///
/// ## Neden `unfocus`, `TextInput.hide` değil
/// Yalnızca klavyeyi gizlemek odağı alanda bırakır; kullanıcı alana tekrar
/// dokununca "zaten odaklı" sayılır ve klavye bazı sürümlerde geri gelmez.
/// Odak bırakılınca sonraki dokunuş sıfırdan odak ister — klavye kesin
/// açılır. İkinci yarı ("yeniden gözükmeli") böyle sağlanır.
///
/// ## Neden `GestureDetector` + `translucent`, `Listener` değil
/// `Listener.onPointerDown` her dokunuşta ateşlenir: bir düğmeye basarken
/// de odağı düşürür, odak kaybına bağlı doğrulama (`register_screen`
/// `_emailTouched`) ve düğmenin kendi işi yarışır. Jest tanıyıcı ise
/// yalnızca BAŞKA HİÇ KİMSENİN almadığı dokunuşu kazanır: boşluk, metin,
/// başlık, liste arası. Düğme/hücre kendi dokunuşunu alır, klavye o anda
/// kapanmazsa da sayfa değişir ya da alan yine dışarıda kalır.
/// `translucent`: dokunuş alttaki çocuğa da iletilir, hiçbir şeyi yutmaz.
///
/// Alan içine dokunuş `TextField` tarafından kazanılır; odak düşmez.
class KlavyeKapatici extends StatelessWidget {
  const KlavyeKapatici({super.key, required this.child});

  final Widget child;

  static void kapat() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: kapat,
      child: child,
    );
  }
}
