import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Okunabilir içerik sütunu (Ar-Ge 2026-11-07 12:30 #3; HIG "readable
/// content width").
///
/// iPad'de (ve yatay/geniş pencerede) satırlar ekranın bir ucundan öbürüne
/// uzuyordu: etiket solda, tutar 1000 pt ötede. İçerik en fazla
/// [azamiGenislik] genişliğinde ortada durur; zemin (Scaffold, kaydırma
/// alanı, başlık çubuğu) kenara uzanır — kaydırma ve yenileme jesti kenarda
/// da çalışır, çünkü sütun kaydırılabilir alanın İÇİNDEDİR.
///
/// Dar ekranda (iPhone, ≤ [azamiGenislik]) NO-OP: boşluk 0, yerleşim tek
/// piksel değişmez (`hig_ortak_bilesen_test` 390 pt'yi kilitler). Ağaç dar
/// ve genişte AYNI kalır (boşluk yalnız sayı olarak değişir): iPad'i
/// döndürünce ya da bölünmüş ekranda genişlik eşiği geçince altındaki
/// durum (kaydırma konumu, açık kartlar) kaybolmasın.
///
/// Ölçü pencere değil EBEVEYN kısıtıdır (LayoutBuilder / sliver
/// crossAxisExtent): iPad bölünmüş ekranda dar kalan uygulama sütunlanmaz.
///
/// Üç biçim — ekranın kuruluşuna göre:
///   - [SandikIcerikSutunu]: kutu içerik (kaydırma görünümünün çocuğu);
///   - [SandikIcerikSutunu.sliver]: CustomScrollView'da sliver grubu;
///   - [SandikIcerikSutunu.olc]: `ListView(padding:)` gibi dolgu alan
///     yerler için ek yatay boşluk ([kenarBoslugu]).
class SandikIcerikSutunu extends StatelessWidget {
  const SandikIcerikSutunu({super.key, required this.child});

  /// İçeriğin en geniş hâli (pt). ~720: iPad dikeyde (744–834) neredeyse
  /// tam genişlik, yatayda (1024–1366) ortada okunur bir sütun; Apple'ın
  /// okunabilir içerik kılavuzu bu aralığı verir.
  static const double azamiGenislik = 720;

  final Widget child;

  /// [genislik] için iki yana eklenecek boşluk; dar ekranda 0.
  static double kenarBoslugu(double genislik) =>
      math.max(0, (genislik - azamiGenislik) / 2);

  /// Sliver'lı ekranlar için: [slivers] tek grupta (`SliverMainAxisGroup`,
  /// sıra ve anahtarlar aynen), iki yandan aynı boşlukla ortalanır. Başlık
  /// çubuğu (`SliverAppBar`) gruba KONMAZ, kenara uzanır.
  static Widget sliver({Key? key, required List<Widget> slivers}) =>
      _SliverSutun(key: key, slivers: slivers);

  /// Dolgu alan kaydırma görünümleri için (`ListView(padding:)`): [builder]
  /// ebeveyn genişliğinden hesaplanan ek yatay boşluğu alır, dolguya ekler.
  /// Böylece sütun kaydırma alanının İÇİNDE kalır, kenardan kaydırma ve
  /// yenileme jesti çalışır.
  static Widget olc(
          {Key? key,
          required Widget Function(BuildContext context, double kenar)
              builder}) =>
      LayoutBuilder(
        key: key,
        builder: (context, c) => builder(
            context, c.hasBoundedWidth ? kenarBoslugu(c.maxWidth) : 0.0),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final kenar = c.hasBoundedWidth ? kenarBoslugu(c.maxWidth) : 0.0;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: kenar),
        child: child,
      );
    });
  }
}

class _SliverSutun extends StatelessWidget {
  const _SliverSutun({super.key, required this.slivers});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, c) {
      final kenar = SandikIcerikSutunu.kenarBoslugu(c.crossAxisExtent);
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: kenar),
        sliver: SliverMainAxisGroup(slivers: slivers),
      );
    });
  }
}
