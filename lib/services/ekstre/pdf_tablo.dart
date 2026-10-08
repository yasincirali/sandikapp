import 'dart:math' as math;

import 'ekstre_tablosu.dart';

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
///   4. satır → BLOK (sayfada tablolar arası büyük dikey boşluk),
///   5. blok → TABLO (sonraki sayfada aynı sütunlarla süren blok katılır),
///   6. hücre → SÜTUN BANDI: tablonun çok hücreli satırlarının x aralıkları
///      birleştirilir; her hücre en çok örtüştüğü banda yerleşir. Boş hücre
///      boş kalır — sütun kaymaz.
/// Kurum başına kural yok: aynı algoritma Midas'ın, MKK'nın ve bankaların
/// PDF'lerinde aynı işi yapar; sütunların NE olduğunu `TabloAnlama` çözer.
///
/// ## Bantlar sayfa başına değil, TABLO başına (2026-10-02 / 2026-10-03)
/// Çok sayfalı ekstrede her sayfa aynı sütun düzenini taşır ama son sayfa
/// (toplam satırları, dipnot) ya da bir sütunu tamamen boş geçen bir sayfa
/// farklı sayıda bant üretir; sayfalar alt alta eklenince aynı sütun farklı
/// indekse düşer ve anlama katmanı ikinci sayfadan itibaren adet/fiyatı
/// karıştırır. Bu yüzden bantlar sayfalar boyunca SÜREN tablonun bütününden
/// çıkarılır.
///
/// Ama belge geneli bant (2026-10-02 sürümü) bir sayfada birden çok tablo
/// olan belgeyi çökertti (DenizBank Varlık Ekstresi, 2026-10-03: Vadesiz /
/// Vadeli / Yatırım Fonları ayrı sütun düzeninde, ardından geniş açıklama
/// sütunlu hareket listesi). Farklı tabloların aralıkları zincirleme örtüşüp
/// sayfayı kapladı; "1,647.00 16.9862 TL 27,976.21" tek hücre oldu. Şimdi
/// sayfa dikey boşluktan bloklara bölünür; bir sayfanın İLK tablo bloğu,
/// önceki sayfadaki bir tabloya BİREBİR sütun uyumluysa (her hücre tek bir
/// banda düşer, bir satırda iki hücre aynı banda düşmez) ona katılır.
class PdfKarakter {
  const PdfKarakter(this.c, this.sol, this.sag, this.ust, this.alt);
  final String c;
  final double sol, sag, ust, alt;

  double get yukseklik => (ust - alt).abs();
  double get merkezY => (ust + alt) / 2;
}

class _Kelime {
  _Kelime(this.metin, this.sol, this.sag, this.ust, this.alt);
  String metin;
  double sol, sag, ust, alt;

  double get yukseklik => ust - alt;
  double get merkezY => (ust + alt) / 2;
}

class _Hucre {
  _Hucre(this.metin, this.sol, this.sag);
  String metin;
  double sol, sag;
}

class _Satir {
  _Satir(this.hucreler, this.y);
  final List<_Hucre> hucreler;
  final double y;
}

class _Blok {
  _Blok(this.satirlar, this.aralik, this.sayfa);
  final List<_Satir> satirlar;

  /// Sayfanın medyan satır aralığı (çok satırlı hücre yakınlığı için).
  final double aralik;
  final int sayfa;

  /// Tablo gibi: en az iki çok hücreli satır (başlık/dipnot bloğu değil).
  bool get tabloGibi =>
      satirlar.where((s) => s.hucreler.length >= 2).length >= 2;
}

/// Tek sayfanın karakterleri → satır × sütun.
List<List<String>> sayfadanSatirlar(List<PdfKarakter> karakterler) =>
    sayfalardanSatirlar([karakterler]);

/// Birden çok sayfanın karakterleri → satır × sütun (bütün tablolar art
/// arda). Sayfalar boyunca süren tablonun bantları ortaktır.
List<List<String>> sayfalardanSatirlar(List<List<PdfKarakter>> sayfalar) => [
      for (final t in sayfalardanTablolar(sayfalar)) ...t,
    ];

/// Tek sayfa → tablolar (bloklar).
List<List<List<String>>> sayfadanTablolar(List<PdfKarakter> karakterler) =>
    sayfalardanTablolar([karakterler]);

/// Sayfalar → TABLOLAR (her biri satır × sütun). Başlık/dipnot blokları da
/// kendi "tablosu" olarak döner (tek hücreli satırlar); tablo olup
/// olmadığına çağıran karar verir ([tabloGibiMi]).
List<List<List<String>>> sayfalardanTablolar(List<List<PdfKarakter>> sayfalar) {
  final gruplar = <List<_Blok>>[];
  for (var p = 0; p < sayfalar.length; p++) {
    var ilkTablo = true;
    for (final b in _sayfaBloklari(sayfalar[p], p)) {
      List<_Blok>? hedef;
      if (b.tabloGibi && ilkTablo && p > 0) {
        // Önceki sayfada biten tablolardan, sondan başa, birebir uyumlu ilki.
        for (final g in gruplar.reversed) {
          final son = g.last.sayfa;
          if (son == p) continue; // bu sayfanın başlık blokları
          if (son < p - 1) break;
          if (!g.any((x) => x.tabloGibi)) continue;
          if (_uyumlu(_bantlar([for (final x in g) ...x.satirlar]), b)) {
            hedef = g;
            break;
          }
        }
      }
      if (b.tabloGibi) ilkTablo = false;
      hedef == null ? gruplar.add([b]) : hedef.add(b);
    }
  }
  return [for (final g in gruplar) _grupSatirlari(g)];
}

/// `pdfOku`'nun saf çekirdeği: sayfalar → tablolar + düz metin. Yalnız
/// tablo gibi bloklar tablo olur; düz metin hepsini taşır (belge tarihi
/// "31/05/2026 tarihi itibariyle" ve banka adı tablo dışındaki
/// paragraflardadır).
({List<EkstreTablosu> tablolar, String metin}) pdfSonucu(
  List<List<PdfKarakter>> sayfalar,
) {
  final tablolar = sayfalardanTablolar(sayfalar);
  return (
    tablolar: [
      for (final t in tablolar)
        if (tabloGibiMi(t)) EkstreTablosu(kaynak: 'PDF', satirlar: t),
    ],
    metin: [
      for (final t in tablolar)
        for (final r in t) r.where((x) => x.isNotEmpty).join(' '),
    ].join('\n'),
  );
}

/// Başlık/dipnot değil, tablo: en az iki çok hücreli satır.
bool tabloGibiMi(List<List<String>> tablo) =>
    tablo.where((r) => r.where((x) => x.isNotEmpty).length >= 2).length >= 2;

/// 1–4: karakter → kelime → satır → hücre → blok (tek sayfa).
List<_Blok> _sayfaBloklari(List<PdfKarakter> karakterler, int sayfa) {
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
  final hucreSatirlari = <_Satir>[];
  for (final s in satirlar) {
    final y = s.map((x) => x.merkezY).reduce((a, b) => a + b) / s.length;
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
    hucreSatirlari.add(_Satir(hucreler, y));
  }

  // 4) Bloklar: satır aralığının (medyan) belirgin üstündeki boşlukta böl.
  final araliklar = [
    for (var i = 1; i < hucreSatirlari.length; i++)
      hucreSatirlari[i - 1].y - hucreSatirlari[i].y,
  ];
  final aralik = araliklar.isEmpty
      ? h * 1.5
      : (List.of(araliklar)..sort())[araliklar.length ~/ 2];
  final esik = math.max(aralik * 1.8, h * 2.2);
  final bloklar = <_Blok>[];
  var bas = 0;
  for (var i = 1; i <= hucreSatirlari.length; i++) {
    if (i == hucreSatirlari.length || araliklar[i - 1] > esik) {
      bloklar.add(_Blok(hucreSatirlari.sublist(bas, i), aralik, sayfa));
      bas = i;
    }
  }
  return bloklar;
}

/// Sütun bantları — yalnız çok hücreli satırlardan (başlık/dipnot gibi tek
/// parça satırlar sayfa genişliğinde uzanıp bantları yutardı).
List<(double, double)> _bantlar(List<_Satir> satirlar) {
  final genislik = [
    for (final s in satirlar)
      for (final c in s.hucreler) c.sag,
  ].fold<double>(0, math.max);
  final xAraliklari = <(double, double)>[
    for (final s in satirlar)
      if (s.hucreler.length >= 2)
        for (final c in s.hucreler)
          if (c.sag - c.sol < genislik * 0.4) (c.sol, c.sag),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final bantlar = <(double, double)>[];
  for (final (sol, sag) in xAraliklari) {
    if (bantlar.isNotEmpty && sol <= bantlar.last.$2) {
      bantlar.last = (bantlar.last.$1, math.max(bantlar.last.$2, sag));
    } else {
      bantlar.add((sol, sag));
    }
  }
  return bantlar;
}

/// Blok, bantlara BİREBİR oturuyor mu: çok hücreli her satırda her hücre
/// tam bir bantla örtüşür ve iki hücre aynı banda düşmez. Geniş açıklama
/// hücresi (hareket listesi) birden çok fon sütununa taşar → uyumsuz.
bool _uyumlu(List<(double, double)> bantlar, _Blok b) {
  if (bantlar.length < 2) return false;
  var cokHucreli = 0;
  for (final s in b.satirlar) {
    if (s.hucreler.length < 2) continue;
    cokHucreli++;
    final kullanilan = <int>{};
    for (final c in s.hucreler) {
      final ortusen = [
        for (var i = 0; i < bantlar.length; i++)
          if (math.min(c.sag, bantlar[i].$2) - math.max(c.sol, bantlar[i].$1) >
              0)
            i,
      ];
      if (ortusen.length != 1 || !kullanilan.add(ortusen.single)) return false;
    }
  }
  return cokHucreli > 0;
}

/// 5–6: bir tablonun blokları → bantlara yerleşmiş satırlar; çok satırlı
/// hücreler blok içinde birleştirilir.
List<List<String>> _grupSatirlari(List<_Blok> grup) {
  final bantlar = _bantlar([for (final b in grup) ...b.satirlar]);
  if (bantlar.length < 2) {
    return [
      for (final b in grup)
        for (final s in b.satirlar) [for (final c in s.hucreler) c.metin],
    ];
  }
  final out = <List<String>>[];
  for (final b in grup) {
    final blokBasi = out.length;
    for (var si = 0; si < b.satirlar.length; si++) {
      final s = b.satirlar[si];
      final satir = List<String>.filled(bantlar.length, '');
      for (final c in s.hucreler) {
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
        satir[enIyi] =
            satir[enIyi].isEmpty ? c.metin : '${satir[enIyi]} ${c.metin}';
      }
      // Çok satırlı hücre: uzun fon adı ("İŞ PORTFÖY YARI İLETKEN" /
      // "TEKNOLOJİLERİ DEĞİŞKEN FON") ya da iki satırlık başlık ("Vade" /
      // "Başlangıcı") alt satıra taşar. Taşan satır üst satırdan AZ dolu,
      // içinde rakam yok ve satır aralığı kadar yakın → üst satıra eklenir.
      // Rakam şartı: işlem açıklamasının devamı ("0046 SN: 5752…") ya da
      // yeni bir veri satırı asla yutulmaz. Fonu tanımanın tek yolu adı
      // olan belgelerde kesik ad eşleşmeyi bozardı.
      if (out.length > blokBasi &&
          b.satirlar[si - 1].y - s.y <= b.aralik * 1.3) {
        final ust = out.last;
        int dolu(List<String> r) => r.where((x) => x.isNotEmpty).length;
        final rakamsiz = satir.every((x) => !x.contains(RegExp(r'[0-9]')));
        if (rakamsiz && dolu(satir) < dolu(ust) && dolu(ust) >= 2) {
          for (var i = 0; i < satir.length; i++) {
            if (satir[i].isEmpty) continue;
            ust[i] = ust[i].isEmpty ? satir[i] : '${ust[i]} ${satir[i]}';
          }
          continue;
        }
      }
      out.add(satir);
    }
  }
  return out;
}

/// Karakter → kelime.
///
/// ## Sıkı glif kutusu (2026-10-02, iOS'ta PDF "okuyor ama yanlış")
/// PDFium (`FPDFText_GetCharBox`) yazı tipinin değil GLİFİN kutusunu verir:
/// 9 pt Arial'de rakam 6,5 pt yüksek, virgül 2,2 pt ve 3,5 pt aşağıda,
/// nokta 1 pt, eksi işareti 1 pt. Eski kural eşikleri karakterin KENDİ
/// yüksekliğiyle ölçüyordu (ve dar "1"in sağ boşluğu yatay eşiği aşıyordu);
/// virgül/nokta her seferinde kelimeden koptu, hücre birleştirme araya
/// boşluk koydu: "4.250,00" → "4 .250 ,00". Ölçek artık kelimenin o ana
/// kadarki en yüksek kutusu (yazı boyunun vekili); dikey bağ merkez uzaklığı
/// değil BANT içinde olmak — virgülün merkezi rakam bandının hemen altında,
/// alt satırın rakamı ise çok altında. Gerçek PDFium kutularıyla regresyon:
/// test/fixtures/ekstre_pdf_kutulari.json.
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
    var kopuk = false;
    if (cari != null && onceki != null) {
      final olcek = math.max(cari.yukseklik, k.yukseklik);
      final pay = olcek * 0.25;
      // Ya karakter kelimenin bandında ya kelime karakterin bandında:
      // ikincisi "-4" gibi küçük glifle başlayan kelimeyi tutar.
      final ayniBant =
          (k.merkezY >= cari.alt - pay && k.merkezY <= cari.ust + pay) ||
              (cari.merkezY >= math.min(k.ust, k.alt) - pay &&
                  cari.merkezY <= math.max(k.ust, k.alt) + pay);
      // Yatay eşik geniş: sıkı kutuda "1" ile virgül arası 0,38×yükseklik,
      // gerçek kelime arası 0,47 — ayıramaz. Kelime arasını PDFium zaten
      // boşluk karakteriyle verir (yukarıda kesilir); bu eşik yalnız
      // boşluksuz çizilmiş bitişik hücreler için, hücre eşiği (0,9) altında.
      kopuk = (k.sol - onceki.sag) > olcek * 0.8 ||
          !ayniBant ||
          k.sol < onceki.sol - olcek;
    }
    final ust = math.max(k.ust, k.alt), alt = math.min(k.ust, k.alt);
    if (cari == null || kopuk) {
      cari = _Kelime(k.c, k.sol, k.sag, ust, alt);
      out.add(cari);
    } else {
      cari
        ..metin += k.c
        ..sag = math.max(cari.sag, k.sag)
        ..ust = math.max(cari.ust, ust)
        ..alt = math.min(cari.alt, alt);
    }
    onceki = k;
  }
  return out;
}
