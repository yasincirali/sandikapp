/// Destek ve direnç bölgeleri — dönem serisinden, SAF hesap (2026-10-17).
///
/// yasin (17 Eki): "AI yorumlama kısmında … destek direnç bölgeleri
/// bilgileri verilmeli." Karar kartı: "Seviye bilgisi" — bölgeyi uygulama
/// fiyat geçmişinden hesaplar, AI yalnız fiyatın bu bölgelere uzaklığını
/// anlatır; al/sat, hedef fiyat, "kırılırsa" senaryosu YOK (kişiye özel
/// yatırım danışmanlığı SPK lisansı ister; bkz. `_shared/portfoy_yorum.ts`).
///
/// ── Yöntem ─────────────────────────────────────────────────────────────────
/// 1) Dönüm noktaları: bir nokta, iki yanındaki [_komsu] nokta içinde en
///    düşükse dip, en yüksekse tepe. Komşu sayısı seri uzunluğuyla büyür
///    (≈ n/25, en az 2): 1H'nin saatlik serisi ile 5Y'nin haftalık serisi
///    aynı "belirgin dönüş" ölçeğinde okunur.
/// 2) Kümeleme: fiyatı birbirine [_kumeAraligi] (yüzde) kadar yakın dönüm
///    noktaları tek bölgedir; bölge = kümenin en düşük–en yüksek fiyatı.
///    Tepe ile dip aynı kümeye girer: dün direnç olan seviye bugün destek
///    olabilir — teknik analizdeki "rol değişimi" bu.
/// 3) Bölge en az [asgariTemas] dönüm noktası taşımalı: tek dokunuş bir
///    seviye değil, bir an.
/// 4) Destek = tamamı güncel fiyatın ALTINDA kalan en yakın bölge; direnç =
///    tamamı ÜSTÜNDE kalan en yakın bölge. Fiyat bir bölgenin İÇİNDEYSE o
///    bölge [icinde] olarak ayrıca döner (ne destek ne direnç: sınanıyor).
///
/// Uydurma sayı yok (CLAUDE.md fiyat kaynağı kuralı 3): her bölge sınırı
/// serideki gerçek bir fiyattır; yetecek dönüm noktası yoksa bölge `null`
/// döner ve hiçbir yüzeyde çizilmez.
library;

import 'dart:math' as math;

/// Bir fiyat bölgesi. [alt] ≤ [ust]; ikisi de serideki gerçek noktalar.
class FiyatBolgesi {
  const FiyatBolgesi({
    required this.alt,
    required this.ust,
    required this.temas,
  });

  final double alt;
  final double ust;

  /// Bölgede kaç dönüm noktası var (kaç kez sınandı).
  final int temas;

  /// Fiyatın bölgeye yüzde uzaklığı: aşağıdaki bölgede [ust]'e, yukarıdaki
  /// bölgede [alt]'a göre. İçindeyse 0.
  double uzaklikPct(double fiyat) {
    if (fiyat > ust) return (fiyat / ust - 1) * 100;
    if (fiyat < alt) return (fiyat / alt - 1) * 100;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is FiyatBolgesi &&
      other.alt == alt &&
      other.ust == ust &&
      other.temas == temas;

  @override
  int get hashCode => Object.hash(alt, ust, temas);

  @override
  String toString() => 'FiyatBolgesi($alt-$ust, temas: $temas)';
}

class DestekDirenc {
  const DestekDirenc({this.destek, this.direnc, this.icinde});

  final FiyatBolgesi? destek;
  final FiyatBolgesi? direnc;

  /// Fiyatın şu an içinde bulunduğu bölge (varsa).
  final FiyatBolgesi? icinde;

  bool get bos => destek == null && direnc == null && icinde == null;

  /// Bölge aramak için gereken en az nokta: daha kısa seride "dönüm
  /// noktası" gürültüden ayırt edilemez.
  static const asgariNokta = 20;

  /// Bir bölgenin sayılması için en az dönüm noktası.
  static const asgariTemas = 2;

  /// Aynı bölgeye giren dönüm noktalarının birbirine en çok yüzde uzaklığı.
  static const _kumeAraligi = 1.5;

  static int _komsu(int n) => math.max(2, n ~/ 25);

  /// [seri]: dönem içindeki fiyatlar, zaman sırasıyla. [fiyat]: ekrandaki
  /// güncel fiyat (serinin son noktasıyla aynı kaynak).
  static DestekDirenc? hesapla(List<double> seri, double fiyat) {
    final f = [for (final p in seri) if (p.isFinite && p > 0) p];
    if (f.length < asgariNokta || !fiyat.isFinite || fiyat <= 0) return null;

    final k = _komsu(f.length);
    final donumler = <double>[];
    for (var i = k; i < f.length - k; i++) {
      var dip = true, tepe = true;
      for (var j = i - k; j <= i + k; j++) {
        if (j == i) continue;
        if (f[j] < f[i]) dip = false;
        if (f[j] > f[i]) tepe = false;
      }
      // Düz bir yayla (tüm komşular eşit) hem dip hem tepe görünür; o bir
      // dönüş değil — sayılmaz.
      if (dip == tepe) continue;
      donumler.add(f[i]);
    }
    if (donumler.length < asgariTemas) return const DestekDirenc();

    donumler.sort();
    final bolgeler = <FiyatBolgesi>[];
    var bas = 0;
    for (var i = 1; i <= donumler.length; i++) {
      final kopar = i == donumler.length ||
          (donumler[i] / donumler[bas] - 1) * 100 > _kumeAraligi;
      if (!kopar) continue;
      final adet = i - bas;
      if (adet >= asgariTemas) {
        bolgeler.add(FiyatBolgesi(
            alt: donumler[bas], ust: donumler[i - 1], temas: adet));
      }
      bas = i;
    }

    FiyatBolgesi? destek, direnc, icinde;
    for (final b in bolgeler) {
      if (b.ust < fiyat) {
        if (destek == null || b.ust > destek.ust) destek = b;
      } else if (b.alt > fiyat) {
        if (direnc == null || b.alt < direnc.alt) direnc = b;
      } else {
        icinde = b;
      }
    }
    return DestekDirenc(destek: destek, direnc: direnc, icinde: icinde);
  }
}
