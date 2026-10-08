import 'package:flutter/material.dart';

/// Portföy satırından varlık ekranına geçişte başlığın (THYAO) uçuşu —
/// yol haritası 2.14.
///
/// ## Neden bayrakla (`varlik_hero_gecisi`, varsayılan KAPALI)
/// 2.14 "iki uçtaki boyut farkında bozuk görünür" diye cihazsız
/// yapılmamıştı: satırda `titleMedium`, ekranda `headlineSmall`. Varsayılan
/// `Hero` uçuşu HEDEF metni büyüyen kutuya koyar; kutu küçükken metin
/// kırpılır ya da satır kırar. Bu yüzden uçuşta iki uç da `FittedBox` ile
/// kutuya ÖLÇEKLENİR (yeniden dizilmez) ve çapraz solar — metin hiçbir
/// karede kırılmaz, iki uçtaki yazı farklıysa (döviz satırı adı, ekran
/// kodu) yumuşak geçer. Yine de son söz cihazda; bayrak kapalıyken hiçbir
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
    Widget olcekli(Widget w) => FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          child: w,
        );
    // Uçuş katmanında `DefaultTextStyle`/`Material` yok; metin sarı alt
    // çizgiyle çizilmesin.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animasyon,
        builder: (_, __) => Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: 1 - animasyon.value, child: olcekli(satir)),
            Opacity(opacity: animasyon.value, child: olcekli(ekran)),
          ],
        ),
      ),
    );
  }
}

/// Satır ↔ ekran ortak etiketi. Dize değil kayıt: başka bir `Hero`'nun dize
/// etiketiyle çakışamaz.
Object varlikHeroEtiketi(String pozisyonAnahtari) =>
    (tur: 'varlik-baslik', anahtar: pozisyonAnahtari);
