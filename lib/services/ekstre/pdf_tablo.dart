import 'dart:math' as math;

/// PDF'ten tablo — SAF geometri (eklentiden bağımsız, test edilebilir).
///
/// ## Neden geometri
/// PDF'te "tablo" yoktur; sayfa, koordinatı belli karakterlerdir. Metni
/// düz kopyalamak (eski yapıştırma yolu) satır yapısını ve boş hücreleri
/// kaybeder: "THYAO 100 45,20" ile "THYAO 45,20" (adet boş) ayırt edilemez.
/// Burada tablo karakter kutularından YENİDEN KURULUR:
///   1. karakter → kelime (boşluk ya da yatay boşluk),
///   2. kelime → satır (dikey merkez kümelemesi, yazı yüksekliğine göre),
///   3. satır içinde kelime → hücre (sütun aralığı > yazı yüksekliği),
///   4. hücre → SÜTUN BANDI: çok hücreli satırların x aralıkları sayfa
///      boyunca birleştirilir; her hücre en çok örtüştüğü banda yerleşir.
///      Boş hücre boş kalır — sütun kaymaz.
/// Kurum başına kural yok: aynı algoritma Midas'ın, MKK'nın ve bankaların
/// PDF'lerinde aynı işi yapar; sütunların NE olduğunu `TabloAnlama` çözer.
class PdfKarakter {
  const PdfKarakter(this.c, this.sol, this.sag, this.ust, this.alt);
  final String c;
  final double sol, sag, ust, alt;

  double get yukseklik => (ust - alt).abs();
  double get merkezY => (ust + alt) / 2;
}

class _Kelime {
  _Kelime(this.metin, this.sol, this.sag, this.merkezY, this.yukseklik);
  String metin;
  double sol, sag, merkezY, yukseklik;
}

class _Hucre {
  _Hucre(this.metin, this.sol, this.sag);
  String metin;
  double sol, sag;
}

/// Bir sayfanın karakterleri → satır × sütun.
List<List<String>> sayfadanSatirlar(List<PdfKarakter> karakterler) {
  final kelimeler = _kelimeler(karakterler);
  if (kelimeler.isEmpty) return const [];
  final yukseklikler = kelimeler.map((k) => k.yukseklik).toList()..sort();
  final h = math.max(yukseklikler[yukseklikler.length ~/ 2], 1.0);

  // 2) Satırlar: yukarıdan aşağı (PDF'te y yukarı doğru artar).
  kelimeler.sort((a, b) => b.merkezY.compareTo(a.merkezY));
  final satirlar = <List<_Kelime>>[];
  for (final k in kelimeler) {
    if (satirlar.isNotEmpty) {
      final son = satirlar.last;
      final y = son.map((x) => x.merkezY).reduce((a, b) => a + b) / son.length;
      if ((k.merkezY - y).abs() <= h * 0.5) {
        son.add(k);
        continue;
      }
    }
    satirlar.add([k]);
  }

  // 3) Satır içi hücreler.
  final hucreSatirlari = <List<_Hucre>>[];
  for (final s in satirlar) {
    s.sort((a, b) => a.sol.compareTo(b.sol));
    final hucreler = <_Hucre>[];
    for (final k in s) {
      if (hucreler.isNotEmpty && k.sol - hucreler.last.sag <= h * 0.9) {
        hucreler.last
          ..metin = '${hucreler.last.metin} ${k.metin}'
          ..sag = math.max(hucreler.last.sag, k.sag);
      } else {
        hucreler.add(_Hucre(k.metin, k.sol, k.sag));
      }
    }
    hucreSatirlari.add(hucreler);
  }

  // 4) Sütun bantları — yalnız çok hücreli satırlardan (başlık/dipnot gibi
  // tek parça satırlar sayfa genişliğinde uzanıp bantları yutardı).
  final genislik = [
    for (final s in hucreSatirlari)
      for (final c in s) c.sag,
  ].fold<double>(0, math.max);
  final araliklar = <(double, double)>[
    for (final s in hucreSatirlari)
      if (s.length >= 2)
        for (final c in s)
          if (c.sag - c.sol < genislik * 0.4) (c.sol, c.sag),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final bantlar = <(double, double)>[];
  for (final (sol, sag) in araliklar) {
    if (bantlar.isNotEmpty && sol <= bantlar.last.$2) {
      bantlar.last = (bantlar.last.$1, math.max(bantlar.last.$2, sag));
    } else {
      bantlar.add((sol, sag));
    }
  }
  if (bantlar.length < 2) {
    return [for (final s in hucreSatirlari) [for (final c in s) c.metin]];
  }

  final out = <List<String>>[];
  for (final s in hucreSatirlari) {
    final satir = List<String>.filled(bantlar.length, '');
    for (final c in s) {
      var enIyi = 0;
      var enIyiOrtusme = double.negativeInfinity;
      for (var i = 0; i < bantlar.length; i++) {
        final (bs, bg) = bantlar[i];
        // Örtüşme; hiç örtüşmüyorsa (negatif) mesafe — en yakın bant.
        final o = math.min(c.sag, bg) - math.max(c.sol, bs);
        if (o > enIyiOrtusme) {
          enIyiOrtusme = o;
          enIyi = i;
        }
      }
      satir[enIyi] = satir[enIyi].isEmpty ? c.metin : '${satir[enIyi]} ${c.metin}';
    }
    out.add(satir);
  }
  return out;
}

List<_Kelime> _kelimeler(List<PdfKarakter> karakterler) {
  final out = <_Kelime>[];
  _Kelime? cari;
  PdfKarakter? onceki;
  for (final k in karakterler) {
    final bosluk = k.c.trim().isEmpty;
    final kutusuz = k.sag <= k.sol || k.yukseklik <= 0;
    if (bosluk || kutusuz) {
      cari = null;
      onceki = null;
      continue;
    }
    final kopuk = cari != null &&
        onceki != null &&
        ((k.sol - onceki.sag) > k.yukseklik * 0.35 ||
            (k.merkezY - onceki.merkezY).abs() > k.yukseklik * 0.6 ||
            k.sol < onceki.sol - k.yukseklik);
    if (cari == null || kopuk) {
      cari = _Kelime(k.c, k.sol, k.sag, k.merkezY, k.yukseklik);
      out.add(cari);
    } else {
      cari
        ..metin += k.c
        ..sag = math.max(cari.sag, k.sag)
        ..yukseklik = math.max(cari.yukseklik, k.yukseklik);
    }
    onceki = k;
  }
  return out;
}
