import 'package:flutter/material.dart';

/// Portföy satırından varlık ekranına geçişte başlığın (THYAO) uçuşu —
/// yol haritası 2.14.
///
/// ## Neden bayrakla (`varlik_hero_gecisi`, varsayılan KAPALI)
/// 2.14 "iki uçtaki boyut farkında bozuk görünür" diye cihazsız
/// yapılmamıştı: satırda `titleMedium`, ekranda `headlineSmall`. Varsayılan
/// `Hero` uçuşu HEDEF metni büyüyen kutuya koyar; kutu küçükken metin
/// kırpılır ya da satır kırar. Bu yüzden uçuşta iki uç da kendi boyunda
/// kalır, birlikte kayarak çapraz solar — metin hiçbir karede kırılmaz, iki
/// uçtaki yazı farklıysa (döviz satırı adı, ekran kodu) yumuşak geçer.
/// (İlk sürüm ölçekliyordu; neden bırakıldı `_ucus`'ta.) Yine de son söz cihazda; bayrak kapalıyken hiçbir
/// `Hero` kurulmaz, geçiş birebir eski.
///
/// "Hareketi azalt" açıkken uçuş yok (`MediaQuery.disableAnimations`).
///
/// ## Etiket
/// [varlikHeroEtiketi] satırın `Position.key`'inden kurulur: aynı rota
/// ağacında iki `Hero` aynı etiketi taşırsa Flutter assert'le düşer. Liste
/// satırları zaten bu anahtarla `ValueKey` alıyor (tekil). Etiket satırdan
/// ekrana AÇIKÇA taşınır; ekran kendi anahtarını uydurmaz — ortak satırda
/// (Ben/Hepsi) açılan pozisyon gösterilenden farklı olabilir.
class VarlikBaslikHero extends StatelessWidget {
  const VarlikBaslikHero(
      {super.key, required this.etiket, required this.child});

  /// `null` → `Hero` kurulmaz (bayrak kapalı ya da çağıran uçuş istemiyor).
  final Object? etiket;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = etiket;
    if (e == null || MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: e,
      flightShuttleBuilder: _ucus,
      child: child,
    );
  }

  static Widget _ucus(
    BuildContext ucusBaglami,
    Animation<double> animasyon,
    HeroFlightDirection yon,
    BuildContext kaynakBaglami,
    BuildContext hedefBaglami,
  ) {
    final kaynak = (kaynakBaglami.widget as Hero).child;
    final hedef = (hedefBaglami.widget as Hero).child;
    // Flutter `animasyon`u iki yönde de İTİLEN rotanınkini verir (push 0→1,
    // pop 1→0), ama `pop`'ta kaynak/hedef yer değiştirir. Opaklığı yöne
    // değil uca bağla: satır = 1−v, ekran = v.
    final satir = yon == HeroFlightDirection.push ? kaynak : hedef;
    final ekran = yon == HeroFlightDirection.push ? hedef : kaynak;
    // İki uç da KENDİ boyunda, sola yaslı çizilir; uçuş kutusu büyürken
    // metin ölçeklenmez. İlk sürüm (2026-10-08) iki ucu `FittedBox` ile her
    // karede kutuya ölçekliyordu: yazı her karede yeni bir boyda
    // rasterleşti ve TestFlight'ta uçuş kare düşürdü (yasin 2026-10-09:
    // "çok düşük fps ile gidiyor"). Şimdi metin tek kez dizilir
    // (`OverflowBox` sabit kısıt verir, kutu boyu değişse de yeniden
    // dizilmez), kare başına yalnız konum ve opaklık değişir; opaklık
    // `FadeTransition` ile katmanda — her karede widget yeniden kurulmaz.
    // Kesim yok: kutu küçükken büyük uç taşar ama kırpılmaz, satır kırmaz.
    Widget uc(Widget w, Animation<double> opaklik) => FadeTransition(
          opacity: opaklik,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: w,
          ),
        );
    // Uçuş katmanında `DefaultTextStyle`/`Material` yok; metin sarı alt
    // çizgiyle çizilmesin.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          uc(satir, ReverseAnimation(animasyon)),
          uc(ekran, animasyon),
        ],
      ),
    );
  }
}

/// Satır ↔ ekran ortak etiketi. Dize değil kayıt: başka bir `Hero`'nun dize
/// etiketiyle çakışamaz.
Object varlikHeroEtiketi(String pozisyonAnahtari) =>
    (tur: 'varlik-baslik', anahtar: pozisyonAnahtari);
